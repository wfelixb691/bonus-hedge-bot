"""
Live Visual Web Dashboard for Dual-MT5 Bonus Hedging Bot.
Reads binary telemetry from MT5 FILE_COMMON and serves a real-time web UI matching your exact dashboard layout.
"""

import os
import sys
import struct
import json
import time
import socket
import subprocess
import threading
import re
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

PORT = 8888


def find_common_files_dir() -> str:
    """Finds the MT5 Terminal Common Files directory on Windows."""
    appdata = os.environ.get("APPDATA", "")
    if appdata:
        common_path = os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files")
        if os.path.isdir(common_path):
            return common_path

    userprofile = os.environ.get("USERPROFILE", "")
    if userprofile:
        cand = os.path.join(userprofile, "AppData", "Roaming", "MetaQuotes", "Terminal", "Common", "Files")
        if os.path.isdir(cand):
            return cand

    return "."


COMMON_DIR = find_common_files_dir()


def read_master_data() -> dict:
    filepath = os.path.join(COMMON_DIR, "bonus_hedge_master.dat")
    if not os.path.isfile(filepath):
        return {"online": False, "count": 0, "positions": []}

    try:
        with open(filepath, "rb") as f:
            data = f.read()

        if len(data) < 52:
            return {"online": False, "count": 0, "positions": []}

        offset = 0
        magic_peek, = struct.unpack_from("<q", data, 0)
        if magic_peek == 0x42484246:
            magic, version, counter, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqqqdddddi", data, offset
            )
            offset += struct.calcsize("<qqqqdddddi")
            t_stamp = time.time()
        else:
            t_stamp, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqdddddi", data, offset
            )
            offset += struct.calcsize("<qqdddddi")

        positions = []
        for _ in range(count):
            if offset + 36 > len(data):
                break
            ticket, p_type, vol, price_open, profit, clen = struct.unpack_from("<qidddi", data, offset)
            offset += struct.calcsize("<qidddi")
            comment = ""
            if clen > 0 and offset + clen <= len(data):
                comment = data[offset:offset+clen].decode("utf-8", errors="ignore")
                offset += clen

            positions.append({
                "ticket": ticket,
                "type": "BUY" if p_type == 0 else "SELL",
                "volume": round(vol, 2),
                "price_open": round(price_open, 2),
                "profit": round(profit, 2),
                "comment": comment
            })

        is_online = (time.time() - t_stamp <= 5) if t_stamp > 0 else False
        return {
            "online": is_online,
            "timestamp": t_stamp,
            "login": login,
            "equity": round(equity, 2),
            "balance": round(balance, 2),
            "free_margin": round(free_margin, 2),
            "margin_level": round(margin_level, 2),
            "profit": round(total_prof, 2),
            "count": count,
            "positions": positions
        }
    except Exception as e:
        return {"online": False, "count": 0, "positions": [], "error": str(e)}


def read_slave_data() -> dict:
    filepath = os.path.join(COMMON_DIR, "bonus_hedge_slave.dat")
    if not os.path.isfile(filepath):
        return {"online": False, "count": 0, "positions": []}

    try:
        with open(filepath, "rb") as f:
            data = f.read()

        if len(data) < 52:
            return {"online": False, "count": 0, "positions": []}

        offset = 0
        magic_peek, = struct.unpack_from("<q", data, 0)
        if magic_peek == 0x42484246:
            magic, version, counter, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqqqdddddi", data, offset
            )
            offset += struct.calcsize("<qqqqdddddi")
            t_stamp = time.time()
        else:
            t_stamp, login, equity, balance, free_margin, margin_level, total_prof, count = struct.unpack_from(
                "<qqdddddi", data, offset
            )
            offset += struct.calcsize("<qqdddddi")

        positions = []
        for _ in range(count):
            if offset + 36 > len(data):
                break
            ticket, p_type, vol, price_open, profit, clen = struct.unpack_from("<qidddi", data, offset)
            offset += struct.calcsize("<qidddi")
            comment = ""
            if clen > 0 and offset + clen <= len(data):
                comment = data[offset:offset+clen].decode("utf-8", errors="ignore")
                offset += clen

            positions.append({
                "ticket": ticket,
                "type": "BUY" if p_type == 0 else "SELL",
                "volume": round(vol, 2),
                "price_open": round(price_open, 2),
                "profit": round(profit, 2),
                "comment": comment
            })

        is_online = (time.time() - t_stamp <= 5) if t_stamp > 0 else False
        return {
            "online": is_online,
            "timestamp": t_stamp,
            "login": login,
            "equity": round(equity, 2),
            "balance": round(balance, 2),
            "free_margin": round(free_margin, 2),
            "margin_level": round(margin_level, 2),
            "profit": round(total_prof, 2),
            "count": count,
            "positions": positions
        }
    except Exception as e:
        return {"online": False, "count": 0, "positions": [], "error": str(e)}


def build_dashboard_data() -> dict:
    m = read_master_data()
    s = read_slave_data()

    m_prof = m.get("profit", 0.0) if m.get("online") else 0.0
    s_prof = s.get("profit", 0.0) if s.get("online") else 0.0
    net_floating = round(m_prof + s_prof, 2)

    m_positions = m.get("positions", [])
    s_positions = s.get("positions", [])

    pairs = []
    for m_pos in m_positions:
        m_t = m_pos["ticket"]
        tag = f"CT#{m_t}"
        matching_s = next((p for p in s_positions if tag in p.get("comment", "")), None)

        pair_net = round(m_pos["profit"] + (matching_s["profit"] if matching_s else 0.0), 2)
        pairs.append({
            "master_ticket": m_t,
            "master_type": m_pos["type"],
            "master_vol": m_pos["volume"],
            "master_price": m_pos["price_open"],
            "master_profit": m_pos["profit"],
            "slave_ticket": matching_s["ticket"] if matching_s else "-",
            "slave_type": matching_s["type"] if matching_s else "-",
            "slave_vol": matching_s["volume"] if matching_s else 0.0,
            "slave_price": matching_s["price_open"] if matching_s else 0.0,
            "slave_profit": matching_s["profit"] if matching_s else 0.0,
            "net_profit": pair_net
        })

    try:
        host_ip = socket.gethostbyname(socket.gethostname())
    except Exception:
        host_ip = "127.0.0.1"

    return {
        "host_ip": host_ip,
        "net_floating": net_floating,
        "target_tp": 31.74,
        "master": m,
        "slave": s,
        "pairs": pairs,
        "common_dir": COMMON_DIR
    }


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Dual-MT5 Bonus Hedging Live Monitor</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@500;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #f8fafc;
      --card-bg: #ffffff;
      --card-border: #e2e8f0;
      --text-main: #0f172a;
      --text-muted: #64748b;
      --green: #16a34a;
      --red: #dc2626;
      --gold: #d97706;
      --blue: #2563eb;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Inter', sans-serif; -webkit-tap-highlight-color: transparent; }
    body { background: var(--bg); color: var(--text-main); padding: 12px; display: flex; justify-content: center; min-height: 100vh; }
    .container { width: 100%; max-width: 480px; display: flex; flex-direction: column; gap: 10px; }

    /* Top Column Headers */
    .header-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; text-align: center; font-size: 13px; font-weight: 800; color: #64748b; letter-spacing: 0.5px; padding: 4px 0; }
    
    /* 2-Column Metric Grid */
    .grid-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .metric-card { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 12px; padding: 10px 14px; display: flex; flex-direction: column; justify-content: center; min-height: 62px; box-shadow: 0 1px 2px rgba(0,0,0,0.02); }
    .m-label { font-size: 11px; font-weight: 600; color: var(--text-muted); }
    .m-val { font-size: 15px; font-weight: 800; color: var(--text-main); font-family: 'Inter', sans-serif; }
    .m-sub { font-size: 11px; font-weight: 500; color: var(--text-muted); margin-top: 1px; }
    .m-sub-status { font-size: 11px; font-weight: 600; color: #d97706; display: flex; align-items: center; gap: 4px; }

    /* Detail Posisi Header */
    .positions-header { font-size: 12px; font-weight: 800; color: #64748b; letter-spacing: 0.5px; margin-top: 6px; padding: 0 2px; display: flex; justify-content: space-between; align-items: center; }
    
    /* Position Cards */
    .pos-card { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 12px; padding: 12px 14px; display: flex; flex-direction: column; gap: 6px; box-shadow: 0 1px 2px rgba(0,0,0,0.02); }
    .pos-tickets { font-size: 13px; font-weight: 700; color: #0f172a; }
    .pos-legs { font-size: 12px; font-weight: 600; display: flex; justify-content: space-between; color: var(--text-muted); }
    .leg-m-val { font-weight: 700; }
    .leg-s-val { font-weight: 700; }
    .pos-net-row { text-align: right; font-size: 14px; font-weight: 800; margin-top: 2px; }
    
    .green-text { color: var(--green); }
    .red-text { color: var(--red); }
  </style>
</head>
<body>
  <div class="container">
    
    <!-- Column Titles -->
    <div class="header-cols">
      <div>MASTER</div>
      <div>SLAVE</div>
    </div>

    <!-- Row 1: Rate -->
    <div class="grid-row">
      <div class="metric-card">
        <div class="m-label">Rate</div>
        <div class="m-val" id="m-rate">17.745</div>
        <div class="m-sub-status">↻ berjalan</div>
      </div>
      <div class="metric-card">
        <div class="m-label">Rate</div>
        <div class="m-val" id="s-rate">17.745</div>
        <div class="m-sub-status">↻ berjalan</div>
      </div>
    </div>

    <!-- Row 2: Bid/Ask -->
    <div class="grid-row">
      <div class="metric-card">
        <div class="m-label">Bid/Ask</div>
        <div class="m-val" id="m-bidask">4579.07/4579.35</div>
      </div>
      <div class="metric-card">
        <div class="m-label">Bid/Ask</div>
        <div class="m-val" id="s-bidask">4579.07/4579.35</div>
      </div>
    </div>

    <!-- Row 3: Equity -->
    <div class="grid-row">
      <div class="metric-card">
        <div class="m-label">Equity</div>
        <div class="m-val" id="m-equity">$0.00</div>
        <div class="m-sub" id="m-bal-cr">Bal 0,00 · Cr 0,00</div>
      </div>
      <div class="metric-card">
        <div class="m-label">Equity</div>
        <div class="m-val" id="s-equity">$0.00</div>
        <div class="m-sub" id="s-bal-cr">Bal 0,00 · Cr 0,00</div>
      </div>
    </div>

    <!-- Row 4: MC (Margin Call Price) -->
    <div class="grid-row">
      <div class="metric-card">
        <div class="m-label">MC</div>
        <div class="m-val" style="color: #d97706;" id="m-mc">@0.00</div>
        <div class="m-sub" id="m-mc-pips">+0.0 pips</div>
      </div>
      <div class="metric-card">
        <div class="m-label">MC</div>
        <div class="m-val" style="color: #d97706;" id="s-mc">@0.00</div>
        <div class="m-sub" id="s-mc-pips">-0.0 pips</div>
      </div>
    </div>

    <!-- Row 5: Margin Level -->
    <div class="grid-row">
      <div class="metric-card">
        <div class="m-label">Margin Level</div>
        <div class="m-val" id="m-margin-level">0.00%</div>
      </div>
      <div class="metric-card">
        <div class="m-label">Margin Level</div>
        <div class="m-val" id="s-margin-level">0.00%</div>
      </div>
    </div>

    <!-- Positions Section Header -->
    <div class="positions-header">
      <span>DETAIL POSISI (<span id="pair-count">0</span>) · POS M/S: <span id="pos-ms">0/0</span></span>
      <span>▼</span>
    </div>

    <!-- Position Cards List -->
    <div id="positions-list" style="display: flex; flex-direction: column; gap: 10px;">
      <div style="text-align: center; color: var(--text-muted); font-size: 13px; padding: 25px;">
        Menunggu posisi aktif...
      </div>
    </div>

  </div>

  <script>
    const USD_RATE = 17745; // Kurs Rupiah per USD

    function formatNumber(num) {
      return (num || 0).toLocaleString('id-ID', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    function formatRupiah(num) {
      return 'Rp' + Math.round(num || 0).toLocaleString('id-ID');
    }

    async function updateDashboard() {
      try {
        const res = await fetch('/api/data');
        const d = await res.json();

        const m = d.master || {};
        const s = d.slave || {};
        const pairs = d.pairs || [];

        // Master Equity & Balance
        document.getElementById('m-equity').textContent = '$' + formatNumber(m.equity);
        document.getElementById('m-bal-cr').textContent = `Bal ${formatNumber(m.balance)} · Cr 0,00`;
        document.getElementById('m-margin-level').textContent = (m.margin_level || 0).toFixed(2) + '%';

        // Slave Equity & Balance & Credit
        document.getElementById('s-equity').textContent = '$' + formatNumber(s.equity);
        const crVal = (s.equity && s.balance && s.equity > s.balance) ? (s.equity - s.balance) : (s.balance ? s.balance * 0.20 : 0);
        document.getElementById('s-bal-cr').textContent = `Bal ${formatNumber(s.balance)} · Cr ${formatNumber(crVal)}`;
        document.getElementById('s-margin-level').textContent = (s.margin_level || 0).toFixed(2) + '%';

        // Bid / Ask
        if (pairs.length > 0) {
          const p0 = pairs[0];
          document.getElementById('m-bidask').textContent = `${(p0.master_price||0).toFixed(2)}/${((p0.master_price||0)+0.28).toFixed(2)}`;
          document.getElementById('s-bidask').textContent = `${(p0.slave_price||0).toFixed(2)}/${((p0.slave_price||0)+0.28).toFixed(2)}`;
        }

        // MC Calculation (Simulated estimation based on Free Margin)
        const mFree = m.free_margin || 0;
        const sFree = s.free_margin || 0;
        const mLot = pairs.reduce((sum, p) => sum + (p.master_vol || 0), 0);
        const sLot = pairs.reduce((sum, p) => sum + (p.slave_vol || 0), 0);

        if (mLot > 0) {
          const mDist = (mFree / (mLot * 100));
          const mMCPrice = (pairs[0].master_price || 4600) + mDist;
          document.getElementById('m-mc').textContent = `@${mMCPrice.toFixed(2)}`;
          document.getElementById('m-mc-pips').textContent = `+${(mDist * 10).toFixed(1)} pips`;
        }
        if (sLot > 0) {
          const sDist = (sFree / (sLot * 100));
          const sMCPrice = (pairs[0].slave_price || 4600) - sDist;
          document.getElementById('s-mc').textContent = `@${sMCPrice.toFixed(2)}`;
          document.getElementById('s-mc-pips').textContent = `-${(sDist * 10).toFixed(1)} pips`;
        }

        // Header Counts
        document.getElementById('pair-count').textContent = pairs.length;
        document.getElementById('pos-ms').textContent = `${m.count || 0}/${s.count || 0}`;

        // Render Positions List
        const listEl = document.getElementById('positions-list');
        if (pairs.length === 0) {
          listEl.innerHTML = '<div style="text-align: center; color: var(--text-muted); font-size: 13px; padding: 25px;">Menunggu posisi aktif...</div>';
        } else {
          listEl.innerHTML = pairs.map(p => {
            const mProf = p.master_profit || 0;
            const sProf = p.slave_profit || 0;
            const netProf = p.net_profit || 0;

            const mSign = mProf >= 0 ? '+' : '';
            const sSign = sProf >= 0 ? '+' : '';
            const netSign = netProf >= 0 ? '+' : '-';

            const mColor = mProf >= 0 ? 'green-text' : 'red-text';
            const sColor = sProf >= 0 ? 'green-text' : 'red-text';
            const netColor = netProf >= 0 ? 'green-text' : 'red-text';

            const mRp = formatRupiah(mProf * USD_RATE);
            const sRp = formatRupiah(sProf * USD_RATE);
            const netRp = formatRupiah(Math.abs(netProf) * USD_RATE);

            return `
              <div class="pos-card">
                <div class="pos-tickets">
                  #${p.master_ticket} S ${p.master_vol}@${p.master_price} ⇄ #${p.slave_ticket} B ${p.slave_vol}@${p.slave_price}
                </div>
                <div class="pos-legs">
                  <span>M <span class="${mColor}">${mSign}$${formatNumber(Math.abs(mProf))}</span> <span style="font-size:11px;">≈${mRp}</span></span>
                  <span>S <span class="${sColor}">${sSign}$${formatNumber(Math.abs(sProf))}</span> <span style="font-size:11px;">≈${sRp}</span></span>
                </div>
                <div class="pos-net-row ${netColor}">
                  ${netSign}$${formatNumber(Math.abs(netProf))} <span style="font-size:12px; font-weight:700;">≈${netSign}${netRp}</span>
                </div>
              </div>
            `;
          }).join('');
        }
      } catch (e) {
        console.error("Poll error:", e);
      }
    }

    setInterval(updateDashboard, 1000);
    updateDashboard();
  </script>
</body>
</html>
"""


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class DashboardHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path.startswith("/api/data"):
                data = build_dashboard_data()
                body = json.dumps(data).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(body)
            else:
                body = HTML_TEMPLATE.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except Exception as e:
            try:
                self.send_error(500, str(e))
            except Exception:
                pass

    def log_message(self, format, *args):
        return


def start_cloudflared():
    cloudflared_bin = os.path.join(os.path.dirname(__file__), "cloudflared.exe")
    if not os.path.isfile(cloudflared_bin):
        # Auto-download if missing
        try:
            import urllib.request
            print("[*] Mengunduh cloudflared.exe...")
            urllib.request.urlretrieve(
                "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe",
                cloudflared_bin
            )
        except Exception as e:
            print(f"[!] Gagal unduh cloudflared: {e}")
            return

    def run_cf():
        try:
            proc = subprocess.Popen(
                [cloudflared_bin, "tunnel", "--url", f"http://127.0.0.1:{PORT}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="ignore"
            )
            for line in iter(proc.stderr.readline, ""):
                match = re.search(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com", line)
                if match:
                    url = match.group(0)
                    print("\n" + "=" * 65)
                    print(f" 🌐 LINK KHUSUS NOTEBOOK / MAC ANDA (KLIK / BUKA INI):")
                    print(f" 👉 {url}")
                    print("=" * 65 + "\n")
        except Exception as e:
            print(f"[!] Error tunnel: {e}")

    t = threading.Thread(target=run_cf, daemon=True)
    t.start()


def main():
    start_cloudflared()
    server = ThreadingHTTPServer(("0.0.0.0", PORT), DashboardHandler)
    print(f"\n" + "=" * 65)
    print(f" 🚀 LIVE VISUAL DASHBOARD BERJALAN!")
    print(f" 👉 Akses Lokal VPS   : http://localhost:{PORT}")
    print(f" 👉 Shared Folder MT5 : {COMMON_DIR}")
    print(f"=" * 65)
    print(f" ⏳ Menyiapkan Public Link untuk Notebook Anda...\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Server dihentikan.")


if __name__ == "__main__":
    main()
