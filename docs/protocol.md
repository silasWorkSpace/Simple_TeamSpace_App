# Protocol Specification

## Version: 1.0

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
- Response packets MUST preserve the original request `id` when responding to a specific client request.
- System-initiated packets (e.g., notifications) may use "system" as the `id`.

## Packet Types

### System
- `SYS_PING`: Sent by client or server to check connectivity.
- `SYS_PONG`: Response to `SYS_PING`.
- `SYS_ERROR`: Sent by server when a request fails.
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

### Authentication (Milestone 2)
- `AUTH_REGISTER`: Client request to create a new account.
  - Data: `{"phone": "...", "password": "...", "display_name": "..."}`
- `AUTH_LOGIN`: Client request to log in.
  - Data: `{"phone": "...", "password": "..."}`
- `AUTH_SUCCESS`: Server response for successful login/registration.
  - Data: `{"user_id": 1, "display_name": "...", "phone": "..."}`

## Authentication Failure Handling
- All authentication failures MUST use the `SYS_ERROR` packet.
- Do not use separate `AUTH_FAILED` or `LOGIN_FAILED` packet types.
- Example: A failed login due to wrong password returns `SYS_ERROR` with code `401`.
