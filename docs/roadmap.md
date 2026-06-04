# Project Roadmap

## Milestone 1: Connectivity (Approved)
- [x] TCP Server implementation with threading.
- [x] TCP Client implementation in Flutter.
- [x] Packet framing (4-byte length prefix).
- [x] Basic SYS_PING/SYS_PONG heartbeat.
- [x] Initial database schema.

## Milestone 2: Authentication (Current)
- [ ] Password hashing.
- [ ] User Registration (`AUTH_REGISTER`).
- [ ] User Login (`AUTH_LOGIN`).
- [ ] Session Mapping (tracking online users).
- [ ] AUTH_SUCCESS and SYS_ERROR packet handling.
- [ ] Authentication UI (Login/Register screens).

## Milestone 3: Chat (Future)
- [ ] Private chat functionality.
- [ ] Message persistence.
- [ ] Online status indicators.

## Milestone 4: Kanban (Future)
- [ ] Task creation, assignment, and status updates.

## Milestone 5: File Storage + Voice Calling (Future)
- [ ] File upload/download via TCP.
- [ ] Real-time voice calling.
- [ ] Call signaling and connection management.
- [ ] Media transport architecture to be finalized during implementation.
