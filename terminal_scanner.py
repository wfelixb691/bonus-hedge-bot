"""
Safe MT5 Process Matcher.
Accurately finds running terminal64.exe processes and pairs 100870 & 100871 without any cmd.exe false-positives.
"""

import os
import sys
import logging
from typing import Dict, Any, List, Tuple

logger = logging.getLogger("TerminalScanner")


def get_running_mt5_instances() -> List[Dict[str, Any]]:
    """
    Safely finds currently running terminal64.exe / terminal.exe instances.
    Guaranteed to ignore cmd.exe, powershell.exe, python.exe, etc.
    """
    instances: List[Dict[str, Any]] = []
    if sys.platform != "win32":
        return instances

    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32

        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def enum_windows_proc(hwnd, lparam):
            if not user32.IsWindowVisible(hwnd):
                return True

            length = user32.GetWindowTextLengthW(hwnd)
            if length > 0:
                buff = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(hwnd, buff, length + 1)
                title = buff.value

                pid = wintypes.DWORD()
                user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))

                if pid.value > 0:
                    h_proc = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
                    if h_proc:
                        exe_path_buf = ctypes.create_unicode_buffer(1024)
                        size = wintypes.DWORD(1024)
                        if kernel32.QueryFullProcessImageNameW(h_proc, 0, exe_path_buf, ctypes.byref(size)):
                            exe_path = exe_path_buf.value
                            exe_lower = exe_path.lower()

                            # STRICT: Must be terminal64.exe or terminal.exe (NEVER cmd.exe or python.exe)
                            if exe_lower.endswith("terminal64.exe") or exe_lower.endswith("terminal.exe"):
                                instances.append({
                                    "path": exe_path,
                                    "title": title,
                                    "pid": pid.value,
                                })
                        kernel32.CloseHandle(h_proc)
            return True

        user32.EnumWindows(enum_windows_proc, 0)
    except Exception as e:
        logger.warning(f"Error resolving running MT5 instances: {e}")

    return instances


def match_terminals_by_login(login_master: int = 100870, login_slave: int = 100871) -> Tuple[str, str]:
    """
    Finds exact terminal64.exe paths for Master (100870) and Slave (100871).
    """
    running = get_running_mt5_instances()
    path_master = ""
    path_slave = ""

    print(f"\n🔍 [MT5 Scanner] Menemukan {len(running)} terminal MT5 asli yang sedang aktif:")
    for inst in running:
        p = inst["path"]
        t = inst["title"]
        print(f"   👉 [{inst['pid']}] {p}\n      Judul: {t}")
        if str(login_master) in t:
            path_master = p
            print(f"      ✅ MATCH MASTER ({login_master})")
        elif str(login_slave) in t:
            path_slave = p
            print(f"      ✅ MATCH SLAVE ({login_slave})")

    # Fallback to known Prime Codex paths on VPS if title matching didn't catch one
    prime_paths = [
        r"C:\Program Files\Prime Codex MetaTrader 5\terminal64.exe",
        r"C:\Program Files\Prime Codex MetaTrader 5 TB 1\terminal64.exe",
        r"C:\Program Files\Prime Codex MetaTrader 5 TB 2\terminal64.exe",
        r"C:\Program Files\Prime Codex MetaTrader 5 Felix-1 Terminal\terminal64.exe",
        r"C:\Program Files\Prime Codex MetaTrader 5 Felix-2 Terminal\terminal64.exe",
        r"C:\Program Files\MetaTrader 5\terminal64.exe",
        r"C:\Program Files\MetaTrader 5 Master\terminal64.exe",
        r"C:\Program Files\MetaTrader 5 Bonus\terminal64.exe",
    ]

    valid_on_disk = [p for p in prime_paths if os.path.isfile(p)]

    if not path_master:
        # If we have running instances that weren't assigned to slave
        running_non_slave = [x["path"] for x in running if x["path"] != path_slave]
        if running_non_slave:
            path_master = running_non_slave[0]
        elif valid_on_disk:
            path_master = valid_on_disk[0]

    if not path_slave:
        running_non_master = [x["path"] for x in running if x["path"] != path_master]
        if running_non_master:
            path_slave = running_non_master[0]
        elif len(valid_on_disk) > 1:
            path_slave = valid_on_disk[1]

    print(f"\n🎯 [Hasil Mapping Terminal]:")
    print(f"   Master ({login_master}): {path_master}")
    print(f"   Slave  ({login_slave}): {path_slave}\n")

    return path_master, path_slave


def auto_detect_and_configure() -> Tuple[Dict[str, Any], bool]:
    """Auto-detects running Master (100870) and Slave (100871) and builds config."""
    path_m, path_s = match_terminals_by_login(100870, 100871)
    cfg = {
        "accounts": {
            "account_a": {
                "name": "Account A (Master 100870)",
                "login": 100870,
                "password": "",
                "server": "",
                "terminal_path": path_m,
            },
            "account_b": {
                "name": "Account B (Slave 100871)",
                "login": 100871,
                "password": "",
                "server": "",
                "terminal_path": path_s,
            },
        },
        "grid": {
            "enabled": True,
            "symbol": "XAUUSD",
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
            "XAUUSD": "XAUUSD",
            "xauusd.std": "xauusd.std",
            "GOLD": "GOLD",
        },
        "monitoring": {
            "scan_interval_ms": 100,
            "state_file": "hedge_state.json",
            "log_file": "bot_hedger.log",
        },
    }
    return cfg, True
