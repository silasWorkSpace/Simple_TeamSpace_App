from storage import database

class ChannelService:
    @classmethod
    def handle_list(cls, handler, packet):
        p_id = packet.get("id")
        user_id = handler.user_id
        
        channels = database.get_channels_for_user(user_id)
        client_channels = []
        for c in channels:
            client_channels.append({
                "id": -c["id"],
                "name": c["name"],
                "owner_id": c["owner_id"],
                "is_public": bool(c["is_public"]),
                "is_joined": bool(c.get("is_joined", False))
            })
            
        handler.send_packet("CHANNEL_LIST_RESP", {"channels": client_channels}, p_id)

    @classmethod
    def handle_create(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        name = p_data.get("name")
        is_public = p_data.get("is_public", False)
        
        if not name:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing channel name"}, p_id)
            return

        channel = database.create_channel(name, handler.user_id, is_public)
        client_channel = {
            "id": -channel["id"],
            "name": channel["name"],
            "owner_id": channel["owner_id"],
            "is_public": bool(channel["is_public"]),
            "is_joined": True
        }
        handler.send_packet("CHANNEL_CREATE_RESP", {"channel": client_channel}, p_id)

    @classmethod
    def handle_join(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")

        if not client_channel_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing channel_id"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        channel = database.get_channel(db_channel_id)
        
        if not channel:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Channel not found"}, p_id)
            return
            
        if not channel["is_public"]:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Cannot join private channel"}, p_id)
            return

        database.add_channel_member(db_channel_id, handler.user_id)
        handler.send_packet("CHANNEL_JOIN_RESP", {"success": True}, p_id)
        handler.server.broadcast_to_user(handler.user_id, "CHANNEL_LIST_UPDATED", {})

    @classmethod
    def handle_leave(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")

        if not client_channel_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing channel_id"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        role = database.get_channel_role(db_channel_id, handler.user_id)
        if not role:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Not a member"}, p_id)
            return

        if role == 'owner':
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Owner cannot leave without transferring ownership"}, p_id)
            return

        database.remove_channel_member(db_channel_id, handler.user_id)
        handler.send_packet("CHANNEL_LEAVE_RESP", {"success": True}, p_id)
        handler.server.broadcast_to_user(handler.user_id, "CHANNEL_LIST_UPDATED", {})

    @classmethod
    def handle_kick(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")
        target_user_id = p_data.get("user_id")

        if not client_channel_id or not target_user_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing parameters"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        my_role = database.get_channel_role(db_channel_id, handler.user_id)
        target_role = database.get_channel_role(db_channel_id, target_user_id)
        
        if my_role not in ['owner', 'admin']:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Requires owner/admin"}, p_id)
            return
            
        if target_role == 'owner':
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Cannot kick owner"}, p_id)
            return
            
        if my_role == 'admin' and target_role == 'admin':
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Admin cannot kick another admin"}, p_id)
            return

        database.remove_channel_member(db_channel_id, target_user_id)
        handler.send_packet("CHANNEL_KICK_RESP", {"success": True}, p_id)

        if target_user_id in handler.server.active_sessions:
            handler.server.broadcast_to_user(target_user_id, "CHANNEL_LIST_UPDATED", {})

    @classmethod
    def handle_role_update(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")
        target_user_id = p_data.get("user_id")
        new_role = p_data.get("role")

        if not client_channel_id or not target_user_id or new_role not in ['admin', 'member']:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Invalid parameters"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        my_role = database.get_channel_role(db_channel_id, handler.user_id)
        target_role = database.get_channel_role(db_channel_id, target_user_id)
        
        if my_role != 'owner':
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Requires owner"}, p_id)
            return
            
        if target_role == 'owner':
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Cannot change owner role"}, p_id)
            return

        conn = database.get_connection()
        cursor = conn.cursor()
        cursor.execute("UPDATE channel_members SET role = ? WHERE channel_id = ? AND user_id = ?", (new_role, db_channel_id, target_user_id))
        conn.commit()
        conn.close()

        handler.send_packet("CHANNEL_ROLE_UPDATE_RESP", {"success": True, "channel_id": client_channel_id, "user_id": target_user_id, "role": new_role}, p_id)
        # Notify the target user (their list/role changed)
        if target_user_id in handler.server.active_sessions:
            handler.server.broadcast_to_user(target_user_id, "CHANNEL_LIST_UPDATED", {})
        # Also notify the owner's other devices (so the dialog refreshes on all screens)
        handler.server.broadcast_to_user(handler.user_id, "CHANNEL_LIST_UPDATED", {}, exclude_handler=handler)

    @classmethod
    def handle_rename(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")
        new_name = p_data.get("name")
        
        if not client_channel_id or not new_name:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing parameters"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        my_role = database.get_channel_role(db_channel_id, handler.user_id)
        if my_role not in ['owner', 'admin']:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Only owner/admin can rename channel"}, p_id)
            return

        success = database.rename_channel(db_channel_id, new_name)
        if success:
            handler.send_packet("CHANNEL_RENAME_RESP", {"success": True}, p_id)
        else:
            handler.send_packet("SYS_ERROR", {"code": 500, "message": "Failed to rename channel"}, p_id)

    @classmethod
    def handle_add_member(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")
        target_user_id = p_data.get("user_id")

        if not client_channel_id or not target_user_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing parameters"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        my_role = database.get_channel_role(db_channel_id, handler.user_id)
        
        if my_role not in ['owner', 'admin']:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Only owner/admin can add members"}, p_id)
            return

        database.add_channel_member(db_channel_id, target_user_id)
        handler.send_packet("CHANNEL_ADD_MEMBER_RESP", {"success": True}, p_id)
        
        # Notify the added user if online
        if target_user_id in handler.server.active_sessions:
            handler.server.broadcast_to_user(target_user_id, "CHANNEL_LIST_UPDATED", {})

    @classmethod
    def handle_remove_member(cls, handler, packet):
        # Deprecated: use handle_kick or handle_leave
        cls.handle_kick(handler, packet)

    @classmethod
    def handle_delete(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")

        if not client_channel_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing channel_id"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        channel = database.get_channel(db_channel_id)
        
        if not channel:
            handler.send_packet("SYS_ERROR", {"code": 404, "message": "Channel not found"}, p_id)
            return
            
        if channel["owner_id"] != handler.user_id:
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Only owner can delete channel"}, p_id)
            return

        # Fetch members to notify before deleting
        members = database.get_channel_members(db_channel_id)
        
        database.delete_channel(db_channel_id)
        handler.send_packet("CHANNEL_DELETE_RESP", {"success": True}, p_id)

        # Notify all members
        for m in members:
            uid = m['id']
            if uid in handler.server.active_sessions:
                handler.server.broadcast_to_user(uid, "CHANNEL_LIST_UPDATED", {})

    @classmethod
    def handle_members_list(cls, handler, packet):
        p_id = packet.get("id")
        p_data = packet.get("data", {})
        client_channel_id = p_data.get("channel_id")

        if not client_channel_id:
            handler.send_packet("SYS_ERROR", {"code": 400, "message": "Missing channel_id"}, p_id)
            return

        db_channel_id = abs(client_channel_id)
        if not database.is_channel_member(db_channel_id, handler.user_id):
            handler.send_packet("SYS_ERROR", {"code": 403, "message": "Access denied"}, p_id)
            return

        members = database.get_channel_members(db_channel_id)
        handler.send_packet("CHANNEL_MEMBERS_RESP", {"members": members}, p_id)
