# Milestone 4 Architecture Snapshot: Task Synchronization & Multi-Device Core

## 1. Protocol Overview
The system uses a JSON-over-TCP protocol with a 4-byte big-endian length prefix. All packets follow a versioned schema `{"v": "1.0", "id": "...", "type": "...", "data": {...}}`.

### 1.1 AUTH Packets
*   `AUTH_REGISTER`: Handshake for new account creation.
*   `AUTH_LOGIN`: Credential verification and session establishment.
*   `AUTH_SUCCESS`: Server confirmation with profile data.

### 1.2 CHAT Packets
*   `CHAT_SEND`: Outgoing message from client.
*   `CHAT_RECEIVE`: Pushed message for recipient.
*   `CHAT_SENT`: Server confirmation of persistence.
*   `CHAT_DELIVERED`: Receipt confirmation (Delivery status).
*   `CHAT_LIST_REQ / RESP`: Conversation summary list.
*   `CHAT_HIST_REQ / RESP`: Paginated message history.

### 1.3 TASK Packets
*   `TASK_CREATE_REQ / RESP`: Task creation and assignment.
*   `TASK_UPDATE_REQ / RESP`: Modification of status or details.
*   `TASK_DELETE_REQ / RESP`: Task removal.
*   `TASK_LIST_REQ / RESP`: Fetching tasks visible to the user.

### 1.4 EVENT Packets (Push Layer)
System-initiated authoritative state updates sent to relevant handlers.
*   `TASK_CREATED_EVENT`: Sent when a task enters a user's visibility scope.
*   `TASK_UPDATED_EVENT`: Sent when a visible task is modified by another party.
*   `TASK_DELETED_EVENT`: Sent when a task is deleted or leaves visibility scope.
*   `USER_ONLINE / USER_OFFLINE`: Presence updates for active contacts.

### 1.5 USER Lookup Packets
*   `USER_SEARCH_REQ / RESP`: Directory search by phone or name.
*   `USER_GET_REQ / RESP`: Fetching specific user metadata for UI resolution.

---

## 2. Database Overview
Storage is managed via SQLite with strict foreign key constraints.

### 2.1 Main Tables
*   `users`: Stores credentials, display names, and `is_online` status.
*   `messages`: Persistent chat history with delivery/read tracking.
*   `tasks`: Centralized task state. Includes `creator_id`, `assignee_id`, `status` (TODO, DOING, DONE), and timestamps.

### 2.2 Key Relationships
*   `tasks` -> `users`: Two-way relationship via `creator_id` and `assignee_id`.
*   `messages` -> `users`: Sender and Receiver associations.

### 2.3 Task Visibility Assumptions
*   **Access Rule:** A task is visible to a user **ONLY IF** `user.id == task.creator_id` OR `user.id == task.assignee_id`.
*   **Ownership:** Visibility defines the scope of data synchronization. Changes outside this scope are never pushed to the client.

---

## 3. Session Architecture
The server manages a thread-safe registry to support high-concurrency and multi-device scenarios.

### 3.1 Registry (`active_sessions`)
*   **Model:** `Dict[int, Set[ClientHandler]]` (1:N mapping).
*   **Integrity:** Mutations are protected by a `threading.Lock` to prevent race conditions during overlapping login/logout operations.

### 3.2 Presence Lifecycle
*   **Centralization:** `TCPServer` is the sole authority for presence.
*   **Atomic Transitions:** Database `is_online` status is updated only on the first login or last logout of a user's multi-device session.

### 3.3 Multi-Device Synchronization
*   **Authoritative Sync:** Any write operation on one device results in an `EVENT` broadcast to all other active devices belonging to the same `user_id`.
*   **Routing Logic:** The originating handler (`H_orig`) is always excluded from the `EVENT` broadcast to prevent redundant UI updates.

---

## 4. Permission Matrix
| Action | Creator | Assignee | Non-Participant |
| :--- | :---: | :---: | :---: |
| **Read Task** | Yes | Yes | No |
| **Update Status** | Yes | Yes | No |
| **Update Details** | Yes | No | No |
| **Reassign Task** | Yes | No | No |
| **Delete Task** | Yes | No | No |

---

## 5. Task Event Matrix
Routing is computed using visibility set differences: `Δ = curr_visible - prev_visible`.

| Scenario | Requester (H_orig) | Other Devices (Self) | Peer(s) |
| :--- | :--- | :--- | :--- |
| **Create** | `CREATE_RESP` | `CREATED_EVENT` | `CREATED_EVENT` |
| **Update Title** | `UPDATE_RESP` | `UPDATED_EVENT` | `UPDATED_EVENT` |
| **Update Status** | `UPDATE_RESP` | `UPDATED_EVENT` | `UPDATED_EVENT` |
| **Reassign (B->C)** | `UPDATE_RESP` | `UPDATED_EVENT` | **B:** `DELETED_EVENT`<br>**C:** `CREATED_EVENT` |
| **Delete** | `DELETE_RESP` | `DELETED_EVENT` | `DELETED_EVENT` |

---

## 6. Known Limitations / Future Enhancements
*   **Intentionally Deferred:**
    *   **Group Tasks:** Visibility currently restricted to 1:1 (Creator/Assignee).
    *   **Packet Correlation:** Some request/response flows still rely on packet-type routing instead of strict requestId correlation. The current implementation is sufficient for Milestone 4 but may require correlation IDs for higher-concurrency scenarios.
    *   **Binary File Transfer:** Currently limited to metadata; raw file streams planned for Phase 6.
    *   **Offline Push:** Real-time sync depends on active TCP sessions; no APNS/FCM integration in Milestone 4.
    *   **Admins/Moderators:** No super-user role implemented in the current permission matrix.

---

## 7. Milestone 4 Achievements
* Authentication & Registration
* Contact Management
* Real-Time Chat
* Presence Tracking
* Task CRUD
* Role-Based Permissions
* User Resolution Cache
* Kanban Board
* Drag & Drop Task Workflow
* Multi-Device Session Management
* Real-Time Task Synchronization
* Visibility-Aware Event Routing
