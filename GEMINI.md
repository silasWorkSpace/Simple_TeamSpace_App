# AI Operating Constitution (GEMINI.md)

## Current Milestone: Milestone 2 (Authentication)

## Locked Design Items
The following items are frozen. Modifications require explicit user authorization.
- **Architecture**: TCP Client-Server with threaded handler. 4-byte Big-Endian length-prefix framing.
- **Protocol**: JSON-based packets with `v`, `id`, `type`, and `data` fields. (Defined in `protocol.md`).
- **Database**: SQLite schema with tables: `users`, `messages`, `tasks`, `files`. (Defined in `database.md`).

## Implementation Constraints
- **Scope**: Only Milestone 2 features (Login, Register, Hashing, Session Mapping).
- **Forbidden**: Do not modify Chat, Kanban, File Storage, or Voice Calling logic.
- **Abstractions**: Do not introduce new architectural patterns (Repositories, Clean Architecture, etc.) unless proposed in `implementation_plan.md` and approved.

## Workflow Rules
1. **Research First**: Always use `read_file` and `grep_search` before implementing.
2. **Surgical Edits**: Prefer `replace` over `write_file` for existing files.
3. **Audit Requirement**: Any implementation must be followed by an audit of modified files and verification results.
4. **No Unprompted Commits**: Never use `git commit` or `git add` unless explicitly directed.

## Approval Workflow
1. Propose implementation details in `implementation_plan.md` (marked as Proposals).
2. Wait for user approval before proceeding.
3. After implementation, provide a full audit of changes and wait for approval before moving to the next task.

## Future AI Session Rules
- This file (`GEMINI.md`) must be loaded at the start of every session to restore context.
- All documentation files (`architecture.md`, `roadmap.md`, `protocol.md`, `database.md`) are source-of-truth.
