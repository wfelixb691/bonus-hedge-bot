"""
Diagnostic tool to inspect Python environment and exact MetaTrader5 import error.
"""

import sys
import os

print("=" * 60)
print(" 🔍 CEK DETAIL PYTHON & METATRADER 5")
print("=" * 60)
print(f"👉 Python Executable: {sys.executable}")
print(f"👉 Python Version:    {sys.version}")

try:
    import MetaTrader5 as mt5
    print("\n✅ Library MetaTrader5: BERHASIL DI-IMPORT 100%!")
    print(f"👉 Versi MetaTrader5 Package: {mt5.__version__}")
    
    # Try connecting
    if mt5.initialize():
        info = mt5.account_info()
        if info:
            print(f"\n🎉 BERHASIL TERHUBUNG KE AKUN MT5!")
            print(f"   👉 Login:   {info.login}")
            print(f"   👉 Server:  {info.server}")
            print(f"   👉 Balance: ${info.balance:,.2f}")
            print(f"   👉 Credit:  ${info.credit:,.2f}")
            print(f"   👉 Equity:  ${info.equity:,.2f}")
        else:
            print(f"⚠️ Initialize OK tapi account info None: {mt5.last_error()}")
        mt5.shutdown()
    else:
        print(f"⚠️ Inisialisasi default: {mt5.last_error()}")

except Exception as e:
    print(f"\n❌ GAGAL IMPORT MetaTrader5: {type(e).__name__} -> {e}")
    print("\n👉 SOLUSI: Jalankan perintah ini di CMD:")
    print(f"   {sys.executable} -m pip install --upgrade --force-reinstall MetaTrader5")

print("\n" + "=" * 60)
