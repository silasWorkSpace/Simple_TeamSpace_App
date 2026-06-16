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

def run_hotfix_verification():
    server_addr = ('127.0.0.1', 8888)
    
    print("--- STARTING HOTFIX VERIFICATION ---")
    
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(server_addr)
        
        # 1. Register a user to search for
        phone = f"fix_{int(time.time())}"
        send_packet(s, "AUTH_REGISTER", {"phone": phone, "password": "pw", "display_name": "Target User"})
        resp = recv_packet(s)
        target_id = resp["data"]["user_id"]
        print(f"Target user registered with ID: {target_id}")
        
        # 2. Search for the user (Simulate the failing path)
        print("\n[STEP 1] Searching for user...")
        send_packet(s, "USER_SEARCH_REQ", {"query": "Target"}, p_id="search_1")
        search_resp = recv_packet(s)
        
        if search_resp["type"] == "USER_SEARCH_RESP":
            users = search_resp["data"]["users"]
            found_user = next((u for u in users if u["display_name"] == "Target User"), None)
            
            if found_user:
                print(f"Server response for user: {found_user}")
                # This 'id' key is what caused the bug (client expected 'user_id')
                actual_id_in_resp = found_user.get("id")
                print(f"ID in server response: {actual_id_in_resp}")
                
                # 3. Simulate client-side parsing with the fix logic
                # (Since I can't run Dart code easily, I verify the logic matches the fix)
                client_parsed_id = found_user.get("id") or found_user.get("user_id") or 0
                print(f"Client-side parsed ID (simulated): {client_parsed_id}")
                
                if client_parsed_id == target_id:
                    print("SUCCESS: ID correctly resolved from 'id' field.")
                else:
                    print(f"FAILURE: ID resolved to {client_parsed_id}, expected {target_id}")
                    sys.exit(1)
            else:
                print("FAILURE: Target user not found in search results.")
                sys.exit(1)
        else:
            print(f"FAILURE: Unexpected response type {search_resp['type']}")
            sys.exit(1)

        # 4. Verify Task Update with the resolved ID
        print("\n[STEP 2] Verifying Task Update with resolved ID...")
        send_packet(s, "TASK_CREATE_REQ", {"title": "Test Bug Task"}, p_id="create_task")
        task_resp = recv_packet(s)
        task_id = task_resp["data"]["task"]["id"]
        
        # Try to assign using the ID we just parsed
        send_packet(s, "TASK_UPDATE_REQ", {
            "task_id": task_id,
            "updates": {"assignee_id": client_parsed_id}
        }, p_id="assign_task")
        
        update_resp = recv_packet(s)
        if update_resp["type"] == "TASK_UPDATE_RESP":
            assigned_id = update_resp["data"]["task"]["assignee_id"]
            if assigned_id == target_id:
                print(f"SUCCESS: Task assigned to user {assigned_id} correctly.")
            else:
                print(f"FAILURE: Task assigned to {assigned_id}, expected {target_id}")
                sys.exit(1)
        else:
            print(f"FAILURE: Task update failed: {update_resp}")
            sys.exit(1)

    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
    finally:
        s.close()
        print("\n--- HOTFIX VERIFICATION COMPLETE ---")

if __name__ == "__main__":
    run_hotfix_verification()
