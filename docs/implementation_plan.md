# Implementation Plan

## Implemented Architecture Decisions (Milestone 2 Verified)
- **Database Access**: Implemented `server/storage/database.py` using a lightweight Open-Execute-Close pattern.
- **Server Business Logic**: Implemented `server/services/auth_service.py` using `bcrypt` for secure hashing.
- **Client Networking**: Implemented `client/lib/services/auth_service.dart` with request-response correlation.
- **Client State Management**: Implemented `client/lib/controllers/auth_controller.dart` using `ChangeNotifier`.

---

## Future Proposals (Pending Approval)

### Milestone 3: Chat
- **Logic**: Implement `ChatService` on the server to route messages between `active_sessions`.
- **Persistence**: Finalize `messages` table schema and implement CRUD operations.
- **Client**: Create `ChatController` and `ChatTab` UI.

### Milestone 4: Tasks/Kanban (User-Scoped)
- **Scope**: A Kanban-style task management system where tasks are private to the creator and assignee.
- **Phased Implementation**:
    - **Phase 1 (M4 Initial)**: "Self-Management". Users create and manage their own tasks (`assignee_id` is null or same as `creator_id`). No dependency on user discovery.
    - **Phase 2 (Future)**: "Collaboration". Integrate `USER_LIST_REQ` to allow assigning tasks to other users.
- **Logic**: Implement `TaskService` on the server with strict ownership checks (`creator_id` or `assignee_id` must match the session user).
- **Persistence**: Finalize `tasks` table schema with `creator_id` and `assignee_id` foreign keys.
- **Client**: `TaskController` for state management and `KanbanTab` for UI.

### Milestone 5: File Storage + Voice
- **Logic**: Implement binary chunking for files and signaling for calls.
