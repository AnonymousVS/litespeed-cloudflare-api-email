#!/bin/bash
# =============================================================
#  replace-token-email.sh v4.7
#  Bulk Update Cloudflare API Token
#  LiteSpeed Cache › CDN › Cloudflare
# ============================================================
#  Updated: 2026-04-27 06:39 (UTC+7)
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
# v4.7 (2026-04-27)
#   - Parked domain: detect จาก /etc/userdatadomains (แสดง main domain + cpanel user)
#   - Not on server: detect domain ที่ไม่อยู่บน server → log error
#   - Telegram: แจ้ง parked count + not-on-server list
# v4.6 (2026-04-27)
#   - เพิ่ม Parked/Alias domain support: detect จาก domains.csv + purge CF cache
# v4.5 (2026-04-27)
#   - Purge CF cache: แสดง purge สำเร็จ/ไม่สำเร็จ + log ชื่อเว็บที่ fail
# v4.7 (2026-04-27)
#   - Parked domain: detect จาก /etc/userdatadomains (แสดง main domain + cpanel user)
#   - Not on server: detect domain ที่ไม่อยู่บน server → log error
#   - Telegram: แจ้ง parked count + not-on-server list
# v4.6 (2026-04-27)
#   - เพิ่ม Parked/Alias domain support: detect จาก domains.csv + purge CF cache
# v4.5 (2026-04-27)
#   - Purge CF: แจ้ง pass/fail count + ชื่อเว็บที่ purge fail ใน Telegram
# v4.4 (2026-04-27)
#   - เพิ่ม Purge Cloudflare cache หลังใส่ Token + Zone ID
# v4.3 (2026-04-27)
#   - Fix: spinner ไม่เว้นบรรทัดก่อนแสดงผล (clear line ก่อน log)
# v4.2 (2026-04-27)
#   - ปรับ output สั้นลง: cpanel_user | domain | zone 5 ตัว
# v4.1 (2026-04-27)
#   - Fix: Zone ID ใช้ wp option update (bypass LiteSpeed hooks ที่ reset zone)
#   - Fix: curl ใช้ pipe ตรง (ไม่แยก http_code — เหมือน website-daily-create.sh)
#   - Fix: Telegram HTML mode + แสดง error จริง
#   - Fix: litespeed-option set redirect stdout (ไม่รกจอ)
# v4 (2026-04-27)
#   - Rewrite: ใช้ litespeed-option set แทน wp eval (เหมือน website-daily-create.sh)
#   - Fix: bash variable quoting bug 6 จุด (ตัวแปรไม่ expand ใน PHP eval)
#   - Fix: Telegram แสดง token ในจอ
#   - เพิ่ม domains.csv: ระบุ domain + Cloudflare email เฉพาะเจาะจง
#   - Multi-token: แต่ละ CF account มี token ของตัวเอง (CF_TOKENS map)
#   - Backward compatible: CF_TOKEN เดียวยังใช้ได้ (Format A)
#   - per-domain email + token: ดึง Zone ID ด้วย token ที่ถูก account
#   - domains.csv ว่าง/ไม่มี = แก้ทุกเว็บ + ใช้ _default token
#   - Repo ย้ายไป AnonymousVS/Litespeed-Cloudflare-Api-Update
# v3 (2026-04-20)
#   - แยก config: server-config.conf (public) + CF Token (private)
#   - WordPress API Token (cfut_) เท่านั้น — ห้ามใช้ Global Key
#   - เพิ่ม CPANEL_USERS + Telegram notification + Spinner
# v1 (เดิม)
#   - Single config file, auto-detect จาก CF_EMAIL
# =============================================================

VERSION="v4.7"
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
echo "║   Telegram     :  $( [[ -n "$TELEGRAM_BOT_TOKEN" ]] && echo "ON" || echo "OFF" )"
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
log " Telegram     : $( [[ -n "$TELEGRAM_BOT_TOKEN" ]] && echo "ON" || echo "OFF" )"
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
declare -A MATCHED_DOMAINS
declare -A PARKED_INFO
PARKED_DOMAINS=()
NOT_ON_SERVER=()

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
            MATCHED_DOMAINS["$_folder"]=1
        fi
    done

    # domain ที่ไม่เจอ WP folder → เช็ค /etc/userdatadomains
    for _dom in "${!TARGET_DOMAINS[@]}"; do
        if [[ -z "${MATCHED_DOMAINS[$_dom]+_}" ]]; then
            _udd_line=$(grep "^${_dom}:" /etc/userdatadomains 2>/dev/null)
            if [[ -n "$_udd_line" ]]; then
                _udd_type=$(echo "$_udd_line" | awk -F'==' '{print $3}')
                _udd_main=$(echo "$_udd_line" | awk -F'==' '{print $4}')
                _udd_user=$(echo "$_udd_line" | cut -d: -f2 | awk -F'==' '{print $1}' | tr -d ' ')
                if [[ "$_udd_type" == "parked" ]]; then
                    PARKED_DOMAINS+=("$_dom")
                    PARKED_INFO["$_dom"]="${_udd_main}|${_udd_user}"
                else
                    # addon/sub แต่ไม่มี WP → ยังอยู่บน server
                    PARKED_DOMAINS+=("$_dom")
                    PARKED_INFO["$_dom"]="${_udd_main}|${_udd_user}|${_udd_type}"
                fi
            else
                NOT_ON_SERVER+=("$_dom")
            fi
        fi
    done

    log "🎯 Filter domains.csv: ${#DIRS[@]} → ${#FILTERED_DIRS[@]} เว็บ"
    [[ ${#PARKED_DOMAINS[@]} -gt 0 ]] && log "🔗 Parked/Alias (purge only): ${#PARKED_DOMAINS[@]} เว็บ"
    [[ ${#NOT_ON_SERVER[@]} -gt 0 ]] && log "⚠️  ไม่อยู่บน server: ${#NOT_ON_SERVER[@]} เว็บ"
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
    local SITE UNIQ CPUSER_NAME DOMAIN_NAME
    CPUSER_NAME=$(echo "$dir" | sed 's|/home[0-9]*/||;s|/.*||')
    DOMAIN_NAME=$(basename "${dir%/}")
    [[ "$DOMAIN_NAME" == "public_html" ]] && DOMAIN_NAME=$(basename "$(dirname "${dir%/}")")
    SITE="$CPUSER_NAME/$DOMAIN_NAME"
    UNIQ="${BASHPID}_$(date +%s%N)"
    local LABEL="[$COUNT/$TOTAL] $CPUSER_NAME | $DOMAIN_NAME"

    if [[ "$dir" =~ /public_html/$ ]]; then
        return
    fi

    _log() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        printf "\r\033[K"
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

    # ── 1. Plugin active? ─────────────────────────────────────
    if ! wp --path="$dir" plugin is-active litespeed-cache --allow-root 2>/dev/null; then
        _log  "⏭  $LABEL | LiteSpeed ไม่ active"
        _log_r skip "$SITE | plugin ไม่ active"
        touch "${RESULT_DIR}/skip_${UNIQ}"
        return
    fi

    # ── 2. อ่าน options ปัจจุบัน ──────────────────────────────
    local cur_enabled cur_key cur_email cur_zone cur_name
    cur_enabled=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare --allow-root 2>/dev/null || echo "0")
    cur_key=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_key --allow-root 2>/dev/null || echo "")
    cur_email=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_email --allow-root 2>/dev/null || echo "")
    cur_zone=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_zone --allow-root 2>/dev/null || echo "")
    cur_name=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_name --allow-root 2>/dev/null || echo "")

    # ── 3. CF_ONLY_ACTIVE: ข้ามถ้า CF ปิดอยู่ ────────────────
    if [[ "$CF_ONLY_ACTIVE" == "yes" && ( -z "$cur_enabled" || "$cur_enabled" == "0" ) ]]; then
        _log  "🔴 $LABEL | CF ปิดอยู่ — ข้าม"
        _log_r skip "$SITE | Cloudflare=OFF ใน plugin — ข้ามตาม CF_ONLY_ACTIVE=yes"
        touch "${RESULT_DIR}/skip_${UNIQ}"
        return
    fi

    # ── 4. CF_OVERWRITE_KEY: ข้ามถ้ามี key อยู่แล้ว ──────────
    if [[ "$CF_OVERWRITE_KEY" != "yes" && -n "$cur_key" ]]; then
        _log  "⏩ $LABEL | มี key อยู่แล้ว — ข้าม"
        _log_r nochange "$SITE | existing_key=${cur_key:0:8}..."
        touch "${RESULT_DIR}/nochange_${UNIQ}"
        return
    fi

    # ── 5. Auto-fix domain จาก folder name ────────────────────
    local folder_name DOMAIN was_fixed="0"
    folder_name=$(basename "${dir%/}")
    [[ "$folder_name" == "public_html" ]] && folder_name=$(basename "$(dirname "${dir%/}")")

    DOMAIN="$cur_name"
    if [[ -n "$folder_name" && -n "$cur_name" && "$folder_name" != "$cur_name" ]]; then
        DOMAIN="$folder_name"
        was_fixed="1"
    fi
    [[ -z "$DOMAIN" ]] && DOMAIN="$folder_name"

    # ── 6. เขียน Credentials (litespeed-option set) ──────────
    wp --path="$dir" litespeed-option set cdn-cloudflare 1 --allow-root >/dev/null 2>&1
    wp --path="$dir" litespeed-option set cdn-cloudflare_key "$SITE_CF_TOKEN" --allow-root >/dev/null 2>&1
    wp --path="$dir" litespeed-option set cdn-cloudflare_email "" --allow-root >/dev/null 2>&1
    wp --path="$dir" litespeed-option set cdn-cloudflare_name "$DOMAIN" --allow-root >/dev/null 2>&1
    wp --path="$dir" litespeed-option set cdn-cloudflare_clear 1 --allow-root >/dev/null 2>&1
    wp --path="$dir" litespeed-option set cdn 1 --allow-root >/dev/null 2>&1

    # ── 7. ดึง Zone ID จาก Cloudflare API (bash curl) ────────
    # ใช้ pipe ตรงเหมือน website-daily-create.sh (ง่าย ไม่มี bug)
    local zone_id="" zone_name="" cf_error="" attempt=0
    while [[ $attempt -lt $MAX_RETRY ]]; do
        attempt=$((attempt+1))

        local cf_response
        cf_response=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
            -H "Authorization: Bearer $SITE_CF_TOKEN" \
            -H "Content-Type: application/json" 2>/dev/null)

        zone_id=$(echo "$cf_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [[ -n "$zone_id" ]]; then
            zone_name=$(echo "$cf_response" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            [[ -z "$zone_name" ]] && zone_name="$DOMAIN"
            break
        fi

        cf_error="zone_empty"
        [[ $attempt -lt $MAX_RETRY ]] && sleep "$RETRY_DELAY"
    done

    # ── 8. บันทึก Zone ID (wp option update — bypass plugin hooks) ─
    # หมายเหตุ: litespeed-option set จะ trigger plugin save handler
    #           ซึ่ง reset zone เป็นว่าง → ต้องใช้ wp option update แทน
    local purge_ok=""
    if [[ -n "$zone_id" ]]; then
        wp --path="$dir" option update litespeed.conf.cdn-cloudflare_zone "$zone_id" --allow-root >/dev/null 2>&1
        wp --path="$dir" option update litespeed.conf.cdn-cloudflare_name "$zone_name" --allow-root >/dev/null 2>&1

        # ── 8.5 Purge Cloudflare cache ────────────────────────
        local purge_result
        purge_result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/purge_cache" \
            -H "Authorization: Bearer $SITE_CF_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"purge_everything":true}' 2>/dev/null)

        if echo "$purge_result" | grep -q '"success":true'; then
            purge_ok="1"
            touch "${RESULT_DIR}/purge_pass_${UNIQ}"
        else
            purge_ok="0"
            echo "$DOMAIN_NAME" > "${RESULT_DIR}/purge_fail_${UNIQ}"
        fi
    fi

    # ── 9. Verify ─────────────────────────────────────────────
    local v_key v_zone v_email key_ok="0"
    v_key=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_key --allow-root 2>/dev/null || echo "")
    v_zone=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_zone --allow-root 2>/dev/null || echo "")
    v_email=$(wp --path="$dir" option get litespeed.conf.cdn-cloudflare_email --allow-root 2>/dev/null || echo "")
    [[ "$v_key" == "$SITE_CF_TOKEN" ]] && key_ok="1"

    # ── 10. Log ผลลัพธ์ ───────────────────────────────────────
    local FIX_TAG=""
    [[ "$was_fixed" == "1" ]] && FIX_TAG=" | ⚙️ domain ถูกแก้อัตโนมัติ"

    local OLD_ZONE_DISPLAY="${cur_zone:0:5}"
    [[ -z "$OLD_ZONE_DISPLAY" ]] && OLD_ZONE_DISPLAY="(empty)"
    [[ -n "$cur_zone" ]] && OLD_ZONE_DISPLAY="${OLD_ZONE_DISPLAY}..."
    local NEW_ZONE_DISPLAY="${v_zone:0:5}"
    [[ -z "$NEW_ZONE_DISPLAY" ]] && NEW_ZONE_DISPLAY="(no zone)"
    [[ -n "$v_zone" ]] && NEW_ZONE_DISPLAY="${NEW_ZONE_DISPLAY}..."

    if [[ "$key_ok" == "1" && -n "$v_zone" ]]; then
        local PURGE_TAG=""
        [[ "$purge_ok" == "1" ]] && PURGE_TAG=" | purge ✅"
        [[ "$purge_ok" == "0" ]] && PURGE_TAG=" | purge ❌"
        _log  "✅ $LABEL | zone: $OLD_ZONE_DISPLAY → $NEW_ZONE_DISPLAY${PURGE_TAG}${FIX_TAG}"
        _log_r pass "$SITE | zone: $cur_zone | key: ${v_key:0:12}... | email: $v_email | attempt=${attempt}/${MAX_RETRY}${FIX_TAG}"
        [[ "$was_fixed" == "1" ]] && _log_r mismatch "$SITE | domain ถูกแก้อัตโนมัติ → $DOMAIN"
        touch "${RESULT_DIR}/pass_${UNIQ}"
        [[ "$was_fixed" == "1" ]] && touch "${RESULT_DIR}/mismatch_${UNIQ}"
    elif [[ "$key_ok" == "1" && "$cf_error" == "zone_empty" ]]; then
        _log  "🌐 $LABEL | domain ไม่อยู่ใน CF account${FIX_TAG}"
        _log_r fail "$SITE | domain ไม่อยู่ใน CF | attempt=${attempt}/${MAX_RETRY}${FIX_TAG}"
        touch "${RESULT_DIR}/fail_${UNIQ}"
    elif [[ "$key_ok" == "1" ]]; then
        _log  "❌ $LABEL | CF API error=$cf_error | attempt=${attempt}/${MAX_RETRY}${FIX_TAG}"
        _log_r fail "$SITE | CF API error=$cf_error | attempt=${attempt}/${MAX_RETRY}${FIX_TAG}"
        touch "${RESULT_DIR}/fail_${UNIQ}"
    else
        _log  "❌ $LABEL | verify key ไม่ผ่าน${FIX_TAG}"
        _log_r fail "$SITE | verify failed — key ไม่ตรง${FIX_TAG}"
        touch "${RESULT_DIR}/fail_${UNIQ}"
    fi
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
echo ""
log "──────────────────────────────────────"
log "  ประมวลผลครบ $TOTAL เว็บ"

# ─── Parked/Alias domains: Purge CF cache only ──────────────
if [[ ${#PARKED_DOMAINS[@]} -gt 0 ]]; then
    echo ""
    log "======================================"
    log "  🔗 Parked/Alias Domains — Purge CF cache only"
    log "======================================"
    P_COUNT=0
    P_TOTAL=${#PARKED_DOMAINS[@]}

    for _pd in "${PARKED_DOMAINS[@]}"; do
        P_COUNT=$((P_COUNT+1))

        # ดึง main domain + cpanel user
        _pd_info="${PARKED_INFO[$_pd]:-}"
        _pd_main=$(echo "$_pd_info" | cut -d'|' -f1)
        _pd_user=$(echo "$_pd_info" | cut -d'|' -f2)

        # หา email + token
        _pd_email="${DOMAIN_CF_EMAIL[$_pd]:-}"
        _pd_token=""
        if [[ -n "$_pd_email" && -n "${CF_TOKENS[$_pd_email]+_}" ]]; then
            _pd_token="${CF_TOKENS[$_pd_email]}"
        elif [[ -n "${CF_TOKENS[_default]+_}" ]]; then
            _pd_token="${CF_TOKENS[_default]}"
        fi

        if [[ -z "$_pd_token" ]]; then
            log "  ⚠️ [$P_COUNT/$P_TOTAL] $_pd → ไม่มี token — ข้าม"
            continue
        fi

        # ดึง Zone ID
        _pd_zone=""
        _pd_zone=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=$_pd" \
            -H "Authorization: Bearer $_pd_token" \
            -H "Content-Type: application/json" 2>/dev/null \
            | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [[ -z "$_pd_zone" ]]; then
            log "  ❌ [$P_COUNT/$P_TOTAL] $_pd → parked ของ $_pd_main ($_pd_user) | Zone ID ไม่เจอ"
            echo "$_pd" > "${RESULT_DIR}/purge_fail_parked_${P_COUNT}"
            continue
        fi

        # Purge CF cache
        _pd_purge=""
        _pd_purge=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${_pd_zone}/purge_cache" \
            -H "Authorization: Bearer $_pd_token" \
            -H "Content-Type: application/json" \
            -d '{"purge_everything":true}' 2>/dev/null)

        if echo "$_pd_purge" | grep -q '"success":true'; then
            log "  ✅ [$P_COUNT/$P_TOTAL] $_pd → $_pd_main ($_pd_user) | zone: ${_pd_zone:0:5}... | purged"
            touch "${RESULT_DIR}/purge_pass_parked_${P_COUNT}"
        else
            log "  ❌ [$P_COUNT/$P_TOTAL] $_pd → $_pd_main ($_pd_user) | purge failed"
            echo "$_pd" > "${RESULT_DIR}/purge_fail_parked_${P_COUNT}"
        fi
    done

    log "──────────────────────────────────────"
    log "  Parked purge เสร็จ $P_TOTAL เว็บ"
fi

# ─── Domain ไม่อยู่บน server ────────────────────────────────
if [[ ${#NOT_ON_SERVER[@]} -gt 0 ]]; then
    echo ""
    log "======================================"
    log "  ⚠️  Domain ไม่อยู่บน server นี้ ($(hostname))"
    log "======================================"
    for _ns in "${NOT_ON_SERVER[@]}"; do
        log "  ❌ $_ns — ไม่พบใน cPanel บน server นี้"
        ( flock 202; echo "[$(date '+%Y-%m-%d %H:%M:%S')] NOT_ON_SERVER: $_ns" >> "$LOG_FAIL" ) 202>"${LOG_FILE}.fail.lock"
    done
fi

# ─── สรุป ────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

SUCCESS=$(  find "$RESULT_DIR" -name "pass_*"       2>/dev/null | wc -l)
FAILED=$(   find "$RESULT_DIR" -name "fail_*"       2>/dev/null | wc -l)
SKIPPED=$(  find "$RESULT_DIR" -name "skip_*"       2>/dev/null | wc -l)
NOCHANGE=$( find "$RESULT_DIR" -name "nochange_*"   2>/dev/null | wc -l)
MISMATCH=$( find "$RESULT_DIR" -name "mismatch_*"   2>/dev/null | wc -l)
PURGE_PASS=$(find "$RESULT_DIR" -name "purge_pass_*" 2>/dev/null | wc -l)
PURGE_FAIL=$(find "$RESULT_DIR" -name "purge_fail_*" 2>/dev/null | wc -l)
PURGE_FAIL_LIST=""
if [[ $PURGE_FAIL -gt 0 ]]; then
    PURGE_FAIL_LIST=$(cat "$RESULT_DIR"/purge_fail_* 2>/dev/null | sort)
fi

log "======================================"
log " สรุปผลรวม  $VERSION"
log " รวมทั้งหมด      : $TOTAL เว็บ"
log " ✅ Pass (อัปเดต) : $SUCCESS เว็บ"
log " 🗑 Purge CF cache : $PURGE_PASS สำเร็จ / $PURGE_FAIL ไม่สำเร็จ"
log " 🔗 Parked purge  : ${#PARKED_DOMAINS[@]} เว็บ"
log " ⏩ Nochange       : $NOCHANGE เว็บ  (มี key อยู่แล้ว ข้ามตาม CF_OVERWRITE_KEY=no)"
log " ❌ Fail          : $FAILED เว็บ"
log " ⏭  Skip          : $SKIPPED เว็บ  (plugin ไม่ active / CF ปิด)"
log " ⚙️  Auto-fixed    : $MISMATCH เว็บ  (domain ถูกแก้อัตโนมัติจาก folder name)"
if [[ ${#NOT_ON_SERVER[@]} -gt 0 ]]; then
log " ⚠️  ไม่อยู่บน server: ${#NOT_ON_SERVER[@]} เว็บ"
fi
log " เวลาที่ใช้       : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
if [[ -n "$PURGE_FAIL_LIST" ]]; then
    log " 🗑❌ Purge fail   :"
    echo "$PURGE_FAIL_LIST" | while read -r _pf; do log "    - $_pf"; done
fi
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
    TG_MSG="🔄 <b>CF Token Update — $HOSTNAME</b>

✅ Pass: $SUCCESS
🗑 Purge: ${PURGE_PASS}✅ / ${PURGE_FAIL}❌
🔗 Parked purge: ${#PARKED_DOMAINS[@]}
⏩ Nochange: $NOCHANGE
❌ Fail: $FAILED
⏭ Skip: $SKIPPED

⏱ $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"

    if [[ -n "$PURGE_FAIL_LIST" ]]; then
        TG_MSG="$TG_MSG

🗑❌ <b>Purge fail:</b>
$(echo "$PURGE_FAIL_LIST" | sed 's/^/  - /')"
    fi

    if [[ ${#NOT_ON_SERVER[@]} -gt 0 ]]; then
        TG_MSG="$TG_MSG

⚠️ <b>ไม่อยู่บน server:</b>
$(printf '  - %s\n' "${NOT_ON_SERVER[@]}")"
    fi

    TG_RESULT=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$TG_MSG" \
        -d parse_mode="HTML" 2>&1)

    if echo "$TG_RESULT" | grep -q '"ok":true'; then
        log "📨 Telegram notification sent"
    else
        log "⚠️  Telegram notification failed: $(echo "$TG_RESULT" | grep -o '"description":"[^"]*"' | head -1)"
    fi
fi

exit 0
