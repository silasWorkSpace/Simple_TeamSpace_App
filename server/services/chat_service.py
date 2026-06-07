from storage import database

class ChatService:
    """Handles core chat logic: persistence, routing, and history."""

    @staticmethod
    def handle_send(handler, packet):
        """
        Handles CHAT_SEND from client.
        1. Persists to DB (with dedup).
        2. Sends CHAT_SENT to sender.
        3. Routes CHAT_RECEIVE to recipient if online.
        """
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        client_msg_id = p_data.get("client_msg_id")
        receiver_id = p_data.get("receiver_id")
        content = p_data.get("content")
        sender_id = handler.user_id

        if not all([client_msg_id, receiver_id, content]):
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing chat fields"}, p_id)
            return

        # 1. Persist
        server_msg_id, created_at, is_duplicate = database.create_message(
            client_msg_id, sender_id, receiver_id, content
        )

        # 2. Confirm to sender
        handler.send_packet("CHAT_SENT", {
            "server_msg_id": server_msg_id,
            "client_msg_id": client_msg_id,
            "sender_id": sender_id,
            "receiver_id": receiver_id,
            "created_at": created_at
        }, p_id)

        # 3. Route to recipient if online and not a duplicate (redundant but safe)
        recipient_handler = handler.server.active_sessions.get(receiver_id)
        if recipient_handler:
            recipient_handler.send_packet("CHAT_RECEIVE", {
                "server_msg_id": server_msg_id,
                "sender_id": sender_id,
                "sender_display_name": handler.display_name,
                "content": content,
                "created_at": created_at,
                "id": server_msg_id,
                "client_msg_id": client_msg_id,
                "receiver_id": receiver_id,
                "delivered_at": None,
                "read_at": None
            })

    @staticmethod
    def handle_received(handler, packet):
        """
        Handles CHAT_RECEIVED from recipient.
        1. Updates delivered_at in DB.
        2. Routes CHAT_DELIVERED to sender if online.
        """
        p_data = packet.get("data", {})
        server_msg_id = p_data.get("server_msg_id")

        if not server_msg_id:
            return

        # 1. Update DB
        delivered_at, client_msg_id, sender_id = database.update_delivered_status(server_msg_id)
        
        if delivered_at and sender_id:
            # 2. Notify original sender
            sender_handler = handler.server.active_sessions.get(sender_id)
            if sender_handler:
                sender_handler.send_packet("CHAT_DELIVERED", {
                    "client_msg_id": client_msg_id,
                    "server_msg_id": server_msg_id,
                    "delivered_at": delivered_at
                })

    @staticmethod
    def handle_history_request(handler, packet):
        """Fetches and returns chat history."""
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        
        peer_id = p_data.get("peer_id")
        limit = p_data.get("limit", 50)
        before_id = p_data.get("before_id")
        
        if not peer_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing peer_id"}, p_id)
            return

        history = database.get_chat_history(handler.user_id, peer_id, limit, before_id)
        handler.send_packet("CHAT_HIST_RESP", {"messages": history}, p_id)

    @staticmethod
    def handle_list_request(handler, packet):
        """
        Handles CHAT_LIST_REQ.
        Returns a list of conversation summaries.
        is_online is cross-referenced with active_sessions.
        """
        p_id = packet.get("id")
        user_id = handler.user_id

        # 1. Fetch summaries from DB (No status fields)
        summaries = database.get_conversation_list(user_id)
        
        # 2. Append real-time is_online status
        formatted_convs = []
        for s in summaries:
            peer_id = s['peer_id']
            # Real-time truth from TCPServer.active_sessions
            is_online = peer_id in handler.server.active_sessions
            
            formatted_convs.append({
                "peer_id": peer_id,
                "display_name": s['display_name'],
                "is_online": is_online,
                "last_message": {
                    "id": s['id'],
                    "client_msg_id": s['client_msg_id'],
                    "sender_id": s['sender_id'],
                    "receiver_id": s['receiver_id'],
                    "content": s['content'],
                    "created_at": s['created_at'],
                    "delivered_at": s['delivered_at'],
                    "read_at": s['read_at']
                }
            })

        handler.send_packet("CHAT_LIST_RESP", {"conversations": formatted_convs}, p_id)
