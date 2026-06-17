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
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_db():
    """Initializes the users, messages, and tasks tables."""
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

        # Table: tasks (Milestone 4 + Phase 6A)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT,
                status TEXT CHECK( status IN ('TODO', 'DOING', 'DONE') ) NOT NULL DEFAULT 'TODO',
                creator_id INTEGER NOT NULL,
                assignee_id INTEGER,
                due_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                completed_at DATETIME,
                FOREIGN KEY(creator_id) REFERENCES users(id),
                FOREIGN KEY(assignee_id) REFERENCES users(id)
            )
        ''')
        # Migration: Add due_at if missing
        cursor.execute("PRAGMA table_info(tasks)")
        columns = [row[1] for row in cursor.fetchall()]
        if 'due_at' not in columns:
            cursor.execute("ALTER TABLE tasks ADD COLUMN due_at DATETIME")
            print("[DATABASE] Migrated tasks table: added due_at column.")

        # Indexes for tasks
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_tasks_creator ON tasks(creator_id)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON tasks(assignee_id)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)')
        
        # Table: task_comments (Phase 6A)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS task_comments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                content TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_comments_task ON task_comments(task_id)')

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

def user_exists(user_id):
    """Returns True if user_id exists in the users table."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM users WHERE id = ?", (user_id,))
        return cursor.fetchone() is not None
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

def get_conversation_list(user_id):
    """
    Returns a list of conversation summaries for a user.
    Each summary includes peer info and the last message.
    Does NOT include volatile status fields.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        # Find the latest message ID for each unique peer
        query = """
            WITH LastMessageIDs AS (
                SELECT MAX(id) as max_id
                FROM messages
                WHERE sender_id = ? OR receiver_id = ?
                GROUP BY (CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END)
            )
            SELECT 
                m.*,
                u.id as peer_id,
                u.display_name
            FROM messages m
            JOIN LastMessageIDs lm ON m.id = lm.max_id
            JOIN users u ON (CASE WHEN m.sender_id = ? THEN m.receiver_id ELSE m.sender_id END) = u.id
            ORDER BY m.id DESC
        """
        cursor.execute(query, (user_id, user_id, user_id, user_id))
        rows = cursor.fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()

def create_task(title, description, creator_id, assignee_id=None, due_at=None):
    """Creates a new task and returns the full task record with comment_count."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO tasks (title, description, creator_id, assignee_id, due_at) VALUES (?, ?, ?, ?, ?)",
            (title, description, creator_id, assignee_id, due_at)
        )
        task_id = cursor.lastrowid
        conn.commit()
        return get_task_by_id(task_id)
    finally:
        conn.close()

def get_task_by_id(task_id):
    """Fetches a single task by its ID with comment_count."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        query = """
            SELECT t.*, 
                   (SELECT COUNT(*) FROM task_comments WHERE task_id = t.id) as comment_count
            FROM tasks t 
            WHERE t.id = ?
        """
        cursor.execute(query, (task_id,))
        row = cursor.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()

def get_user_tasks(user_id):
    """Fetches all tasks where user is creator OR assignee with comment_count."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        query = """
            SELECT t.*, 
                   (SELECT COUNT(*) FROM task_comments WHERE task_id = t.id) as comment_count
            FROM tasks t 
            WHERE t.creator_id = ? OR t.assignee_id = ? 
            ORDER BY t.updated_at DESC
        """
        cursor.execute(query, (user_id, user_id))
        rows = cursor.fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()

def update_task(task_id, updates):
    """
    Updates a task with the provided fields.
    Handles updated_at and completed_at logic.
    Returns authoritative state with comment_count.
    """
    if not updates:
        return get_task_by_id(task_id)

    conn = get_connection()
    try:
        cursor = conn.cursor()
        
        # Build query dynamically
        fields = []
        params = []
        for key, value in updates.items():
            fields.append(f"{key} = ?")
            params.append(value)
        
        # Always update updated_at
        fields.append("updated_at = CURRENT_TIMESTAMP")
        
        # Status-based completed_at logic
        if 'status' in updates:
            if updates['status'] == 'DONE':
                fields.append("completed_at = CURRENT_TIMESTAMP")
            else:
                fields.append("completed_at = NULL")
        
        params.append(task_id)
        query = f"UPDATE tasks SET {', '.join(fields)} WHERE id = ?"
        
        cursor.execute(query, params)
        conn.commit()
        return get_task_by_id(task_id)
    finally:
        conn.close()

def delete_task(task_id):
    """Deletes a task by its ID. Returns True if successful."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()

def get_users_by_ids(user_ids):
    """
    Fetches multiple users by their IDs.
    Returns a list of {id, display_name} dicts.
    """
    if not user_ids:
        return []
    conn = get_connection()
    try:
        cursor = conn.cursor()
        placeholders = ', '.join(['?'] * len(user_ids))
        query = f"SELECT id, display_name FROM users WHERE id IN ({placeholders})"
        cursor.execute(query, user_ids)
        rows = cursor.fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()

def search_users(query):
    """
    Searches for users by display_name or phone.
    Returns a list of {id, display_name} dicts.
    Limit 20.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        search_term = f"%{query}%"
        cursor.execute(
            "SELECT id, display_name FROM users WHERE display_name LIKE ? OR phone LIKE ? LIMIT 20",
            (search_term, search_term)
        )
        rows = cursor.fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()

def create_comment(task_id, user_id, content):
    """Creates a new task comment."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO task_comments (task_id, user_id, content) VALUES (?, ?, ?)",
            (task_id, user_id, content)
        )
        comment_id = cursor.lastrowid
        conn.commit()
        
        # Return the created comment
        cursor.execute("SELECT * FROM task_comments WHERE id = ?", (comment_id,))
        row = cursor.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()
