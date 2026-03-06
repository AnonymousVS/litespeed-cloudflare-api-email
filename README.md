# litespeed-cloudflare-api-email

Bulk replace **Cloudflare API Token / Global API Key / Email** ใน LiteSpeed Cache Plugin ทุกเว็บบนเซิร์ฟเวอร์ (cPanel / WHM) พร้อมกัน

---

## ปัญหาที่แก้

เมื่อต้องการเปลี่ยน Cloudflare API Token หรือ Email ในเซิร์ฟเวอร์ที่มีหลาย WordPress พร้อมกัน การแก้ทีละเว็บในหน้า LiteSpeed Cache › CDN › Cloudflare เสียเวลามาก — Script นี้ทำในครั้งเดียว แบบ parallel ผ่าน WP-CLI

---

## ไฟล์ในโปรเจกต์

```
litespeed-cloudflare-api-email/
├── replace-token-email.sh      ← script หลัก
└── replace-token-email.conf    ← config (แก้ที่นี่ที่เดียว)
```

---

## วิธีใช้งาน

### วิธีที่ 1 — One-liner (ดาวน์โหลด + รันทันที)

> ⚠️ ต้องมี `replace-token-email.conf` อยู่ใน directory ปัจจุบันก่อน

```bash
bash <(curl -s https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-email/main/replace-token-email.sh)
```

---

### วิธีที่ 2 — Clone แล้วแก้ config

```bash
# 1. Clone repo
git clone https://github.com/AnonymousVS/litespeed-cloudflare-api-email.git
cd litespeed-cloudflare-api-email

# 2. แก้ config
nano replace-token-email.conf

# 3. รัน
bash replace-token-email.sh
```

---

### วิธีที่ 3 — ระบุ config path เอง

```bash
bash replace-token-email.sh /path/to/my-custom.conf
```

---

## ตั้งค่าใน `replace-token-email.conf`

```bash
# โหมด Auth
CF_AUTH_MODE="token"      # "token" หรือ "apikey"

# Credentials ใหม่
CF_KEY="YOUR_API_TOKEN_OR_GLOBAL_KEY_HERE"
CF_EMAIL=""               # ใส่เฉพาะตอน CF_AUTH_MODE=apikey

# ตัวเลือกเพิ่มเติม
CF_CLEAR_ZONE="yes"       # ล้าง zone_id หลังเปลี่ยน key (แนะนำ yes)
CF_ONLY_ACTIVE="no"       # yes = อัปเดตเฉพาะเว็บที่เปิด CF ไว้
CF_OVERWRITE_KEY="yes"    # no  = ข้ามเว็บที่มี key อยู่แล้ว
```

### `CF_AUTH_MODE`

| ค่า | ใช้เมื่อ | ต้องใส่ |
|---|---|---|
| `token` | ใช้ Cloudflare API Token | `CF_KEY` เท่านั้น |
| `apikey` | ใช้ Global API Key แบบเดิม | `CF_KEY` + `CF_EMAIL` |

---

## สิ่งที่ Script ทำ (ทีละขั้น)

1. **ค้นหา WordPress** ทุกเว็บบนเซิร์ฟเวอร์ จาก `/etc/trueuserdomains` (WHM) และ `/home*`
2. **ตรวจ LiteSpeed Cache** ว่า active อยู่ไหม — ถ้าไม่ → ข้าม
3. **ตรวจเงื่อนไข** ตาม `CF_ONLY_ACTIVE` และ `CF_OVERWRITE_KEY`
4. **เขียน credentials ใหม่** ลง WordPress DB โดยตรงผ่าน `update_option()`
5. **ล้าง zone_id** (ถ้า `CF_CLEAR_ZONE=yes`) เพื่อให้ดึง zone ใหม่จาก key ใหม่
6. **Verify** อ่านกลับมาตรวจว่าบันทึกจริง
7. **รัน parallel** สูงสุด 5 เว็บพร้อมกัน

---

## Status ที่จะเจอใน Log

| สัญลักษณ์ | ความหมาย |
|---|---|
| ✅ `PASS` | อัปเดตสำเร็จ + verify ผ่าน |
| ⏩ `NOCHANGE` | มี key อยู่แล้ว ข้ามตาม `CF_OVERWRITE_KEY=no` |
| 🔴 `SKIP_CFOFF` | Cloudflare ปิดอยู่ใน plugin ข้ามตาม `CF_ONLY_ACTIVE=yes` |
| ⏭ `SKIP` | LiteSpeed Cache ไม่ active |
| ❌ `FAIL` | wp eval ล้มเหลว หรือ verify ไม่ผ่าน |

---

## Log Files

| ไฟล์ | เนื้อหา |
|---|---|
| `/var/log/lscwp-cf-update.log` | Log รวมทั้งหมด |
| `/var/log/lscwp-cf-update-pass.log` | เว็บที่อัปเดตสำเร็จ |
| `/var/log/lscwp-cf-update-fail.log` | เว็บที่ล้มเหลว |
| `/var/log/lscwp-cf-update-nochange.log` | เว็บที่ข้าม (มี key แล้ว) |
| `/var/log/lscwp-cf-update-skip.log` | เว็บที่ข้าม (plugin ไม่ active / CF ปิด) |

> Log ทุกไฟล์จะถูก **ล้างทุกครั้งที่รัน** เก็บเฉพาะผลของ run ล่าสุด

---

## ความต้องการของระบบ

- Linux server (cPanel / WHM หรือ VPS ทั่วไป)
- [WP-CLI](https://wp-cli.org) ติดตั้งและเรียกใช้ได้จาก `wp`
- WordPress + LiteSpeed Cache Plugin (active)
- รันในฐานะ `root` หรือผู้ใช้ที่มีสิทธิ์อ่าน home directory ทุก user

---

## ตัวอย่าง Output

```
======================================
 BULK UPDATE CF CREDENTIALS (LiteSpeed)
 เริ่มเวลา    : 2025-03-06 10:00:00
 Auth Mode    : token
 Key (prefix) : abcd1234...
 Clear Zone   : yes
======================================
พบ WordPress  : 47 เว็บ
======================================
✅ PASS: [1/47] user1/public_html/site1.com | domain=site1.com | key: oldkey1... → abcd1234... | zone: abc123... → (cleared)
✅ PASS: [2/47] user2/public_html/site2.com | domain=site2.com | key: oldkey2... → abcd1234...
⏭  SKIP (LiteSpeed Cache ไม่ active): [3/47] user3/public_html/newsite.com
...
======================================
 สรุปผลรวม
 รวมทั้งหมด      : 47 เว็บ
 ✅ Pass (อัปเดต) : 43 เว็บ
 ⏩ Nochange       : 0  เว็บ
 ❌ Fail          : 1  เว็บ
 ⏭  Skip          : 3  เว็บ
 เวลาที่ใช้       : 2 นาที 18 วินาที
======================================
```
---
MIT
