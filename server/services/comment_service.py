from storage import database
from services.task_service import TaskService

class CommentService:
    """Handles task comment operations and real-time broadcasting."""

    @staticmethod
    def handle_send(handler, packet):
        """
        Handles COMMENT_SEND_REQ.
        Contract: { "task_id": X, "content": "..." }
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        task_id = p_data.get("task_id")
        content = p_data.get("content")
        user_id = handler.user_id

        # Basic validation
        if not task_id or not content or not str(content).strip():
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "task_id and content are required"}, p_id)
            return

        # 1. Centralized Visibility Check (Strict Enforcement)
        if not TaskService.can_view_task(task_id, user_id):
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Permission denied: Cannot comment on this task"}, p_id)
            return

        # 2. Persist Comment
        try:
            comment = database.create_comment(task_id, user_id, str(content).strip())
            if not comment:
                handler.send_packet("SYS_ERROR", {"code": 500, "message": "Failed to create comment"}, p_id)
                return
            
            # TODO: Hook into Activity Log (Phase 6B)

            # 3. Respond to Requester (H_orig)
            handler.send_packet("COMMENT_SEND_RESP", {"comment": comment}, p_id)

            # 4. Multi-Device Event Delivery Behavior
            task = database.get_task_by_id(task_id) # Inherently contains creator_id and assignee_id
            visible_users = TaskService.get_visible_users(task)
            
            for v_user_id in visible_users:
                # Exclude the requester's specific connection
                handler.server.broadcast_to_user(
                    v_user_id, 
                    "COMMENT_CREATED_EVENT", 
                    {"comment": comment}, 
                    exclude_handler=handler
                )

        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": str(e)}, p_id)

    @staticmethod
    def handle_list(handler, packet):
        """
        Handles COMMENT_LIST_REQ.
        Contract: { "task_id": X }
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        task_id = p_data.get("task_id")
        user_id = handler.user_id

        if not task_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "task_id is required"}, p_id)
            return

        # 1. Centralized Visibility Check
        if not TaskService.can_view_task(task_id, user_id):
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Permission denied: Cannot view comments for this task"}, p_id)
            return

        # 2. Fetch Comments
        try:
            comments = database.get_comments_for_task(task_id)
            handler.send_packet("COMMENT_LIST_RESP", {"task_id": task_id, "comments": comments}, p_id)
        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": str(e)}, p_id)
