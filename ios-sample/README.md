# Factory Sample

Tweak Theos tự viết, chỉ móc `SpringBoard` lúc khởi động để ghi log và hiện thông báo. Chọn `rootless` vì dữ liệu tương thích của xưởng ghi Dopamine/palera1n là `rootless`; gói đặt mã dưới `/var/jb`. RootHide có thể cần gói và phép thử riêng, chưa được xác nhận tương thích. Trạng thái lần chạy đầu lưu trong thư mục Application Support của tài khoản SpringBoard (`/var/mobile`), tách khỏi vùng hệ thống và dùng được với rootless. Nếu không đọc/ghi được hoặc không lấy được UDID từ MobileGestalt, tweak chặn hoạt động.

Khóa cục bộ trong gói public không chống được người dùng cố ý sửa binary hay xóa dữ liệu; cần kiểm trên iPhone jailbreak thật trước khi chứng nhận và giao khách.
