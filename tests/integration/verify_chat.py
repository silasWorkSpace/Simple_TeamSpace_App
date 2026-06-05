import socket
import json
import struct
import time
import uuid

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
    server_addr = ('127.0.0.1', 8888)
    u1_phone = f"user1_{int(time.time())}"
    u2_phone = f"user2_{int(time.time())}"
    
    print(f"--- STARTING CHAT VERIFICATION ---")
    
    try:
        # 1. Setup Users
        s1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s1.connect(server_addr)
        send_packet(s1, "AUTH_REGISTER", {"phone": u1_phone, "password": "pw", "display_name": "User 1"})
        u1_data = recv_packet(s1)["data"]
        u1_id = u1_data["user_id"]
        
        s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s2.connect(server_addr)
        send_packet(s2, "AUTH_REGISTER", {"phone": u2_phone, "password": "pw", "display_name": "User 2"})
        u2_data = recv_packet(s2)["data"]
        u2_id = u2_data["user_id"]
        
        print(f"Users registered: U1={u1_id}, U2={u2_id}")

        # 2. Test Full Lifecycle (CHAT_SEND -> CHAT_SENT -> CHAT_RECEIVE -> CHAT_RECEIVED -> CHAT_DELIVERED)
        print("\n[TEST 1] Full Lifecycle")
        c_msg_id = str(uuid.uuid4())
        send_packet(s1, "CHAT_SEND", {
            "client_msg_id": c_msg_id,
            "receiver_id": u2_id,
            "content": "Hello User 2!"
        }, p_id="send_1")
        
        # A. Sender receives CHAT_SENT
        sent_resp = recv_packet(s1)
        print(f"S1 Received: {sent_resp['type']}")
        if sent_resp["type"] == "CHAT_SENT" and sent_resp["data"]["client_msg_id"] == c_msg_id:
            print("PASS: CHAT_SENT received.")
            s_msg_id = sent_resp["data"]["server_msg_id"]
        else:
            print("FAIL: CHAT_SENT mismatch.")
            return

        # B. Recipient receives CHAT_RECEIVE
        recv_resp = recv_packet(s2)
        print(f"S2 Received: {recv_resp['type']}")
        if recv_resp["type"] == "CHAT_RECEIVE" and recv_resp["data"]["content"] == "Hello User 2!":
            print("PASS: CHAT_RECEIVE received.")
        else:
            print("FAIL: CHAT_RECEIVE mismatch.")
            return

        # C. Recipient sends CHAT_RECEIVED
        send_packet(s2, "CHAT_RECEIVED", {"server_msg_id": s_msg_id})
        
        # D. Sender receives CHAT_DELIVERED
        deliv_resp = recv_packet(s1)
        print(f"S1 Received: {deliv_resp['type']}")
        if deliv_resp["type"] == "CHAT_DELIVERED" and deliv_resp["data"]["server_msg_id"] == s_msg_id:
            print("PASS: CHAT_DELIVERED received.")
        else:
            print("FAIL: CHAT_DELIVERED mismatch.")
            return

        # 3. Test De-duplication
        print("\n[TEST 2] De-duplication")
        dup_c_id = str(uuid.uuid4())
        # First send
        send_packet(s1, "CHAT_SEND", {"client_msg_id": dup_c_id, "receiver_id": u2_id, "content": "Dup test"}, p_id="dup_1")
        resp1 = recv_packet(s1)
        s_msg_id1 = resp1["data"]["server_msg_id"]
        
        # Second send (same client_msg_id)
        print("Sending duplicate client_msg_id...")
        send_packet(s1, "CHAT_SEND", {"client_msg_id": dup_c_id, "receiver_id": u2_id, "content": "Dup test"}, p_id="dup_2")
        resp2 = recv_packet(s1)
        s_msg_id2 = resp2["data"]["server_msg_id"]
        
        if s_msg_id1 == s_msg_id2:
            print(f"PASS: Duplicate correctly handled. Server ID: {s_msg_id1}")
        else:
            print(f"FAIL: Duplicate created new ID: {s_msg_id2}")

        # 4. Test Presence (USER_ONLINE / USER_OFFLINE)
        print("\n[TEST 3] Presence")
        # Since they have exchanged messages, they are "active contacts"
        print("Disconnecting S2...")
        s2.close()
        
        # S1 should receive USER_OFFLINE
        off_resp = recv_packet(s1)
        if off_resp and off_resp["type"] == "USER_OFFLINE" and off_resp["data"]["user_id"] == u2_id:
            print("PASS: USER_OFFLINE received by active contact.")
        else:
            print(f"FAIL: USER_OFFLINE not received. Got: {off_resp}")

        # Reconnect S2
        s2_new = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s2_new.connect(server_addr)
        send_packet(s2_new, "AUTH_LOGIN", {"phone": u2_phone, "password": "pw"})
        recv_packet(s2_new) # Login success
        
        on_resp = recv_packet(s1)
        if on_resp and on_resp["type"] == "USER_ONLINE" and on_resp["data"]["user_id"] == u2_id:
            print("PASS: USER_ONLINE received by active contact.")
        else:
            print(f"FAIL: USER_ONLINE not received. Got: {on_resp}")

    except Exception as e:
        print(f"\n[ERROR] {e}")
    finally:
        s1.close()
        try: s2.close() 
        except: pass
        print("\n--- VERIFICATION COMPLETE ---")

if __name__ == "__main__":
    run_test()
