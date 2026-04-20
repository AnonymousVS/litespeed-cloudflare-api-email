# LiteSpeed Cache — Cloudflare API Token Bulk Update

Bash script สำหรับอัปเดต **Cloudflare API Token** ให้กับ WordPress ทุกเว็บบนเซิร์ฟเวอร์ ผ่าน **LiteSpeed Cache Plugin → CDN → Cloudflare**

## คำสั่งรัน

### วิธี 1: ดึง config จาก private repo (แนะนำ)

```bash
GH_TOKEN="ghp_xxxxx"
curl -s -H "Authorization: token $GH_TOKEN" \
    https://raw.githubusercontent.com/AnonymousVS/config/main/Cf-Token-Litespeed-Cloudflare-Api-Update.conf \
    -o /tmp/Cf-Token-Litespeed-Cloudflare-Api-Update.conf && \
curl -s https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/server-config.conf \
    -o /tmp/server-config.conf && \
bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/replace-token-email.sh)
```

## ไฟล์ในโปรเจค

| ไฟล์ | ตำแหน่ง | คำอธิบาย |
|------|---------|----------|
| `replace-token-email.sh` | Public repo | Script หลัก |
| `server-config.conf` | Public repo | cPanel Users + Telegram + ตัวเลือก |
| `Cf-Token-Litespeed-Cloudflare-Api-Update.conf` | **Private repo** (`AnonymousVS/config`) | Cloudflare API Token (cfut_) |

## Config

### server-config.conf (Public)

```bash
# ระบุ cPanel user (คั่นด้วย space) — ว่าง = scan ทั้ง server
CPANEL_USERS="y2026m04ns504 jan2026newkey"

# Cloudflare Email (สำหรับ LiteSpeed display — ไม่ใช้สำหรับ auth)
CF_EMAIL=""

# Telegram Notification
TELEGRAM_BOT_TOKEN="xxxx:xxxxxxx"
TELEGRAM_CHAT_ID="-xxxxxxxxxx"

# ตัวเลือก
CF_ONLY_ACTIVE="no"      # no = อัปเดตทุกเว็บ / yes = เฉพาะเว็บที่เปิด CF อยู่
CF_OVERWRITE_KEY="yes"    # yes = เขียนทับ key เดิม / no = ข้ามเว็บที่มี key แล้ว
```

### Cf-Token-Litespeed-Cloudflare-Api-Update.conf (Private)

```bash
# WordPress API Token เท่านั้น (cfut_) — ห้ามใช้ Global Key
CF_TOKEN="cfut_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

**API Token Permission:**
- Zone — Zone — Read
- Zone — Cache Purge — Purge
- Zone — Bot Management — Edit

---

## Features

- ใช้ **WordPress API Token (cfut_)** เท่านั้น — ปลอดภัยกว่า Global Key
- **CF Token แยก private repo** — ไม่ถูก revoke โดย GitHub/Cloudflare scanner
- **Auto-detect cfut_ prefix** → Bearer auth + email ว่างอัตโนมัติ
- **CPANEL_USERS** — ระบุ user เฉพาะ หรือ scan ทั้ง server
- เปิด **Cloudflare API + CDN + Clear CF cache** อัตโนมัติ
- ดึง **Zone ID** จาก Cloudflare API + retry 3 ครั้ง
- **Telegram notification** สรุปผลหลังรันเสร็จ
- รันซ้ำได้ปลอดภัย (idempotent)
- รัน **parallel** สูงสุด 5 เว็บพร้อมกัน
- ตรวจสอบผลลัพธ์ + เก็บ **Log แยกตามสถานะ**
- Config ค้นหาอัตโนมัติ: `/tmp/` → `/usr/local/etc/litespeed-cloudflare/` → `/root/` → ถาม PAT

## ขั้นตอนการทำงาน

Script ทำงานต่อเว็บ:

| Step | ทำอะไร |
|------|--------|
| 1 | ตรวจ LiteSpeed Cache Plugin active |
| 2 | อ่าน options ปัจจุบัน |
| 3 | เช็ค CF_ONLY_ACTIVE / CF_OVERWRITE_KEY |
| 4 | Auto-fix domain name จาก folder name |
| 5 | เปิด CF API + CDN + Clear CF cache = ON |
| 6 | ใส่ API Token + email ว่าง |
| 7 | ดึง Zone ID จาก CF API (retry 3 ครั้ง) |
| 8 | บันทึก Zone ID ลง DB |
| 9 | Verify ทุกค่า |

## สถานะผลลัพธ์

| สถานะ | ความหมาย | Log File |
|-------|----------|----------|
| ✅ **PASS** | Zone ID แสดง = สำเร็จ | `lscwp-cf-update-pass.log` |
| ⏩ **NOCHANGE** | มี key อยู่แล้ว ข้ามไป | `lscwp-cf-update-nochange.log` |
| ❌ **FAIL** | CF API error / verify ไม่ผ่าน | `lscwp-cf-update-fail.log` |
| ⏭ **SKIP** | Plugin ไม่ active / CF ปิดอยู่ | `lscwp-cf-update-skip.log` |
| ⚙️ **AUTO-FIXED** | Domain name ถูกแก้จาก folder name | `lscwp-cf-update-mismatch.log` |

**Log files:** `/var/log/lscwp-cf-update*.log`

```bash
cat /var/log/lscwp-cf-update.log        # ดู log รวม
cat /var/log/lscwp-cf-update-pass.log   # เฉพาะที่สำเร็จ
cat /var/log/lscwp-cf-update-fail.log   # เฉพาะที่ล้มเหลว
```

## ค่า Runtime

| ตัวแปร | ค่า default | คำอธิบาย |
|--------|-------------|----------|
| `MAX_JOBS` | 5 | จำนวนเว็บที่รัน parallel พร้อมกัน |
| `WP_TIMEOUT` | 30 | Timeout ต่อเว็บ (วินาที) |
| `MAX_RETRY` | 3 | จำนวนครั้ง retry CF API |
| `RETRY_DELAY` | 5 | หน่วงระหว่าง retry (วินาที) |

## Requirements

- **Root access**
- **WP-CLI** — [wp-cli.org](https://wp-cli.org)
- **cPanel / WHM**
- **LiteSpeed Cache Plugin**
- **curl**

## Changelog

### v3 (2026-04-20) — ปัจจุบัน

- แยก config 2 ไฟล์: `server-config.conf` (public) + CF Token (private)
- WordPress API Token (`cfut_`) เท่านั้น — ห้ามใช้ Global Key
- LiteSpeed CDN email ว่างอัตโนมัติ
- Cloudflare API: `Authorization: Bearer` เท่านั้น
- เพิ่ม `CPANEL_USERS` (ระบุ user เฉพาะ หรือ scan ทั้ง server)
- เพิ่ม Telegram notification สรุปผล
- Config ค้นหาอัตโนมัติ

### v2

- อ่าน config จาก 2 ไฟล์ CSV (`config-domain.csv` + `config-api-key-token.csv`)
- แต่ละโดเมนมี Email + Token ของตัวเอง
- Zone ID verification + retry

### v1

- อ่าน config จาก `.conf` ไฟล์เดียว
- ใส่ Key + Email เดียวกันให้ทุกเว็บบนเซิร์ฟเวอร์

## License

MIT
