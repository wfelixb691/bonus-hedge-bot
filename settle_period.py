"""
Settlement & Period Reset Utility for Dual-MT5 Bonus Hedging Bot.
Marks the current profit-sharing period as SETTLED/PAID, records payout history,
and starts a fresh accounting period with exact timestamp tracking.
"""

import os
import sys
import json
from datetime import datetime

LEDGER_FILE = "profit_ledger.json"
CONFIG_FILE = "telegram_config.json"


def load_ledger() -> dict:
    default_ledger = {
        "current_period_start": datetime.now().strftime("%d %b %Y, %H:%M:%S"),
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


def send_settlement_telegram(p_start: str, p_end: str, cycles: int, gross: float, share: float, net_inv: float):
    if not os.path.isfile(CONFIG_FILE):
        return
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        token = cfg.get("telegram_bot_token", "")
        chat_id = cfg.get("telegram_chat_id", "")
        share_pct = int(cfg.get("profit_sharing_percentage", 30.0))

        if not token or not chat_id:
            return

        msg = f"""🧾 <b>[SETTLEMENT / PEMBAYARAN PROFIT SHARING]</b>
────────────────────────────
📅 <b>Periode: {p_start} s/d {p_end}</b>
🔢 Total Siklus: <b>{cycles} Siklus</b>
────────────────────────────
💰 <b>Gross Profit Pool : 🟢 +${gross:,.2f}</b>
🤝 <b>Profit Sharing ({share_pct}%): -${share:,.2f} (LUNAS DIBAYARKAN)</b>
💵 <b>Net Investor ({100-share_pct}%) : 🟢 +${net_inv:,.2f}</b>
────────────────────────────
✅ <i>Buku kas di-reset! Periode baru dimulai per {p_end}.</i>"""

        # Import send_telegram from telegram_reporter if available
        import telegram_reporter
        telegram_reporter.send_telegram(token, chat_id, msg)
        print("✅ Notifikasi Settlement berhasil dikirim ke Telegram!")
    except Exception as e:
        print(f"⚠️ Gagal kirim notif telegram: {e}")


def main():
    ledger = load_ledger()
    p_gross = ledger.get("period_gross_profit", 0.0)
    p_share = ledger.get("period_profit_share", 0.0)
    p_net = ledger.get("period_net_investor", 0.0)
    p_cycles = ledger.get("period_cycles", 0)
    p_start = ledger.get("current_period_start", "Awal")
    p_end = datetime.now().strftime("%d %b %Y, %H:%M:%S")

    print("=" * 65)
    print(" 🧾 SETTLEMENT & RESET BUKU KAS PROFIT SHARING")
    print("=" * 65)
    print(f" 📅 Periode Berjalan : {p_start} s/d {p_end}")
    print(f" 🔢 Siklus Selesai   : {p_cycles} Siklus")
    print(f" 💰 Gross Profit Pool: +${p_gross:,.2f}")
    print(f" 🤝 Profit Share 30% : +${p_share:,.2f} (Tagihan Pembayaran)")
    print(f" 💵 Net Investor 70% : +${p_net:,.2f}")
    print("=" * 65)

    if p_cycles == 0 and p_gross == 0:
        print("\nℹ️ Periode ini masih kosong (belum ada siklus TP).")
        print("Reset tetap akan memperbarui tanggal awal periode ke hari ini.")

    confirm = input("\n👉 Apakah Anda yakin ingin MERESET periode & menandai sudah dibayar? (y/n): ")
    if confirm.lower() != "y":
        print("\n❌ Settlement dibatalkan.")
        return

    # Record settlement
    settlement_entry = {
        "settlement_id": len(ledger.get("settlements", [])) + 1,
        "period_start": p_start,
        "period_end": p_end,
        "cycles": p_cycles,
        "gross_profit": p_gross,
        "profit_share": p_share,
        "net_investor": p_net
    }
    ledger.setdefault("settlements", []).append(settlement_entry)

    # Reset current period
    ledger["current_period_start"] = p_end
    ledger["period_cycles"] = 0
    ledger["period_gross_profit"] = 0.0
    ledger["period_profit_share"] = 0.0
    ledger["period_net_investor"] = 0.0

    with open(LEDGER_FILE, "w", encoding="utf-8") as f:
        json.dump(ledger, f, indent=2)

    print("\n🎉 [SUKSES] Periode berhasil di-reset!")
    print(f"📅 Periode Baru Dimulai: {p_end}")

    # Send telegram broadcast
    send_settlement_telegram(p_start, p_end, p_cycles, p_gross, p_share, p_net)


if __name__ == "__main__":
    main()
