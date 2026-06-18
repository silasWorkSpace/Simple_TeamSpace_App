import socket
import json
import struct
import time

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

def test_due_date_sync():
    print("\n[TEST 6A-B] Starting Due Date Sync Integration Test...")
    HOST, PORT = '127.0.0.1', 8888
    
    # 1. Setup Users
    suffix = int(time.time())
    uA_phone, uB_phone = f"da_{suffix}", f"db_{suffix}"
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

    # 2. Connect Clients
    a_d1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    a_d1.connect((HOST, PORT))
    send_packet(a_d1, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(a_d1)

    a_d2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    a_d2.connect((HOST, PORT))
    send_packet(a_d2, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(a_d2)

    b_d1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    b_d1.connect((HOST, PORT))
    send_packet(b_d1, "AUTH_LOGIN", {"phone": uB_phone, "password": password})
    recv_packet(b_d1)

    # --- Scenario F: Validation ---
    print("\n[Scenario F] Invalid due_at format validation")
    send_packet(a_d1, "TASK_CREATE_REQ", {"title": "Bad Date", "due_at": "2026-06-30 18:00:00"}) # Missing Z / T
    resp = recv_packet(a_d1)
    assert resp['type'] == 'SYS_ERROR' and resp['data']['code'] == 400
    print("SUCCESS: Invalid date format correctly rejected")

    # --- Scenario A: Create task with due_at ---
    print("\n[Scenario A & D & E] Create task with due_at (and verify propagation)")
    due_date_utc = "2026-06-30T18:00:00Z"
    send_packet(a_d1, "TASK_CREATE_REQ", {"title": "Due Task", "assignee_id": uB_id, "due_at": due_date_utc})
    
    resp_a1 = recv_packet(a_d1)
    ev_a2 = recv_packet(a_d2)
    ev_b1 = recv_packet(b_d1)

    task_id = resp_a1['data']['task']['id']
    assert resp_a1['data']['task']['due_at'] == due_date_utc, "RESP missing due_at"
    assert ev_a2['data']['task']['due_at'] == due_date_utc, "EVENT A2 missing due_at"
    assert ev_b1['data']['task']['due_at'] == due_date_utc, "EVENT B1 missing due_at"
    print("SUCCESS: Task created and propagated with correct due_at to all devices and roles")

    # --- Scenario B: Update due_at ---
    print("\n[Scenario B] Update due_at")
    new_date_utc = "2026-07-01T10:00:00Z"
    send_packet(a_d1, "TASK_UPDATE_REQ", {"task_id": task_id, "updates": {"due_at": new_date_utc}})
    
    resp_a1 = recv_packet(a_d1)
    ev_a2 = recv_packet(a_d2)
    ev_b1 = recv_packet(b_d1)

    assert resp_a1['data']['task']['due_at'] == new_date_utc
    assert ev_a2['data']['task']['due_at'] == new_date_utc
    assert ev_b1['data']['task']['due_at'] == new_date_utc
    print("SUCCESS: due_at successfully updated and propagated")

    # --- Scenario C: Remove due_at (set null) ---
    print("\n[Scenario C] Remove due_at (null semantics)")
    send_packet(a_d1, "TASK_UPDATE_REQ", {"task_id": task_id, "updates": {"due_at": None}})
    
    resp_a1 = recv_packet(a_d1)
    ev_a2 = recv_packet(a_d2)
    ev_b1 = recv_packet(b_d1)

    assert resp_a1['data']['task']['due_at'] is None
    assert ev_a2['data']['task']['due_at'] is None
    assert ev_b1['data']['task']['due_at'] is None
    print("SUCCESS: due_at successfully removed (nullified) and propagated")

    for s in [a_d1, a_d2, b_d1]:
        s.close()
    print("\n[TEST 6A-B] All due_at sync scenarios passed!\n")

if __name__ == "__main__":
    test_due_date_sync()
