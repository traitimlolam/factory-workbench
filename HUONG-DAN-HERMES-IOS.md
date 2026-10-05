# Hướng dẫn Hermes kiểm đường build iOS

Tài liệu này chỉ dành cho kho xưởng thử public `traitimlolam/factory-workbench`. Không thao tác trên Singapore, server-agent hoặc môi trường triển khai. Không cần tạo PAT mới: dùng phiên đăng nhập GitHub hiện có đã được chủ cấu hình cho kho này, và không in token hay secret.

## 1. Đồng bộ gói workbench

Từ máy quản trị đã có quyền với kho, sao chép nội dung `deploy/workbench/` vào checkout của `traitimlolam/factory-workbench`, kiểm tra diff chỉ chứa tài sản workbench, rồi commit và push lên `main`. Không sao chép dữ liệu khách, file môi trường, artifact hoặc cấu hình thật. Giữ `verified_builders.sample.json` ở `kiem_chung: false`.

Các workflow iOS dùng `macos-14`, Theos và iPhoneOS 16.5 SDK được ghim bằng commit trong `tools/install_ios_toolchain.sh`. Artifact `.deb` được mã hóa bằng cùng định dạng của Android và chỉ lưu một ngày.

## 2. Chạy kiểm logic khóa một lần

```bash
set -euo pipefail
export WORKBENCH_REPO='traitimlolam/factory-workbench'
export VERIFY_RUN_URL="$(gh workflow run verify-ios-lock.yml --ref main -R "$WORKBENCH_REPO")"
export VERIFY_RUN_ID="${VERIFY_RUN_URL##*/}"
[[ "$VERIFY_RUN_ID" =~ ^[0-9]+$ ]]
gh run watch "$VERIFY_RUN_ID" -R "$WORKBENCH_REPO" --exit-status
export VERIFY_DIR="$(mktemp -d)"
gh run download "$VERIFY_RUN_ID" -R "$WORKBENCH_REPO" -n verify-ios-lock-result -D "$VERIFY_DIR"
jq . "$VERIFY_DIR/verify-ios-result.json"
jq -e '.moi_truong == "macos-14-clang" and (.cac_phep_thu | length) == 5 and (.cac_phep_thu | all(. == true)) and (.loi | length) == 0' "$VERIFY_DIR/verify-ios-result.json"
```

Hermes báo chủ URL run, mã run, SHA commit và kết quả của năm phép thử: đúng UDID, sai UDID, trial hết sau một giờ, đồng hồ bị chỉnh lùi và paid không hết hạn. Nếu workflow, artifact, JSON hoặc bất kỳ phép thử nào lỗi, báo rõ bước/lệnh trong trường `loi`; không đặt `kiem_chung: true`.

## 3. Giới hạn xác minh

Workflow này chỉ biên dịch và chạy hàm khóa thuần bằng `clang` trên macOS. Nó chưa cài `.deb` và chưa thử MobileGestalt, đường dẫn dữ liệu rootless, hook SpringBoard, respring, thông báo, Dopamine/palera1n hoặc RootHide trên iPhone jailbreak thật. Vì vậy kết quả macOS không phải chứng nhận máy thật. Chủ chỉ cập nhật chứng nhận sau khi thử riêng trên iPhone phù hợp và xác nhận không gây safe mode, bootloop hay kẹt khởi động.
