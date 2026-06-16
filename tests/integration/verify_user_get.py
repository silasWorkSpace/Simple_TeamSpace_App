import socket
import json
import struct
import time
import sys

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

def run_user_get_verification():
    server_addr = ('127.0.0.1', 8888)
    
    print("--- STARTING USER_GET_REQ VERIFICATION ---")
    
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(server_addr)
        
        # 1. Register two users to resolve
        print("[STEP 1] Registering users...")
        ts = int(time.time())
        send_packet(s, "AUTH_REGISTER", {"phone": f"user_a_{ts}", "password": "pw", "display_name": "Alice"})
        u1_id = recv_packet(s)["data"]["user_id"]
        
        send_packet(s, "AUTH_REGISTER", {"phone": f"user_b_{ts}", "password": "pw", "display_name": "Bob"})
        u2_id = recv_packet(s)["data"]["user_id"]
        
        print(f"Registered: Alice (ID: {u1_id}), Bob (ID: {u2_id})")
        
        # 2. Test USER_GET_REQ
        print("\n[STEP 2] Batch resolving user IDs...")
        req_id = f"batch_res_{ts}"
        send_packet(s, "USER_GET_REQ", {"user_ids": [u1_id, u2_id]}, p_id=req_id)
        resp = recv_packet(s)
        
        if resp["type"] == "USER_GET_RESP" and resp["id"] == req_id:
            users = resp["data"]["users"]
            print(f"Server returned: {users}")
            
            # Verify no phone numbers
            for u in users:
                if "phone" in u:
                    print(f"FAILURE: Phone number leaked for user {u['id']}!")
                    sys.exit(1)
            
            # Verify names
            u1_data = next((u for u in users if u["id"] == u1_id), None)
            u2_data = next((u for u in users if u["id"] == u2_id), None)
            
            if u1_data and u1_data["display_name"] == "Alice" and u2_data and u2_data["display_name"] == "Bob":
                print("SUCCESS: IDs correctly resolved to names without phone numbers.")
            else:
                print(f"FAILURE: Data mismatch. U1: {u1_data}, U2: {u2_data}")
                sys.exit(1)
        else:
            print(f"FAILURE: Unexpected response: {resp}")
            sys.exit(1)

        # 3. Test Invalid Input (non-list)
        print("\n[STEP 3] Testing invalid input (non-list)...")
        send_packet(s, "USER_GET_REQ", {"user_ids": "not-a-list"}, p_id="bad_req_1")
        resp = recv_packet(s)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 400:
            print("SUCCESS: Non-list input correctly rejected with 400.")
        else:
            print(f"FAILURE: Expected 400 error, got: {resp}")
            sys.exit(1)

        # 4. Test Mixed Types (Should now return 400, not filter)
        print("\n[STEP 4] Testing mixed-type IDs [ID1, 'abc', None]...")
        send_packet(s, "USER_GET_REQ", {"user_ids": [u1_id, "abc", None]}, p_id="bad_req_2")
        resp = recv_packet(s)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 400:
            print("SUCCESS: Mixed types correctly rejected with 400.")
        else:
            print(f"FAILURE: Expected 400 error for mixed types, got: {resp}")
            sys.exit(1)

    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
    finally:
        s.close()
        print("\n--- USER_GET_REQ VERIFICATION COMPLETE ---")

if __name__ == "__main__":
    run_user_get_verification()
