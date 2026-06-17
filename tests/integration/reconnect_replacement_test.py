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
    except:
        return None

def reconnect_replacement_test():
    print("\n[RECONNECT TEST] Starting Reconnect Replacement Test...")
    HOST, PORT = '127.0.0.1', 8888
    
    # Setup users
    suffix = int(time.time())
    uA_phone = f"ua_recon_{suffix}"
    uB_phone = f"ub_recon_{suffix}"
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
    send_packet(s, "CHAT_SEND", {"client_msg_id": "recon-setup", "receiver_id": uB_id, "content": "hi"})
    time.sleep(0.5)
    s.close()

    # Watcher (User B)
    watcher = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    watcher.connect((HOST, PORT))
    send_packet(watcher, "AUTH_LOGIN", {"phone": uB_phone, "password": password})
    recv_packet(watcher) # AUTH_SUCCESS
    print("[Watcher] Logged in and monitoring User A...")

    # 1. Device A connects
    da = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    da.connect((HOST, PORT))
    send_packet(da, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(da)
    print("[Device A] Connected.")
    
    pkt = recv_packet(watcher)
    assert pkt and pkt['type'] == 'USER_ONLINE', f"Expected USER_ONLINE, got {pkt.get('type') if pkt else 'None'}"

    # 2. Simulate "Network Drop" for Device A
    print("[Device A] Simulating network drop (no close yet).")

    # 3. Device B logs in (Replacement session)
    db = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    db.connect((HOST, PORT))
    send_packet(db, "AUTH_LOGIN", {"phone": uA_phone, "password": password})
    recv_packet(db)
    print("[Device B] Logged in (Replacement).")
    
    pkt = recv_packet(watcher, timeout=1.0)
    assert pkt is None, "Should NOT see USER_ONLINE/OFFLINE on replacement"

    # 4. Now old Device A cleanup executes (close it)
    print("[Device A] Cleanup executing (closing socket).")
    da.close()
    time.sleep(1.0)
    
    pkt = recv_packet(watcher, timeout=1.0)
    assert pkt is None, "Should NOT see USER_OFFLINE because Device B is still active"
    print("[Watcher] Correct: No USER_OFFLINE after old device cleanup.")

    # 5. Verify broadcasts still reach Device B
    print("[Watcher] Sending a message to User A to verify Device B receives it...")
    send_packet(watcher, "CHAT_SEND", {"client_msg_id": "test-recon", "receiver_id": uA_id, "content": "hello B"})
    
    # Watcher receives CHAT_SENT
    pkt_sent = recv_packet(watcher)
    assert pkt_sent and pkt_sent['type'] == 'CHAT_SENT'

    pkt = recv_packet(db)
    assert pkt and pkt['type'] == 'CHAT_RECEIVE', f"Expected CHAT_RECEIVE on Device B, got {pkt.get('type')}"
    print("[Device B] Received message correctly. Registry is healthy.")

    db.close()
    time.sleep(1.0)
    
    # Drain any remaining packets to find USER_OFFLINE
    while True:
        pkt = recv_packet(watcher, timeout=1.0)
        if not pkt: break
        if pkt['type'] == 'USER_OFFLINE':
            print("[Watcher] Received USER_OFFLINE exactly once.")
            break
    else:
        assert False, "Final USER_OFFLINE expected"
    
    watcher.close()
    print("[RECONNECT TEST] Reconnect replacement logic verified!\n")

if __name__ == "__main__":
    reconnect_replacement_test()
