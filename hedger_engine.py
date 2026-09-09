"""
Hedger Engine Core Logic.
Coordinates order scanning, reverse order execution, lot scaling, ticket mapping, and synchronized closing.
"""

import time
import logging
from typing import Dict, Any, Optional

from lot_calculator import LotCalculator
from state_manager import StateManager
from mt5_connector import MT5Connector

logger = logging.getLogger("HedgerEngine")


class HedgerEngine:
    def __init__(self, config: Dict[str, Any], connector: MT5Connector, is_test_mode: bool = False):
        self.config = config
        self.connector = connector
        self.is_test_mode = is_test_mode

        # Hedging parameters
        h_cfg = config.get("hedging", {})
        self.enabled = h_cfg.get("enabled", True)
        self.lot_mode = h_cfg.get("lot_mode", "multiplier")
        self.multiplier = float(h_cfg.get("multiplier", 1.1))
        self.min_lot = float(h_cfg.get("min_lot", 0.01))
        self.max_lot = float(h_cfg.get("max_lot", 50.0))
        self.magic_number = int(h_cfg.get("magic_number", 888999))
        self.comment_prefix = str(h_cfg.get("comment_prefix", "CT#"))
        self.slippage = int(h_cfg.get("slippage_points", 50))
        self.sync_close = bool(h_cfg.get("sync_close", True))
        self.execution_delay_ms = int(h_cfg.get("execution_delay_ms", 0))
        self.retry_attempts = int(h_cfg.get("retry_attempts", 3))
        self.retry_delay_ms = int(h_cfg.get("retry_delay_ms", 250))

        # Symbol Mapping
        self.symbol_mapping: Dict[str, str] = config.get("symbol_mapping", {})

        # Submodules
        self.lot_calculator = LotCalculator(
            mode=self.lot_mode,
            multiplier=self.multiplier,
            min_lot=self.min_lot,
            max_lot=self.max_lot,
        )
        state_file = config.get("monitoring", {}).get("state_file", "hedge_state.json")
        self.state_manager = StateManager(state_file=state_file)

    def map_symbol(self, symbol_a: str) -> str:
        """Resolves target symbol on Account B."""
        return self.symbol_mapping.get(symbol_a, symbol_a)

    def execute_reverse_order(self, pos_a: Dict[str, Any], equity_a: float, equity_b: float) -> Optional[int]:
        """
        Calculates lot size and executes opposite order on Account B with CT# tagging.
        """
        master_ticket = int(pos_a["ticket"])
        symbol_a = pos_a["symbol"]
        symbol_b = self.map_symbol(symbol_a)
        master_type = pos_a["type"]  # "BUY" or "SELL"
        slave_type = "SELL" if master_type == "BUY" else "BUY"
        master_lot = float(pos_a["volume"])

        # Fetch symbol specs on Account B
        s_info_resp = self.connector.get_symbol_info_b(symbol_b)
        v_min, v_max, v_step = 0.01, 50.0, 0.01
        if s_info_resp.get("status") == "OK":
            s_data = s_info_resp.get("data", {})
            v_min = s_data.get("volume_min", 0.01)
            v_max = s_data.get("volume_max", 50.0)
            v_step = s_data.get("volume_step", 0.01)

        # Calculate lot
        slave_lot = self.lot_calculator.calculate_slave_lot(
            master_lot=master_lot,
            equity_a=equity_a,
            equity_b=equity_b,
            volume_min=v_min,
            volume_max=v_max,
            volume_step=v_step,
        )

        # Calculate inverted SL/TP if sync_sl_tp is enabled and SL/TP exists on Master
        slave_sl = 0.0
        slave_tp = 0.0
        if self.config.get("hedging", {}).get("sync_sl_tp", False):
            master_price = float(pos_a.get("price_open", 0.0))
            master_sl = float(pos_a.get("sl", 0.0))
            master_tp = float(pos_a.get("tp", 0.0))
            if master_price > 0:
                if master_type == "SELL":
                    # Master SELL: SL is above, TP is below
                    # Slave BUY: SL is below (master TP distance), TP is above (master SL distance)
                    if master_sl > 0:
                        dist_sl = abs(master_sl - master_price)
                        slave_tp = round(s_info_resp.get("data", {}).get("ask", master_price) + dist_sl, 2)
                    if master_tp > 0:
                        dist_tp = abs(master_price - master_tp)
                        slave_sl = round(s_info_resp.get("data", {}).get("bid", master_price) - dist_tp, 2)
                elif master_type == "BUY":
                    # Master BUY: SL is below, TP is above
                    # Slave SELL: SL is above (master TP distance), TP is below (master SL distance)
                    if master_sl > 0:
                        dist_sl = abs(master_price - master_sl)
                        slave_tp = round(s_info_resp.get("data", {}).get("bid", master_price) - dist_sl, 2)
                    if master_tp > 0:
                        dist_tp = abs(master_tp - master_price)
                        slave_sl = round(s_info_resp.get("data", {}).get("ask", master_price) + dist_tp, 2)

        # Comment tag: e.g. CT#13511868
        order_comment = f"{self.comment_prefix}{master_ticket}"

        logger.info(
            f"[HEDGE OPEN] Master #{master_ticket} ({symbol_a} {master_type} {master_lot}L) -> "
            f"Slave ({symbol_b} {slave_type} {slave_lot}L, Comment: {order_comment})"
        )

        if self.execution_delay_ms > 0:
            time.sleep(self.execution_delay_ms / 1000.0)

        # Execute with retry
        for attempt in range(1, self.retry_attempts + 1):
            resp = self.connector.send_order_b(
                symbol=symbol_b,
                order_type=slave_type,
                volume=slave_lot,
                sl=slave_sl,
                tp=slave_tp,
                slippage=self.slippage,
                magic=self.magic_number,
                comment=order_comment,
            )


            if resp.get("status") == "OK":
                slave_ticket = resp["data"].get("ticket")
                logger.info(f"[HEDGE SUCCESS] Slave position opened successfully. Ticket #{slave_ticket}")
                self.state_manager.add_pair(
                    master_ticket=master_ticket,
                    slave_ticket=slave_ticket,
                    symbol_a=symbol_a,
                    symbol_b=symbol_b,
                    master_type=master_type,
                    slave_type=slave_type,
                    master_lot=master_lot,
                    slave_lot=slave_lot,
                )
                return slave_ticket
            else:
                logger.warning(
                    f"[HEDGE RETRY {attempt}/{self.retry_attempts}] Failed to open on B: "
                    f"{resp.get('error')} (RetCode: {resp.get('retcode')})"
                )
                if attempt < self.retry_attempts:
                    time.sleep(self.retry_delay_ms / 1000.0)

        logger.error(f"[HEDGE FAILED] Could not hedge Master #{master_ticket} after {self.retry_attempts} attempts!")
        return None

    def execute_close_pair(self, master_ticket: int, pair_info: Dict[str, Any]) -> bool:
        """
        Closes matching position on Account B when Master position closes.
        """
        slave_ticket = pair_info.get("slave_ticket")
        if not slave_ticket:
            return False

        logger.info(
            f"[SYNC CLOSE] Master #{master_ticket} closed -> Closing matching Slave #{slave_ticket} "
            f"({pair_info.get('symbol_b')} {pair_info.get('slave_type')} {pair_info.get('slave_lot')}L)"
        )

        for attempt in range(1, self.retry_attempts + 1):
            resp = self.connector.close_position_b(ticket=slave_ticket, slippage=self.slippage)
            if resp.get("status") == "OK":
                logger.info(f"[SYNC CLOSE SUCCESS] Slave position #{slave_ticket} closed.")
                self.state_manager.mark_closed(master_ticket)
                return True
            else:
                logger.warning(
                    f"[SYNC CLOSE RETRY {attempt}/{self.retry_attempts}] Failed to close Slave #{slave_ticket}: "
                    f"{resp.get('error')}"
                )
                if attempt < self.retry_attempts:
                    time.sleep(self.retry_delay_ms / 1000.0)

        logger.error(f"[SYNC CLOSE FAILED] Could not close Slave #{slave_ticket}!")
        return False

    def scan_and_sync(self) -> Dict[str, Any]:
        """
        Single scan cycle to detect new master positions and sync closed ones.
        """
        if not self.enabled:
            return {"status": "DISABLED", "new_hedged": 0, "closed_synced": 0}

        # 1. Fetch current positions and accounts
        resp_pos_a = self.connector.get_positions_a()
        if resp_pos_a.get("status") != "OK":
            return {"status": "ERROR_FETCH_A", "error": resp_pos_a.get("error")}

        open_positions_a = resp_pos_a.get("data", [])
        current_a_tickets = {int(p["ticket"]): p for p in open_positions_a}

        # Fetch equity for ratio calculations
        equity_a, equity_b = 1000.0, 1200.0
        acc_a = self.connector.get_account_info_a()
        acc_b = self.connector.get_account_info_b()
        if acc_a.get("status") == "OK":
            equity_a = acc_a["data"].get("equity", 1000.0)
        if acc_b.get("status") == "OK":
            equity_b = acc_b["data"].get("equity", 1200.0)

        new_hedged_count = 0
        closed_synced_count = 0

        # 2. Check for newly opened positions in Account A
        for ticket, pos_a in current_a_tickets.items():
            # SAFETY: Never hedge positions created by Hedger itself (CT# or magic)
            comment_a = str(pos_a.get("comment", ""))
            magic_a = pos_a.get("magic", 0)
            if self.comment_prefix in comment_a or magic_a == self.magic_number:
                continue

            if not self.state_manager.is_master_ticket_hedged(ticket):
                res = self.execute_reverse_order(pos_a=pos_a, equity_a=equity_a, equity_b=equity_b)
                if res:
                    new_hedged_count += 1


        # 3. Check for closed positions in Account A
        if self.sync_close:
            active_pairs = self.state_manager.get_all_open_pairs()
            for master_ticket, pair_info in active_pairs.items():
                if master_ticket not in current_a_tickets:
                    # Master position has closed!
                    if self.execute_close_pair(master_ticket, pair_info):
                        closed_synced_count += 1

        return {
            "status": "OK",
            "open_a_count": len(open_positions_a),
            "new_hedged": new_hedged_count,
            "closed_synced": closed_synced_count,
            "active_hedged_pairs": len(self.state_manager.get_all_open_pairs()),
        }
