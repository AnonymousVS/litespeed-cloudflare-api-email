#!/bin/bash
# =============================================================
#  replace-token-email.sh
#  Bulk Update Cloudflare API Key / Token / Email
#  LiteSpeed Cache › CDN › Cloudflare — ทุกเว็บบนเซิร์ฟเวอร์
#
#  Repo   : https://github.com/AnonymousVS/litespeed-cloudflare-api-email
#  วิธีใช้:
#    bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/replace-token-email.sh)
#    หรือรันแบบมี config:
#    bash replace-token-email.sh /path/to/config-apitoken-email.conf
# =============================================================

VERSION="v1"

# ─── โหลด Config หรือถามแบบ Interactive ─────────────────────
CONFIG_FILE="${1:-/root/config-apitoken-email.conf}"

CONF_URL="https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/refs/heads/main/config-apitoken-email.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    # ── ไม่มีไฟล์ config → ดาวน์โหลดจาก GitHub แล้วเปิดแก้ ──
    echo ""
    echo "📥 ดาวน์โหลด config จาก GitHub..."
    if ! curl -fsSL "$CONF_URL" -o "$CONFIG_FILE"; then
        echo "❌ ERROR: ดาวน์โหลด config ไม่สำเร็จ — ตรวจสอบการเชื่อมต่อ"
        exit 1
    fi
    echo "✅ ดาวน์โหลดสำเร็จ → $CONFIG_FILE"
    echo ""
    echo "📝 เปิด config เพื่อแก้ไข — กรอก CF_KEY และ CF_EMAIL แล้วบันทึก"
    echo "   (nano: Ctrl+O บันทึก, Ctrl+X ออก)"
    echo ""
    sleep 1
    nano "$CONFIG_FILE"
    echo ""
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ─── Validate ─────────────────────────────────────────────────
if [[ -z "$CF_KEY" || "$CF_KEY" == "YOUR_API_TOKEN_OR_GLOBAL_KEY_HERE" ]]; then
    echo "❌ ERROR: CF_KEY ว่างเปล่า — กรุณาใส่ API Token หรือ Global API Key"
    exit 1
fi

# ─── Auto-detect Auth Mode จาก CF_EMAIL ─────────────────────
# CF_EMAIL มีค่า → Global API Key mode / ว่างเปล่า → Token mode
if [[ -n "$CF_EMAIL" ]]; then
    CF_AUTH_MODE="apikey"
else
    CF_AUTH_MODE="token"
fi

# ─── แสดงค่าที่จะใช้ + ขอ Confirm ──────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════"
echo "║   🔄  คุณต้องการเปลี่ยน Cloudflare CDN ค่าใหม่ ดังนี้"
echo "╠══════════════════════════════════════════════════════════════"
echo "║   Version    :  $VERSION"
echo "║"
if [[ "$CF_AUTH_MODE" == "token" ]]; then
echo "║   Auth Mode  :  API Token"
echo "║   API Token  :  ${CF_KEY:0:8}...${CF_KEY: -4}"
echo "║   Email      :  (ไม่ใช้ — Token mode)"
else
echo "║   Auth Mode  :  Global API Key"
echo "║   API Key    :  ${CF_KEY:0:8}...${CF_KEY: -4}"
echo "║   Email      :  $CF_EMAIL"
fi
echo "║"
echo "║   Only Active CF :  $CF_ONLY_ACTIVE"
echo "║   Overwrite Key  :  $CF_OVERWRITE_KEY"
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
LOG_OVERWRITE="/var/log/lscwp-cf-update-overwrite.log"
LOCK_FILE="${LOG_FILE}.lock"
RESULT_DIR="/tmp/lscwp-cf-update-$$"
mkdir -p "$RESULT_DIR"

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$1"
    ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
}

cleanup() {
    wait
    rm -rf "$RESULT_DIR"
    rm -f "$LOCK_FILE" \
          "${LOG_FILE}.pass.lock" "${LOG_FILE}.fail.lock" \
          "${LOG_FILE}.skip.lock" "${LOG_FILE}.nochange.lock" \
          "${LOG_FILE}.mismatch.lock" "${LOG_FILE}.overwrite.lock"
}
trap cleanup EXIT

# ─── ตรวจ WP-CLI ─────────────────────────────────────────────
if ! command -v wp &>/dev/null; then
    log "❌ ERROR: ไม่พบ WP-CLI — https://wp-cli.org"
    exit 1
fi

# ─── ล้าง log ก่อนรัน (เก็บเฉพาะ run ล่าสุด) ────────────────
> "$LOG_FILE"
> "$LOG_PASS"
> "$LOG_FAIL"
> "$LOG_SKIP"
> "$LOG_NOCHANGE"
> "$LOG_MISMATCH"
> "$LOG_OVERWRITE"

START_TIME=$(date +%s)
log "======================================"
log " BULK UPDATE CF CREDENTIALS (LiteSpeed)  $VERSION"
log " เริ่มเวลา    : $(date '+%Y-%m-%d %H:%M:%S')"
log " Config       : $CONFIG_FILE"
log " Auth Mode    : $CF_AUTH_MODE (auto-detect)"
log " Email        : ${CF_EMAIL:-"(ไม่ใช้ — Token mode)"}"
log " Key (prefix) : ${CF_KEY:0:8}..."
log " Only Active  : $CF_ONLY_ACTIVE"
log " Overwrite Key: $CF_OVERWRITE_KEY"
log " Jobs         : $MAX_JOBS"
log "======================================"

# ─── ค้นหา WordPress ทุกเว็บ ─────────────────────────────────
declare -A _SEEN
DIRS=()

# แหล่งที่ 1: WHM — /etc/trueuserdomains
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

# แหล่งที่ 2: Scan /home /home2 /home3 /home4 /home5 /usr/home
for _base in /home /home2 /home3 /home4 /home5 /usr/home; do
    [[ -d "$_base" ]] || continue
    while IFS= read -r -d '' _wpc; do
        _d="$(dirname "$_wpc")/"
        [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; DIRS+=("$_d"); }
    done < <(find "$_base" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
done

TOTAL=${#DIRS[@]}
log "พบ WordPress  : $TOTAL เว็บ"
log "======================================"

# ─── ฟังก์ชัน process แต่ละเว็บ ──────────────────────────────
process_site() {
    local dir="$1"
    local COUNT="$2"
    local TOTAL="$3"
    local SITE UNIQ
    SITE=$(echo "$dir" | sed 's|/home[0-9]*/||;s|/$||')
    UNIQ="${BASHPID}_$(date +%s%N)"
    local LABEL="[$COUNT/$TOTAL] $SITE"

    # ── Skip /public_html/ root ───────────────────────────────
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
            pass)      ( flock 201; echo "[$ts] $2" >> "$LOG_PASS"      ) 201>"${LOG_FILE}.pass.lock" ;;
            fail)      ( flock 202; echo "[$ts] $2" >> "$LOG_FAIL"      ) 202>"${LOG_FILE}.fail.lock" ;;
            skip)      ( flock 203; echo "[$ts] $2" >> "$LOG_SKIP"      ) 203>"${LOG_FILE}.skip.lock" ;;
            nochange)  ( flock 204; echo "[$ts] $2" >> "$LOG_NOCHANGE"  ) 204>"${LOG_FILE}.nochange.lock" ;;
            mismatch)  ( flock 205; echo "[$ts] $2" >> "$LOG_MISMATCH"  ) 205>"${LOG_FILE}.mismatch.lock" ;;
            overwrite) ( flock 206; echo "[$ts] $2" >> "$LOG_OVERWRITE" ) 206>"${LOG_FILE}.overwrite.lock" ;;
        esac
    }

    # ── เขียน PHP ลง temp file ผ่าน heredoc ─────────────────────
    # bash expand ${CF_KEY} ตอนเขียนไฟล์ → PHP รับค่าตรงๆ ไม่ผ่าน env
    # หลีกเลี่ยง wp eval '...' ที่ PHP subprocess อาจไม่ inherit env vars
    local _PHP_FILE
    _PHP_FILE=$(mktemp /tmp/wp-cf-eval-XXXXXX.php)
    # shellcheck disable=SC2154
    cat > "$_PHP_FILE" << PHPEOF
<?php
// ── ค่าจาก bash — inject ตอนเขียน temp file (ไม่ใช่ getenv) ──────
\$_new_key       = '${CF_KEY}';
\$_new_email     = '${CF_EMAIL}';
\$_overwrite     = ('${CF_OVERWRITE_KEY}' === 'yes');
\$_only_active   = ('${CF_ONLY_ACTIVE}'   === 'yes');
\$_max_retry     = max(1, (int) '${MAX_RETRY}');
\$_retry_delay   = max(1, (int) '${RETRY_DELAY}');

// ── 1. Plugin active? ──────────────────────────────────────────────
if (!is_plugin_active('litespeed-cache/litespeed-cache.php')) {
    echo 'STATUS:NOPLUGIN'; return;
}

// ── 2. อ่าน options ปัจจุบัน ─────────────────────────────────────
\$cur_enabled = get_option('litespeed.conf.cdn-cloudflare',       '0');
\$cur_key     = trim((string) get_option('litespeed.conf.cdn-cloudflare_key',   ''));
\$cur_email   = trim((string) get_option('litespeed.conf.cdn-cloudflare_email', ''));
\$cur_zone    = trim((string) get_option('litespeed.conf.cdn-cloudflare_zone',  ''));
\$cur_name    = trim((string) get_option('litespeed.conf.cdn-cloudflare_name',  ''));

// ── 3. CF_ONLY_ACTIVE ────────────────────────────────────────────
if (\$_only_active && (!\$cur_enabled || \$cur_enabled === '0')) {
    echo 'STATUS:SKIP_CFOFF'; return;
}

// ── 4. ตรวจ key/email — NOCHANGE ถ้าตรงครบทั้งคู่ ──────────────
\$key_match   = (\$cur_key !== '' && \$cur_key === \$_new_key);
\$email_match = (\$cur_email === \$_new_email);

if (!\$_overwrite && \$cur_key !== '' && \$key_match && \$email_match) {
    printf("STATUS:NOCHANGE\tOLD_KEY:%s\tOLD_EMAIL:%s\tDOMAIN:%s",
        substr(\$cur_key, 0, 8), \$cur_email, \$cur_name);
    return;
}

// force_ow = มี key เดิม แต่ key หรือ email ไม่ตรงกับ config
\$force_ow = (\$cur_key !== '' && (!\$key_match || !\$email_match)) ? 1 : 0;

// ── 5. Auto-fix domain จาก folder name ──────────────────────────
\$folder = basename(rtrim(ABSPATH, '/'));
if (\$folder === 'public_html') {
    \$folder = basename(dirname(rtrim(ABSPATH, '/')));
}
\$name_clean = preg_replace('#^https?://#', '', rtrim(\$cur_name, '/'));
\$was_fixed  = false;
if (\$folder && \$name_clean && \$folder !== \$name_clean) {
    \$cur_name  = \$folder;
    \$was_fixed = true;
}

// ── 6. เขียน Credentials ลง DB ──────────────────────────────────
\$is_apikey = (\$_new_email !== '');

update_option('litespeed.conf.cdn-cloudflare_key',   \$_new_key);
update_option('litespeed.conf.cdn-cloudflare_name',  \$cur_name);
update_option('litespeed.conf.cdn-cloudflare_zone',  '');
update_option('litespeed.conf.cdn-cloudflare_email', \$is_apikey ? \$_new_email : '');

// ── 7. ดึง Zone ID จาก Cloudflare API ───────────────────────────
\$zone_id   = '';
\$zone_name = '';
\$cf_error  = '';
\$attempt   = 0;

\$headers = \$is_apikey
    ? ['X-Auth-Email: ' . \$_new_email, 'X-Auth-Key: ' . \$_new_key, 'Content-Type: application/json']
    : ['Authorization: Bearer ' . \$_new_key,                         'Content-Type: application/json'];

while (\$attempt < \$_max_retry) {
    \$attempt++;
    \$url = 'https://api.cloudflare.com/client/v4/zones?status=active&match=all&name=' . urlencode(\$cur_name);
    \$ch  = curl_init();
    curl_setopt(\$ch, CURLOPT_URL,            \$url);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER,     \$headers);
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_TIMEOUT,        10);
    curl_setopt(\$ch, CURLOPT_SSL_VERIFYPEER, true);
    \$raw      = curl_exec(\$ch);
    \$http     = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    \$curl_err = curl_error(\$ch);
    curl_close(\$ch);

    if (\$curl_err) {
        \$cf_error = 'curl:' . \$curl_err;
        if (\$attempt < \$_max_retry) { sleep(\$_retry_delay); continue; }
        break;
    }
    \$res = json_decode(\$raw, true);
    if (\$http !== 200 || empty(\$res['success'])) {
        \$cf_error = 'http:' . \$http . ' err:' . json_encode(\$res['errors'] ?? []);
        if (\$attempt < \$_max_retry) { sleep(\$_retry_delay); continue; }
        break;
    }
    \$zone_id   = \$res['result'][0]['id']   ?? '';
    \$zone_name = \$res['result'][0]['name'] ?? \$cur_name;
    if (\$zone_id) break;
    \$cf_error = 'zone_empty';
    if (\$attempt < \$_max_retry) sleep(\$_retry_delay);
}

// ── 8. บันทึก Zone ID ──────────────────────────────────────────
if (\$zone_id) {
    update_option('litespeed.conf.cdn-cloudflare_zone', \$zone_id);
    update_option('litespeed.conf.cdn-cloudflare_name', \$zone_name);
}

// ── 9. Verify ───────────────────────────────────────────────────
\$v_key   = trim((string) get_option('litespeed.conf.cdn-cloudflare_key',   ''));
\$v_zone  = trim((string) get_option('litespeed.conf.cdn-cloudflare_zone',  ''));
\$v_email = trim((string) get_option('litespeed.conf.cdn-cloudflare_email', ''));
\$key_ok  = (\$v_key === \$_new_key) ? 1 : 0;

printf(
    "STATUS:DONE\tKEY_OK:%d\tDOMAIN:%s\tOLD_KEY:%s\tNEW_KEY:%s\tOLD_EMAIL:%s\tNEW_EMAIL:%s\tOLD_ZONE:%s\tNEW_ZONE:%s\tFIXED:%d\tATTEMPT:%d\tCF_ERROR:%s\tFORCE_OW:%d",
    \$key_ok,
    \$zone_name ?: \$cur_name,
    substr(\$cur_key, 0, 8),
    substr(\$v_key,   0, 8),
    \$cur_email,
    \$v_email,
    \$cur_zone ? substr(\$cur_zone, 0, 12) . '...' : '(empty)',
    \$v_zone   ?: '(no zone)',
    \$was_fixed ? 1 : 0,
    \$attempt,
    \$cf_error,
    \$force_ow
);
PHPEOF

    EVAL_OUT=$(timeout "$WP_TIMEOUT" wp --path="$dir" eval-file "$_PHP_FILE" --allow-root 2>/dev/null)
    rm -f "$_PHP_FILE" 

    local STATUS
    STATUS=$(echo "$EVAL_OUT" | grep -oP '(?<=STATUS:)\w+')

    case "$STATUS" in
        DONE)
            local KEY_OK DOMAIN OLD_KEY NEW_KEY OLD_EMAIL NEW_EMAIL OLD_ZONE NEW_ZONE FIXED ATTEMPT CF_ERROR FORCE_OW
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
            FORCE_OW=$(  echo "$EVAL_OUT" | grep -oP '(?<=FORCE_OW:)\d+')
            local FIX_TAG="" OW_TAG=""
            [[ "$FIXED"    == "1" ]] && FIX_TAG=" | ⚙️ domain ถูกแก้อัตโนมัติ"
            [[ "$FORCE_OW" == "1" ]] && OW_TAG=" | ✏️ เขียนทับ (key/email เดิมไม่ตรง)"

            if [[ "$KEY_OK" == "1" && "$NEW_ZONE" != "(no zone)" ]]; then
                _log  "✅ PASS: $LABEL | domain=$DOMAIN | key: ${OLD_KEY:-"(none)"}... → ${NEW_KEY}... | email: ${OLD_EMAIL:-"(none)"} → ${NEW_EMAIL:-"(none)"} | zone: $OLD_ZONE → $NEW_ZONE | attempt=${ATTEMPT}/${MAX_RETRY}${OW_TAG}${FIX_TAG}"
                _log_r pass "$SITE | domain=$DOMAIN | old_key=${OLD_KEY:-"(none)"}... | new_key=${NEW_KEY}... | old_email=${OLD_EMAIL:-"(none)"} | new_email=${NEW_EMAIL:-"(none)"} | zone: $OLD_ZONE → $NEW_ZONE | attempt=${ATTEMPT}/${MAX_RETRY}${OW_TAG}${FIX_TAG}"
                [[ "$FORCE_OW" == "1" ]] && _log_r overwrite "$SITE | domain=$DOMAIN | เขียนทับ old_key=${OLD_KEY:-"(none)"}... → new_key=${NEW_KEY}... | old_email=${OLD_EMAIL:-"(none)"} → new_email=${NEW_EMAIL:-"(none)"}"
                [[ "$FIXED"    == "1" ]] && _log_r mismatch  "$SITE | domain ถูกแก้อัตโนมัติ → $DOMAIN"
                touch "${RESULT_DIR}/pass_${UNIQ}"
                [[ "$FORCE_OW" == "1" ]] && touch "${RESULT_DIR}/overwrite_${UNIQ}"
                [[ "$FIXED"    == "1" ]] && touch "${RESULT_DIR}/mismatch_${UNIQ}"
            elif [[ "$KEY_OK" == "1" && "$CF_ERROR" == "zone_empty" ]]; then
                _log  "🌐 NOTCF: $LABEL | domain=$DOMAIN | key/email เขียนแล้ว แต่ domain ไม่อยู่ใน CF account (attempt=${ATTEMPT}/${MAX_RETRY})${OW_TAG}${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | key อัปเดตแล้ว แต่ domain ไม่อยู่ใน CF | attempt=${ATTEMPT}/${MAX_RETRY}${OW_TAG}${FIX_TAG}"
                [[ "$FORCE_OW" == "1" ]] && _log_r overwrite "$SITE | domain=$DOMAIN | เขียนทับ old_key=${OLD_KEY:-"(none)"}... | old_email=${OLD_EMAIL:-"(none)"}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
                [[ "$FORCE_OW" == "1" ]] && touch "${RESULT_DIR}/overwrite_${UNIQ}"
            elif [[ "$KEY_OK" == "1" && -n "$CF_ERROR" ]]; then
                _log  "❌ FAIL (CF API error): $LABEL | domain=$DOMAIN | error=$CF_ERROR | attempt=${ATTEMPT}/${MAX_RETRY}${OW_TAG}${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | key อัปเดตแล้ว แต่ดึง zone ไม่ได้ | error=$CF_ERROR | attempt=${ATTEMPT}/${MAX_RETRY}${OW_TAG}${FIX_TAG}"
                [[ "$FORCE_OW" == "1" ]] && _log_r overwrite "$SITE | domain=$DOMAIN | เขียนทับ old_key=${OLD_KEY:-"(none)"}... | old_email=${OLD_EMAIL:-"(none)"}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
                [[ "$FORCE_OW" == "1" ]] && touch "${RESULT_DIR}/overwrite_${UNIQ}"
            elif [[ "$KEY_OK" == "1" ]]; then
                # KEY_OK=1 แต่ zone ว่าง และ CF_ERROR ว่าง = CF API ไม่ได้ถูกเรียก (attempt=0) หรือ network timeout
                _log  "⚠️  WARN (no zone, unknown): $LABEL | domain=$DOMAIN | key เขียนแล้ว แต่ไม่ได้ zone (attempt=${ATTEMPT}/${MAX_RETRY}, cf_error=empty)${OW_TAG}${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | key อัปเดตแล้ว zone ไม่ได้ — cf_error ว่าง | attempt=${ATTEMPT}/${MAX_RETRY}${OW_TAG}${FIX_TAG}"
                [[ "$FORCE_OW" == "1" ]] && _log_r overwrite "$SITE | domain=$DOMAIN | เขียนทับ old_key=${OLD_KEY:-"(none)"}... | old_email=${OLD_EMAIL:-"(none)"}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
                [[ "$FORCE_OW" == "1" ]] && touch "${RESULT_DIR}/overwrite_${UNIQ}"
            else
                _log  "❌ FAIL (verify key ไม่ผ่าน): $LABEL | domain=$DOMAIN${OW_TAG}${FIX_TAG}"
                _log_r fail "$SITE | domain=$DOMAIN | verify failed — key ไม่ตรง${OW_TAG}${FIX_TAG}"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            fi
            ;;
        NOCHANGE)
            local OLD_KEY OLD_EMAIL DOMAIN
            OLD_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=OLD_KEY:)[^\t]*')
            OLD_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=OLD_EMAIL:)[^\t]*')
            DOMAIN=$(    echo "$EVAL_OUT" | grep -oP '(?<=DOMAIN:)[^\t]*')
            _log  "⏩ NOCHANGE: $LABEL | domain=$DOMAIN | key=${OLD_KEY}... email=${OLD_EMAIL:-"(none)"} ตรงกับ config แล้ว"
            _log_r nochange "$SITE | domain=$DOMAIN | existing_key=${OLD_KEY}... | existing_email=${OLD_EMAIL:-"(none)"}"
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
export LOG_FILE LOCK_FILE LOG_PASS LOG_FAIL LOG_SKIP LOG_NOCHANGE LOG_MISMATCH LOG_OVERWRITE RESULT_DIR
export WP_TIMEOUT MAX_RETRY RETRY_DELAY CF_KEY CF_EMAIL CF_ONLY_ACTIVE CF_OVERWRITE_KEY

# ─── รัน parallel ────────────────────────────────────────────
declare -a PIDS=()
COUNT=0
for dir in "${DIRS[@]}"; do
    COUNT=$(( COUNT + 1 ))
    process_site "$dir" "$COUNT" "$TOTAL" &
    PIDS+=($!)
    if (( ${#PIDS[@]} >= MAX_JOBS )); then
        wait "${PIDS[0]}"
        PIDS=("${PIDS[@]:1}")
    fi
done
for pid in "${PIDS[@]}"; do wait "$pid"; done

# ─── สรุป ────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

SUCCESS=$(   find "$RESULT_DIR" -name "pass_*"      2>/dev/null | wc -l)
FAILED=$(    find "$RESULT_DIR" -name "fail_*"      2>/dev/null | wc -l)
SKIPPED=$(   find "$RESULT_DIR" -name "skip_*"      2>/dev/null | wc -l)
NOCHANGE=$(  find "$RESULT_DIR" -name "nochange_*"  2>/dev/null | wc -l)
MISMATCH=$(  find "$RESULT_DIR" -name "mismatch_*"  2>/dev/null | wc -l)
OVERWRITTEN=$(find "$RESULT_DIR" -name "overwrite_*" 2>/dev/null | wc -l)

log "======================================"
log " สรุปผลรวม"
log " รวมทั้งหมด        : $TOTAL เว็บ"
log " ✅ Pass (อัปเดต)  : $SUCCESS เว็บ"
log " ✏️  Force Overwrite : $OVERWRITTEN เว็บ  (มี key/email เดิมไม่ตรง — เขียนทับ)"
log " ⏩ Nochange         : $NOCHANGE เว็บ  (key+email ตรงกับ config แล้ว)"
log " ❌ Fail            : $FAILED เว็บ"
log " ⏭  Skip            : $SKIPPED เว็บ  (plugin ไม่ active / CF ปิด)"
log " ⚙️  Auto-fixed      : $MISMATCH เว็บ  (domain ถูกแก้อัตโนมัติจาก folder name)"
log " เวลาที่ใช้         : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log "======================================"
log " Log รวม           : $LOG_FILE"
log " ✅ Pass            : $LOG_PASS"
log " ✏️  Force Overwrite : $LOG_OVERWRITE"
log " ❌ Fail            : $LOG_FAIL"
log " ⏩ Nochange         : $LOG_NOCHANGE"
log " ⏭  Skip            : $LOG_SKIP"
log " ⚙️  Auto-fixed      : $LOG_MISMATCH"
log "======================================"

exit 0
