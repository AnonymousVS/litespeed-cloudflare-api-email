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

# ─── โหลด Config ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/config-apitoken-email.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ ERROR: ไม่พบไฟล์ config: $CONFIG_FILE"
    echo "   ดาวน์โหลด config ตัวอย่างได้ที่:"
    echo "   https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/config-apitoken-email.conf"
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ─── Validate Config ─────────────────────────────────────────
if [[ -z "$CF_KEY" || "$CF_KEY" == "YOUR_API_TOKEN_OR_GLOBAL_KEY_HERE" ]]; then
    echo "❌ ERROR: กรุณาตั้งค่า CF_KEY ใน $CONFIG_FILE ก่อนรัน"
    exit 1
fi

# ─── Auto-detect Auth Mode จาก CF_EMAIL ─────────────────────
# CF_EMAIL มีค่า → Global API Key mode / ว่างเปล่า → Token mode
if [[ -n "$CF_EMAIL" ]]; then
    CF_AUTH_MODE="apikey"
else
    CF_AUTH_MODE="token"
fi

# ─── ค่า Runtime ─────────────────────────────────────────────
MAX_JOBS=5
WP_TIMEOUT=30

LOG_FILE="/var/log/lscwp-cf-update.log"
LOG_PASS="/var/log/lscwp-cf-update-pass.log"
LOG_FAIL="/var/log/lscwp-cf-update-fail.log"
LOG_SKIP="/var/log/lscwp-cf-update-skip.log"
LOG_NOCHANGE="/var/log/lscwp-cf-update-nochange.log"
LOCK_FILE="${LOG_FILE}.lock"
RESULT_DIR="/tmp/lscwp-cf-update-$$"
mkdir -p "$RESULT_DIR"

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$1"
    ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
}

log_result() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    case "$1" in
        pass)     ( flock 201; echo "[$ts] $2" >> "$LOG_PASS"     ) 201>"${LOG_FILE}.pass.lock" ;;
        fail)     ( flock 202; echo "[$ts] $2" >> "$LOG_FAIL"     ) 202>"${LOG_FILE}.fail.lock" ;;
        skip)     ( flock 203; echo "[$ts] $2" >> "$LOG_SKIP"     ) 203>"${LOG_FILE}.skip.lock" ;;
        nochange) ( flock 204; echo "[$ts] $2" >> "$LOG_NOCHANGE" ) 204>"${LOG_FILE}.nochange.lock" ;;
    esac
}

cleanup() {
    wait
    rm -rf "$RESULT_DIR"
    rm -f "$LOCK_FILE" \
          "${LOG_FILE}.pass.lock" "${LOG_FILE}.fail.lock" \
          "${LOG_FILE}.skip.lock" "${LOG_FILE}.nochange.lock"
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

START_TIME=$(date +%s)
log "======================================"
log " BULK UPDATE CF CREDENTIALS (LiteSpeed)"
log " เริ่มเวลา    : $(date '+%Y-%m-%d %H:%M:%S')"
log " Config       : $CONFIG_FILE"
log " Auth Mode    : $CF_AUTH_MODE (auto-detect)"
log " Email        : ${CF_EMAIL:-"(ไม่ใช้ — Token mode)"}"
log " Key (prefix) : ${CF_KEY:0:8}..."
log " Clear Zone   : $CF_CLEAR_ZONE"
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
            pass)     ( flock 201; echo "[$ts] $2" >> "$LOG_PASS"     ) 201>"${LOG_FILE}.pass.lock" ;;
            fail)     ( flock 202; echo "[$ts] $2" >> "$LOG_FAIL"     ) 202>"${LOG_FILE}.fail.lock" ;;
            skip)     ( flock 203; echo "[$ts] $2" >> "$LOG_SKIP"     ) 203>"${LOG_FILE}.skip.lock" ;;
            nochange) ( flock 204; echo "[$ts] $2" >> "$LOG_NOCHANGE" ) 204>"${LOG_FILE}.nochange.lock" ;;
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

        // ── 5. เขียน Credentials ใหม่ลง DB ───────────────────
        $new_key   = '"'"'$CF_KEY'"'"';
        $new_email = '"'"'$CF_EMAIL'"'"';

        // auto-detect: มี email → apikey mode / ไม่มี → token mode
        $is_apikey = ($new_email !== "");

        update_option("litespeed.conf.cdn-cloudflare_key", $new_key);

        if ($is_apikey) {
            update_option("litespeed.conf.cdn-cloudflare_email", $new_email);
        } else {
            // token mode → ล้าง email ออก (ไม่ใช้)
            update_option("litespeed.conf.cdn-cloudflare_email", "");
        }

        // ── 6. CF_CLEAR_ZONE : ล้าง zone_id ─────────────────
        $clear_zone = ('"'"'$CF_CLEAR_ZONE'"'"' === "yes");
        if ($clear_zone) {
            update_option("litespeed.conf.cdn-cloudflare_zone", "");
        }

        // ── 7. Verify อ่านกลับมาตรวจ ────────────────────────
        $v_key   = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",   ""));
        $v_email = trim((string) get_option("litespeed.conf.cdn-cloudflare_email", ""));
        $v_zone  = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone",  ""));

        $key_ok = ($v_key === $new_key) ? 1 : 0;

        printf(
            "STATUS:DONE\tKEY_OK:%d\tDOMAIN:%s\tOLD_KEY:%s\tNEW_KEY:%s\tOLD_EMAIL:%s\tNEW_EMAIL:%s\tOLD_ZONE:%s\tNEW_ZONE:%s",
            $key_ok,
            $cur_name,
            substr($cur_key,   0, 8),
            substr($v_key,     0, 8),
            $cur_email,
            $v_email,
            $cur_zone   ? substr($cur_zone, 0, 12)."..." : "(empty)",
            $v_zone     ?: "(cleared)"
        );
    ' --allow-root 2>/dev/null)

    local STATUS
    STATUS=$(echo "$EVAL_OUT" | grep -oP '(?<=STATUS:)\w+')

    case "$STATUS" in
        DONE)
            local KEY_OK DOMAIN OLD_KEY NEW_KEY OLD_EMAIL NEW_EMAIL OLD_ZONE NEW_ZONE
            KEY_OK=$(    echo "$EVAL_OUT" | grep -oP '(?<=KEY_OK:)\d+')
            DOMAIN=$(    echo "$EVAL_OUT" | grep -oP '(?<=DOMAIN:)[^\t]*')
            OLD_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=OLD_KEY:)[^\t]*')
            NEW_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=NEW_KEY:)[^\t]*')
            OLD_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=OLD_EMAIL:)[^\t]*')
            NEW_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=NEW_EMAIL:)[^\t]*')
            OLD_ZONE=$(  echo "$EVAL_OUT" | grep -oP '(?<=OLD_ZONE:)[^\t]*')
            NEW_ZONE=$(  echo "$EVAL_OUT" | grep -oP '(?<=NEW_ZONE:)[^\t]*')

            if [[ "$KEY_OK" == "1" ]]; then
                _log  "✅ PASS: $LABEL | domain=$DOMAIN | key: ${OLD_KEY}... → ${NEW_KEY}... | zone: $OLD_ZONE → $NEW_ZONE"
                _log_r pass "$SITE | domain=$DOMAIN | old_key=${OLD_KEY}... | new_key=${NEW_KEY}... | old_email=$OLD_EMAIL | new_email=$NEW_EMAIL | zone: $OLD_ZONE → $NEW_ZONE"
                touch "${RESULT_DIR}/pass_${UNIQ}"
            else
                _log  "❌ FAIL (verify ไม่ผ่าน): $LABEL | domain=$DOMAIN"
                _log_r fail "$SITE | domain=$DOMAIN | verify failed — key ไม่ตรง"
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
export LOG_FILE LOCK_FILE LOG_PASS LOG_FAIL LOG_SKIP LOG_NOCHANGE RESULT_DIR
export WP_TIMEOUT CF_KEY CF_EMAIL CF_AUTH_MODE CF_CLEAR_ZONE CF_ONLY_ACTIVE CF_OVERWRITE_KEY

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

SUCCESS=$(  find "$RESULT_DIR" -name "pass_*"     2>/dev/null | wc -l)
FAILED=$(   find "$RESULT_DIR" -name "fail_*"     2>/dev/null | wc -l)
SKIPPED=$(  find "$RESULT_DIR" -name "skip_*"     2>/dev/null | wc -l)
NOCHANGE=$( find "$RESULT_DIR" -name "nochange_*" 2>/dev/null | wc -l)

log "======================================"
log " สรุปผลรวม"
log " รวมทั้งหมด      : $TOTAL เว็บ"
log " ✅ Pass (อัปเดต) : $SUCCESS เว็บ"
log " ⏩ Nochange       : $NOCHANGE เว็บ  (มี key อยู่แล้ว ข้ามตาม CF_OVERWRITE_KEY=no)"
log " ❌ Fail          : $FAILED เว็บ"
log " ⏭  Skip          : $SKIPPED เว็บ  (plugin ไม่ active / CF ปิด)"
log " เวลาที่ใช้       : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log "======================================"
log " Log รวม         : $LOG_FILE"
log " ✅ Pass          : $LOG_PASS"
log " ❌ Fail          : $LOG_FAIL"
log " ⏩ Nochange       : $LOG_NOCHANGE"
log " ⏭  Skip          : $LOG_SKIP"
log "======================================"

exit 0
