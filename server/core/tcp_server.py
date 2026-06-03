import socket
import threading
import sys
import os

# Thêm đường dẫn gốc để import config không bị lỗi
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import HOST, TCP_PORT
from core.client_handler import ClientHandler

class TCPServer:
    def __init__(self):
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        # Lưu các client đang kết nối: { "phone_number": socket_object }
        self.active_clients = {} 

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