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
        # Registry of active sessions: { user_id: ClientHandler }
        self.active_sessions = {} 

    def register_session(self, user_id, handler):
        """Registers a user session and notifies active contacts."""
        self.active_sessions[user_id] = handler
        print(f"[SESSION] User {user_id} registered.")
        
        # Broadcast USER_ONLINE to active contacts
        contact_ids = database.get_active_contact_ids(user_id)
        for c_id in contact_ids:
            if c_id in self.active_sessions:
                self.active_sessions[c_id].send_packet("USER_ONLINE", {"user_id": user_id})

    def unregister_session(self, user_id):
        """Unregisters a user session and notifies active contacts."""
        if user_id in self.active_sessions:
            del self.active_sessions[user_id]
            print(f"[SESSION] User {user_id} unregistered.")
            
            # Broadcast USER_OFFLINE to active contacts
            contact_ids = database.get_active_contact_ids(user_id)
            for c_id in contact_ids:
                if c_id in self.active_sessions:
                    self.active_sessions[c_id].send_packet("USER_OFFLINE", {"user_id": user_id})

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