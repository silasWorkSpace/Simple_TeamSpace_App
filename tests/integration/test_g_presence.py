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

def recv_packet(sock):
    header = sock.recv(4)
    if not header: return None
    length = struct.unpack('>I', header)[0]
    payload = sock.recv(length).decode('utf-8')
    return json.loads(payload)

def test_g_presence():
    print("\n[TEST G] Starting Multi-Device Presence Test...")
    
    suffix = int(time.time())
    u1_phone = f"u1_{suffix}"
    u2_phone = f"u2_{suffix}"
    password = "password"

    # 1. Register users using separate connections
    def register(phone, name):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8888))
        send_packet(s, "AUTH_REGISTER", {"phone": phone, "password": password, "display_name": name})
        resp = recv_packet(s)
        uid = resp['data']['user_id']
        s.close()
        return uid

    u1_id = register(u1_phone, "User 1")
    u2_id = register(u2_phone, "User 2")
    
    # Establish contact
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8888))
    send_packet(s, "AUTH_LOGIN", {"phone": u1_phone, "password": password})
    recv_packet(s) # AUTH_SUCCESS
    send_packet(s, "CHAT_SEND", {"client_msg_id": "setup", "receiver_id": u2_id, "content": "hi"})
    time.sleep(0.5)
    s.close()
    
    print(f"[Setup] Registered {u1_phone} (ID:{u1_id}) and {u2_phone} (ID:{u2_id})")

    # 2. User B (Watcher) connects
    watcher = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    watcher.connect(('127.0.0.1', 8888))
    send_packet(watcher, "AUTH_LOGIN", {"phone": u2_phone, "password": password})
    recv_packet(watcher) # AUTH_SUCCESS
    print(f"[Watcher] Logged in ({u2_phone})")
    time.sleep(1)

    # 3. User A Device 1 connects
    d1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    d1.connect(('127.0.0.1', 8888))
    send_packet(d1, "AUTH_LOGIN", {"phone": u1_phone, "password": password})
    print(f"[Device 1] Logged in ({u1_phone})")
    
    # Watcher should see USER_ONLINE
    time.sleep(1)
    watcher.setblocking(False)
    try:
        pkt = recv_packet(watcher)
        if pkt and pkt['type'] == 'USER_ONLINE' and pkt['data']['user_id'] == u1_id:
            print(f"[Watcher] Received: {pkt['type']} for user {pkt['data'].get('user_id')}")
        else:
            print(f"[Watcher] ERROR: Expected USER_ONLINE, got {pkt.get('type') if pkt else 'None'}")
    except Exception as e:
        print(f"[Watcher] ERROR: No packet received ({e})")

    # 4. User A Device 2 connects
    d2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    d2.connect(('127.0.0.1', 8888))
    send_packet(d2, "AUTH_LOGIN", {"phone": u1_phone, "password": password})
    print(f"[Device 2] Logged in ({u1_phone})")
    
    # Watcher should NOT see another USER_ONLINE
    time.sleep(1)
    try:
        pkt = recv_packet(watcher)
        if pkt and pkt['type'] == 'USER_ONLINE' and pkt['data']['user_id'] == u1_id: 
            print(f"[Watcher] ERROR: Unexpected duplicate USER_ONLINE")
        else: 
            print(f"[Watcher] Correct: No duplicate USER_ONLINE (Packet: {pkt.get('type') if pkt else 'None'})")
    except:
        print("[Watcher] Correct: No duplicate USER_ONLINE")

    # 5. Device 1 Disconnects
    print("[Device 1] Disconnecting...")
    d1.close()
    time.sleep(1)
    
    # Watcher should NOT see USER_OFFLINE
    try:
        pkt = recv_packet(watcher)
        if pkt and pkt['type'] == 'USER_OFFLINE' and pkt['data']['user_id'] == u1_id: 
            print(f"[Watcher] ERROR: Unexpected USER_OFFLINE")
        else: 
            print(f"[Watcher] Correct: No USER_OFFLINE yet (Packet: {pkt.get('type') if pkt else 'None'})")
    except:
        print("[Watcher] Correct: No USER_OFFLINE yet")

    # 6. Device 2 Disconnects
    print("[Device 2] Disconnecting...")
    d2.close()
    time.sleep(1)
    
    # Watcher should see USER_OFFLINE exactly once
    try:
        watcher.setblocking(True)
        pkt = recv_packet(watcher)
        if pkt and pkt['type'] == 'USER_OFFLINE' and pkt['data']['user_id'] == u1_id:
            print(f"[Watcher] Received: {pkt['type']} for user {pkt['data'].get('user_id')}")
        else:
            print(f"[Watcher] ERROR: Expected USER_OFFLINE, got {pkt.get('type') if pkt else 'None'}")
    except Exception as e:
        print(f"[Watcher] ERROR: No USER_OFFLINE received ({e})")

    watcher.close()
    print("[TEST G] Completed.\n")

if __name__ == "__main__":
    test_g_presence()
