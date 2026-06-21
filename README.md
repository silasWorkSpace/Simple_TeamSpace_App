# Project Overview

This repository contains a high-performance, real-time collaboration platform designed to seamlessly integrate instant messaging with structured task management. The system bypasses traditional HTTP/REST overhead by utilizing a custom persistent TCP socket architecture, ensuring sub-100ms latency and instantaneous state synchronization across all connected clients.

### Technology Stack
* **Client:** Flutter / Dart
* **Server:** Python (Raw TCP `socketserver`)
* **Database:** SQLite
* **Protocol:** Custom JSON-encoded, length-prefixed TCP Socket multiplexing

# Features

* Authentication
* Direct Messaging
* Public Channels
* Private Channels
* Channel Roles (Owner/Admin/Member)
* File Transfer
* Image Sharing
* Voice Messages
* Stickers
* Kanban Task Board
* Task Assignment
* Activity Logs
* Real-time Synchronization

# System Architecture

The system operates on a highly decoupled dual-server model to ensure chat messaging remains perfectly synchronized and unblocked, even during large file uploads.

```text
Client (Flutter)
       ↓
[ TCP Signaling Server (Port 5000) ] ↔ [ SQLite Database ]
       ↓
[ Binary Data Server (Port 5001) ] 
```

**Why Separate Ports?**
The TCP Signaling Server handles lightweight JSON packets sequentially. If a user uploads a 50MB file on the same thread, it would block the socket buffer, causing all other users' chat messages to queue up and lag. Separating binary traffic to a dedicated port and chunking the data ensures chat signaling remains instant even under heavy media transfer loads.

# Project Structure

```text
server/
├── main.py
├── config.py
├── core/
├── services/
├── storage/
└── assets/

client/
├── lib/
├── assets/
├── android/
├── windows/
├── web/
└── pubspec.yaml
```

**Directory Responsibilities:**
* `server/main.py` & `config.py`: Core entrypoints and configuration bindings.
* `server/core/`: Contains the low-level TCP connection handlers and Binary server infrastructure.
* `server/services/`: Contains the business logic and routing for channels, chat, auth, and tasks.
* `server/storage/`: Houses the database schema and query executors.
* `server/assets/`: Stores server-provided static assets (like stickers).
* `client/lib/`: Contains the entire Flutter frontend, state management, and UI logic.
* `client/pubspec.yaml`: Defines Flutter dependencies and local assets.

# Requirements

* **Python:** 3.10+
* **Flutter:** 3.19.0+
* **Dart:** 3.3.0+

# Setup Instructions

## Server

1. Navigate to the server directory.
2. The server relies on Python's built-in standard libraries, so external dependencies are minimal.
3. Run the server entrypoint:

```bash
cd server
python main.py
```

## Client

1. Navigate to the client directory.
2. Resolve Flutter dependencies.
3. Run the application on your preferred platform (Windows, macOS, Linux, Web, Android, iOS):

```bash
cd client
flutter clean
flutter pub get
flutter run -d windows
```

# Database

The backend utilizes SQLite for zero-configuration, atomic persistence. The database is automatically created on the first startup through the `init_db()` function. **No manual SQL setup is required.** The server will seamlessly bootstrap all necessary tables upon initialization.

# Demo Accounts

If no default accounts exist in your environment, users can easily self-register directly from the Flutter login screen. The database will safely track and persist new accounts across restarts.

# Known Limitations

* Voice/Video Call not implemented
* Ownership transfer UI not implemented
* Voice playback requires local device audio hardware

# Authors

* [silas]
