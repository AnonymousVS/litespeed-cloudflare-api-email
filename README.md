# LiteSpeed Cache — Cloudflare API Token Bulk Update

Bash script สำหรับอัปเดต **Cloudflare API Token** ให้กับ WordPress ทุกเว็บบนเซิร์ฟเวอร์ ผ่าน **LiteSpeed Cache Plugin → CDN → Cloudflare** รองรับหลาย Cloudflare Account (คนละ email คนละ token)





## คำสั่งรัน
```bash
https://drive.google.com/file/d/1nNZx0-evfkHVvaXNTgBdoB4gtI3_dUiw/view?usp=drive_link
```

```bash
GH_TOKEN="ghp_xxxxx"
curl -s -H "Authorization: token $GH_TOKEN" \
    https://raw.githubusercontent.com/AnonymousVS/config/main/Litespeed-Cloudflare-Api-Update.conf \
    -o /tmp/Litespeed-Cloudflare-Api-Update.conf && \
curl -s https://raw.githubusercontent.com/AnonymousVS/Litespeed-Cloudflare-Api-Update/main/server-config.conf \
    -o /tmp/server-config.conf && \
curl -s https://raw.githubusercontent.com/AnonymousVS/Litespeed-Cloudflare-Api-Update/main/domains.csv \
    -o /tmp/domains.csv && \
bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/Litespeed-Cloudflare-Api-Update/main/replace-token-email.sh)
```

> ต้องรันด้วย **root**

---

## ไฟล์ในโปรเจค

| ไฟล์ | ตำแหน่ง | คำอธิบาย |
|------|---------|----------|
| `replace-token-email.sh` | Public repo | Script หลัก |
| `server-config.conf` | Public repo | cPanel Users + Telegram + ตัวเลือก |
| `domains.csv` | Public repo | domain + CF email (ว่าง = ทุกเว็บ) |
| `Litespeed-Cloudflare-Api-Update.conf` | **Private repo** (`AnonymousVS/config`) | email → token mapping |

## Config

### domains.csv — ระบุ domain + Cloudflare Email

```csv
domain,cf_email
elon168.org,ufavisionseoteam16@gmail.com
kingdom988.com,ufavisionseoteam17@gmail.com
glm7899.net,ufavisionseoteam18@gmail.com
slot1bet.org,ufavisionseoteam16@gmail.com
```

- มี domain → แก้เฉพาะ domain ที่ระบุ
- cf_email → ใช้ map หา token จาก private config
- ว่าง / ไม่มีไฟล์ → แก้ทุกเว็บ + ใช้ default token

### Litespeed-Cloudflare-Api-Update.conf (Private)

แก้ไขที่นี่ ใน Repo Config
https://github.com/AnonymousVS/config/blob/main/Litespeed-Cloudflare-Api-Update.conf
**หลาย account (แนะนำ):**
```bash
declare -A CF_TOKENS

CF_TOKENS["ufavisionseoteam16@gmail.com"]="cfut_xxxxx_token_account1"
CF_TOKENS["ufavisionseoteam17@gmail.com"]="cfut_yyyyy_token_account2"
CF_TOKENS["ufavisionseoteam18@gmail.com"]="cfut_zzzzz_token_account3"
```

**token เดียว (ทุกเว็บ):**
```bash
CF_TOKEN="cfut_xxxxx"
```

**API Token Permission:** Zone-Zone-Read, Zone-Cache Purge-Purge, Zone-Bot Management-Edit

### server-config.conf (Public)

```bash
CPANEL_USERS="y2026m04ns504 jan2026newkey"

TELEGRAM_BOT_TOKEN="xxxx:xxxxxxx"
TELEGRAM_CHAT_ID="-xxxxxxxxxx"

CF_ONLY_ACTIVE="no"
CF_OVERWRITE_KEY="yes"
```

---

## ขั้นตอนการทำงาน

Script ทำงานต่อเว็บ ด้วย `wp litespeed-option set` + `bash curl`:

| Step | ทำอะไร | คำสั่ง |
|------|--------|--------|
| 1 | ตรวจ LiteSpeed Cache Plugin | `wp plugin is-active litespeed-cache` |
| 2 | อ่าน options ปัจจุบัน | `wp option get litespeed.conf.cdn-cloudflare_*` |
| 3 | เช็ค CF_ONLY_ACTIVE | bash `[[ ]]` |
| 4 | เช็ค CF_OVERWRITE_KEY | bash `[[ ]]` |
| 5 | Auto-fix domain จาก folder | bash `basename` |
| 6 | เขียน Credentials | `wp litespeed-option set cdn-cloudflare_key "$TOKEN"` |
| 7 | ดึง Zone ID | bash `curl -H "Authorization: Bearer $TOKEN"` |
| 8 | บันทึก Zone ID | `wp eval "update_option(...)"` |
| 9 | Verify ผลลัพธ์ | `wp option get litespeed.conf.cdn-cloudflare_*` |
| 10 | Log ผลลัพธ์ | pass / fail / skip / nochange |

## Features

- **litespeed-option set** — เขียน credentials ผ่าน LiteSpeed WP-CLI (ไม่มี quoting bug)
- **Multi-token** — แต่ละ CF account มี token ของตัวเอง (รันครั้งเดียวจบ)
- **WordPress API Token (cfut_)** เท่านั้น — ปลอดภัยกว่า Global Key
- **CF Token แยก private repo** — ไม่ถูก revoke
- **domains.csv** — ระบุ domain + email เฉพาะ
- **Backward compatible** — CF_TOKEN เดียวยังใช้ได้
- เปิด **Cloudflare API + CDN + Clear CF cache** อัตโนมัติ
- ดึง **Zone ID** + retry 3 ครั้ง
- **Telegram notification** สรุปผล
- **Spinner** แสดง progress
- รัน **parallel** สูงสุด 5 เว็บพร้อมกัน
- **Log แยกตามสถานะ** (pass/fail/skip/nochange)

## สถานะผลลัพธ์

| สถานะ | ความหมาย | Log File |
|-------|----------|----------|
| ✅ **PASS** | สำเร็จ (Zone ID แสดง) | `lscwp-cf-update-pass.log` |
| ⏩ **NOCHANGE** | มี key อยู่แล้ว ข้ามไป | `lscwp-cf-update-nochange.log` |
| ❌ **FAIL** | CF API error / verify ไม่ผ่าน | `lscwp-cf-update-fail.log` |
| ⏭ **SKIP** | Plugin ไม่ active / CF ปิด / ไม่มี token | `lscwp-cf-update-skip.log` |

**Log:** `/var/log/lscwp-cf-update*.log`

## Changelog

### v4 (2026-04-27) — ปัจจุบัน

- Rewrite: ใช้ `litespeed-option set` แทน `wp eval` (เหมือน website-daily-create.sh)
- Fix: bash variable quoting bug 6 จุด
- Fix: Telegram แสดง token ในจอ
- Multi-token: CF_TOKENS["email"]="cfut_token" (หลาย account)
- domains.csv: domain + cf_email mapping
- Per-domain token: ดึง Zone ID ด้วย token ที่ถูก account
- Backward compatible: CF_TOKEN เดียวยังใช้ได้

### v3 (2026-04-20)

- แยก config: server-config.conf (public) + CF Token (private)
- WordPress API Token (cfut_) เท่านั้น
- เพิ่ม CPANEL_USERS + Telegram + Spinner

## License

MIT
