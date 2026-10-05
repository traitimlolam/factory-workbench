"""CỔNG KIỂM TRA MÃ NGUỒN TĨNH (Code Gate) — VÒNG 2 (Chốt an toàn 3 lớp phòng vệ).

Toàn bộ quy tắc chạy bằng regex/lexing xác định tuyệt đối (deterministic), KHÔNG gọi AI.
Chặn đứng (BLOCK) các hành vi nguy hiểm từ mã do thợ AI sinh ra:
1. Deny-list mở rộng: Chặn toàn bộ đường truyền mạng ẩn (Foundation, Swift, Android, Smali),
   gọi shell nhúng, clipboard snooping, ghi phím (keylogger/hooking), reflection động,
   cài đặt boot persistence và rò rỉ IPC qua Android exported components.
2. Allow-list nhập khẩu (Import Allow-list): Mỗi nền tảng chỉ cho phép import danh mục
   framework và gói tin cậy (rule 'import_not_allowed').
3. Kiểm tra tệp ngoài mã (Non-code checks): Cấm curl, wget, pipe-to-shell trong Makefile,
   control, install scripts (postinst/preinst), build.gradle và plist launchd persistence.
4. Chống né tránh (Evasion Prevention): Bắt ghép chuỗi literal liền kề (rule 'string_concat_evasion')
   và giới hạn đối số động của NSClassFromString / Class.forName trong danh mục an toàn.

HẠN CHẾ TRUNG THỰC CỦA PHÂN TÍCH TĨNH (STATIC ANALYSIS LIMITS):
- Phân tích tĩnh dựa trên Regex/Lexing bị giới hạn bởi Định lý Rice và Bài toán dừng (Halting Problem).
- Không thể phát hiện mã hóa đa tầng runtime (ví dụ AES-256 payload tải từ RAM hoặc mảng byte XOR phức tạp).
- Không thể giải mã dynamic symbol resolution thông qua IPC hoặc memory injection nếu qua mặt được lexing.
- Cổng tĩnh này là Lớp phòng thủ số 1 (L1 Gate: Siêu nhanh < 1s, xác định 100%),
  được bổ trợ bởi Lớp L2 (AI Reviewer độc lập) và Lớp L3 (Kỹ sư chủ duyệt trước khi xuất xưởng).
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import PurePosixPath


@dataclass(frozen=True)
class Violation:
    rule: str
    path: str
    line: int
    message: str
    severity: str  # "block" | "warn"


def has_blockers(violations: list[Violation]) -> bool:
    """Trả về True nếu danh sách vi phạm có ít nhất một lỗi mức 'block'."""
    return any(v.severity == "block" for v in violations)


LIMITS = {
    "max_files": 12,
    "max_total_chars": 60000,
    "max_file_chars": 20000,
}

# Đuôi file cho phép từng nền tảng
ALLOWED_EXTENSIONS_BY_PLATFORM = {
    "ios_tweak": {
        ".x", ".xm", ".xi", ".xmi", ".m", ".mm", ".h", ".hpp",
        ".c", ".cpp", ".swift", ".plist", ".json", ".strings",
        ".entitlements", ""
    },
    "ios_app": {
        ".swift", ".m", ".mm", ".h", ".c", ".cpp", ".plist",
        ".json", ".storyboard", ".xib", ".strings", ".entitlements", ""
    },
    "android_app": {
        ".java", ".kt", ".xml", ".smali", ".gradle", ".json",
        ".properties", ".txt", ".pro", ""
    },
}

ALLOWED_FILENAMES_WITHOUT_EXT = {
    "makefile", "control", "proguard-rules",
    "postinst", "preinst", "prerm", "postrm"
}

# Đuôi file tuyệt đối cấm trên mọi nền tảng
FORBIDDEN_EXTENSIONS = {
    ".dylib", ".so", ".jar", ".apk", ".ipa", ".zip", ".tar", ".gz", ".7z",
    ".sh", ".bash", ".py", ".js", ".bin", ".exe", ".dex", ".class", ".bat", ".cmd"
}


# ═════════════════════════════════════════════════════════════════════════════
# HẰNG SỐ ALLOW-LIST NHẬP KHẨU (IMPORT ALLOW-LIST) THEO NỀN TẢNG
# ═════════════════════════════════════════════════════════════════════════════

ALLOWED_FRAMEWORKS_IOS_BASE = {
    "uikit", "foundation", "coregraphics", "quartzcore",
    "audiotoolbox", "corefoundation", "substrate.h", "cydiasubstrate"
}

ALLOWED_IMPORTS_SWIFT_BASE = {
    "uikit", "foundation", "swiftui", "coregraphics",
    "quartzcore", "corefoundation", "audiotoolbox"
}

# Tiền tố package Android Java / Kotlin được phép
ALLOWED_ANDROID_PACKAGE_PREFIXES_BASE = (
    "android.app", "android.os", "android.widget", "android.view",
    "android.content", "android.util", "android.graphics",
    "android.content.res", "android.text", "android.animation",
    "androidx.appcompat", "androidx.core", "androidx.annotation",
    "androidx.fragment", "androidx.recyclerview", "androidx.lifecycle",
    "java.util", "java.lang", "java.io", "java.math", "java.text",
    "kotlin",
)

# Các package Android tuyệt đối cấm
FORBIDDEN_ANDROID_PACKAGE_PREFIXES = (
    "java.net", "javax.net", "okhttp", "retrofit",
    "android.net", "android.webkit", "android.telephony",
    "android.provider", "dalvik.system", "java.lang.reflect",
    "io.ktor", "ktor",
)

# Danh sách lớp cho phép trong NSClassFromString / Class.forName động
ALLOWED_DYNAMIC_CLASSES_IOS = {
    "sbapplication", "springboard", "uiwindow", "uiview", "uiviewcontroller", "uiapplication"
}
ALLOWED_DYNAMIC_CLASSES_ANDROID = {
    "java.lang.string", "java.lang.integer", "android.view.view", "android.widget.textview"
}


# ── BỘ LỌC CHÚ THÍCH (COMMENTS) THÔNG MINH ───────────────────────────────────
_XML_COMMENT_RE = re.compile(r"<!--[\s\S]*?-->")

_C_STRING_OR_COMMENT_RE = re.compile(
    r'("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')|(/\*[\s\S]*?\*/)|(//[^\n]*)'
)

_HASH_STRING_OR_COMMENT_RE = re.compile(
    r'("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')|(#[^\n]*)'
)


def _mask_comment(match: re.Match) -> str:
    """Thay thế comment bằng khoảng trắng, giữ nguyên ký tự xuống dòng."""
    return "".join("\n" if c == "\n" else " " for c in match.group(0))


def _strip_comments_preserving_strings(content: str, filename: str) -> str:
    """Loại bỏ chú thích nhưng bảo tồn chuỗi ký tự '...' và số dòng."""
    ext = PurePosixPath(filename).suffix.lower()
    base_name = PurePosixPath(filename).name.lower()

    if ext in (".xml", ".plist", ".storyboard", ".xib"):
        return _XML_COMMENT_RE.sub(_mask_comment, content)

    if ext in (".properties", ".pro") or base_name in ("makefile", "control", "postinst", "preinst", "prerm", "postrm"):
        def repl_hash(m: re.Match) -> str:
            if m.group(1) is not None:
                return m.group(1)
            comment = m.group(2)
            return "".join("\n" if c == "\n" else " " for c in comment)
        return _HASH_STRING_OR_COMMENT_RE.sub(repl_hash, content)

    # C, C++, ObjC, Swift, Java, Kotlin, Logos (.x, .xm), Smali
    def repl_c(m: re.Match) -> str:
        if m.group(1) is not None:
            return m.group(1)
        comment = m.group(2) or m.group(3)
        return "".join("\n" if c == "\n" else " " for c in comment)

    stripped = _C_STRING_OR_COMMENT_RE.sub(repl_c, content)
    if ext == ".smali":
        def repl_hash_smali(m: re.Match) -> str:
            if m.group(1) is not None:
                return m.group(1)
            comment = m.group(2)
            return "".join("\n" if c == "\n" else " " for c in comment)
        stripped = _HASH_STRING_OR_COMMENT_RE.sub(repl_hash_smali, stripped)

    return stripped


# ═════════════════════════════════════════════════════════════════════════════
# CÁC REGEX QUY TẮC AN TOÀN (LỚP 1: DENY-LIST MỞ RỘNG)
# ═════════════════════════════════════════════════════════════════════════════

# 1. Mạng cốt lõi & mở rộng
_NETWORK_BASE_RE = re.compile(
    r"\b(NSURLSession|NSURLConnection|CFNetwork|CFStream|URLSession)\b|"
    r"\b(socket|connect)\s*\(|"
    r"\bgetaddrinfo\b|"
    r"\bWebSocket\b|"
    r"\b(HttpURLConnection|OkHttp[A-Za-z0-9_]*|Retrofit[A-Za-z0-9_]*|Volley|InetAddress)\b|"
    r"\bjava\.net\.|"
    r"\bandroid\.net\.http|"
    r"\b(?:WKWebView|UIWebView|WebView)\b[\s\S]{0,80}?\bloadUrl\b|"
    r"\bloadUrl\s*\(\s*[\"']https?://"
)

_NETWORK_EXPANDED_IOS_RE = re.compile(
    r"\b(dataWithContentsOfURL|stringWithContentsOfURL|initWithContentsOfURL)\s*:|"
    r"\b(NSURLRequest|NSMutableURLRequest|NSURLProtocol)\b|"
    r"\b(AFHTTPSessionManager|AFURLSessionManager|AFHTTPRequestOperation|AFNetworking|Alamofire)\b|"
    r"\bnw_(?:connection|endpoint|parameters|listener|path|browse)[a-zA-Z0-9_]*\b|"
    r"\b(?:CFSocket|CFSocketCreate|CFSocketRef|CFReadStream|CFWriteStream|CFHTTPMessage)[a-zA-Z0-9_]*\b"
)

_NETWORK_EXPANDED_SWIFT_RE = re.compile(
    r"\bData\s*\(\s*contentsOf\s*:|"
    r"\bString\s*\(\s*contentsOf\s*:|"
    r"\bNWConnection\b"
)

_NETWORK_EXPANDED_ANDROID_RE = re.compile(
    r"\b(?:new\s+)?(?:Server)?Socket\s*[\(<]|"
    r"\b(?:new\s+)?Socket\s+[a-zA-Z0-9_]+\s*=|"
    r"Ljava/net/(?:Socket|ServerSocket|URL|URLConnection|HttpURLConnection)|"
    r"Ljavax/net/ssl/HttpsURLConnection|"
    r"\b(?:new\s+URL\s*\(|URL\s*\([^)]*\))\s*\.\s*(?:openStream|openConnection|readText)\b|"
    r"\.openStream\s*\(|"
    r"\.openConnection\s*\(|"
    r"\.readText\s*\(|"
    r"\bHttpsURLConnection\b|"
    r"\b(?:HttpClient|CIO)\b|"
    r"\bDownloadManager\b|"
    r"\bsetJavaScriptEnabled\s*\(|"
    r"\baddJavascriptInterface\s*\(",
    re.IGNORECASE
)

_NETWORK_MANIFEST_RE = re.compile(
    r"<uses-permission\s+[^>]*android:name=[\"']android\.permission\.INTERNET[\"']"
)

# 2. Dữ liệu riêng tư & Bảo mật
_PRIVACY_GROUPS = {
    "contacts": {
        "pattern": re.compile(
            r"\b(CNContact[A-Za-z0-9_]*|ABAddressBook|ContactsContract)\b|"
            r"android\.permission\.(?:READ_CONTACTS|WRITE_CONTACTS)|"
            r'content://contacts\b'
        ),
        "desc": "danh bạ điện thoại",
    },
    "photos": {
        "pattern": re.compile(
            r"\b(PHPhoto[A-Za-z0-9_]*|MediaStore)\b|"
            r"android\.permission\.(?:READ_MEDIA_IMAGES|READ_EXTERNAL_STORAGE)"
        ),
        "desc": "thư viện ảnh/đa phương tiện",
    },
    "messages": {
        "pattern": re.compile(
            r"\b(MFMessage[A-Za-z0-9_]*|SmsManager|Telephony)\b|\bsms\.db\b|"
            r"android\.permission\.(?:READ_SMS|RECEIVE_SMS|SEND_SMS)|"
            r'content://(?:sms|call_log)\b'
        ),
        "desc": "tin nhắn SMS / cuộc gọi",
    },
    "microphone": {
        "pattern": re.compile(
            r"\b(AVAudioRecorder|MediaRecorder|AudioRecord)\b|"
            r"android\.permission\.RECORD_AUDIO"
        ),
        "desc": "ghi âm / microphone",
    },
    "camera": {
        "pattern": re.compile(
            r"\b(AVCapture[A-Za-z0-9_]*|camera2)\b|\bandroid\.hardware\.Camera\b|"
            r"android\.permission\.CAMERA"
        ),
        "desc": "máy ảnh / camera",
    },
    "location": {
        "pattern": re.compile(
            r"\b(CLLocation[A-Za-z0-9_]*|LocationManager)\b|"
            r"android\.permission\.(?:ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|ACCESS_BACKGROUND_LOCATION)"
        ),
        "desc": "vị trí / GPS",
    },
}

_PRIVACY_CREDENTIALS_RE = re.compile(
    r"\b(SecItemCopyMatching|SecItemAdd|SecItemUpdate|SecItemDelete)\b|"
    r"\b(KeyStore|AccountManager)\b"
)

# Clipboard & Keylogger
_CLIPBOARD_RE = re.compile(
    r"\bUIPasteboard\b|\bClipboardManager\b"
)

_KEYLOGGER_RE = re.compile(
    r"%hook\s+(?:UITextField|UITextView|UIKeyboard[A-Za-z0-9_]*)\b|"
    r"\b(?:addInputString|insertText)\s*:|"
    r"\bIOHIDEvent[A-Za-z0-9_]*\b"
)

# 3. Chạy tiến trình / Tải mã / Độc hại
_EXECUTION_RE = re.compile(
    r"\b(system|popen|posix_spawn|fork|execve)\s*\(|"
    r"\bNSTask\b|"
    r"Runtime\.getRuntime\(\)\.exec|"
    r"\bProcessBuilder\b|"
    r"\bProcess\s*\(\s*\)|"
    r"\b(dlopen|dlsym)\b|"
    r"\b(DexClassLoader|PathClassLoader)\b|"
    r"\bClass\.forName\s*\(|"
    r"\beval\s*\(|"
    r"\bclass-dump\b"
)

_DYNAMIC_CODE_RE = re.compile(
    r"\bSystem\s*\.\s*(?:load|loadLibrary)\s*\(|"
    r"\bperformSelector\s*:|"
    r"\bNSSelectorFromString\s*\(|"
    r"\bobjc_msgSend\b|"
    r"\bMethod\s*\.\s*invoke\b|\.invoke\s*\("
)

_SHELL_EMBEDDED_RE = re.compile(
    r"/bin/sh\b|/bin/bash\b|/bin/zsh\b|/usr/bin/su\b|"
    r"\bsu\s+-c\b|"
    r"\bchmod\s+\+x\b|"
    r"\b(?:curl|wget|nc)\s+|"
    r'["\'][^"\']*\b-c\s+[^"\']*["\']'
)

_ACTION_VIEW_RE = re.compile(
    r'Intent\.ACTION_VIEW\s*,?\s*(?:Uri\.parse|[a-zA-Z0-9_]+)'
)

_SETTINGS_SECURE_RE = re.compile(
    r'Settings\.(?:Secure|Global)\b|Settings\.System\.put[A-Za-z0-9_]*|'
    r'Landroid/provider/Settings\$(?:Secure|Global|System);->put[A-Za-z0-9_]*'
)

# 4. Mờ / Giấu / Obfuscation
_MALICIOUS_DESTINATIONS_RE = re.compile(
    r"\.onion\b|pastebin\.com|discord\.com/api/webhooks|t\.me/|api\.telegram\.org"
)
_SUSPICIOUS_URL_RE = re.compile(
    r"https?://(?!schemas\.android\.com/|www\.apple\.com/DTDs/)[a-zA-Z0-9_.-]+"
)
_IPV4_RE = re.compile(
    r"\b(?!127\.0\.0\.1\b|0\.0\.0\.0\b)(?:[1-9]\d{0,2}\.){3}[1-9]\d{0,2}\b"
)
_LONG_BASE64_HEX_RE = re.compile(
    r"\b[A-Za-z0-9+/=]{201,}\b|\b[0-9a-fA-F]{201,}\b"
)
_CRYPTO_WALLET_RE = re.compile(
    r"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b|\b0x[a-fA-F0-9]{40}\b"
)
_COIN_MINING_RE = re.compile(
    r"\b(stratum|xmrig|cryptonight)\b", re.I
)
_XOR_DECRYPT_RE = re.compile(
    r"\^=\s*0x[0-9a-fA-F]{1,2}|\bfor\b[\s\S]{0,40}\^"
)
_OBFUSCATED_VAR_RE = re.compile(
    r"\b_0x[a-f0-9]{6,}\b"
)

# 5. Quyền lực / Leo thang đặc quyền (Privilege)
_PRIVILEGE_OS_RE = re.compile(
    r"\b(setuid|setgid|mount|ptrace|csops|task_for_pid|sandbox_extension)\b|"
    r"\bchmod\s*\(|chmod\s+777"
)
_DANGEROUS_ENTITLEMENTS_RE = re.compile(
    r"platform-application|com\.apple\.private\.|get-task-allow"
)
_DANGEROUS_ANDROID_PERMS_RE = re.compile(
    r"android\.permission\.(?:REQUEST_INSTALL_PACKAGES|SYSTEM_ALERT_WINDOW|"
    r"BIND_ACCESSIBILITY_SERVICE|DEVICE_ADMIN|CALL_PHONE|MANAGE_EXTERNAL_STORAGE|"
    r"RECEIVE_BOOT_COMPLETED)|android\.intent\.action\.BOOT_COMPLETED"
)
_ANDROID_EXPORTED_RE = re.compile(
    r'<(?:service|receiver|provider)\b[^>]*android:exported=[\'"]true[\'"]', re.I | re.S
)

# 6. Ghi đè file hệ thống (System Tampering)
_SYSTEM_TAMPERING_RE = re.compile(
    r"/(?:var/mobile/Library|System|private/var)/[a-zA-Z0-9_/.-]+"
)

# 7. Cảnh báo (WARN)
_WARN_PRIVATE_API_RE = re.compile(
    r"\bMSHookMessageEx\b"
)
_WARN_INFINITE_LOOP_RE = re.compile(
    r"while\s*\(\s*(?:true|1)\s*\)[\s\S]{0,80}?\b(?:sleep|usleep)\b"
)

# 8. Tệp ngoài mã nguy hiểm (Makefile, Deb scripts, Plist persistence)
_NON_CODE_DANGEROUS_RE = re.compile(
    r"\b(?:curl|wget|nc)\b|\|\s*(?:sh|bash)\b|"
    r"\b(?:sh|bash|python\d*)\s+-c\b|/bin/sh\s+-c|"
    r"\b(?:touch|cp|mv|rm|mkdir|install|tee|chmod|chown)\s+(?:-[A-Za-z]+\s+)*(?:/etc|/var|/tmp|/System|/usr|/private|/Library)/",
    re.I
)
_LAUNCHD_PERSISTENCE_RE = re.compile(
    r"<key>\s*(?:RunAtLoad|ProgramArguments|KeepAlive)\s*</key>"
)

# 9. Danh mục từ khóa cấm khi ghép chuỗi literal (String concat evasion)
_STRING_CONCAT_SUSPICIOUS_TOKENS = (
    "nsurlsession", "nsurlrequest", "nsurlprotocol", "afnetworking", "cfsocket",
    "socket", "serversocket", "httpsurlconnection", "downloadmanager",
    "uipasteboard", "iohidevent", "class.forname", "method.invoke",
    "/bin/sh", "/bin/bash", "/usr/bin/su", "su -c", "chmod +x", "curl", "wget",
    "content://sms", "content://contacts", "content://call_log",
    "settings.secure", "settings.global", "processbuilder", "runtime.getruntime",
    "system.load", "system.loadlibrary", "nw_connection"
)


# ── BỘ KIỂM TRA GHÉP CHUỖI LITERAL ──────────────────────────────────────────
_CONCAT_LITERAL_REGEX = re.compile(
    r'(@?"(?:[^"\\]|\\.)*")(?:\s*(?:\+|\s)\s*(@?"(?:[^"\\]|\\.)*"))+'
)
_SINGLE_STRING_LITERAL_RE = re.compile(r'@?"((?:[^"\\]|\\.)*)"')


def _check_string_concatenation_evasion(line: str) -> str | None:
    """Kiểm tra xem dòng mã có ghép nhiều chuỗi literal nhằm lẩn tránh API cấm hay không."""
    for match in _CONCAT_LITERAL_REGEX.finditer(line):
        full_match = match.group(0)
        parts = _SINGLE_STRING_LITERAL_RE.findall(full_match)
        if len(parts) >= 2:
            combined = "".join(parts).lower()
            for token in _STRING_CONCAT_SUSPICIOUS_TOKENS:
                if token in combined:
                    return f"Ghép chuỗi literal '{combined}' khớp API/lệnh cấm '{token}'"
    return None


# ── BỘ KIỂM TRA LỚP ĐỘNG (NSClassFromString / Class.forName / objc_getClass) ─
_NSCLASSFROMSTRING_RE = re.compile(r'\bNSClassFromString\s*\(\s*([^)]+)\s*\)')
_CLASS_FORNAME_RE = re.compile(r'\bClass\.forName\s*\(\s*([^)]+)\s*\)')
_OBJC_GETCLASS_RE = re.compile(r'\bobjc_getClass\s*\(\s*([^)]+)\s*\)')


def _check_dynamic_class_lookup(line: str, platform: str) -> str | None:
    """Cấm NSClassFromString / Class.forName / objc_getClass với đối số không phải literal trong allow-list."""
    # ObjC NSClassFromString
    for m in _NSCLASSFROMSTRING_RE.finditer(line):
        arg = m.group(1).strip()
        str_m = re.fullmatch(r'@?"([^"]+)"', arg)
        if not str_m:
            return f"NSClassFromString với đối số không phải chuỗi cố định: {arg}"
        cls_name = str_m.group(1).lower()
        if cls_name not in ALLOWED_DYNAMIC_CLASSES_IOS:
            return f"NSClassFromString với lớp '{str_m.group(1)}' không nằm trong allow-list"

    # Java Class.forName
    for m in _CLASS_FORNAME_RE.finditer(line):
        arg = m.group(1).strip()
        str_m = re.fullmatch(r'"([^"]+)"', arg)
        if not str_m:
            return f"Class.forName với đối số không phải chuỗi cố định: {arg}"
        cls_name = str_m.group(1).lower()
        if cls_name not in ALLOWED_DYNAMIC_CLASSES_ANDROID:
            return f"Class.forName với lớp '{str_m.group(1)}' không nằm trong allow-list"

    # objc_getClass
    for m in _OBJC_GETCLASS_RE.finditer(line):
        arg = m.group(1).strip()
        str_m = re.fullmatch(r'"([^"]+)"', arg)
        if not str_m:
            return f"objc_getClass với đối số không phải chuỗi cố định: {arg}"
        cls_name = str_m.group(1).lower()
        if cls_name not in ALLOWED_DYNAMIC_CLASSES_IOS:
            return f"objc_getClass với lớp lạ '{str_m.group(1)}' không nằm trong allow-list"

    return None


# ── BỘ KIỂM TRA ALLOW-LIST NHẬP KHẨU (LỚP 2) ──────────────────────────────────
_OBJC_IMPORT_RE = re.compile(
    r'^\s*(?:#\s*import|#\s*include)\s*(<[^>]+>|"[^"]+")|^\s*@import\s+([a-zA-Z0-9_]+)\s*;'
)
_SWIFT_IMPORT_RE = re.compile(
    r'^\s*(?:@_\w+\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([a-zA-Z0-9_]+)'
)
_JAVA_IMPORT_RE = re.compile(
    r'^\s*import\s+(?:static\s+)?([a-zA-Z0-9_.]+(?:\*)?)(?:\s+as\s+[a-zA-Z0-9_]+)?\s*;?\s*$'
)

# API names and manifest/plist keys are matched without case sensitivity.
# Compile once here so a 60k-character scan does not recompile rules per line.
for _rule_name in (
    "_NETWORK_BASE_RE", "_NETWORK_EXPANDED_IOS_RE", "_NETWORK_EXPANDED_SWIFT_RE",
    "_NETWORK_EXPANDED_ANDROID_RE", "_NETWORK_MANIFEST_RE", "_PRIVACY_CREDENTIALS_RE",
    "_CLIPBOARD_RE", "_KEYLOGGER_RE", "_EXECUTION_RE", "_DYNAMIC_CODE_RE",
    "_SHELL_EMBEDDED_RE", "_ACTION_VIEW_RE", "_SETTINGS_SECURE_RE",
    "_MALICIOUS_DESTINATIONS_RE", "_SUSPICIOUS_URL_RE", "_COIN_MINING_RE",
    "_PRIVILEGE_OS_RE", "_DANGEROUS_ENTITLEMENTS_RE", "_DANGEROUS_ANDROID_PERMS_RE",
    "_SYSTEM_TAMPERING_RE", "_LAUNCHD_PERSISTENCE_RE", "_NSCLASSFROMSTRING_RE",
    "_CLASS_FORNAME_RE", "_OBJC_GETCLASS_RE", "_OBJC_IMPORT_RE", "_SWIFT_IMPORT_RE",
    "_JAVA_IMPORT_RE",
    "_XOR_DECRYPT_RE", "_OBFUSCATED_VAR_RE", "_WARN_PRIVATE_API_RE",
    "_WARN_INFINITE_LOOP_RE",
):
    _pattern = globals()[_rule_name]
    globals()[_rule_name] = re.compile(_pattern.pattern, _pattern.flags | re.I)
for _group in _PRIVACY_GROUPS.values():
    _pattern = _group["pattern"]
    _group["pattern"] = re.compile(_pattern.pattern, _pattern.flags | re.I)


def _check_import_allowlist(
    line: str,
    ext: str,
    platform: str,
    *,
    allow_network: bool,
    allow_sensitive: set[str],
    project_paths: set[str],
    current_path: str,
) -> str | None:
    """Kiểm tra tính hợp lệ của lệnh import dựa trên allow-list nghiêm ngặt của nền tảng."""
    # 1. C/ObjC/Logos (.m, .mm, .h, .c, .cpp, .x, .xm)
    if ext in (".x", ".xm", ".xi", ".xmi", ".m", ".mm", ".h", ".hpp", ".c", ".cpp"):
        m = _OBJC_IMPORT_RE.match(line)
        if m:
            quoted_header = m.group(1)
            module_name = m.group(2)
            if quoted_header:
                if quoted_header.startswith('"'):
                    header_inner = quoted_header[1:-1].strip()
                    if header_inner.startswith(("/", "../")) or ".." in header_inner.split("/"):
                        return "Header trích dẫn đi ra ngoài dự án"
                    first = header_inner.split("/")[0].lower()
                    # Dấu nháy không biến framework cấm thành header cục bộ.
                    permitted = ((first in {"network", "cfnetwork", "systemconfiguration"} and allow_network)
                                 or (first == "corelocation" and "location" in allow_sensitive)
                                 or (first == "avfoundation" and bool({"camera", "microphone"} & allow_sensitive))
                                 or (first in {"contacts", "photos"} and first in allow_sensitive))
                    if first in {"network", "cfnetwork", "systemconfiguration", "webkit", "messageui",
                                 "contacts", "photos", "avfoundation", "corelocation", "security",
                                 "localauthentication"} and not permitted:
                        return f"Import framework '{first}' không nằm trong allow-list iOS"
                    if permitted:
                        return None
                    local = (PurePosixPath(current_path).parent / header_inner).as_posix()
                    if header_inner.lower() != "substrate.h" and local not in project_paths:
                        return f"Header '{header_inner}' không có trong dự án"
                    return None
                header_inner = quoted_header[1:-1].strip()
                framework = header_inner.split("/")[0].lower() if "/" in header_inner else header_inner.lower()
            else:
                framework = module_name.lower()

            allowed_ios = set(ALLOWED_FRAMEWORKS_IOS_BASE)
            if allow_network:
                allowed_ios.update({"network", "cfnetwork", "systemconfiguration"})
            if "location" in allow_sensitive:
                allowed_ios.add("corelocation")
            if "camera" in allow_sensitive or "microphone" in allow_sensitive:
                allowed_ios.add("avfoundation")
            if "contacts" in allow_sensitive:
                allowed_ios.add("contacts")
            if "photos" in allow_sensitive:
                allowed_ios.add("photos")

            if framework not in allowed_ios:
                return f"Import framework/header '{framework}' không nằm trong allow-list iOS"

    # 2. Swift
    elif ext == ".swift":
        m = _SWIFT_IMPORT_RE.match(line)
        if m:
            mod = m.group(1).lower()
            allowed_swift = set(ALLOWED_IMPORTS_SWIFT_BASE)
            if allow_network:
                allowed_swift.add("network")
            if "location" in allow_sensitive:
                allowed_swift.add("corelocation")
            if "camera" in allow_sensitive or "microphone" in allow_sensitive:
                allowed_swift.add("avfoundation")
            if "contacts" in allow_sensitive:
                allowed_swift.add("contacts")
            if "photos" in allow_sensitive:
                allowed_swift.add("photos")

            if mod not in allowed_swift:
                return f"Import module '{m.group(1)}' không nằm trong allow-list Swift"

    # 3. Android Java / Kotlin
    elif ext in (".java", ".kt"):
        m = _JAVA_IMPORT_RE.match(line)
        if m:
            pkg = m.group(1)
            pkg_lower = pkg.lower()

            # Kiểm tra deny-list trước
            for f_prefix in FORBIDDEN_ANDROID_PACKAGE_PREFIXES:
                if pkg_lower == f_prefix or pkg_lower.startswith(f_prefix + "."):
                    if pkg_lower in ("android.provider.settings", "android.provider.settings.system"):
                        break
                    if allow_network and f_prefix in ("java.net", "javax.net", "okhttp", "retrofit", "android.net", "io.ktor", "ktor"):
                        continue
                    return f"Import package cấm '{pkg}' trên Android"

            # Kiểm tra allow-list
            allowed_prefixes = list(ALLOWED_ANDROID_PACKAGE_PREFIXES_BASE)
            allowed_prefixes.extend(["android.provider.settings"])
            if allow_network:
                allowed_prefixes.extend(["java.net", "javax.net", "okhttp", "retrofit", "android.net", "io.ktor", "ktor"])
            if "location" in allow_sensitive:
                allowed_prefixes.append("android.location")

            is_allowed = any(pkg_lower == p or pkg_lower.startswith(p + ".") for p in allowed_prefixes)
            if not is_allowed:
                return f"Import package '{pkg}' không nằm trong allow-list Android"

    return None


# ── HÀM KIỂM TRA ĐƯỜNG DẪN ───────────────────────────────────────────────────
def _check_path(path: str) -> str | None:
    """Kiểm tra tính an toàn của đường dẫn file. Trả về thông báo lỗi nếu vi phạm."""
    if not path or not path.strip():
        return "Đường dẫn file không được rỗng"
    if path.startswith("/") or path.startswith("\\") or ":" in path:
        return f"Đường dẫn '{path}' không được là đường dẫn tuyệt đối"
    parts = path.replace("\\", "/").split("/")
    if any(p == ".." for p in parts):
        return f"Đường dẫn '{path}' chứa ký tự '..' nguy hiểm"
    if any(p == "" for p in parts[:-1]):
        return f"Đường dẫn '{path}' chứa thư mục rỗng bất thường"
    if re.search(r"[\x00-\x1f\x7f<>:\"|?*]", path):
        return f"Đường dẫn '{path}' chứa ký tự lạ không hợp lệ"
    return None


def _logical_lines(content: str) -> list[tuple[int, str]]:
    """Gộp chỉ thị có dấu backslash cuối dòng, giữ số dòng bắt đầu."""
    result: list[tuple[int, str]] = []
    pending = ""
    start = 1
    for number, line in enumerate(content.splitlines(), 1):
        if not pending:
            start = number
        piece = line.rstrip()
        if piece.endswith("\\"):
            pending += piece[:-1] + " "
            continue
        result.append((start, pending + line))
        pending = ""
    if pending:
        result.append((start, pending))
    return result


# ── HÀM KIỂM TRA HOOK PLIST CỦA TWEAK ─────────────────────────────────────────
def _check_tweak_filter_plist(path: str, content: str) -> list[Violation]:
    """Kiểm tra Filter plist của Theos tweak (hook com.apple.UIKit, *, SpringBoard...)."""
    violations: list[Violation] = []
    stripped = _XML_COMMENT_RE.sub("", content)

    # 1. Hook com.apple.UIKit -> BLOCK
    if "com.apple.uikit" in stripped.lower():
        violations.append(Violation(
            rule="hook_too_broad",
            path=path,
            line=1,
            message="Filter plist hook 'com.apple.UIKit' (toàn bộ ứng dụng giao diện) bị chặn",
            severity="block"
        ))

    # 2. Filter trống hoặc hook mọi tiến trình (*)
    if re.search(r"<key>Bundles</key>\s*<array>\s*</array>", stripped, re.I) or "<string>*</string>" in stripped:
        violations.append(Violation(
            rule="hook_all_processes",
            path=path,
            line=1,
            message="Filter plist để trống hoặc hook '*' (mọi tiến trình) bị chặn",
            severity="block"
        ))

    # 3. Hook SpringBoard -> WARN
    if "com.apple.springboard" in stripped.lower():
        violations.append(Violation(
            rule="hook_springboard",
            path=path,
            line=1,
            message="Tweak hook SpringBoard (giao diện hệ thống) — cần kỹ sư xem xét",
            severity="warn"
        ))

    return violations


# ── HÀM SCAN CHÍNH ────────────────────────────────────────────────────────────
def scan(
    files: dict[str, str],
    platform: str,
    *,
    allow_network: bool = False,
    allow_sensitive: set[str] | None = None,
) -> list[Violation]:
    """Cổng quét mã tĩnh phân tích toàn bộ file dự án (Vòng 2).

    Args:
        files: Từ điển {đường dẫn tương đối: nội dung văn bản}.
        platform: Nền tảng đích ('ios_tweak' | 'ios_app' | 'android_app').
        allow_network: Cho phép gọi mạng nếu có nhu cầu rõ ràng.
        allow_sensitive: Tập các nhóm quyền riêng tư được phép (ví dụ: {'location'}).

    Returns:
        Danh sách Violation (các lỗi 'block' và cảnh báo 'warn').
    """
    violations: list[Violation] = []
    allow_sens = set(allow_sensitive or ())

    # 1. KIỂM TRA GIỚI HẠN TỔNG QUAN (LIMITS)
    if len(files) > LIMITS["max_files"]:
        violations.append(Violation(
            rule="limits_max_files",
            path="",
            line=0,
            message=f"Số lượng file ({len(files)}) vượt quá giới hạn cho phép ({LIMITS['max_files']})",
            severity="block",
        ))

    total_chars = sum(len(c) for c in files.values())
    if total_chars > LIMITS["max_total_chars"]:
        violations.append(Violation(
            rule="limits_total_chars",
            path="",
            line=0,
            message=f"Tổng độ dài ký tự ({total_chars}) vượt quá giới hạn ({LIMITS['max_total_chars']})",
            severity="block",
        ))

    allowed_exts = ALLOWED_EXTENSIONS_BY_PLATFORM.get(platform, set())
    project_paths = set(files)

    # 2. QUÉT TỪNG FILE
    for path, content in files.items():
        pure_p = PurePosixPath(path)
        ext = pure_p.suffix.lower()
        base_name = pure_p.name.lower()

        # 2.1 Kiểm tra tính hợp lệ của đường dẫn file
        path_err = _check_path(path)
        if path_err:
            violations.append(Violation(
                rule="invalid_path",
                path=path,
                line=0,
                message=path_err,
                severity="block",
            ))

        # 2.2 Kiểm tra giới hạn kích thước từng file
        if len(content) > LIMITS["max_file_chars"]:
            violations.append(Violation(
                rule="limits_file_chars",
                path=path,
                line=0,
                message=f"File vượt quá giới hạn ký tự ({len(content)} > {LIMITS['max_file_chars']})",
                severity="block",
            ))

        # 2.3 Kiểm tra đuôi file
        if ext in FORBIDDEN_EXTENSIONS:
            violations.append(Violation(
                rule="forbidden_extension",
                path=path,
                line=0,
                message=f"Đuôi file '{ext}' thuộc danh mục tuyệt đối cấm tải/chạy",
                severity="block",
            ))
        elif ext not in allowed_exts and base_name not in ALLOWED_FILENAMES_WITHOUT_EXT:
            violations.append(Violation(
                rule="unallowed_extension",
                path=path,
                line=0,
                message=f"Đuôi file '{ext}' không được phép trên nền tảng {platform}",
                severity="block",
            ))

        # 2.4 LỚP 3: KIỂM TRA TỆP NGOÀI MÃ (NON-CODE CHECKS)
        # 2.4.1 Plist launchd persistence
        if ext == ".plist":
            if _LAUNCHD_PERSISTENCE_RE.search(content):
                violations.append(Violation(
                    rule="persistence_launchd",
                    path=path,
                    line=1,
                    message="Phát hiện khóa persistence của Launchd (RunAtLoad/ProgramArguments/KeepAlive)",
                    severity="block",
                ))
            if platform == "ios_tweak":
                violations.extend(_check_tweak_filter_plist(path, content))

        # 2.4.2 Makefile & deb packaging scripts (postinst, preinst, prerm, postrm) & build.gradle
        if base_name in ("makefile", "control", "postinst", "preinst", "prerm", "postrm") or ext == ".gradle":
            if _NON_CODE_DANGEROUS_RE.search(content):
                violations.append(Violation(
                    rule="non_code_network_or_shell",
                    path=path,
                    line=1,
                    message=f"Tệp ngoài mã '{path}' chứa lệnh curl/wget/sh -c nguy hiểm",
                    severity="block",
                ))

        # 2.5 Loại bỏ comment (bảo tồn chuỗi ký tự) để quét mã
        clean_text = _strip_comments_preserving_strings(content, path)

        # Một thẻ manifest hoặc phép nối literal có thể trải qua nhiều dòng.
        if base_name == "androidmanifest.xml":
            for match in _ANDROID_EXPORTED_RE.finditer(clean_text):
                violations.append(Violation(
                    rule="exported_component", path=path,
                    line=clean_text.count("\n", 0, match.start()) + 1,
                    message="Thành phần Android exported=true tăng nguy cơ tấn công IPC",
                    severity="block",
                ))
        for match in _CONCAT_LITERAL_REGEX.finditer(clean_text):
            concat_err = _check_string_concatenation_evasion(match.group(0))
            if concat_err:
                violations.append(Violation(
                    rule="string_concat_evasion", path=path,
                    line=clean_text.count("\n", 0, match.start()) + 1,
                    message=concat_err, severity="block",
                ))

        # 2.6 Quét đa dòng (Multi-line warning)
        for match in _WARN_INFINITE_LOOP_RE.finditer(clean_text):
            line_no = clean_text[:match.start()].count("\n") + 1
            violations.append(Violation(
                rule="warn_infinite_loop",
                path=path,
                line=line_no,
                message="Vòng lặp vô hạn kết hợp sleep — nguy cơ gây đơ hoặc nóng máy",
                severity="warn",
            ))

        # 2.7 Quét từng dòng (Single-line rules)
        for line_idx, line in _logical_lines(clean_text):
            line_str = line.strip()
            if not line_str:
                continue

            # ── LỚP 2: ALLOW-LIST NHẬP KHẨU (IMPORT ALLOW-LIST) ──
            import_err = _check_import_allowlist(
                line_str,
                ext,
                platform,
                allow_network=allow_network,
                allow_sensitive=allow_sens,
                project_paths=project_paths,
                current_path=path,
            )
            if import_err:
                violations.append(Violation(
                    rule="import_not_allowed",
                    path=path,
                    line=line_idx,
                    message=import_err,
                    severity="block",
                ))

            # ── CHỐNG NÉ TRÁNH GHÉP CHUỖI (STRING CONCAT EVASION) ──
            concat_err = _check_string_concatenation_evasion(line_str)
            if concat_err:
                violations.append(Violation(
                    rule="string_concat_evasion",
                    path=path,
                    line=line_idx,
                    message=concat_err,
                    severity="block",
                ))

            # ── KIỂM TRA LỚP ĐỘNG (NSClassFromString / Class.forName) ──
            dyn_err = _check_dynamic_class_lookup(line_str, platform)
            if dyn_err:
                violations.append(Violation(
                    rule="dynamic_lookup",
                    path=path,
                    line=line_idx,
                    message=dyn_err,
                    severity="block",
                ))

            # ── QUY TẮC MẠNG (NETWORK) ──
            if not allow_network:
                if _NETWORK_BASE_RE.search(line_str):
                    violations.append(Violation(
                        rule="network",
                        path=path,
                        line=line_idx,
                        message="Phát hiện lệnh/lớp kết nối mạng khi chưa được phép",
                        severity="block",
                    ))
                if ext in (".x", ".xm", ".m", ".mm", ".c", ".cpp") and _NETWORK_EXPANDED_IOS_RE.search(line_str):
                    violations.append(Violation(
                        rule="network",
                        path=path,
                        line=line_idx,
                        message="Phát hiện API mạng Foundation/CoreNetworking/AFNetworking không được phép",
                        severity="block",
                    ))
                if ext == ".swift" and _NETWORK_EXPANDED_SWIFT_RE.search(line_str):
                    violations.append(Violation(
                        rule="network",
                        path=path,
                        line=line_idx,
                        message="Phát hiện Data(contentsOf)/NWConnection trong Swift khi chưa được phép",
                        severity="block",
                    ))
                if ext in (".java", ".kt", ".smali") and _NETWORK_EXPANDED_ANDROID_RE.search(line_str):
                    violations.append(Violation(
                        rule="network",
                        path=path,
                        line=line_idx,
                        message="Phát hiện API mạng Android/Java (Socket/openStream/HttpsURLConnection/Ktor/CIO)",
                        severity="block",
                    ))
                if base_name == "androidmanifest.xml" and _NETWORK_MANIFEST_RE.search(line_str):
                    violations.append(Violation(
                        rule="network",
                        path=path,
                        line=line_idx,
                        message="Quyền INTERNET trong AndroidManifest bị chặn khi allow_network=False",
                        severity="block",
                    ))

            # ── QUY TẮC DỮ LIỆU RIÊNG TƯ (PRIVACY) ──
            for grp_name, grp_info in _PRIVACY_GROUPS.items():
                if grp_name not in allow_sens:
                    if grp_info["pattern"].search(line_str):
                        violations.append(Violation(
                            rule=f"privacy_{grp_name}",
                            path=path,
                            line=line_idx,
                            message=f"Truy cập dữ liệu riêng tư ({grp_info['desc']}) khi chưa được cấp phép",
                            severity="block",
                        ))

            # Keychain / Mật khẩu / Token (luôn chặn)
            if _PRIVACY_CREDENTIALS_RE.search(line_str):
                violations.append(Violation(
                    rule="privacy_credentials",
                    path=path,
                    line=line_idx,
                    message="Truy cập Keychain/KeyStore/AccountManager lưu trữ mật khẩu/token",
                    severity="block",
                ))

            # Clipboard & Keylogger
            if _CLIPBOARD_RE.search(line_str):
                violations.append(Violation(
                    rule="clipboard_access",
                    path=path,
                    line=line_idx,
                    message="Đọc dữ liệu bảng nhớ tạm (UIPasteboard / ClipboardManager)",
                    severity="block",
                ))

            if _KEYLOGGER_RE.search(line_str):
                violations.append(Violation(
                    rule="keylogger_hook",
                    path=path,
                    line=line_idx,
                    message="Hook trường nhập liệu bàn phím (UITextField/UIKeyboard/IOHIDEvent)",
                    severity="block",
                ))

            # ── QUY TẮC TIẾN TRÌNH / TẢI MÃ / SHELL (EXECUTION) ──
            if _EXECUTION_RE.search(line_str):
                violations.append(Violation(
                    rule="execution",
                    path=path,
                    line=line_idx,
                    message="Phát hiện thực thi tiến trình hệ thống, Process() hoặc dynamic loader",
                    severity="block",
                ))

            if _DYNAMIC_CODE_RE.search(line_str):
                violations.append(Violation(
                    rule="dynamic_execution",
                    path=path,
                    line=line_idx,
                    message="Phát hiện System.load, performSelector, objc_msgSend hoặc Method.invoke",
                    severity="block",
                ))

            if _SHELL_EMBEDDED_RE.search(line_str):
                violations.append(Violation(
                    rule="shell_embedded",
                    path=path,
                    line=line_idx,
                    message="Phát hiện chuỗi lệnh shell nhúng (/bin/sh, su, curl, wget, -c)",
                    severity="block",
                ))

            if _ACTION_VIEW_RE.search(line_str):
                violations.append(Violation(
                    rule="action_view_intent",
                    path=path,
                    line=line_idx,
                    message="Khởi chạy Intent.ACTION_VIEW với URL ngoài",
                    severity="block",
                ))

            if _SETTINGS_SECURE_RE.search(line_str):
                violations.append(Violation(
                    rule="settings_tampering",
                    path=path,
                    line=line_idx,
                    message="Can thiệp cài đặt hệ thống Settings.Secure / Settings.Global",
                    severity="block",
                ))

            # ── QUY TẮC MỜ / GIẤU / OBFUSCATION ──
            if _MALICIOUS_DESTINATIONS_RE.search(line_str):
                violations.append(Violation(
                    rule="obfuscation_c2",
                    path=path,
                    line=line_idx,
                    message="Phát hiện đích kết nối nghi vấn độc hại (.onion, pastebin, discord, telegram)",
                    severity="block",
                ))
            elif _SUSPICIOUS_URL_RE.search(line_str):
                # Cho phép URL scheme prefs: trên iOS và URI content: được quản lý riêng
                if not line_str.startswith("prefs:") and "prefs:" not in line_str and "content://" not in line_str:
                    violations.append(Violation(
                        rule="hardcoded_url",
                        path=path,
                        line=line_idx,
                        message="Phát hiện địa chỉ URL từ xa gán cứng trong mã nguồn",
                        severity="block",
                    ))

            if _IPV4_RE.search(line_str):
                violations.append(Violation(
                    rule="hardcoded_ip",
                    path=path,
                    line=line_idx,
                    message="Phát hiện địa chỉ IP gán cứng trong mã nguồn",
                    severity="block",
                ))

            if _LONG_BASE64_HEX_RE.search(line_str):
                violations.append(Violation(
                    rule="obfuscation_payload",
                    path=path,
                    line=line_idx,
                    message="Phát hiện chuỗi Base64/Hex dài (>200 ký tự) nghi vấn payload ẩn",
                    severity="block",
                ))

            if _CRYPTO_WALLET_RE.search(line_str):
                violations.append(Violation(
                    rule="crypto_wallet",
                    path=path,
                    line=line_idx,
                    message="Phát hiện địa chỉ ví tiền mã hóa gán cứng",
                    severity="block",
                ))

            if _COIN_MINING_RE.search(line_str):
                violations.append(Violation(
                    rule="coin_mining",
                    path=path,
                    line=line_idx,
                    message="Phát hiện từ khóa công cụ đào coin (stratum, xmrig, cryptonight)",
                    severity="block",
                ))

            if _XOR_DECRYPT_RE.search(line_str):
                violations.append(Violation(
                    rule="xor_obfuscation",
                    path=path,
                    line=line_idx,
                    message="Phát hiện thuật toán giải mã XOR nghi vấn che giấu shellcode",
                    severity="block",
                ))

            if _OBFUSCATED_VAR_RE.search(line_str):
                violations.append(Violation(
                    rule="obfuscated_identifier",
                    path=path,
                    line=line_idx,
                    message="Phát hiện định danh biến/hàm bị làm mờ dạng ngẫu nhiên (_0x...)",
                    severity="block",
                ))

            # ── QUY TẮC LEO THANG ĐẶC QUYỀN (PRIVILEGE) ──
            if _PRIVILEGE_OS_RE.search(line_str):
                violations.append(Violation(
                    rule="privilege_os",
                    path=path,
                    line=line_idx,
                    message="Lệnh can thiệp quyền hệ điều hành (setuid/setgid/mount/ptrace/chmod)",
                    severity="block",
                ))

            if _DANGEROUS_ENTITLEMENTS_RE.search(line_str):
                violations.append(Violation(
                    rule="dangerous_entitlements",
                    path=path,
                    line=line_idx,
                    message="Entitlement nguy hiểm (platform-application, private, get-task-allow)",
                    severity="block",
                ))

            if _DANGEROUS_ANDROID_PERMS_RE.search(line_str):
                violations.append(Violation(
                    rule="dangerous_permission",
                    path=path,
                    line=line_idx,
                    message="Quyền Android nguy hiểm cao (REQUEST_INSTALL_PACKAGES, RECEIVE_BOOT_COMPLETED...)",
                    severity="block",
                ))

            # ── GHI ĐÈ FILE HỆ THỐNG ──
            if _SYSTEM_TAMPERING_RE.search(line_str):
                violations.append(Violation(
                    rule="system_tampering",
                    path=path,
                    line=line_idx,
                    message="Truy cập / ghi đè trực tiếp đường dẫn hệ thống (/System, /private/var...)",
                    severity="block",
                ))

            # ── CẢNH BÁO (WARN) ──
            if _WARN_PRIVATE_API_RE.search(line_str):
                violations.append(Violation(
                    rule="warn_private_api",
                    path=path,
                    line=line_idx,
                    message="Sử dụng MSHookMessageEx trên lớp hệ thống — cần kiểm tra tương thích",
                    severity="warn",
                ))

    return violations
