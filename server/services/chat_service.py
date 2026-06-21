import uuid
from storage import database

class ChatService:
    """Handles core chat logic: persistence, routing, and history."""

    @staticmethod
    def handle_file_complete(server, token, uploader_id, uploader_display_name,
                             receiver_id, filename, size_bytes, msg_type=None, metadata=None):
        """
        Called by file_service after a binary upload completes.
        Persists a chat message with msg_type='file' (or 'image' or provided) and routes
        the CHAT_RECEIVE packet to the recipient using existing broadcast logic.
        """
        import os
        
        # Use provided msg_type or fallback to extension inference
        if not msg_type:
            ext = os.path.splitext(filename)[1].lower()
            msg_type = 'image' if ext in ('.png', '.jpg', '.jpeg', '.gif', '.webp') else 'file'

        # Use provided metadata or fallback to standard file metadata
        if not metadata:
            metadata = {}
        
        # Always inject standard file info into metadata
        metadata["filename"] = filename
        metadata["size_bytes"] = size_bytes

        client_msg_id = f"file_{token}"

        # Persist the chat message referencing the file token
        server_msg_id, created_at, _ = database.create_message(
            client_msg_id, uploader_id, receiver_id, token,
            msg_type=msg_type,
            metadata=metadata
        )

        payload = {
            "server_msg_id": server_msg_id,
            "sender_id": uploader_id,
            "sender_display_name": uploader_display_name,
            "content": token,
            "msg_type": msg_type,
            "metadata": metadata,
            "created_at": created_at,
            "id": server_msg_id,
            "client_msg_id": client_msg_id,
            "receiver_id": receiver_id,
            "delivered_at": None,
            "read_at": None,
        }

        if receiver_id < 0:
            channel_id = abs(receiver_id)
            channel = database.get_channel(channel_id)
            if channel and channel['is_public']:
                targets = list(server.active_sessions.keys())
            else:
                members = database.get_channel_members(channel_id)
                targets = [m['id'] for m in members]

            # Broadcast to all active sessions in targets (including sender if they are in targets)
            for uid in targets:
                if uid in server.active_sessions:
                    server.broadcast_to_user(uid, "CHAT_RECEIVE", payload)
        else:
            server.broadcast_to_user(receiver_id, "CHAT_RECEIVE", payload)
            if uploader_id != receiver_id:
                server.broadcast_to_user(uploader_id, "CHAT_RECEIVE", payload)

    @staticmethod
    def handle_send(handler, packet):
        """
        Handles CHAT_SEND from client.
        1. Persists to DB (with dedup).
        2. Sends CHAT_SENT to sender.
        3. Routes CHAT_RECEIVE to recipient if online.
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        client_msg_id = p_data.get("client_msg_id")
        receiver_id = p_data.get("receiver_id")
        content = p_data.get("content", "")
        msg_type = p_data.get("msg_type", "text")
        metadata = p_data.get("metadata", None)
        sender_id = handler.user_id

        if client_msg_id is None or receiver_id is None:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing chat fields"}, p_id)
            return

        if receiver_id < 0:
            db_channel_id = abs(receiver_id)
            if not database.is_channel_member(db_channel_id, handler.user_id):
                handler.send_packet("SYS_ERROR", {"code": 403, "message": "Only members can send messages"}, p_id)
                return

        # 1. Persist
        server_msg_id, created_at, is_duplicate = database.create_message(
            client_msg_id, sender_id, receiver_id, content, msg_type=msg_type, metadata=metadata
        )

        # 2. Confirm to sender
        handler.send_packet("CHAT_SENT", {
            "server_msg_id": server_msg_id,
            "client_msg_id": client_msg_id,
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "created_at": created_at
        }, p_id)

        # 3. Route to recipient(s) if online
        if receiver_id < 0:
            channel_id = abs(receiver_id)
            channel = database.get_channel(channel_id)
            if channel and channel['is_public']:
                targets = list(handler.server.active_sessions.keys())
            else:
                members = database.get_channel_members(channel_id)
                targets = [m['id'] for m in members]

            for uid in targets:
                if uid != sender_id and uid in handler.server.active_sessions:
                    handler.server.broadcast_to_user(uid, "CHAT_RECEIVE", {
                        "server_msg_id": server_msg_id,
                        "sender_id": sender_id,
                        "sender_display_name": handler.display_name,
                        "content": content,
                        "msg_type": msg_type,
                        "metadata": metadata,
                        "created_at": created_at,
                        "id": server_msg_id,
                        "client_msg_id": client_msg_id,
                        "receiver_id": receiver_id,
                        "delivered_at": None,
                        "read_at": None
                    })
        else:
            handler.server.broadcast_to_user(receiver_id, "CHAT_RECEIVE", {
                "server_msg_id": server_msg_id,
                "sender_id": sender_id,
                "sender_display_name": handler.display_name,
                "content": content,
                "msg_type": msg_type,
                "metadata": metadata,
                "created_at": created_at,
                "id": server_msg_id,
                "client_msg_id": client_msg_id,
                "receiver_id": receiver_id,
                "delivered_at": None,
                "read_at": None
            })

    @staticmethod
    def handle_received(handler, packet):
        """
        Handles CHAT_RECEIVED from recipient.
        1. Updates delivered_at in DB.
        2. Routes CHAT_DELIVERED to sender's active devices.
        """
        p_data = packet.get("data", {})
        server_msg_id = p_data.get("server_msg_id")

        if not server_msg_id:
            return

        # 1. Update DB
        delivered_at, client_msg_id, sender_id = database.update_delivered_status(server_msg_id)
        
        if delivered_at and sender_id:
            # 2. Notify original sender's devices
            handler.server.broadcast_to_user(sender_id, "CHAT_DELIVERED", {
                "client_msg_id": client_msg_id,
                "server_msg_id": server_msg_id,
                "delivered_at": delivered_at
            })

    @staticmethod
    def handle_history_request(handler, packet):
        """Fetches and returns chat history."""
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        peer_id = p_data.get("peer_id")
        limit = p_data.get("limit", 50)
        before_id = p_data.get("before_id")
        
        if not peer_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing peer_id"}, p_id)
            return

        if peer_id < 0:
            channel_id = abs(peer_id)
            if not database.is_channel_readable(channel_id, handler.user_id):
                handler.send_packet("SYS_ERROR", {"code": 403, "message": "Not a member of this channel"}, p_id)
                return

        history = database.get_chat_history(handler.user_id, peer_id, limit, before_id)
        handler.send_packet("CHAT_HIST_RESP", {"messages": history}, p_id)

    @staticmethod
    def handle_list_request(handler, packet):
        """
        Handles CHAT_LIST_REQ.
        Returns a list of conversation summaries.
        is_online is cross-referenced with active_sessions.
        """
        p_id = packet.get("id")
        user_id = handler.user_id

        # 1. Fetch summaries from DB (No status fields)
        summaries = database.get_conversation_list(user_id)
        
        # 2. Append real-time is_online status
        formatted_convs = []
        for s in summaries:
            peer_id = s['peer_id']
            # Real-time truth from TCPServer.active_sessions
            is_online = peer_id in handler.server.active_sessions
            
            formatted_convs.append({
                "peer_id": peer_id,
                "display_name": s['display_name'],
                "is_online": is_online,
                "last_message": {
                    "id": s['id'],
                    "client_msg_id": s['client_msg_id'],
                    "sender_id": s['sender_id'],
                    "receiver_id": s['receiver_id'],
                    "content": s['content'],
                    "created_at": s['created_at'],
                    "delivered_at": s['delivered_at'],
                    "read_at": s['read_at']
                }
            })

        handler.send_packet("CHAT_LIST_RESP", {"conversations": formatted_convs}, p_id)
