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
    server_addr = ('127.0.0.1', 8888)
    u1_phone = f"task_user1_{int(time.time())}"
    u2_phone = f"task_user2_{int(time.time())}"
    u3_phone = f"task_user3_{int(time.time())}"
    
    print(f"--- STARTING TASK VERIFICATION ---")
    
    try:
        # 1. Setup Users
        def register_user(phone, name):
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect(server_addr)
            send_packet(s, "AUTH_REGISTER", {"phone": phone, "password": "pw", "display_name": name})
            resp = recv_packet(s)
            return s, resp["data"]["user_id"]

        s1, u1_id = register_user(u1_phone, "Creator")
        s2, u2_id = register_user(u2_phone, "Assignee")
        s3, u3_id = register_user(u3_phone, "Other")
        
        print(f"Users registered: U1(Creator)={u1_id}, U2(Assignee)={u2_id}, U3(Other)={u3_id}")

        # 2. TASK_CREATE_REQ
        print("\n[TEST 1] Create Task")
        send_packet(s1, "TASK_CREATE_REQ", {
            "title": "Test Task 1",
            "description": "Description 1",
            "assignee_id": u2_id
        }, p_id="create_1")
        
        resp = recv_packet(s1)
        if resp["type"] == "TASK_CREATE_RESP":
            task1 = resp["data"]["task"]
            task1_id = task1["id"]
            print(f"PASS: Task created with ID {task1_id}")
        else:
            print(f"FAIL: Expected TASK_CREATE_RESP, got {resp['type']}")
            return

        # 3. TASK_LIST_REQ
        print("\n[TEST 2] List Tasks")
        # S1 (Creator) should see it
        send_packet(s1, "TASK_LIST_REQ", {}, p_id="list_1")
        list1 = recv_packet(s1)["data"]["tasks"]
        if any(t["id"] == task1_id for t in list1):
            print("PASS: Creator sees task in list.")
        else:
            print("FAIL: Creator does not see task.")

        # S2 (Assignee) should see it
        send_packet(s2, "TASK_LIST_REQ", {}, p_id="list_2")
        list2 = recv_packet(s2)["data"]["tasks"]
        if any(t["id"] == task1_id for t in list2):
            print("PASS: Assignee sees task in list.")
        else:
            print("FAIL: Assignee does not see task.")

        # S3 (Other) should NOT see it
        send_packet(s3, "TASK_LIST_REQ", {}, p_id="list_3")
        list3 = recv_packet(s3)["data"]["tasks"]
        if any(t["id"] == task1_id for t in list3):
            print("FAIL: Other user sees task.")
        else:
            print("PASS: Other user does not see task.")

        # 4. TASK_UPDATE_REQ
        print("\n[TEST 3] Update Task (Permissions)")
        
        # A. Creator updates Title and Description
        print("Creator updating title/desc...")
        send_packet(s1, "TASK_UPDATE_REQ", {
            "task_id": task1_id,
            "updates": {"title": "Updated Title", "description": "Updated Desc"}
        }, p_id="update_1")
        resp = recv_packet(s1)
        if resp["type"] == "TASK_UPDATE_RESP" and resp["data"]["task"]["title"] == "Updated Title":
            print("PASS: Creator updated title.")
        else:
            print(f"FAIL: Creator update failed. {resp}")

        # B. Assignee updates status (Allowed)
        print("Assignee updating status to DOING...")
        send_packet(s2, "TASK_UPDATE_REQ", {
            "task_id": task1_id,
            "updates": {"status": "DOING"}
        }, p_id="update_2")
        resp = recv_packet(s2)
        if resp["type"] == "TASK_UPDATE_RESP" and resp["data"]["task"]["status"] == "DOING":
            print("PASS: Assignee updated status.")
        else:
            print(f"FAIL: Assignee status update failed. {resp}")

        # C. Assignee updates title (Forbidden)
        print("Assignee trying to update title (should fail)...")
        send_packet(s2, "TASK_UPDATE_REQ", {
            "task_id": task1_id,
            "updates": {"title": "Hacked Title"}
        }, p_id="update_3")
        resp = recv_packet(s2)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 403:
            print(f"PASS: Correctly rejected with 403. Message: {resp['data']['message']}")
        else:
            print(f"FAIL: Incorrect response for forbidden update: {resp}")

        # D. Other user updates task (Forbidden)
        print("Other user trying to update task (should fail)...")
        send_packet(s3, "TASK_UPDATE_REQ", {
            "task_id": task1_id,
            "updates": {"status": "DONE"}
        }, p_id="update_4")
        resp = recv_packet(s3)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 403:
            print("PASS: Correctly rejected with 403.")
        else:
            print(f"FAIL: Incorrect response for unauthorized update: {resp}")

        # 5. Validation
        print("\n[TEST 4] Validation")
        # A. Invalid Status
        print("Creator trying invalid status...")
        send_packet(s1, "TASK_UPDATE_REQ", {
            "task_id": task1_id,
            "updates": {"status": "INVALID"}
        }, p_id="update_invalid_status")
        resp = recv_packet(s1)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 400:
            print("PASS: Invalid status rejected with 400.")
        else:
            print(f"FAIL: Got {resp}")

        # B. Invalid Assignee
        print("Creator trying invalid assignee...")
        send_packet(s1, "TASK_CREATE_REQ", {
            "title": "Bad Task",
            "assignee_id": 999999
        }, p_id="create_invalid_assignee")
        resp = recv_packet(s1)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 400:
            print("PASS: Invalid assignee rejected with 400.")
        else:
            print(f"FAIL: Got {resp}")

        # 6. TASK_DELETE_REQ
        print("\n[TEST 5] Delete Task")
        # A. Assignee tries to delete (Forbidden)
        print("Assignee trying to delete (should fail)...")
        send_packet(s2, "TASK_DELETE_REQ", {"task_id": task1_id}, p_id="delete_1")
        resp = recv_packet(s2)
        if resp["type"] == "SYS_ERROR" and resp["data"]["code"] == 403:
            print("PASS: Assignee delete rejected with 403.")
        else:
            print(f"FAIL: Got {resp}")

        # B. Creator deletes
        print("Creator deleting task...")
        send_packet(s1, "TASK_DELETE_REQ", {"task_id": task1_id}, p_id="delete_2")
        resp = recv_packet(s1)
        if resp["type"] == "TASK_DELETE_RESP" and resp["data"]["task_id"] == task1_id:
            print("PASS: Task deleted.")
        else:
            print(f"FAIL: Got {resp}")

        # 7. Timestamps
        print("\n[TEST 6] Timestamps (completed_at / updated_at)")
        # Create a new task
        send_packet(s1, "TASK_CREATE_REQ", {"title": "Timestamp Task"}, p_id="create_ts")
        task_ts = recv_packet(s1)["data"]["task"]
        ts_id = task_ts["id"]
        
        orig_updated = task_ts["updated_at"]
        print(f"Initial updated_at: {orig_updated}, completed_at: {task_ts['completed_at']}")

        # Wait a bit to ensure CURRENT_TIMESTAMP changes
        time.sleep(1.1)

        # Update to DONE
        print("Updating to DONE...")
        send_packet(s1, "TASK_UPDATE_REQ", {
            "task_id": ts_id,
            "updates": {"status": "DONE"}
        }, p_id="update_done")
        task_done = recv_packet(s1)["data"]["task"]
        
        if task_done["completed_at"] is not None and task_done["updated_at"] > orig_updated:
            print(f"PASS: completed_at populated: {task_done['completed_at']}, updated_at changed: {task_done['updated_at']}")
        else:
            print(f"FAIL: Timestamps not updated correctly. {task_done}")

        # Wait a bit
        time.sleep(1.1)
        mid_updated = task_done["updated_at"]

        # Update back to DOING
        print("Updating back to DOING...")
        send_packet(s1, "TASK_UPDATE_REQ", {
            "task_id": ts_id,
            "updates": {"status": "DOING"}
        }, p_id="update_doing")
        task_doing = recv_packet(s1)["data"]["task"]

        if task_doing["completed_at"] is None and task_doing["updated_at"] > mid_updated:
            print(f"PASS: completed_at cleared, updated_at changed: {task_doing['updated_at']}")
        else:
            print(f"FAIL: Timestamps not updated correctly. {task_doing}")

    except Exception as e:
        print(f"\n[ERROR] {e}")
    finally:
        s1.close()
        s2.close()
        s3.close()
        print("\n--- VERIFICATION COMPLETE ---")

if __name__ == "__main__":
    run_test()
