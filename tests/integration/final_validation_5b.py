import socket
import json
import struct
import time
import sys
import os

def send_packet(sock, p_type, data):
    payload = {"v": "1.0", "id": "test", "type": p_type, "data": data}
    json_str = json.dumps(payload).encode('utf-8')
    header = struct.pack('>I', len(json_str))
    sock.sendall(header + json_str)

def recv_packet(sock, timeout=2.0):
    sock.settimeout(timeout)
    try:
        header = sock.recv(4)
        if not header: return None
        length = struct.unpack('>I', header)[0]
        data = bytearray()
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk: break
            data.extend(chunk)
        return json.loads(data.decode('utf-8'))
    except socket.timeout:
        return None

def test_phase_5b_sync():
    print("\n[TEST 5B] Starting Multi-Client Task Sync Test...")
    HOST, PORT = '127.0.0.1', 8888
    
    # 1. Setup Users
    suffix = int(time.time())
    uA_phone, uB_phone, uC_phone = f"ua_{suffix}", f"ub_{suffix}", f"uc_{suffix}"
    password = "password"

    def register(phone, name):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect((HOST, PORT))
        send_packet(s, "AUTH_REGISTER", {"phone": phone, "password": password, "display_name": name})
        resp = recv_packet(s)
        uid = resp['data']['user_id']
        s.close()
        return uid

    uA_id = register(uA_phone, "User A")
    uB_id = register(uB_phone, "User B")
    uC_id = register(uC_phone, "User C")
    print(f"[Setup] Registered Users: A({uA_id}), B({uB_id}), C({uC_id})")

    # 2. Connect Clients
    # User A: 2 Devices
    a_d1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    a_d1.connect((HOST, PORT))
    send_packet(a_d1, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(a_d1)

    a_d2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    a_d2.connect((HOST, PORT))
    send_packet(a_d2, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(a_d2)

    # User B: 1 Device
    b_d1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    b_d1.connect((HOST, PORT))
    send_packet(b_d1, "AUTH_LOGIN", {"phone": uB_phone, "password": password})
    recv_packet(b_d1)

    # User C: 1 Device
    c_d1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    c_d1.connect((HOST, PORT))
    send_packet(c_d1, "AUTH_LOGIN", {"phone": uC_phone, "password": password})
    recv_packet(c_d1)

    print("[Clients] All clients logged in and ready.")

    # --- Scenario 1: Multi-Device Self-Sync ---
    print("\n[Scenario 1] User A (D1) creates a task...")
    send_packet(a_d1, "TASK_CREATE_REQ", {"title": "Task 1", "description": "Desc 1"})
    
    resp_a1 = recv_packet(a_d1)
    event_a2 = recv_packet(a_d2)
    
    assert resp_a1['type'] == 'TASK_CREATE_RESP', f"Expected RESP, got {resp_a1['type']}"
    assert event_a2['type'] == 'TASK_CREATED_EVENT', f"Expected EVENT, got {event_a2['type']}"
    task_id = resp_a1['data']['task']['id']
    print(f"SUCCESS: A(D1) got RESP, A(D2) got EVENT for Task {task_id}")

    # --- Scenario 2: Peer Assignment ---
    print("\n[Scenario 2] User A (D1) assigns Task 1 to User B...")
    send_packet(a_d1, "TASK_UPDATE_REQ", {"task_id": task_id, "updates": {"assignee_id": uB_id}})
    
    resp_a1 = recv_packet(a_d1)
    event_a2 = recv_packet(a_d2)
    event_b1 = recv_packet(b_d1)
    
    assert resp_a1['type'] == 'TASK_UPDATE_RESP'
    assert event_a2['type'] == 'TASK_UPDATED_EVENT'
    assert event_b1['type'] == 'TASK_CREATED_EVENT', f"B should get CREATED_EVENT (visibility entry), got {event_b1['type']}"
    print(f"SUCCESS: B(D1) received CREATED_EVENT for reassignment")

    # --- Scenario 3: Collaborative Status Update ---
    print("\n[Scenario 3] User B moves Task 1 to DOING...")
    send_packet(b_d1, "TASK_UPDATE_REQ", {"task_id": task_id, "updates": {"status": "DOING"}})
    
    resp_b1 = recv_packet(b_d1)
    event_a1 = recv_packet(a_d1)
    event_a2 = recv_packet(a_d2)
    
    assert resp_b1['type'] == 'TASK_UPDATE_RESP'
    assert event_a1['type'] == 'TASK_UPDATED_EVENT'
    assert event_a2['type'] == 'TASK_UPDATED_EVENT'
    assert event_a1['data']['task']['status'] == 'DOING'
    print(f"SUCCESS: All User A devices synced status change from B")

    # --- Scenario 4: Complex Reassignment (B -> C) ---
    print("\n[Scenario 4] User A (D1) reassigns B -> C...")
    send_packet(a_d1, "TASK_UPDATE_REQ", {"task_id": task_id, "updates": {"assignee_id": uC_id}})
    
    resp_a1 = recv_packet(a_d1)
    event_a2 = recv_packet(a_d2)
    event_b1 = recv_packet(b_d1)
    event_c1 = recv_packet(c_d1)
    
    assert resp_a1['type'] == 'TASK_UPDATE_RESP'
    assert event_a2['type'] == 'TASK_UPDATED_EVENT'
    assert event_b1['type'] == 'TASK_DELETED_EVENT', f"B should get DELETED_EVENT (visibility exit), got {event_b1['type']}"
    assert event_c1['type'] == 'TASK_CREATED_EVENT', f"C should get CREATED_EVENT (visibility entry), got {event_c1['type']}"
    print(f"SUCCESS: Reassignment visibility logic verified (B exit, C entry)")

    # --- Scenario 5: Cleanup (Delete) ---
    print("\n[Scenario 5] User A (D2) deletes the task...")
    send_packet(a_d2, "TASK_DELETE_REQ", {"task_id": task_id})
    
    resp_a2 = recv_packet(a_d2)
    event_a1 = recv_packet(a_d1)
    event_c1 = recv_packet(c_d1)
    
    assert resp_a2['type'] == 'TASK_DELETE_RESP'
    assert event_a1['type'] == 'TASK_DELETED_EVENT'
    assert event_c1['type'] == 'TASK_DELETED_EVENT'
    print(f"SUCCESS: All parties notified of deletion")

    # Cleanup connections
    for s in [a_d1, a_d2, b_d1, c_d1]:
        s.close()
    print("\n[TEST 5B] All Scenarios Passed Successfully!")

if __name__ == "__main__":
    test_phase_5b_sync()
