import os
import sys

# Setup path so we can import the server module
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../server')))
from storage import database

def test_cascade_delete():
    print("Testing ON DELETE CASCADE for task_comments...")
    database.init_db()

    # 1. Create a dummy user
    u_id = database.create_user("cascade_test_phone", "password123", "Cascade Tester")
    if not u_id:
        u_id = database.get_user_by_phone("cascade_test_phone")['id']

    # 2. Create a task
    task = database.create_task("Task to Delete", "Testing CASCADE", u_id)
    t_id = task['id']

    # 3. Create a comment on the task
    comment = database.create_comment(t_id, u_id, "This comment should be deleted automatically.")
    c_id = comment['id']

    # Verify the comment exists
    conn = database.get_connection()
    c = conn.execute("SELECT * FROM task_comments WHERE id = ?", (c_id,)).fetchone()
    assert c is not None, "Comment was not inserted!"

    # 4. Delete the task
    success = database.delete_task(t_id)
    assert success, "Task deletion failed"

    # 5. Verify the comment is gone
    c = conn.execute("SELECT * FROM task_comments WHERE id = ?", (c_id,)).fetchone()
    assert c is None, f"CASCADE FAILED! Comment {c_id} still exists for deleted task {t_id}."

    print("SUCCESS: ON DELETE CASCADE is working correctly.")

if __name__ == "__main__":
    test_cascade_delete()
