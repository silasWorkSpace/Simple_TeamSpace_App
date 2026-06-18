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

def test_comment_sync():
    print("\n[TEST 6A] Starting Comment Sync Integration Test...")
    HOST, PORT = '127.0.0.1', 8888
    
    # 1. Setup Users
    suffix = int(time.time())
    uA_phone, uB_phone, uC_phone = f"ca_{suffix}", f"cb_{suffix}", f"cc_{suffix}"
    password = "password"

    def register(phone, name):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect((HOST, PORT))
        send_packet(s, "AUTH_REGISTER", {"phone": phone, "password": password, "display_name": name})
        resp = recv_packet(s)
        uid = resp['data']['user_id']
        s.close()
        return uid

    uA_id = register(uA_phone, "Creator")
    uB_id = register(uB_phone, "Assignee")
    uC_id = register(uC_phone, "Observer")

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

    # Create Task
    send_packet(a_d1, "TASK_CREATE_REQ", {"title": "Comment Task", "assignee_id": uB_id})
    resp = recv_packet(a_d1)
    task_id = resp['data']['task']['id']
    recv_packet(a_d2) # Clear EVENT
    recv_packet(b_d1) # Clear EVENT

    # --- Scenario F: Multi-Device Comment Sync ---
    print("\n[Scenario F] Multi-Device Comment Sync")
    send_packet(a_d1, "COMMENT_SEND_REQ", {"task_id": task_id, "content": "First comment!"})
    
    resp_a1 = recv_packet(a_d1)
    event_a2 = recv_packet(a_d2)
    event_b1 = recv_packet(b_d1)
    
    assert resp_a1['type'] == 'COMMENT_SEND_RESP'
    assert event_a2['type'] == 'COMMENT_CREATED_EVENT'
    assert event_b1['type'] == 'COMMENT_CREATED_EVENT'
    
    c_id_1 = resp_a1['data']['comment']['id']
    c_id_2 = event_a2['data']['comment']['id']
    assert c_id_1 == c_id_2, "Comment IDs must match across RESP and EVENT"
    print(f"SUCCESS: A(D1) received RESP, A(D2) and B(D1) received EVENT for Comment {c_id_1}")

    # --- Scenario: Visibility Boundary ---
    print("\n[Scenario Visibility] Non-participant attempts to fetch comments")
    send_packet(c_d1, "COMMENT_LIST_REQ", {"task_id": task_id})
    resp_c1 = recv_packet(c_d1)
    
    assert resp_c1['type'] == 'SYS_ERROR'
    assert resp_c1['data']['code'] == 403
    print("SUCCESS: Observer C correctly denied access to comments")

    # --- Scenario: Reassignment Access ---
    print("\n[Scenario Reassignment] Reassigning B -> C, checking access")
    send_packet(a_d1, "TASK_UPDATE_REQ", {"task_id": task_id, "updates": {"assignee_id": uC_id}})
    recv_packet(a_d1) # RESP
    recv_packet(a_d2) # EVENT
    recv_packet(b_d1) # EVENT (DELETED)
    recv_packet(c_d1) # EVENT (CREATED)
    
    # B tries to list comments (should fail)
    send_packet(b_d1, "COMMENT_LIST_REQ", {"task_id": task_id})
    resp_b1 = recv_packet(b_d1)
    assert resp_b1['type'] == 'SYS_ERROR' and resp_b1['data']['code'] == 403
    print("SUCCESS: Former assignee B denied access after reassignment")

    # C tries to list comments (should succeed)
    send_packet(c_d1, "COMMENT_LIST_REQ", {"task_id": task_id})
    resp_c1 = recv_packet(c_d1)
    assert resp_c1['type'] == 'COMMENT_LIST_RESP'
    assert len(resp_c1['data']['comments']) == 1
    print("SUCCESS: New assignee C granted access and sees history")

    # Cleanup connections
    for s in [a_d1, a_d2, b_d1, c_d1]:
        s.close()
    print("\n[TEST 6A] CommentSync Integration Passed Successfully!")

if __name__ == "__main__":
    test_comment_sync()
