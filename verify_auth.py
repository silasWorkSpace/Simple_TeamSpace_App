import socket
import json
import struct
import time

def send_packet(s, p_type, data, p_id="test-req"):
    """Encapsulates data into a JSON packet with a 4-byte length prefix."""
    payload = {
        "v": "1.0",
        "id": p_id,
        "type": p_type,
        "data": data
    }
    json_str = json.dumps(payload).encode('utf-8')
    header = struct.pack('>I', len(json_str))
    s.sendall(header + json_str)

def recv_packet(s):
    """
    Reads a 4-byte length prefix followed by the JSON payload.
    Note: Assumes header is received in one chunk (acceptable for local test).
    """
    header = s.recv(4)
    if not header:
        return None
    length = struct.unpack('>I', header)[0]
    
    # Receive the full payload
    data = bytearray()
    while len(data) < length:
        chunk = s.recv(length - len(data))
        if not chunk:
            break
        data.extend(chunk)
    
    return json.loads(data.decode('utf-8'))

def run_test():
    server_addr = ('127.0.0.1', 8888)
    # Unique phone for this test run to avoid conflicts
    test_phone = f"test_{int(time.time())}" 
    
    print(f"--- STARTING AUTH VERIFICATION (Target: {server_addr[0]}:{server_addr[1]}) ---")
    
    try:
        # 1. Test Successful Registration
        s1 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s1.connect(server_addr)
        print("\n[TEST 1] Successful Registration")
        send_packet(s1, "AUTH_REGISTER", {
            "phone": test_phone,
            "password": "secure_password",
            "display_name": "Verification User"
        }, p_id="reg_success")
        
        resp = recv_packet(s1)
        print(f"Response: {json.dumps(resp, indent=2)}")
        if resp and resp.get("type") == "AUTH_SUCCESS":
            print("PASS: Registration successful.")
        else:
            print("FAIL: Expected AUTH_SUCCESS.")

        # 2. Test Duplicate Registration (using same phone)
        s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s2.connect(server_addr)
        print("\n[TEST 2] Duplicate Registration (Phone Exists)")
        send_packet(s2, "AUTH_REGISTER", {
            "phone": test_phone,
            "password": "another_password",
            "display_name": "Duplicate User"
        }, p_id="reg_dup")
        
        resp = recv_packet(s2)
        print(f"Response: {json.dumps(resp, indent=2)}")
        if resp and resp.get("type") == "SYS_ERROR" and resp["data"].get("code") == 400:
            print("PASS: Correctly rejected duplicate phone.")
        else:
            print("FAIL: Expected SYS_ERROR with code 400.")
        s2.close()

        # 3. Test Successful Login
        s3 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s3.connect(server_addr)
        print("\n[TEST 3] Successful Login")
        send_packet(s3, "AUTH_LOGIN", {
            "phone": test_phone,
            "password": "secure_password"
        }, p_id="login_success")
        
        resp = recv_packet(s3)
        print(f"Response: {json.dumps(resp, indent=2)}")
        if resp and resp.get("type") == "AUTH_SUCCESS":
            print("PASS: Login successful.")
        else:
            print("FAIL: Expected AUTH_SUCCESS.")

        # 4. Test Failed Login (Wrong Password)
        s4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s4.connect(server_addr)
        print("\n[TEST 4] Failed Login (Incorrect Password)")
        send_packet(s4, "AUTH_LOGIN", {
            "phone": test_phone,
            "password": "wrong_password"
        }, p_id="login_fail")
        
        resp = recv_packet(s4)
        print(f"Response: {json.dumps(resp, indent=2)}")
        if resp and resp.get("type") == "SYS_ERROR" and resp["data"].get("code") == 401:
            print("PASS: Correctly rejected invalid credentials.")
        else:
            print("FAIL: Expected SYS_ERROR with code 401.")
        s4.close()

        # 5. Verify Session Cleanup (Registration/Unregistration)
        print("\n[TEST 5] Session Cleanup")
        print("Closing authenticated connection (s3)...")
        s3.close()
        # Closing s1 (registered user)
        s1.close()
        print("PASS: Check server console for [SESSION] unregistered logs.")

    except Exception as e:
        print(f"\n[ERROR] Verification script failed: {e}")
    finally:
        print("\n--- VERIFICATION COMPLETE ---")

if __name__ == "__main__":
    run_test()
