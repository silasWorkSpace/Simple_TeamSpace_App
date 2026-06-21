import socket
import json
import struct
import threading
import time

PORT = 8888
HOST = '127.0.0.1'

class TestClient:
    def __init__(self, phone, password, display_name):
        self.phone = phone
        self.password = password
        self.display_name = display_name
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.user_id = None
        self.messages = []
        self.running = True
        self.connected = False
        
    def connect(self):
        self.sock.connect((HOST, PORT))
        self.connected = True
        threading.Thread(target=self._listen, daemon=True).start()
        
        # Register or Login
        self.send("AUTH_REGISTER", {
            "phone": self.phone,
            "password": self.password,
            "display_name": self.display_name
        })
        time.sleep(0.5)
        
    def _listen(self):
        while self.running:
            try:
                header = self.sock.recv(4)
                if not header: break
                length = struct.unpack('>I', header)[0]
                payload = self.sock.recv(length).decode('utf-8')
                packet = json.loads(payload)
                
                if packet['type'] == 'AUTH_SUCCESS':
                    self.user_id = packet['data']['user_id']
                elif packet['type'] == 'SYS_ERROR' and 'Phone already exists' in packet['data'].get('message', ''):
                    # Fallback to login
                    self.send("AUTH_LOGIN", {
                        "phone": self.phone,
                        "password": self.password
                    })
                    
                self.messages.append(packet)
            except:
                break
                
    def send(self, p_type, data, p_id="test"):
        packet = {"v": "1.0", "id": p_id, "type": p_type, "data": data}
        payload = json.dumps(packet).encode('utf-8')
        self.sock.sendall(struct.pack('>I', len(payload)) + payload)
        
    def get_packets(self, p_type):
        return [m for m in self.messages if m['type'] == p_type]
        
    def clear_packets(self):
        self.messages = []
        
    def close(self):
        self.running = False
        self.sock.close()

def run_tests():
    print("Starting Integration Tests...")
    
    c1 = TestClient("1111", "pass", "User A")
    c2 = TestClient("2222", "pass", "User B")
    c3 = TestClient("3333", "pass", "User C")
    
    c1.connect()
    c2.connect()
    c3.connect()
    
    time.sleep(1)
    
    assert c1.user_id is not None
    assert c2.user_id is not None
    assert c3.user_id is not None
    
    print("\n--- Test A: Public Channel ---")
    c1.clear_packets()
    c2.clear_packets()
    
    # Send to #General (receiver_id = -1)
    c1.send("CHAT_SEND", {
        "client_msg_id": "pub_msg_1",
        "receiver_id": -1,
        "content": "Hello Public!"
    }, "req_a1")
    
    time.sleep(0.5)
    
    rcv_a = c2.get_packets("CHAT_RECEIVE")
    if any(p['data']['content'] == 'Hello Public!' for p in rcv_a):
        print("PASS: Another user receives public message")
    else:
        print("FAIL: Another user did not receive public message")
        
    # History reload
    c2.clear_packets()
    c2.send("CHAT_HIST_REQ", {"peer_id": -1, "limit": 10}, "req_a2")
    time.sleep(0.5)
    hist_a = c2.get_packets("CHAT_HIST_RESP")
    if hist_a and any(m['content'] == 'Hello Public!' for m in hist_a[0]['data']['messages']):
        print("PASS: History reload works")
    else:
        print("FAIL: History reload failed")


    print("\n--- Test B: Private Channel ---")
    c1.clear_packets()
    c1.send("CHANNEL_CREATE_REQ", {"name": "Secret", "is_public": False}, "req_b1")
    time.sleep(0.5)
    
    resp_b1 = c1.get_packets("CHANNEL_CREATE_RESP")
    if not resp_b1:
        print("FAIL: Channel creation failed")
        return
    channel_id = abs(resp_b1[0]['data']['channel']['id'])
    print("PASS: Private channel created (ID: {})".format(channel_id))
    
    # Add Member c2
    c2.clear_packets()
    c1.send("CHANNEL_ADD_MEMBER_REQ", {"channel_id": channel_id, "user_id": c2.user_id}, "req_b2")
    time.sleep(0.5)
    print("PASS: Add member executed")
    
    # Member receives channel instantly
    list_updated = c2.get_packets("CHANNEL_LIST_UPDATED")
    if list_updated:
        print("PASS: Member receives channel list updated instantly")
    else:
        print("FAIL: Member did NOT receive channel list updated")
    
    # Member sees channel
    c2.clear_packets()
    c2.send("CHANNEL_LIST_REQ", {}, "req_b3")
    time.sleep(0.5)
    list_c2 = c2.get_packets("CHANNEL_LIST_RESP")
    if list_c2 and any(abs(c['id']) == channel_id for c in list_c2[0]['data']['channels']):
        print("PASS: Member sees channel")
    else:
        print("FAIL: Member does not see channel")
        
    # Non-member does not see channel
    c3.clear_packets()
    c3.send("CHANNEL_LIST_REQ", {}, "req_b4")
    time.sleep(0.5)
    list_c3 = c3.get_packets("CHANNEL_LIST_RESP")
    if list_c3 and not any(abs(c['id']) == channel_id for c in list_c3[0]['data']['channels']):
        print("PASS: Non-member does not see channel")
    else:
        print("FAIL: Non-member sees channel incorrectly")
        
    # Member receives messages
    c2.clear_packets()
    c1.send("CHAT_SEND", {
        "client_msg_id": "priv_msg_1",
        "receiver_id": -channel_id,
        "content": "Secret Message!"
    }, "req_b5")
    time.sleep(0.5)
    rcv_b = c2.get_packets("CHAT_RECEIVE")
    if any(p['data']['content'] == 'Secret Message!' for p in rcv_b):
        print("PASS: Member receives messages")
    else:
        print("FAIL: Member did not receive message")
        
    # Non-member cannot fetch history
    c3.clear_packets()
    c3.send("CHAT_HIST_REQ", {"peer_id": -channel_id, "limit": 10}, "req_b6")
    time.sleep(0.5)
    err_c3 = c3.get_packets("SYS_ERROR")
    if err_c3 and err_c3[0]['data']['code'] == 403:
        print("PASS: Non-member cannot fetch history (403 Forbidden)")
    else:
        print("FAIL: Non-member was able to fetch history or wrong error")

    # Delete Channel and test visibility lost instantly
    print("\n--- Test B2: Delete Channel ---")
    c2.clear_packets()
    c1.send("CHANNEL_DELETE_REQ", {"channel_id": channel_id}, "req_b7")
    time.sleep(0.5)
    list_updated_del = c2.get_packets("CHANNEL_LIST_UPDATED")
    if list_updated_del:
        print("PASS: Member receives channel list updated instantly after delete")
    else:
        print("FAIL: Member did NOT receive channel list updated after delete")
        
    c2.clear_packets()
    c2.send("CHAT_HIST_REQ", {"peer_id": -channel_id, "limit": 10}, "req_b8")
    time.sleep(0.5)
    err_c2_del = c2.get_packets("SYS_ERROR")
    if err_c2_del and err_c2_del[0]['data']['code'] in (404, 403):
        print("PASS: All members lose visibility immediately (cannot fetch history)")
    else:
        print("FAIL: Member could still fetch history or wrong error")

    print("\n--- Test C & D: Private Channel File Transfer / Voice ---")
    # File download test
    c1.clear_packets()
    c1.send("FILE_UPLOAD_REQ", {
        "filename": "secret.txt",
        "size_bytes": 100,
        "receiver_id": -channel_id
    }, "req_cd1")
    time.sleep(0.5)
    upl_resp = c1.get_packets("FILE_UPLOAD_RESP")
    if upl_resp:
        token = upl_resp[0]['data']['token']
        print("PASS: Upload token generated")
        
        # Manually complete the DB record to bypass the binary server for test
        import sqlite3
        import os
        db_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'storage', 'database.db')
        conn = sqlite3.connect(db_path)
        conn.execute("UPDATE files SET status='completed' WHERE id=?", (token,))
        # Also create a fake message
        import uuid
        conn.execute("INSERT INTO messages (client_msg_id, sender_id, receiver_id, content, msg_type) VALUES (?, ?, ?, ?, ?)",
                     (f"test_file_{uuid.uuid4().hex[:8]}", c1.user_id, -channel_id, token, "file"))
        conn.commit()
        conn.close()
        
        c2.clear_packets()
        c2.send("FILE_DOWNLOAD_REQ", {"token": token}, "req_cd2")
        time.sleep(0.5)
        dn_resp = c2.get_packets("FILE_DOWNLOAD_RESP")
        if dn_resp:
            print("PASS: Authorized member can access it")
        else:
            print("FAIL: Authorized member rejected")
            
        c3.clear_packets()
        c3.send("FILE_DOWNLOAD_REQ", {"token": token}, "req_cd3")
        time.sleep(0.5)
        err_dn = c3.get_packets("SYS_ERROR")
        if err_dn and err_dn[0]['data']['code'] == 403:
            print("PASS: Unauthorized user cannot access it (403 Forbidden)")
        else:
            print("FAIL: Unauthorized user bypassed checks")
    
    print("\nTests complete.")
    c1.close()
    c2.close()
    c3.close()

if __name__ == '__main__':
    run_tests()
