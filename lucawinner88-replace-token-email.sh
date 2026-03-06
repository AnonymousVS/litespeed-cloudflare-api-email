#!/bin/bash
# =============================================================
#  lucawinner88-replace-token-email.sh
#  Update Cloudflare API Key / Token / Email — lucawinner88.co
#
#  Repo   : https://github.com/AnonymousVS/litespeed-cloudflare-api-email
#  วิธีใช้:
#    bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/lucawinner88-replace-token-email.sh)
# =============================================================

VERSION="v1"
TARGET_DOMAIN="lucawinner88.co"
TARGET_PATH="/home/armadaso3/lucawinner88.co"

CONF_URL="https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/refs/heads/main/config-apitoken-email.conf"

MAX_RETRY=3
RETRY_DELAY=5
WP_TIMEOUT=60

LOG_FILE="/var/log/lscwp-cf-update-lucawinner88.log"

log() {
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$1"
    echo "[$ts] $1" >> "$LOG_FILE"
}

> "$LOG_FILE"

# ─── ตรวจ WP-CLI ─────────────────────────────────────────────
if ! command -v wp &>/dev/null; then
    echo "❌ ERROR: ไม่พบ WP-CLI — https://wp-cli.org"
    exit 1
fi

# ─── ตรวจ path ───────────────────────────────────────────────
if [[ ! -f "${TARGET_PATH}/wp-config.php" ]]; then
    echo "❌ ERROR: ไม่พบ WordPress ที่ $TARGET_PATH"
    echo "   ตรวจสอบว่า path ถูกต้องและมี wp-config.php อยู่"
    exit 1
fi

# ─── โหลด Config ─────────────────────────────────────────────
CONFIG_FILE="${1:-/root/config-apitoken-email.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
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
echo "║   Target     :  $TARGET_DOMAIN"
echo "║   Path       :  $TARGET_PATH"
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
echo "╚══════════════════════════════════════════════════════════════"
echo ""
read -rp "  ▶  ยืนยันการเปลี่ยนค่า? [y/N] : " _CONFIRM
echo ""
if [[ ! "$_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "🚫 ยกเลิกการทำงาน"
    exit 0
fi

# ─── เริ่มทำงาน ───────────────────────────────────────────────
START_TIME=$(date +%s)
log "======================================"
log " UPDATE CF CREDENTIALS — $TARGET_DOMAIN  $VERSION"
log " เริ่มเวลา : $(date '+%Y-%m-%d %H:%M:%S')"
log " Path      : $TARGET_PATH"
log " Auth Mode : $CF_AUTH_MODE (auto-detect)"
log " Email     : ${CF_EMAIL:-"(ไม่ใช้ — Token mode)"}"
log " Key       : ${CF_KEY:0:8}..."
log "======================================"

# ─── Process เว็บเดียว ────────────────────────────────────────
EVAL_OUT=$(timeout "$WP_TIMEOUT" wp --path="$TARGET_PATH" eval '
    // ── 1. Plugin active? ────────────────────────────────
    if (!is_plugin_active("litespeed-cache/litespeed-cache.php")) {
        echo "STATUS:NOPLUGIN"; return;
    }

    // ── 2. อ่าน options ปัจจุบัน ─────────────────────────
    $cur_key   = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",   ""));
    $cur_email = trim((string) get_option("litespeed.conf.cdn-cloudflare_email", ""));
    $cur_zone  = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone",  ""));
    $cur_name  = trim((string) get_option("litespeed.conf.cdn-cloudflare_name",  ""));

    // ── 3. Auto-fix domain ให้ตรงกับ folder ──────────────
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

    // ── 4. เขียน Credentials ใหม่ลง DB ───────────────────
    $new_key   = '"'"'$CF_KEY'"'"';
    $new_email = '"'"'$CF_EMAIL'"'"';
    $is_apikey = ($new_email !== "");

    update_option("litespeed.conf.cdn-cloudflare_key",   $new_key);
    update_option("litespeed.conf.cdn-cloudflare_name",  $cur_name);
    update_option("litespeed.conf.cdn-cloudflare_zone",  "");

    if ($is_apikey) {
        update_option("litespeed.conf.cdn-cloudflare_email", $new_email);
    } else {
        update_option("litespeed.conf.cdn-cloudflare_email", "");
    }

    // ── 5. ดึง Zone ID จาก Cloudflare API ────────────────
    $max_retry   = '"'"'$MAX_RETRY'"'"';
    $retry_delay = '"'"'$RETRY_DELAY'"'"';
    $zone_id     = "";
    $zone_name   = "";
    $cf_error    = "";
    $attempt     = 0;

    $headers = $is_apikey
        ? ["X-Auth-Email: $new_email", "X-Auth-Key: $new_key", "Content-Type: application/json"]
        : ["Authorization: Bearer $new_key",                    "Content-Type: application/json"];

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

    // ── 6. บันทึก Zone ID ลง DB ──────────────────────────
    if ($zone_id) {
        update_option("litespeed.conf.cdn-cloudflare_zone", $zone_id);
        update_option("litespeed.conf.cdn-cloudflare_name", $zone_name);
    }

    // ── 7. Verify ─────────────────────────────────────────
    $v_key  = trim((string) get_option("litespeed.conf.cdn-cloudflare_key",  ""));
    $v_zone = trim((string) get_option("litespeed.conf.cdn-cloudflare_zone", ""));
    $key_ok = ($v_key === $new_key) ? 1 : 0;

    printf(
        "STATUS:DONE\tKEY_OK:%d\tDOMAIN:%s\tOLD_KEY:%s\tNEW_KEY:%s\tOLD_ZONE:%s\tNEW_ZONE:%s\tFIXED:%d\tATTEMPT:%d\tCF_ERROR:%s",
        $key_ok,
        $zone_name ?: $cur_name,
        substr($cur_key, 0, 8),
        substr($v_key,   0, 8),
        $cur_zone ? substr($cur_zone, 0, 12)."..." : "(empty)",
        $v_zone   ?: "(no zone)",
        $was_fixed ? 1 : 0,
        $attempt,
        $cf_error
    );
' --allow-root 2>/dev/null)

# ─── แสดงผลลัพธ์ ──────────────────────────────────────────────
STATUS=$(echo "$EVAL_OUT" | grep -oP '(?<=STATUS:)\w+')

case "$STATUS" in
    DONE)
        KEY_OK=$(   echo "$EVAL_OUT" | grep -oP '(?<=KEY_OK:)\d+')
        DOMAIN=$(   echo "$EVAL_OUT" | grep -oP '(?<=DOMAIN:)[^\t]*')
        OLD_KEY=$(  echo "$EVAL_OUT" | grep -oP '(?<=OLD_KEY:)[^\t]*')
        NEW_KEY=$(  echo "$EVAL_OUT" | grep -oP '(?<=NEW_KEY:)[^\t]*')
        OLD_ZONE=$( echo "$EVAL_OUT" | grep -oP '(?<=OLD_ZONE:)[^\t]*')
        NEW_ZONE=$( echo "$EVAL_OUT" | grep -oP '(?<=NEW_ZONE:)[^\t]*')
        FIXED=$(    echo "$EVAL_OUT" | grep -oP '(?<=FIXED:)\d+')
        ATTEMPT=$(  echo "$EVAL_OUT" | grep -oP '(?<=ATTEMPT:)\d+')
        CF_ERROR=$( echo "$EVAL_OUT" | grep -oP '(?<=CF_ERROR:)[^\t]*')
        FIX_TAG=""
        [[ "$FIXED" == "1" ]] && FIX_TAG=" | ⚙️ domain ถูกแก้อัตโนมัติ"

        if [[ "$KEY_OK" == "1" && "$NEW_ZONE" != "(no zone)" ]]; then
            log "✅ PASS | domain=$DOMAIN | key: ${OLD_KEY}... → ${NEW_KEY}... | zone: $OLD_ZONE → $NEW_ZONE | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
        elif [[ "$KEY_OK" == "1" && "$CF_ERROR" == "zone_empty" ]]; then
            log "🌐 NOTCF | domain=$DOMAIN | key อัปเดตแล้ว แต่ domain ไม่อยู่ใน CF account${FIX_TAG}"
        elif [[ "$KEY_OK" == "1" ]]; then
            log "❌ FAIL (CF API error) | domain=$DOMAIN | error=$CF_ERROR | attempt=${ATTEMPT}/${MAX_RETRY}${FIX_TAG}"
        else
            log "❌ FAIL (verify key ไม่ผ่าน) | domain=$DOMAIN${FIX_TAG}"
        fi
        ;;
    NOPLUGIN)
        log "⏭  SKIP | LiteSpeed Cache ไม่ active ที่ $TARGET_PATH"
        ;;
    *)
        log "❌ FAIL (wp error/timeout) | ${EVAL_OUT:0:200}"
        ;;
esac

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
log "======================================"
log " เวลาที่ใช้ : $(( ELAPSED / 60 )) นาที $(( ELAPSED % 60 )) วินาที"
log " Log        : $LOG_FILE"
log "======================================"

exit 0
