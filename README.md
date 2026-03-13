# LiteSpeed Cache — Cloudflare API Bulk Update

Bash script สำหรับอัปเดต **Cloudflare API Key / Token / ** ให้กับ WordPress ทุกเว็บบนเซิร์ฟเวอร์ ผ่าน **LiteSpeed Cache Plugin → CDN → Cloudflare** โดยอ่านค่าจากไฟล์ CSV

## Features

- อ่าน config จาก **2 ไฟล์ CSV** บน GitHub — แต่ละโดเมนมี  + API Token ของตัวเอง
- ประมวลผล **เฉพาะโดเมนที่ระบุ** ใน CSV เท่านั้น
- เปิด **Cloudflare API = ON** อัตโนมัติ
- ใส่ **API Token + ** ให้แต่ละเว็บ
- เปิด **Clear Cloudflare cache on purge all = ON**
- กด **Save** = ดึง **Zone ID** จาก Cloudflare API อัตโนมัติ (retry 3 ครั้ง)
- ตรวจสอบผลลัพธ์ + เก็บ **Log แยกตามสถานะ**
- รันซ้ำได้ปลอดภัย (idempotent)
- รองรับ **cPanel / WHM** (trueuserdomains, userdatadomains)
- รัน parallel สูงสุด 5 เว็บพร้อมกัน พร้อม rate limit delay

## ไฟล์ในโปรเจค

| ไฟล์ | คำอธิบาย |
|------|----------|
| `replace-token-.sh` | Script หลัก |
| `config-domain.csv` | รายชื่อ Domain + Cloudflare  |
| `config-api-key-token.csv` | Cloudflare  + API Token |

## วิธีใช้งาน

### 1. แก้ไขไฟล์ CSV

**config-domain.csv** — ใส่โดเมนที่ต้องการอัปเดต:

```csv
Domain,Cloudflare 
supreme8888.com,seoteam16@gmail.com
ktv4s.org,seoteam17@gmail.com
m4asia.net,seoteam18@gmail.com
```

**config-api-key-token.csv** — ใส่ API Token ของแต่ละอีเมล:

```csv
Cloudflare ,API Token
seoteam17@gmail.com,6a0a1968e2b8ca54954a435f4d7f441a1fd2f
seoteam18@gmail.com,3648ec5f900116438e47c4282edd62251e2c3
```

> **หมายเหตุ:** โดเมนที่มี  แต่ไม่มี Token จะถูก skip อัตโนมัติ

### 2. รัน Script

**รันจาก GitHub โดยตรง (แนะนำ):**

```bash
bash <(curl -s "https://raw.githubusercontent.com/AnonymousVS/litespeed-cloudflare-api-/main/replace-token-.sh?t=$(date +%s)")
```

> ต้องรันด้วย **root** เพราะใช้ `wp-cli --allow-root`

### 3. ตรวจสอบผลลัพธ์

Script จะแสดงรายละเอียดก่อนรัน และขอ confirm ก่อนเริ่ม:

```
╔══════════════════════════════════════════════════════════════
║   🔄  replace-token-.sh  v2
║   CSV-based — แต่ละโดเมนมี  + Token ของตัวเอง
╠══════════════════════════════════════════════════════════════
║
║   จำนวนโดเมน              : 5
║   มี Token พร้อม          : 2
║   ขาด Token               : 3
║
║   Domain                                              Token
║   supreme8888.com           seoteam16@gmail.com            ❌ ไม่มี
║   ktv4s.org                 seoteam17@gmail.com            6a0a1968...1fd2f
║   m4asia.net                seoteam18@gmail.com            3648ec5f...e2c3
║
╚══════════════════════════════════════════════════════════════

  ▶  ยืนยันการเปลี่ยนค่า? [y/N] :
```

## ขั้นตอนการทำงาน

Script จะทำงาน 10 ขั้นตอนต่อเว็บ:

| Step | ทำอะไร | LiteSpeed Option |
|------|--------|-----------------|
| 1 | ตรวจ Plugin active | — |
| 2 | อ่าน options ปัจจุบัน | — |
| 3 | ค่าใหม่จาก CSV | — |
| 4 | เปิด Cloudflare API = ON | `litespeed.conf.cdn-cloudflare` |
| 5 | ใส่ API Token +  + Domain | `cdn-cloudflare_key` / `_` / `_name` |
| 6 | เปิด CDN = ON | `litespeed.conf.cdn` |
| 7 | เปิด Clear CF cache on purge all | `litespeed.conf.cdn-cloudflare_clear` |
| 8 | ดึง Zone ID จาก CF API (= Save) | Cloudflare API v4 |
| 9 | บันทึก Zone ID ลง DB | `cdn-cloudflare_zone` / `_name` |
| 10 | Verify ทุกค่า | ตรวจ key +  + zone + cf_on |

## สถานะผลลัพธ์

| สถานะ | ความหมาย | Log File |
|-------|----------|----------|
| ✅ **PASS** | Zone ID แสดง = สำเร็จทั้งหมด | `lscwp-cf-update-pass.log` |
| ⚠️ **WARN** | Key+ ใส่แล้ว แต่ Zone ID ยังไม่แสดง | `lscwp-cf-update-warn.log` |
| ❌ **FAIL** | Verify key/ ไม่ผ่าน หรือ wp eval ล้มเหลว | `lscwp-cf-update-fail.log` |
| ⏭ **SKIP** | ไม่มี API Token / LiteSpeed Cache ไม่ active | `lscwp-cf-update-skip.log` |
| 🔍 **NOT FOUND** | ไม่พบ WordPress directory บนเซิร์ฟเวอร์ | `lscwp-cf-update-notfound.log` |

**Log files ทั้งหมดอยู่ที่:** `/var/log/lscwp-cf-update*.log`

```bash
# ดู log รวม
cat /var/log/lscwp-cf-update.log

# ดูเฉพาะที่สำเร็จ
cat /var/log/lscwp-cf-update-pass.log

# ดูเฉพาะ Zone ID ไม่แสดง
cat /var/log/lscwp-cf-update-warn.log

# ดูเฉพาะที่ล้มเหลว
cat /var/log/lscwp-cf-update-fail.log
```

## การป้องกัน Edge Cases

| ป้องกัน | วิธีจัดการ |
|---------|----------|
| CSV ค้างจาก run เก่า | ดาวน์โหลดจาก GitHub ใหม่ทุกครั้ง + cache-busting |
| GitHub CDN cache | ต่อ `?t=timestamp` ท้าย URL อัตโนมัติ |
|  ตัวพิมพ์ใหญ่/เล็กไม่ตรง | Lowercase ทั้ง  + domain ก่อน compare |
| Domain ซ้ำใน CSV | แจ้งเตือน + ใช้ค่าจากแถวสุดท้าย |
| Token มีอักขระพิเศษ | Validate + skip ถ้ามี `' " \ $ ; \|` |
| Cloudflare API rate limit | หน่วง 1 วินาทีระหว่างเว็บ |
| WP scan ช้า (4,000+ เว็บ) | แสดง progress ระหว่าง scan |
| CF API timeout | Retry 3 ครั้ง (delay 5 วินาที) |

## ค่า Runtime (ปรับได้ใน script)

| ตัวแปร | ค่า default | คำอธิบาย |
|--------|------------|----------|
| `MAX_JOBS` | 5 | จำนวนเว็บที่รัน parallel พร้อมกัน |
| `WP_TIMEOUT` | 30 | Timeout ต่อเว็บ (วินาที) |
| `MAX_RETRY` | 3 | จำนวนครั้ง retry CF API |
| `RETRY_DELAY` | 5 | หน่วงระหว่าง retry (วินาที) |
| `CF_API_DELAY` | 1 | หน่วงระหว่างเว็บ ป้องกัน rate limit (วินาที) |

## Requirements

- **Root access** — ต้องรันด้วย root
- **WP-CLI** — ต้องติดตั้ง ([wp-cli.org](https://wp-cli.org))
- **cPanel / WHM** — รองรับ trueuserdomains, userdatadomains
- **LiteSpeed Cache Plugin v7.0+** — ติดตั้งและ activate บนเว็บที่ต้องการ
- **curl** — สำหรับดาวน์โหลด CSV และเรียก CF API

## Changelog

### v2 (ปัจจุบัน)
- อ่าน config จาก 2 ไฟล์ CSV (แต่ละโดเมนมี token ของตัวเอง)
- ประมวลผลเฉพาะโดเมนใน CSV
- เปิด CF API + CDN + Clear CF cache อัตโนมัติ
- เพิ่ม Zone ID verification
- เพิ่ม WARN สำหรับ Zone ID ไม่แสดง
- ดาวน์โหลด CSV ใหม่ทุกครั้ง + cache-busting
-  lowercase ก่อน compare
- ตรวจจับ domain ซ้ำใน CSV
- Validate token special characters
- แสดง progress ตอน scan WordPress
- Rate limit delay ระหว่างเว็บ

### v1
- อ่าน config จาก `.conf` ไฟล์เดียว
- ใส่ Key +  เดียวกันให้ทุกเว็บบนเซิร์ฟเวอร์

## License

MIT
