import socket
import threading
import sys
import os

# Thêm đường dẫn gốc để import config không bị lỗi
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import HOST, TCP_PORT
from core.client_handler import ClientHandler
from storage import database

class TCPServer:
    def __init__(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        # Registry of active sessions: { user_id: Set[ClientHandler] }
        self.active_sessions = {} 
        self.lock = threading.Lock()

    def register_session(self, user_id, handler):
        """Registers a user session and updates presence if first session."""
        should_broadcast_online = False
        with self.lock:
            if user_id not in self.active_sessions:
                self.active_sessions[user_id] = set()
                database.update_online_status(user_id, True)
                should_broadcast_online = True
            
            self.active_sessions[user_id].add(handler)
            print(f"[SESSION] User {user_id} registered (Total handlers: {len(self.active_sessions[user_id])}).")
        
        if should_broadcast_online:
            # Broadcast outside lock to reduce contention
            contact_ids = database.get_active_contact_ids(user_id)
            for c_id in contact_ids:
                self.broadcast_to_user(c_id, "USER_ONLINE", {"user_id": user_id})

    def unregister_session(self, user_id, handler):
        """Unregisters a specific handler instance and updates presence if last session."""
        should_broadcast_offline = False
        with self.lock:
            if user_id in self.active_sessions:
                self.active_sessions[user_id].discard(handler)
                print(f"[SESSION] User {user_id} handler unregistered (Remaining: {len(self.active_sessions[user_id])}).")
                
                if not self.active_sessions[user_id]:
                    del self.active_sessions[user_id]
                    database.update_online_status(user_id, False)
                    should_broadcast_offline = True

        if should_broadcast_offline:
            # Broadcast outside lock to reduce contention
            contact_ids = database.get_active_contact_ids(user_id)
            for c_id in contact_ids:
                self.broadcast_to_user(c_id, "USER_OFFLINE", {"user_id": user_id})

    def broadcast_to_user(self, user_id, packet_type, data, exclude_handler=None):
        """Broadcasts a packet to all handlers of a user, optionally excluding one."""
        # Note: Accessing self.active_sessions here is safe without a lock 
        # because dict.get() is atomic and we iterate over a list copy.
        handlers = self.active_sessions.get(user_id, set())
        for h in list(handlers): 
            if h != exclude_handler:
                try:
                    h.send_packet(packet_type, data)
                except Exception as e:
                    print(f"[BROADCAST ERROR] User {user_id}: {e}")

    def start(self):
        try:
            self.server_socket.bind((HOST, TCP_PORT))
            self.server_socket.listen(10)
            print(f"[SERVER] Đang lắng nghe TCP tại {HOST}:{TCP_PORT}...")
            
            while True:
                client_socket, client_address = self.server_socket.accept()
                print(f"[KẾT NỐI] Client {client_address} đã vào mạng.")
                
                # Ném kết nối sang ClientHandler xử lý độc lập
                handler = ClientHandler(client_socket, client_address, self)
                thread = threading.Thread(target=handler.run)
                thread.daemon = True
                thread.start()
                
        except Exception as e:
            print(f"[LỖI SERVER] {e}")
        finally:
            self.server_socket.close()