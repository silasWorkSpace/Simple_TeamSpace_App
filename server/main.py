from storage import database
from core.tcp_server import TCPServer

def main():
    print("="*40)
    print("SERVER STARTING (Milestone 2)...")
    print("="*40)
    
    database.init_db()
    server = TCPServer()
    server.start()

if __name__ == "__main__":
    main()
