# Database Specification

## Database Engine: SQLite
- **Path**: `server/storage/database.db`
- **Access Pattern**: Lightweight Open-Execute-Close (No pooling).

## Implemented Schema (Milestone 3 Baseline)

### Table: `users` (Implemented)
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Unique ID |
| `phone` | TEXT | UNIQUE, NOT NULL | Login ID |
| `password_hash` | TEXT | NOT NULL | bcrypt hash |
| `display_name` | TEXT | NOT NULL | Visible name |
| `is_online` | INTEGER | DEFAULT 0 | 1 if online |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Timestamp |

### Table: `messages` (Implemented)
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Unique ID |
| `sender_id` | INTEGER | NOT NULL, FK(users.id) | Sender ID |
| `receiver_id` | INTEGER | NOT NULL, FK(users.id) | Receiver ID |
| `content` | TEXT | NOT NULL | Message content |
| `msg_type` | TEXT | DEFAULT 'text' | 'text', 'image', 'file', 'sticker' |
| `is_read` | INTEGER | DEFAULT 0 | 1 if read |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Timestamp |

### Indexes (Implemented)
- `idx_users_phone`: `ON users(phone)`
- `idx_messages_conversation`: `ON messages(sender_id, receiver_id)`
- `idx_messages_timestamp`: `ON messages(created_at)`

---

## Planned Schema (Milestone 4)

### Table: `tasks` (Planned - Milestone 4)
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Unique ID |
| `title` | TEXT | NOT NULL | Task title |
| `description` | TEXT | | Optional details |
| `status` | TEXT | DEFAULT 'TODO' | 'TODO', 'DOING', 'DONE' |
| `creator_id` | INTEGER | NOT NULL, FK(users.id) | Task creator |
| `assignee_id` | INTEGER | FK(users.id) | Optional assignee |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Created date |
| `updated_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Last modified |
| `completed_at` | DATETIME | | Timestamp when status set to DONE |

**Visibility Rule**: A task is only visible/accessible if `session_user_id` matches `creator_id` OR `assignee_id`.

**Query Behavior**:
- `TASK_LIST_REQ`: `SELECT * FROM tasks WHERE creator_id = ? OR assignee_id = ? ORDER BY updated_at DESC`

### Table: `files` (Planned)
- `id`, `filename`, `local_path`, `file_size`, `uploader_id`, `created_at`

### Indexes (Planned)
- `idx_messages_conversation`: `ON messages(sender_id, receiver_id)`
- `idx_messages_timestamp`: `ON messages(created_at)`
- `idx_tasks_status`: `ON tasks(status)`
- `idx_tasks_assignee`: `ON tasks(assignee_id)`
