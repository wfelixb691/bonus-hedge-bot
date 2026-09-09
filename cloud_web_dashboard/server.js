/**
 * Cloud Web Dashboard API & Server for Dual-MT5 Bonus Hedging Bot.
 * Receives live telemetry from MT5 via WebRequest POST and serves real-time web dashboard.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;

// In-memory telemetry cache keyed by Master Login ID
const accountsData = {};

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
  if (req.method === 'POST' && pathname === '/api/telemetry') {
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

        // Store latest telemetry with receive timestamp
        payload.last_updated = Date.now();
        accountsData[masterLogin] = payload;

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, master_login: masterLogin, received_at: payload.last_updated }));
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON body', message: err.message }));
      }
    });
    return;
  }

  // ----------------------------------------------------
  // 2. GET ACTIVE ACCOUNTS LIST (For Admin/Client Selector)
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname === '/api/accounts') {
    const list = Object.keys(accountsData).map(login => {
      const acc = accountsData[login];
      const isOnline = (Date.now() - (acc.last_updated || 0)) < 15000;
      return {
        login: Number(login),
        symbol: acc.symbol || 'XAUUSD',
        master_equity: acc.master?.equity || 0,
        slave_equity: acc.slave?.equity || 0,
        net_floating: acc.net_floating || 0,
        pairs_count: acc.pairs?.length || 0,
        is_online: isOnline,
        last_updated: acc.last_updated
      };
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ accounts: list }));
    return;
  }

  // ----------------------------------------------------
  // 3. GET SPECIFIC ACCOUNT TELEMETRY (For Live Dashboard)
  // ----------------------------------------------------
  if (req.method === 'GET' && pathname.startsWith('/api/status/')) {
    const login = pathname.split('/api/status/')[1];
    const acc = accountsData[login];

    if (!acc) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Account not found or offline' }));
      return;
    }

    acc.is_online = (Date.now() - (acc.last_updated || 0)) < 15000;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(acc));
    return;
  }

  // ----------------------------------------------------
  // 4. SERVE STATIC WEB DASHBOARD HTML
  // ----------------------------------------------------
  if (req.method === 'GET') {
    const publicDir = path.join(__dirname, 'public');
    let filePath = path.join(publicDir, pathname === '/' ? 'index.html' : pathname);

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
  console.log(` 🚀 CLOUD WEB DASHBOARD SERVER RUNNING!`);
  console.log(` 👉 Server Port       : ${PORT}`);
  console.log(` 👉 Telemetry Endpoint: POST http://localhost:${PORT}/api/telemetry`);
  console.log(` 👉 Live Web Portal   : http://localhost:${PORT}`);
  console.log('====================================================');
});
