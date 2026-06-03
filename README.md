last_project/
│
├──server/                             # --- MÃ NGUỒN PHÍA SERVER (PYTHON) ---
│   ├── main.py                        # Điểm khởi chạy hệ thống Server
│   ├── config.py                      # Cấu hình IP, Port, Database String
│   │
│   ├── core/                          # Thư mục chứa xử lý lõi của mạng
│   │   ├── __init__.py
│   │   ├── tcp_server.py              # Lắng nghe TCP, quản lý đa luồng kết nối
│   │   ├── udp_server.py              # Xử lý luồng gọi thoại/video (nếu làm dạng Relay)
│   │   └── client_handler.py          # Logic đọc/ghi và phân tích gói tin JSON từ Client
│   │
│   ├── services/                      # Nghiệp vụ xử lý logic ứng dụng
│   │   ├── chat_service.py            # Xử lý chuyển tiếp tin nhắn, lưu lịch sử chat
│   │   ├── task_service.py            # Xử lý cập nhật trạng thái Kanban board
│   │   ├── file_service.py            # Xử lý upload/download lưu file vật lý
│   │   └── notification_bot.py        # Luồng chạy ngầm quét deadline và tự động bắn tin nhắn
│   │
│   ├── storage/                       # Nơi lưu trữ dữ liệu của Server
│   │   ├── database.db                # File SQLite lưu tài khoản, tin nhắn, thông tin task
│   │   └── uploaded_files/            # Thư mục vật lý lưu trữ các file client tải lên
│   │
│   └── assets/                        # Tài nguyên cố định hệ thống
│       └── stickers/                  # Bản sao các file ảnh Sticker để đối chiếu nếu cần
│
└──client/                             # --- MÃ NGUỒN PHÍA CLIENT GUI (FLUTTER) ---
    ├── pubspec.yaml                   # Khai báo thư viện (thêm thư viện socket, camera, webrtc)
    ├── assets/
    │   ├── images/                    # Logo, hình ảnh nền ứng dụng
    │   └── stickers/                  # BỘ STICKER IPHONE (Lưu sẵn local để render bằng ID)
    │       ├── apple_laugh.png
    │       └── apple_cry.png
    │
    └── lib/                           # Mã nguồn chính Dart
        ├── main.dart                  # Điểm khởi chạy ứng dụng Client
        │
        ├── network/                   # Tầng giao tiếp mạng (Socket Wrapper)
        │   ├── tcp_client.dart        # Quản lý kết nối TCP Socket, lắng nghe tin nhắn từ Server
        │   ├── udp_client.dart        # Quản lý Socket UDP truyền nhận voice/video stream
        │   └── packet_parser.dart     # Chuyển đổi qua lại giữa Object và chuỗi JSON mạng
        │
        ├── models/                    # Khai báo các cấu trúc dữ liệu (Data Objects)
        │   ├── user_model.dart        # Định nghĩa thuộc tính User (id, name, status)
        │   ├── message_model.dart     # Định nghĩa thuộc tính Tin nhắn (text, emoji, sticker_id)
        │   └── task_model.dart        # Định nghĩa thuộc tính Task (title, assignee, deadline, status)
        │
        ├── views/                     # Tầng giao diện người dùng (GUI - UI Screens)
        │   ├── auth/
        │   │   └── login_screen.dart  # Màn hình đăng nhập / cấu hình IP Server
        │   ├── home/
        │   │   └── main_layout.dart   # Khung điều hướng chính (Chứa thanh Tab bar chuyển đổi)
        │   ├── chat/
        │   │   ├── chat_tab.dart      # Giao diện phòng chat, danh sách kênh
        │   │   ├── widgets/
        │   │   │   ├── emoji_picker.dart   # Bảng chọn Emoji tích hợp trong dòng text
        │   │   │   └── sticker_picker.dart # Bảng lưới chọn sticker lớn kiểu iPhone
        │   ├── tasks/
        │   │   └── kanban_tab.dart    # Giao diện bảng công việc chia cột kéo thả
        │   ├── files/
        │   │   └── storage_tab.dart   # Giao diện danh sách file và nút bấm upload
        │   └── call/
        │       └── call_overlay.dart  # Giao diện cuộc gọi thoại/video (gồm lưới video, nút tắt mic)
        │
        └── controllers/               # Tầng điều khiển (Quản lý trạng thái giao diện)
            ├── chat_controller.dart   # Nhận tin nhắn từ tầng network và đẩy ra màn hình chat
            ├── task_controller.dart   # Xử lý thay đổi vị trí thẻ và thông báo cho tầng network
            └─  call_controller.dart   # Xử lý bật/tắt thiết bị camera, micro và luồng UDP