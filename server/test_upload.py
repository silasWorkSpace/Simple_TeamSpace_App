import socket
import json
import uuid
import time

def recv_packet(sock):
    # read until newline
    buf = b''
    while True:
        chunk = sock.recv(1)
        if not chunk: return None
        if chunk == b'\n': break
        buf += chunk
    return json.loads(buf.decode('utf-8'))

def send_packet(sock, p_type, data, p_id=None):
    if not p_id: p_id = str(uuid.uuid4())
    p = {"type": p_type, "data": data, "id": p_id}
    sock.sendall((json.dumps(p) + "\n").encode('utf-8'))
    return p_id

def test_upload(test_name, filename, msg_type_input, metadata_input, expected_msg_type):
    print(f"\n--- Testing {test_name} ---")
    s = socket.socket()
    s.connect(('127.0.0.1', 8888))
    
    # login
    send_packet(s, "AUTH_REQ", {"username": "testuser", "password": "password"})
    auth_resp = recv_packet(s)
    user_id = auth_resp['data']['user']['id']
    
    # upload req
    req_data = {
        "filename": filename,
        "size_bytes": 10,
        "receiver_id": user_id  # send to self
    }
    if msg_type_input: req_data["msg_type"] = msg_type_input
    if metadata_input: req_data["metadata"] = metadata_input
    
    req_id = send_packet(s, "FILE_UPLOAD_REQ", req_data)
    resp = recv_packet(s)
    
    if resp['type'] == 'SYS_ERROR':
        print("ERROR:", resp)
        return False
        
    token = resp['data']['token']
    
    # upload binary
    ds = socket.socket()
    ds.connect(('127.0.0.1', 8081))
    ds.sendall(b'U' + token.encode('utf-8') + b'1234567890')
    ds.close()
    
    # expect CHAT_RECEIVE
    chat_recv = recv_packet(s)
    if not chat_recv or chat_recv['type'] != 'CHAT_RECEIVE':
        print("FAIL: Expected CHAT_RECEIVE, got", chat_recv)
        return False
        
    data = chat_recv['data']
    print("CHAT_RECEIVE msg_type:", data['msg_type'])
    print("CHAT_RECEIVE metadata:", data['metadata'])
    
    if data['msg_type'] != expected_msg_type:
        print(f"FAIL: Expected msg_type {expected_msg_type}, got {data['msg_type']}")
        return False
        
    if metadata_input:
        for k, v in metadata_input.items():
            if data['metadata'].get(k) != v:
                print(f"FAIL: Expected metadata[{k}]={v}, got {data['metadata'].get(k)}")
                return False
                
    # check history
    send_packet(s, "CHAT_HIST_REQ", {"peer_id": user_id, "limit": 1})
    hist = recv_packet(s)
    msgs = hist['data']['messages']
    if not msgs:
        print("FAIL: No messages in history")
        return False
        
    if msgs[0]['msg_type'] != expected_msg_type:
        print("FAIL: History msg_type mismatch")
        return False
        
    print("SUCCESS")
    return True

if __name__ == '__main__':
    ok = test_upload("Generic File", "doc.txt", None, None, "file")
    ok = ok and test_upload("Inline Image", "photo.png", None, None, "image")
    ok = ok and test_upload("Voice Message", "voice.m4a", "voice", {"duration_ms": 1500, "codec": "m4a"}, "voice")
    
    if ok:
        print("\nALL E2E TESTS PASSED")
    else:
        print("\nTESTS FAILED")
