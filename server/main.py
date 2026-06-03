import sqlite3
import os
from config import DB_PATH
from core.tcp_server import TCPServer

def init_db():
    """Initializes the SQLite database with the specified schema."""
    if not os.path.exists('storage'):
        os.makedirs('storage')
        
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Table: users
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            display_name TEXT NOT NULL,
            is_online INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Table: messages (Skeleton for future compatibility)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender_id INTEGER NOT NULL,
            receiver_id INTEGER NOT NULL,
            content TEXT NOT NULL,
            msg_type TEXT NOT NULL,
            is_read INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (sender_id) REFERENCES users (id),
            FOREIGN KEY (receiver_id) REFERENCES users (id)
        )
    ''')

    # Table: tasks (Skeleton for future compatibility)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            status TEXT NOT NULL,
            creator_id INTEGER NOT NULL,
            assignee_id INTEGER,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (creator_id) REFERENCES users (id),
            FOREIGN KEY (assignee_id) REFERENCES users (id)
        )
    ''')

    # Table: files (Skeleton for future compatibility)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            local_path TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            uploader_id INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (uploader_id) REFERENCES users (id)
        )
    ''')

    conn.commit()
    conn.close()
    print("[DATABASE] Schema initialized successfully.")

def main():
    print("="*40)
    print("SERVER STARTING (Milestone 1)...")
    print("="*40)
    
    init_db()
    server = TCPServer()
    server.start()

if __name__ == "__main__":
    main()
