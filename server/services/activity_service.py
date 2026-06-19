import json
import sqlite3
from typing import Optional, List, Dict, Any
from storage import database

# Action Type Constants
TASK_CREATED = 'TASK_CREATED'
STATUS_CHANGED = 'STATUS_CHANGED'
ASSIGNEE_CHANGED = 'ASSIGNEE_CHANGED'
DUE_DATE_CHANGED = 'DUE_DATE_CHANGED'
COMMENT_ADDED = 'COMMENT_ADDED'

class ActivityService:
    @staticmethod
    def log_activity(task_id: int, user_id: Optional[int], action_type: str, details: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Logs an activity for a task.
        details is a dictionary that will be JSON encoded.
        Returns the created activity dict or None.
        """
        conn = database.get_connection()
        try:
            cursor = conn.cursor()
            details_json = json.dumps(details)
            
            cursor.execute(
                "INSERT INTO activity_logs (task_id, user_id, action_type, details) VALUES (?, ?, ?, ?)",
                (task_id, user_id, action_type, details_json)
            )
            activity_id = cursor.lastrowid
            conn.commit()
            
            # Fetch and return the newly created row
            cursor.execute("SELECT * FROM activity_logs WHERE id = ?", (activity_id,))
            row = cursor.fetchone()
            if row:
                result = dict(row)
                if result['details']:
                    result['details'] = json.loads(result['details'])
                return result
            return None
        finally:
            conn.close()

    @staticmethod
    def get_task_activities(task_id: int) -> List[Dict[str, Any]]:
        """
        Fetches all activities for a specific task, ordered chronologically.
        The 'details' field is automatically JSON decoded back to a dictionary.
        """
        conn = database.get_connection()
        try:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT * FROM activity_logs WHERE task_id = ? ORDER BY created_at ASC, id ASC",
                (task_id,)
            )
            rows = cursor.fetchall()
            
            results = []
            for row in rows:
                item = dict(row)
                if item['details']:
                    try:
                        item['details'] = json.loads(item['details'])
                    except json.JSONDecodeError:
                        item['details'] = {}
                else:
                    item['details'] = {}
                results.append(item)
                
            return results
        finally:
            conn.close()

    @staticmethod
    def handle_list(handler, packet):
        """
        Handles ACTIVITY_LIST_REQ.
        Contract: { "task_id": X }
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        task_id = p_data.get("task_id")
        user_id = handler.user_id

        if not task_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "task_id is required"}, p_id)
            return

        # Deferred import to avoid circular dependency
        from services.task_service import TaskService

        # 1. Centralized Visibility Check
        if not TaskService.can_view_task(task_id, user_id):
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Permission denied: Cannot view activity for this task"}, p_id)
            return

        # 2. Fetch Activities
        try:
            activities = ActivityService.get_task_activities(task_id)
            handler.send_packet("ACTIVITY_LIST_RESP", {"task_id": task_id, "activities": activities}, p_id)
        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": str(e)}, p_id)
