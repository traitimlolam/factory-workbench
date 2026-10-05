# Hướng dẫn dựng kho xưởng thử riêng tư

Chạy các lệnh dưới đây trên **máy quản trị**, trong Bash. Đây là hướng dẫn để chủ hoặc Hermes thực hiện sau khi chủ cho phép; việc tạo kho, đặt secret và sửa môi trường máy Mỹ **chưa được thực hiện** khi tạo gói này. Không chạy trên Singapore. Các lệnh không in PAT, mật khẩu hoặc nội dung keystore.

## 0. Điều kiện trước khi bắt đầu

```bash
set -euo pipefail
command -v gh
command -v git
command -v keytool
command -v base64
command -v jq
command -v ssh
gh auth status
export GH_OWNER="$(gh api user --jq .login)"
export WORKBENCH_REPO="$GH_OWNER/factory-workbench"
export WORKBENCH_SRC="/Users/nguyentronghieu/Project/factory-tweaks-claude2/deploy/workbench"
test -f "$WORKBENCH_SRC/.github/workflows/verify-lock.yml"
```

Nếu bất kỳ lệnh nào lỗi, **dừng và báo chủ**. Xác nhận tài khoản `GH_OWNER` là tài khoản được chủ chỉ định; không tự chọn kho khác.

## 1. Tạo kho riêng tư và đẩy đúng thư mục workbench

```bash
gh repo create "$WORKBENCH_REPO" --private
export WORKBENCH_CHECKOUT="$(mktemp -d)/factory-workbench"
git clone "https://github.com/$WORKBENCH_REPO.git" "$WORKBENCH_CHECKOUT"
cp -a "$WORKBENCH_SRC/." "$WORKBENCH_CHECKOUT/"
cd "$WORKBENCH_CHECKOUT"
git add .
git commit -m "Khởi tạo kho xưởng thử Android"
git push -u origin HEAD:main
gh repo view "$WORKBENCH_REPO" --json visibility --jq .visibility
```

Kết quả lệnh cuối phải là `PRIVATE`. Nếu kho đã tồn tại, không ghi đè: **dừng và báo chủ**. Chỉ sao chép nội dung `deploy/workbench/`, không đẩy mã hay dữ liệu từ xưởng chính. Không commit file `.jks`, mật khẩu, `verify-result.json` hoặc APK build.

## 2. Tạo keystore và đặt GitHub Actions secrets

```bash
umask 077
export KEY_DIR="$(mktemp -d)"
export KEYSTORE="$KEY_DIR/factory-workbench.jks"
keytool -genkeypair -keystore "$KEYSTORE" -alias factory -keyalg RSA -keysize 3072 -validity 3650
chmod 600 "$KEYSTORE"
base64 < "$KEYSTORE" | tr -d '\n' | gh secret set KEYSTORE_B64 -R "$WORKBENCH_REPO"
read -r -s -p 'Mật khẩu keystore: ' KS_PASS; printf '\n'
printf '%s' "$KS_PASS" | gh secret set KS_PASS -R "$WORKBENCH_REPO"
printf '%s' 'factory' | gh secret set KS_ALIAS -R "$WORKBENCH_REPO"
unset KS_PASS
gh secret list -R "$WORKBENCH_REPO"
```

Khi `keytool` hỏi mật khẩu của key riêng, dùng **cùng mật khẩu keystore** (workflow dùng `KS_PASS` cho cả hai). Giữ keystore và mật khẩu trong kho bí mật của chủ để ký các bản cập nhật; không đưa vào Git. Nếu không thể lưu an toàn, **dừng và báo chủ**. `gh secret set` đọc giá trị qua stdin và mã hóa trước khi gửi lên GitHub ([tài liệu gh](https://cli.github.com/manual/gh_secret_set)).

## 3. Tạo PAT giới hạn một kho

GitHub CLI không có lệnh an toàn để tạo fine-grained PAT thay chủ. Chủ mở **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**. Chọn đúng kho `$WORKBENCH_REPO`, thời hạn do chủ quyết định, cấp **Actions: Read and write**, **Contents: Read and write** (để đẩy nhánh `ticket-*`) và **Metadata: Read**. Không cấp quyền kho khác. Khi chủ đã tạo PAT, nhập trực tiếp vào terminal bảo mật; không dán vào chat:

```bash
read -r -s -p 'Fine-grained PAT của workbench: ' WORKBENCH_PAT; printf '\n'
test -n "$WORKBENCH_PAT"
```

Nếu thiếu quyền, PAT hết hạn, hoặc kho không đúng, **dừng và báo chủ**; không tự mở rộng quyền. [Hướng dẫn quyền PAT của GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

## 4. Đặt môi trường và cấu hình CI trên máy Mỹ

Chủ cung cấp địa chỉ SSH máy Mỹ; **không** dùng máy Singapore. Tài khoản SSH cần `sudo -n` vào `/opt/factory` mà không đọc mật khẩu từ stdin. Thay `USER@US_HOST` bằng địa chỉ được chủ xác nhận:

```bash
export FACTORY_SSH='USER@US_HOST'
ssh "$FACTORY_SSH" 'sudo -n test -d /opt/factory/data'
scp tools/set_factory_env.py "$FACTORY_SSH:/tmp/factory-set-env.py"
printf '%s\n' "$WORKBENCH_PAT" | ssh "$FACTORY_SSH" "sudo -n python3 /tmp/factory-set-env.py '$WORKBENCH_REPO'"
unset WORKBENCH_PAT
ssh "$FACTORY_SSH" 'sudo -n test "$(stat -c %a /opt/factory/factory.env)" = 600'
python3 -c 'import json,sys; p=json.load(open("ci_services.sample.json")); repo=sys.argv[1]; [v.__setitem__("repo",repo) for v in p.values()]; json.dump(p,open("/tmp/factory-ci-services.json","w"),ensure_ascii=False,indent=2)' "$WORKBENCH_REPO"
scp /tmp/factory-ci-services.json "$FACTORY_SSH:/tmp/factory-ci-services.json"
ssh "$FACTORY_SSH" 'sudo -n install -m 644 /tmp/factory-ci-services.json /opt/factory/data/ci_services.json'
ssh "$FACTORY_SSH" 'sudo -n python3 -c '\''import json; p=json.load(open("/opt/factory/data/ci_services.json")); assert set(p)=={"android_sample","worker_android_app"}'\'''
```

Không dùng `cat`/`grep` để in `factory.env`. Nếu `sudo -n` lỗi hoặc máy Mỹ không có `/opt/factory/data`, **dừng và báo chủ**. File mẫu `verified_builders.sample.json` có `kiem_chung: false`; không sao chép đè chứng nhận thật đang có. Cấu hình CI chỉ cho phép thử, chưa mở tự giao.

## 5. Chạy kiểm khóa trên emulator và đọc kết quả

```bash
export VERIFY_RUN_URL="$(gh workflow run verify-lock.yml --ref main -R "$WORKBENCH_REPO")"
export VERIFY_RUN_ID="${VERIFY_RUN_URL##*/}"
[[ "$VERIFY_RUN_ID" =~ ^[0-9]+$ ]] || { printf 'Không xác định được run mới; dừng.\n' >&2; exit 1; }
gh run watch "$VERIFY_RUN_ID" -R "$WORKBENCH_REPO" --exit-status || true
export VERIFY_DIR="$(mktemp -d)"
gh run download "$VERIFY_RUN_ID" -R "$WORKBENCH_REPO" -n verify-lock-result -D "$VERIFY_DIR"
jq '{ngay,moi_truong,cac_phep_thu,loi}' "$VERIFY_DIR/verify-result.json"
jq -e '.moi_truong == "android-emulator-API34" and (.cac_phep_thu | keys | length) == 5 and (.cac_phep_thu | all(. == true))' "$VERIFY_DIR/verify-result.json"
```

Nếu job không tạo artifact, JSON không đúng cấu trúc, hoặc **bất kỳ** phép thử nào là `false`, **dừng và báo chủ**; không sửa test để cho qua. Bốn nhóm bắt buộc là đúng model, sai model, trial (cả hết 1 giờ **và** lùi đồng hồ), paid không hết hạn; JSON ghi riêng 5 kết quả. [Lệnh workflow](https://cli.github.com/manual/gh_workflow_run) và [tải artifact](https://cli.github.com/manual/gh_run_download) do GitHub CLI hỗ trợ.

Emulator API 34 **không thay máy thật**: chưa kiểm được tùy biến Samsung/Xiaomi/Pixel, Play Protect, cơ chế cài APK của từng hãng, hành vi khi cập nhật/cài lại và độ chính xác của `Build.MODEL` trên máy khách. Sau khi emulator đạt, chủ phải làm bảng kiểm trên máy thật theo `docs/KIEM-TRA-APK-TREN-MAY-THAT.md`, xác nhận nguồn `SOURCES-MAU.json` trước khi chính chủ cập nhật `data/sources.json` và đăng ký dịch vụ trong catalog. Hermes **không** tự sửa mã xưởng hoặc đặt `kiem_chung: true`. Chỉ sau kết quả máy thật được chủ ký xác nhận mới xem xét điền `verified_builders.json` với ngày, tên máy, người xác nhận.

## 6. Quy tắc dừng

- Dừng khi lỗi xác thực/quyền GitHub, hạn mức Actions hoặc `ci_runs` hết, keystore không dùng được, workflow lỗi, thiếu artifact, hash sai, hoặc phép thử thất bại. Báo chủ mã run và tên phép thử lỗi, không gửi secret.
- Không sửa mã xưởng, không bật `/tho bat`, không tự đặt `kiem_chung: true` khi còn phép thử fail hoặc chưa có xác nhận máy thật.
- Không in token, mật khẩu, keystore, nội dung `factory.env` ra chat hoặc log. Không đưa code lên server Mỹ bằng hướng dẫn này; máy Mỹ chỉ nhận cấu hình theo bước 4 sau khi chủ cho phép.
