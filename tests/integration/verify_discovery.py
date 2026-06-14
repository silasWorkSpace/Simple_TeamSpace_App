import socket
import json
import struct
import time

def send_packet(s, p_type, data, p_id="test-id"):
    payload = json.dumps({
        "v": "1.0",
        "id": p_id,
        "type": p_type,
        "data": data
    }).encode('utf-8')
    header = struct.pack('!I', len(payload))
    s.sendall(header + payload)

def recv_packet(s):
    header = s.recv(4)
    if not header: return None
    length = struct.unpack('!I', header)[0]
    payload = s.recv(length).decode('utf-8')
    return json.loads(payload)

def test_discovery():
    print("[TEST] Starting User Discovery Verification...")
    
    # Connect to server
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8888))
    
    try:
        # 1. Register/Login as User A
        phone_a = f"test_a_{int(time.time())}"
        send_packet(s, "AUTH_REGISTER", {"phone": phone_a, "password": "pass", "display_name": "Alice Wonderland"})
        resp = recv_packet(s)
        assert resp['type'] == "AUTH_SUCCESS", f"Auth failed: {resp}"
        
        # 2. Register/Login as User B (via separate connection to keep A active)
        s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s2.connect(('127.0.0.1', 8888))
        phone_b = f"test_b_{int(time.time())}"
        send_packet(s2, "AUTH_REGISTER", {"phone": phone_b, "password": "pass", "display_name": "Bob Builder"})
        recv_packet(s2)
        s2.close()

        # 3. Search by partial name ("Ali")
        print("[TEST] Searching by partial name 'Ali'...")
        send_packet(s, "USER_SEARCH_REQ", {"query": "Ali"})
        resp = recv_packet(s)
        assert resp['type'] == "USER_SEARCH_RESP"
        users = resp['data']['users']
        assert any(u['display_name'] == "Alice Wonderland" for u in users), "Alice not found by name"
        assert all("phone" not in u for u in users), "PRIVACY BREACH: Phone number exposed in results"
        print("[SUCCESS] Partial name search verified.")

        # 4. Search by phone number
        print(f"[TEST] Searching by phone number {phone_b}...")
        send_packet(s, "USER_SEARCH_REQ", {"query": phone_b})
        resp = recv_packet(s)
        assert resp['type'] == "USER_SEARCH_RESP"
        users = resp['data']['users']
        assert any(u['display_name'] == "Bob Builder" for u in users), "Bob not found by phone"
        print("[SUCCESS] Phone number search verified.")

        # 5. Search with short query (should be empty, not error)
        print("[TEST] Searching with short query 'A'...")
        send_packet(s, "USER_SEARCH_REQ", {"query": "A"})
        resp = recv_packet(s)
        assert resp['type'] == "USER_SEARCH_RESP"
        assert len(resp['data']['users']) == 0
        print("[SUCCESS] Short query validation verified.")

        # 6. Search with trimmed query
        print("[TEST] Searching with padded query '  Ali  '...")
        send_packet(s, "USER_SEARCH_REQ", {"query": "  Ali  "})
        resp = recv_packet(s)
        assert resp['type'] == "USER_SEARCH_RESP"
        assert len(resp['data']['users']) > 0
        print("[SUCCESS] Query trimming verified.")

        print("\n[COMPLETE] All User Discovery backend tests passed.")

    finally:
        s.close()

if __name__ == "__main__":
    test_discovery()
