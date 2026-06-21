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

        # Insert system users for channels
        cursor.execute('''
            INSERT OR IGNORE INTO users (id, phone, password_hash, display_name) 
            VALUES 
              (-1, 'sys_general', 'sys', '#General'),
              (-2, 'sys_backend', 'sys', 'Backend'),
              (-3, 'sys_frontend', 'sys', 'Frontend')
        ''')

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

        # Migration: Add metadata if missing
        cursor.execute("PRAGMA table_info(messages)")
        columns = [row[1] for row in cursor.fetchall()]
        if 'metadata' not in columns:
            cursor.execute("ALTER TABLE messages ADD COLUMN metadata TEXT")
            print("[DATABASE] Migrated messages table: added metadata column.")

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

        # Table: activity_logs (Phase 6B)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS activity_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                user_id INTEGER,
                action_type TEXT NOT NULL,
                details TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
            )
        ''')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_activity_task ON activity_logs(task_id)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_activity_task_created ON activity_logs(task_id, created_at)')

        # Table: files (Phase 9)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS files (
                id TEXT PRIMARY KEY,
                uploader_id INTEGER NOT NULL,
                filename TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                status TEXT DEFAULT 'pending',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                completed_at DATETIME,
                FOREIGN KEY(uploader_id) REFERENCES users(id)
            )
        ''')
        # Table: channels (Phase 10)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS channels (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                owner_id INTEGER NOT NULL,
                is_public BOOLEAN DEFAULT 0,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Table: channel_members (Phase 10 & 11)
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS channel_members (
                channel_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                role TEXT CHECK( role IN ('owner', 'admin', 'member') ) DEFAULT 'member',
                joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (channel_id, user_id),
                FOREIGN KEY(channel_id) REFERENCES channels(id) ON DELETE CASCADE,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        ''')
        
        # Migration for role
        cursor.execute("PRAGMA table_info(channel_members)")
        columns = [row[1] for row in cursor.fetchall()]
        if 'role' not in columns:
            cursor.execute("ALTER TABLE channel_members ADD COLUMN role TEXT CHECK( role IN ('owner', 'admin', 'member') ) DEFAULT 'member'")
            print("[DATABASE] Migrated channel_members: added role column.")
            # Set creators as owners
            cursor.execute("UPDATE channel_members SET role = 'owner' WHERE user_id IN (SELECT owner_id FROM channels WHERE id = channel_members.channel_id)")
            # Add all existing users to public channels as members
            cursor.execute('''
                INSERT OR IGNORE INTO channel_members (channel_id, user_id, role)
                SELECT c.id, u.id, 'member'
                FROM channels c
                CROSS JOIN users u
                WHERE c.is_public = 1 AND u.id > 0
            ''')
            conn.commit()

        # Seed initial channels if they don't exist
        cursor.execute('''
            INSERT OR IGNORE INTO channels (id, name, owner_id, is_public) 
            VALUES 
              (1, '#General', 0, 1),
              (2, '#Backend', 0, 1),
              (3, '#Frontend', 0, 1)
        ''')

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

import json

def create_message(client_msg_id, sender_id, receiver_id, content, msg_type='text', metadata=None):
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
        meta_str = json.dumps(metadata) if metadata is not None else None
        cursor.execute(
            "INSERT INTO messages (client_msg_id, sender_id, receiver_id, content, msg_type, metadata) VALUES (?, ?, ?, ?, ?, ?)",
            (client_msg_id, sender_id, receiver_id, content, msg_type, meta_str)
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
        if user_b < 0:
            query = "SELECT * FROM messages WHERE receiver_id = ?"
            params = [user_b]
        else:
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
        
        # Convert to list of dicts for JSON serialization and parse metadata
        result = []
        for row in rows:
            d = dict(row)
            if d.get('metadata'):
                try:
                    import json
                    d['metadata'] = json.loads(d['metadata'])
                except:
                    d['metadata'] = None
            else:
                d['metadata'] = None
            result.append(d)
        return result
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
                WHERE (sender_id = ? OR receiver_id = ?) AND receiver_id > 0 AND sender_id > 0
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

def get_comments_for_task(task_id):
    """Fetches all comments for a specific task."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM task_comments WHERE task_id = ? ORDER BY id ASC", (task_id,))
        rows = cursor.fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()

def create_file_record(file_id, uploader_id, filename, size_bytes):
    """Creates a new pending file record."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO files (id, uploader_id, filename, size_bytes) VALUES (?, ?, ?, ?)",
            (file_id, uploader_id, filename, size_bytes)
        )
        conn.commit()
    finally:
        conn.close()

def complete_file_record(file_id):
    """Marks a file as completed."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE files SET status = 'completed', completed_at = CURRENT_TIMESTAMP WHERE id = ?",
            (file_id,)
        )
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()

def get_file_record(file_id):
    """Fetches a file record by its ID."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM files WHERE id = ?", (file_id,))
        row = cursor.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()

def cleanup_orphaned_files():
    """
    Deletes file records stuck in 'pending' status for more than 1 hour.
    Returns a list of full metadata dicts for each orphan so callers can
    delete physical files from disk and log human-readable details.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        # Fetch full metadata for logging/disk cleanup
        cursor.execute(
            "SELECT * FROM files WHERE status = 'pending' AND created_at < datetime('now', '-1 hour')"
        )
        orphans = [dict(row) for row in cursor.fetchall()]

        if orphans:
            ids = [o['id'] for o in orphans]
            placeholders = ','.join(['?'] * len(ids))
            cursor.execute(f"DELETE FROM files WHERE id IN ({placeholders})", ids)
            conn.commit()

        return orphans
    finally:
        conn.close()

def get_message_by_file_token(token):
    """
    Looks up the chat message whose content (file token) matches the given UUID.
    Returns a dict with sender_id and receiver_id for authorization checks,
    or None if no associated message is found yet.
    """
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT sender_id, receiver_id FROM messages WHERE content = ? AND msg_type IN ('file', 'image') LIMIT 1",
            (token,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def create_channel(name, owner_id, is_public=False):
    """Creates a new channel, adds a dummy user for FK constraints, and adds the owner as a member."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO channels (name, owner_id, is_public) VALUES (?, ?, ?)",
            (name, owner_id, 1 if is_public else 0)
        )
        channel_id = cursor.lastrowid
        
        cursor.execute(
            "INSERT OR IGNORE INTO users (id, phone, password_hash, display_name) VALUES (?, ?, 'sys', ?)",
            (-channel_id, f'sys_chan_{channel_id}', name)
        )
        
        cursor.execute(
            "INSERT INTO channel_members (channel_id, user_id, role) VALUES (?, ?, 'owner')",
            (channel_id, owner_id)
        )
        conn.commit()
        return get_channel(channel_id)
    finally:
        conn.close()

def get_channel(channel_id):
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM channels WHERE id = ?", (channel_id,))
        row = cursor.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()

def rename_channel(channel_id, new_name):
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("UPDATE channels SET name = ? WHERE id = ?", (new_name, channel_id))
        cursor.execute("UPDATE users SET display_name = ? WHERE id = ?", (new_name, -channel_id))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()

def delete_channel(channel_id):
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM channels WHERE id = ?", (channel_id,))
        cursor.execute("DELETE FROM users WHERE id = ?", (-channel_id,))
        # SQLite with PRAGMA foreign_keys = ON will handle channel_members deletion via CASCADE
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()

def get_channels_for_user(user_id):
    """Returns all public channels + private channels the user is a member of."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT c.*, 
                   EXISTS(SELECT 1 FROM channel_members WHERE channel_id = c.id AND user_id = ?) as is_joined
            FROM channels c
            WHERE c.is_public = 1
               OR EXISTS(SELECT 1 FROM channel_members WHERE channel_id = c.id AND user_id = ?)
            ORDER BY c.id ASC
        ''', (user_id, user_id))
        return [dict(row) for row in cursor.fetchall()]
    finally:
        conn.close()

def is_channel_readable(channel_id, user_id):
    """Checks if a user can read history (True for public, or explicit membership)."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT is_public FROM channels WHERE id = ?", (channel_id,))
        row = cursor.fetchone()
        if not row:
            return False
        if row['is_public']:
            return True
        cursor.execute("SELECT 1 FROM channel_members WHERE channel_id = ? AND user_id = ?", (channel_id, user_id))
        return cursor.fetchone() is not None
    finally:
        conn.close()

def is_channel_member(channel_id, user_id):
    """Checks strict membership (required to send messages)."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM channel_members WHERE channel_id = ? AND user_id = ?", (channel_id, user_id))
        return cursor.fetchone() is not None
    finally:
        conn.close()

def get_channel_role(channel_id, user_id):
    """Returns the role of a user in a channel ('owner', 'admin', 'member') or None."""
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT role FROM channel_members WHERE channel_id = ? AND user_id = ?", (channel_id, user_id))
        row = cursor.fetchone()
        return row['role'] if row else None
    finally:
        conn.close()

def get_channel_members(channel_id):
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT u.id, u.display_name, u.is_online, cm.role
            FROM channel_members cm
            JOIN users u ON cm.user_id = u.id
            WHERE cm.channel_id = ?
        ''', (channel_id,))
        return [dict(row) for row in cursor.fetchall()]
    finally:
        conn.close()

def add_channel_member(channel_id, user_id):
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("INSERT OR IGNORE INTO channel_members (channel_id, user_id) VALUES (?, ?)", (channel_id, user_id))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()

def remove_channel_member(channel_id, user_id):
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM channel_members WHERE channel_id = ? AND user_id = ?", (channel_id, user_id))
        conn.commit()
        return cursor.rowcount > 0
    finally:
        conn.close()
