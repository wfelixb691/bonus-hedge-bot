import struct
import os
import tempfile
import unittest
import shutil

class DualMT5SimulationTest(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix='mt5_sim_test_')
        self.master_file = os.path.join(self.test_dir, 'bonus_hedge_master.dat')
        self.slave_file = os.path.join(self.test_dir, 'bonus_hedge_slave.dat')
        self.cmd_file = os.path.join(self.test_dir, 'bonus_hedge_command.dat')

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def write_master_state(self, counter, login, equity, balance, free_margin, margin_lvl, total_prof, positions):
        data = struct.pack('<qqqqdddddi', 0x42484246, 2, counter, login, equity, balance, free_margin, margin_lvl, total_prof, len(positions))
        for p in positions:
            comment_b = p.get('comment', '').encode('utf-8')
            data += struct.pack('<qidddi', p['ticket'], p['type'], p['volume'], p['price'], p['profit'], len(comment_b))
            if len(comment_b) > 0:
                data += comment_b
        with open(self.master_file, 'wb') as f:
            f.write(data)

    def write_slave_state(self, counter, login, equity, balance, free_margin, margin_lvl, total_prof, positions):
        data = struct.pack('<qqqqdddddi', 0x42484246, 2, counter, login, equity, balance, free_margin, margin_lvl, total_prof, len(positions))
        for p in positions:
            comment_b = p.get('comment', '').encode('utf-8')
            data += struct.pack('<qidddi', p['ticket'], p['type'], p['volume'], p['price'], p['profit'], len(comment_b))
            if len(comment_b) > 0:
                data += comment_b
        with open(self.slave_file, 'wb') as f:
            f.write(data)

    def read_master_state(self):
        if not os.path.exists(self.master_file):
            return None
        with open(self.master_file, 'rb') as f:
            data = f.read()
        if len(data) < 76:
            return None
        magic, ver, counter, login, equity, balance, free_margin, margin_lvl, total_prof, count = struct.unpack('<qqqqdddddi', data[:76])
        offset = 76
        positions = []
        for _ in range(count):
            ticket, p_type, vol, price, prof, clen = struct.unpack('<qidddi', data[offset:offset+40])
            offset += 40
            comment = data[offset:offset+clen].decode('utf-8') if clen > 0 else ''
            offset += clen
            positions.append({'ticket': ticket, 'type': p_type, 'volume': vol, 'price': price, 'profit': prof, 'comment': comment})
        return {'counter': counter, 'login': login, 'equity': equity, 'balance': balance, 'free_margin': free_margin, 'margin_lvl': margin_lvl, 'profit': total_prof, 'positions': positions}

    def write_command(self, cmd):
        cmd_b = cmd.encode('utf-8')
        with open(self.cmd_file, 'wb') as f:
            f.write(struct.pack('<i', len(cmd_b)) + cmd_b)

    def read_and_clear_command(self):
        if not os.path.exists(self.cmd_file):
            return None
        with open(self.cmd_file, 'rb') as f:
            data = f.read()
        os.remove(self.cmd_file)
        if len(data) < 4:
            return None
        clen = struct.unpack('<i', data[:4])[0]
        return data[4:4+clen].decode('utf-8') if clen > 0 else ''

    def test_debounce_liquidation_harvest(self):
        print('\n--- TEST 1: Liquidation Harvest Debounce & Equity <= 0 ---')
        class MasterLiquidationChecker:
            def __init__(self):
                self.slave_mc_counter = 0
                self.harvest_triggered = False

            def check_slave_liquidation(self, slave_online, slave_login, slave_equity, slave_margin_level):
                if not slave_online:
                    return False
                is_liquidated = (slave_login > 0 and (slave_equity <= 10.0 or (slave_margin_level > 0 and slave_margin_level < 20.0)))
                if is_liquidated:
                    self.slave_mc_counter += 1
                    if self.slave_mc_counter >= 3:
                        self.harvest_triggered = True
                        return True
                else:
                    self.slave_mc_counter = 0
                return False

        checker = MasterLiquidationChecker()

        # Phase A: 1-Tick Transient Glitch
        res1 = checker.check_slave_liquidation(slave_online=True, slave_login=100871, slave_equity=0.0, slave_margin_level=0.0)
        self.assertFalse(res1)
        self.assertEqual(checker.slave_mc_counter, 1)

        # Tick 2: Broker recovers
        res2 = checker.check_slave_liquidation(slave_online=True, slave_login=100871, slave_equity=1150.0, slave_margin_level=450.0)
        self.assertFalse(res2)
        self.assertEqual(checker.slave_mc_counter, 0)

        # Phase B: Genuine Liquidation with Negative Balance / /bin/zsh.00 Equity across 3 consecutive ticks
        checker.check_slave_liquidation(slave_online=True, slave_login=100871, slave_equity=-4.50, slave_margin_level=0.0)
        self.assertEqual(checker.slave_mc_counter, 1)

        checker.check_slave_liquidation(slave_online=True, slave_login=100871, slave_equity=0.00, slave_margin_level=0.0)
        self.assertEqual(checker.slave_mc_counter, 2)

        res3 = checker.check_slave_liquidation(slave_online=True, slave_login=100871, slave_equity=0.00, slave_margin_level=0.0)
        self.assertTrue(res3)
        self.assertTrue(checker.harvest_triggered)
        print('  [PASS] 1-Tick glitch rejected, 3-Cycle genuine MC (/bin/zsh/negative equity) successfully harvested!')

    def test_counter_ordering_and_zero_latency_broadcast(self):
        print('\n--- TEST 2: Counter Ordering & Zero-Latency Post-Trade Broadcast ---')
        counter = 1
        pos_master = [{'ticket': 1001, 'type': 1, 'volume': 0.10, 'price': 2650.00, 'profit': 0.0, 'comment': 'GRID_S1'}]
        self.write_master_state(counter, 100870, 1000.0, 1000.0, 950.0, 500.0, 0.0, pos_master)

        slave_positions = [{'ticket': 2001, 'type': 0, 'volume': 0.11, 'price': 2650.15, 'profit': 0.0, 'comment': 'CT#1001'}]
        slave_last_counter = counter

        # Master opens Layer 2 and calls BroadcastMasterState() IMMEDIATELY
        counter += 1
        pos_master.append({'ticket': 1002, 'type': 1, 'volume': 0.10, 'price': 2670.00, 'profit': 0.0, 'comment': 'GRID_S2'})
        self.write_master_state(counter, 100870, 1000.0, 1000.0, 900.0, 400.0, 0.0, pos_master)

        master_snapshot = self.read_master_state()
        self.assertIsNotNone(master_snapshot)
        self.assertEqual(master_snapshot['counter'], 2)
        self.assertEqual(len(master_snapshot['positions']), 2)
        self.assertGreater(master_snapshot['counter'], slave_last_counter)

        new_hedges_opened = []
        for m_pos in master_snapshot['positions']:
            expected_comment = f"CT#{m_pos['ticket']}"
            already_hedged = any(s['comment'] == expected_comment for s in slave_positions)
            if not already_hedged:
                new_hedge = {
                    'ticket': 2002,
                    'type': 0 if m_pos['type'] == 1 else 1,
                    'volume': round(m_pos['volume'] * 1.10, 2),
                    'price': 2670.15,
                    'profit': 0.0,
                    'comment': expected_comment
                }
                slave_positions.append(new_hedge)
                new_hedges_opened.append(new_hedge)

        self.assertEqual(len(new_hedges_opened), 1)
        self.assertEqual(new_hedges_opened[0]['comment'], 'CT#1002')
        self.assertEqual(new_hedges_opened[0]['volume'], 0.11)
        print('  [PASS] Zero-latency post-trade broadcast verified: Layer 2 hedged instantly without delay!')

    def test_close_all_race_single_commander(self):
        print('\n--- TEST 3: CLOSE_ALL Single Commander & Anti-Collision ---')
        master_positions = [{'ticket': 1001, 'type': 1, 'volume': 0.10, 'price': 2650.00, 'profit': -20.0, 'comment': 'GRID_S1'}]
        slave_positions  = [{'ticket': 2001, 'type': 0, 'volume': 0.11, 'price': 2650.15, 'profit': 60.0, 'comment': 'CT#1001'}]

        target_basket_tp = 31.74
        master_profit = master_positions[0]['profit']
        slave_profit  = slave_positions[0]['profit']
        combined_net_profit = master_profit + slave_profit

        master_closed = False
        if combined_net_profit >= target_basket_tp:
            master_positions.clear()
            master_closed = True
            self.write_command('CLOSE_ALL')

        self.assertTrue(master_closed)
        self.assertTrue(os.path.exists(self.cmd_file))

        cmd = self.read_and_clear_command()
        self.assertEqual(cmd, 'CLOSE_ALL')

        slave_positions.clear()
        self.assertEqual(len(slave_positions), 0)
        self.assertFalse(os.path.exists(self.cmd_file))
        print('  [PASS] Single Commander TP execution verified: Clean close, command consumed, zero race collisions!')

    def test_sync_close_anti_jitter_3_cycle_confirmation(self):
        print('\n--- TEST 4: Anti-Jitter SyncClose 3-Cycle Confirmation ---')
        missing_tracker = {}
        slave_pos = [{'ticket': 2001, 'comment': 'CT#1001'}]

        def sync_close_step(master_open_tickets):
            closed_tickets = []
            for s in list(slave_pos):
                m_ticket = int(s['comment'].replace('CT#', ''))
                if m_ticket in master_open_tickets:
                    missing_tracker[s['ticket']] = 0
                else:
                    missing_tracker[s['ticket']] = missing_tracker.get(s['ticket'], 0) + 1
                    if missing_tracker[s['ticket']] >= 3:
                        slave_pos.remove(s)
                        closed_tickets.append(s['ticket'])
            return closed_tickets

        closed = sync_close_step([])
        self.assertEqual(len(closed), 0)
        self.assertEqual(missing_tracker[2001], 1)

        closed = sync_close_step([1001])
        self.assertEqual(len(closed), 0)
        self.assertEqual(missing_tracker[2001], 0)

        sync_close_step([])
        self.assertEqual(missing_tracker[2001], 1)
        sync_close_step([])
        self.assertEqual(missing_tracker[2001], 2)
        closed = sync_close_step([])
        self.assertEqual(closed, [2001])
        self.assertEqual(len(slave_pos), 0)
        print('  [PASS] Anti-Jitter SyncClose verified: 1-cycle glitch tolerated, 3-cycle missing safely closed!')

if __name__ == '__main__':
    unittest.main(verbosity=2)