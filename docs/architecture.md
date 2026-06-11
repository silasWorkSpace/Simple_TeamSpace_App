# Architecture Design

## Implemented Architecture (Milestone 3)

### Server Components (Python)
- **TCP Server**: Manages incoming socket connections and threading. Maintains `active_sessions` registry.
- **ClientHandler**: Manages protocol framing (4-byte length-prefix) and packet routing.
- **Authentication Service**: Business logic for registration and login using `bcrypt`.
- **Chat Service**: Real-time messaging, notification routing, and history persistence.
- **SQLite Storage**: Persistent data storage using a lightweight access pattern.

### Client Components (Flutter)
- **Flutter Network Layer**: `TcpClient` for managed socket communication and buffering.
- **Authentication Service**: Networking logic for auth packets with request-response correlation.
- **Chat Service**: Packet handling for SEND/RECEIVE/LIST/HIST.
- **State Management**: `AuthController` and `ChatController`.
- **UI Components**: Login/Register screens, Chat Tab, Conversation Screen.

---

## Under Development (Milestone 4)
- **Task/Kanban Service**: Task lifecycle and assignment management.

## Planned Architecture (Future Work)
- **File Service**: Binary data transport and storage management (Planned for M5).
- **Voice/Call Service**: Call signaling and media transport (Planned for M5).
