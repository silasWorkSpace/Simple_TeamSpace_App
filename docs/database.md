# Database Specification

## Database Engine: SQLite
- **Path**: `server/storage/database.db`

## Schema

### Table: `users`
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Unique user identifier |
| `phone` | TEXT | UNIQUE, NOT NULL | User's phone number (login ID) |
| `password_hash` | TEXT | NOT NULL | Hashed password |
| `display_name` | TEXT | NOT NULL | User's visible name |
| `is_online` | INTEGER | DEFAULT 0 | 1 if online, 0 otherwise |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Account creation time |

### Table: `messages`
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Message ID |
| `sender_id` | INTEGER | NOT NULL, FK(users.id) | ID of the sender |
| `receiver_id` | INTEGER | NOT NULL, FK(users.id) | ID of the receiver |
| `content` | TEXT | NOT NULL | Message body |
| `msg_type` | TEXT | NOT NULL | Type (text, image, etc.) |
| `is_read` | INTEGER | DEFAULT 0 | Read status |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Timestamp |

### Table: `tasks`
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | Task ID |
| `title` | TEXT | NOT NULL | Task title |
| `description` | TEXT | | Detailed description |
| `status` | TEXT | NOT NULL | e.g., 'todo', 'doing', 'done' |
| `creator_id` | INTEGER | NOT NULL, FK(users.id) | Task creator |
| `assignee_id` | INTEGER | FK(users.id) | Assigned user |
| `updated_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Last update |

### Table: `files`
| Column | Type | Constraints | Description |
| --- | --- | --- | --- |
| `id` | INTEGER | PRIMARY KEY, AUTOINCREMENT | File ID |
| `filename` | TEXT | NOT NULL | Original filename |
| `local_path` | TEXT | NOT NULL | Storage path on server |
| `file_size` | INTEGER | NOT NULL | Size in bytes |
| `uploader_id` | INTEGER | NOT NULL, FK(users.id) | User who uploaded |
| `created_at` | DATETIME | DEFAULT CURRENT_TIMESTAMP | Upload timestamp |

## Relationships
- `messages.sender_id` -> `users.id`
- `messages.receiver_id` -> `users.id`
- `tasks.creator_id` -> `users.id`
- `tasks.assignee_id` -> `users.id`
- `files.uploader_id` -> `users.id`

## Foreign Key Policy
- All foreign keys must use `ON DELETE CASCADE` or `ON DELETE SET NULL` as appropriate to maintain referential integrity.
- Constraints must be explicitly checked (SQLite requires `PRAGMA foreign_keys = ON;`).

## Indexing Strategy
- **Users**: Unique index on `phone` (created by `UNIQUE` constraint).
- **Messages**: 
  - Composite index on `(sender_id, receiver_id)` for conversation lookups.
  - Index on `created_at` for efficient timestamp ordering.
- **Tasks**:
  - Index on `status` for task status filtering.
  - Index on `assignee_id` for user-specific task lists.

## Indexes
- `idx_users_phone`: `ON users(phone)`
- `idx_messages_conversation`: `ON messages(sender_id, receiver_id)`
- `idx_messages_timestamp`: `ON messages(created_at)`
- `idx_tasks_status`: `ON tasks(status)`
- `idx_tasks_assignee`: `ON tasks(assignee_id)`
