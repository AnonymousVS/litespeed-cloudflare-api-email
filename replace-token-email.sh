#!/bin/bash
# =============================================================
#  replace-token-email.sh v3.1
#  Bulk Update Cloudflare API Token
#  LiteSpeed Cache › CDN › Cloudflare
# ============================================================
#  Updated: 2026-04-21 19:00 (UTC+7)
#  Repo   : https://github.com/AnonymousVS/Litespeed-Cloudflare-Api-Update
# =============================================================
# ไฟล์ Config (3 ไฟล์):
#   1. server-config.conf (public repo)
#      → CPANEL_USERS, Telegram, ตัวเลือก
#   2. domains.csv (public repo)
#      → รายชื่อ domain + CF email (ว่าง = ทุกเว็บ)
#   3. Litespeed-Cloudflare-Api-Update.conf (private repo: AnonymousVS/config)
#      → CF_TOKENS["email"]="cfut_token" (หลาย account)
#      → หรือ CF_TOKEN="cfut_xxxxx" (token เดียว ทุกเว็บ)
# =============================================================
# วิธีรัน:
#   GH_TOKEN="ghp_xxxxx"
#   curl -s -H "Authorization: token $GH_TOKEN" \
#       https://raw.githubusercontent.com/AnonymousVS/config/main/Litespeed-Cloudflare-Api-Update.conf \
#       -o /tmp/Litespeed-Cloudflare-Api-Update.conf && \
#   curl -s https://raw.githubusercontent.com/AnonymousVS/Litespeed-Cloudflare-Api-Update/main/server-config.conf \
#       -o /tmp/server-config.conf && \
#   curl -s https://raw.githubusercontent.com/AnonymousVS/Litespeed-Cloudflare-Api-Update/main/domains.csv \
#       -o /tmp/domains.csv && \
#   bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/Litespeed-Cloudflare-Api-Update/main/replace-token-email.sh)
# =============================================================
# CHANGELOG:
# v3.1 (2026-04-21)
#   - เพิ่ม domains.csv: ระบุ domain + Cloudflare email เฉพาะเจาะจง
#   - Multi-token: แต่ละ CF account มี token ของตัวเอง (CF_TOKENS map)
#   - Backward compatible: CF_TOKEN เดียวยังใช้ได้ (Format A)
#   - per-domain email + token: ดึง Zone ID ด้วย token ที่ถูกต้อง
#   - domains.csv ว่าง/ไม่มี = แก้ทุกเว็บ + ใช้ _default token
#   - Repo ย้ายไป AnonymousVS/Litespeed-Cloudflare-Api-Update
# v3 (2026-04-20)
#   - แยก config: server-config.conf (public) + CF Token (private)
#   - WordPress API Token (cfut_) เท่านั้น — ห้ามใช้ Global Key
#   - เพิ่ม CPANEL_USERS + Telegram notification + Spinner
# v1 (เดิม)
#   - Single config file, auto-detect จาก CF_EMAIL
# =============================================================

VERSION="v3.1"
PRIVATE_REPO="AnonymousVS/config"
PUBLIC_REPO="AnonymousVS/Litespeed-Cloudflare-Api-Update"
CF_TOKEN_FILE="Litespeed-Cloudflare-Api-Update.conf"
SERVER_CONFIG_FILE="server-config.conf"
DOMAINS_CSV_FILE="domains.csv"

# ─── ค้นหา + โหลด server-config.conf ────────────────────────
SERVER_CONFIG=""
if [[ -f "/tmp/$SERVER_CONFIG_FILE" ]]; then
    SERVER_CONFIG="/tmp/$SERVER_CONFIG_FILE"
elif [[ -f "/usr/local/etc/litespeed-cloudflare/$SERVER_CONFIG_FILE" ]]; then
    SERVER_CONFIG="/usr/local/etc/litespeed-cloudflare/$SERVER_CONFIG_FILE"
else
    echo "📥 ดาวน์โหลด server-config.conf จาก GitHub..."
    curl -fsSL "https://raw.githubusercontent.com/$PUBLIC_REPO/main/server-config.conf" \
        -o "/tmp/$SERVER_CONFIG_FILE" 2>/dev/null
    if [[ $? -eq 0 && -s "/tmp/$SERVER_CONFIG_FILE" ]]; then
        SERVER_CONFIG="/tmp/$SERVER_CONFIG_FILE"
    else
        echo "❌ ดาวน์โหลด server-config.conf ไม่สำเร็จ"
        exit 1
    fi
fi
echo "📄 Server Config: $SERVER_CONFIG"
source "$SERVER_CONFIG"

# ─── ค้นหา + โหลด domains.csv (optional) ────────────────────
# Format: domain,cf_email
# ถ้ามี domain → แก้เฉพาะ domain ที่ระบุ + ใช้ email ตาม CSV
# ถ้าว่าง / ไม่มี → แก้ทุกเว็บตาม CPANEL_USERS
DOMAINS_CSV=""
declare -A TARGET_DOMAINS
declare -A DOMAIN_CF_EMAIL
TARGET_DOMAIN_COUNT=0

if [[ -f "/tmp/$DOMAINS_CSV_FILE" ]]; then
    DOMAINS_CSV="/tmp/$DOMAINS_CSV_FILE"
elif [[ -f "/usr/local/etc/litespeed-cloudflare/$DOMAINS_CSV_FILE" ]]; then
    DOMAINS_CSV="/usr/local/etc/litespeed-cloudflare/$DOMAINS_CSV_FILE"
else
    # ดาวน์โหลดจาก public repo (optional — ไม่ error ถ้าไม่มี)
    curl -fsSL "https://raw.githubusercontent.com/$PUBLIC_REPO/main/domains.csv" \
        -o "/tmp/$DOMAINS_CSV_FILE" 2>/dev/null
    if [[ $? -eq 0 && -s "/tmp/$DOMAINS_CSV_FILE" ]]; then
        DOMAINS_CSV="/tmp/$DOMAINS_CSV_FILE"
    fi
fi

if [[ -n "$DOMAINS_CSV" ]]; then
    while IFS=',' read -r _dom _email; do
        _dom=$(echo "$_dom" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        _email=$(echo "$_email" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
        [[ -z "$_dom" || "$_dom" == "domain" ]] && continue
        TARGET_DOMAINS["$_dom"]=1
        DOMAIN_CF_EMAIL["$_dom"]="$_email"
        TARGET_DOMAIN_COUNT=$((TARGET_DOMAIN_COUNT+1))
    done < "$DOMAINS_CSV"
    echo "📋 domains.csv: $DOMAINS_CSV ($TARGET_DOMAIN_COUNT domains)"
else
    echo "📋 domains.csv: ไม่มี (แก้ทุกเว็บ)"
fi

# ─── ค้นหา + โหลด CF Token (private repo) ───────────────────
# Format: declare -A CF_TOKENS; CF_TOKENS["email"]="cfut_token"
# ค้นหาตามลำดับ:
#   1. /tmp/Litespeed-Cloudflare-Api-Update.conf
#   2. /usr/local/etc/litespeed-cloudflare/Litespeed-Cloudflare-Api-Update.conf
#   3. /root/Litespeed-Cloudflare-Api-Update.conf
#   4. ถาม GitHub PAT → ดึงจาก private repo
TOKEN_CONFIG=""
if [[ -f "/tmp/$CF_TOKEN_FILE" ]]; then
    TOKEN_CONFIG="/tmp/$CF_TOKEN_FILE"
elif [[ -f "/usr/local/etc/litespeed-cloudflare/$CF_TOKEN_FILE" ]]; then
    TOKEN_CONFIG="/usr/local/etc/litespeed-cloudflare/$CF_TOKEN_FILE"
elif [[ -f "/root/$CF_TOKEN_FILE" ]]; then
    TOKEN_CONFIG="/root/$CF_TOKEN_FILE"
fi

if [[ -z "$TOKEN_CONFIG" ]]; then
    echo ""
    echo "⚠️  ไม่พบ CF Token config — ดึงจาก private repo..."
    read -rp "  GitHub PAT (ghp_xxxxx): " GH_TOKEN
    if [[ -n "$GH_TOKEN" ]]; then
        curl -fsSL -H "Authorization: token $GH_TOKEN" \
            "https://raw.githubusercontent.com/$PRIVATE_REPO/main/$CF_TOKEN_FILE" \
            -o "/tmp/$CF_TOKEN_FILE" 2>/dev/null
        if [[ $? -eq 0 && -s "/tmp/$CF_TOKEN_FILE" ]]; then
            TOKEN_CONFIG="/tmp/$CF_TOKEN_FILE"
            echo "✅ ดาวน์โหลดสำเร็จ"
        else
            echo "❌ ดาวน์โหลดไม่สำเร็จ — ตรวจสอบ PAT + repo"
            exit 1
        fi
    else
        echo "❌ ต้องมี CF Token config"
        exit 1
    fi
fi
echo "🔑 CF Token: $TOKEN_CONFIG"

# โหลด config — รองรับ 2 format:
#   Format A (เดิม): CF_TOKEN="cfut_xxxxx" (token เดียว ทุกเว็บ)
#   Format B (ใหม่): CF_TOKENS["email"]="cfut_xxxxx" (token ต่อ email)
declare -A CF_TOKENS
CF_TOKEN=""
source "$TOKEN_CONFIG"

# ─── Validate tokens ──────────────────────────────────────────
TOKEN_COUNT=${#CF_TOKENS[@]}
if [[ $TOKEN_COUNT -gt 0 ]]; then
    # Format B: multi-token
    echo "📋 CF Tokens: $TOKEN_COUNT accounts"
    BAD_TOKENS=0
    for _email in "${!CF_TOKENS[@]}"; do
        _tok="${CF_TOKENS[$_email]}"
        if [[ "$_tok" != cfut_* ]]; then
            echo "❌ Token ของ $_email ไม่ใช่ cfut_ — ห้ามใช้ Global Key"
            BAD_TOKENS=$((BAD_TOKENS+1))
        fi
    done
    [[ $BAD_TOKENS -gt 0 ]] && exit 1
elif [[ -n "$CF_TOKEN" ]]; then
    # Format A: single token → ใส่ทุก email ใน CF_TOKENS
    if [[ "$CF_TOKEN" != cfut_* ]]; then
        echo "❌ ERROR: ต้องใช้ WordPress API Token (cfut_) เท่านั้น — ห้ามใช้ Global Key"
        exit 1
    fi
    echo "📋 CF Token: 1 token (ใช้ทุกเว็บ)"
    # map ทุก email ใน domains.csv → token เดียว
    if [[ $TARGET_DOMAIN_COUNT -gt 0 ]]; then
        for _dom in "${!DOMAIN_CF_EMAIL[@]}"; do
            _em="${DOMAIN_CF_EMAIL[$_dom]}"
            [[ -n "$_em" && -z "${CF_TOKENS[$_em]+_}" ]] && CF_TOKENS["$_em"]="$CF_TOKEN"
        done
    fi
    # fallback สำหรับเว็บที่ไม่มี email ใน CSV
    CF_TOKENS["_default"]="$CF_TOKEN"
else
    echo "❌ ERROR: ไม่พบ CF_TOKEN หรือ CF_TOKENS ใน config"
    exit 1
fi

# ─── แสดงค่าที่จะใช้ + ขอ Confirm ──────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════"
echo "║   🔄  replace-token-email.sh  $VERSION"
echo "║   WordPress API Token → LiteSpeed Cache CDN"
echo "╠══════════════════════════════════════════════════════════════"
echo "║"
echo "║   Auth Mode    :  Bearer (cfut_ WordPress Token)"
echo "║   CF Accounts  :  ${#CF_TOKENS[@]} token(s)"
for _tk_email in "${!CF_TOKENS[@]}"; do
    [[ "$_tk_email" == "_default" ]] && continue
    _tk_val="${CF_TOKENS[$_tk_email]}"
    printf "║     %-35s %s...%s\n" "$_tk_email" "${_tk_val:0:8}" "${_tk_val: -4}"
done
[[ -n "${CF_TOKENS[_default]+_}" ]] && echo "║     (default)                              ${CF_TOKENS[_default]:0:8}...${CF_TOKENS[_default]: -4}"
echo "║"
echo "║   cPanel Users :  ${CPANEL_USERS:-"(ทุก user บน server)"}"
echo "║   domains.csv  :  ${TARGET_DOMAIN_COUNT:-0} domains ${TARGET_DOMAIN_COUNT:+(เฉพาะ domain ที่ระบุ)}"
echo "║   Only Active  :  $CF_ONLY_ACTIVE"
echo "║   Overwrite Key:  $CF_OVERWRITE_KEY"
echo "║   Telegram     :  ${TELEGRAM_BOT_TOKEN:+ON}${TELEGRAM_BOT_TOKEN:-OFF}"
echo "║"
echo "╚══════════════════════════════════════════════════════════════"
echo ""
read -rp "  ▶  ยืนยันการเปลี่ยนค่า? [y/N] : " _CONFIRM
echo ""
if [[ ! "$_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "🚫 ยกเลิกการทำงาน"
    exit 0
fi

# ─── ค่า Runtime ─────────────────────────────────────────────
MAX_JOBS=5
WP_TIMEOUT=30
MAX_RETRY=3
RETRY_DELAY=5

LOG_FILE="/var/log/lscwp-cf-update.log"
LOG_PASS="/var/log/lscwp-cf-update-pass.log"
LOG_FAIL="/var/log/lscwp-cf-update-fail.log"
LOG_SKIP="/var/log/lscwp-cf-update-skip.log"
LOG_NOCHANGE="/var/log/lscwp-cf-update-nochange.log"
LOG_MISMATCH="/var/log/lscwp-cf-update-mismatch.log"
LOCK_FILE="${LOG_FILE}.lock"
RESULT_DIR="/tmp/lscwp-cf-update-$$"
mkdir -p "$RESULT_DIR"

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$1"
    ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
}

cleanup() {
    # หยุด spinner/progress ถ้ายังทำงานอยู่
    [[ -n "$spinner_pid" ]] && kill "$spinner_pid" 2>/dev/null
    [[ -n "$PROGRESS_PID" ]] && kill "$PROGRESS_PID" 2>/dev/null
    wait
    rm -rf "$RESULT_DIR"
    rm -f "$LOCK_FILE" \
          "${LOG_FILE}.pass.lock" "${LOG_FILE}.fail.lock" \
          "${LOG_FILE}.skip.lock" "${LOG_FILE}.nochange.lock" \
          "${LOG_FILE}.mismatch.lock"
}
PROGRESS_PID=""
trap cleanup EXIT

# ─── ตรวจ WP-CLI ─────────────────────────────────────────────
if ! command -v wp &>/dev/null; then
    log "❌ ERROR: ไม่พบ WP-CLI — https://wp-cli.org"
    exit 1
fi

# ─── ล้าง log ────────────────────────────────────────────────
> "$LOG_FILE"
> "$LOG_PASS"
> "$LOG_FAIL"
> "$LOG_SKIP"
> "$LOG_NOCHANGE"
> "$LOG_MISMATCH"

START_TIME=$(date +%s)
log "======================================"
log " BULK UPDATE CF CREDENTIALS (LiteSpeed)  $VERSION"
log " เริ่มเวลา    : $(date '+%Y-%m-%d %H:%M:%S')"
log " Server Config: $SERVER_CONFIG"
log " CF Token     : $TOKEN_CONFIG (${#CF_TOKENS[@]} accounts)"
log " domains.csv  : ${DOMAINS_CSV:-"(ไม่มี — แก้ทุกเว็บ)"} (${TARGET_DOMAIN_COUNT} domains)"
log " Auth Mode    : Bearer (WordPress API Token cfut_)"
log " cPanel Users : ${CPANEL_USERS:-"(ทุก user บน server)"}"
log " Only Active  : $CF_ONLY_ACTIVE"
log " Overwrite Key: $CF_OVERWRITE_KEY"
log " Telegram     : ${TELEGRAM_BOT_TOKEN:+ON}${TELEGRAM_BOT_TOKEN:-OFF}"
log " Jobs         : $MAX_JOBS"
log "======================================"

# ─── Spinner ──────────────────────────────────────────────────
SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
spinner_pid=""
start_spinner() {
    local msg="$1"
    (
        local i=0
        while true; do
            printf "\r  %s %s " "${SPINNER_CHARS:i%${#SPINNER_CHARS}:1}" "$msg"
            i=$((i+1))
            sleep 0.1
        done
    ) &
    spinner_pid=$!
}
stop_spinner() {
    [[ -n "$spinner_pid" ]] && kill "$spinner_pid" 2>/dev/null && wait "$spinner_pid" 2>/dev/null
    spinner_pid=""
    printf "\r\033[K"
}

# ─── ค้นหา WordPress ─────────────────────────────────────────
# CPANEL_USERS ว่าง = scan ทุก user
# CPANEL_USERS ระบุ = scan เฉพาะ user ที่กำหนด
declare -A _SEEN
DIRS=()

if [[ -n "$CPANEL_USERS" ]]; then
    # ─── Scan เฉพาะ user ที่ระบุ ──────────────────────────────
    log "🔍 Scan เฉพาะ: $CPANEL_USERS"
    start_spinner "Scanning WordPress installations..."
    for _usr in $CPANEL_USERS; do
        _uhome=$(getent passwd "$_usr" 2>/dev/null | cut -d: -f6)
        if [[ ! -d "$_uhome" ]]; then
            log "⚠️  User $_usr ไม่พบ home directory — ข้าม"
            continue
        fi
        while IFS= read -r -d '' _wpc; do
            _d="$(dirname "$_wpc")/"
            [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
        done < <(find "$_uhome" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
    done
else
    # ─── Scan ทุก user ────────────────────────────────────────
    start_spinner "Scanning WordPress installations..."
    if [[ -f /etc/trueuserdomains ]]; then
        while IFS=' ' read -r _dom _usr _rest; do
            _usr="${_usr%:}"
            [[ -z "$_usr" ]] && continue
            _uhome=$(getent passwd "$_usr" 2>/dev/null | cut -d: -f6)
            [[ -d "$_uhome" ]] || continue
            while IFS= read -r -d '' _wpc; do
                _d="$(dirname "$_wpc")/"
                [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
            done < <(find "$_uhome" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
        done < /etc/trueuserdomains
    fi

    for _base in /home /home2 /home3 /home4 /home5 /usr/home; do
        [[ -d "$_base" ]] || continue
        while IFS= read -r -d '' _wpc; do
            _d="$(dirname "$_wpc")/"
            [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
        done < <(find "$_base" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
    done
fi
stop_spinner

# ─── Filter ตาม domains.csv (ถ้ามี) ─────────────────────────
if [[ $TARGET_DOMAIN_COUNT -gt 0 ]]; then
    FILTERED_DIRS=()
    for dir in "${DIRS[@]}"; do
        _folder=$(basename "${dir%/}")
        if [[ "$_folder" == "public_html" ]]; then
            _folder=$(basename "$(dirname "${dir%/}")")
        fi
        _folder=$(echo "$_folder" | tr '[:upper:]' '[:lower:]')
        if [[ -n "${TARGET_DOMAINS[$_folder]+_}" ]]; then
            FILTERED_DIRS+=("$dir")
        fi
    done
    log "🎯 Filter domains.csv: ${#DIRS[@]} → ${#FILTERED_DIRS[@]} เว็บ"
    DIRS=("${FILTERED_DIRS[@]}")
fi

TOTAL=${#DIRS[@]}
log "พบ WordPress  : $TOTAL เว็บ"
log "======================================"

# ─── ฟังก์ชัน process แต่ละเว็บ ──────────────────────────────
process_site() {
    local dir="$1"
    local COUNT="$2"
    local TOTAL="$3"
    local SITE_CF_EMAIL="$4"
    local SITE_CF_TOKEN="$5"
    local SITE UNIQ
    SITE=$(echo "$dir" | sed 's|/home[0-9]*/||;s|/$||')
    UNIQ="${BASHPID}_$(date +%s%N)"
    local LABEL="[$COUNT/$TOTAL] $SITE"

    if [[ "$dir" =~ /public_html/$ ]]; then
        return
    fi

    _log() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$1"
        ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
    }
    _log_r() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        case "$1" in
            pass)     ( flock 201; echo "[$ts] $2" >> "$LOG_PASS"     ) 201>"${LOG_FILE}.pass.lock" ;;
            fail)     ( flock 202; echo "[$ts] $2" >> "$LOG_FAIL"     ) 202>"${LOG_FILE}.fail.lock" ;;
            skip)     ( flock 203; echo "[$ts] $2" >> "$LOG_SKIP"     ) 203>"${LOG_FILE}.skip.lock" ;;
            nochange) ( flock 204; echo "[$ts] $2" >> "$LOG_NOCHANGE" ) 204>"${LOG_FILE}.nochange.lock" ;;
            mismatch) ( flock 205; echo "[$ts] $2" >> "$LOG_MISMATCH" ) 205>"${LOG_FILE}.mismatch.lock" ;;
        esac
    }

    EVAL_OUT=$(timeout "$WP_TIMEOUT" wp --path="$dir" eval '
        // ── 1. Plugin active? ────────────────────────────────
        if (!is_plugin_active("litespeed-cache/litespeed-cache.php")) {
            echo "STATUS:NOPLUGIN"; return;
        }

        // ── 2. อ่าน options ปัจจุบัน ─────────────────────────
        $cur_enabled = get_option("litespeed.conf.cdn-cloudflare",       "0");
        $cur_key     = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",   ""));
        $cur_email   = trim((string) get_option("litespeed.conf.cdn-cloudflare_email", ""));
        $cur_zone    = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone",  ""));
        $cur_name    = trim((string) get_option("litespeed.conf.cdn-cloudflare_name",  ""));

        // ── 3. CF_ONLY_ACTIVE : ข้ามถ้า CF ปิดอยู่ ───────────
        $only_active = ('"'"'$CF_ONLY_ACTIVE'"'"' === "yes");
        if ($only_active && (!$cur_enabled || $cur_enabled === "0")) {
            echo "STATUS:SKIP_CFOFF"; return;
        }

        // ── 4. CF_OVERWRITE_KEY : ข้ามถ้ามี key อยู่แล้ว ────
        $overwrite = ('"'"'$CF_OVERWRITE_KEY'"'"' === "yes");
        if (!$overwrite && $cur_key !== "") {
            printf("STATUS:NOCHANGE\tOLD_KEY:%s\tDOMAIN:%s", substr($cur_key,0,8), $cur_name);
            return;
        }

        // ── 5. Auto-fix domain ให้ตรงกับ folder ──────────────
        $folder = basename(rtrim(ABSPATH, "/"));
        if ($folder === "public_html") {
            $folder = basename(dirname(rtrim(ABSPATH, "/")));
        }
        $name_clean = preg_replace("#^https?://#", "", rtrim($cur_name, "/"));
        $was_fixed  = false;
        if ($folder && $name_clean && $folder !== $name_clean) {
            $cur_name  = $folder;
            $was_fixed = true;
        }

        // ── 6. เขียน Credentials ใหม่ลง DB ───────────────────
        $new_key   = '"'"'$SITE_CF_TOKEN'"'"';
        $new_email = '"'"'$SITE_CF_EMAIL'"'"';

        update_option("litespeed.conf.cdn-cloudflare",      "1");
        update_option("litespeed.conf.cdn-cloudflare_key",   $new_key);
        update_option("litespeed.conf.cdn-cloudflare_email", $new_email);
        update_option("litespeed.conf.cdn-cloudflare_name",  $cur_name);
        update_option("litespeed.conf.cdn-cloudflare_zone",  "");
        update_option("litespeed.conf.cdn-cloudflare_clear", "1");
        update_option("litespeed.conf.cdn",                  "1");

        // ── 7. ดึง Zone ID จาก Cloudflare API ────────────────
        $max_retry   = '"'"'$MAX_RETRY'"'"';
        $retry_delay = '"'"'$RETRY_DELAY'"'"';
        $zone_id     = "";
        $zone_name   = "";
        $cf_error    = "";
        $attempt     = 0;

        // Bearer auth เท่านั้น (WordPress API Token)
        $headers = ["Authorization: Bearer $new_key", "Content-Type: application/json"];

        while ($attempt < $max_retry) {
            $attempt++;
            $url = "https://api.cloudflare.com/client/v4/zones?status=active&match=all&name=" . urlencode($cur_name);
            $ch  = curl_init();
            curl_setopt($ch, CURLOPT_URL,            $url);
            curl_setopt($ch, CURLOPT_HTTPHEADER,     $headers);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT,        10);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
            $raw      = curl_exec($ch);
            $http     = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curl_err = curl_error($ch);
            curl_close($ch);

            if ($curl_err) {
                $cf_error = "curl:" . $curl_err;
                if ($attempt < $max_retry) { sleep($retry_delay); continue; }
                break;
            }
            $res = json_decode($raw, true);
            if ($http !== 200 || empty($res["success"])) {
                $cf_error = "http:" . $http . " err:" . json_encode($res["errors"] ?? []);
                if ($attempt < $max_retry) { sleep($retry_delay); continue; }
                break;
            }
            $zone_id   = $res["result"][0]["id"]   ?? "";
            $zone_name = $res["result"][0]["name"] ?? $cur_name;
            if ($zone_id) break;
            $cf_error = "zone_empty";
            if ($attempt < $max_retry) sleep($retry_delay);
        }

        // ── 8. บันทึก Zone ID ลง DB ──────────────────────────
        if ($zone_id) {
            update_option("litespeed.conf.cdn-cloudflare_zone", $zone_id);
            update_option("litespeed.conf.cdn-cloudflare_name", $zone_name);
        }

        // ── 9. Verify ─────────────────────────────────────────
        $v_key   = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",   ""));
        $v_zone  = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone",  ""));
        $v_email = trim((string) get_option("litespeed.conf.cdn-cloudflare_email", ""));
        $key_ok  = ($v_key === $new_key) ? 1 : 0;

        printf(
            "STATUS:DONE\tKEY_OK:%d\tDOMAIN:%s\tOLD_KEY:%s\tNEW_KEY:%s\tOLD_EMAIL:%s\tNEW_EMAIL:%s\tOLD_ZONE:%s\tNEW_ZONE:%s\tFIXED:%d\tATTEMPT:%d\tCF_ERROR:%s",
            $key_ok,
            $zone_name ?: $cur_name,
            substr($cur_key,  0, 8),
            substr($v_key,    0, 8),
            $cur_email,
            $v_email,
            $cur_zone ? substr($cur_zone, 0, 12)."..." : "(empty)",
            $v_zone   ?: "(no zone)",
            $was_fixed ? 1 : 0,
            $attempt,
            $cf_error
        );
    ' --allow-root 2>/dev/null)

    local STATUS
    STATUS=$(echo "$EVAL_OUT" | grep -oP '(?<=STATUS:)\w+')

    case "$STATUS" in
        DONE)
            local KEY_OK DOMAIN OLD_KEY NEW_KEY OLD_EMAIL NEW_EMAIL OLD_ZONE NEW_ZONE FIXED ATTEMPT CF_ERROR
            KEY_OK=$(    echo "$EVAL_OUT" | grep -oP '(?<=KEY_OK:)\d+')
            DOMAIN=$(    echo "$EVAL_OUT" | grep -oP '(?<=DOMAIN:)[^\t]*')
            OLD_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=OLD_KEY:)[^\t]*')
            NEW_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=NEW_KEY:)[^\t]*')
            OLD_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=OLD_EMAIL:)[^\t]*')
            NEW_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=NEW_EMAIL:)[^\t]*')
            OLD_ZONE=$(  echo "$EVAL_OUT" | grep -oP '(?<=OLD_ZONE:)[^\t]*')
            NEW_ZONE=$(  echo "$EVAL_OUT" | grep -oP '(?<=NEW_ZONE:)[^\t]*')
            FIXED=$(     echo "$EVAL_OUT" | grep -oP '(?<=FIXED:)\d+')
            ATTEMPT=$(   echo "$EVAL_OUT" | grep -oP '(?<=ATTEMPT:)\d+')
            CF_ERROR=$(  echo "$EVAL_OUT" | grep -oP '(?<=CF_ERROR:)[^\t]*')
            local FIX_TAG=""
            [[ "$FIXED" == "1" ]] && FIX_TAG=" | ⚙️ domain ถูกแก้อัตโนมัติ"

            if [[ "$KEY_OK" == "1" && "$NEW_ZONE" != "(no zone)" ]]; then
                _log  "✅ PASS: $LABEL | domain=$DOMAIN | key: ${OLD_KEY}... → ${NEW_KEY}... | zone: $OLD_ZONE → $NEW_ZONE | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
                _log_r pass "$SITE | domain=$DOMAIN | old_key=${OLD_KEY}... | new_key=${NEW_KEY}... | old_email=$OLD_EMAIL | new_email=$NEW_EMAIL | zone: $OLD_ZONE → $NEW_ZONE | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
                [[ "$FIXED" == "1" ]] && _log_r mismatch "$SITE | domain ถูกแก้อัตโนมัติ → $DOMAIN"
                touch "${RESULT_DIR}/pass_${UNIQ}"
                [[ "$FIXED" == "1" ]] && touch "${RESULT_DIR}/mismatch_${UNIQ}"
            elif [[ "$KEY_OK" == "1" && "$CF_ERROR" == "zone_empty" ]]; then
                _log  "🌐 NOTCF: $LABEL | domain=$DOMAIN | domain ไม่อยู่ใน CF account${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | key อัปเดตแล้ว แต่ domain ไม่อยู่ใน CF | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            elif [[ "$KEY_OK" == "1" ]]; then
                _log  "❌ FAIL (CF API error): $LABEL | domain=$DOMAIN | error=$CF_ERROR | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | key อัปเดตแล้ว แต่ดึง zone ไม่ได้ | error=$CF_ERROR | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            else
                _log  "❌ FAIL (verify key ไม่ผ่าน): $LABEL | domain=$DOMAIN${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | verify failed — key ไม่ตรง${FIX_TAG}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            fi
            ;;
        NOCHANGE)
            local OLD_KEY DOMAIN
            OLD_KEY=$(echo "$EVAL_OUT" | grep -oP '(?<=OLD_KEY:)[^\t]*')
            DOMAIN=$( echo "$EVAL_OUT" | grep -oP '(?<=DOMAIN:)[^\t]*')
            _log  "⏩ NOCHANGE: $LABEL | domain=$DOMAIN | มี key อยู่แล้ว (${OLD_KEY}...) ข้ามไป"
            _log_r nochange "$SITE | domain=$DOMAIN | existing_key=${OLD_KEY}..."
            touch "${RESULT_DIR}/nochange_${UNIQ}"
            ;;
        SKIP_CFOFF)
            _log  "🔴 SKIP (CF ปิดอยู่): $LABEL"
            _log_r skip "$SITE | Cloudflare=OFF ใน plugin — ข้ามตาม CF_ONLY_ACTIVE=yes"
            touch "${RESULT_DIR}/skip_${UNIQ}"
            ;;
        NOPLUGIN)
            _log  "⏭  SKIP (LiteSpeed Cache ไม่ active): $LABEL"
            _log_r skip "$SITE | plugin ไม่ active"
            touch "${RESULT_DIR}/skip_${UNIQ}"
            ;;
        *)
            _log  "❌ FAIL (wp error/timeout): $LABEL | ${EVAL_OUT:0:120}"
            _log_r fail "$SITE | wp eval ล้มเหลว | ${EVAL_OUT:0:120}"
            touch "${RESULT_DIR}/fail_${UNIQ}"
            ;;
    esac
}

export -f process_site
export LOG_FILE LOCK_FILE LOG_PASS LOG_FAIL LOG_SKIP LOG_NOCHANGE LOG_MISMATCH RESULT_DIR
export WP_TIMEOUT MAX_RETRY RETRY_DELAY CF_ONLY_ACTIVE CF_OVERWRITE_KEY

# ─── รัน parallel + progress ─────────────────────────────────
declare -a PIDS=()
COUNT=0

# Progress spinner (background)
(
    i=0
    while true; do
        _done=$(find "$RESULT_DIR" -maxdepth 1 -name "pass_*" -o -name "fail_*" -o -name "skip_*" -o -name "nochange_*" 2>/dev/null | wc -l)
        printf "\r  %s ประมวลผล [%d/%d เว็บ]  " "${SPINNER_CHARS:i%${#SPINNER_CHARS}:1}" "$_done" "$TOTAL"
        i=$((i+1))
        sleep 0.3
        [[ "$_done" -ge "$TOTAL" ]] && break
    done
) &
PROGRESS_PID=$!

for dir in "${DIRS[@]}"; do
    COUNT=$(( COUNT + 1 ))
    # หา domain name จาก folder
    _d_folder=$(basename "${dir%/}")
    [[ "$_d_folder" == "public_html" ]] && _d_folder=$(basename "$(dirname "${dir%/}")")
    _d_folder=$(echo "$_d_folder" | tr '[:upper:]' '[:lower:]')
    # หา email จาก domains.csv
    _d_email="${DOMAIN_CF_EMAIL[$_d_folder]:-}"
    # หา token จาก CF_TOKENS (email → token) หรือ _default
    _d_token=""
    if [[ -n "$_d_email" && -n "${CF_TOKENS[$_d_email]+_}" ]]; then
        _d_token="${CF_TOKENS[$_d_email]}"
    elif [[ -n "${CF_TOKENS[_default]+_}" ]]; then
        _d_token="${CF_TOKENS[_default]}"
    fi
    # ข้ามถ้าไม่มี token
    if [[ -z "$_d_token" ]]; then
        log "⚠️ [$COUNT/$TOTAL] $_d_folder → ไม่มี token สำหรับ $_d_email — ข้าม"
        touch "${RESULT_DIR}/skip_${BASHPID}_$(date +%s%N)"
        continue
    fi
    process_site "$dir" "$COUNT" "$TOTAL" "$_d_email" "$_d_token" &
    PIDS+=($!)
    if (( ${#PIDS[@]} >= MAX_JOBS )); then
        wait "${PIDS[0]}"
        PIDS=("${PIDS[@]:1}")
    fi
done
for pid in "${PIDS[@]}"; do wait "$pid"; done

kill "$PROGRESS_PID" 2>/dev/null && wait "$PROGRESS_PID" 2>/dev/null
printf "\r\033[K"
log "✅ ประมวลผลเสร็จ $TOTAL เว็บ"

# ─── สรุป ────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

SUCCESS=$(  find "$RESULT_DIR" -name "pass_*"     2>/dev/null | wc -l)
FAILED=$(   find "$RESULT_DIR" -name "fail_*"     2>/dev/null | wc -l)
SKIPPED=$(  find "$RESULT_DIR" -name "skip_*"     2>/dev/null | wc -l)
NOCHANGE=$( find "$RESULT_DIR" -name "nochange_*"  2>/dev/null | wc -l)
MISMATCH=$( find "$RESULT_DIR" -name "mismatch_*"  2>/dev/null | wc -l)

log "======================================"
log " สรุปผลรวม  $VERSION"
log " รวมทั้งหมด      : $TOTAL เว็บ"
log " ✅ Pass (อัปเดต) : $SUCCESS เว็บ"
log " ⏩ Nochange       : $NOCHANGE เว็บ  (มี key อยู่แล้ว ข้ามตาม CF_OVERWRITE_KEY=no)"
log " ❌ Fail          : $FAILED เว็บ"
log " ⏭  Skip          : $SKIPPED เว็บ  (plugin ไม่ active / CF ปิด)"
log " ⚙️  Auto-fixed    : $MISMATCH เว็บ  (domain ถูกแก้อัตโนมัติจาก folder name)"
log " เวลาที่ใช้       : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log "======================================"
log " Log รวม         : $LOG_FILE"
log " ✅ Pass          : $LOG_PASS"
log " ❌ Fail          : $LOG_FAIL"
log " ⏩ Nochange       : $LOG_NOCHANGE"
log " ⏭  Skip          : $LOG_SKIP"
log " ⚙️  Auto-fixed    : $LOG_MISMATCH"
log "======================================"

# ─── Telegram Notification ───────────────────────────────────
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    HOSTNAME=$(hostname)
    TG_MSG="🔄 *CF Token Update — $HOSTNAME*
━━━━━━━━━━━━━━━━━
✅ Pass: $SUCCESS
⏩ Nochange: $NOCHANGE
❌ Fail: $FAILED
⏭ Skip: $SKIPPED
⚙️ Auto-fixed: $MISMATCH
━━━━━━━━━━━━━━━━━
⏱ $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$TG_MSG" \
        -d parse_mode="Markdown" >/dev/null 2>&1 \
        && log "📨 Telegram notification sent" \
        || log "⚠️  Telegram notification failed"
fi

exit 0
