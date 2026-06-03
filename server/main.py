import sqlite3
import os
from config import DB_PATH
from core.tcp_server import TCPServer
def init_db():
    # Khởi tạo thư mục storage và database SQLite nếu chưa có
    if not os.path.exists('storage'):
        os.makedirs('storage')
        
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Bảng users dùng cột phone làm định danh
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            display_name TEXT NOT NULL,
            is_online INTEGER DEFAULT 0
        )
    ''')
    conn.commit()
    conn.close()
    print("[DATABASE] SQLite đã sẵn sàng.")

def main():
    print("="*40)
    print("SERVER STARTING...")
    print("="*40)
    
    init_db()
    server = TCPServer()
    server.start()

if __name__ == "__main__":
    main()