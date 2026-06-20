import socket
import threading
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import HOST
from core.constants import DATA_PORT

CHUNK_SIZE = 65536  # 64 KB
TOKEN_LENGTH = 36   # UUID4 string length


class DataServer:
    """
    A secondary TCP server that handles ONLY raw binary file transfers.

    Responsibilities:
    - Accepting raw binary connections on DATA_PORT.
    - Reading the 36-byte UUID token header to identify the transfer.
    - Streaming incoming bytes to disk in 64 KB chunks.
    - Notifying file_service.py upon completion so it can update state and route chat.
    - Streaming completed files back out to downloading clients.

    NOT responsible for:
    - JSON protocol parsing.
    - Upload token validation or creation (file_service.py handles that).
    - Chat message routing (chat_service.py handles that).
    - Any signaling logic.
    """

    def __init__(self, on_upload_complete_callback, get_file_path_callback,
                 get_expected_size_callback):
        """
        Args:
            on_upload_complete_callback: Called with (token) when upload finishes.
            get_file_path_callback: Called with (token) to resolve disk path.
            get_expected_size_callback: Called with (token) to get expected byte count.
        """
        self._on_upload_complete = on_upload_complete_callback
        self._get_file_path = get_file_path_callback
        self._get_expected_size = get_expected_size_callback
        self._server_socket = None

    def start(self):
        """Binds the data port and begins accepting binary connections in a daemon thread."""
        self._server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server_socket.bind((HOST, DATA_PORT))
        self._server_socket.listen(20)
        print(f"[DATA SERVER] Listening for binary transfers on {HOST}:{DATA_PORT}...")

        thread = threading.Thread(target=self._accept_loop, daemon=True)
        thread.start()

    def _accept_loop(self):
        """Continuously accepts new binary connections and dispatches each to a handler thread."""
        while True:
            try:
                client_socket, address = self._server_socket.accept()
                print(f"[DATA SERVER] Binary connection from {address}")
                thread = threading.Thread(
                    target=self._handle_connection,
                    args=(client_socket, address),
                    daemon=True
                )
                thread.start()
            except Exception as e:
                print(f"[DATA SERVER] Accept error: {e}")
                break

    def _handle_connection(self, conn, address):
        """
        Handles one binary connection. The protocol is:
          - First byte: 'U' (upload) or 'D' (download)
          - Next TOKEN_LENGTH bytes: the UUID token
          - Remaining bytes (upload only): raw file data
        """
        try:
            # 1. Read direction byte
            direction = self._recv_exact(conn, 1)
            if not direction:
                return
            direction = direction.decode('ascii', errors='ignore')

            # 2. Read UUID token
            token_bytes = self._recv_exact(conn, TOKEN_LENGTH)
            if not token_bytes:
                return
            token = token_bytes.decode('ascii', errors='ignore').strip()

            if direction == 'U':
                self._handle_upload(conn, token)
            elif direction == 'D':
                self._handle_download(conn, token)
            else:
                print(f"[DATA SERVER] Unknown direction byte '{direction}' from {address}")
        except Exception as e:
            print(f"[DATA SERVER] Connection error from {address}: {e}")
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def _handle_upload(self, conn, token):
        """Streams incoming bytes to disk. Verifies byte count before notifying file_service."""
        file_path = self._get_file_path(token)
        print(f"[DATA SERVER] Upload start: token={token}")

        received = 0
        try:
            with open(file_path, 'wb') as f:
                while True:
                    chunk = conn.recv(CHUNK_SIZE)
                    if not chunk:
                        break
                    f.write(chunk)
                    received += len(chunk)
            # File handle is now flushed and closed.
            # Retrieve expected size from file_service for verification.
            expected = self._get_expected_size(token)
            if expected is not None and received != expected:
                print(f"[DATA SERVER] Truncated upload: token={token} "
                      f"expected={expected} received={received}. Discarding.")
                try:
                    import os
                    os.remove(file_path)
                except OSError:
                    pass
                return  # Do NOT notify completion
            print(f"[DATA SERVER] Upload complete: token={token} bytes={received}")
            self._on_upload_complete(token)
        except Exception as e:
            print(f"[DATA SERVER] Upload error for token={token}: {e}")

    def _handle_download(self, conn, token):
        """Streams file bytes from disk to the client."""
        file_path = self._get_file_path(token)
        print(f"[DATA SERVER] Download start: token={token}")

        if not os.path.exists(file_path):
            print(f"[DATA SERVER] File not found for token={token}")
            return

        try:
            with open(file_path, 'rb') as f:
                while True:
                    chunk = f.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    conn.sendall(chunk)
            print(f"[DATA SERVER] Download complete: token={token}")
        except Exception as e:
            print(f"[DATA SERVER] Download error for token={token}: {e}")

    def _recv_exact(self, conn, n):
        """Reads exactly n bytes from the socket."""
        data = bytearray()
        while len(data) < n:
            chunk = conn.recv(n - len(data))
            if not chunk:
                return None
            data.extend(chunk)
        return bytes(data)
