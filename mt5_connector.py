"""
MT5 Multi-Terminal Connector Module.
Uses isolated multiprocessing workers to safely interface with multiple MT5 instances simultaneously.
"""

import os
import sys
import multiprocessing as mp
import time
import logging
from typing import Dict, Any, List, Optional

from algo_enabler import force_enable_algo_trading_all_mt5

logger = logging.getLogger("MT5Connector")


def _mt5_worker_loop(
    account_config: Dict[str, Any],
    req_queue: mp.Queue,
    resp_queue: mp.Queue,
    is_test_mode: bool = False,
):
    """
    Worker process dedicated to one MT5 terminal instance.
    All imports needed inside this process must be declared here
    because multiprocessing spawns a fresh Python interpreter.
    """
    import os       # Must re-import inside spawned process
    import sys      # Must re-import inside spawned process
    import time     # Must re-import inside spawned process
    import logging  # Must re-import inside spawned process

    worker_name = account_config.get("name", "MT5Worker")
    terminal_path = account_config.get("terminal_path", "")
    login = account_config.get("login", 0)
    password = account_config.get("password", "")
    server = account_config.get("server", "")

    mt5 = None
    connected = False

    if not is_test_mode:
        try:
            import MetaTrader5 as mt5_module
            mt5 = mt5_module
        except ImportError:
            mt5 = None

    def connect() -> bool:
        nonlocal connected
        if is_test_mode or mt5 is None:
            connected = True
            return True

        # Try initializing with specific path first, fallback to generic initialize()
        ok = False
        if terminal_path and os.path.isfile(terminal_path):
            ok = mt5.initialize(path=terminal_path)
            if not ok:
                print(f"⚠️ [{worker_name}] Path tidak valid '{terminal_path}': {mt5.last_error()}. Pakai terminal default...")

        if not ok:
            ok = mt5.initialize()

        if not ok:
            error = mt5.last_error()
            print(f"❌ [{worker_name}] Gagal menghubungkan ke MetaTrader 5: {error}")
            return False

        if login and int(login) > 0 and password:
            if not mt5.login(login=int(login), password=str(password), server=str(server)):
                error = mt5.last_error()
                print(f"⚠️ [{worker_name}] Login gagal ({login}@{server}): {error}")
                # Don't return False — still continue using whatever account is active

        # Fetch active account info
        info = mt5.account_info()
        acc_str = (
            f"Login {info.login} @ {info.server} (Bal: ${info.balance:,.2f}, Credit: ${info.credit:,.2f})"
            if info else "Connected (no account info)"
        )
        connected = True
        print(f"✅ [{worker_name}] Terhubung Real MT5: {acc_str}")
        return True

    connect()

    while True:
        try:
            msg = req_queue.get()
            if not msg:
                continue

            req_id = msg.get("req_id")
            cmd = msg.get("cmd")
            payload = msg.get("payload", {})

            if cmd == "SHUTDOWN":
                if mt5 and connected and not is_test_mode:
                    mt5.shutdown()
                resp_queue.put({"req_id": req_id, "status": "OK", "data": "Shutdown complete"})
                break

            if is_test_mode or mt5 is None:
                # Simulated response for test mode
                if cmd == "GET_ACCOUNT_INFO":
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {
                            "login": login or 1001,
                            "balance": 1000.0,
                            "credit": 200.0 if "Bonus" in worker_name else 0.0,
                            "equity": 1200.0 if "Bonus" in worker_name else 1000.0,
                            "margin": 0.0,
                            "margin_free": 1200.0 if "Bonus" in worker_name else 1000.0,
                            "margin_level": 0.0,
                            "server": server or "Demo-Server",
                            "currency": "USD",
                        },
                    })
                elif cmd == "GET_POSITIONS":
                    resp_queue.put({"req_id": req_id, "status": "OK", "data": []})
                elif cmd == "GET_SYMBOL_INFO":
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {
                            "symbol": payload.get("symbol", "XAUUSD"),
                            "bid": 2650.00,
                            "ask": 2650.25,
                            "point": 0.01,
                            "digits": 2,
                            "spread": 25,
                            "volume_min": 0.01,
                            "volume_max": 100.0,
                            "volume_step": 0.01,
                        },
                    })
                elif cmd == "ORDER_SEND":
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {"ticket": 9999001, "retcode": 10009, "comment": "Trade simulated"},
                    })
                elif cmd == "ORDER_CLOSE":
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {"retcode": 10009, "comment": "Closed simulated"},
                    })
                else:
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"Unknown cmd: {cmd}"})
                continue

            # Real MT5 Execution
            if not connected:
                if not connect():
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": "MT5 not connected"})
                    continue

            if cmd == "GET_ACCOUNT_INFO":
                info = mt5.account_info()
                if info is None:
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": str(mt5.last_error())})
                else:
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {
                            "login": info.login,
                            "balance": info.balance,
                            "credit": info.credit,
                            "equity": info.equity,
                            "margin": info.margin,
                            "margin_free": info.margin_free,
                            "margin_level": info.margin_level,
                            "server": info.server,
                            "currency": info.currency,
                        },
                    })

            elif cmd == "GET_POSITIONS":
                symbol = payload.get("symbol")
                positions = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
                if positions is None:
                    resp_queue.put({"req_id": req_id, "status": "OK", "data": []})
                else:
                    pos_list = []
                    for p in positions:
                        pos_list.append({
                            "ticket": p.ticket,
                            "symbol": p.symbol,
                            "type": "BUY" if p.type == 0 else "SELL",
                            "volume": p.volume,
                            "price_open": p.price_open,
                            "sl": p.sl,
                            "tp": p.tp,
                            "price_current": p.price_current,
                            "profit": p.profit,
                            "swap": p.swap,
                            "comment": p.comment,
                            "magic": p.magic,
                            "time": p.time,
                        })
                    resp_queue.put({"req_id": req_id, "status": "OK", "data": pos_list})

            elif cmd == "GET_SYMBOL_INFO":
                symbol = payload.get("symbol")
                s_info = mt5.symbol_info(symbol)
                if s_info is None:
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"Symbol {symbol} not found"})
                else:
                    if not s_info.visible:
                        mt5.symbol_select(symbol, True)
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {
                            "symbol": s_info.name,
                            "bid": s_info.bid,
                            "ask": s_info.ask,
                            "point": s_info.point,
                            "digits": s_info.digits,
                            "spread": s_info.spread,
                            "volume_min": s_info.volume_min,
                            "volume_max": s_info.volume_max,
                            "volume_step": s_info.volume_step,
                        },
                    })

            elif cmd == "ORDER_SEND":
                symbol = payload.get("symbol")
                action_type = payload.get("type")  # "BUY" or "SELL"
                volume = payload.get("volume")
                sl = payload.get("sl", 0.0)
                tp = payload.get("tp", 0.0)
                slippage = payload.get("slippage", 50)
                magic = payload.get("magic", 0)
                comment = payload.get("comment", "")

                # 1. Resolve exact symbol in MT5 MarketWatch
                actual_symbol = symbol
                s_info = mt5.symbol_info(symbol)
                if s_info is None:
                    for fallback in ["xauusd.std", "XAUUSD.std", "XAUUSD", "GOLD", "xauusd", "XAUUSDm", "XAUUSD.m", "XAUUSD_i"]:
                        s_info = mt5.symbol_info(fallback)
                        if s_info is not None:
                            actual_symbol = fallback
                            break

                # If still not found, search all broker symbols for Gold
                if s_info is None:
                    all_syms = mt5.symbols_get()
                    if all_syms:
                        for sym in all_syms:
                            if "XAU" in sym.name.upper() or "GOLD" in sym.name.upper():
                                actual_symbol = sym.name
                                s_info = sym
                                break

                if s_info is None:
                    print(f"❌ [{worker_name}] Symbol {symbol} (Gold) tidak ditemukan di broker!")
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"Symbol {symbol} not found on broker"})
                    continue

                if not s_info.visible:
                    mt5.symbol_select(actual_symbol, True)

                tick = mt5.symbol_info_tick(actual_symbol)
                if tick is None or (tick.ask <= 0 and tick.bid <= 0):
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"No tick price for {actual_symbol}"})
                    continue

                order_type = mt5.ORDER_TYPE_BUY if action_type == "BUY" else mt5.ORDER_TYPE_SELL
                price = tick.ask if action_type == "BUY" else tick.bid

                # Determine best filling mode
                filling_modes = [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]
                if hasattr(s_info, "filling_mode"):
                    if s_info.filling_mode & 1:
                        filling_modes = [mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_RETURN]
                    elif s_info.filling_mode & 2:
                        filling_modes = [mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK, mt5.ORDER_FILLING_RETURN]

                result = None
                for fill_mode in filling_modes:
                    request = {
                        "action": mt5.TRADE_ACTION_DEAL,
                        "symbol": actual_symbol,
                        "volume": float(volume),
                        "type": order_type,
                        "price": float(price),
                        "sl": float(sl) if sl and float(sl) > 0 else 0.0,
                        "tp": float(tp) if tp and float(tp) > 0 else 0.0,
                        "deviation": int(slippage),
                        "magic": int(magic),
                        "comment": str(comment),
                        "type_time": mt5.ORDER_TIME_GTC,
                        "type_filling": fill_mode,
                    }
                    result = mt5.order_send(request)
                    if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                        break

                if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
                    err_msg = result.comment if result else str(mt5.last_error())
                    retcode = result.retcode if result else -1
                    print(f"❌ [{worker_name}] ORDER_SEND gagal: {err_msg} (retcode={retcode})")
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": err_msg, "retcode": retcode})
                else:
                    print(f"🎉 [{worker_name}] ORDER berhasil: #{result.order} {actual_symbol} {action_type} {volume}L @ {result.price}")
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {
                            "ticket": result.order,
                            "deal": result.deal,
                            "volume": result.volume,
                            "price": result.price,
                            "retcode": result.retcode,
                            "comment": result.comment,
                            "symbol": actual_symbol,
                        },
                    })

            elif cmd == "ORDER_CLOSE":
                ticket = payload.get("ticket")
                volume = payload.get("volume")
                slippage = payload.get("slippage", 50)
                magic = payload.get("magic", 0)

                positions = mt5.positions_get(ticket=ticket)
                if not positions or len(positions) == 0:
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"Position #{ticket} not found"})
                    continue

                pos = positions[0]
                close_type = mt5.ORDER_TYPE_SELL if pos.type == 0 else mt5.ORDER_TYPE_BUY
                tick = mt5.symbol_info_tick(pos.symbol)
                if tick is None:
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"Tick not available for {pos.symbol}"})
                    continue

                close_price = tick.bid if close_type == mt5.ORDER_TYPE_SELL else tick.ask
                close_volume = float(volume) if volume else float(pos.volume)

                request = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "position": int(pos.ticket),
                    "symbol": pos.symbol,
                    "volume": close_volume,
                    "type": close_type,
                    "price": float(close_price),
                    "deviation": int(slippage),
                    "magic": int(magic),
                    "comment": f"Close #{pos.ticket}",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }

                result = mt5.order_send(request)
                if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
                    request["type_filling"] = mt5.ORDER_FILLING_FOK
                    result = mt5.order_send(request)

                if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
                    request["type_filling"] = mt5.ORDER_FILLING_RETURN
                    result = mt5.order_send(request)

                if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
                    err_msg = result.comment if result else str(mt5.last_error())
                    retcode = result.retcode if result else -1
                    resp_queue.put({"req_id": req_id, "status": "ERROR", "error": err_msg, "retcode": retcode})
                else:
                    resp_queue.put({
                        "req_id": req_id,
                        "status": "OK",
                        "data": {
                            "ticket": result.order,
                            "deal": result.deal,
                            "volume": result.volume,
                            "price": result.price,
                            "retcode": result.retcode,
                        },
                    })

            else:
                resp_queue.put({"req_id": req_id, "status": "ERROR", "error": f"Unknown cmd: {cmd}"})

        except Exception as e:
            import traceback
            print(f"❌ [{worker_name}] Exception in worker loop: {e}")
            traceback.print_exc()


class MT5Connector:
    """
    Manages dual-terminal MT5 connections via isolated workers.
    """

    def __init__(self, config: Dict[str, Any], is_test_mode: bool = False):
        self.config = config
        self.is_test_mode = is_test_mode
        self._req_counter = 0

        self.account_a_cfg = config.get("accounts", {}).get("account_a", {})
        self.account_b_cfg = config.get("accounts", {}).get("account_b", {})

        self.q_req_a = mp.Queue()
        self.q_resp_a = mp.Queue()
        self.q_req_b = mp.Queue()
        self.q_resp_b = mp.Queue()

        self.proc_a: Optional[mp.Process] = None
        self.proc_b: Optional[mp.Process] = None

    def start(self) -> None:
        """Starts both terminal workers."""
        # Automatically toggle Algo Trading to ON in MT5 windows for configured logins only
        login_master = self.account_a_cfg.get("login", 0)
        login_slave = self.account_b_cfg.get("login", 0)
        force_enable_algo_trading_all_mt5(login_master=login_master, login_slave=login_slave)

        self.proc_a = mp.Process(
            target=_mt5_worker_loop,
            args=(self.account_a_cfg, self.q_req_a, self.q_resp_a, self.is_test_mode),
            name="MT5Worker-A",
        )

        self.proc_b = mp.Process(
            target=_mt5_worker_loop,
            args=(self.account_b_cfg, self.q_req_b, self.q_resp_b, self.is_test_mode),
            name="MT5Worker-B",
        )
        self.proc_a.daemon = True
        self.proc_b.daemon = True
        self.proc_a.start()
        self.proc_b.start()

    def _call(self, target: str, cmd: str, payload: Optional[Dict[str, Any]] = None, timeout: float = 10.0) -> Dict[str, Any]:
        self._req_counter += 1
        req_id = self._req_counter
        msg = {"req_id": req_id, "cmd": cmd, "payload": payload or {}}

        req_q = self.q_req_a if target == "A" else self.q_req_b
        resp_q = self.q_resp_a if target == "A" else self.q_resp_b

        req_q.put(msg)
        start_time = time.time()
        while time.time() - start_time < timeout:
            if not resp_q.empty():
                resp = resp_q.get()
                if resp.get("req_id") == req_id:
                    return resp
            time.sleep(0.01)

        return {"req_id": req_id, "status": "TIMEOUT", "error": f"Request {cmd} timed out after {timeout}s"}

    def get_account_info_a(self) -> Dict[str, Any]:
        return self._call("A", "GET_ACCOUNT_INFO")

    def get_account_info_b(self) -> Dict[str, Any]:
        return self._call("B", "GET_ACCOUNT_INFO")

    def get_positions_a(self, symbol: Optional[str] = None) -> Dict[str, Any]:
        return self._call("A", "GET_POSITIONS", {"symbol": symbol})

    def get_positions_b(self, symbol: Optional[str] = None) -> Dict[str, Any]:
        return self._call("B", "GET_POSITIONS", {"symbol": symbol})

    def get_symbol_info_a(self, symbol: str) -> Dict[str, Any]:
        return self._call("A", "GET_SYMBOL_INFO", {"symbol": symbol})

    def send_order_a(
        self,
        symbol: str,
        order_type: str,
        volume: float,
        sl: float = 0.0,
        tp: float = 0.0,
        slippage: int = 50,
        magic: int = 0,
        comment: str = "",
    ) -> Dict[str, Any]:
        return self._call("A", "ORDER_SEND", {
            "symbol": symbol,
            "type": order_type,
            "volume": volume,
            "sl": sl,
            "tp": tp,
            "slippage": slippage,
            "magic": magic,
            "comment": comment,
        })

    def close_position_a(self, ticket: int, volume: Optional[float] = None, slippage: int = 50) -> Dict[str, Any]:
        return self._call("A", "ORDER_CLOSE", {"ticket": ticket, "volume": volume, "slippage": slippage})

    def get_symbol_info_b(self, symbol: str) -> Dict[str, Any]:
        return self._call("B", "GET_SYMBOL_INFO", {"symbol": symbol})

    def send_order_b(
        self,
        symbol: str,
        order_type: str,
        volume: float,
        sl: float = 0.0,
        tp: float = 0.0,
        slippage: int = 50,
        magic: int = 0,
        comment: str = "",
    ) -> Dict[str, Any]:
        return self._call("B", "ORDER_SEND", {
            "symbol": symbol,
            "type": order_type,
            "volume": volume,
            "sl": sl,
            "tp": tp,
            "slippage": slippage,
            "magic": magic,
            "comment": comment,
        })

    def close_position_b(self, ticket: int, volume: Optional[float] = None, slippage: int = 50) -> Dict[str, Any]:
        return self._call("B", "ORDER_CLOSE", {"ticket": ticket, "volume": volume, "slippage": slippage})

    def stop(self) -> None:
        """Stops both workers cleanly."""
        try:
            self._call("A", "SHUTDOWN", timeout=1.0)
        except Exception:
            pass
        try:
            self._call("B", "SHUTDOWN", timeout=1.0)
        except Exception:
            pass

        for p in (self.proc_a, self.proc_b):
            if p and p.is_alive():
                try:
                    p.terminate()
                    p.join(timeout=1.0)
                except Exception:
                    pass
