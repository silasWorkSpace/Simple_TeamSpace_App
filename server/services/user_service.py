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
