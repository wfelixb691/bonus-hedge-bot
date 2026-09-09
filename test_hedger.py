"""
Unit Tests for Dual-MT5 Bonus Hedging Bot.
"""

import os
from lot_calculator import LotCalculator
from state_manager import StateManager
from hedger_engine import HedgerEngine


def test_lot_calculator():
    calc = LotCalculator(mode="multiplier", multiplier=1.1, min_lot=0.01, max_lot=50.0)

    # 0.10 * 1.1 = 0.11 lot (matches user's screenshot)
    lot = calc.calculate_slave_lot(master_lot=0.10)
    assert lot == 0.11, f"Expected 0.11, got {lot}"

    # Min lot clamp
    lot_min = calc.calculate_slave_lot(master_lot=0.005, volume_min=0.01)
    assert lot_min >= 0.01

    # Equity ratio mode
    calc_ratio = LotCalculator(mode="equity_ratio")
    lot_ratio = calc_ratio.calculate_slave_lot(master_lot=0.10, equity_a=1000.0, equity_b=1200.0)
    assert lot_ratio == 0.12, f"Expected 0.12, got {lot_ratio}"
    print("[PASS] LotCalculator tests passed.")


def test_state_manager():
    test_state_file = "test_state_sm.json"
    if os.path.exists(test_state_file):
        os.remove(test_state_file)

    try:
        sm = StateManager(state_file=test_state_file)

        # Add pair
        sm.add_pair(
            master_ticket=13511868,
            slave_ticket=13511869,
            symbol_a="xauusd.std",
            symbol_b="xauusd.std",
            master_type="SELL",
            slave_type="BUY",
            master_lot=0.10,
            slave_lot=0.11,
        )

        assert sm.is_master_ticket_hedged(13511868) is True
        assert sm.get_slave_ticket(13511868) == 13511869
        assert len(sm.get_all_open_pairs()) == 1

        # Test persistence reload
        sm2 = StateManager(state_file=test_state_file)
        assert sm2.is_master_ticket_hedged(13511868) is True
        assert sm2.get_slave_ticket(13511868) == 13511869

        # Mark closed
        sm2.mark_closed(13511868)
        assert sm2.get_slave_ticket(13511868) is None
        assert len(sm2.get_all_open_pairs()) == 0
        print("[PASS] StateManager tests passed.")
    finally:
        if os.path.exists(test_state_file):
            os.remove(test_state_file)


def test_hedger_engine_flow():
    test_state_file = "test_state_engine.json"
    if os.path.exists(test_state_file):
        os.remove(test_state_file)

    try:
        class MockConnector:
            def __init__(self):
                self.sent_orders = []
                self.closed_orders = []

            def get_account_info_a(self):
                return {"status": "OK", "data": {"login": 1001, "equity": 1000.0, "balance": 1000.0}}

            def get_account_info_b(self):
                return {"status": "OK", "data": {"login": 2002, "equity": 1200.0, "balance": 1000.0, "credit": 200.0}}

            def get_positions_a(self, symbol=None):
                return {"status": "OK", "data": []}

            def get_symbol_info_b(self, symbol):
                return {
                    "status": "OK",
                    "data": {
                        "symbol": symbol,
                        "volume_min": 0.01,
                        "volume_max": 50.0,
                        "volume_step": 0.01,
                    },
                }

            def send_order_b(self, **kwargs):
                ticket = 13511869
                self.sent_orders.append({**kwargs, "ticket": ticket})
                return {"status": "OK", "data": {"ticket": ticket, "retcode": 10009}}

            def close_position_b(self, **kwargs):
                self.closed_orders.append(kwargs.get("ticket"))
                return {"status": "OK", "data": {"retcode": 10009}}

        config = {
            "accounts": {
                "account_a": {"name": "Account A", "login": 1001},
                "account_b": {"name": "Account B Bonus", "login": 2002},
            },
            "hedging": {
                "enabled": True,
                "lot_mode": "multiplier",
                "multiplier": 1.1,
                "comment_prefix": "CT#",
                "slippage_points": 50,
                "sync_close": True,
            },
            "symbol_mapping": {
                "xauusd.std": "xauusd.std",
            },
            "monitoring": {
                "state_file": test_state_file,
            },
        }

        mock_conn = MockConnector()
        hedger = HedgerEngine(config=config, connector=mock_conn, is_test_mode=True)

        # Test execute reverse order for Sell 0.10 lot
        pos_a = {
            "ticket": 13511868,
            "symbol": "xauusd.std",
            "type": "SELL",
            "volume": 0.10,
        }

        slave_ticket = hedger.execute_reverse_order(pos_a=pos_a, equity_a=1000.0, equity_b=1200.0)
        assert slave_ticket == 13511869
        assert hedger.state_manager.is_master_ticket_hedged(13511868) is True

        pair = hedger.state_manager.pairs[13511868]
        assert pair["slave_type"] == "BUY"
        assert pair["slave_lot"] == 0.11
        assert mock_conn.sent_orders[0]["comment"] == "CT#13511868"

        # Test close
        closed = hedger.execute_close_pair(13511868, pair)
        assert closed is True
        assert hedger.state_manager.get_slave_ticket(13511868) is None
        assert 13511869 in mock_conn.closed_orders
        print("[PASS] HedgerEngine reverse copy and sync close tests passed.")
    finally:
        if os.path.exists(test_state_file):
            os.remove(test_state_file)


def test_grid_engine_flow():
    from grid_engine import GridEngine

    class MockConnectorGrid:
        def __init__(self):
            self.orders_a = []
            self.closed_a = []

        def get_positions_a(self, symbol=None):
            return {"status": "OK", "data": self.orders_a}

        def get_symbol_info_a(self, symbol):
            return {
                "status": "OK",
                "data": {
                    "symbol": symbol,
                    "bid": 4657.17,
                    "ask": 4657.42,
                    "point": 0.01,
                    "digits": 2,
                },
            }

        def send_order_a(self, **kwargs):
            layer_num = len(self.orders_a) + 1
            ticket = 13511798 + layer_num - 1
            order = {
                "ticket": ticket,
                "symbol": kwargs.get("symbol"),
                "type": kwargs.get("order_type"),
                "volume": kwargs.get("volume"),
                "price_open": 4657.17 if layer_num == 1 else 4636.75,
                "profit": 0.0,
                "comment": kwargs.get("comment"),
                "magic": kwargs.get("magic"),
            }
            self.orders_a.append(order)
            return {"status": "OK", "data": {"ticket": ticket, "retcode": 10009}}

        def close_position_a(self, ticket, **kwargs):
            self.closed_a.append(ticket)
            self.orders_a = [o for o in self.orders_a if o["ticket"] != ticket]
            return {"status": "OK", "data": {"retcode": 10009}}

    config = {
        "grid": {
            "enabled": True,
            "symbol": "xauusd.std",
            "direction": "SELL",
            "initial_lot": 0.10,
            "grid_step_points": 2000,
            "max_layers": 5,
            "basket_tp_dollars": 50.0,
            "comment_prefix": "GRID_S",
        },
        "hedging": {
            "magic_number": 888999,
            "slippage_points": 50,
        },
    }

    mock_conn = MockConnectorGrid()
    ge = GridEngine(config=config, connector=mock_conn, is_test_mode=True)

    # Test initial grid order (GRID_S1)
    res = ge.check_and_trade()
    assert res["status"] == "OPENED_INITIAL"
    assert res["layer"] == 1
    assert mock_conn.orders_a[0]["comment"] == "GRID_S1"
    assert mock_conn.orders_a[0]["volume"] == 0.10

    # Simulate price moving to 4636.75 (step distance reached)
    mock_conn.get_symbol_info_a = lambda symbol: {
        "status": "OK",
        "data": {"symbol": symbol, "bid": 4636.75, "ask": 4637.00, "point": 0.01},
    }
    ge.last_order_time = 0.0  # reset cooldown
    res2 = ge.check_and_trade()
    assert res2["status"] == "OPENED_NEXT_LAYER"
    assert res2["layer"] == 2
    assert mock_conn.orders_a[1]["comment"] == "GRID_S2"

    print("[PASS] GridEngine initial order (GRID_S1) and next layer (GRID_S2) tests passed.")


if __name__ == "__main__":
    test_lot_calculator()
    test_state_manager()
    test_hedger_engine_flow()
    test_grid_engine_flow()
    print("\n✅ ALL TESTS (GRID & HEDGER) PASSED SUCCESSFULLY!")

