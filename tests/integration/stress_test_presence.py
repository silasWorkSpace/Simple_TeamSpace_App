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
        payload = sock.recv(length).decode('utf-8')
        return json.loads(payload)
    except:
        return None

def stress_test_presence():
    print("\n[STRESS TEST] Starting Multi-Device Presence Stress Test...")
    HOST, PORT = '127.0.0.1', 8888
    
    # Setup users
    suffix = int(time.time())
    uA_phone = f"ua_stress_{suffix}"
    uB_phone = f"ub_stress_{suffix}"
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
    
    # Establish contact (A sends to B)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((HOST, PORT))
    send_packet(s, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(s)
    send_packet(s, "CHAT_SEND", {"client_msg_id": "stress-setup", "receiver_id": uB_id, "content": "hi"})
    time.sleep(0.5)
    s.close()

    # Watcher (User B)
    watcher = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    watcher.connect((HOST, PORT))
    send_packet(watcher, "AUTH_LOGIN", {"phone": uB_phone, "password": password})
    recv_packet(watcher)
    print("[Watcher] Logged in and monitoring User A...")

    # User A Device 1..5
    devices = []
    for i in range(1, 6):
        d = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        d.connect((HOST, PORT))
        send_packet(d, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
        recv_packet(d)
        devices.append(d)
        print(f"[Device {i}] Logged in.")
        if i == 1:
            pkt = recv_packet(watcher)
            assert pkt and pkt['type'] == 'USER_ONLINE', "Expected USER_ONLINE on first device"
            print("[Watcher] Received USER_ONLINE correctly.")
        else:
            pkt = recv_packet(watcher, timeout=0.5)
            assert pkt is None, f"Expected no packet on device {i} login, got {pkt}"

    # Disconnect 3, 1, 2, 4
    for idx in [2, 0, 1, 3]:
        print(f"[Device {idx+1}] Disconnecting...")
        devices[idx].close()
        time.sleep(0.5)
        pkt = recv_packet(watcher, timeout=0.5)
        assert pkt is None, f"Expected no USER_OFFLINE yet after device {idx+1} disconnected"
    
    print("[Watcher] Correct: User A still online after 4/5 devices disconnected.")

    # Disconnect 5
    print("[Device 5] Disconnecting...")
    devices[4].close()
    time.sleep(1)
    
    pkt = recv_packet(watcher)
    assert pkt and pkt['type'] == 'USER_OFFLINE', "Expected USER_OFFLINE after last device disconnected"
    print("[Watcher] Received USER_OFFLINE exactly once after last device disconnected.")

    watcher.close()
    print("[STRESS TEST] All multi-device scenarios passed!\n")

if __name__ == "__main__":
    stress_test_presence()
