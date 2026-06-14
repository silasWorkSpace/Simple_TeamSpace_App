# Protocol Specification

## Version: 1.0 (Milestone 2 Baseline)

## Packet Framing
All packets sent over TCP must follow this format:
1. **Header**: 4 bytes, unsigned integer (Big-Endian), representing the length of the payload.
2. **Payload**: UTF-8 encoded JSON string of the specified length.

## Base JSON Structure
```json
{
  "v": "1.0",
  "id": "packet-unique-id",
  "type": "PACKET_TYPE",
  "data": { ... }
}
```

## Request-Response Correlation
- Response packets **MUST** preserve the original request `id`.
- System-initiated packets use "system" as the `id`.

## Implemented Packet Types

### System
- `SYS_PING`: Connectivity check.
- `SYS_PONG`: Response to `SYS_PING`.
- `SYS_ERROR`: Failure response.
  - Data: 
    ```json
    {
      "code": 400,
      "message": "Error description"
    }
    ```
  - **Error Codes**:
    - `400`: Bad Request (malformed JSON, missing fields).
    - `401`: Unauthorized (failed login, invalid credentials).
    - `403`: Forbidden (access denied).
    - `404`: Not Found.
    - `500`: Internal Server Error.

### Authentication (Implemented & Verified in Milestone 2)
- `AUTH_REGISTER`: Registration request.
  - Data: `{"phone": "...", "password": "...", "display_name": "..."}`
- `AUTH_LOGIN`: Login request.
  - Data: `{"phone": "...", "password": "..."}`
- `AUTH_SUCCESS`: Successful auth response.
  - Data: `{"user_id": 1, "display_name": "...", "phone": "..."}`

## Authentication Failure Handling
- All authentication failures MUST use the `SYS_ERROR` packet.
- Do not use separate `AUTH_FAILED` or `LOGIN_FAILED` packet types.
- Example: A failed login due to wrong password returns `SYS_ERROR` with code `401`.

## Future Packet Types (Proposals)
- `CHAT_SEND`: Send a message.
- `CHAT_RECEIVE`: Incoming message notification.
### Tasks (Milestone 4)

- `TASK_CREATE`: Create a new task.
  - Data: `{"title": "...", "description": "...", "assignee_id": null}`
- `TASK_CREATE_RESP`:
  - Data: `{"task_id": 1, "status": "TODO"}`

- `TASK_UPDATE`: Update task status or details.
  - Data: `{"task_id": 1, "status": "DOING", "title": "...", "description": "...", "assignee_id": null}`
- `TASK_UPDATE_RESP`:
  - Data: `{"task_id": 1}`

- `TASK_DELETE`: Remove a task.
  - Data: `{"task_id": 1}`
- `TASK_DELETE_RESP`:
  - Data: `{"task_id": 1}`

- `TASK_LIST_REQ`: Request tasks visible to the user.
  - Data: `{}`
- `TASK_LIST_RESP`: Response with task list.
  - Data: `{"tasks": [{"id": 1, "title": "...", "status": "TODO", "creator_id": 1, "assignee_id": null, "completed_at": null, ...}]}`

### User Discovery (Milestone 4 Phase 3)

- `USER_SEARCH_REQ`: Search for users by name or phone.
  - Data: `{"query": "..."}`
- `USER_SEARCH_RESP`: Search results.
  - Data: `{"users": [{"id": 1, "display_name": "..."}]}`

**Permissions Matrix**:
- **Creator**: Can update `title`, `description`, `assignee_id`, `status`. Can `DELETE`.
- **Assignee**: Can ONLY update `status`. Cannot `DELETE`.
- **Uninvolved**: No access (Filtered by `TASK_LIST_REQ` and server validation).
