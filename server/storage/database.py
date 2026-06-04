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
    """Initializes the users table and its index for Milestone 2."""
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
        conn.commit()
        print("[DATABASE] Users table and index initialized.")
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
