# Database Specification

## Database Engine: SQLite
- **Path**: `server/storage/database.db`
- **Access Pattern**: Lightweight Open-Execute-Close (No pooling).

## Implemented Schema (Milestone 2)

### Table: `users` (Implemented)
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Unique ID |
| `phone` | TEXT | UNIQUE, NOT NULL | Login ID |
| `password_hash` | TEXT | NOT NULL | bcrypt hash |
| `display_name` | TEXT | NOT NULL | Visible name |
| `is_online` | INTEGER | DEFAULT 0 | 1 if online |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Timestamp |

### Indexes (Implemented)
- `idx_users_phone`: `ON users(phone)`

---

## Planned Schema (Future Work)

### Table: `messages` (Planned)
- `id`, `sender_id`, `receiver_id`, `content`, `msg_type`, `is_read`, `created_at`

### Table: `tasks` (Planned)
- `id`, `title`, `description`, `status`, `creator_id`, `assignee_id`, `updated_at`

### Table: `files` (Planned)
- `id`, `filename`, `local_path`, `file_size`, `uploader_id`, `created_at`

### Indexes (Planned)
- `idx_messages_conversation`: `ON messages(sender_id, receiver_id)`
- `idx_messages_timestamp`: `ON messages(created_at)`
- `idx_tasks_status`: `ON tasks(status)`
- `idx_tasks_assignee`: `ON tasks(assignee_id)`
