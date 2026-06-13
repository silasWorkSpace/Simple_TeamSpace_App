from storage import database

class TaskService:
    """Handles task management: CRUD operations and permissions."""

    VALID_STATUS = {"TODO", "DOING", "DONE"}

    @staticmethod
    def handle_create(handler, packet):
        """
        Handles TASK_CREATE_REQ.
        Contract: { "title": "...", "description": "...", "assignee_id": ID|None }
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        title = p_data.get("title")
        description = p_data.get("description")
        assignee_id = p_data.get("assignee_id")
        creator_id = handler.user_id

        # Validation: Title required
        if not title or not title.strip():
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Title is required"}, p_id)
            return

        # 1. Explicit Assignee Validation
        if assignee_id is not None and not database.user_exists(assignee_id):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Assignee user does not exist"}, p_id)
            return

        # 2. Database Execution
        try:
            task = database.create_task(title.strip(), description, creator_id, assignee_id)
            # Response Contract: TASK_CREATE_RESP { "task": { ... } }
            handler.send_packet("TASK_CREATE_RESP", {"task": task}, p_id)
        except Exception as e:
            # Code 400 for validation/constraint failures as requested
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
        Payload Contract: { "task_id": X, "updates": { "status": "...", etc } }
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

        # 1. Fetch task for permission check
        task = database.get_task_by_id(task_id)
        if not task:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Task not found"}, p_id)
            return

        # 2. Permission Model
        is_creator = task['creator_id'] == user_id
        is_assignee = task['assignee_id'] == user_id

        if not is_creator and not is_assignee:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Permission denied"}, p_id)
            return

        # 3. Filter updates based on role
        allowed_updates = {}
        if is_creator:
            # Creator: Full control
            for field in ['title', 'description', 'status', 'assignee_id']:
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

        # 4. Status Validation (Shared Constant)
        if 'status' in allowed_updates:
            if allowed_updates['status'] not in TaskService.VALID_STATUS:
                handler.send_packet("SYS_ERROR", {"code": 400, "message": f"Invalid status. Must be one of {TaskService.VALID_STATUS}"}, p_id)
                return

        # 5. Assignee Validation (if creator is changing it)
        if 'assignee_id' in allowed_updates and allowed_updates['assignee_id'] is not None:
            if not database.user_exists(allowed_updates['assignee_id']):
                handler.send_packet("SYS_ERROR", {"code": 400, "message": "New assignee does not exist"}, p_id)
                return

        # 6. Apply to DB
        try:
            updated_task = database.update_task(task_id, allowed_updates)
            # Response Contract: TASK_UPDATE_RESP { "task": { ... } }
            handler.send_packet("TASK_UPDATE_RESP", {"task": updated_task}, p_id)
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

        task = database.get_task_by_id(task_id)
        if not task:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Task not found"}, p_id)
            return

        # Permission Check: Creator only
        if task['creator_id'] != user_id:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Only the creator can delete this task"}, p_id)
            return

        if database.delete_task(task_id):
            # Response Contract: TASK_DELETE_RESP { "task_id": X }
            handler.send_packet("TASK_DELETE_RESP", {"task_id": task_id}, p_id)
        else:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": "Delete failed"}, p_id)
