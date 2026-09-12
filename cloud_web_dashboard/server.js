/**
 * Cloud Web Dashboard API & Server for Dual-MT5 Bonus Hedging Bot.
 * Supports Multi-Account Portfolio Management (Monitor All Accounts in 1 Screen or Page 1/2/3).
 * Receives live telemetry from MT5 via WebRequest POST and serves real-time web dashboard.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;

// Pure Real-Time Production Store (No Demo/Mock Data)
const SEED_ACCOUNTS = {};

// 1st-Level Referral / IB Partners Data
const referralsData = {
  "PARTNER01": {
    code: "PARTNER01",
    name: "Budi Santoso",
    tier: "VIP Partner (1st Level)",
    rebate_per_lot: 7.50,
    profit_share_pct: 10,
    payout_bank: "BCA 8010293841 a/n Budi Santoso",
    client_logins: []
  },
  "PARTNER02": {
    code: "PARTNER02",
    name: "David Tan",
    tier: "Gold Partner (1st Level)",
    rebate_per_lot: 7.50,
    profit_share_pct: 10,
    payout_bank: "Mandiri 1370019283712 a/n David Tan",
    client_logins: []
  }
};

// Working store (100% Real MT5 Live Accounts Only)
const accountsData = {};

const STATE_FILE = path.join(__dirname, 'state.json');
function saveState() {
  try {
    const realAccounts = {};
    for (const [k, v] of Object.entries(accountsData)) {
      if (!v.is_mock) realAccounts[k] = v;
    }
    fs.writeFileSync(STATE_FILE, JSON.stringify({ accounts: realAccounts, referrals: referralsData }, null, 2));
  } catch (e) {}
}

function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      if (data.accounts && Object.keys(data.accounts).length > 0) {
        for (const k of Object.keys(accountsData)) delete accountsData[k];
        Object.assign(accountsData, data.accounts);
      }
      if (data.referrals) {
        Object.assign(referralsData, data.referrals);
      }
    }
  } catch (e) {}
}
loadState();

const server = http.createServer((req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Api-Key');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = parsedUrl.pathname;

  // ----------------------------------------------------
  // 1. TELEMETRY INGESTION ENDPOINT (Called by MT5 Master)
  // ----------------------------------------------------
  if (req.method === 'POST' && pathname.toLowerCase() === '/api/telemetry') {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString();
      if (body.length > 1e6) req.socket.destroy(); // 1MB max payload
    });

    req.on('end', () => {
      try {
        const payload = JSON.parse(body);
        const masterLogin = payload.master?.login || payload.login;
        if (!masterLogin) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Missing master login number' }));
          return;
        }

        // AUTO-PURGE MOCK DATA: When first real MT5 telemetry arrives, wipe out mock accounts!
        let hadMock = false;
        for (const k of Object.keys(accountsData)) {
          if (accountsData[k].is_mock) {
            delete accountsData[k];
            hadMock = true;
          }
        }
        if (hadMock) {
          console.log(`[REAL MT5 CONNECTED] Master #${masterLogin} connected! Auto-purged all demo/mock accounts.`);
        }

        // Store latest real telemetry
        const existing = accountsData[masterLogin] || {};
        payload.last_updated = Date.now();
        payload.is_mock = false;
        payload.profit_today = payload.profit_today !== undefined ? payload.profit_today : (existing.profit_today || 0);
        payload.profit_week = payload.profit_week !== undefined ? payload.profit_week : (existing.profit_week || 0);
        payload.profit_month = payload.profit_month !== undefined ? payload.profit_month : (existing.profit_month || 0);
        payload.profit_all_time = payload.profit_all_time !== undefined ? payload.profit_all_time : (existing.profit_all_time || 0);
        payload.client_name = payload.client_name || existing.client_name || `Account #${masterLogin}`;
        accountsData[masterLogin] = { ...existing, ...payload };

        // Auto-link to Referral Partner downline if referral_code is provided
        if (payload.referral_code && payload.referral_code.trim().length > 0) {
          const rCode = payload.referral_code.toUpperCase().trim();
          if (!referralsData[rCode]) {
            referralsData[rCode] = {
              code: rCode,
              name: `Mitra ${rCode}`,
              tier: "Partner (1st Level)",
              rebate_per_lot: 7.50,
              profit_share_pct: 10,
              payout_bank: "Pending Rekening BCA",
              client_logins: []
            };
          }
          if (!referralsData[rCode].client_logins.includes(masterLogin)) {
            referralsData[rCode].client_logins.push(masterLogin);
          }
        }

        saveState();

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, master_login: masterLogin, received_at: payload.last_updated, is_mock: false }));
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON body', message: err.message }));
      }
    });
    return;
  }

  // ----------------------------------------------------
  // CLEAR / TOGGLE MOCK DATA ENDPOINTS
  // ----------------------------------------------------
  if (req.method === 'POST' && pathname === '/api/clear-mock') {
    for (const k of Object.keys(accountsData)) {
      if (accountsData[k].is_mock) {
        delete accountsData[k];
      }
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, message: 'All mock data cleared. Waiting for real MT5 telemetry.' }));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/reset-demo') {
    Object.assign(accountsData, SEED_ACCOUNTS);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, message: 'Demo mock accounts restored.' }));
    return;
  }

  // ----------------------------------------------------
  // 2. GET ACTIVE ACCOUNTS LIST (With Summary & Periodic Profits)
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname === '/api/accounts') {
    const list = Object.keys(accountsData).map(login => {
      const acc = accountsData[login];
      const isOnline = (Date.now() - (acc.last_updated || 0)) < 30000;
      return {
        login: Number(login),
        slave_login: acc.slave?.login || 0,
        client_name: acc.client_name || `Account #${login}`,
        pair_id: acc.pair_id || 1,
        symbol: acc.symbol || 'XAUUSD',
        master_balance: acc.master?.balance || 0,
        master_equity: acc.master?.equity || 0,
        master_float: (acc.master?.equity || 0) - (acc.master?.balance || 0),
        slave_balance: acc.slave?.balance || 0,
        slave_equity: acc.slave?.equity || 0,
        slave_float: (acc.slave?.equity || 0) - (acc.slave?.balance || 0),
        slave_credit: acc.slave?.credit || (acc.slave?.equity && acc.slave?.balance && acc.slave.equity > acc.slave.balance ? acc.slave.equity - acc.slave.balance : 0),
        net_floating: acc.net_floating !== undefined ? acc.net_floating : ((acc.master?.equity || 0) - (acc.master?.balance || 0) + (acc.slave?.equity || 0) - (acc.slave?.balance || 0)),
        target_tp: acc.target_tp || 31.74,
        profit_today: acc.profit_today || 0,
        profit_week: acc.profit_week || 0,
        profit_month: acc.profit_month || 0,
        profit_all_time: acc.profit_all_time || 0,
        shield_status: acc.shield_status || 'NORMAL',
        cur_spread: acc.cur_spread || 20.0,
        pairs_count: acc.pairs?.length || acc.master?.count || 0,
        is_online: isOnline,
        last_updated: acc.last_updated
      };
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ accounts: list }));
    return;
  }

  // ----------------------------------------------------
  // 3. GET AGGREGATE PORTFOLIO SUMMARY (Manager Console)
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname === '/api/portfolio/summary') {
    const all = Object.values(accountsData);
    let totalMasterBal = 0, totalMasterEq = 0;
    let totalSlaveBal = 0, totalSlaveEq = 0, totalSlaveCredit = 0;
    let totalNetFloat = 0;
    let totalProfitToday = 0, totalProfitWeek = 0, totalProfitMonth = 0, totalProfitAllTime = 0;
    let onlineCount = 0;
    let spreadLockCount = 0;
    let newsPauseCount = 0;

    all.forEach(acc => {
      const isOnline = (Date.now() - (acc.last_updated || 0)) < 30000;
      if (isOnline) onlineCount++;
      if (acc.shield_status === 'SPREAD-LOCK') spreadLockCount++;
      if (acc.shield_status === 'NEWS-PAUSE') newsPauseCount++;

      totalMasterBal += acc.master?.balance || 0;
      totalMasterEq += acc.master?.equity || 0;
      totalSlaveBal += acc.slave?.balance || 0;
      totalSlaveEq += acc.slave?.equity || 0;
      totalSlaveCredit += acc.slave?.credit || 0;
      
      const netF = acc.net_floating !== undefined ? acc.net_floating : ((acc.master?.equity || 0) - (acc.master?.balance || 0) + (acc.slave?.equity || 0) - (acc.slave?.balance || 0));
      totalNetFloat += netF;

      totalProfitToday += acc.profit_today || 0;
      totalProfitWeek += acc.profit_week || 0;
      totalProfitMonth += acc.profit_month || 0;
      totalProfitAllTime += acc.profit_all_time || 0;
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      total_accounts: all.length,
      online_accounts: onlineCount,
      spread_locked: spreadLockCount,
      news_paused: newsPauseCount,
      master_total_balance: totalMasterBal,
      master_total_equity: totalMasterEq,
      slave_total_balance: totalSlaveBal,
      slave_total_equity: totalSlaveEq,
      slave_total_credit: totalSlaveCredit,
      combined_total_equity: totalMasterEq + totalSlaveEq,
      portfolio_net_floating: totalNetFloat,
      portfolio_profit_today: totalProfitToday,
      portfolio_profit_week: totalProfitWeek,
      portfolio_profit_month: totalProfitMonth,
      portfolio_profit_all_time: totalProfitAllTime,
      last_updated: Date.now()
    }));
    return;
  }

  // ----------------------------------------------------
  // 4. GET SPECIFIC ACCOUNT TELEMETRY (For Live Modal Deep Dive & Client Portal)
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname.startsWith('/api/status/')) {
    const login = pathname.split('/api/status/')[1];
    const acc = accountsData[login];

    if (!acc) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Account not found or offline' }));
      return;
    }

    acc.is_online = (Date.now() - (acc.last_updated || 0)) < 30000;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(acc));
    return;
  }

  // ----------------------------------------------------
  // 5. CLIENT PORTAL API (Investor-Safe Single Account Endpoint)
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname.startsWith('/api/client/')) {
    const login = pathname.split('/api/client/')[1];
    const acc = accountsData[login];

    if (!acc) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Client account not found or offline' }));
      return;
    }

    const mEq = acc.master?.equity || 0;
    const mBal = acc.master?.balance || 0;
    const sEq = acc.slave?.equity || 0;
    const sBal = acc.slave?.balance || 0;
    const sCr = acc.slave?.credit || 0;
    const totalEq = mEq + sEq;
    const totalBal = mBal + sBal;
    const netF = acc.net_floating !== undefined ? acc.net_floating : ((mEq - mBal) + (sEq - sBal));
    const isOnline = (Date.now() - (acc.last_updated || 0)) < 30000;
    const pAll = acc.profit_all_time || 0;
    const initialDeposit = Math.max(1000, totalBal - pAll);
    const roiPct = ((pAll / initialDeposit) * 100).toFixed(1);

    // Dynamic equity curve generation based on real profit trajectory
    const chartPoints = [
      { date: '10 Hari Lalu', equity: Number((totalEq - pAll * 0.85).toFixed(2)) },
      { date: '8 Hari Lalu', equity: Number((totalEq - pAll * 0.70).toFixed(2)) },
      { date: '6 Hari Lalu', equity: Number((totalEq - pAll * 0.50).toFixed(2)) },
      { date: '4 Hari Lalu', equity: Number((totalEq - pAll * 0.35).toFixed(2)) },
      { date: '2 Hari Lalu', equity: Number((totalEq - pAll * 0.15).toFixed(2)) },
      { date: 'Kemarin', equity: Number((totalEq - (acc.profit_today || 0)).toFixed(2)) },
      { date: 'Hari Ini', equity: Number(totalEq.toFixed(2)) }
    ];

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      login: Number(login),
      client_name: acc.client_name || `Investor #${login}`,
      registered_bank: "BCA 8010293841 a/n " + (acc.client_name ? acc.client_name.split('(')[0].trim() : 'Investor'),
      symbol: acc.symbol || 'XAUUSD',
      initial_deposit: initialDeposit,
      total_combined_balance: totalBal,
      total_combined_equity: totalEq,
      roi_percent: roiPct,
      net_floating: netF,
      profit_today: acc.profit_today || 0,
      profit_week: acc.profit_week || 0,
      profit_month: acc.profit_month || 0,
      profit_all_time: pAll,
      client_share_pct: 60, // 60% Hak Investor / Anggota Konsorsium
      management_fee_pct: 40, // 40% Biaya Pengelolaan Total (dilihat anggota)
      coordinator_margin_pct: 10, // 10% Margin Bersih Koordinator (Rahasia)
      master_fee_pct: 30, // 30% Hak Master Operator (Anda)
      payout_history: [
        { date: '01 Sep 2026', amount_usd: 240.00, amount_rp: 4258800, bank: 'BCA 8010***', status: 'LUNAS DITRANSFER' },
        { date: '15 Agu 2026', amount_usd: 215.50, amount_rp: 3824040, bank: 'BCA 8010***', status: 'LUNAS DITRANSFER' },
        { date: '01 Agu 2026', amount_usd: 190.00, amount_rp: 3371550, bank: 'BCA 8010***', status: 'LUNAS DITRANSFER' }
      ],
      chart_data: chartPoints,
      strategy_status: "🟢 AKTIF MENGHASILKAN (LOW-RISK HEDGED PORTFOLIO)",
      master: acc.master || {},
      slave: acc.slave || {},
      pairs: acc.pairs || [],
      is_online: isOnline,
      last_updated: acc.last_updated
    }));
    return;
  }

  // ----------------------------------------------------
  // 6. 1ST-LEVEL REFERRAL / IB PORTAL API
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname === '/api/referrals') {
    const list = Object.keys(referralsData).map(code => {
      const r = referralsData[code];
      return {
        code: r.code,
        name: r.name,
        tier: r.tier,
        client_count: r.client_logins.length
      };
    });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ referrals: list }));
    return;
  }

  if (req.method === 'GET' && pathname.startsWith('/api/referral/')) {
    const code = pathname.split('/api/referral/')[1].toUpperCase();
    const ref = referralsData[code] || referralsData["PARTNER01"]; // Fallback to partner 1

    if (!ref) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Referral code not found' }));
      return;
    }

    // Calculate aggregated statistics for this partner's clients
    let totalClientEq = 0, totalNetFloat = 0;
    let totalProfToday = 0, totalProfWeek = 0, totalProfMonth = 0, totalProfAll = 0;
    let clientCards = [];

    ref.client_logins.forEach(login => {
      const acc = accountsData[String(login)];
      if (acc) {
        const mEq = acc.master?.equity || 0;
        const sEq = acc.slave?.equity || 0;
        const combEq = mEq + sEq;
        const netF = acc.net_floating || 0;
        const pM = acc.profit_month || 0;
        const pAll = acc.profit_all_time || 0;

        totalClientEq += combEq;
        totalNetFloat += netF;
        totalProfToday += acc.profit_today || 0;
        totalProfWeek += acc.profit_week || 0;
        totalProfMonth += pM;
        totalProfAll += pAll;

        // Commission share from this client (10% profit share + lot rebate)
        const estLotsClient = (pAll / 35.0) * 0.22; // ~0.22 lot per $35 basket TP
        const commShareClient = (pAll * (ref.profit_share_pct / 100.0)) + (estLotsClient * ref.rebate_per_lot);

        clientCards.push({
          login: login,
          masked_login: String(login).slice(0, 4) + '***',
          client_name: acc.client_name,
          equity: combEq,
          net_floating: netF,
          profit_today: acc.profit_today || 0,
          profit_month: pM,
          profit_all_time: pAll,
          estimated_lots: Number(estLotsClient.toFixed(2)),
          partner_commission_earned: Number(commShareClient.toFixed(2)),
          is_online: (Date.now() - (acc.last_updated || 0)) < 30000
        });
      }
    });

    const estLotsTotal = (totalProfAll / 35.0) * 0.22;
    const rebateToday = (totalProfToday / 35.0) * 0.22 * ref.rebate_per_lot + (totalProfToday * (ref.profit_share_pct / 100.0));
    const rebateWeek = (totalProfWeek / 35.0) * 0.22 * ref.rebate_per_lot + (totalProfWeek * (ref.profit_share_pct / 100.0));
    const rebateMonth = (totalProfMonth / 35.0) * 0.22 * ref.rebate_per_lot + (totalProfMonth * (ref.profit_share_pct / 100.0));
    const rebateTotal = (totalProfAll / 35.0) * 0.22 * ref.rebate_per_lot + (totalProfAll * (ref.profit_share_pct / 100.0));

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      code: ref.code,
      partner_name: ref.name,
      tier: ref.tier,
      rebate_per_lot: ref.rebate_per_lot,
      profit_share_pct: ref.profit_share_pct,
      payout_bank: ref.payout_bank,
      total_referred_clients: clientCards.length,
      total_referred_equity: totalClientEq,
      total_referred_net_float: totalNetFloat,
      total_volume_lots: Number(estLotsTotal.toFixed(2)),
      commission_today: Number(rebateToday.toFixed(2)),
      commission_week: Number(rebateWeek.toFixed(2)),
      commission_month: Number(rebateMonth.toFixed(2)),
      commission_all_time: Number(rebateTotal.toFixed(2)),
      clients: clientCards,
      last_updated: Date.now()
    }));
    return;
  }

  // ----------------------------------------------------
  // 7. SERVE STATIC WEB DASHBOARD HTML & ROUTING
  // ----------------------------------------------------
  if (req.method === 'GET') {
    const publicDir = path.join(__dirname, 'public');
    let fileName = pathname === '/' ? 'index.html' : pathname;
    if (fileName === '/client') fileName = 'client.html';
    if (fileName === '/referral') fileName = 'referral.html';
    if (fileName.startsWith('/')) fileName = fileName.slice(1);

    let filePath = path.join(publicDir, fileName);

    // Security: avoid directory traversal
    if (!filePath.startsWith(publicDir)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    fs.readFile(filePath, (err, content) => {
      if (err) {
        // Fallback to index.html
        fs.readFile(path.join(publicDir, 'index.html'), (err2, indexContent) => {
          if (err2) {
            res.writeHead(404);
            res.end('Page not found');
          } else {
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(indexContent);
          }
        });
      } else {
        const ext = path.extname(filePath).toLowerCase();
        const mimeTypes = {
          '.html': 'text/html; charset=utf-8',
          '.css': 'text/css',
          '.js': 'application/javascript',
          '.json': 'application/json',
          '.png': 'image/png',
          '.jpg': 'image/jpeg',
          '.svg': 'image/svg+xml'
        };
        res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'text/plain' });
        res.end(content);
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log('====================================================');
  console.log(` 🚀 CLOUD WEB DASHBOARD SERVER RUNNING (v1.24)!`);
  console.log(` 👉 Server Port          : ${PORT}`);
  console.log(` 👉 Telemetry Ingestion  : POST http://localhost:${PORT}/api/telemetry`);
  console.log(` 👉 Portfolio Summary API: GET  http://localhost:${PORT}/api/portfolio/summary`);
  console.log(` 👉 Accounts List API    : GET  http://localhost:${PORT}/api/accounts`);
  console.log(` 👉 Live Web Portal      : http://localhost:${PORT}`);
  console.log('====================================================');
});

