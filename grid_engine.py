"""
Grid Trading Engine Module.
Executes autonomous Grid Trading strategy on Account A (Master)
matching the exact GRID_S1, GRID_S2... pattern from the attachment.
"""

import time
import logging
from typing import Dict, Any, List, Optional

from mt5_connector import MT5Connector

logger = logging.getLogger("GridEngine")


class GridEngine:
    def __init__(self, config: Dict[str, Any], connector: MT5Connector, is_test_mode: bool = False):
        self.config = config
        self.connector = connector
        self.is_test_mode = is_test_mode

        grid_cfg = config.get("grid", {})
        self.enabled = grid_cfg.get("enabled", True)
        self.symbol = str(grid_cfg.get("symbol", "xauusd.std"))
        self.direction = str(grid_cfg.get("direction", "SELL")).upper()
        self.initial_lot = float(grid_cfg.get("initial_lot", 0.10))
        self.grid_step_points = float(grid_cfg.get("grid_step_points", 2000.0))
        self.max_layers = int(grid_cfg.get("max_layers", 10))
        self.take_profit_points = float(grid_cfg.get("take_profit_points", 2500.0))
        self.basket_tp_dollars = float(grid_cfg.get("basket_tp_dollars", 50.0))
        self.comment_prefix = str(grid_cfg.get("comment_prefix", "GRID_S"))
        self.magic_number = int(config.get("hedging", {}).get("magic_number", 888999))
        self.slippage = int(config.get("hedging", {}).get("slippage_points", 50))

        self.last_order_time = 0.0

    def get_grid_positions(self) -> List[Dict[str, Any]]:
        """Returns all active positions belonging to this Grid."""
        resp = self.connector.get_positions_a(symbol=self.symbol)
        if resp.get("status") != "OK":
            return []
        positions = resp.get("data", [])
        grid_positions = []
        for p in positions:
            comment = str(p.get("comment", ""))
            if self.comment_prefix in comment or p.get("magic") == self.magic_number:
                grid_positions.append(p)
        return grid_positions

    def check_and_trade(self) -> Dict[str, Any]:
        """
        Main grid evaluation cycle:
        1. Checks current grid layers.
        2. Evaluates exit / take profit conditions.
        3. Opens initial or next grid layer if conditions are met.
        """
        if not self.enabled:
            return {"status": "DISABLED"}

        # Cooldown between orders (at least 2 seconds)
        if time.time() - self.last_order_time < 2.0:
            return {"status": "COOLDOWN"}

        # 1. Fetch current price and auto-resolve gold symbol
        s_info = self.connector.get_symbol_info_a(self.symbol)
        if s_info.get("status") != "OK":
            # Fallback auto-discovery for gold symbol
            for fallback in ["XAUUSD", "xauusd", "GOLD", "xauusd.std", "XAUUSDm"]:
                s_fallback = self.connector.get_symbol_info_a(fallback)
                if s_fallback.get("status") == "OK":
                    self.symbol = fallback
                    s_info = s_fallback
                    break

        if s_info.get("status") != "OK":
            return {"status": "ERROR_SYMBOL_INFO", "error": s_info.get("error")}


        data = s_info.get("data", {})
        bid = float(data.get("bid", 0.0))
        ask = float(data.get("ask", 0.0))
        point = float(data.get("point", 0.01))
        if point <= 0:
            point = 0.01

        current_price = bid if self.direction == "SELL" else ask
        if current_price <= 0:
            return {"status": "INVALID_PRICE"}

        # 2. Get active grid positions
        grid_positions = self.get_grid_positions()
        num_layers = len(grid_positions)

        # 3. Check Basket Take Profit
        total_profit = sum(p.get("profit", 0.0) for p in grid_positions)
        if num_layers > 0 and self.basket_tp_dollars > 0 and total_profit >= self.basket_tp_dollars:
            logger.info(f"[GRID BASKET TP] Total profit ${total_profit:,.2f} reached target ${self.basket_tp_dollars}. Closing all layers on Account A.")
            for p in grid_positions:
                self.connector.close_position_a(ticket=p["ticket"], slippage=self.slippage)
            self.last_order_time = time.time()
            return {"status": "BASKET_TP_CLOSED", "profit": total_profit, "layers": num_layers}

        # 4. If 0 positions: Open Initial Layer (e.g. GRID_S1)
        if num_layers == 0:
            # Auto-scale lot and TP based on Master Balance if available
            acc_a_resp = self.connector.get_account_info_a()
            effective_lot = self.initial_lot
            if acc_a_resp.get("status") == "OK":
                bal_a = float(acc_a_resp.get("data", {}).get("balance", 1000.0))
                if bal_a > 0 and self.config.get("grid", {}).get("auto_scale_lot", True):
                    # Scale proportionally: 0.10 lot per $1000 balance
                    raw_lot = (bal_a / 1000.0) * 0.10
                    effective_lot = max(0.01, min(50.0, round(raw_lot, 2)))
                    # Also scale basket TP proportionally ($31.74 per $1000 balance)
                    self.basket_tp_dollars = round((bal_a / 1000.0) * 31.74, 2)

            comment = f"{self.comment_prefix}1"
            logger.info(f"[GRID INITIAL] Opening initial layer 1: {self.symbol} {self.direction} {effective_lot}L ({comment}) | Target Basket TP: ${self.basket_tp_dollars:,.2f}")
            resp = self.connector.send_order_a(
                symbol=self.symbol,
                order_type=self.direction,
                volume=effective_lot,
                slippage=self.slippage,
                magic=self.magic_number,
                comment=comment,
            )
            if resp.get("status") == "OK":
                self.last_order_time = time.time()
                print(f"🎉 [GRID SUCCESS] Berhasil buka order initial: #{resp['data'].get('ticket')} {self.symbol} {self.direction} {effective_lot}L")
                return {"status": "OPENED_INITIAL", "layer": 1, "ticket": resp["data"].get("ticket")}
            
            err_reason = resp.get("error", "Unknown error")
            print(f"❌ [GRID GAGAL OPEN ORDER] MT5 Menolak Order: {err_reason}")
            logger.error(f"[GRID INITIAL FAILED] {err_reason}")
            return {"status": "ERROR_OPEN", "error": err_reason}



        # 5. If layers exist and below max_layers: Check if price reached next step
        if num_layers < self.max_layers:
            # Sort positions by open price
            prices = [float(p.get("price_open", 0.0)) for p in grid_positions]
            min_price = min(prices)
            max_price = max(prices)

            should_open = False
            step_distance_price = self.grid_step_points * point

            if self.direction == "SELL":
                # For SELL Grid: Next layer opens if price moves away by step distance
                # (either above max price or below min price by step)
                if abs(current_price - min_price) >= step_distance_price and current_price < min_price:
                    should_open = True
                elif abs(current_price - max_price) >= step_distance_price and current_price > max_price:
                    should_open = True
            elif self.direction == "BUY":
                if abs(current_price - min_price) >= step_distance_price and current_price < min_price:
                    should_open = True
                elif abs(current_price - max_price) >= step_distance_price and current_price > max_price:
                    should_open = True

            if should_open:
                next_layer_num = num_layers + 1
                comment = f"{self.comment_prefix}{next_layer_num}"
                logger.info(
                    f"[GRID NEXT LAYER] Opening layer {next_layer_num}: {self.symbol} {self.direction} "
                    f"{self.initial_lot}L at price {current_price} ({comment})"
                )
                resp = self.connector.send_order_a(
                    symbol=self.symbol,
                    order_type=self.direction,
                    volume=self.initial_lot,
                    slippage=self.slippage,
                    magic=self.magic_number,
                    comment=comment,
                )
                if resp.get("status") == "OK":
                    self.last_order_time = time.time()
                    return {"status": "OPENED_NEXT_LAYER", "layer": next_layer_num, "ticket": resp["data"].get("ticket")}

        return {"status": "MONITORING", "layers": num_layers, "total_profit": total_profit}
