#!/usr/bin/env bash
set -euo pipefail

tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
version="$(<"$tools_dir/apktool.version")"
expected_sha256="$(<"$tools_dir/apktool.sha256")"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Phiên bản apktool không hợp lệ' >&2
  exit 1
fi
if [[ "$expected_sha256" == 'CHUA-CO-MA-BAM' ]]; then
  echo 'Chưa có mã băm SHA256 của apktool; từ chối cài đặt' >&2
  exit 1
fi
if [[ ! "$expected_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo 'Mã băm SHA256 của apktool không hợp lệ' >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
jar="$tmp_dir/apktool.jar"
url="https://github.com/iBotPeaches/Apktool/releases/download/v${version}/apktool_${version}.jar"
curl --proto '=https' --tlsv1.2 --location --fail --silent --show-error --output "$jar" "$url"

actual_sha256="$(sha256sum -- "$jar")"
actual_sha256="${actual_sha256%% *}"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo 'Mã băm SHA256 apktool tải về không khớp; từ chối cài đặt' >&2
  exit 1
fi

cat > "$tmp_dir/apktool" <<'WRAPPER'
#!/usr/bin/env bash
exec java -jar /usr/local/lib/apktool.jar "$@"
WRAPPER
sudo install -D -m 0644 "$jar" /usr/local/lib/apktool.jar
sudo install -D -m 0755 "$tmp_dir/apktool" /usr/local/bin/apktool
