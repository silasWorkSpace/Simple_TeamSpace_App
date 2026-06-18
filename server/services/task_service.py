from storage import database
import datetime

class TaskService:
    """Handles task management: CRUD operations and permissions."""

    VALID_STATUS = {"TODO", "DOING", "DONE"}

    @staticmethod
    def _validate_due_at(date_str):
        """Validates that a string is a strict ISO-8601 UTC datetime or None."""
        if date_str is None:
            return True
        try:
            # Expected format: "YYYY-MM-DDTHH:mm:ssZ"
            if not isinstance(date_str, str) or not date_str.endswith('Z'):
                return False
            datetime.datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            return True
        except ValueError:
            return False

    @staticmethod
    def get_visible_users(task):
        """
        The single source of truth for task visibility.
        Currently: {creator_id, assignee_id}.
        Filters out None to prevent routing errors.
        """
        visible = {task['creator_id']}
        if task.get('assignee_id') is not None:
            visible.add(task['assignee_id'])
        return visible

    @staticmethod
    def can_view_task(task_id, user_id):
        """Checks if a user has visibility of a task."""
        task = database.get_task_by_id(task_id)
        if not task:
            return False
        return user_id in TaskService.get_visible_users(task)

    @staticmethod
    def _broadcast_task_change(old_task, new_task, requester_handler):
        """
        Computes the difference in visibility and broadcasts events.
        Centralized logic for CREATE, UPDATE, DELETE, and REASSIGN.
        """
        prev_visible = TaskService.get_visible_users(old_task) if old_task else set()
        curr_visible = TaskService.get_visible_users(new_task) if new_task else set()

        # 1. Users losing visibility -> TASK_DELETED_EVENT
        for user_id in (prev_visible - curr_visible):
            requester_handler.server.broadcast_to_user(user_id, "TASK_DELETED_EVENT", {"task_id": old_task['id']})

        # 2. Users gaining visibility -> TASK_CREATED_EVENT
        for user_id in (curr_visible - prev_visible):
            # For the requester, we send RESP. For others (even on different devices), we send EVENT.
            requester_handler.server.broadcast_to_user(user_id, "TASK_CREATED_EVENT", {"task": new_task}, exclude_handler=requester_handler)

        # 3. Users with persistent visibility -> TASK_UPDATED_EVENT
        for user_id in (prev_visible & curr_visible):
            # Exclude requester_handler to satisfy "No self-event" mandate
            requester_handler.server.broadcast_to_user(user_id, "TASK_UPDATED_EVENT", {"task": new_task}, exclude_handler=requester_handler)

    @staticmethod
    def handle_create(handler, packet):
        """
        Handles TASK_CREATE_REQ.
        Contract: { "title": "...", "description": "...", "assignee_id": ID|None, "due_at": "YYYY-MM-DDTHH:mm:ssZ"|None }
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        title = p_data.get("title")
        description = p_data.get("description")
        assignee_id = p_data.get("assignee_id")
        due_at = p_data.get("due_at")
        creator_id = handler.user_id

        # Validation: Title required
        if not title or not title.strip():
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Title is required"}, p_id)
            return

        # Explicit Date Validation
        if "due_at" in p_data and not TaskService._validate_due_at(due_at):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Invalid due_at format. Must be ISO-8601 UTC (e.g. 2026-06-30T18:00:00Z) or null"}, p_id)
            return

        # 1. Explicit Assignee Validation
        if assignee_id is not None and not database.user_exists(assignee_id):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Assignee user does not exist"}, p_id)
            return

        # 2. Database Execution
        try:
            task = database.create_task(title.strip(), description, creator_id, assignee_id, due_at)
            # Response to requester
            handler.send_packet("TASK_CREATE_RESP", {"task": task}, p_id)
            # Broadcast to others
            TaskService._broadcast_task_change(None, task, handler)
        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": str(e)}, p_id)

    @staticmethod
    def handle_list(handler, packet):
        """
        Handles TASK_LIST_REQ.
        Returns tasks where user is creator OR assignee.
        """
        p_id = packet.get("id")
        user_id = handler.user_id

        tasks = database.get_user_tasks(user_id)
        # Response Contract: TASK_LIST_RESP { "tasks": [...] }
        handler.send_packet("TASK_LIST_RESP", {"tasks": tasks}, p_id)

    @staticmethod
    def handle_update(handler, packet):
        """
        Handles TASK_UPDATE_REQ.
        Payload Contract: { "task_id": X, "updates": { "status": "...", "due_at": "..." } }
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        task_id = p_data.get("task_id")
        updates = p_data.get("updates", {})
        user_id = handler.user_id

        if not task_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "task_id is required"}, p_id)
            return

        if not updates:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "No updates provided"}, p_id)
            return

        # 1. Fetch task for permission check and snapshot
        old_task = database.get_task_by_id(task_id)
        if not old_task:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Task not found"}, p_id)
            return

        # 2. Permission Model
        is_creator = old_task['creator_id'] == user_id
        is_assignee = old_task['assignee_id'] == user_id

        if not is_creator and not is_assignee:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Permission denied"}, p_id)
            return

        # 3. Filter updates based on role
        allowed_updates = {}
        if is_creator:
            for field in ['title', 'description', 'status', 'assignee_id', 'due_at']:
                if field in updates:
                    allowed_updates[field] = updates[field]
        else:
            # Assignee: Status only
            if 'status' in updates:
                allowed_updates['status'] = updates['status']
            
            forbidden_keys = [k for k in updates.keys() if k != 'status']
            if forbidden_keys:
                handler.send_packet("SYS_ERROR", {
                    "code": 403, 
                    "message": f"Assignee can only update status. Forbidden: {forbidden_keys}"
                }, p_id)
                return

        if not allowed_updates:
             handler.send_packet("SYS_ERROR", {"code": 400, "message": "No valid updates for your role"}, p_id)
             return

        # 4. Validations
        if 'status' in allowed_updates:
            if allowed_updates['status'] not in TaskService.VALID_STATUS:
                handler.send_packet("SYS_ERROR", {"code": 400, "message": f"Invalid status. Must be one of {TaskService.VALID_STATUS}"}, p_id)
                return

        if 'assignee_id' in allowed_updates and allowed_updates['assignee_id'] is not None:
            if not database.user_exists(allowed_updates['assignee_id']):
                handler.send_packet("SYS_ERROR", {"code": 400, "message": "New assignee does not exist"}, p_id)
                return

        if 'due_at' in allowed_updates:
            if not TaskService._validate_due_at(allowed_updates['due_at']):
                handler.send_packet("SYS_ERROR", {"code": 400, "message": "Invalid due_at format. Must be ISO-8601 UTC (e.g. 2026-06-30T18:00:00Z) or null"}, p_id)
                return

        # 5. Apply to DB
        try:
            new_task = database.update_task(task_id, allowed_updates)
            # Response to requester
            handler.send_packet("TASK_UPDATE_RESP", {"task": new_task}, p_id)
            # Broadcast to others
            TaskService._broadcast_task_change(old_task, new_task, handler)
        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": str(e)}, p_id)

    @staticmethod
    def handle_delete(handler, packet):
        """
        Handles TASK_DELETE_REQ.
        Creator only.
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        task_id = p_data.get("task_id")
        user_id = handler.user_id

        if not task_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "task_id is required"}, p_id)
            return

        old_task = database.get_task_by_id(task_id)
        if not old_task:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Task not found"}, p_id)
            return

        # Permission Check: Creator only
        if old_task['creator_id'] != user_id:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Only the creator can delete this task"}, p_id)
            return

        if database.delete_task(task_id):
            # Response to requester
            handler.send_packet("TASK_DELETE_RESP", {"task_id": task_id}, p_id)
            # Broadcast to others
            TaskService._broadcast_task_change(old_task, None, handler)
        else:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": "Delete failed"}, p_id)
