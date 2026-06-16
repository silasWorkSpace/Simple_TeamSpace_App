class UserService:
    """Handles user discovery and profile management."""

    @staticmethod
    def handle_search(handler, packet):
        """
        Handles USER_SEARCH_REQ.
        Contract: { "query": "..." }
        Min 2 chars (trimmed).
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        query = p_data.get("query", "").strip()
        
        # Validation: Min 2 chars
        if len(query) < 2:
            # We return empty results rather than an error for search-as-you-type UX
            handler.send_packet("USER_SEARCH_RESP", {"users": []}, p_id)
            return

        from storage import database
        try:
            users = database.search_users(query)
            handler.send_packet("USER_SEARCH_RESP", {"users": users}, p_id)
        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": str(e)}, p_id)

    @staticmethod
    def handle_get(handler, packet):
        """
        Handles USER_GET_REQ.
        Contract: { "user_ids": [ID1, ID2, ...] }
        Validation: Returns 400 if user_ids is not a list or contains non-integers.
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        user_ids = p_data.get("user_ids", [])

        if not isinstance(user_ids, list):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "user_ids must be a list"}, p_id)
            return

        # Strict Validation: All must be integers
        if not all(isinstance(uid, int) for uid in user_ids):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "All user_ids must be integers"}, p_id)
            return

        from storage import database
        try:
            users = database.get_users_by_ids(user_ids)
            handler.send_packet("USER_GET_RESP", {"users": users}, p_id)
        except Exception as e:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": str(e)}, p_id)
