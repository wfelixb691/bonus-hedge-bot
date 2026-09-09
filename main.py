"""
Dual-MT5 Bonus Hedging Bot - Main Entry Point & Dashboard.
"""

import os
import sys
import time
import json
import logging
import argparse
from typing import Dict, Any

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.layout import Layout
    from rich.live import Live
    from rich.text import Text
    HAS_RICH = True
except ImportError:
    HAS_RICH = False

from mt5_connector import MT5Connector
from hedger_engine import HedgerEngine
from grid_engine import GridEngine
from setup_wizard import show_main_interactive_menu, run_interactive_wizard


def setup_logging(log_file: str = "bot_hedger.log"):
    """Sets up logging to file and stream."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )



def load_config(config_path: str = "config.json") -> Dict[str, Any]:
    if not os.path.exists(config_path):
        print(f"[WARN] Config file '{config_path}' tidak ditemukan. Membuka Setup Wizard...")
        return run_interactive_wizard(config_path)
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_dashboard(
    acc_a: Dict[str, Any],
    acc_b: Dict[str, Any],
    open_pairs: Dict[int, Dict[str, Any]],
    pos_a_list: list,
    pos_b_list: list,
    stats: Dict[str, Any],
    grid_status: str = "ACTIVE",
) -> Any:
    """Renders terminal live dashboard."""
    # Account Summary Table
    acc_table = Table(show_header=True, header_style="bold cyan", expand=True)
    acc_table.add_column("Account Role", style="bold")
    acc_table.add_column("Login")
    acc_table.add_column("Balance", justify="right")
    acc_table.add_column("Credit (Bonus)", justify="right", style="bold yellow")
    acc_table.add_column("Equity", justify="right", style="bold green")
    acc_table.add_column("Margin Free", justify="right")

    acc_table.add_row(
        "Master (Grid STP)",
        str(acc_a.get("login", "-")),
        f"${acc_a.get('balance', 0.0):,.2f}",
        f"${acc_a.get('credit', 0.0):,.2f}",
        f"${acc_a.get('equity', 0.0):,.2f}",
        f"${acc_a.get('margin_free', 0.0):,.2f}",
    )
    acc_table.add_row(
        "Hedger (20% Bonus LP)",
        str(acc_b.get("login", "-")),
        f"${acc_b.get('balance', 0.0):,.2f}",
        f"${acc_b.get('credit', 0.0):,.2f}",
        f"${acc_b.get('equity', 0.0):,.2f}",
        f"${acc_b.get('margin_free', 0.0):,.2f}",
    )

    # Hedged Pairs Table
    pair_table = Table(show_header=True, header_style="bold magenta", expand=True)
    pair_table.add_column("Master Ticket", justify="center")
    pair_table.add_column("Symbol", justify="center")
    pair_table.add_column("Type A (Grid)", justify="center")
    pair_table.add_column("Lot A", justify="right")
    pair_table.add_column("Slave Ticket", justify="center")
    pair_table.add_column("Type B (Hedge)", justify="center")
    pair_table.add_column("Lot B", justify="right")
    pair_table.add_column("Status", justify="center", style="bold green")

    total_profit_a = sum(p.get("profit", 0.0) for p in pos_a_list)
    total_profit_b = sum(p.get("profit", 0.0) for p in pos_b_list)
    net_combined_profit = total_profit_a + total_profit_b

    if not open_pairs:
        pair_table.add_row("-", "No active hedged positions", "-", "-", "-", "-", "-", "IDLE")
    else:
        for m_ticket, p in open_pairs.items():
            s_ticket = p.get("slave_ticket", "-")
            type_a_color = "[red]SELL[/red]" if p.get("master_type") == "SELL" else "[green]BUY[/green]"
            type_b_color = "[green]BUY[/green]" if p.get("slave_type") == "BUY" else "[red]SELL[/red]"
            pair_table.add_row(
                str(m_ticket),
                str(p.get("symbol_a")),
                type_a_color,
                f"{p.get('master_lot', 0.0):.2f}",
                str(s_ticket),
                type_b_color,
                f"{p.get('slave_lot', 0.0):.2f}",
                "[bold green]HEDGED[/bold green]",
            )

    # Summary Stats
    profit_style = "bold green" if net_combined_profit >= 0 else "bold red"
    summary_text = (
        f"[bold]Grid Status:[/bold] {grid_status}  |  "
        f"[bold]Active Layers:[/bold] {len(open_pairs)}  |  "
        f"[bold]Master Floating:[/bold] ${total_profit_a:+,.2f}  |  "
        f"[bold]Hedger Floating:[/bold] ${total_profit_b:+,.2f}  |  "
        f"[bold]Net Combined Profit:[/bold] [{profit_style}]${net_combined_profit:+,.2f}[/{profit_style}]"
    )

    content = Layout()
    content.split_column(
        Layout(acc_table, size=6),
        Layout(pair_table, ratio=1),
        Layout(Panel(Text.from_markup(summary_text), style="cyan"), size=3),
    )

    return Panel(
        content,
        title="[bold green]⚡ ALL-IN-ONE DUAL-MT5 GRID & BONUS HEDGING BOT ⚡[/bold green]",
        subtitle="[dim]Press Ctrl+C to Stop Safely[/dim]",
        border_style="bright_blue",
    )


def start_bot_loop(config: Dict[str, Any], is_test_mode: bool = False):
    setup_logging(config.get("monitoring", {}).get("log_file", "bot_hedger.log"))

    # Auto-resolve terminal paths if not provided
    if not is_test_mode and sys.platform == "win32":
        path_a = config.get("accounts", {}).get("account_a", {}).get("terminal_path", "")
        path_b = config.get("accounts", {}).get("account_b", {}).get("terminal_path", "")
        login_a = config.get("accounts", {}).get("account_a", {}).get("login", 100870)
        login_b = config.get("accounts", {}).get("account_b", {}).get("login", 100871)

        if not path_a or not path_b or not os.path.isfile(path_a) or not os.path.isfile(path_b):
            from terminal_scanner import match_terminals_by_login
            found_a, found_b = match_terminals_by_login(login_a, login_b)
            if found_a:
                config["accounts"]["account_a"]["terminal_path"] = found_a
            if found_b:
                config["accounts"]["account_b"]["terminal_path"] = found_b

    print("\nStarting bot engine...")
    connector = MT5Connector(config=config, is_test_mode=is_test_mode)
    connector.start()

    # Safety Handshake: Verify dual accounts before opening trades
    if not is_test_mode:
        time.sleep(1.5)
        resp_a = connector.get_account_info_a()
        resp_b = connector.get_account_info_b()
        act_login_a = resp_a.get("data", {}).get("login", 0)
        act_login_b = resp_b.get("data", {}).get("login", 0)

        if act_login_a == act_login_b and act_login_a > 0:
            print("\n" + "=" * 60)
            print(f"❌ PERINGATAN: KEDUA TERMINAL TERHUBUNG KE AKUN YANG SAMA ({act_login_a})!")
            print("   Bot dicegah membuka posisi agar tidak terjadi tabrakan/loop.")
            print("   Pastikan MT5 Master 100870 dan Slave 100871 dibuka dari 2 folder berbeda.")
            print("=" * 60 + "\n")
            connector.stop()
            return

    grid_engine = GridEngine(config=config, connector=connector, is_test_mode=is_test_mode)
    hedger = HedgerEngine(config=config, connector=connector, is_test_mode=is_test_mode)
    scan_interval = config.get("monitoring", {}).get("scan_interval_ms", 100) / 1000.0



    try:
        if HAS_RICH:
            console = Console()
            with Live(console=console, refresh_per_second=4, screen=False) as live:
                while True:
                    grid_res = grid_engine.check_and_trade()
                    sync_res = hedger.scan_and_sync()

                    resp_acc_a = connector.get_account_info_a()
                    resp_acc_b = connector.get_account_info_b()
                    resp_pos_a = connector.get_positions_a()
                    resp_pos_b = connector.get_positions_b()

                    acc_a = resp_acc_a.get("data", {}) if resp_acc_a.get("status") == "OK" else {}
                    acc_b = resp_acc_b.get("data", {}) if resp_acc_b.get("status") == "OK" else {}
                    pos_a = resp_pos_a.get("data", []) if resp_pos_a.get("status") == "OK" else []
                    pos_b = resp_pos_b.get("data", []) if resp_pos_b.get("status") == "OK" else []

                    open_pairs = hedger.state_manager.get_all_open_pairs()
                    dashboard_panel = build_dashboard(
                        acc_a=acc_a,
                        acc_b=acc_b,
                        open_pairs=open_pairs,
                        pos_a_list=pos_a,
                        pos_b_list=pos_b,
                        stats=sync_res,
                        grid_status=grid_res.get("status", "ACTIVE"),
                    )
                    live.update(dashboard_panel)
                    time.sleep(scan_interval)
        else:
            print("[INFO] Bot running in standard console mode. Press Ctrl+C to exit.")
            last_print = 0
            while True:
                grid_res = grid_engine.check_and_trade()
                sync_res = hedger.scan_and_sync()
                if time.time() - last_print > 2.0:
                    open_pairs = hedger.state_manager.get_all_open_pairs()
                    resp_acc_a = connector.get_account_info_a()
                    resp_acc_b = connector.get_account_info_b()
                    eq_a = resp_acc_a.get("data", {}).get("equity", 0.0)
                    eq_b = resp_acc_b.get("data", {}).get("equity", 0.0)
                    print(
                        f"[{time.strftime('%H:%M:%S')}] Grid: {grid_res.get('status')} | "
                        f"Active Pairs: {len(open_pairs)} | Equity A: ${eq_a:,.2f} | Equity B: ${eq_b:,.2f}"
                    )
                    last_print = time.time()
                time.sleep(scan_interval)

    except KeyboardInterrupt:
        print("\n[Stopping] Stopping bot cleanly...")
    finally:
        connector.stop()
        print("[Done] Bot stopped.")


from terminal_scanner import auto_detect_and_configure


def main():
    parser = argparse.ArgumentParser(description="All-in-One Dual-MT5 Grid & Bonus Hedging Controller")
    parser.add_argument("--config", default="config.json", help="Path to config.json")
    parser.add_argument("--test-mode", action="store_true", help="Run in mock/test mode without live MT5")
    parser.add_argument("--wizard", action="store_true", help="Launch interactive setup wizard directly")
    parser.add_argument("--auto", action="store_true", help="Start directly without interactive menu")
    args = parser.parse_args()

    config_path = args.config

    if args.wizard:
        run_interactive_wizard(config_path)
        return

    if args.auto or args.test_mode:
        config = load_config(config_path)
        start_bot_loop(config=config, is_test_mode=args.test_mode)
        return

    # Interactive Menu
    while True:
        choice = show_main_interactive_menu()
        if choice == "1":
            if not os.path.exists(config_path):
                print("\n🔍 [1-Click Auto] Mendeteksi terminal MT5 otomatis...")
                config, _ = auto_detect_and_configure()
                with open(config_path, "w", encoding="utf-8") as f:
                    json.dump(config, f, indent=2)
            else:
                config = load_config(config_path)

            start_bot_loop(config=config, is_test_mode=False)
            break
        elif choice == "2":
            run_interactive_wizard(config_path)
        elif choice == "3":
            config = load_config(config_path)
            start_bot_loop(config=config, is_test_mode=True)
            break
        elif choice == "4":
            print("\nSampai jumpa!")
            break
        else:
            print("\nPilihan tidak valid.")


if __name__ == "__main__":
    main()




