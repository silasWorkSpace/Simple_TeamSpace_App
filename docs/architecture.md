# Architecture Design

## System Overview
The project is a client-server application for communication and task management. It utilizes a custom TCP-based protocol for reliable data exchange and SQLite for persistent storage.

## Components
### Server (Python)
- **TCP Server**: Handles incoming socket connections and manages threading.
- **Client Handler**: Manages individual client lifecycles, protocol framing (length-prefix), and packet routing.
- **Services**: Business logic for Authentication, Chat, Tasks, and Files.
- **Storage**: SQLite database for user data and metadata.

### Client (Flutter)
- **Network Layer**: `TcpClient` manages the socket connection and packet buffering.
- **Controllers**: Handle UI logic and communicate with the networking layer.
- **Views**: Flutter widgets for the user interface.

## Communication
- **Transport**: TCP for all control and data packets.
- **Framing**: 4-byte length prefix (Big-Endian) followed by a UTF-8 encoded JSON payload.
- **UDP**: For real-time voice calling (Planned for Milestone 5).
