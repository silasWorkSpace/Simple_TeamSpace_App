# Implementation Plan - Milestone 2

## Approved Goals
1. Implement User Registration (`AUTH_REGISTER`).
2. Implement User Login (`AUTH_LOGIN`).
3. Implement Password Hashing for all stored credentials.
4. Implement Session Mapping (linking active TCP connections to `user_id`).
5. Handle `AUTH_SUCCESS` and `SYS_ERROR` responses.
6. Create Authentication UI (Login and Registration screens).

## Technical Proposals (Pending Approval)
*Note: These are suggested implementation details and are not yet approved design decisions.*

- **Hashing**: Use `bcrypt` for secure password hashing and verification.
- **Server Organization**: 
  - Centralize database operations in a `server/storage/database.py` helper.
  - Create an `AuthService` in `server/services/auth_service.py` to handle logic.
- **Client Organization**:
  - Implement an `AuthService` in `client/lib/services/auth_service.dart`.
  - Use a `ChangeNotifier` or similar pattern for managing user session state in the Flutter app.

## Implementation Order
1. **Server-side Logic**: Implement hashing, database lookups/inserts, and packet handlers.
2. **Server-side Session Tracking**: Update `TCPServer` or `ClientHandler` to maintain the `user_id` context.
3. **Client-side Service**: Implement packet sending and response parsing for Auth types.
4. **Client-side UI**: Build the Login and Registration screens and hook them to the service.
5. **Verification**: End-to-end testing of the registration and login flows.
