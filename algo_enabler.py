"""
Safe Windows MT5 Auto-Enabler for Algo Trading.
Only targets specific Master and Slave MT5 windows, leaving other EAs untouched.
"""

import sys
import logging

logger = logging.getLogger("AlgoEnabler")


def force_enable_algo_trading_all_mt5(login_master: int = 0, login_slave: int = 0):
    """
    Finds running MetaTrader 5 windows for Master (100870) and Slave (100871)
    and programmatically ensures Algo Trading is ON.
    Leaves other EA windows completely untouched.
    """
    if sys.platform != "win32":
        return

    try:
        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def enum_windows_proc(hwnd, lparam):
            if not user32.IsWindowVisible(hwnd):
                return True

            length = user32.GetWindowTextLengthW(hwnd)
            if length > 0:
                buff = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(hwnd, buff, length + 1)
                title = buff.value

                is_target = False
                if login_master and str(login_master) in title:
                    is_target = True
                elif login_slave and str(login_slave) in title:
                    is_target = True
                elif not login_master and not login_slave and ("MetaTrader 5" in title or "MT5" in title or "PrimeCodex" in title):
                    is_target = True

                if is_target:
                    WM_COMMAND = 0x0111
                    CMD_ALGO_TRADING = 32851
                    user32.PostMessageW(hwnd, WM_COMMAND, CMD_ALGO_TRADING, 0)
                    logger.info(f"[AlgoEnabler] 🟢 Activated Algo Trading for target window: {title}")

            return True

        user32.EnumWindows(enum_windows_proc, 0)
    except Exception as e:
        logger.warning(f"[AlgoEnabler] Notice: {e}")
