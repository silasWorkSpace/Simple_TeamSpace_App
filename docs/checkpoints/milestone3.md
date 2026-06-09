# Milestone 3 Checkpoint Report

## 1. Current Architecture

### Client Services
*   **`TcpClient`**: Core networking layer handling persistent socket connections, fragmented packet assembly (4-byte length prefix), and a global broadcast stream for incoming packets.
*   **`AuthService`**: Manages `AUTH_REGISTER` and `AUTH_LOGIN` requests, awaiting specific response IDs via the packet stream.
*   **`ChatService`**: Handles dispatching of chat-related packets (`CHAT_SEND`, `CHAT_HIST_REQ`, `CHAT_LIST_REQ`) and exposes a filtered broadcast stream for chat-specific and user presence events.

### Controllers
*   **`AuthController`**: Application-level session state management.
*   **`ChatController`**: The reactive, single source of truth for messaging state. Manages in-memory message history (chronological), conversation tracking, peer metadata, online status, and handles deduplication via `server_msg_id`. Injected dynamically via `ChangeNotifierProxyProvider` to react to user context changes.

### Views Completed
*   **Shell**: `MainLayout`, `ChatTab`.
*   **Chat Core**: `ConversationScreen`, `ChatInput` (with `FocusNode` and keyboard submit wiring), `MessageBubble`, `ConversationTile`.
*   **Auth**: `LoginScreen`, `RegisterScreen`.

---

## 2. Chat Features Verified Working
*   **Login/Register**: Full end-to-end TCP auth flow with payload parsing.
*   **Logout/Re-login**: State clearance and socket disconnection without crashing the app or permanently closing the listener stream.
*   **`CHAT_SEND`**: Optimistic UI updates with a 10-second timeout/error mechanism.
*   **`CHAT_RECEIVE`**: Real-time incoming messages with automatic server ACK responses (`CHAT_RECEIVED`).
*   **`CHAT_HIST_REQ`**: Requesting paginated history natively populated into the `ConversationScreen` (reverse ListView).
*   **`CHAT_LIST_REQ`**: Loading active conversation summaries.
*   **Conversation Restoration**: Automatic fetching of `CHAT_LIST_REQ` upon a successful login or app hot restart.

---

## 3. Bugs Fixed
*   **`CHAT_LIST_REQ` Dispatch Missing / Initialization Lifecycle Issue**: Fixed an architectural flaw where `ChatController` was bypassing initial data fetching. `currentUserId` was removed from the constructor to ensure `updateCurrentUser` acts as the definitive, single source of truth for session transitions.
*   **`TcpClient` Logout Stream Issue**: Fixed a destructive teardown where `logout()` was calling `dispose()`, permanently killing the underlying `StreamController.broadcast()`. Replaced with a non-destructive `disconnect()` method that only destroys the TCP `Socket`.

---

## 4. Current Temporary Limitations
*   **New Chat Creation**: Currently utilizes a manual, numeric "User ID" entry dialog via a Floating Action Button in `ChatTab`.
*   **`USER_LIST_REQ`**: Not implemented in the protocol or server.
*   **`USER_SEARCH_REQ`**: Not implemented in the protocol or server, preventing phone-number-based user discovery.

---

## 5. Remaining Milestones
*   **Milestone 4**: Task/Kanban service integration.
*   **Milestone 5**: File transfer implementation (binary chunking and transport).
*   **Milestone 6**: Voice signaling (media negotiation over TCP/UDP).

---

## 6. Files Modified During Milestone 3
*   `client/lib/main.dart`
*   `client/lib/network/tcp_client.dart`
*   `client/lib/services/chat_service.dart`
*   `client/lib/controllers/auth_controller.dart`
*   `client/lib/controllers/chat_controller.dart`
*   `client/lib/views/chat/chat_tab.dart`
*   `client/lib/views/chat/conversation_screen.dart` (New)
*   `client/lib/views/chat/widgets/chat_input.dart` (New)

---

## 7. Known Warnings Remaining (`flutter analyze`)
*   `unused_local_variable`: The value of the local variable `serverId` isn't used (`lib/controllers/chat_controller.dart:206`).
*   `unused_import`: Unused import `UserModel` (`lib/network/packet_parser.dart:2`).
*   `unused_import`: Unused import `foundation.dart` (`lib/services/auth_service.dart:2`).