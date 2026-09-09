"""
State Manager Module for Dual-MT5 Hedging Bot.
Maintains persistent mapping between Master tickets and Slave hedge tickets.
"""

import json
import os
import threading
from typing import Dict, Any, Optional


class StateManager:
    def __init__(self, state_file: str = "hedge_state.json"):
        self.state_file = state_file
        self._lock = threading.Lock()
        self.pairs: Dict[int, Dict[str, Any]] = {}
        self.load_state()

    def load_state(self) -> None:
        """Loads hedged ticket pairs from disk."""
        with self._lock:
            if os.path.exists(self.state_file):
                try:
                    with open(self.state_file, "r", encoding="utf-8") as f:
                        data = json.load(f)
                        # Ensure keys are integers (tickets)
                        self.pairs = {int(k): v for k, v in data.get("pairs", {}).items()}
                except Exception as e:
                    print(f"[WARN] Error loading state file {self.state_file}: {e}")
                    self.pairs = {}
            else:
                self.pairs = {}

    def save_state(self) -> None:
        """Saves state to disk."""
        with self._lock:
            try:
                parent_dir = os.path.dirname(self.state_file)
                if parent_dir:
                    os.makedirs(parent_dir, exist_ok=True)
                with open(self.state_file, "w", encoding="utf-8") as f:
                    json.dump({"pairs": self.pairs}, f, indent=2)
            except Exception as e:
                print(f"[ERROR] Error saving state file: {e}")


    def add_pair(
        self,
        master_ticket: int,
        slave_ticket: int,
        symbol_a: str,
        symbol_b: str,
        master_type: str,
        slave_type: str,
        master_lot: float,
        slave_lot: float,
        open_time: Optional[str] = None,
    ) -> None:
        """Registers a new hedged pair."""
        with self._lock:
            self.pairs[master_ticket] = {
                "master_ticket": master_ticket,
                "slave_ticket": slave_ticket,
                "symbol_a": symbol_a,
                "symbol_b": symbol_b,
                "master_type": master_type,
                "slave_type": slave_type,
                "master_lot": master_lot,
                "slave_lot": slave_lot,
                "open_time": open_time,
                "status": "OPEN",
            }
        self.save_state()

    def get_slave_ticket(self, master_ticket: int) -> Optional[int]:
        """Returns the slave ticket matching a master ticket."""
        with self._lock:
            pair = self.pairs.get(master_ticket)
            if pair and pair.get("status") == "OPEN":
                return pair.get("slave_ticket")
            return None

    def mark_closed(self, master_ticket: int) -> Optional[Dict[str, Any]]:
        """Marks a pair as closed."""
        with self._lock:
            if master_ticket in self.pairs:
                self.pairs[master_ticket]["status"] = "CLOSED"
                closed_pair = self.pairs[master_ticket]
                self.save_state()
                return closed_pair
            return None

    def is_master_ticket_hedged(self, master_ticket: int) -> bool:
        """Checks if a master ticket is already tracked or hedged."""
        with self._lock:
            return master_ticket in self.pairs

    def get_all_open_pairs(self) -> Dict[int, Dict[str, Any]]:
        """Returns all currently open hedged pairs."""
        with self._lock:
            return {k: v for k, v in self.pairs.items() if v.get("status") == "OPEN"}
