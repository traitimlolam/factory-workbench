# Kiểm tra APK trên máy Android thật

Trong kho workbench, app mẫu tự viết được khai báo tại `SOURCES-MAU.json`. Xưởng chính chưa cho phép phôi này trong `data/sources.json` và chưa đăng ký bộ build tự giao. Bảng kiểm dưới đây dành cho chủ thử APK mẫu sau khi workflow trên emulator đạt.

## Chuẩn bị

1. Ghi tên phôi, nguồn và giấy phép từ `SOURCES-MAU.json`. Chỉ dùng `app-debug.apk` do chính workflow build từ mã mẫu; không dùng StorageCleaner_FOSS.apk hoặc StorageCleaner_Trial_1Hour.apk.
2. Ghi `Build.MODEL` từ **Cài đặt → Giới thiệu điện thoại → Số hiệu model**, bản Android và `SDK_INT` của máy thử. Chuẩn bị thêm máy có model khác.
3. Lưu kho khóa ngoài repo. Cấp đường dẫn và alias bằng `APK_KEYSTORE`, `APK_KS_ALIAS`; cấp mật khẩu bằng `APK_KS_PASS`, `APK_KEY_PASS` hoặc `APK_SIGNING_SECRET_FILE` có quyền `600`. Không chép mật khẩu vào lệnh, log hay phiếu thử.
4. Tạo bản trial và paid với `tools/lock_apk.py` trên runner hoặc máy thử đã cài Android build tools; lưu mã giấy phép, thời điểm build, mốc `valid_until` và mã băm SHA-256 của mỗi APK. Xác minh lại bằng `apksigner verify`.

## Thử từng trường hợp

| Trường hợp | Thao tác | Kết quả cần ghi |
|---|---|---|
| Đúng model, đúng SDK | Cài và mở bản trial trên máy đích | App chạy; ghi giờ mở lần đầu |
| Sai model | Cài trên máy model khác cùng SDK | Hiện “Bản này không dành cho thiết bị của bạn” rồi đóng |
| Sai SDK | Cài trên máy có SDK khác | Hiện thông báo và đóng |
| Hết 1 giờ | Mở lại sau hơn 3.600 giây từ `firstInstallTime` | Bị khóa |
| Xóa dữ liệu | Xóa dữ liệu app sau khi hết giờ, mở lại | Vẫn bị khóa |
| Cài lại quá mốc | Gỡ, cài lại sau `valid_until` | Vẫn bị khóa |
| Chỉnh đồng hồ lùi | Mở trial, lùi giờ thiết bị, mở lại | Bị khóa |
| Bản paid | Cài bản paid đúng model/SDK; thử lại sau 1 giờ và qua ngày | Vẫn chạy; sai model/SDK vẫn bị khóa |

Ghi cho mỗi hàng: ngày giờ Việt Nam, model, SDK, mã giấy phép, mã băm APK, kết quả thực tế, ảnh/video bằng chứng, tên người xác nhận. Nếu bất kỳ hàng nào thất bại hoặc chưa thử, **không** ghi `kiem_chung: true` vào `data/verified_builders.json` và không cho tự giao.
