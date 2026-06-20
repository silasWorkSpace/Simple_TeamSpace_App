from storage import database
from core.tcp_server import TCPServer
from core.data_server import DataServer
from services.file_service import FileService
from services.chat_service import ChatService

def main():
    print("="*40)
    print("SERVER STARTING...")
    print("="*40)

    # 1. Initialize DB tables and run orphan cleanup
    database.init_db()
    FileService.startup_cleanup()

    # 2. Start JSON signaling server (primary)
    tcp_server = TCPServer()

    # 3. Wire upload completion: file_service -> chat_service -> tcp_server routing
    def on_upload_complete(token, uploader_id, uploader_display_name,
                           receiver_id, filename, size_bytes):
        ChatService.handle_file_complete(
            server=tcp_server,
            token=token,
            uploader_id=uploader_id,
            uploader_display_name=uploader_display_name,
            receiver_id=receiver_id,
            filename=filename,
            size_bytes=size_bytes,
        )

    FileService.set_completion_callback(on_upload_complete)

    # 4. Start binary data server (secondary)
    data_server = DataServer(
        on_upload_complete_callback=FileService.on_binary_upload_complete,
        get_file_path_callback=FileService.get_file_path,
        get_expected_size_callback=FileService.get_expected_size,
    )
    data_server.start()

    # 5. Start primary TCP server (blocking)
    tcp_server.start()

if __name__ == "__main__":
    main()
