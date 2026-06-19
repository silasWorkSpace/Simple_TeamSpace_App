import os
import sys
import unittest

# Add parent directory to path to import modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from storage.database import init_db, get_connection
from services.activity_service import (
    ActivityService,
    STATUS_CHANGED,
    ASSIGNEE_CHANGED
)

import config

class TestActivityService(unittest.TestCase):
    def setUp(self):
        # Use in-memory DB for tests
        config.DB_PATH = ':memory:'
        init_db()
        # Create dummy user and task for foreign key constraints
        conn = get_connection()
        try:
            cursor = conn.cursor()
            cursor.execute("INSERT INTO users (phone, password_hash, display_name) VALUES ('123', 'hash', 'Test')")
            user_id = cursor.lastrowid
            cursor.execute("INSERT INTO tasks (title, creator_id) VALUES ('Test Task', ?)", (user_id,))
            conn.commit()
        finally:
            conn.close()

    def test_activity_logging(self):
        # 1. We know task_id=1, user_id=1 from setup
        task_id = 1
        user_id = 1
        
        # 2. Log first activity
        act1 = ActivityService.log_activity(
            task_id=task_id, 
            user_id=user_id, 
            action_type=STATUS_CHANGED, 
            details={"from": "TODO", "to": "DOING"}
        )
        
        self.assertIsNotNone(act1)
        self.assertEqual(act1['action_type'], STATUS_CHANGED)
        self.assertEqual(act1['details']['from'], "TODO")
        self.assertEqual(act1['details']['to'], "DOING")
        
        # 3. Log second activity
        act2 = ActivityService.log_activity(
            task_id=task_id,
            user_id=user_id,
            action_type=ASSIGNEE_CHANGED,
            details={"from": None, "to": 2}
        )
        
        self.assertEqual(act2['action_type'], ASSIGNEE_CHANGED)
        self.assertIsNone(act2['details']['from'])
        self.assertEqual(act2['details']['to'], 2)

        # 4. Fetch activities
        activities = ActivityService.get_task_activities(task_id)
        
        self.assertEqual(len(activities), 2)
        
        # Verify chronological ordering
        self.assertEqual(activities[0]['id'], act1['id'])
        self.assertEqual(activities[1]['id'], act2['id'])
        
        # Verify JSON deserialization
        self.assertEqual(activities[0]['details'], {"from": "TODO", "to": "DOING"})
        self.assertEqual(activities[1]['details'], {"from": None, "to": 2})

if __name__ == '__main__':
    unittest.main()
