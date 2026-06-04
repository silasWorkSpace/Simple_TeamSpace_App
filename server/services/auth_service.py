import bcrypt
from storage import database

class AuthService:
    """Handles user registration and login logic with bcrypt hashing."""

    @staticmethod
    def register(phone, password, display_name):
        """
        Hashes password and creates a new user.
        Returns (True, user_dict) on success, (False, error_code) on failure.
        """
        # 1. Check if user already exists
        if database.get_user_by_phone(phone):
            return False, 400  # Bad Request - User exists

        # 2. Hash password
        salt = bcrypt.gensalt()
        password_hash = bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

        # 3. Create user
        user_id = database.create_user(phone, password_hash, display_name)
        if user_id:
            # Update online status (Auto-login)
            database.update_online_status(user_id, True)
            user = {
                "user_id": user_id,
                "phone": phone,
                "display_name": display_name
            }
            return True, user
        
        return False, 500

    @staticmethod
    def login(phone, password):
        """
        Verifies credentials and logs in the user.
        Returns (True, user_dict) on success, (False, error_code) on failure.
        """
        user_row = database.get_user_by_phone(phone)
        if not user_row:
            return False, 401  # Unauthorized

        stored_hash = user_row['password_hash']
        
        # Verify password
        if bcrypt.checkpw(password.encode('utf-8'), stored_hash.encode('utf-8')):
            user_id = user_row['id']
            database.update_online_status(user_id, True)
            user = {
                "user_id": user_id,
                "phone": user_row['phone'],
                "display_name": user_row['display_name']
            }
            return True, user
        
        return False, 401
