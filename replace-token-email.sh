#!/bin/bash
# =============================================================
#  replace-token-email.sh  v2
#  Bulk Update Cloudflare API Key / Token / Email
#  LiteSpeed Cache › CDN › Cloudflare
#  ──────────────────────────────────────────────────────────
#  v2 : อ่านจาก CSV — แต่ละโดเมนมี Email + API Token ของตัวเอง
#       ประมวลผลเฉพาะโดเมนที่ระบุใน config-domain.csv
#       เปิด Cloudflare API + CDN + ดึง Zone ID อัตโนมัติ
#
#  ไฟล์ Config (GitHub CSV):
#    config-domain.csv         → Domain , Cloudflare Email
#    config-api-key-token.csv  → Cloudflare Email , API Token
#
#  Repo : https://github.com/AnonymousVS/litespeed-cloudflare-api-email
#
#  วิธีใช้:
#    bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/replace-token-email.sh)
#
#    หรือใช้ไฟล์ CSV local:
#    bash replace-token-email.sh [config-domain.csv] [config-api-key-token.csv]
# =============================================================

VERSION="v2"

# ─── URL ของ CSV บน GitHub ────────────────────────────────────
DOMAIN_CSV_URL="https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/config-domain.csv"
TOKEN_CSV_URL="https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/config-api-key-token.csv"

# ─── รับ path จาก argument หรือใช้ default ───────────────────
DOMAIN_CSV="${1:-/root/config-domain.csv}"
TOKEN_CSV="${2:-/root/config-api-key-token.csv}"

# ─── ดาวน์โหลด CSV ถ้ายังไม่มี ──────────────────────────────
download_csv() {
    local file="$1" url="$2" label="$3"
    if [[ ! -f "$file" ]]; then
        echo "📥 ดาวน์โหลด $label จาก GitHub..."
        if ! curl -fsSL "$url" -o "$file"; then
            echo "❌ ERROR: ดาวน์โหลด $label ไม่สำเร็จ"
            exit 1
        fi
        echo "✅ → $file"
    fi
}

download_csv "$DOMAIN_CSV"  "$DOMAIN_CSV_URL"  "config-domain.csv"
download_csv "$TOKEN_CSV"   "$TOKEN_CSV_URL"   "config-api-key-token.csv"

# ─── อ่าน CSV สร้าง Associative Array ───────────────────────
#  DOMAIN_EMAIL[domain]  = email
#  EMAIL_TOKEN[email]    = api_token
#  DOMAIN_TOKEN[domain]  = api_token   (lookup สำเร็จ)
# ─────────────────────────────────────────────────────────────

declare -A DOMAIN_EMAIL
declare -A EMAIL_TOKEN
declare -A DOMAIN_TOKEN
declare -a DOMAIN_LIST=()

# อ่าน config-api-key-token.csv → EMAIL_TOKEN
while IFS=',' read -r email token; do
    # ลบ \r, ลบ whitespace หน้า-หลัง
    email=$(echo "$email" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    token=$(echo "$token" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # ข้าม header + บรรทัดว่าง
    [[ "$email" == "Cloudflare Email" ]] && continue
    [[ -z "$email" || -z "$token" ]] && continue
    [[ "$token" == "YOUR_API_TOKEN_HERE" ]] && continue
    EMAIL_TOKEN["$email"]="$token"
done < "$TOKEN_CSV"

echo "📋 อ่าน API Token : ${#EMAIL_TOKEN[@]} รายการ"

# อ่าน config-domain.csv → DOMAIN_EMAIL + DOMAIN_TOKEN
while IFS=',' read -r domain email; do
    domain=$(echo "$domain" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    email=$(echo "$email"   | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # ข้าม header + บรรทัดว่าง
    [[ "$domain" == "Domain" ]] && continue
    [[ -z "$domain" || -z "$email" ]] && continue
    DOMAIN_EMAIL["$domain"]="$email"
    DOMAIN_LIST+=("$domain")

    # lookup token จาก EMAIL_TOKEN
    if [[ -n "${EMAIL_TOKEN[$email]+_}" ]]; then
        DOMAIN_TOKEN["$domain"]="${EMAIL_TOKEN[$email]}"
    else
        DOMAIN_TOKEN["$domain"]=""
    fi
done < "$DOMAIN_CSV"

echo "📋 อ่านโดเมน      : ${#DOMAIN_LIST[@]} รายการ"

# ─── Validate ────────────────────────────────────────────────
if [[ ${#DOMAIN_LIST[@]} -eq 0 ]]; then
    echo "❌ ERROR: ไม่พบโดเมนใน $DOMAIN_CSV"
    exit 1
fi

# ตรวจว่ามี token ครบไหม
MISSING_TOKEN=0
for d in "${DOMAIN_LIST[@]}"; do
    if [[ -z "${DOMAIN_TOKEN[$d]}" ]]; then
        echo "⚠️  WARNING: โดเมน $d (email: ${DOMAIN_EMAIL[$d]}) ไม่มี API Token ใน $TOKEN_CSV"
        MISSING_TOKEN=$(( MISSING_TOKEN + 1 ))
    fi
done

# ─── แสดงค่าที่จะใช้ + Confirm ──────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════"
echo "║   🔄  replace-token-email.sh  $VERSION"
echo "║   CSV-based — แต่ละโดเมนมี Email + Token ของตัวเอง"
echo "╠══════════════════════════════════════════════════════════════"
echo "║"
echo "║   config-domain.csv       : $DOMAIN_CSV"
echo "║   config-api-key-token.csv: $TOKEN_CSV"
echo "║   จำนวนโดเมน              : ${#DOMAIN_LIST[@]}"
echo "║   มี Token พร้อม          : $(( ${#DOMAIN_LIST[@]} - MISSING_TOKEN ))"
echo "║   ขาด Token               : $MISSING_TOKEN"
echo "║"
echo "║   การทำงาน:"
echo "║     1. ค้นหา WordPress directory ของแต่ละโดเมน"
echo "║     2. เปิด Cloudflare API  = ON  (litespeed.conf.cdn-cloudflare)"
echo "║     3. ใส่ API Token + Email"
echo "║     4. เปิด CDN             = ON  (litespeed.conf.cdn)"
echo "║     5. กด Save = ดึง Zone ID จาก Cloudflare API"
echo "║     6. ตรวจสอบ: Zone ID แสดง = ✅ ไปเว็บถัดไป"
echo "║                 Zone ID ไม่แสดง = ⚠️ เก็บ Log"
echo "║"
printf "║   %-25s %-38s %s\n" "Domain" "Email" "Token"
echo "║   ───────────────────────── ────────────────────────────────────── ────────────"
for d in "${DOMAIN_LIST[@]}"; do
    local_token="${DOMAIN_TOKEN[$d]}"
    if [[ -n "$local_token" ]]; then
        token_display="${local_token:0:8}...${local_token: -4}"
    else
        token_display="❌ ไม่มี"
    fi
    printf "║   %-25s %-38s %s\n" "$d" "${DOMAIN_EMAIL[$d]}" "$token_display"
done
echo "║"
echo "╚══════════════════════════════════════════════════════════════"
echo ""

if [[ $MISSING_TOKEN -gt 0 ]]; then
    echo "⚠️  มี $MISSING_TOKEN โดเมนที่ขาด Token — จะถูกข้ามไป"
    echo ""
fi

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
LOG_WARN="/var/log/lscwp-cf-update-warn.log"
LOG_FAIL="/var/log/lscwp-cf-update-fail.log"
LOG_SKIP="/var/log/lscwp-cf-update-skip.log"
LOG_NOTFOUND="/var/log/lscwp-cf-update-notfound.log"
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
          "${LOG_FILE}.pass.lock" "${LOG_FILE}.warn.lock" "${LOG_FILE}.fail.lock" \
          "${LOG_FILE}.skip.lock" "${LOG_FILE}.notfound.lock"
}
trap cleanup EXIT

# ─── ตรวจ WP-CLI ─────────────────────────────────────────────
if ! command -v wp &>/dev/null; then
    log "❌ ERROR: ไม่พบ WP-CLI — https://wp-cli.org"
    exit 1
fi

# ─── ล้าง log ────────────────────────────────────────────────
> "$LOG_FILE"
> "$LOG_PASS"
> "$LOG_WARN"
> "$LOG_FAIL"
> "$LOG_SKIP"
> "$LOG_NOTFOUND"

START_TIME=$(date +%s)
log "======================================"
log " BULK UPDATE CF CREDENTIALS (LiteSpeed)  $VERSION"
log " เริ่มเวลา : $(date '+%Y-%m-%d %H:%M:%S')"
log " โดเมน     : ${#DOMAIN_LIST[@]} รายการ (มี token ${#DOMAIN_LIST[@]}-${MISSING_TOKEN}=$(( ${#DOMAIN_LIST[@]} - MISSING_TOKEN )))"
log " Jobs      : $MAX_JOBS"
log "======================================"

# ─── ค้นหา WordPress — สร้าง map: domain → wp_path ──────────
declare -A WP_PATH_MAP

# Scan ทุก wp-config.php
declare -a ALL_WP_DIRS=()
declare -A _SEEN

# แหล่งที่ 1: WHM — /etc/trueuserdomains
if [[ -f /etc/trueuserdomains ]]; then
    while IFS=' ' read -r _dom _usr _rest; do
        _usr="${_usr%:}"
        [[ -z "$_usr" ]] && continue
        _uhome=$(getent passwd "$_usr" 2>/dev/null | cut -d: -f6)
        [[ -d "$_uhome" ]] || continue
        while IFS= read -r -d '' _wpc; do
            _d="$(dirname "$_wpc")/"
            [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; ALL_WP_DIRS+=("$_d"); }
        done < <(find "$_uhome" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
    done < /etc/trueuserdomains
fi

# แหล่งที่ 2: Scan /home*
for _base in /home /home2 /home3 /home4 /home5 /usr/home; do
    [[ -d "$_base" ]] || continue
    while IFS= read -r -d '' _wpc; do
        _d="$(dirname "$_wpc")/"
        [[ -z "${_SEEN[$_d]+_}" ]] && { _SEEN[$_d]=1; ALL_WP_DIRS+=("$_d"); }
    done < <(find "$_base" -maxdepth 5 -name "wp-config.php" -print0 2>/dev/null)
done

log "พบ WordPress ทั้งหมด : ${#ALL_WP_DIRS[@]} เว็บ"

# ─── จับคู่ domain กับ wp path ────────────────────────────────
# วิธีที่ 1: folder name = domain name (addon/subdomain ใน cPanel)
# วิธีที่ 2: public_html → ใช้ /etc/userdatadomains หา main domain
# วิธีที่ 3: Fallback → ใช้ wp option get siteurl
# ─────────────────────────────────────────────────────────────

for dir in "${ALL_WP_DIRS[@]}"; do
    folder=$(basename "${dir%/}")

    if [[ "$folder" != "public_html" ]]; then
        # ── addon/subdomain: folder = domain name ─────────────
        for target_domain in "${DOMAIN_LIST[@]}"; do
            if [[ "$folder" == "$target_domain" ]]; then
                WP_PATH_MAP["$target_domain"]="$dir"
                break
            fi
        done
    else
        # ── main domain (public_html) ─────────────────────────
        # หา cPanel username จาก path
        # ใช้ awk: หา folder ที่ชื่อ home* แล้วเอา folder ถัดไป = username
        _user=$(echo "$dir" | awk -F'/' '{for(i=1;i<=NF;i++){if($i ~ /^home[0-9]*$/){print $(i+1);exit}}}')
        _main_domain=""

        # วิธี A: ใช้ /etc/userdatadomains (cPanel)
        if [[ -f /etc/userdatadomains && -n "$_user" ]]; then
            while IFS=': ' read -r _udom _rest; do
                [[ -z "$_udom" || -z "$_rest" ]] && continue
                # format: domain: user==owner==type==docroot==ip==port
                _uusr=$(echo "$_rest" | awk -F'==' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                _type=$(echo "$_rest" | awk -F'==' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ "$_uusr" == "$_user" && "$_type" == "main" ]]; then
                    _main_domain="$_udom"
                    break
                fi
            done < /etc/userdatadomains
        fi

        # วิธี B: ใช้ /var/cpanel/users/$_user (cPanel)
        if [[ -z "$_main_domain" && -f "/var/cpanel/users/$_user" ]]; then
            _main_domain=$(grep '^DNS=' "/var/cpanel/users/$_user" 2>/dev/null | head -1 | cut -d= -f2)
        fi

        # วิธี C: Fallback → ใช้ wp option get siteurl
        if [[ -z "$_main_domain" ]]; then
            _siteurl=$(timeout 10 wp --path="$dir" option get siteurl --allow-root 2>/dev/null)
            if [[ -n "$_siteurl" ]]; then
                # ลบ http(s):// และ trailing /
                _main_domain=$(echo "$_siteurl" | sed 's|^https\?://||;s|/.*||')
            fi
        fi

        # จับคู่กับ DOMAIN_LIST
        if [[ -n "$_main_domain" ]]; then
            for target_domain in "${DOMAIN_LIST[@]}"; do
                if [[ "$_main_domain" == "$target_domain" ]]; then
                    WP_PATH_MAP["$target_domain"]="$dir"
                    break
                fi
            done
        fi
    fi
done

# แสดงผลการ match
MATCHED=0
for d in "${DOMAIN_LIST[@]}"; do
    if [[ -n "${WP_PATH_MAP[$d]:-}" ]]; then
        log "  📁 $d → ${WP_PATH_MAP[$d]}"
        MATCHED=$(( MATCHED + 1 ))
    fi
done
log "จับคู่ domain ↔ WP path ได้ : $MATCHED / ${#DOMAIN_LIST[@]}"
log "======================================"

# ─── ฟังก์ชัน process แต่ละโดเมน ─────────────────────────────
process_domain() {
    local domain="$1"
    local wp_dir="$2"
    local cf_email="$3"
    local cf_token="$4"
    local count="$5"
    local total="$6"
    local UNIQ="${BASHPID}_$(date +%s%N)"
    local LABEL="[$count/$total] $domain"

    _log() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$1"
        ( flock 200; echo "[$ts] $1" >> "$LOG_FILE" ) 200>"$LOCK_FILE"
    }
    _log_r() {
        local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
        case "$1" in
            pass)     ( flock 201; echo "[$ts] $2" >> "$LOG_PASS"     ) 201>"${LOG_FILE}.pass.lock" ;;
            warn)     ( flock 205; echo "[$ts] $2" >> "$LOG_WARN"     ) 205>"${LOG_FILE}.warn.lock" ;;
            fail)     ( flock 202; echo "[$ts] $2" >> "$LOG_FAIL"     ) 202>"${LOG_FILE}.fail.lock" ;;
            skip)     ( flock 203; echo "[$ts] $2" >> "$LOG_SKIP"     ) 203>"${LOG_FILE}.skip.lock" ;;
            notfound) ( flock 204; echo "[$ts] $2" >> "$LOG_NOTFOUND" ) 204>"${LOG_FILE}.notfound.lock" ;;
        esac
    }

    # ── เรียก wp eval เพื่ออัปเดต LiteSpeed Cache options ────
    # ── ทำทุกอย่างใน wp eval ครั้งเดียว = "กด Save 1 ครั้ง" ──
    EVAL_OUT=$(timeout "$WP_TIMEOUT" wp --path="$wp_dir" eval '
        // ── 1. Plugin active? ────────────────────────────────
        if (!is_plugin_active("litespeed-cache/litespeed-cache.php")) {
            echo "STATUS:NOPLUGIN"; return;
        }

        // ── 2. อ่าน options ปัจจุบัน ─────────────────────────
        $cur_enabled  = get_option("litespeed.conf.cdn-cloudflare",            "0");
        $cur_key      = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",    ""));
        $cur_email    = trim((string) get_option("litespeed.conf.cdn-cloudflare_email",  ""));
        $cur_zone     = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone",   ""));
        $cur_name     = trim((string) get_option("litespeed.conf.cdn-cloudflare_name",   ""));

        // ── 3. ค่าใหม่จาก CSV ────────────────────────────────
        $new_key    = '"'"'$cf_token'"'"';
        $new_email  = '"'"'$cf_email'"'"';
        $new_domain = '"'"'$domain'"'"';

        // ══════════════════════════════════════════════════════
        // ── 4. เปิด Cloudflare API (Turn ON) ─────────────────
        //    Option: litespeed.conf.cdn-cloudflare
        //    ค่า: "1" = เปิด, "0" = ปิด
        // ══════════════════════════════════════════════════════
        update_option("litespeed.conf.cdn-cloudflare", "1");

        // ══════════════════════════════════════════════════════
        // ── 5. ใส่ API Token + Email + Domain Name ───────────
        //    Option: litespeed.conf.cdn-cloudflare_key
        //    Option: litespeed.conf.cdn-cloudflare_email
        //    Option: litespeed.conf.cdn-cloudflare_name
        //    Option: litespeed.conf.cdn-cloudflare_zone (reset)
        // ══════════════════════════════════════════════════════
        update_option("litespeed.conf.cdn-cloudflare_key",   $new_key);
        update_option("litespeed.conf.cdn-cloudflare_email", $new_email);
        update_option("litespeed.conf.cdn-cloudflare_name",  $new_domain);
        update_option("litespeed.conf.cdn-cloudflare_zone",  "");

        // ══════════════════════════════════════════════════════
        // ── 6. เปิด CDN (Turn ON) ────────────────────────────
        //    Option: litespeed.conf.cdn
        //    ค่า: "1" = เปิด
        // ══════════════════════════════════════════════════════
        update_option("litespeed.conf.cdn", "1");

        // ══════════════════════════════════════════════════════
        // ── 7. เปิด Clear Cloudflare cache on purge all ──────
        //    Option: litespeed.conf.cdn-cloudflare_clear
        //    ค่า: "1" = เปิด (v7.2+)
        //    เมื่อ LiteSpeed Purge All → purge CF cache ด้วย
        // ══════════════════════════════════════════════════════
        update_option("litespeed.conf.cdn-cloudflare_clear", "1");

        // ══════════════════════════════════════════════════════
        // ── 8. ดึง Zone ID จาก Cloudflare API ────────────────
        //    = เทียบเท่า "กด Save Changes" ในหน้า Cloudflare CDN
        //    กด Save → plugin ดึง Zone ID จาก CF API อัตโนมัติ
        //    ถ้า Zone ID แสดง = Success
        //    ถ้า Zone ID ไม่แสดง = Key+Email ใส่แล้ว แต่ Zone ยังไม่ได้
        // ══════════════════════════════════════════════════════
        $max_retry   = '"'"'$MAX_RETRY'"'"';
        $retry_delay = '"'"'$RETRY_DELAY'"'"';
        $zone_id     = "";
        $zone_name   = "";
        $cf_error    = "";
        $attempt     = 0;

        $is_apikey = ($new_email !== "");
        $headers = $is_apikey
            ? ["X-Auth-Email: $new_email", "X-Auth-Key: $new_key", "Content-Type: application/json"]
            : ["Authorization: Bearer $new_key",                    "Content-Type: application/json"];

        while ($attempt < $max_retry) {
            $attempt++;
            $url = "https://api.cloudflare.com/client/v4/zones?status=active&match=all&name=" . urlencode($new_domain);
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
            $zone_name = $res["result"][0]["name"] ?? $new_domain;
            if ($zone_id) break;
            $cf_error = "zone_empty";
            if ($attempt < $max_retry) sleep($retry_delay);
        }

        // ══════════════════════════════════════════════════════
        // ── 9. บันทึก Zone ID ลง DB (= Save Changes) ─────────
        //    ถ้า Zone ID ได้ → บันทึก = ตรวจสอบผ่าน
        // ══════════════════════════════════════════════════════
        if ($zone_id) {
            update_option("litespeed.conf.cdn-cloudflare_zone", $zone_id);
            update_option("litespeed.conf.cdn-cloudflare_name", $zone_name);
        }

        // ══════════════════════════════════════════════════════
        // ── 10. Verify ทุกค่า ──────────────────────────────────
        // ══════════════════════════════════════════════════════
        $v_cf_on   = get_option("litespeed.conf.cdn-cloudflare",          "0");
        $v_cdn_on  = get_option("litespeed.conf.cdn",                     "0");
        $v_key     = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",   ""));
        $v_zone    = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone",  ""));
        $v_email   = trim((string) get_option("litespeed.conf.cdn-cloudflare_email", ""));
        $v_name    = trim((string) get_option("litespeed.conf.cdn-cloudflare_name",  ""));

        $key_ok    = ($v_key   === $new_key)   ? 1 : 0;
        $email_ok  = ($v_email === $new_email)  ? 1 : 0;
        $cf_on     = ($v_cf_on === "1")         ? 1 : 0;
        $cdn_on    = ($v_cdn_on === "1")        ? 1 : 0;

        printf(
            "STATUS:DONE\tCF_ON:%d\tCDN_ON:%d\tKEY_OK:%d\tEMAIL_OK:%d\tDOMAIN:%s\tOLD_KEY:%s\tNEW_KEY:%s\tOLD_EMAIL:%s\tNEW_EMAIL:%s\tOLD_ZONE:%s\tNEW_ZONE:%s\tATTEMPT:%d\tCF_ERROR:%s",
            $cf_on,
            $cdn_on,
            $key_ok,
            $email_ok,
            $v_name ?: $new_domain,
            substr($cur_key,  0, 8),
            substr($v_key,    0, 8),
            $cur_email,
            $v_email,
            $cur_zone ? substr($cur_zone, 0, 12)."..." : "(empty)",
            $v_zone   ?: "(no zone)",
            $attempt,
            $cf_error
        );
    ' --allow-root 2>/dev/null)

    # ── แยกผลลัพธ์ ────────────────────────────────────────────
    local STATUS
    STATUS=$(echo "$EVAL_OUT" | grep -oP '(?<=STATUS:)\w+')

    case "$STATUS" in
        DONE)
            local CF_ON CDN_ON KEY_OK EMAIL_OK DOMAIN OLD_KEY NEW_KEY OLD_EMAIL NEW_EMAIL OLD_ZONE NEW_ZONE ATTEMPT CF_ERROR
            CF_ON=$(     echo "$EVAL_OUT" | grep -oP '(?<=CF_ON:)\d+')
            CDN_ON=$(    echo "$EVAL_OUT" | grep -oP '(?<=CDN_ON:)\d+')
            KEY_OK=$(    echo "$EVAL_OUT" | grep -oP '(?<=KEY_OK:)\d+')
            EMAIL_OK=$(  echo "$EVAL_OUT" | grep -oP '(?<=EMAIL_OK:)\d+')
            DOMAIN=$(    echo "$EVAL_OUT" | grep -oP '(?<=DOMAIN:)[^\t]*')
            OLD_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=OLD_KEY:)[^\t]*')
            NEW_KEY=$(   echo "$EVAL_OUT" | grep -oP '(?<=NEW_KEY:)[^\t]*')
            OLD_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=OLD_EMAIL:)[^\t]*')
            NEW_EMAIL=$( echo "$EVAL_OUT" | grep -oP '(?<=NEW_EMAIL:)[^\t]*')
            OLD_ZONE=$(  echo "$EVAL_OUT" | grep -oP '(?<=OLD_ZONE:)[^\t]*')
            NEW_ZONE=$(  echo "$EVAL_OUT" | grep -oP '(?<=NEW_ZONE:)[^\t]*')
            ATTEMPT=$(   echo "$EVAL_OUT" | grep -oP '(?<=ATTEMPT:)\d+')
            CF_ERROR=$(  echo "$EVAL_OUT" | grep -oP '(?<=CF_ERROR:)[^\t]*')

            if [[ "$KEY_OK" == "1" && "$EMAIL_OK" == "1" && "$CF_ON" == "1" && "$NEW_ZONE" != "(no zone)" ]]; then
                # ✅ Zone ID แสดง = Success → ไปเว็บถัดไป
                _log  "✅ PASS: $LABEL | CF=ON | key: ${OLD_KEY}→${NEW_KEY} | email: ${OLD_EMAIL}→${NEW_EMAIL} | zone: $OLD_ZONE→$NEW_ZONE | attempt=${ATTEMPT}/${MAX_RETRY}"
                _log_r pass "$domain | CF=ON | key=${NEW_KEY}... | email=$NEW_EMAIL | zone=$NEW_ZONE"
                touch "${RESULT_DIR}/pass_${UNIQ}"
            elif [[ "$KEY_OK" == "1" && "$EMAIL_OK" == "1" && "$CF_ON" == "1" && "$CF_ERROR" == "zone_empty" ]]; then
                # ⚠️ Key+Email ใส่แล้ว + CF เปิดแล้ว แต่ Zone ID ยังไม่แสดง
                _log  "⚠️  WARN: $LABEL | CF=ON | Key+Email ใส่แล้ว แต่ Zone ID ยังไม่แสดง (domain อาจไม่อยู่ใน CF account นี้)"
                _log_r warn "$domain | CF=ON | key=${NEW_KEY}... | email=$NEW_EMAIL | Zone ID ยังไม่แสดง"
                touch "${RESULT_DIR}/warn_${UNIQ}"
            elif [[ "$KEY_OK" == "1" && "$EMAIL_OK" == "1" && "$CF_ON" == "1" ]]; then
                # ⚠️ Key+Email ใส่แล้ว + CF เปิดแล้ว แต่ CF API error → Zone ID ไม่ได้
                _log  "⚠️  WARN: $LABEL | CF=ON | Key+Email ใส่แล้ว แต่ Zone ID ยังไม่แสดง | error=$CF_ERROR | attempt=${ATTEMPT}/${MAX_RETRY}"
                _log_r warn "$domain | CF=ON | key=${NEW_KEY}... | email=$NEW_EMAIL | Zone ID ยังไม่แสดง | error=$CF_ERROR"
                touch "${RESULT_DIR}/warn_${UNIQ}"
            else
                # ❌ Key หรือ Email verify ไม่ผ่าน = จริงจัง FAIL
                _log  "❌ FAIL (verify): $LABEL | key_ok=$KEY_OK email_ok=$EMAIL_OK cf_on=$CF_ON"
                _log_r fail "$domain | verify failed — key_ok=$KEY_OK email_ok=$EMAIL_OK cf_on=$CF_ON"
                touch "${RESULT_DIR}/fail_${UNIQ}"
            fi
            ;;
        NOPLUGIN)
            _log  "⏭  SKIP: $LABEL | LiteSpeed Cache ไม่ active"
            _log_r skip "$domain | plugin ไม่ active"
            touch "${RESULT_DIR}/skip_${UNIQ}"
            ;;
        *)
            _log  "❌ FAIL: $LABEL | wp error/timeout | ${EVAL_OUT:0:200}"
            _log_r fail "$domain | wp eval ล้มเหลว | ${EVAL_OUT:0:200}"
            touch "${RESULT_DIR}/fail_${UNIQ}"
            ;;
    esac
}

export -f process_domain
export LOG_FILE LOCK_FILE LOG_PASS LOG_WARN LOG_FAIL LOG_SKIP LOG_NOTFOUND RESULT_DIR
export WP_TIMEOUT MAX_RETRY RETRY_DELAY

# ─── วนลูปแต่ละโดเมนจาก CSV ─────────────────────────────────
declare -a PIDS=()
COUNT=0
TOTAL=${#DOMAIN_LIST[@]}
FOUND=0
NOT_FOUND=0

for domain in "${DOMAIN_LIST[@]}"; do
    COUNT=$(( COUNT + 1 ))
    cf_email="${DOMAIN_EMAIL[$domain]}"
    cf_token="${DOMAIN_TOKEN[$domain]}"

    # ข้ามถ้าไม่มี token
    if [[ -z "$cf_token" ]]; then
        log "⚠️  [$COUNT/$TOTAL] $domain → ข้ามเพราะไม่มี API Token (email: $cf_email)"
        ( flock 203; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $domain | ไม่มี token สำหรับ $cf_email" >> "$LOG_SKIP" ) 203>"${LOG_FILE}.skip.lock"
        touch "${RESULT_DIR}/skip_${BASHPID}_$(date +%s%N)"
        continue
    fi

    # หา wp path
    wp_dir="${WP_PATH_MAP[$domain]:-}"
    if [[ -z "$wp_dir" ]]; then
        log "🔍 [$COUNT/$TOTAL] $domain → ไม่พบ WordPress directory บนเซิร์ฟเวอร์"
        ( flock 204; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $domain | ไม่พบ WP path" >> "$LOG_NOTFOUND" ) 204>"${LOG_FILE}.notfound.lock"
        touch "${RESULT_DIR}/notfound_${BASHPID}_$(date +%s%N)"
        NOT_FOUND=$(( NOT_FOUND + 1 ))
        continue
    fi

    FOUND=$(( FOUND + 1 ))

    # process_domain รับค่าผ่าน function arguments โดยตรง
    process_domain "$domain" "$wp_dir" "$cf_email" "$cf_token" "$COUNT" "$TOTAL" &
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
WARNED=$(   find "$RESULT_DIR" -name "warn_*"     2>/dev/null | wc -l)
FAILED=$(   find "$RESULT_DIR" -name "fail_*"     2>/dev/null | wc -l)
SKIPPED=$(  find "$RESULT_DIR" -name "skip_*"     2>/dev/null | wc -l)
NOTFOUND=$( find "$RESULT_DIR" -name "notfound_*" 2>/dev/null | wc -l)

log "======================================"
log " สรุปผลรวม  $VERSION"
log "────────────────────────────────────"
log " โดเมนใน CSV      : $TOTAL"
log " พบ WP path       : $FOUND"
log " ✅ Pass           : $SUCCESS เว็บ  (Zone ID แสดง = สำเร็จ)"
log " ⚠️  Warn           : $WARNED เว็บ  (Key+Email ใส่แล้ว แต่ Zone ID ยังไม่แสดง)"
log " ❌ Fail           : $FAILED เว็บ  (verify key/email ไม่ผ่าน)"
log " ⏭  Skip           : $SKIPPED เว็บ  (ไม่มี token / plugin ไม่ active)"
log " 🔍 Not Found      : $NOTFOUND เว็บ  (ไม่พบ WP directory)"
log " เวลาที่ใช้        : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log "======================================"
log " Log รวม      : $LOG_FILE"
log " ✅ Pass       : $LOG_PASS"
log " ⚠️  Warn       : $LOG_WARN"
log " ❌ Fail       : $LOG_FAIL"
log " ⏭  Skip       : $LOG_SKIP"
log " 🔍 Not Found  : $LOG_NOTFOUND"
log "======================================"

exit 0
