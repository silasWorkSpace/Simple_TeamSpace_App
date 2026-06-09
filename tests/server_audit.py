import socket
import json
import struct
import time

def send_packet(s, p_type, data, p_id="test-req"):
    payload = {
        "v": "1.0",
        "id": p_id,
        "type": p_type,
        "data": data
    }
    json_str = json.dumps(payload).encode('utf-8')
    header = struct.pack('>I', len(json_str))
    s.sendall(header + json_str)

def recv_packet(s, timeout=5):
    s.settimeout(timeout)
    try:
        header = s.recv(4)
        if not header: return None
        length = struct.unpack('>I', header)[0]
        data = bytearray()
        while len(data) < length:
            chunk = s.recv(length - len(data))
            if not chunk: break
            data.extend(chunk)
        return json.loads(data.decode('utf-8'))
    except socket.timeout:
        return None

def run_test():
    server_addr = ("127.0.0.1", 8888)
    ts = int(time.time())
    u1_phone = f"u1_{ts}"
    u2_phone = f"u2_{ts}"
    
    try:
        # User 1
        s1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s1.connect(server_addr)
        print("--- U1 REGISTERING ---")
        send_packet(s1, "AUTH_REGISTER", {"phone": u1_phone, "password": "pw", "display_name": "User 1"})
        u1_resp = recv_packet(s1)
        u1_id = u1_resp['data']['user_id']
        
        # User 2
        s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s2.connect(server_addr)
        print("--- U2 REGISTERING ---")
        send_packet(s2, "AUTH_REGISTER", {"phone": u2_phone, "password": "pw", "display_name": "User 2"})
        u2_resp = recv_packet(s2)
        u2_id = u2_resp['data']['user_id']
        
        # U1 sends message to U2 to create conversation
        print("--- U1 SENDING MESSAGE TO U2 ---")
        send_packet(s1, "CHAT_SEND", {"client_msg_id": "c1", "receiver_id": u2_id, "content": "Hello U2"})
        recv_packet(s1) # CHAT_SENT
        
        # U1 requests conversation list
        print("--- U1 REQUESTING CHAT_LIST ---")
        send_packet(s1, "CHAT_LIST_REQ", {}, p_id="list_test")
        list_resp = recv_packet(s1)
        
        print("--- CHAT_LIST_RESP RECEIVED ---")
        print(json.dumps(list_resp, indent=2))
        
        s1.close()
        s2.close()
                
    except Exception as e:
        print(f"TEST ERROR: {e}")

if __name__ == "__main__":
    run_test()
