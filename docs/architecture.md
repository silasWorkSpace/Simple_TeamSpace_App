# Architecture Design

## Implemented Architecture (Milestone 2)

### Server Components (Python)
- **TCP Server**: Manages incoming socket connections and threading. Maintains `active_sessions` registry.
- **ClientHandler**: Manages protocol framing (4-byte length-prefix) and packet routing.
- **Authentication Service**: Business logic for registration and login using `bcrypt`.
- **SQLite Storage**: Persistent data storage using a lightweight access pattern.

### Client Components (Flutter)
- **Flutter Network Layer**: `TcpClient` for managed socket communication and buffering.
- **Authentication Service (Dart)**: Networking logic for auth packets with request-response correlation.
- **Authentication UI**: Login and Register screens with state-driven feedback.

---

## Planned Architecture (Future Work)
- **Chat Service**: Real-time messaging and notification routing (Planned for M3).
- **Task/Kanban Service**: Task lifecycle and assignment management (Planned for M4).
- **File Service**: Binary data transport and storage management (Planned for M5).
- **Voice/Call Service**: Call signaling and media transport (Planned for M5).
