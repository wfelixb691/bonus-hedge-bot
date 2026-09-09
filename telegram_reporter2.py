"""
Smart Telegram Live Reporter for Dual-MT5 Bonus Hedging Bot.
Features:
1. Instant Alert on NEW LAYER OPEN with Period & All-Time Cumulative Stats
2. Instant Alert on BASKET TP HIT with 30% Profit Sharing Breakdown & Date Range Tracking
3. Periodic Status Summary (Default: Every 1 Hour or configurable in telegram_config.json)
4. Persistent Multi-Period Accounting Ledger (profit_ledger.json) with Settlement Support.
"""

import os
import sys
import json
import time
import struct
import subprocess
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

# Graceful SSL import
SSL_AVAILABLE = False
try:
    import ssl
    import urllib.request
    import urllib.parse
    SSL_AVAILABLE = True
except Exception:
    SSL_AVAILABLE = False

CONFIG_FILE = "telegram_config_pair2.json"
LEDGER_FILE = "profit_ledger_pair2.json"
MASTER_FILE = "bonus_hedge_master_2.dat"
SLAVE_FILE = "bonus_hedge_slave_2.dat"


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
    default_cfg = {
        "telegram_bot_token": "8712779586:AAG65JUC9MgBgQHNRHdwaX7xUJUnm61SAzs",
        "telegram_chat_id": "-1004330330141",
        "initial_deposit_master": 1000.0,
        "initial_deposit_slave": 1000.0,
        "initial_total_capital": 2000.0,
        "enable_high_watermark_protection": True,
        "periodic_report_interval_minutes": 60,
        "send_on_order_open": True,
        "send_on_cycle_close": True,
        "enable_profit_sharing": True,
        "profit_sharing_percentage": 30.0
    }
    if not os.path.isfile(CONFIG_FILE):
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(default_cfg, f, indent=2)
        return default_cfg

    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            for k, v in default_cfg.items():
                if k not in data:
                    data[k] = v
            return data
    except Exception:
        return default_cfg


def load_ledger() -> dict:
    now_str = datetime.now().strftime("%d %b %Y, %H:%M")
    default_ledger = {
        "current_period_start": now_str,
        "period_cycles": 0,
        "period_gross_profit": 0.0,
        "period_profit_share": 0.0,
        "period_net_investor": 0.0,
        "all_time_cycles": 0,
        "all_time_gross_profit": 0.0,
        "all_time_profit_share": 0.0,
        "all_time_net_investor": 0.0,
        "settlements": [],
        "history": []
    }
    if not os.path.isfile(LEDGER_FILE):
        with open(LEDGER_FILE, "w", encoding="utf-8") as f:
            json.dump(default_ledger, f, indent=2)
        return default_ledger

    try:
        with open(LEDGER_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            for k, v in default_ledger.items():
                if k not in data:
                    data[k] = v
            return data
    except Exception:
        return default_ledger


def record_cycle_profit(gross_profit: float, share_pct: float = 30.0, current_portfolio_val: float = 2000.0, initial_capital: float = 2000.0, enable_hwm: bool = True) -> dict:
    ledger = load_ledger()

    # HIGH-WATER MARK PROTECTION:
    # Jika total nilai portofolio saat ini masih di bawah modal awal ($2,000.00),
    # Profit sharing 30% DITANGGUHKAN ($0.00) dan 100% laba dialokasikan memulihkan modal investor!
    hwm_active = False
    if enable_hwm and current_portfolio_val < initial_capital:
        share_fee = 0.0
        net_investor = gross_profit
        hwm_active = True
    else:
        share_fee = round(gross_profit * (share_pct / 100.0), 2) if gross_profit > 0 else 0.0
        net_investor = round(gross_profit - share_fee, 2)

    # Increment Period Stats
    ledger["period_cycles"] = ledger.get("period_cycles", 0) + 1
    ledger["period_gross_profit"] = round(ledger.get("period_gross_profit", 0.0) + gross_profit, 2)
    ledger["period_profit_share"] = round(ledger.get("period_profit_share", 0.0) + share_fee, 2)
    ledger["period_net_investor"] = round(ledger.get("period_net_investor", 0.0) + net_investor, 2)

    # Increment All-Time Stats
    ledger["all_time_cycles"] = ledger.get("all_time_cycles", 0) + 1
    ledger["all_time_gross_profit"] = round(ledger.get("all_time_gross_profit", 0.0) + gross_profit, 2)
    ledger["all_time_profit_share"] = round(ledger.get("all_time_profit_share", 0.0) + share_fee, 2)
    ledger["all_time_net_investor"] = round(ledger.get("all_time_net_investor", 0.0) + net_investor, 2)

    entry = {
        "cycle_period": ledger["period_cycles"],
        "cycle_all_time": ledger["all_time_cycles"],
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "gross_profit": gross_profit,
        "share_pct": 0.0 if hwm_active else share_pct,
        "share_fee": share_fee,
        "net_investor": net_investor,
        "hwm_shield_active": hwm_active,
        "portfolio_val": current_portfolio_val,
        "period_gross": ledger["period_gross_profit"],
        "period_share": ledger["period_profit_share"],
        "period_net": ledger["period_net_investor"],
        "all_time_gross": ledger["all_time_gross_profit"],
        "all_time_share": ledger["all_time_profit_share"],
        "all_time_net": ledger["all_time_net_investor"]
    }
    ledger.setdefault("history", []).append(entry)

    try:
        with open(LEDGER_FILE, "w", encoding="utf-8") as f:
            json.dump(ledger, f, indent=2)
    except Exception as e:
        print(f"Error saving ledger: {e}")

    return {
        "cycle_num": ledger["period_cycles"],
        "all_time_num": ledger["all_time_cycles"],
        "period_start": ledger.get("current_period_start", "Awal"),
        "gross_profit": gross_profit,
        "share_fee": share_fee,
        "net_investor": net_investor,
        "hwm_shield_active": hwm_active,
        "period_gross": ledger["period_gross_profit"],
        "period_share": ledger["period_profit_share"],
        "period_net": ledger["period_net_investor"],
        "all_time_gross": ledger["all_time_gross_profit"],
        "all_time_share": ledger["all_time_profit_share"],
        "all_time_net": ledger["all_time_net_investor"]
    }


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
        magic_peek, = struct.unpack_from("<q", data, 0)
        if magic_peek == 0x42484246:
            magic, version, counter, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqqqdddddi", data, offset
            )
            offset += struct.calcsize("<qqqqdddddi")
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


def send_telegram(token: str, chat_id: str, message: str) -> bool:
    if not token or not chat_id or "PASTE_" in token:
        return False

    url = f"https://api.telegram.org/bot{token}/sendMessage"

    # Method 1: Python requests (if installed)
    try:
        import requests
        resp = requests.post(url, json={"chat_id": chat_id, "text": message, "parse_mode": "HTML"}, timeout=10)
        if resp.status_code == 200:
            return True
    except Exception:
        pass

    # Method 2: Python urllib with JSON payload & SSL bypass
    try:
        import urllib.request
        payload = json.dumps({"chat_id": chat_id, "text": message, "parse_mode": "HTML"}).encode("utf-8")
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json", "User-Agent": "NovaHedgeReporter/1.0"})
        ctx = ssl._create_unverified_context() if hasattr(ssl, "_create_unverified_context") else None
        with urllib.request.urlopen(req, data=payload, context=ctx, timeout=10) as resp:
            if resp.status == 200:
                return True
    except Exception:
        pass

    # Method 3: Windows Native curl.exe with JSON payload
    try:
        payload_str = json.dumps({"chat_id": chat_id, "text": message, "parse_mode": "HTML"})
        cmd = [
            "curl.exe", "-s", "-X", "POST", url,
            "-H", "Content-Type: application/json",
            "-d", payload_str
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
        if res.returncode == 0 and '"ok":true' in res.stdout:
            return True
    except Exception:
        pass

    return False


def sync_to_cloud_portal(m: dict, s: dict, cycle_event: dict = None, sync_url: str = "https://novahedgeglobalplatform.vercel.app/api/mt5/sync"):
    """Auto-Syncs Live MT5 Data to Nova Hedge Client Portal Database."""
    try:
        if not m.get("login"):
            return  # tanpa login, server menolak payload (400) — tidak perlu dikirim
        m_bal = m.get("balance", 0.0)
        s_bal = s.get("balance", 0.0)
        m_eq = m.get("equity", 0.0)
        s_eq = s.get("equity", 0.0)
        payload = {
            "master": m,
            "slave": s,
            "total_equity": round(m_eq + max(0.0, s_eq), 2),
            "pure_cash_equity": round(m_bal + max(0.0, s_bal), 2),
            "cycle_event": cycle_event,
            "status_engine": f"⚡ ACTIVE TRADING: {m.get('count', 0)} Layers" if m.get('count', 0) > 0 else "🟢 ACTIVE STANDBY"
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(sync_url, data=data, headers={"Content-Type": "application/json", "User-Agent": "NovaHedgeLiveSync/1.0"})
        ctx = ssl._create_unverified_context() if hasattr(ssl, "_create_unverified_context") else None
        with urllib.request.urlopen(req, data=data, context=ctx, timeout=5) as resp:
            if resp.status == 200:
                print(f"[{datetime.now().strftime('%H:%M:%S')}] ☁️ Web portal synced (HTTP 200)")
    except Exception as e:
        print(f"[{datetime.now().strftime('%H:%M:%S')}] ⚠️ Web sync gagal: {e}")


def format_periodic_report(m: dict, s: dict, ledger: dict, share_pct: float, cfg: dict) -> str:
    now_str = datetime.now().strftime("%d %b %Y, %H:%M:%S")
    net_fl = round(m.get("profit", 0.0) + s.get("profit", 0.0), 2)
    sign = "+$" if net_fl >= 0 else "-$"
    icon = "🟢" if net_fl >= 0 else "🔴"

    m_bal = m.get("balance", 0.0)
    m_eq = m.get("equity", 0.0)
    s_bal = s.get("balance", 0.0)
    s_eq = s.get("equity", 0.0)

    # DYNAMIC AUTO-DETECTION FROM MT5 BALANCE:
    # Modal pokok awal dibaca otomatis dari saldo riil MT5 di awal periode pembukuan (tanpa perlu setting manual).
    init_total = float(ledger.get("period_initial_capital", 0.0))
    init_m = float(ledger.get("initial_master", 0.0))
    init_s = float(ledger.get("initial_slave", 0.0))

    if init_total <= 0.0 and m_bal > 0:
        init_m = m_bal
        init_s = max(0.0, s_bal)
        init_total = round(init_m + init_s, 2)
        ledger["period_initial_capital"] = init_total
        ledger["initial_master"] = init_m
        ledger["initial_slave"] = init_s
        try:
            with open(LEDGER_FILE, "w", encoding="utf-8") as f:
                json.dump(ledger, f, indent=2)
        except Exception:
            pass

    if init_total <= 0.0:
        init_m = float(cfg.get("initial_deposit_master", 1500.0))
        init_s = float(cfg.get("initial_deposit_slave", 1500.0))
        init_total = float(cfg.get("initial_total_capital", init_m + init_s))

    enable_hwm = cfg.get("enable_high_watermark_protection", True)

    pos_text = ""
    if m.get("count", 0) > 0:
        for idx, p in enumerate(m.get("positions", []), 1):
            m_type = p.get('type', 'SELL')
            pos_text += f"\n   • Layer #{idx}: {m_type} {p['volume']}L @ {p['price_open']} ({'+$' if p['profit']>=0 else '-$'}{abs(p['profit']):.2f})"
    else:
        pos_text = "\n   • Status: Flat (Menunggu siklus baru)"

    s_pos_text = ""
    if s.get("count", 0) > 0:
        for idx, p in enumerate(s.get("positions", []), 1):
            s_type = p.get('type', 'BUY')
            s_pos_text += f"\n   • Hedge #{idx}: {s_type} {p['volume']}L @ {p['price_open']} ({'+$' if p['profit']>=0 else '-$'}{abs(p['profit']):.2f})"
    else:
        s_pos_text = "\n   • Status: Flat (0 Hedges)"

    p_start = ledger.get("current_period_start", "Awal")
    p_gross = ledger.get("period_gross_profit", 0.0)
    p_share = ledger.get("period_profit_share", 0.0)
    p_net = ledger.get("period_net_investor", 0.0)
    p_cycles = ledger.get("period_cycles", 0)

    # MURNI HASIL TRADING KAS vs BONUS BROKER:
    # 1. Kas Riil Portofolio = Saldo Master + Saldo Slave + Floating Bersih
    # 2. Total Equity Live = Kas Riil + Kredit Bonus Broker ($300)
    pure_cash_equity = round(m_bal + max(0.0, s_bal) + net_fl, 2)
    pure_trading_gain = round(pure_cash_equity - init_total, 2)
    total_live_equity = round(m_eq + max(0.0, s_eq), 2)

    sign_gain = "+$" if pure_trading_gain >= 0 else "-$"
    sign_gross = "+$" if p_gross >= 0 else "-$"
    sign_net = "+$" if p_net >= 0 else "-$"

    # Determine Live Engine Status matching MT5 on-chart box
    s_free = s.get('free_margin', 0.0)
    m_count = m.get('count', 0)
    surplus_m_val = round(m_bal - init_m, 2)
    pct_m_val = (surplus_m_val / init_m * 100.0) if init_m > 0 else 0.0

    if pct_m_val >= 20.0 and m_count == 0:
        bot_status_str = f"🔔 REBALANCE: Saldo Master Naik +{pct_m_val:.1f}% (+${surplus_m_val:,.2f})!"
        action_hint = f"<i>💡 <b>SARAN REBALANCE (+{pct_m_val:.1f}%):</b> Saldo Master surplus +${surplus_m_val:,.2f}. Disarankan transfer ke Slave di Client Portal agar modal seimbang & klaim bonus LP broker baru.</i>"
    elif s_free < 10.0 and m_count == 0:
        bot_status_str = f"⚠️ PAUSED: Slave Margin Rendah (${s_free:,.2f}) - Harap Rebalance!"
        action_hint = "<i>💡 Tugas akun Slave telah selesai menyedot bonus! Silakan lakukan Internal Transfer dari Master ke Slave di portal Prime Codex untuk klaim bonus baru & mulai siklus berikutnya.</i>"
    elif m_count > 0:
        bot_status_str = f"⚡ ACTIVE TRADING: {m_count} Active Layers Hedged"
        action_hint = "<i>🔄 Robot sedang aktif trading & mengunci profit dua arah.</i>"
    else:
        bot_status_str = "🟢 ACTIVE: Standby Menunggu Sinyal Buka Layer 1"
        action_hint = "<i>⏳ Robot siap membuka siklus order baru.</i>"

    # Status block
    if pure_trading_gain >= 0:
        status_block = f"""\n────────────────────────────
🛡️ <b>STATUS KINERJA PORTOFOLIO</b>:
   • Target Modal Pokok : <b>${init_total:,.2f}</b>
   • Laba Trading Riil  : 🟢 <b>SURPLUS {sign_gain}{abs(pure_trading_gain):,.2f}</b>
   • Status Engine      : <b>{bot_status_str}</b>
   • Petunjuk Tindakan  : {action_hint}"""
    else:
        status_block = f"""\n────────────────────────────
🛡️ <b>STATUS KINERJA PORTOFOLIO</b>:
   • Target Modal Pokok : <b>${init_total:,.2f}</b>
   • Floating Kas Riil  : 🟡 <b>Floating {sign_gain}{abs(pure_trading_gain):,.2f} (Ter-Hedge Aman)</b>
   • Status Engine      : <b>{bot_status_str}</b>
   • Petunjuk Tindakan  : {action_hint}"""

    cum_block = f"""\n────────────────────────────
📊 <b>AKUMULASI SIKLUS ({p_cycles} Siklus Selesai)</b>:
   • Total Gross Profit : <b>{sign_gross}{abs(p_gross):,.2f}</b>
   • Net Hak Investor   : <b>{sign_net}{abs(p_net):,.2f}</b>"""

    msg = f"""📊 <b>[LIVE DUAL-MT5 BONUS HEDGING REPORT]</b>
⏰ <i>{now_str}</i>
────────────────────────────
🏦 <b>MODAL POKOK AWAL  : ${init_total:,.2f}</b> (Master: ${init_m:,.2f} | Slave: ${init_s:,.2f})
────────────────────────────
👑 <b>MASTER ({m.get('login', 'Master')})</b>:
   • Saldo / Equity : <b>${m_bal:,.2f} / ${m_eq:,.2f}</b>
   • Free Margin    : ${m.get('free_margin', 0.0):,.2f} ({m.get('margin_level', 0.0):.1f}%)
   • Floating       : ${m.get('profit', 0.0):,.2f} ({m.get('count', 0)} / 10 Layers){pos_text}

🛡️ <b>SLAVE ({s.get('login', 'Slave')} - Bonus 20% LP)</b>:
   • Saldo / Equity : <b>${s_bal:,.2f} / ${s_eq:,.2f}</b>
   • Free Margin    : ${s.get('free_margin', 0.0):,.2f} ({s.get('margin_level', 0.0):.1f}%)
   • Floating       : ${s.get('profit', 0.0):,.2f} ({s.get('count', 0)} Hedges){s_pos_text}
────────────────────────────
🎯 <b>NET FLOATING     : {icon} {sign}{abs(net_fl):.2f}</b>
📈 <b>TOTAL EQUITY LIVE: ${total_live_equity:,.2f}</b> <i>(Termasuk Bonus Broker)</i>{status_block}{cum_block}"""
    return msg


def main():
    cfg = load_config()
    token = cfg.get("telegram_bot_token", "")
    chat_id = cfg.get("telegram_chat_id", "")

    init_m = float(cfg.get("initial_deposit_master", 1000.0))
    init_s = float(cfg.get("initial_deposit_slave", 1000.0))
    init_total = float(cfg.get("initial_total_capital", init_m + init_s))
    enable_hwm = cfg.get("enable_high_watermark_protection", True)

    if "periodic_report_interval_minutes" in cfg:
        interval_sec = int(cfg.get("periodic_report_interval_minutes", 60)) * 60
    else:
        interval_sec = int(cfg.get("report_interval_seconds", 3600))

    send_on_open = cfg.get("send_on_order_open", True)
    send_on_close = cfg.get("send_on_cycle_close", True)
    enable_share = cfg.get("enable_profit_sharing", True)
    share_pct = float(cfg.get("profit_sharing_percentage", 30.0))

    print("=" * 60)
    print(" 🚀 SMART TELEGRAM LIVE REPORTER AKTIF! [PAIR 2]")
    print(f" 👉 Shared Folder MT5 : {COMMON_DIR}")
    print(f" 👉 Modal Awal Pokok  : ${init_total:,.2f} (Master: ${init_m:,.2f} | Slave: ${init_s:,.2f})")
    print(f" 👉 Proteksi Watermark: {'AKTIF (Modal Terlindungi)' if enable_hwm else 'NONAKTIF'}")
    print(f" 👉 Laporan Berkala   : Setiap {interval_sec // 60} Menit")
    print(f" 👉 Profit Sharing    : {share_pct}% ({'AKTIF' if enable_share else 'NONAKTIF'})")
    print(f" 👉 Target Group ID   : {chat_id}")
    print("=" * 60)

    last_count = -1
    last_periodic_send = 0
    last_rebalance_alert_ts = 0
    cycle_start_bal_m = 0.0
    cycle_start_bal_s = 0.0
    last_known_floating = 0.0
    last_cloud_sync = 0.0

    ledger_init = load_ledger()
    p_start_init = ledger_init.get("current_period_start", datetime.now().strftime("%d %b %Y"))

    # Startup ping
    startup_msg = f"""🟢 <b>[TELEGRAM LIVE REPORTER DIAKTIFKAN]</b>
Bot monitoring aktif di VPS.
🏦 <b>Modal Pokok Terdaftar : ${init_total:,.2f}</b>
🛡️ <b>Proteksi High-Water Mark : {'AKTIF (Laba ditahan jika modal < $2,000)' if enable_hwm else 'NONAKTIF'}</b>
💼 <i>Periode Akuntansi Aktif : Sejak {p_start_init} (Share: {int(share_pct)}%)</i>"""
    send_telegram(token, chat_id, startup_msg)

    while True:
        try:
            m = read_telemetry_file(MASTER_FILE)
            s = read_telemetry_file(SLAVE_FILE)
            ledger = load_ledger()

            # Guard: Jangan proses perubahan state jika file sedang offline / I/O lag sesaat
            if not m.get("online", False):
                time.sleep(1)
                continue

            curr_count = m.get("count", 0)
            curr_bal_m = m.get("balance", 0.0)
            curr_bal_s = s.get("balance", 0.0)
            curr_floating_m = m.get("profit", 0.0)
            curr_floating_s = s.get("profit", 0.0)
            curr_net_fl = round(curr_floating_m + curr_floating_s, 2)

            if curr_count > 0:
                last_known_floating = curr_net_fl
                if cycle_start_bal_m == 0.0 and curr_bal_m > 0:
                    cycle_start_bal_m = curr_bal_m
                if cycle_start_bal_s == 0.0 and curr_bal_s > 0:
                    cycle_start_bal_s = curr_bal_s

            # 1. EVENT: POSISI BARU TERBUKA (OPEN LAYER)
            if send_on_open and last_count != -1 and curr_count > last_count:
                new_layer = curr_count
                if last_count == 0:
                    cycle_start_bal_m = curr_bal_m
                    cycle_start_bal_s = curr_bal_s

                p_g = ledger.get("period_gross_profit", 0.0)
                p_s = ledger.get("period_profit_share", 0.0)
                p_n = ledger.get("period_net_investor", 0.0)
                p_c = ledger.get("period_cycles", 0)
                p_start_txt = ledger.get("current_period_start", "Awal")

                s_pg = "+$" if p_g >= 0 else "-$"
                s_pn = "+$" if p_n >= 0 else "-$"

                msg_open = f"""⚡ <b>[ORDER BARU TERBUKA]</b>
────────────────────────────
👑 Master: Buka <b>Layer #{new_layer}</b> ({curr_count} Posisi Aktif)
🛡️ Slave: Auto-Hedge Terbuka Berpasangan
💰 Master Balance: <b>${curr_bal_m:,.2f}</b>
💰 Slave Balance: <b>${curr_bal_s:,.2f}</b>
────────────────────────────
📊 <b>AKUMULASI SIKLUS ({p_c} Siklus Selesai):</b>
   • Total Gross Profit : <b>{s_pg}{abs(p_g):,.2f}</b>
   • Profit Share {int(share_pct)}%    : <b>-${abs(p_s):,.2f}</b>
   • Net Hak Investor   : <b>{s_pn}{abs(p_n):,.2f}</b>
⏰ <i>{datetime.now().strftime('%H:%M:%S')}</i>"""
                send_telegram(token, chat_id, msg_open)
                sync_to_cloud_portal(m, s)
                print(f"[{datetime.now().strftime('%H:%M:%S')}] 🔔 Notif Order Baru terkirim ke Telegram & Web Synced!")

            # 2. EVENT: SIKLUS SELESAI / BASKET TP TERCAPAI (CLOSE ALL)
            elif send_on_close and last_count > 0 and curr_count == 0:
                # Beri jeda 1.5 detik agar MT5 Slave selesai menulis saldo baru setelah close
                time.sleep(1.5)
                m = read_telemetry_file(MASTER_FILE)
                s = read_telemetry_file(SLAVE_FILE)
                curr_bal_m = m.get("balance", 0.0)
                curr_bal_s = s.get("balance", 0.0)

                # Calculate realized cycle profit based on actual closed trading result & floating telemetry
                # (Immune to internal transfers between Master & Slave)
                if last_known_floating > 0:
                    net_profit = round(last_known_floating, 2)
                else:
                    profit_m = round(curr_bal_m - cycle_start_bal_m, 2) if cycle_start_bal_m > 0 else 0.0
                    profit_s = round(curr_bal_s - cycle_start_bal_s, 2) if cycle_start_bal_s > 0 else 0.0
                    net_profit = round(profit_m + profit_s, 2)

                profit_m = round(curr_bal_m - cycle_start_bal_m, 2) if cycle_start_bal_m > 0 else 0.0
                profit_s = round(curr_bal_s - cycle_start_bal_s, 2) if cycle_start_bal_s > 0 else 0.0

                sign_m = "+$" if profit_m >= 0 else "-$"
                sign_s = "+$" if profit_s >= 0 else "-$"
                sign_net = "+$" if net_profit >= 0 else "-$"
                total_combined_equity = round(m.get("equity", curr_bal_m) + max(0.0, s.get("equity", 0.0)), 2)

                # Record in persistent multi-period ledger with High-Water Mark protection check!
                rec = record_cycle_profit(
                    gross_profit=net_profit,
                    share_pct=share_pct,
                    current_portfolio_val=total_combined_equity,
                    initial_capital=init_total,
                    enable_hwm=enable_hwm
                )
                cycle_num = rec["cycle_num"]
                share_fee = rec["share_fee"]
                net_investor = rec["net_investor"]
                hwm_shield = rec.get("hwm_shield_active", False)
                p_gross = rec["period_gross"]
                p_share = rec["period_share"]
                p_net = rec["period_net"]
                p_start_txt = rec["period_start"]
                all_g = rec["all_time_gross"]
                all_s = rec["all_time_share"]
                all_n = rec["all_time_net"]

                sign_pg = "+$" if p_gross >= 0 else "-$"
                sign_pn = "+$" if p_net >= 0 else "-$"
                sign_ag = "+$" if all_g >= 0 else "-$"

                if hwm_shield:
                    share_line = f"🤝 <b>Profit Sharing ({int(share_pct)}%): $0.00 (🛑 DITANGGUHKAN - Proteksi Modal)</b>"
                    net_line = f"💵 <b>Net Investor (100%) : 🟢 +${net_investor:,.2f} (100% Pemulihan Modal)</b>"
                else:
                    share_line = f"🤝 <b>Profit Sharing ({int(share_pct)}%): -${share_fee:,.2f}</b>"
                    net_line = f"💵 <b>Net Investor ({int(100-share_pct)}%) : 🟢 +${net_investor:,.2f}</b>"

                rebalance_note = ""
                init_m_calc = float(ledger.get("initial_master", 0.0)) or init_m
                init_s_calc = float(ledger.get("initial_slave", 0.0)) or init_s

                surplus_m = round(curr_bal_m - init_m_calc, 2)
                pct_m = (surplus_m / init_m_calc * 100.0) if init_m_calc > 0 else 0.0

                surplus_s = round(curr_bal_s - init_s_calc, 2)
                pct_s = (surplus_s / init_s_calc * 100.0) if init_s_calc > 0 else 0.0

                if pct_m >= 20.0:
                    rebalance_note = f"""
────────────────────────────
🔔 <b>SARAN REBALANCE OTOMATIS (MASTER SURPLUS +{pct_m:.1f}%):</b>
Saldo Master sudah mencapai <b>${curr_bal_m:,.2f}</b> (Surplus: 🟢 +${surplus_m:,.2f} dari modal awal ${init_m_calc:,.2f}).
👉 <i>Disarankan transfer internal <b>${surplus_m:,.2f}</b> dari Master ke Slave di Client Portal broker agar modal kembali seimbang dan akun Slave siap menyerap bonus LP broker 20% secara maksimal!</i>"""
                elif pct_s >= 20.0:
                    rebalance_note = f"""
────────────────────────────
🔔 <b>SARAN REBALANCE OTOMATIS (SLAVE SURPLUS +{pct_s:.1f}%):</b>
Saldo Slave sudah mencapai <b>${curr_bal_s:,.2f}</b> (Surplus: 🟢 +${surplus_s:,.2f} dari modal awal ${init_s_calc:,.2f}).
👉 <i>Disarankan transfer internal <b>${surplus_s:,.2f}</b> dari Slave ke Master di Client Portal broker agar Slave kembali ramping dan bonus broker cepat tersedot tuntas saat harga turun!</i>"""

                m_login_str = str(m.get('login', 'Master'))
                s_login_str = str(s.get('login', 'Slave'))

                msg_close = f"""🎉 <b>[BASKET TP TERCAPAI - SIKLUS #{cycle_num}]</b>
⏰ <i>{datetime.now().strftime('%d %b %Y, %H:%M:%S')}</i>
────────────────────────────
💰 <b>Gross Profit Pool  : 🟢 {sign_net}{abs(net_profit):,.2f}</b>
{share_line}
{net_line}
────────────────────────────
👑 <b>Master ({m_login_str})</b>: {sign_m}{abs(profit_m):,.2f} (Saldo: ${curr_bal_m:,.2f})
🛡️ <b>Slave ({s_login_str})</b> : {sign_s}{abs(profit_s):,.2f} (Saldo: ${curr_bal_s:,.2f})
────────────────────────────
📊 <b>AKUMULASI SIKLUS (Periode Sejak {p_start_txt}):</b>
   • Total Gross ({cycle_num} Siklus): <b>{sign_pg}{abs(p_gross):,.2f}</b>
   • Profit Share {int(share_pct)}% (Unsettled): <b>-${abs(p_share):,.2f}</b>
   • Net Hak Investor ({int(100-share_pct)}%) : <b>{sign_pn}{abs(p_net):,.2f}</b>
────────────────────────────
🏆 <i>All-Time Gross: {sign_ag}{abs(all_g):,.2f} (Total Share: ${abs(all_s):,.2f})</i>
📈 <b>Total Equity Portofolio: ${total_combined_equity:,.2f}</b>{rebalance_note}
✅ Status: Akun Bersih (0 Posisi), Siap Siklus Baru!"""
                send_telegram(token, chat_id, msg_close)
                sync_to_cloud_portal(m, s, cycle_event={
                    "cycle_num": cycle_num,
                    "gross_profit": net_profit,
                    "investor_net": net_investor,
                    "share_fee": share_fee,
                    "master_profit": profit_m,
                    "slave_profit": profit_s
                })
                print(f"[{datetime.now().strftime('%H:%M:%S')}] 🎉 Notif Basket TP (+${net_profit:,.2f} | Share: ${share_fee:,.2f}) terkirim & Web Database Synced!")

                # Reset cycle start balances
                cycle_start_bal_m = curr_bal_m
                cycle_start_bal_s = curr_bal_s
                last_known_floating = 0.0

            # 3. LAPORAN BERKALA (PERIODIC REPORT)
            now = time.time()
            if now - last_periodic_send >= interval_sec:
                report = format_periodic_report(m, s, ledger, share_pct, cfg)
                if send_telegram(token, chat_id, report):
                    last_periodic_send = now
                    sync_to_cloud_portal(m, s)
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] 📊 Laporan berkala terkirim ke Telegram & Web Database!")

            # 4. STANDALONE ALERT REBALANCE MASTER (JIKA SALDO MASTER NAIK >= 20%)
            init_m_check = float(ledger.get("initial_master", 0.0)) or init_m
            if init_m_check > 0 and curr_bal_m > 0:
                surplus_m_rt = round(curr_bal_m - init_m_check, 2)
                pct_m_rt = (surplus_m_rt / init_m_check) * 100.0
                now_ts = time.time()

                # Reset cooldown jika saldo sudah di-rebalance (surplus < 10%)
                if pct_m_rt < 10.0:
                    last_rebalance_alert_ts = 0
                elif pct_m_rt >= 20.0 and (now_ts - last_rebalance_alert_ts >= 14400):  # Cooldown 4 jam
                    last_rebalance_alert_ts = now_ts
                    m_login_str = str(m.get('login', 'Master'))
                    s_login_str = str(s.get('login', 'Slave'))
                    msg_reb = f"""🔔 <b>[PERINGATAN REBALANCE - SALDO MASTER NAIK +{pct_m_rt:.1f}%]</b>
⏰ <i>{datetime.now().strftime('%d %b %Y, %H:%M:%S')}</i>
────────────────────────────
👑 <b>Master ({m_login_str}):</b>
   • Modal Pokok Awal : <b>${init_m_check:,.2f}</b>
   • Saldo Saat Ini   : <b>${curr_bal_m:,.2f}</b> (Surplus: 🟢 +${surplus_m_rt:,.2f})
🛡️ <b>Slave ({s_login_str}):</b>
   • Saldo Saat Ini   : <b>${curr_bal_s:,.2f}</b>
────────────────────────────
💡 <b>PETUNJUK TINDAKAN REBALANCE:</b>
Saldo akun Master sudah surplus <b>+{pct_m_rt:.1f}%</b> di atas modal awal!
👉 <i>Disarankan segera lakukan <b>Internal Transfer sebesar ${surplus_m_rt:,.2f}</b> dari Master ke Slave di Client Portal broker agar:</i>
1. Rasio ketahanan modal Master & Slave kembali seimbang.
2. Akun Slave kembali terisi dan siap menyerap bonus kredit LP broker 20% secara optimal!"""
                    send_telegram(token, chat_id, msg_reb)
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] 🔔 Alert Rebalance Master (+{pct_m_rt:.1f}%) terkirim ke Telegram!")

            last_count = curr_count

            # HEARTBEAT CLOUD SYNC (tiap 30s): portal menandai telemetry >15 detik
            # sebagai offline — jadi kirim status teratur walau tidak ada event.
            if time.time() - last_cloud_sync >= 30.0:
                sync_to_cloud_portal(m, s)
                last_cloud_sync = time.time()

        except Exception as e:
            print(f"Error loop: {e}")

        time.sleep(2)


if __name__ == "__main__":
    main()
