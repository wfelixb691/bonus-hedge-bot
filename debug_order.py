"""
Debug tool: Test apakah MT5 bisa konek dan buka order Gold.
Jalankan: python debug_order.py
"""

import sys
import time

print("=" * 60)
print(" 🔍 DEBUG: CEK KONEKSI + TEST BUKA ORDER GOLD")
print("=" * 60)
print(f"👉 Python: {sys.executable}")

try:
    import MetaTrader5 as mt5
    print(f"✅ Library MetaTrader5 OK (versi {mt5.__version__})")
except Exception as e:
    print(f"❌ GAGAL import MetaTrader5: {e}")
    print(f"   Jalankan: {sys.executable} -m pip install MetaTrader5")
    input("\nTekan Enter untuk keluar...")
    sys.exit(1)

# ─── 1. Inisialisasi MT5 ────────────────────────────────────
print("\n[1] Inisialisasi MT5...")
if not mt5.initialize():
    print(f"❌ initialize() gagal: {mt5.last_error()}")
    input("\nTekan Enter untuk keluar...")
    sys.exit(1)
print("✅ initialize() berhasil!")

# ─── 2. Info Akun ────────────────────────────────────────────
info = mt5.account_info()
if info:
    print(f"\n[2] Akun Aktif:")
    print(f"   Login   : {info.login}")
    print(f"   Server  : {info.server}")
    print(f"   Balance : ${info.balance:,.2f}")
    print(f"   Credit  : ${info.credit:,.2f}")
    print(f"   Equity  : ${info.equity:,.2f}")
else:
    print(f"⚠️  Tidak ada info akun: {mt5.last_error()}")

# ─── 3. Cari Symbol Gold ─────────────────────────────────────
print("\n[3] Mencari symbol Gold...")
gold_symbol = None
for name in ["xauusd.std", "XAUUSD.std", "XAUUSD", "GOLD", "xauusd", "XAUUSDm"]:
    s = mt5.symbol_info(name)
    if s is not None:
        gold_symbol = name
        print(f"✅ Symbol ditemukan: {name}  (bid={s.bid}, ask={s.ask})")
        break

if gold_symbol is None:
    print("⚠️  Mencari dari semua symbol broker...")
    all_syms = mt5.symbols_get()
    if all_syms:
        for sym in all_syms:
            if "XAU" in sym.name.upper() or "GOLD" in sym.name.upper():
                gold_symbol = sym.name
                print(f"✅ Ditemukan dari daftar: {gold_symbol}")
                break

if gold_symbol is None:
    print("❌ Symbol Gold tidak ditemukan di broker ini!")
    mt5.shutdown()
    input("\nTekan Enter untuk keluar...")
    sys.exit(1)

# Pastikan symbol visible di MarketWatch
mt5.symbol_select(gold_symbol, True)
time.sleep(0.3)

# ─── 4. Cek Harga ────────────────────────────────────────────
tick = mt5.symbol_info_tick(gold_symbol)
if not tick or tick.ask <= 0:
    print(f"❌ Tidak ada harga untuk {gold_symbol}: {mt5.last_error()}")
    mt5.shutdown()
    input("\nTekan Enter untuk keluar...")
    sys.exit(1)

print(f"\n[4] Harga sekarang: BID={tick.bid}  ASK={tick.ask}")

# ─── 5. Test Buka Order SELL 0.01 Lot ──────────────────────
print(f"\n[5] Mencoba buka order SELL 0.01L {gold_symbol}...")
s_info = mt5.symbol_info(gold_symbol)

filling_modes = [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]
mode_names    = ["IOC", "FOK", "RETURN"]
result = None

for fill_mode, mode_name in zip(filling_modes, mode_names):
    request = {
        "action":       mt5.TRADE_ACTION_DEAL,
        "symbol":       gold_symbol,
        "volume":       0.01,
        "type":         mt5.ORDER_TYPE_SELL,
        "price":        tick.bid,
        "deviation":    50,
        "magic":        999888,
        "comment":      "DEBUG_TEST",
        "type_time":    mt5.ORDER_TIME_GTC,
        "type_filling": fill_mode,
    }
    print(f"   Mencoba filling mode {mode_name}...")
    result = mt5.order_send(request)
    if result and result.retcode == mt5.TRADE_RETCODE_DONE:
        print(f"   ✅ ORDER BERHASIL! Ticket #{result.order}  Price={result.price}")
        break
    else:
        retcode = result.retcode if result else -1
        comment = result.comment if result else str(mt5.last_error())
        print(f"   ❌ Gagal ({mode_name}): retcode={retcode}  alasan='{comment}'")

if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
    print("\n❌ SEMUA FILLING MODE GAGAL. Kemungkinan penyebab:")
    print("   1. Algo Trading BELUM aktif di MT5 (tombol harus hijau)")
    print("   2. Akun demo tidak mengizinkan trading")
    print("   3. Symbol Gold tidak tersedia untuk trading di akun ini")
else:
    # Tutup order test
    time.sleep(1)
    print(f"\n[6] Menutup order test #{result.order}...")
    tick2 = mt5.symbol_info_tick(gold_symbol)
    close_req = {
        "action":       mt5.TRADE_ACTION_DEAL,
        "position":     result.order,
        "symbol":       gold_symbol,
        "volume":       0.01,
        "type":         mt5.ORDER_TYPE_BUY,
        "price":        tick2.ask if tick2 else tick.ask,
        "deviation":    50,
        "magic":        999888,
        "comment":      "Close DEBUG",
        "type_time":    mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    close_res = mt5.order_send(close_req)
    if close_res and close_res.retcode == mt5.TRADE_RETCODE_DONE:
        print(f"   ✅ Order test berhasil ditutup.")
    else:
        print(f"   ⚠️  Tutup manual di MT5: ticket #{result.order}")

mt5.shutdown()
print("\n" + "=" * 60)
print(" ✅ DEBUG SELESAI")
print("=" * 60)
input("\nTekan Enter untuk keluar...")
