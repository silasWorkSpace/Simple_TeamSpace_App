import sqlite3
import os
import sys

# Add parent directory to path to import config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import DB_PATH

def get_connection():
    """Returns a connection to the SQLite database with row factory enabled."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Initializes the users and messages tables for Milestone 3."""
    if not os.path.exists('storage'):
        os.makedirs('storage')
        
    conn = get_connection()
    try:
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
        # Index for phone lookup
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone)')

        # Table: messages (Milestone 3)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_msg_id TEXT NOT NULL,
                sender_id INTEGER NOT NULL,
                receiver_id INTEGER NOT NULL,
                content TEXT NOT NULL,
                msg_type TEXT DEFAULT 'text',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                delivered_at DATETIME,
                read_at DATETIME,
                FOREIGN KEY(sender_id) REFERENCES users(id),
                FOREIGN KEY(receiver_id) REFERENCES users(id)
            )
        ''')
        # Index for de-duplication
        cursor.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_dedup ON messages(sender_id, client_msg_id)')
        # Index for conversation history
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(sender_id, receiver_id)')
        
        conn.commit()
        print("[DATABASE] Tables and indexes initialized.")
    finally:
        conn.close()

def create_user(phone, password_hash, display_name):
    """Inserts a new user into the database. Returns user_id or None if phone exists."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO users (phone, password_hash, display_name) VALUES (?, ?, ?)",
            (phone, password_hash, display_name)
        )
        user_id = cursor.lastrowid
        conn.commit()
        return user_id
    except sqlite3.IntegrityError:
        return None
    finally:
        conn.close()

def get_user_by_phone(phone):
    """Fetches a user by their phone number."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM users WHERE phone = ?", (phone,))
        return cursor.fetchone()
    finally:
        conn.close()

def update_online_status(user_id, is_online):
    """Updates the is_online status for a user."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("UPDATE users SET is_online = ? WHERE id = ?", (1 if is_online else 0, user_id))
        conn.commit()
    finally:
        conn.close()

def create_message(client_msg_id, sender_id, receiver_id, content):
    """
    Inserts a message if it doesn't exist (dedup).
    Returns (server_msg_id, created_at, is_duplicate).
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        # 1. Check for duplicate
        cursor.execute(
            "SELECT id, created_at FROM messages WHERE sender_id = ? AND client_msg_id = ?",
            (sender_id, client_msg_id)
        )
        existing = cursor.fetchone()
        if existing:
            return existing['id'], existing['created_at'], True

        # 2. Insert new
        cursor.execute(
            "INSERT INTO messages (client_msg_id, sender_id, receiver_id, content) VALUES (?, ?, ?, ?)",
            (client_msg_id, sender_id, receiver_id, content)
        )
        msg_id = cursor.lastrowid
        
        # Get the created_at timestamp
        cursor.execute("SELECT created_at FROM messages WHERE id = ?", (msg_id,))
        created_at = cursor.fetchone()['created_at']
        
        conn.commit()
        return msg_id, created_at, False
    finally:
        conn.close()

def update_delivered_status(server_msg_id):
    """Updates delivered_at for a message and returns (delivered_at, client_msg_id, sender_id)."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        now = sqlite3.connect(':memory:').execute("SELECT datetime('now')").fetchone()[0] # Simple way to get DB time
        cursor.execute(
            "UPDATE messages SET delivered_at = ? WHERE id = ? AND delivered_at IS NULL",
            (now, server_msg_id)
        )
        
        cursor.execute("SELECT delivered_at, client_msg_id, sender_id FROM messages WHERE id = ?", (server_msg_id,))
        row = cursor.fetchone()
        conn.commit()
        if row:
            return row['delivered_at'], row['client_msg_id'], row['sender_id']
        return None, None, None
    finally:
        conn.close()

def get_chat_history(user_a, user_b, limit=50, before_id=None):
    """Fetches paginated chat history between two users."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        query = """
            SELECT * FROM messages 
            WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
        """
        params = [user_a, user_b, user_b, user_a]
        
        if before_id:
            query += " AND id < ?"
            params.append(before_id)
            
        query += " ORDER BY id DESC LIMIT ?"
        params.append(limit)
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        # Convert to list of dicts for JSON serialization
        return [dict(row) for row in rows]
    finally:
        conn.close()

def get_active_contact_ids(user_id):
    """Returns IDs of users who have exchanged at least one message with user_id."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT DISTINCT receiver_id FROM messages WHERE sender_id = ?
            UNION
            SELECT DISTINCT sender_id FROM messages WHERE receiver_id = ?
        """, (user_id, user_id))
        return [row[0] for row in cursor.fetchall()]
    finally:
        conn.close()
