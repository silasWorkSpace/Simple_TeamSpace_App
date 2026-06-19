import os
import sys
import unittest
import json
import sqlite3

# Add parent directory to path to import modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.database import init_db, get_connection
from services.task_service import TaskService
from services.comment_service import CommentService
from services.activity_service import ActivityService

import config

class MockServer:
    def broadcast_to_user(self, user_id, event, data, exclude_handler=None):
        pass

class MockHandler:
    def __init__(self, user_id):
        self.user_id = user_id
        self.server = MockServer()
        self.sent_packets = []
        
    def send_packet(self, packet_type, data, packet_id="system"):
        self.sent_packets.append({
            "type": packet_type,
            "data": data,
            "id": packet_id
        })
        
    def clear_packets(self):
        self.sent_packets = []

class TestActivityIntegration(unittest.TestCase):
    def setUp(self):
        from storage import database
        database.DB_PATH = ':memory:'
        init_db()
        
        # Monkey patch get_connection so that it uses a shared in-memory connection
        # SQLite :memory: DBs are per-connection. To share it, we need to keep it open.
        self.real_conn = sqlite3.connect(':memory:')
        self.real_conn.row_factory = sqlite3.Row
        self.real_conn.execute("PRAGMA foreign_keys = ON")
        
        class MockConnection:
            def __init__(self, conn):
                self.conn = conn
            def cursor(self):
                return self.conn.cursor()
            def commit(self):
                self.conn.commit()
            def close(self):
                pass # Prevent backend from closing the shared connection
                
        def mock_get_connection():
            return MockConnection(self.real_conn)
        
        self.original_get_connection = database.get_connection
        database.get_connection = mock_get_connection
        
        init_db()
        
        # Create users
        conn = database.get_connection()
        try:
            cursor = conn.cursor()
            cursor.execute("INSERT INTO users (phone, password_hash, display_name) VALUES ('user1', 'hash', 'User 1')")
            self.user1_id = cursor.lastrowid
            cursor.execute("INSERT INTO users (phone, password_hash, display_name) VALUES ('user2', 'hash', 'User 2')")
            self.user2_id = cursor.lastrowid
            cursor.execute("INSERT INTO users (phone, password_hash, display_name) VALUES ('user3', 'hash', 'User 3')")
            self.user3_id = cursor.lastrowid
            conn.commit()
        except Exception as e:
            pass

    def tearDown(self):
        from storage import database
        database.get_connection = self.original_get_connection
        self.real_conn.close()

    def test_full_activity_workflow(self):
        h1 = MockHandler(self.user1_id)
        
        # 1. Create Task -> TASK_CREATED
        create_req = {
            "id": "req-1",
            "data": {
                "title": "Activity Test",
                "description": "Integration Test",
                "due_at": "2026-06-30T18:00:00Z"
            }
        }
        TaskService.handle_create(h1, create_req)
        self.assertEqual(h1.sent_packets[-1]["type"], "TASK_CREATE_RESP", f"Expected TASK_CREATE_RESP but got: {h1.sent_packets[-1]}")
        task_id = h1.sent_packets[-1]["data"]["task"]["id"]
        
        # 2. Update Status and Assignee -> STATUS_CHANGED, ASSIGNEE_CHANGED
        update_req = {
            "id": "req-2",
            "data": {
                "task_id": task_id,
                "updates": {
                    "status": "DOING",
                    "assignee_id": self.user2_id,
                    "due_at": "2026-07-01T12:00:00Z"
                }
            }
        }
        TaskService.handle_update(h1, update_req)
        self.assertEqual(h1.sent_packets[-1]["type"], "TASK_UPDATE_RESP")
        
        # 3. Add Comment -> COMMENT_ADDED
        comment_req = {
            "id": "req-3",
            "data": {
                "task_id": task_id,
                "content": "This is a comment test"
            }
        }
        CommentService.handle_send(h1, comment_req)
        self.assertEqual(h1.sent_packets[-1]["type"], "COMMENT_SEND_RESP")
        
        # 4. Fetch Activity List
        list_req = {
            "id": "req-4",
            "data": {
                "task_id": task_id
            }
        }
        h1.clear_packets()
        ActivityService.handle_list(h1, list_req)
        
        self.assertEqual(len(h1.sent_packets), 1)
        resp = h1.sent_packets[0]
        self.assertEqual(resp["type"], "ACTIVITY_LIST_RESP")
        activities = resp["data"]["activities"]
        
        # We expect 5 activities:
        # TASK_CREATED
        # STATUS_CHANGED
        # ASSIGNEE_CHANGED
        # DUE_DATE_CHANGED
        # COMMENT_ADDED
        self.assertEqual(len(activities), 5)
        
        action_types = [a["action_type"] for a in activities]
        self.assertIn("TASK_CREATED", action_types)
        self.assertIn("STATUS_CHANGED", action_types)
        self.assertIn("ASSIGNEE_CHANGED", action_types)
        self.assertIn("DUE_DATE_CHANGED", action_types)
        self.assertIn("COMMENT_ADDED", action_types)
        
        # Verify chronological ordering by checking IDs are ascending
        ids = [a["id"] for a in activities]
        self.assertEqual(ids, sorted(ids))
        
        # 5. Verify visibility denial (403) for unrelated user
        h3 = MockHandler(self.user3_id)
        ActivityService.handle_list(h3, list_req)
        self.assertEqual(h3.sent_packets[-1]["type"], "SYS_ERROR")
        self.assertEqual(h3.sent_packets[-1]["data"]["code"], 403)

if __name__ == '__main__':
    unittest.main()
