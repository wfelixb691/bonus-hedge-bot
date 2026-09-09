"""
Super-Clean Setup Wizard:
Only asks for Master Login and Slave Login.
Automatically detects and pairs the matching MT5 terminals on the VPS.
"""

import os
import json
from typing import Dict, Any
from terminal_scanner import match_terminals_by_login


def load_current_config(config_path: str = "config.json") -> Dict[str, Any]:
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_config(config: Dict[str, Any], config_path: str = "config.json") -> None:
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)
    print(f"\n✅ Akun Master & Slave berhasil dipasangkan dan disimpan!\n")


def prompt_input(label: str, default: Any = "") -> str:
    default_str = f" [{default}]" if default != "" else ""
    prompt_text = f"{label}{default_str}: "
    val = input(prompt_text).strip()
    return val if val != "" else str(default)


def run_interactive_wizard(config_path: str = "config.json") -> Dict[str, Any]:
    """Hanya menanyakan Nomor Login Master dan Slave, sisanya otomatis 100%."""
    cfg = load_current_config(config_path)

    acc_a = cfg.get("accounts", {}).get("account_a", {})
    acc_b = cfg.get("accounts", {}).get("account_b", {})

    print("\n" + "=" * 60)
    print(" 🛠️  INPUT NOMOR LOGIN AKUN MT5")
    print("=" * 60)
    print("Semua parameter trading & path terminal sudah OTOMATIS.")
    print("Cukup masukkan 2 nomor login akun MT5 Anda:\n")

    # --- 1. Login Master ---
    login_a_str = prompt_input("1. Nomor Login MT5 Master (Akun Tanpa Bonus)", acc_a.get("login", ""))
    login_a = int(login_a_str) if login_a_str and login_a_str != "0" else 0

    # --- 2. Login Slave ---
    login_b_str = prompt_input("2. Nomor Login MT5 Slave (Akun Welcome Bonus 20%)", acc_b.get("login", ""))
    login_b = int(login_b_str) if login_b_str and login_b_str != "0" else 0

    # Auto-match MT5 terminal paths based on logins
    path_a, path_b = match_terminals_by_login(login_a, login_b)

    new_config = {
        "accounts": {
            "account_a": {
                "name": f"Account A (Master {login_a})",
                "login": login_a,
                "password": "",
                "server": "",
                "terminal_path": path_a or "C:\\Program Files\\MetaTrader 5 Master\\terminal64.exe",
            },
            "account_b": {
                "name": f"Account B (Slave {login_b})",
                "login": login_b,
                "password": "",
                "server": "",
                "terminal_path": path_b or "C:\\Program Files\\MetaTrader 5 Bonus\\terminal64.exe",
            },
        },
        "grid": {
            "enabled": True,
            "symbol": "xauusd.std",
            "direction": "SELL",
            "initial_lot": 0.10,
            "auto_scale_lot": True,
            "grid_step_points": 2000,
            "max_layers": 10,
            "take_profit_points": 2500,
            "basket_tp_dollars": 31.74,
            "comment_prefix": "GRID_S",
        },
        "hedging": {
            "enabled": True,
            "lot_mode": "multiplier",
            "multiplier": 1.1,
            "min_lot": 0.01,
            "max_lot": 50.0,
            "magic_number": 888999,
            "comment_prefix": "CT#",
            "slippage_points": 50,
            "sync_close": True,
            "sync_sl_tp": False,
            "execution_delay_ms": 0,
            "retry_attempts": 3,
            "retry_delay_ms": 250,
        },
        "symbol_mapping": {
            "xauusd.std": "xauusd.std",
            "XAUUSD": "XAUUSD",
            "GOLD": "GOLD",
        },
        "monitoring": {
            "scan_interval_ms": 100,
            "state_file": "hedge_state.json",
            "log_file": "bot_hedger.log",
        },
    }

    save_config(new_config, config_path)
    return new_config


def show_main_interactive_menu() -> str:
    """Shows interactive menu on launch."""
    print("\n" + "=" * 60)
    print(" ⚡ ALL-IN-ONE DUAL-MT5 GRID & BONUS HEDGING BOT ⚡")
    print("=" * 60)
    print(" [1] 🚀 Jalankan Bot Live (Master + Bonus Hedging)")
    print(" [2] ⚙️  Input / Edit Nomor Login Akun (Master & Slave)")
    print(" [3] 🧪 Jalankan Mode Simulasi / Test (Tanpa MT5 Live)")
    print(" [4] ❌ Keluar")
    print("=" * 60)
    choice = input("Pilih Menu (1/2/3/4) [Default: 1]: ").strip()
    return choice if choice != "" else "1"
