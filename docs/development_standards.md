# Development Standards

## Code Style
- **Python**: Follow PEP 8. Use type hints where appropriate.
- **Dart**: Follow Official Dart Style Guide (Effective Dart).

## Networking
- Always use the defined 4-byte length prefix (Big-Endian).
- All JSON keys should be snake_case.
- Packet types must be uppercase (e.g., `AUTH_LOGIN`).

## Security
- **NEVER** store plain-text passwords.
- **NEVER** log sensitive user data or passwords.
- Use `chcp 65001` before running shell commands to ensure UTF-8 encoding.

## Workflow
- Research existing code before implementing.
- Use `replace` for surgical edits.
- Add tests or verification scripts for every new feature.
- Do not commit changes unless explicitly requested.

## Error Handling Standards
- **Server**: Use try-except blocks around networking and DB operations. Return structured `SYS_ERROR` packets to the client.
- **Client**: Implement error boundaries and catch exceptions in services. Display user-friendly messages for network or auth failures.
- **Protocol**: All failures must use the `SYS_ERROR` packet with appropriate status codes (400, 401, 403, 404, 500).

## Logging Standards
- Use a standard logging format: `[LEVEL] [COMPONENT] Message`.
- Log levels: `INFO` for general flow, `WARNING` for unexpected but non-fatal events, `ERROR` for failures.
- **Sensitive Data**: Strictly prohibit logging of passwords, tokens, or personal identifiable information (PII).

## Database Access Standards
- Use parameterized queries (placeholders) to prevent SQL injection.
- Close database connections/cursors immediately after use.
- Centralize database logic in dedicated service or helper modules.

## Testing Standards
- **Unit Tests**: Required for business logic (e.g., password hashing, packet parsing).
- **Integration Tests**: Verify client-server handshake and authentication flows.
- **Verification Scripts**: Provide standalone Python or Dart scripts to demonstrate feature functionality during audits.

## Documentation Standards
- **Code**: Use docstrings for all classes and public methods.
- **API/Protocol**: Keep `protocol.md` updated with every new packet type or field change.
- **Readability**: Maintain clear, concise comments for complex logic.

## Git Commit Conventions
- Format: `<type>(<scope>): <subject>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.
- Example: `feat(auth): implement password hashing with bcrypt`
- Always propose a draft commit message for user approval.

## Code Review Checklist
- [ ] Does the change adhere to the locked architecture?
- [ ] Is the framing (length-prefix) correctly implemented?
- [ ] Are passwords handled securely (hashed, no logs)?
- [ ] Are all JSON keys snake_case?
- [ ] Does it include verification/tests?
- [ ] Are database queries safe from injection?
- [ ] Does it follow the established implementation plan?
