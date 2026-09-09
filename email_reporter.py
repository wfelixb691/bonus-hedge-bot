"""
Email Live Reporter for Dual-MT5 Bonus Hedging Bot.
Reads binary telemetry from MT5 FILE_COMMON and sends periodic rich HTML email summaries
to your email address (every 12 hours or configurable interval).
"""

import os
import sys
import json
import time
import struct
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime

# Safe DLL directory injection for Windows
py_dir = os.path.dirname(sys.executable)
for p in [py_dir, os.path.join(py_dir, "DLLs"), os.path.join(py_dir, "Library", "bin")]:
    if os.path.isdir(p):
        os.environ["PATH"] = p + os.pathsep + os.environ.get("PATH", "")
        if hasattr(os, "add_dll_directory"):
            try:
                os.add_dll_directory(p)
            except Exception:
                pass

SSL_AVAILABLE = False
try:
    import ssl
    SSL_AVAILABLE = True
except Exception:
    SSL_AVAILABLE = False

CONFIG_FILE = "email_config.json"


def find_common_files_dir() -> str:
    """Finds the MT5 Terminal Common Files directory on Windows or local fallback."""
    appdata = os.environ.get("APPDATA", "")
    if appdata:
        common_path = os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files")
        if os.path.isdir(common_path):
            return common_path

    userprofile = os.environ.get("USERPROFILE", "")
    if userprofile:
        cand = os.path.join(userprofile, "AppData", "Roaming", "MetaQuotes", "Terminal", "Common", "Files")
        if os.path.isdir(cand):
            return cand

    return "."


COMMON_DIR = find_common_files_dir()


def load_config() -> dict:
    if not os.path.isfile(CONFIG_FILE):
        default_cfg = {
            "smtp_server": "smtp.gmail.com",
            "smtp_port": 465,
            "use_ssl": True,
            "sender_email": "YOUR_EMAIL@gmail.com",
            "sender_password": "YOUR_GMAIL_APP_PASSWORD",
            "recipient_email": "YOUR_EMAIL@gmail.com",
            "report_interval_hours": 12,
            "send_immediate_on_tp": True,
            "immediate_tp_threshold": 30.0
        }
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(default_cfg, f, indent=2)
        return default_cfg

    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def read_telemetry_file(filename: str) -> dict:
    filepath = os.path.join(COMMON_DIR, filename)
    if not os.path.isfile(filepath):
        return {"online": False, "count": 0, "positions": []}

    try:
        with open(filepath, "rb") as f:
            data = f.read()

        if len(data) < 52:
            return {"online": False, "count": 0, "positions": []}

        offset = 0
        # Check header magic (v2 has 0x42484246, version, counter)
        magic_peek, = struct.unpack_from("<q", data, 0)
        if magic_peek == 0x42484246:
            magic, version, counter, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqqqdddddi", data, offset
            )
            offset += struct.calcsize("<qqqqdddddi")
            t_stamp = time.time()
        else:
            t_stamp, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqdddddi", data, offset
            )
            offset += struct.calcsize("<qqdddddi")

        positions = []
        for _ in range(count):
            if offset + 40 > len(data):
                break
            ticket, p_type, vol, price_open, profit, clen = struct.unpack_from("<qidddi", data, offset)
            offset += struct.calcsize("<qidddi")
            comment = ""
            if clen > 0:
                if offset + clen * 2 <= len(data):
                    try:
                        comment = data[offset:offset+clen*2].decode("utf-16le")
                        offset += clen * 2
                    except Exception:
                        comment = data[offset:offset+clen].decode("utf-8", errors="ignore")
                        offset += clen
                elif offset + clen <= len(data):
                    comment = data[offset:offset+clen].decode("utf-8", errors="ignore")
                    offset += clen

            positions.append({
                "ticket": ticket,
                "type": "BUY" if p_type == 0 else "SELL",
                "volume": round(vol, 2),
                "price_open": round(price_open, 2),
                "profit": round(profit, 2),
                "comment": comment
            })

        return {
            "online": True,
            "login": login,
            "equity": round(equity, 2),
            "balance": round(balance, 2),
            "free_margin": round(free_margin, 2),
            "margin_level": round(margin_level, 2),
            "profit": round(total_prof, 2),
            "count": count,
            "positions": positions
        }
    except Exception as e:
        return {"online": False, "count": 0, "positions": [], "error": str(e)}


def build_email_content(m: dict, s: dict) -> tuple:
    """Returns (plain_text, html_text, subject)"""
    now_str = datetime.now().strftime("%d %b %Y, %H:%M:%S")
    net_fl = round(m.get("profit", 0.0) + s.get("profit", 0.0), 2)
    m_eq = m.get("equity", 0.0)
    m_bal = m.get("balance", 0.0)
    s_eq = s.get("equity", 0.0)
    s_bal = s.get("balance", 0.0)
    s_credit = max(0.0, round(s_eq - s_bal, 2))

    sign = "+$" if net_fl >= 0 else "-$"
    color = "#10b981" if net_fl >= 0 else "#ef4444"

    subject = f"📊 [REKAP 12 JAM] Dual-MT5 Bonus Hedging Bot (Net: {sign}{abs(net_fl):.2f})"

    # Plain text version
    plain = f"""====================================================
 ⚡ DUAL-MT5 BONUS HEDGING - LAPORAN 12 JAM
 Tanggal/Waktu: {now_str}
====================================================

👑 AKUN MASTER ({m.get('login', 100870)}):
   • Balance / Equity : ${m_bal:,.2f} / ${m_eq:,.2f}
   • Free Margin      : ${m.get('free_margin', 0.0):,.2f} ({m.get('margin_level', 0.0):.1f}%)
   • Floating Profit  : ${m.get('profit', 0.0):,.2f} ({m.get('count', 0)} Layers)

🛡️ AKUN SLAVE ({s.get('login', 100871)} - Bonus 20%):
   • Balance / Equity : ${s_bal:,.2f} / ${s_eq:,.2f}
   • Credit Bonus     : ${s_credit:,.2f}
   • Free Margin      : ${s.get('free_margin', 0.0):,.2f} ({s.get('margin_level', 0.0):.1f}%)
   • Floating Profit  : ${s.get('profit', 0.0):,.2f} ({s.get('count', 0)} Hedges)

----------------------------------------------------
🎯 NET FLOATING GABUNGAN : {sign}{abs(net_fl):.2f}
----------------------------------------------------
Laporan ini dikirim otomatis setiap 12 jam oleh bot trading Anda.
"""

    # Rich HTML version
    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  body {{ font-family: 'Segoe UI', Helvetica, Arial, sans-serif; background-color: #0f172a; color: #f8fafc; margin: 0; padding: 20px; }}
  .card {{ max-width: 600px; margin: 0 auto; background-color: #1e293b; border-radius: 12px; border: 1px solid #334155; overflow: hidden; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }}
  .header {{ background: linear-gradient(135deg, #1e3a8a, #0f172a); padding: 24px; text-align: center; border-bottom: 1px solid #334155; }}
  .header h2 {{ margin: 0 0 8px 0; color: #38bdf8; font-size: 20px; }}
  .header p {{ margin: 0; color: #94a3b8; font-size: 13px; }}
  .content {{ padding: 24px; }}
  .grid {{ display: table; width: 100%; margin-bottom: 20px; }}
  .col {{ display: table-cell; width: 50%; padding: 12px; vertical-align: top; background-color: #0f172a; border-radius: 8px; border: 1px solid #1e293b; }}
  .col-title {{ font-weight: bold; font-size: 14px; margin-bottom: 10px; padding-bottom: 6px; border-bottom: 1px solid #334155; }}
  .master-title {{ color: #fbbf24; }}
  .slave-title {{ color: #a855f7; }}
  .stat {{ font-size: 12px; color: #94a3b8; margin: 6px 0; }}
  .stat strong {{ color: #f8fafc; font-size: 13px; }}
  .banner {{ background-color: #0f172a; border: 1px solid {color}; border-radius: 8px; padding: 16px; text-align: center; margin-top: 15px; }}
  .banner-label {{ font-size: 12px; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; }}
  .banner-val {{ font-size: 26px; font-weight: bold; color: {color}; margin-top: 4px; }}
  .footer {{ padding: 16px; text-align: center; font-size: 11px; color: #64748b; border-top: 1px solid #334155; }}
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <h2>⚡ DUAL-MT5 BONUS HEDGING</h2>
    <p>Laporan Periodik 12 Jam &bull; {now_str}</p>
  </div>
  <div class="content">
    <div class="grid">
      <div class="col" style="margin-right: 8px;">
        <div class="col-title master-title">👑 MASTER ({m.get('login', 100870)})</div>
        <div class="stat">Balance: <strong>${m_bal:,.2f}</strong></div>
        <div class="stat">Equity: <strong>${m_eq:,.2f}</strong></div>
        <div class="stat">Free Margin: <strong>${m.get('free_margin', 0.0):,.2f}</strong></div>
        <div class="stat">Margin Level: <strong>{m.get('margin_level', 0.0):.1f}%</strong></div>
        <div class="stat">Layers: <strong>{m.get('count', 0)} Posisi</strong></div>
        <div class="stat">Floating: <strong style="color: {'#10b981' if m.get('profit', 0) >= 0 else '#ef4444'}">${m.get('profit', 0.0):,.2f}</strong></div>
      </div>
      <div class="col">
        <div class="col-title slave-title">🛡️ SLAVE ({s.get('login', 100871)})</div>
        <div class="stat">Balance: <strong>${s_bal:,.2f}</strong></div>
        <div class="stat">Equity: <strong>${s_eq:,.2f}</strong></div>
        <div class="stat">Bonus Credit: <strong>${s_credit:,.2f}</strong></div>
        <div class="stat">Margin Level: <strong>{s.get('margin_level', 0.0):.1f}%</strong></div>
        <div class="stat">Hedges: <strong>{s.get('count', 0)} Posisi</strong></div>
        <div class="stat">Floating: <strong style="color: {'#10b981' if s.get('profit', 0) >= 0 else '#ef4444'}">${s.get('profit', 0.0):,.2f}</strong></div>
      </div>
    </div>

    <div class="banner">
      <div class="banner-label">NET COMBINED FLOATING (MASTER + SLAVE)</div>
      <div class="banner-val">{sign}{abs(net_fl):,.2f}</div>
    </div>
  </div>
  <div class="footer">
    Dikirim otomatis oleh Email Live Reporter &bull; Dual-MT5 Bonus Hedging System
  </div>
</div>
</body>
</html>"""

    return plain, html, subject


def send_email(cfg: dict, plain: str, html: str, subject: str) -> bool:
    sender = cfg.get("sender_email", "")
    password = cfg.get("sender_password", "")
    recipient = cfg.get("recipient_email", "")
    smtp_server = cfg.get("smtp_server", "smtp.gmail.com")
    smtp_port = int(cfg.get("smtp_port", 465))
    use_ssl = bool(cfg.get("use_ssl", True))

    if not sender or not password or "YOUR_" in sender or "YOUR_" in password:
        print("⚠️ [Email Reporter] Konfigurasi email belum lengkap di email_config.json")
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"Bonus Hedging Bot <{sender}>"
    msg["To"] = recipient

    msg.attach(MIMEText(plain, "plain"))
    msg.attach(MIMEText(html, "html"))

    try:
        if use_ssl:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(smtp_server, smtp_port, context=context, timeout=15) as server:
                server.login(sender, password)
                server.sendmail(sender, recipient, msg.as_string())
        else:
            with smtplib.SMTP(smtp_server, smtp_port, timeout=15) as server:
                server.starttls()
                server.login(sender, password)
                server.sendmail(sender, recipient, msg.as_string())

        print(f"[{datetime.now().strftime('%H:%M:%S')}] ✅ Email rekap 12 jam berhasil dikirim ke {recipient}")
        return True
    except Exception as e:
        print(f"❌ [Email Error] Gagal mengirim email: {e}")
        return False


def main():
    cfg = load_config()
    interval_sec = int(cfg.get("report_interval_hours", 12)) * 3600

    print("=" * 60)
    print(" 📧 EMAIL LIVE REPORTER AKTIF (12-HOUR CYCLE)")
    print(f" 👉 Shared Folder MT5 : {COMMON_DIR}")
    print(f" 👉 Jadwal Laporan    : Setiap {cfg.get('report_interval_hours', 12)} jam")
    print(f" 👉 Penerima Email    : {cfg.get('recipient_email')}")
    print("=" * 60)

    last_send_time = 0

    while True:
        try:
            now = time.time()
            if now - last_send_time >= interval_sec:
                m_data = read_telemetry_file("bonus_hedge_master.dat")
                s_data = read_telemetry_file("bonus_hedge_slave.dat")

                plain, html, subject = build_email_content(m_data, s_data)
                if send_email(cfg, plain, html, subject):
                    last_send_time = now

        except Exception as e:
            print(f"Error in main loop: {e}")

        time.sleep(10)


if __name__ == "__main__":
    main()
