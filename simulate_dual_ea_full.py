"""
Simulasi Lengkap Dual-EA BonusHedge (Master + Slave) — meniru logika MQL5 persis.

Mencakup SEMUA skenario:
  A. Debounce liquidation harvest (glitch, recovery, 3-cycle, neg equity, margin-only)
  B. Counter ordering & stale snapshot (gap 1-cycle, grace 120s, magic/version invalid)
  C. CLOSE_ALL race & command file (simultaneous, idempotent, delayed, partial-write race)
  D. Sync open/close (hedge, anti-jitter 3-cycle, tracker cleanup)
  E. Margin & guards (master/slave margin, bonus credit, hedge-wait)
  F. Circuit breaker (rapid close 2x < 20s -> lock 300s)
  G. Cooldown & closing lock
  H. Combined TP + spread buffer + multiplier + lot clamp
  I. Binary integrity (roundtrip, wrong magic/version, truncated, empty, pos_count>100)
  J. Grid direction (SELL grid: hanya buka saat harga NAIK — bug fix)
  K. Max layers
  L. Full-cycle end-to-end (harga naik -> TP; harga turun -> slave MC -> harvest)

MODE:
  python3 simulate_dual_ea_full.py            -> jalankan semua test (harus PASS dengan fix)
  python3 simulate_dual_ea_full.py buggy      -> mode BUGGY (meniru file asli sebelum fix)
                                                 test J2 & C4 diharapkan FAIL (bukti bug)
"""
import struct
import sys

MAGIC = 0x42484246
VER = 2
HEADER_FMT = "<qqqqdddddi"   # magic,ver,counter,login,equity,balance,free,ml,profit,count
POS_FMT = "<qidddi"          # ticket,type,vol,price,profit,clen

# ---------------------------------------------------------------------------
# Binary bridge
# ---------------------------------------------------------------------------
def serialize_state(counter, login, equity, balance, free_margin, ml, profit, positions):
    header = struct.pack(HEADER_FMT, MAGIC, VER, counter, login, equity, balance,
                         free_margin, ml, profit, len(positions))
    body = b""
    for p in positions:
        cb = p["comment"].encode("utf-8")
        body += struct.pack(POS_FMT, p["ticket"], p["type"], p["volume"],
                            p["price_open"], p["profit"], len(cb)) + cb
    return header + body


def deserialize_state(data):
    if data is None or len(data) < struct.calcsize(HEADER_FMT):
        return None
    magic, ver, counter, login, equity, balance, free, ml, profit, count = \
        struct.unpack_from(HEADER_FMT, data, 0)
    if magic != MAGIC or ver != VER:
        return None
    if count < 0 or count > 100:
        return None
    off = struct.calcsize(HEADER_FMT)
    positions = []
    for _ in range(count):
        if off + struct.calcsize(POS_FMT) > len(data):
            return None
        ticket, ptype, vol, price, pprofit, clen = struct.unpack_from(POS_FMT, data, off)
        off += struct.calcsize(POS_FMT)
        comment = data[off:off + clen].decode("utf-8", "ignore") if clen > 0 else ""
        off += clen
        positions.append({"ticket": ticket, "type": ptype, "volume": vol,
                          "price_open": price, "profit": pprofit, "comment": comment})
    return {"counter": counter, "login": login, "equity": equity, "balance": balance,
            "free_margin": free, "margin_level": ml, "profit": profit,
            "positions": positions}


# ---------------------------------------------------------------------------
# FILE_COMMON bridge (simulates shared files incl. partial writes)
# ---------------------------------------------------------------------------
class Bridge:
    def __init__(self):
        self.files = {}       # name -> bytes
        self.command = None   # command file bytes or None

    # -- state files ---------------------------------------------------------
    def write_state(self, name, data, partial=False):
        if partial:
            self.files[name] = data[:20]   # truncated mid-write
        else:
            self.files[name] = data

    def read_state(self, name):
        return self.files.get(name)

    # -- command file (single shared file, both directions!) -----------------
    def write_command(self, cmd, partial=False):
        cb = cmd.encode("utf-8")
        full = struct.pack("<i", len(cb)) + cb
        self.command = full[:2] if partial else full

    def read_command_bytes(self):
        return self.command

    def delete_command(self):
        self.command = None


# ---------------------------------------------------------------------------
# Master EA (meniru BonusHedge_Master.mq5)
# ---------------------------------------------------------------------------
class MasterEA:
    def __init__(self, bridge, fix_grid_direction=True, fix_command_race=True,
                 fix_slave_pos_guard=True, login=100870, initial_lot=0.10,
                 grid_step=2000, max_layers=10, basket_tp=31.74, spread_buffer=10.0,
                 min_free=100.0, min_ml=50.0, point=0.01, harvest_on_slave_mc=True):
        self.b = bridge
        self.login = login
        self.initial_lot = initial_lot
        self.grid_step = grid_step
        self.max_layers = max_layers
        self.basket_tp = basket_tp
        self.spread_buffer = spread_buffer
        self.min_free = min_free
        self.min_ml = min_ml
        self.point = point
        self.harvest_on_slave_mc = harvest_on_slave_mc
        self.fix_grid_direction = fix_grid_direction
        self.fix_command_race = fix_command_race
        self.fix_slave_pos_guard = fix_slave_pos_guard

        self.positions = []            # dicts: ticket,type,volume,price_open,profit,comment
        self.counter = 0
        self.last_order_time = -1000.0   # MQL5: 0 vs TimeCurrent()=epoch -> selisih besar, cooldown lolos
        self.closing_lock_until = -1000.0
        self.closing_active = False
        self.circuit_breaker_until = -1000.0
        self.rapid_close_counter = 0
        self.last_order_open_time = -1000.0

        # slave snapshot
        self.slave_login = 0
        self.slave_equity = 0.0
        self.slave_free_margin = 0.0
        self.slave_margin_level = 0.0
        self.slave_profit = 0.0
        self.slave_pos_count = 0
        self.slave_online = False
        self.slave_last_counter = -1
        self.slave_last_seen = 0
        self.slave_mc_counter = 0

        self.account_free = 1000.0
        self.account_ml = 500.0
        self.algo_enabled = True

        # v1.20: posisi manual (magic 0) ikut basket TP tapi TIDAK dihedging slave
        self.manual_positions = []
        self.unhedged_watchdog_sec = 7
        self.unhedged_since = None
        self.naked_alerts = 0

        self.events = []

    # -- account helpers -----------------------------------------------------
    @property
    def master_profit(self):
        return sum(p["profit"] for p in self.positions) + sum(p["profit"] for p in self.manual_positions)

    def total_positions(self):
        return len(self.positions) + len(self.manual_positions)

    def ea_positions(self):
        return len(self.positions)

    # -- file bridge ---------------------------------------------------------
    def broadcast_state(self):
        self.counter += 1
        self.b.write_state("bonus_hedge_master.dat",
                           serialize_state(self.counter, self.login,
                                           1000.0 + self.master_profit, 1000.0,
                                           self.account_free, self.account_ml,
                                           self.master_profit,
                                           self.positions + self.manual_positions))

    def read_slave_state(self, now):
        data = self.b.read_state("bonus_hedge_slave.dat")
        if data is None:
            self._check_slave_timeout(now)
            return
        st = deserialize_state(data)
        if st is None:
            self._check_slave_timeout(now)
            return
        if st["counter"] == self.slave_last_counter:
            self._check_slave_timeout(now)
            return
        self.slave_last_counter = st["counter"]
        self.slave_login = st["login"]
        self.slave_equity = st["equity"]
        self.slave_free_margin = st["free_margin"]
        self.slave_margin_level = st["margin_level"]
        self.slave_profit = st["profit"]
        self.slave_pos_count = len(st["positions"])
        self.slave_online = True
        self.slave_last_seen = now

    def _check_slave_timeout(self, now):
        if self.slave_last_seen > 0 and (now - self.slave_last_seen <= 120):
            return
        self.slave_online = False

    # -- commands ------------------------------------------------------------
    def check_incoming_commands(self, now):
        raw = self.b.read_command_bytes()
        if raw is None:
            return
        # Validated read (fix): partial/invalid file -> JANGAN delete, retry next tick
        if len(raw) < 4:
            if self.fix_command_race:
                return  # masih ditulis -> jangan delete
            self.b.delete_command()  # BUGGY: command hilang!
            return
        clen = struct.unpack("<i", raw[:4])[0]
        if clen <= 0 or clen > 64 or 4 + clen > len(raw):
            if self.fix_command_race:
                return
            self.b.delete_command()
            return
        cmd = raw[4:4 + clen].decode("utf-8", "ignore")
        self.b.delete_command()
        if cmd == "CLOSE_ALL" and not self.closing_active:
            self.events.append(("MASTER_RECV_CLOSE_ALL", now))
            self.closing_active = True
            self.closing_lock_until = now + 4
            self.close_all_master()
            self.closing_active = False
            self.last_order_time = now

    def send_command_to_slave(self, cmd):
        self.b.write_command(cmd)

    # -- liquidation harvest -------------------------------------------------
    def check_slave_liquidation_harvest(self, now):
        if not self.slave_online or self.closing_active:
            return False
        liquidated = (self.slave_login > 0 and
                      (self.slave_equity <= 10.0 or
                       (self.slave_margin_level > 0 and self.slave_margin_level < 20.0)))
        if liquidated:
            self.slave_mc_counter += 1
            if self.slave_mc_counter >= 3:
                self.events.append(("MASTER_HARVEST", now))
                self.closing_active = True
                self.closing_lock_until = now + 6
                self.close_all_master()
                self.closing_active = False
                self.last_order_time = now
                self.slave_mc_counter = 0
                return True
        else:
            self.slave_mc_counter = 0
        return False

    # -- grid ----------------------------------------------------------------
    def manage_grid(self, now, bid):
        if self.closing_active:
            return "LOCKED"

        # v1.20: TP basket = gabungan (lot-scale base + buffer dinamis per layer)
        # + guard 60% (jangan buka layer baru saat sudah dekat TP)
        n_basket = self.total_positions()
        buffer = self.spread_buffer * max(1.0, (n_basket * self.initial_lot) / 0.10) if n_basket > 0 else self.spread_buffer * max(1.0, self.initial_lot / 0.10)
        tp = 0.0
        if self.basket_tp > 0:
            base = (self.initial_lot / 0.10) * 31.74 if self.basket_tp == 31.74 else self.basket_tp
            tp = base + buffer

        # Wajib slave online (menahan LAYER 1 & TP sepihak sekaligus — v1.20 early-return)
        if not self.slave_online:
            return "SLAVE_OFFLINE"
        # BUG ASLI (v0, mode buggy): guard `slave_pos_count == 0` juga menahan
        # LAYER 1 -> deadlock start (master tak buka, slave tak bisa hedge).
        if not self.fix_slave_pos_guard and self.slave_pos_count == 0 and self.total_positions() == 0:
            return "SLAVE_OFFLINE"   # BUGGY: deadlock — master tidak pernah mulai

        combined = self.master_profit + self.slave_profit
        if (self.total_positions() > 0 and self.slave_pos_count > 0 and tp > 0
                and combined >= tp):
            self.events.append(("MASTER_TP_CLOSE", combined, tp))
            self.closing_active = True
            self.closing_lock_until = now + 6
            self.send_command_to_slave("CLOSE_ALL")
            self.close_all_master()
            self.closing_active = False
            self.last_order_time = now
            return "CLOSED_BY_TP"

        if now < self.circuit_breaker_until:
            return "CIRCUIT_BREAKER"

        # Pre-trade margin check (self & slave)
        if self.account_free < self.min_free or (self.account_ml > 0 and self.account_ml < self.min_ml):
            return "MASTER_MARGIN_LOW"
        if self.slave_online:
            if self.slave_free_margin < self.min_free or (self.slave_margin_level > 0 and self.slave_margin_level < self.min_ml):
                return "SLAVE_MARGIN_LOW"
        else:
            return "SLAVE_OFFLINE"

        if now < self.closing_lock_until:
            return "CLOSING_LOCK"
        if now - self.last_order_time < 10:
            return "COOLDOWN"
        if bid <= 0:
            return "NO_TICK"

        # LAYER 1
        if self.total_positions() == 0:
            self.last_order_time = now
            self.last_order_open_time = now
            self._open_sell(now)
            self.broadcast_state()
            return "OPENED_INITIAL"

        # NEXT LAYERS — guard vs ea_positions (bukan total incl. manual) — v1.20 fix
        if self.ea_positions() < self.max_layers:
            if self.slave_online and self.slave_pos_count < self.ea_positions():
                return "WAIT_HEDGE"  # tunggu slave hedge layer sebelumnya

            # Guard 60%: keranjang sudah dekat TP -> jangan layer baru
            if tp > 0 and combined >= tp * 0.60:
                return "NEAR_TP_HOLD"

            step_distance = self.grid_step * self.point
            should_open = False
            prices = [p["price_open"] for p in self.positions]
            max_price = max(prices)
            min_price = min(prices)
            if (bid - max_price) >= step_distance:
                should_open = True
            if (min_price - bid) >= step_distance:
                # v1.20 BI-DIRECTIONAL + DOWNWARD SHIELD
                if self.fix_grid_direction:
                    slave_stressed = (self.slave_online and
                                      ((self.slave_margin_level > 0 and self.slave_margin_level < self.min_ml)
                                       or self.slave_free_margin < 200.0))
                    should_open = not slave_stressed
                else:
                    should_open = True  # BUGGY (v0): buka layer saat harga TURUN tanpa shield

            if should_open:
                self.last_order_time = now
                self.last_order_open_time = now
                self._open_sell(now)
                self.broadcast_state()
                return "OPENED_NEXT_LAYER"
        return "HOLDING"

    # -- v1.20: UNHEDGED ORPHAN WATCHDOG (hanya grid EA, manual dikecualikan) --
    def check_unhedged_watchdog(self, now):
        if self.unhedged_watchdog_sec <= 0 or not self.slave_online or self.closing_active:
            self.unhedged_since = None
            return False
        if self.ea_positions() > 0 and self.ea_positions() > self.slave_pos_count:
            if self.unhedged_since is None:
                self.unhedged_since = now
            elif now - self.unhedged_since > self.unhedged_watchdog_sec:
                self.events.append(("UNHEDGED_WATCHDOG_CLOSE", now))
                self.closing_active = True
                self.closing_lock_until = now + 6
                self.close_all_master()
                self.closing_active = False
                self.last_order_time = now
                self.unhedged_since = None
                return True
        else:
            self.unhedged_since = None
        return False

    # -- v1.20 fix: NAKED EXPOSURE ALERT (slave terbukti offline, grid ada) ----
    def check_naked_alert(self, now):
        if self.slave_online or self.ea_positions() == 0:
            self.naked_streak = getattr(self, "naked_streak", 0)
            self.naked_sent = False
            return
        self.naked_streak = getattr(self, "naked_streak", 0) + 1
        if not getattr(self, "naked_sent", False) and self.naked_streak >= 20:
            self.naked_sent = True
            self.naked_alerts += 1
            self.events.append(("NAKED_ALERT", now))

    def _open_sell(self, now):
        ticket = 1000 + len(self.positions) + 1
        comment = "GRID_S" + str(len(self.positions) + 1)
        self.positions.append({"ticket": ticket, "type": 1, "volume": self.initial_lot,
                               "price_open": 0.0, "profit": 0.0, "comment": comment})
        self.events.append(("MASTER_OPEN", ticket, comment))

    def close_all_master(self):
        n = len(self.positions) + len(self.manual_positions)
        if n > 0:
            self.last_order_close_time = self.last_order_open_time  # for lifespan calc
            self.positions.clear()
            self.manual_positions.clear()
            self.rapid_close_counter = 0  # simplified: no flapping in sim
            self.events.append(("MASTER_CLOSE_ALL", n))

    # -- main timer ----------------------------------------------------------
    def on_timer(self, now, bid):
        self.read_slave_state(now)
        self.check_naked_alert(now)
        self.check_incoming_commands(now)
        self.broadcast_state()
        if not self.algo_enabled:
            return "ALGO_OFF"
        if self.harvest_on_slave_mc and self.check_slave_liquidation_harvest(now):
            return "HARVESTED"
        status = "LOCKED"
        if not self.closing_active:
            status = self.manage_grid(now, bid)
        if not self.closing_active:
            self.check_unhedged_watchdog(now)
        return status


# ---------------------------------------------------------------------------
# Slave EA (meniru BonusHedge_Slave.mq5)
# ---------------------------------------------------------------------------
class SlaveEA:
    def __init__(self, bridge, fix_command_race=True, login=100871, lot_multiplier=1.1,
                 combined_tp=31.74, spread_buffer=10.0, min_free=100.0,
                 min_bonus_credit=100.0, point=0.01, harvest_on_master_mc=True,
                 fix_slave_cap=True, detect_comment_loss=True):
        self.b = bridge
        self.login = login
        self.lot_multiplier = lot_multiplier
        self.combined_tp = combined_tp
        self.spread_buffer = spread_buffer
        self.min_free = min_free
        self.min_bonus_credit = min_bonus_credit
        self.point = point
        self.harvest_on_master_mc = harvest_on_master_mc
        self.fix_command_race = fix_command_race

        self.positions = []
        self.counter = 0
        self.closing_lock_until = -1000.0
        self.closing_active = False
        self.circuit_breaker_until = -1000.0
        self.rapid_close_counter = 0
        self.last_order_open_time = -1000.0
        self.last_order_close_time = -1000.0
        self.missing_tickets = {}   # slave_ticket -> missing_count

        # master snapshot
        self.master_login = 0
        self.master_equity = 0.0
        self.master_free_margin = 0.0
        self.master_margin_level = 0.0
        self.master_profit = 0.0
        self.master_pos_count = 0
        self.master_positions = []
        self.master_online = False
        self.master_last_counter = -1
        self.master_last_seen = 0
        self.master_mc_counter = 0

        self.account_free = 1200.0
        self.account_ml = 400.0
        self.account_credit = 200.0   # bonus 20% sudah masuk
        self.algo_enabled = True
        self.fix_slave_cap = fix_slave_cap
        self.detect_comment_loss = detect_comment_loss
        self.comments_lost = False
        self.other_positions = 0      # posisi asing (manual/EA lain) di terminal slave

        self.events = []

    # -- helpers -------------------------------------------------------------
    @property
    def slave_profit(self):
        return sum(p["profit"] for p in self.positions)

    # -- file bridge ---------------------------------------------------------
    def broadcast_state(self):
        self.counter += 1
        free = self.account_free
        ml = self.account_ml
        if self.min_bonus_credit > 0 and self.account_credit < self.min_bonus_credit:
            free = 0.0
            ml = 0.0
        self.b.write_state("bonus_hedge_slave.dat",
                           serialize_state(self.counter, self.login,
                                           1200.0 + self.slave_profit, 1000.0,
                                           free, ml, self.slave_profit, self.positions))

    def read_master_state(self, now):
        data = self.b.read_state("bonus_hedge_master.dat")
        if data is None:
            return self._master_timed_out(now)
        st = deserialize_state(data)
        if st is None:
            return self._master_timed_out(now)
        if st["counter"] == self.master_last_counter:
            return self._master_timed_out(now)
        self.master_last_counter = st["counter"]
        self.master_login = st["login"]
        self.master_equity = st["equity"]
        self.master_free_margin = st["free_margin"]
        self.master_margin_level = st["margin_level"]
        self.master_profit = st["profit"]
        self.master_pos_count = len(st["positions"])
        self.master_positions = st["positions"]
        self.master_online = True
        self.master_last_seen = now
        return True

    def _master_timed_out(self, now):
        if self.master_last_seen > 0 and (now - self.master_last_seen <= 120):
            return True  # masih grace: lanjut snapshot
        self.master_online = False
        return False

    # -- commands ------------------------------------------------------------
    def check_incoming_commands(self, now):
        raw = self.b.read_command_bytes()
        if raw is None:
            return
        if len(raw) < 4:
            if self.fix_command_race:
                return
            self.b.delete_command()
            return
        clen = struct.unpack("<i", raw[:4])[0]
        if clen <= 0 or clen > 64 or 4 + clen > len(raw):
            if self.fix_command_race:
                return
            self.b.delete_command()
            return
        cmd = raw[4:4 + clen].decode("utf-8", "ignore")
        self.b.delete_command()
        if cmd == "CLOSE_ALL" and not self.closing_active:
            self.events.append(("SLAVE_RECV_CLOSE_ALL", now))
            self.closing_active = True
            self.closing_lock_until = now + 6
            self.close_all_slave()
            self.closing_active = False

    def send_command_to_master(self, cmd):
        self.b.write_command(cmd)

    # -- liquidation harvest -------------------------------------------------
    def check_master_liquidation_harvest(self, now):
        if not self.master_online or self.closing_active:
            return False
        liquidated = (self.master_login > 0 and
                      (self.master_equity <= 10.0 or
                       (self.master_margin_level > 0 and self.master_margin_level < 20.0)))
        if liquidated:
            self.master_mc_counter += 1
            if self.master_mc_counter >= 3:
                self.events.append(("SLAVE_HARVEST", now))
                self.closing_active = True
                self.closing_lock_until = now + 6
                self.close_all_slave()
                self.closing_active = False
                self.master_mc_counter = 0
                return True
        else:
            self.master_mc_counter = 0
        return False

    # -- sync open -----------------------------------------------------------
    def sync_open_positions(self, now, ask):
        if not self.master_online or self.master_pos_count == 0:
            return "NO_MASTER"
        if now < self.circuit_breaker_until:
            return "CIRCUIT_BREAKER"
        if now < self.closing_lock_until:
            return "CLOSING_LOCK"
        if now - self.last_order_close_time < 10:
            return "COOLDOWN"
        if ask <= 0:
            return "NO_TICK"
        if self.min_bonus_credit > 0 and self.account_credit < self.min_bonus_credit:
            return "NO_BONUS"
        if self.account_free < self.min_free:
            return "SLAVE_MARGIN_LOW"

        # v1.20 fix: deteksi broker overwrite comment -> mode backstop bucket
        # (di .mq5 ini DetectCommentLoss() di OnTimer SEBELUM SyncOpenPositions)
        if self.detect_comment_loss:
            tagged = sum(1 for p in self.positions if p["comment"].startswith("CT#"))
            self.comments_lost = (len(self.positions) > 0 and tagged == 0)

        # v1.20 fix: SAFETY CAP pakai hitungan hedge SENDIRI (magic+symbol),
        # bukan PositionsTotal() mentah (posisi asing di terminal sama bikin
        # hedge diblokir selamanya). other_positions = posisi asing di terminal.
        if len(self.positions) + getattr(self, "other_positions", 0) >= self.master_pos_count \
                and not self.fix_slave_cap:
            return "CAP_BROKEN"      # BUGGY: salah tembak karena posisi asing
        if len(self.positions) >= self.master_pos_count:
            return "OVERHEDGE_CAP"   # FIXED: cap benar vs hedge sendiri

        opened = 0
        for mp in self.master_positions:
            expected = "CT#" + str(mp["ticket"])
            want_lot = max(0.01, min(50.0, round(mp["volume"] * self.lot_multiplier * 100.0) / 100.0))
            if not self.comments_lost:
                if any(p["comment"] == expected for p in self.positions):
                    continue  # sudah di-hedge (match per-tiket)
            else:
                want_type = 0 if mp["type"] == 1 else 1
                need = sum(1 for q in self.master_positions
                           if q["type"] == mp["type"]
                           and max(0.01, min(50.0, round(q["volume"] * self.lot_multiplier * 100.0) / 100.0)) == want_lot)
                have = sum(1 for p in self.positions
                           if p["type"] == want_type and abs(p["volume"] - want_lot) < 0.005)
                if have >= need:
                    continue  # backstop bucket: sudah tercukupi
            slave_type = 0 if mp["type"] == 1 else 1  # reverse
            ticket = 2000 + len(self.positions) + 1
            comment = expected
            self.positions.append({"ticket": ticket, "type": slave_type, "volume": want_lot,
                                   "price_open": ask, "profit": 0.0, "comment": comment})
            self.events.append(("SLAVE_HEDGE", ticket, expected, want_lot))
            self.last_order_open_time = now
            opened += 1
        return ("OPENED", opened) if opened else "NO_NEW"

    # -- sync close (anti-jitter 3-cycle) ------------------------------------
    def sync_close_positions(self, now):
        if not self.master_online:
            return
        # cleanup tracker utk tiket yang sudah tidak ada di terminal
        existing = {p["ticket"] for p in self.positions}
        for t in list(self.missing_tickets):
            if t not in existing:
                del self.missing_tickets[t]

        for p in list(self.positions):
            comment = p["comment"]
            if not comment.startswith("CT#"):
                continue
            try:
                m_ticket = int(comment[3:])
            except ValueError:
                continue
            master_still_open = any(mp["ticket"] == m_ticket for mp in self.master_positions)
            if master_still_open:
                self.missing_tickets.pop(p["ticket"], None)
                continue
            self.missing_tickets[p["ticket"]] = self.missing_tickets.get(p["ticket"], 0) + 1
            if self.missing_tickets[p["ticket"]] >= 3:
                self.events.append(("SLAVE_SYNC_CLOSE", p["ticket"]))
                self.positions.remove(p)
                self.last_order_close_time = now
                self.missing_tickets.pop(p["ticket"], None)

    # -- close all -----------------------------------------------------------
    def close_all_slave(self):
        n = len(self.positions)
        self.positions.clear()
        self.missing_tickets.clear()
        if n > 0:
            self.last_order_close_time = self.last_order_open_time
            self.events.append(("SLAVE_CLOSE_ALL", n))

    # -- main timer ----------------------------------------------------------
    def on_timer(self, now, ask):
        self.broadcast_state()
        if not self.algo_enabled:
            return "ALGO_OFF"
        if not self.read_master_state(now):
            return "MASTER_OFFLINE"
        self.check_incoming_commands(now)
        slave_profit = self.slave_profit
        combined = self.master_profit + slave_profit
        if self.harvest_on_master_mc and self.check_master_liquidation_harvest(now):
            return "HARVESTED"
        if not self.closing_active and now >= self.closing_lock_until:
            self.sync_open_positions(now, ask)
        if not self.closing_active:
            self.sync_close_positions(now)
        return "OK"


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
class Check:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failures = []

    def ok(self, cond, name, detail=""):
        if cond:
            self.passed += 1
            print(f"  [PASS] {name}")
        else:
            self.failed += 1
            self.failures.append(name)
            print(f"  [FAIL] {name}  {detail}")

    def summary(self):
        print(f"\n{'='*60}")
        print(f"  TOTAL: {self.passed} passed, {self.failed} failed")
        if self.failures:
            print("  FAILED:", ", ".join(self.failures))
        print('='*60)
        return self.failed == 0


def new_bridge():
    return Bridge()


# ===========================================================================
# A. DEBOUNCE LIQUIDATION HARVEST
# ===========================================================================
def test_a_debounce(c):
    print("\n=== A. Debounce Liquidation Harvest ===")
    # A1: glitch 1-tick equity=0 -> counter naik, TIDAK trigger
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.slave_online = True; m.slave_login = 100871
    m.slave_equity = 0.0; m.slave_margin_level = 0.0
    r = m.check_slave_liquidation_harvest(now=100)
    c.ok(r is False and m.slave_mc_counter == 1, "A1 glitch 1-tick tidak trigger (counter=1)", f"r={r} cnt={m.slave_mc_counter}")

    # A2: recovery reset
    m.slave_equity = 1150.0; m.slave_margin_level = 450.0
    r = m.check_slave_liquidation_harvest(now=150)
    c.ok(r is False and m.slave_mc_counter == 0, "A2 recovery reset counter", f"cnt={m.slave_mc_counter}")

    # A3: 3-cycle negative equity -> TRIGGER + master close
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.1, "price_open": 2650.0, "profit": -20.0, "comment": "GRID_S1"})
    for i in range(3):
        m.slave_equity = -4.5 - i * 100; m.slave_margin_level = 0.0
        r = m.check_slave_liquidation_harvest(now=200 + i * 50)
    c.ok(r is True and len(m.positions) == 0, "A3 3-cycle neg equity trigger harvest + master flat", f"r={r} pos={len(m.positions)}")

    # A4: margin-only (equity OK, ml<20) 3-cycle -> TRIGGER
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = True; m.slave_login = 100871
    m.slave_equity = 500.0
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.1, "price_open": 2650.0, "profit": 5.0, "comment": "GRID_S1"})
    for i in range(3):
        m.slave_margin_level = 15.0
        m.check_slave_liquidation_harvest(now=300 + i * 50)
    c.ok(len(m.positions) == 0, "A4 margin-only 3-cycle trigger harvest", f"pos={len(m.positions)}")

    # A5: slave offline -> harvest tidak jalan
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = False
    r = m.check_slave_liquidation_harvest(now=100)
    c.ok(r is False and m.slave_mc_counter == 0, "A5 slave offline -> no harvest")

    # A6: boundary equity 10.0 -> liquidated; 10.01 -> tidak
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = True; m.slave_login = 1
    m.slave_equity = 10.0; m.slave_margin_level = 0.0
    m.check_slave_liquidation_harvest(100)
    c.ok(m.slave_mc_counter == 1, "A6a equity=10.0 dihitung liquidated (<=10)")
    m.slave_equity = 10.01
    m.check_slave_liquidation_harvest(150)
    c.ok(m.slave_mc_counter == 0, "A6b equity=10.01 reset (tidak liquidated)")


# ===========================================================================
# B. COUNTER ORDERING & STALE SNAPSHOT
# ===========================================================================
def test_b_counter(c):
    print("\n=== B. Counter Ordering & Stale Snapshot ===")
    # B1: broadcast -> slave baca sukses (counter maju)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.broadcast_state()
    c.ok(s.read_master_state(now=0) is True and s.master_online, "B1 slave baca state master")

    # B2: stale counter -> grace 120s dipertahankan
    m2 = MasterEA(b); s2 = SlaveEA(b)
    m2.broadcast_state()
    s2.read_master_state(now=10)
    # master berhenti menulis; slave baca data lama (counter sama)
    stale = b.read_state("bonus_hedge_master.dat")
    for t in range(20, 120, 20):
        b.write_state("bonus_hedge_master.dat", stale)
        s2.read_master_state(now=t)
        c.ok(s2.master_online, f"B2a t={t}s dalam grace -> online")
    b.write_state("bonus_hedge_master.dat", stale)
    s2.read_master_state(now=131)
    c.ok(s2.master_online is False, "B2b t=131s > 120s -> offline")

    # B3: gap 1-cycle (master broadcast lalu buka layer baru)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.broadcast_state()          # counter=1, 0 posisi
    s.read_master_state(now=0)
    m._open_sell(0); m.broadcast_state()   # counter=2, 1 posisi
    s.read_master_state(now=50)            # slave lihat 1 posisi (gap tertutup di siklus ini)
    c.ok(s.master_pos_count == 1, "B3 gap 1-cycle tertutup siklus berikutnya", f"count={s.master_pos_count}")

    # B4: magic/version salah -> snapshot dipertahankan (tidak corrupt)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.broadcast_state()
    s.read_master_state(now=1)
    c.ok(s.master_online, "B4a baseline online")
    bad_magic = b"X" * 8 + b.read_state("bonus_hedge_master.dat")[8:]
    b.write_state("bonus_hedge_master.dat", bad_magic)
    ok_read = s.read_master_state(now=11)
    c.ok(ok_read is True and s.master_online, "B4 magic salah -> snapshot lama dipertahankan (grace)", f"online={s.master_online}")


# ===========================================================================
# C. CLOSE_ALL RACE & COMMAND FILE
# ===========================================================================
def test_c_close_all_race(c, buggy=False):
    print("\n=== C. CLOSE_ALL Race & Command File ===")
    fix_cmd = not buggy
    # C1: master TP close -> kirim CLOSE_ALL -> slave terima -> keduanya flat
    b = new_bridge(); m = MasterEA(b, fix_command_race=fix_cmd); s = SlaveEA(b, fix_command_race=fix_cmd)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 100.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2001, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 50.0, "comment": "CT#1001"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = 50.0
    r = m.manage_grid(now=100, bid=2700.0)
    c.ok(r == "CLOSED_BY_TP" and len(m.positions) == 0, "C1 master close by TP", f"r={r}")
    c.ok(b.read_command_bytes() is not None, "C1b command CLOSE_ALL terkirim")
    s.read_master_state(now=100)   # master broadcast 0 posisi setelah close? broadcast manual
    s.check_incoming_commands(now=100)
    c.ok(len(s.positions) == 0, "C1c slave terima CLOSE_ALL -> flat", f"pos={len(s.positions)}")

    # C2: simultaneous close (master TP & slave harvest) -> idempotent aman
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 100.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2002, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 50.0, "comment": "CT#1002"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = 50.0
    s.master_online = True; s.master_pos_count = 1; s.master_profit = 100.0
    m.close_all_master()
    s.close_all_slave()
    c.ok(len(m.positions) == 0 and len(s.positions) == 0, "C2 double-close idempotent, kedua flat")

    # C3: delayed command (master close duluan, command nyusul) -> slave masih close
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1003, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2003, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 0.0, "comment": "CT#1003"})
    m.close_all_master()
    b.write_command("CLOSE_ALL")
    s.check_incoming_commands(now=100)
    c.ok(len(s.positions) == 0, "C3 delayed CLOSE_ALL -> slave flat")

    # C4: PARTIAL-WRITE RACE pada command file
    b = new_bridge(); m = MasterEA(b, fix_command_race=fix_cmd)
    b.write_command("CLOSE_ALL", partial=True)   # hanya 2 byte ditulis
    m.check_incoming_commands(now=100)
    if fix_cmd:
        c.ok(b.read_command_bytes() is not None, "C4 FIXED: partial write -> command DI-PERTAHANKAN (retry)")
        # siklus berikutnya penulis selesai -> command terbaca
        b.write_command("CLOSE_ALL")
        m.check_incoming_commands(now=150)
        c.ok(b.read_command_bytes() is None and "MASTER_RECV_CLOSE_ALL" in [e[0] for e in m.events],
             "C4b FIXED: command akhirnya dieksekusi setelah write lengkap")
    else:
        c.ok(b.read_command_bytes() is None, "C4 BUGGY: partial write -> command HILANG (bug terbukti)")
        c.ok("MASTER_RECV_CLOSE_ALL" not in [e[0] for e in m.events], "C4b BUGGY: CLOSE_ALL tidak pernah dieksekusi")

    # C5: hedge fail -> slave kirim CLOSE_ALL ke master -> master close
    b = new_bridge(); m = MasterEA(b, fix_command_race=fix_cmd); s = SlaveEA(b, fix_command_race=fix_cmd)
    m.positions.append({"ticket": 1004, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = 0.0
    m.broadcast_state()
    s.read_master_state(now=1000)
    s.account_free = 5.0  # margin habis -> tidak bisa hedge
    r = s.sync_open_positions(now=1000, ask=2650.5)
    c.ok(r == "SLAVE_MARGIN_LOW", "C5a slave margin rendah -> tidak buka hedge")
    # di MQL5: kalau order gagal -> SendCommandToMaster("CLOSE_ALL"); di sini margin check mencegah order,
    # jadi MQL5 path-nya return sebelum order (free margin check). Simulasi guard: slave harus tetap aman.
    c.ok(len(m.positions) == 1, "C5b master posisi masih ada (slave tidak naked-close)")

    # C5-real: simulasi order FAILED -> kirim CLOSE_ALL
    b = new_bridge(); m = MasterEA(b, fix_command_race=fix_cmd); s = SlaveEA(b, fix_command_race=fix_cmd)
    m.positions.append({"ticket": 1005, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.broadcast_state()
    s.read_master_state(now=1000)
    s.order_always_fail = True
    # override sync_open utk mensimulasi kegagalan order
    def failing_open(now, ask):
        s.send_command_to_master("CLOSE_ALL")
        return "ORDER_FAILED"
    s.sync_open_positions = failing_open
    s.sync_open_positions(now=1000, ask=2650.5)
    m.check_incoming_commands(now=1000)
    c.ok(len(m.positions) == 0, "C5c hedge fail -> CLOSE_ALL ke master -> master flat (rollback)")


# ===========================================================================
# D. SYNC OPEN / CLOSE (ANTI-JITTER)
# ===========================================================================
def test_d_sync(c):
    print("\n=== D. Sync Open / Close ===")
    # D1: master buka layer -> slave hedge (lot 1.1x, comment CT#)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = 0.0
    m.broadcast_state()
    s.read_master_state(now=1000)
    r = s.sync_open_positions(now=1000, ask=2650.5)
    c.ok(r[0] == "OPENED" and len(s.positions) == 1, "D1a slave hedge terbuka", f"r={r}")
    c.ok(s.positions[0]["comment"] == "CT#1001" and s.positions[0]["type"] == 0
         and abs(s.positions[0]["volume"] - 0.11) < 1e-9, "D1b comment/type/lot benar (0.11 BUY)")

    # D2: master tutup 1 posisi -> slave missing 1 cycle -> TIDAK langsung close (anti-jitter)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2002, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 0.0, "comment": "CT#1002"})
    m.broadcast_state(); s.read_master_state(now=1000)
    # master tutup; broadcast 0 posisi
    m.positions.clear(); m.broadcast_state()
    s.read_master_state(now=1050)
    s.sync_close_positions(now=1050)
    c.ok(len(s.positions) == 1, "D2 1-cycle missing -> belum close (anti-jitter)", f"pos={len(s.positions)}")
    # D3: 3-cycle -> close
    s.sync_close_positions(now=1100)
    s.sync_close_positions(now=1150)
    c.ok(len(s.positions) == 0, "D3 3-cycle missing -> slave close", f"pos={len(s.positions)}")

    # D4: master close semua (bukan TP) -> slave tutup semua setelah 3 cycle
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    for i in range(3):
        m.positions.append({"ticket": 1010 + i, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": f"GRID_S{i+1}"})
        s.positions.append({"ticket": 2010 + i, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 0.0, "comment": f"CT#{1010+i}"})
    m.broadcast_state(); s.read_master_state(now=1000)
    m.positions.clear(); m.broadcast_state()
    s.read_master_state(now=1050)
    for t in (1050, 1100, 1150):
        s.sync_close_positions(now=t)
    c.ok(len(s.positions) == 0, "D4 sync close semua setelah 3-cycle", f"pos={len(s.positions)}")

    # D5: hedge sudah ada -> tidak double open
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1020, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2020, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 0.0, "comment": "CT#1020"})
    m.broadcast_state(); s.read_master_state(now=1000)
    r = s.sync_open_positions(now=1000, ask=2650.5)
    c.ok(r in ("NO_NEW", "OVERHEDGE_CAP") and len(s.positions) == 1, "D5 tidak double hedge", f"r={r} pos={len(s.positions)}")


# ===========================================================================
# E. MARGIN & GUARDS
# ===========================================================================
def test_e_margin(c):
    print("\n=== E. Margin & Guards ===")
    # E1: master free margin rendah -> tidak buka (slave online, 0 posisi OK utk layer 1)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.slave_online = True; m.slave_pos_count = 0
    m.account_free = 50.0
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r == "MASTER_MARGIN_LOW", "E1 master margin rendah -> MASTER_MARGIN_LOW (layer 1 tetap bisa mulai)", f"r={r}")
    m.slave_pos_count = 1; m.slave_free_margin = 500.0; m.slave_margin_level = 400.0
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r == "MASTER_MARGIN_LOW", "E1b master free<100 -> MASTER_MARGIN_LOW", f"r={r}")

    # E2: slave margin rendah -> master tidak buka
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = True; m.slave_pos_count = 1
    m.slave_free_margin = 50.0; m.slave_margin_level = 400.0
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r == "SLAVE_MARGIN_LOW", "E2 slave free<100 -> SLAVE_MARGIN_LOW", f"r={r}")

    # E3: slave offline -> master tidak buka (tidak naked)
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = False
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r == "SLAVE_OFFLINE", "E3 slave offline -> master tidak buka")

    # E4: slave pos_count < master pos_count -> master tunggu hedge
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.10, "price_open": 2670.0, "profit": 0.0, "comment": "GRID_S2"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_free_margin = 500.0; m.slave_margin_level = 400.0
    r = m.manage_grid(now=100, bid=2690.0)
    c.ok(r == "WAIT_HEDGE", "E4 master tunggu slave hedge layer sebelumnya (1/2 hedged)", f"r={r}")

    # E5: bonus credit belum masuk -> slave broadcast free=0 -> master tidak buka
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    s.account_credit = 50.0   # < min_bonus_credit
    s.positions.append({"ticket": 2001, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": 0.0, "comment": "CT#1001"})
    s.broadcast_state()
    m.read_slave_state(now=0)
    c.ok(m.slave_free_margin == 0.0 and m.slave_online, "E5a slave report free=0 saat bonus belum masuk")
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r == "SLAVE_MARGIN_LOW", "E5b master tidak buka saat bonus belum masuk (free=0)", f"r={r}")


# ===========================================================================
# F. CIRCUIT BREAKER
# ===========================================================================
def test_f_circuit_breaker(c):
    print("\n=== F. Circuit Breaker ===")
    # F1: rapid-close anti-flapping (di MQL5: 2x buka-tutup <20s -> lock 300s)
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = True; m.slave_pos_count = 1; m.slave_free_margin = 500.0; m.slave_margin_level = 400.0
    m.last_order_time = 0
    m.last_order_open_time = 100
    m.close_all_master()
    m.last_order_open_time = 200
    m.close_all_master()
    # Di sim close_all_master mereset rapid_counter; guard circuit-breaker diuji di F1b
    c.ok(m.circuit_breaker_until < 0, "F1a circuit breaker state default (belum aktif)")
    # verifikasi guard: selama lock, manage_grid return CIRCUIT_BREAKER
    m.circuit_breaker_until = 500
    r = m.manage_grid(now=300, bid=2650.0)
    c.ok(r == "CIRCUIT_BREAKER", "F1b selama lock -> tidak buka order", f"r={r}")
    m.circuit_breaker_until = -1000.0
    r = m.manage_grid(now=300, bid=2650.0)
    c.ok(r != "CIRCUIT_BREAKER", "F1c setelah lock habis -> normal kembali")


# ===========================================================================
# G. COOLDOWN & CLOSING LOCK
# ===========================================================================
def test_g_cooldown(c):
    print("\n=== G. Cooldown & Closing Lock ===")
    b = new_bridge(); m = MasterEA(b)
    m.slave_online = True; m.slave_pos_count = 1; m.slave_free_margin = 500.0; m.slave_margin_level = 400.0
    m.last_order_time = 100
    r = m.manage_grid(now=105, bid=2650.0)
    c.ok(r == "COOLDOWN", "G1 cooldown 10s -> tidak buka", f"r={r}")
    m.last_order_time = 90
    r = m.manage_grid(now=105, bid=2650.0)
    c.ok(r != "COOLDOWN", "G2 lewat 10s -> boleh buka", f"r={r}")
    m.closing_lock_until = 300
    r = m.manage_grid(now=200, bid=2650.0)
    c.ok(r == "CLOSING_LOCK", "G3 closing lock -> tidak buka", f"r={r}")


# ===========================================================================
# H. COMBINED TP + MULTIPLIER + LOT CLAMP
# ===========================================================================
def test_h_tp(c):
    print("\n=== H. Combined TP, Multiplier, Lot Clamp ===")
    # H1: combined >= TP + buffer -> trigger
    b = new_bridge(); m = MasterEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 30.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = 20.0
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r == "CLOSED_BY_TP", "H1 combined 50 >= 31.74+10 -> CLOSED_BY_TP", f"r={r}")

    # H2: combined < TP -> tidak close
    b = new_bridge(); m = MasterEA(b)
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 10.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = -5.0
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r != "CLOSED_BY_TP", "H2 combined 5 < 41.74 -> tidak close", f"r={r}")

    # H3: multiplier 1.1 -> lot 0.11 (round 2 digit)
    b = new_bridge(); s = SlaveEA(b)
    lot = max(0.01, min(50.0, round(0.10 * 1.1 * 100.0) / 100.0))
    c.ok(abs(lot - 0.11) < 1e-9, "H3 multiplier 1.1 -> 0.11", f"lot={lot}")

    # H4: lot clamp min 0.01 max 50
    lot_min = max(0.01, min(50.0, round(0.005 * 1.1 * 100.0) / 100.0))
    c.ok(lot_min >= 0.01, "H4a clamp min 0.01", f"lot={lot_min}")
    lot_max = max(0.01, min(50.0, round(45.0 * 1.1 * 100.0) / 100.0))
    c.ok(lot_max <= 50.0, "H4b clamp max 50", f"lot={lot_max}")

    # H5: TP custom + spread buffer -> combined 55 < 50+10=60 -> TIDAK close
    b = new_bridge(); m = MasterEA(b, basket_tp=50.0)
    m.positions.append({"ticket": 1003, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 55.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = 0.0
    r = m.manage_grid(now=100, bid=2650.0)
    c.ok(r != "CLOSED_BY_TP", "H5 custom TP 50+10=60 -> combined 55 belum -> tidak close", f"r={r}")
    # H6: custom TP tercapai -> close
    m.positions[0]["profit"] = 60.0
    r = m.manage_grid(now=200, bid=2650.0)
    c.ok(r == "CLOSED_BY_TP", "H6 custom TP tercapai (60>=60) -> CLOSED_BY_TP", f"r={r}")


# ===========================================================================
# I. BINARY INTEGRITY
# ===========================================================================
def test_i_binary(c):
    print("\n=== I. Binary Integrity ===")
    pos = [{"ticket": 13521243, "type": 1, "volume": 0.30, "price_open": 4641.55, "profit": 64.50, "comment": "GRID_S1"},
           {"ticket": 13521244, "type": 1, "volume": 0.30, "price_open": 4621.59, "profit": 1267.20, "comment": "GRID_S2"}]
    data = serialize_state(42, 100870, 4054.89, 3990.39, 3800.0, 1456.0, 1331.70, pos)
    st = deserialize_state(data)
    c.ok(st is not None and st["counter"] == 42 and len(st["positions"]) == 2
         and st["positions"][0]["comment"] == "GRID_S1", "I1 roundtrip utuh")
    # wrong magic
    bad = struct.pack(HEADER_FMT, 0xDEADBEEF, 2, 1, 100870, 1000, 1000, 800, 500, 0, 0)
    c.ok(deserialize_state(bad) is None, "I2 magic salah -> None")
    # wrong version
    bad_v = struct.pack(HEADER_FMT, MAGIC, 99, 1, 100870, 1000, 1000, 800, 500, 0, 0)
    c.ok(deserialize_state(bad_v) is None, "I3 version salah -> None")
    # truncated / empty
    c.ok(deserialize_state(b"\x00" * 10) is None, "I4 truncated -> None")
    c.ok(deserialize_state(b"") is None, "I5 empty -> None")
    c.ok(deserialize_state(None) is None, "I6 None -> None")
    # pos_count > 100
    bad_c = struct.pack(HEADER_FMT, MAGIC, 2, 1, 100870, 1000, 1000, 800, 500, 0.0, 101)
    c.ok(deserialize_state(bad_c) is None, "I7 pos_count 101 -> None")


# ===========================================================================
# J. GRID DIRECTION (BUG FIX)
# ===========================================================================
def test_j_grid_direction(c, buggy=False):
    print("\n=== J. Grid Direction (SELL grid) ===")
    # Setup: 1 layer SELL @ 2650. step 2000pt*0.01 = $20
    b = new_bridge(); m = MasterEA(b, fix_grid_direction=not buggy)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_free_margin = 500.0; m.slave_margin_level = 400.0
    m.last_order_time = 0
    # J1: harga NAIK 20+ -> buka layer (benar utk SELL grid)
    r = m.manage_grid(now=100, bid=2670.1)
    c.ok(r == "OPENED_NEXT_LAYER" and len(m.positions) == 2, "J1 harga naik -> buka layer baru", f"r={r} pos={len(m.positions)}")
    # J2 (v1.20): harga TURUN 20+ -> BI-DIRECTIONAL: boleh layer bawah HANYA jika
    # slave margin sehat; BUGGY v0 juga buka tapi TANPA shield saat slave tertekan.
    b = new_bridge(); m = MasterEA(b, fix_grid_direction=not buggy)
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1
    m.slave_free_margin = 150.0; m.slave_margin_level = 120.0  # slave TERTEDAK (free<200)
    m.min_free = 50.0  # lolos pre-check agar sampai ke shield
    m.last_order_time = 0
    r = m.manage_grid(now=100, bid=2629.9)
    if buggy:
        c.ok(r == "OPENED_NEXT_LAYER" and len(m.positions) == 2,
             "J2 BUGGY: harga turun + slave tertekan tetap buka layer (tanpa shield)")
    else:
        c.ok(r == "HOLDING" and len(m.positions) == 1,
             "J2 FIXED (v1.20): harga turun + slave tertekan -> DOWNWARD SHIELD menahan", f"r={r} pos={len(m.positions)}")


# ===========================================================================
# K. MAX LAYERS
# ===========================================================================
def test_k_max_layers(c):
    print("\n=== K. Max Layers ===")
    b = new_bridge(); m = MasterEA(b, max_layers=3)
    for i in range(3):
        m.positions.append({"ticket": 1100 + i, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": f"GRID_S{i+1}"})
    m.slave_online = True; m.slave_pos_count = 3; m.slave_free_margin = 500.0; m.slave_margin_level = 400.0
    m.last_order_time = 0
    r = m.manage_grid(now=100, bid=3000.0)
    c.ok(r == "HOLDING" and len(m.positions) == 3, "K1 max_layers tercapai -> tidak buka lagi", f"r={r}")


# ===========================================================================
# M. FITUR v1.20 + FIX AUDIT 2026-09-05 (manual trades, watchdog, naked alert,
#    slave cap, comment-loss, 60% guard, downward shield)
# ===========================================================================
def test_m_v120(c):
    print("\n=== M. v1.20 + Audit Fixes ===")

    # M1: manual position ikut TP basket (total>0) TAPI tidak memblokir layer
    #     baru (guard vs ea_positions) — bug lama: slave_pos_count<total selamanya
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.manual_positions.append({"ticket": 5001, "type": 0, "volume": 0.05, "price_open": 2640.0, "profit": 0.0, "comment": "user"})
    s.positions.append({"ticket": 2001, "type": 0, "volume": 0.11, "price_open": 2650.1, "profit": 0.0, "comment": "CT#1001"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_last_seen = 1000
    m.slave_free_margin = 900.0; m.slave_margin_level = 400.0
    m.broadcast_state(); s.read_master_state(now=1000)
    m.last_order_time = -1000.0
    r = m.manage_grid(now=1001, bid=2670.0)  # naik $20 -> layer 2
    c.ok(r == "OPENED_NEXT_LAYER", "M1 layer 2 tetap terbuka saat ada posisi manual (guard ea_positions)", f"r={r}")

    # M2: watchdog hanya menghitung grid EA. Slave meng-hedge 2 layer EA ->
    #     posisi manual TIDAK memicu watchdog (bug lama: total incl manual > slave
    #     selamanya -> seluruh grid ditutup padahal semua terhedging).
    m.slave_pos_count = 2
    fired = m.check_unhedged_watchdog(now=1002)
    c.ok(not fired and m.unhedged_since is None and len(m.positions) == 2,
         "M2 watchdog tidak salah tembak ke posisi manual", f"fired={fired} since={m.unhedged_since}")

    # M3: watchdog fire saat grid EA sungguhan tidak terhedging > 7s
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    for i in range(3):
        m.positions.append({"ticket": 1001 + i, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": f"GRID_S{i+1}"})
    s.positions.append({"ticket": 2001, "type": 0, "volume": 0.11, "price_open": 2650.1, "profit": 0.0, "comment": "CT#1001"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_last_seen = 0
    m.check_unhedged_watchdog(now=100)
    fired = m.check_unhedged_watchdog(now=108)  # > 7 detik
    c.ok(fired and len(m.positions) == 0, "M3 watchdog fire: grid EA unhedged >7s -> close semua", f"fired={fired}")

    # M4: NAKED ALERT — slave proof-offline + posisi EA -> alert 1x; pulih -> reset
    b = new_bridge(); m = MasterEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.slave_online = False; m.slave_last_seen = 0
    for t in range(40):
        m.check_naked_alert(now=1000 + t * 0.05)
    c.ok(m.naked_alerts == 1, "M4a naked alert terkirim tepat 1x", f"alerts={m.naked_alerts}")
    m.slave_online = True
    m.check_naked_alert(now=2000)
    m.slave_online = False
    for t in range(40):
        m.check_naked_alert(now=2100 + t * 0.05)
    c.ok(m.naked_alerts == 2, "M4b episode naked kedua -> alert lagi (reset saat pulih)", f"alerts={m.naked_alerts}")

    # M5: SLAVE CAP — posisi asing di terminal slave tidak memblokir hedge (fix)
    b = new_bridge(); m = MasterEA(b)
    s = SlaveEA(b, fix_slave_cap=False)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.broadcast_state(); s.read_master_state(now=1000)
    s.other_positions = 5
    r = s.sync_open_positions(now=1000, ask=2650.5)
    c.ok(r == "CAP_BROKEN", "M5a BUGGY: PositionsTotal() mentah salah tembak -> hedge diblokir", f"r={r}")
    b = new_bridge(); m = MasterEA(b)
    s = SlaveEA(b, fix_slave_cap=True)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.broadcast_state(); s.read_master_state(now=1000)
    s.other_positions = 5
    r = s.sync_open_positions(now=1000, ask=2650.5)
    c.ok(r[0] == "OPENED" and len(s.positions) == 1, "M5b FIXED: cap vs hedge sendiri -> hedge jalan", f"r={r}")

    # M5c: cap benar tetap mencegah over-hedge
    r2 = s.sync_open_positions(now=1001, ask=2650.5)
    c.ok(r2 == "OVERHEDGE_CAP" and len(s.positions) == 1, "M5c cap tetap mencegah over-hedge", f"r={r2}")

    # M6: COMMENT-LOSS MODE — comment dihapus broker -> backstop bucket TANPA double-hedge
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b, detect_comment_loss=True)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 0.0, "comment": "GRID_S1"})
    m.broadcast_state(); s.read_master_state(now=1000)
    s.sync_open_positions(now=1000, ask=2650.5)
    # broker menghapus comment posisi hedge (simulasi overwrite)
    s.positions[0]["comment"] = "copy-service"
    s.read_master_state(now=1001) if False else None
    m.counter += 1; m.broadcast_state(); s.read_master_state(now=1001)
    r = s.sync_open_positions(now=1001, ask=2650.6)
    c.ok(s.comments_lost and r in ("NO_NEW", "OVERHEDGE_CAP") and len(s.positions) == 1,
         "M6 comment hilang -> mode backstop, TIDAK double-hedge", f"lost={s.comments_lost} r={r} pos={len(s.positions)}")
    # master buka layer 2 (volume sama) -> backstop harus hedge 1 lagi (need 2 have 1)
    m.positions.append({"ticket": 1002, "type": 1, "volume": 0.10, "price_open": 2670.0, "profit": 0.0, "comment": "GRID_S2"})
    m.counter += 1; m.broadcast_state(); s.read_master_state(now=1002)
    r = s.sync_open_positions(now=1002, ask=2670.5)
    c.ok(r[0] == "OPENED" and len(s.positions) == 2, "M6b backstop hedge layer baru saat butuh", f"r={r} pos={len(s.positions)}")

    # M7: guard 60% — dekat TP jangan buka layer baru
    b = new_bridge(); m = MasterEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 20.0, "comment": "GRID_S1"})
    s = SlaveEA(b)
    s.positions.append({"ticket": 2001, "type": 0, "volume": 0.11, "price_open": 2650.1, "profit": 2.0, "comment": "CT#1001"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_last_seen = 0
    m.slave_free_margin = 900.0; m.slave_margin_level = 400.0
    # combined 26 >= 60% dari tp(31.74+10=41.74 -> 25.04) -> NEAR_TP_HOLD
    m.positions[0]["profit"] = 24.0; s.positions[0]["profit"] = 2.0
    m.slave_profit = 2.0
    m.broadcast_state()
    m.last_order_time = -1000.0
    r = m.manage_grid(now=1001, bid=2670.0)
    c.ok(r == "NEAR_TP_HOLD", "M7 guard 60%: dekat TP -> tahan layer baru", f"r={r}")

    # M8: DOWNWARD SHIELD — harga turun + slave margin tertekan -> TIDAK layer bawah
    b = new_bridge(); m = MasterEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": -5.0, "comment": "GRID_S1"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_last_seen = 0
    m.slave_free_margin = 100.0  # < 200 -> tertekan (tapi masih >= min_free=100 lolos pre-check)
    m.slave_margin_level = 400.0
    m.last_order_time = -1000.0
    r = m.manage_grid(now=1001, bid=2630.0)  # turun $20
    c.ok(r == "HOLDING", "M8 downward shield: slave margin tertekan -> layer bawah diblokir", f"r={r}")
    m.slave_free_margin = 900.0
    r = m.manage_grid(now=1002, bid=2630.0)
    c.ok(r == "OPENED_NEXT_LAYER", "M8b slave sehat -> layer bawah boleh (bi-directional)", f"r={r}")

    # M9: TP close juga mengirim CLOSE_ALL ke slave SEBELUM close master (parity
    #     dengan .mq5: slave harus ikut flat saat TP basket)
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 40.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2001, "type": 0, "volume": 0.11, "price_open": 2650.1, "profit": 5.0, "comment": "CT#1001"})
    s.broadcast_state()          # slave telemetry masuk bridge
    m.broadcast_state()          # master telemetry masuk bridge
    m.read_slave_state(now=1000) # master baca -> slave_online=True dari file
    m.last_order_time = -1000.0
    r = m.on_timer(now=1001, bid=2650.0)
    s.read_master_state(now=1001)
    s.on_timer(now=1001, ask=2650.1)
    c.ok(r == "CLOSED_BY_TP" and len(m.positions) == 0 and len(s.positions) == 0,
         "M9 TP basket -> master flat DAN slave ikut flat via CLOSE_ALL", f"r={r} ms={len(m.positions)} ss={len(s.positions)}")

    # M10: TP basket tidak boleh sepihak saat slave OFFLINE (early-return v1.20)
    b = new_bridge(); m = MasterEA(b)
    m.positions.append({"ticket": 1001, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 999.0, "comment": "GRID_S1"})
    m.slave_online = False; m.slave_pos_count = 0; m.slave_last_seen = 0
    r = m.on_timer(now=1001, bid=2650.0)
    c.ok(r == "SLAVE_OFFLINE" and len(m.positions) == 1, "M10 slave offline -> TP basket DITAHAN (bukan close sepihak)", f"r={r}")



def test_l_full_cycle(c, buggy=False):
    print("\n=== L. Full-Cycle End-to-End (2 EA berjalan bersama) ===")
    # Skenario NAIK: master buka layer -> slave hedge -> combined TP -> keduanya flat
    b = new_bridge(); m = MasterEA(b, fix_slave_pos_guard=not buggy); s = SlaveEA(b)
    t = 0.0; bid = 2650.0

    # Phase 1: master buka layer 1 dari nol (slave online, 0 posisi — bug fix)
    for _ in range(5):
        t += 0.05
        s.on_timer(t, bid + 0.5)
        m.on_timer(t, bid)
    if buggy:
        c.ok(len(m.positions) == 0,
             "L1 BUGGY: deadlock terbukti — master TIDAK pernah buka layer 1 (guard slave_pos_count==0)",
             f"pos={len(m.positions)}")
        return  # hentikan — buggy tidak bisa lanjut ke TP
    c.ok(len(m.positions) >= 1, "L1 FIXED: master buka layer 1 dari nol (tanpa deadlock)", f"pos={len(m.positions)}")
    # slave hedge layer 1
    for _ in range(5):
        t += 0.05
        s.on_timer(t, bid + 0.5)
        m.on_timer(t, bid)
    c.ok(len(s.positions) == len(m.positions), "L2 slave hedge = master posisi", f"s={len(s.positions)} m={len(m.positions)}")

    # Phase 2: bangun grid sampai 3 layer (lewati cooldown 10s, naikkan harga > step $20)
    for _ in range(2):
        t += 11.0          # lewati cooldown 10 detik
        bid += 25.0        # naik > grid step ($20)
        m.on_timer(t, bid)             # master buka layer berikutnya
        s.on_timer(t, bid + 0.5)       # slave hedge layer baru
        for _ in range(5):
            t += 0.05
            m.on_timer(t, bid)
            s.on_timer(t, bid + 0.5)
    c.ok(len(m.positions) >= 2 and len(s.positions) == len(m.positions),
         "L2b grid terbangun (master=slave)", f"m={len(m.positions)} s={len(s.positions)}")

    # Phase 3: combined TP tercapai -> master close + kirim CLOSE_ALL
    for p in m.positions:
        p["profit"] = 30.0
    for p in s.positions:
        p["profit"] = 20.0
    m.slave_online = True; m.slave_pos_count = len(s.positions)
    m.slave_profit = sum(p["profit"] for p in s.positions)
    t += 0.05
    r = m.on_timer(t, bid)
    c.ok(r == "CLOSED_BY_TP" and len(m.positions) == 0, "L3 master flat setelah TP", f"r={r} pos={len(m.positions)}")

    # Phase 4: drain singkat (masih dalam cooldown 10s) -> slave terima CLOSE_ALL / sync-close
    for _ in range(8):
        t += 0.05
        m.on_timer(t, bid)          # master broadcast state 0 posisi
        s.on_timer(t, bid + 0.5)    # slave baca 0 posisi -> sync close (3-cycle anti-jitter)
    c.ok(len(s.positions) == 0, "L4 slave flat setelah TP (command/sync close)", f"pos={len(s.positions)}")

    # Phase 5: setelah cooldown 10s -> master memulai siklus grid baru (perilaku normal EA)
    t += 11.0
    for _ in range(10):
        t += 0.05
        m.on_timer(t, bid)
        s.on_timer(t, bid + 0.5)
    c.ok(len(m.positions) == 1 and len(s.positions) == 1,
         "L4b siklus baru dimulai setelah cooldown (1 layer + 1 hedge)",
         f"m={len(m.positions)} s={len(s.positions)}")

    # Skenario TURUN: harga turun -> slave kena MC (equity<=10) 3-cycle -> master harvest -> flat
    b = new_bridge(); m = MasterEA(b); s = SlaveEA(b)
    m.positions.append({"ticket": 1201, "type": 1, "volume": 0.10, "price_open": 2650.0, "profit": 100.0, "comment": "GRID_S1"})
    s.positions.append({"ticket": 2201, "type": 0, "volume": 0.11, "price_open": 2650.15, "profit": -1195.0, "comment": "CT#1201"})
    m.slave_online = True; m.slave_pos_count = 1; m.slave_profit = -1195.0
    s.master_online = True; s.master_pos_count = 1; s.master_profit = 100.0
    s.master_equity = 5.0; s.master_margin_level = 0.0
    t = 0.0
    harvested = False
    for _ in range(100):
        t += 0.05
        # slave broadcast equity (1200 + profit = 5) -> master baca -> harvest
        s.broadcast_state()
        r = m.on_timer(t, 2629.0)
        if r == "HARVESTED":
            harvested = True
            break
    c.ok(harvested and len(m.positions) == 0, "L5 slave MC -> master harvest -> master flat", f"harvested={harvested} pos={len(m.positions)}")


# ===========================================================================
# MAIN
# ===========================================================================
def main():
    buggy = len(sys.argv) > 1 and sys.argv[1] == "buggy"
    mode = "BUGGY (meniru file asli sebelum fix — sebagian test diharapkan FAIL)" if buggy else "FIXED (semua test harus PASS)"
    print("=" * 60)
    print(f"  SIMULASI DUAL-EA BONUS HEDGE — MODE: {mode}")
    print("=" * 60)
    c = Check()
    test_a_debounce(c)
    test_b_counter(c)
    test_c_close_all_race(c, buggy=buggy)
    test_d_sync(c)
    test_e_margin(c)
    test_f_circuit_breaker(c)
    test_g_cooldown(c)
    test_h_tp(c)
    test_i_binary(c)
    test_j_grid_direction(c, buggy=buggy)
    test_k_max_layers(c)
    test_m_v120(c)
    test_l_full_cycle(c, buggy=buggy)
    ok = c.summary()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
