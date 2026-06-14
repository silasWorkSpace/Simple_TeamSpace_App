import json
import struct
import socket
from services.auth_service import AuthService
from services.chat_service import ChatService
from services.task_service import TaskService
from services.user_service import UserService
from storage import database

class ClientHandler:
    """Handles individual client connections and protocol framing."""
    
    def __init__(self, client_socket, address, server):
        self.client_socket = client_socket
        self.address = address
        self.server = server
        self.user_id = None
        self.display_name = None
        self.is_running = True

    def run(self):
        print(f"[HANDLER] Started for {self.address}")
        try:
            while self.is_running:
                # 1. Read 4-byte length prefix
                header = self._recv_all(4)
                if not header:
                    break
                
                length = struct.unpack('>I', header)[0]
                
                # 2. Read JSON payload
                payload_raw = self._recv_all(length)
                if not payload_raw:
                    break
                
                payload_str = payload_raw.decode('utf-8')
                packet = json.loads(payload_str)
                
                self._handle_packet(packet)
                
        except Exception as e:
            print(f"[LỖI HANDLER] {self.address}: {e}")
        finally:
            self._cleanup()

    def _recv_all(self, n):
        """Helper to receive exactly n bytes."""
        data = bytearray()
        while len(data) < n:
            try:
                packet = self.client_socket.recv(n - len(data))
                if not packet:
                    return None
                data.extend(packet)
            except socket.error:
                return None
        return data

    def send_packet(self, packet_type, data, packet_id="system"):
        """Sends a JSON packet with a 4-byte length prefix."""
        payload = {
            "v": "1.0",
            "id": packet_id,
            "type": packet_type,
            "data": data
        }
        json_str = json.dumps(payload).encode('utf-8')
        header = struct.pack('>I', len(json_str))
        self.client_socket.sendall(header + json_str)

    def _handle_packet(self, packet):
        """Processes incoming packets based on type."""
        p_type = packet.get("type")
        p_id = packet.get("id")
        p_data = packet.get("data", {})

        print(f"[PACKET] Received {p_type} from {self.address}")

        if p_type == "SYS_PING":
            self.send_packet("SYS_PONG", {}, p_id)
        
        elif p_type == "AUTH_REGISTER":
            phone = p_data.get("phone")
            password = p_data.get("password")
            name = p_data.get("display_name")
            
            if not all([phone, password, name]):
                self.send_packet("SYS_ERROR", {"code": 400, "message": "Missing fields"}, p_id)
                return

            success, result = AuthService.register(phone, password, name)
            if success:
                self.user_id = result["user_id"]
                self.display_name = result["display_name"]
                self.server.register_session(self.user_id, self)
                self.send_packet("AUTH_SUCCESS", result, p_id)
            else:
                msg = "Phone already exists" if result == 400 else "Server error"
                self.send_packet("SYS_ERROR", {"code": result, "message": msg}, p_id)

        elif p_type == "AUTH_LOGIN":
            phone = p_data.get("phone")
            password = p_data.get("password")
            
            if not all([phone, password]):
                self.send_packet("SYS_ERROR", {"code": 400, "message": "Missing fields"}, p_id)
                return

            success, result = AuthService.login(phone, password)
            if success:
                self.user_id = result["user_id"]
                self.display_name = result["display_name"]
                self.server.register_session(self.user_id, self)
                self.send_packet("AUTH_SUCCESS", result, p_id)
            else:
                self.send_packet("SYS_ERROR", {"code": result, "message": "Invalid credentials"}, p_id)
        
        elif p_type == "CHAT_SEND":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            ChatService.handle_send(self, packet)

        elif p_type == "CHAT_RECEIVED":
            if not self.user_id: return
            ChatService.handle_received(self, packet)

        elif p_type == "CHAT_HIST_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            ChatService.handle_history_request(self, packet)

        elif p_type == "CHAT_LIST_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            ChatService.handle_list_request(self, packet)

        elif p_type == "TASK_CREATE_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            TaskService.handle_create(self, packet)

        elif p_type == "TASK_LIST_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            TaskService.handle_list(self, packet)

        elif p_type == "TASK_UPDATE_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            TaskService.handle_update(self, packet)

        elif p_type == "TASK_DELETE_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            TaskService.handle_delete(self, packet)

        elif p_type == "USER_SEARCH_REQ":
            if not self.user_id:
                self.send_packet("SYS_ERROR", {"code": 401, "message": "Unauthorized"}, p_id)
                return
            UserService.handle_search(self, packet)

        else:
            print(f"[WARNING] Unhandled packet type: {p_type}")

    def _cleanup(self):
        """Closes the socket and cleans up resources."""
        self.is_running = False
        if self.user_id:
            self.server.unregister_session(self.user_id)
            database.update_online_status(self.user_id, False)
        
        try:
            self.client_socket.close()
        except:
            pass
        print(f"[KẾT THÚC] Client {self.address} đã ngắt kết nối.")
