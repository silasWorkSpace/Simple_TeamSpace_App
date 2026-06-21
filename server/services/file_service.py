import os
import uuid
import threading
import time
from storage import database
from core.constants import UPLOAD_TOKEN_EXPIRY_SECONDS, DATA_PORT

# Ensure the file storage directory exists
FILES_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'storage', 'files')
os.makedirs(FILES_DIR, exist_ok=True)

CHUNK_SIZE = 65536  # 64 KB chunks


class FileService:
    """
    Manages upload token lifecycle, metadata persistence, and completion signalling.

    Responsibilities:
    - Issuing and expiring upload tokens.
    - Reserving DB records before binary transfer begins.
    - Completing DB records after binary transfer finishes.
    - Triggering chat delivery via a callback upon completion.
    - Handling download request validation.
    - Running startup orphan cleanup.

    NOT responsible for:
    - Reading/writing binary data (data_server.py handles that).
    - Routing chat messages (chat_service.py handles that).
    """

    # Thread-safe dict: token -> { uploader_id, filename, size_bytes, receiver_id, expiry }
    _pending: dict = {}
    _lock = threading.Lock()

    # Callback set by main.py: on_upload_complete(token, uploader_id, receiver_id, filename, size_bytes)
    _on_complete_callback = None

    @classmethod
    def set_completion_callback(cls, callback):
        """Registers the function to call when an upload finishes."""
        cls._on_complete_callback = callback

    @classmethod
    def startup_cleanup(cls):
        """
        Runs at server boot. Removes orphaned DB rows and physical files left
        by previous server sessions (pending uploads older than 1 hour).
        """
        orphans = database.cleanup_orphaned_files()
        for orphan in orphans:
            file_path = os.path.join(FILES_DIR, orphan['id'])
            if os.path.exists(file_path):
                try:
                    os.remove(file_path)
                    print(f"[FILE] Cleaned up orphan file: {orphan['id']} ({orphan['filename']})")
                except OSError as e:
                    print(f"[FILE] Failed to remove orphan {orphan['id']}: {e}")
        if orphans:
            print(f"[FILE] Cleaned {len(orphans)} orphaned record(s) from the database.")
        else:
            print("[FILE] No orphaned files found.")

    @classmethod
    def handle_upload_request(cls, handler, packet):
        """
        Handles FILE_UPLOAD_REQ from the client.
        1. Validates fields.
        2. Reserves a DB record with status='pending'.
        3. Stores the token in the in-memory pending dict with an expiry.
        4. Replies with FILE_UPLOAD_RESP containing the token and data port.
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})

        filename = p_data.get("filename")
        size_bytes = p_data.get("size_bytes")
        receiver_id = p_data.get("receiver_id")
        msg_type = p_data.get("msg_type") # Optional
        metadata = p_data.get("metadata") # Optional

        if not all([filename, size_bytes, receiver_id is not None]):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing file upload fields"}, p_id)
            return

        token = str(uuid.uuid4())
        uploader_id = handler.user_id

        # 1. Reserve DB row BEFORE binary transfer begins
        database.create_file_record(token, uploader_id, filename, size_bytes)

        # 2. Store in-memory token with expiry timestamp
        expiry = time.time() + UPLOAD_TOKEN_EXPIRY_SECONDS
        with cls._lock:
            cls._pending[token] = {
                "uploader_id": uploader_id,
                "uploader_display_name": handler.display_name,
                "filename": filename,
                "size_bytes": size_bytes,
                "receiver_id": receiver_id,
                "msg_type": msg_type,
                "metadata": metadata,
                "expiry": expiry,
            }

        # 3. Start expiry watcher in background
        threading.Thread(target=cls._expiry_watcher, args=(token,), daemon=True).start()

        # 4. Reply to client with token and data port
        handler.send_packet("FILE_UPLOAD_RESP", {
            "token": token,
            "data_port": DATA_PORT,
        }, p_id)
        print(f"[FILE] Upload token issued: {token} | file={filename} | size={size_bytes}")

    @classmethod
    def handle_download_request(cls, handler, packet):
        """
        Handles FILE_DOWNLOAD_REQ.
        Validates the token, confirms the file is completed, verifies the requester
        is a participant in the associated chat message, then replies with
        FILE_DOWNLOAD_RESP so the client can connect to the data port.
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        token = p_data.get("token")

        if not token:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing token"}, p_id)
            return

        record = database.get_file_record(token)
        if not record:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "File not found"}, p_id)
            return

        if record['status'] != 'completed':
            handler.send_packet("SYS_ERROR", {"code": 409, "message": "File upload not complete"}, p_id)
            return

        # Authorization: verify requester is sender or recipient of the associated message
        requester_id = handler.user_id
        msg = database.get_message_by_file_token(token)
        if msg:
            sender_id = msg['sender_id']
            receiver_id = msg['receiver_id']
            is_channel = receiver_id < 0
            if is_channel:
                channel_id = abs(receiver_id)
                if not database.is_channel_member(channel_id, requester_id):
                    handler.send_packet("SYS_ERROR", {"code": 403, "message": "Access denied"}, p_id)
                    return
            elif requester_id != sender_id and requester_id != receiver_id:
                handler.send_packet("SYS_ERROR", {"code": 403, "message": "Access denied"}, p_id)
                return

        handler.send_packet("FILE_DOWNLOAD_RESP", {
            "token": token,
            "filename": record['filename'],
            "size_bytes": record['size_bytes'],
            "data_port": DATA_PORT,
        }, p_id)
        print(f"[FILE] Download token authorized: {token} | file={record['filename']}")

    @classmethod
    def on_binary_upload_complete(cls, token):
        """
        Called by data_server.py after the binary stream finishes writing to disk.
        1. Validates token is still valid (not expired).
        2. Marks DB record as completed.
        3. Fires the completion callback to trigger chat routing.
        """
        with cls._lock:
            meta = cls._pending.pop(token, None)

        if meta is None:
            print(f"[FILE] Received completion for unknown/expired token: {token}")
            # Still mark DB row if data arrived marginally late
            database.complete_file_record(token)
            return

        # Mark as completed in DB
        database.complete_file_record(token)
        print(f"[FILE] Upload completed: {token} | file={meta['filename']}")

        # Delegate chat routing to chat_service via callback
        if cls._on_complete_callback:
            cls._on_complete_callback(
                token=token,
                uploader_id=meta['uploader_id'],
                uploader_display_name=meta['uploader_display_name'],
                receiver_id=meta['receiver_id'],
                filename=meta['filename'],
                size_bytes=meta['size_bytes'],
                msg_type=meta.get('msg_type'),
                metadata=meta.get('metadata'),
            )

    @classmethod
    def get_file_path(cls, token):
        """Returns the absolute path on disk for a given token."""
        return os.path.join(FILES_DIR, token)

    @classmethod
    def get_expected_size(cls, token):
        """
        Returns the declared size_bytes for a pending upload token,
        or None if the token has already been consumed/expired.
        """
        with cls._lock:
            meta = cls._pending.get(token)
            return meta['size_bytes'] if meta else None

    @classmethod
    def _expiry_watcher(cls, token):
        """
        Background thread that expires an upload token after UPLOAD_TOKEN_EXPIRY_SECONDS.
        If the token still exists in _pending when the timer fires, no binary
        connection was ever made and we clean up the DB row and any partial file.
        """
        time.sleep(UPLOAD_TOKEN_EXPIRY_SECONDS)
        with cls._lock:
            meta = cls._pending.pop(token, None)

        if meta is not None:
            print(f"[FILE] Token expired (no upload received): {token} | file={meta['filename']}")
            # The DB row was reserved pending; remove it
            database.cleanup_orphaned_files()
            # Remove any partial bytes that may have been flushed to disk
            file_path = os.path.join(FILES_DIR, token)
            if os.path.exists(file_path):
                try:
                    os.remove(file_path)
                except OSError:
                    pass
