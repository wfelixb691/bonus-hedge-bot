/**
 * NOVA HEDGE // Dual-Quant Trading OS & Client Portal Backend
 * Complete 3-Level MLM Revenue & Commission Settlement Engine
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

// Sanitasi PORT: '' / undefined / 0 / NaN / 'abc' → fallback 4000
const PORT = parseInt(process.env.PORT, 10) > 0 ? parseInt(process.env.PORT, 10) : 4000;

// Central User Datastore with 3-Level Downline Relationships
const db = {
  users: [
    {
      id: "USR-1000",
      userid: "admin",
      name: "Administrator",
      email: "admin@novahedge.io",
      phone: "+62 812-3037-7777",
      password: "admin123",
      readonly_password: "demo123456",
      rank: "V6 PRESIDENT",
      fuel_balance: 100.00,
      referral_code: "ADMIN888",
      sponsor_code: "ROOT",
      join_date: "01 Sep 2026",
      deposit: 3000.00,
      mt5_master: { broker: "Prime Codex", server: "PrimeCodex-Live", login: 100870, equity: 3420.50, balance: 3000.00 },
      mt5_slave: { broker: "Prime Codex (bonus 20% LP)", server: "PrimeCodex-Bonus", login: 100871, equity: 2950.00, balance: 3000.00, credit: 600.00 },
      lots_traded: 18.4,
      total_profit: 672.35,
      vps_status: "ACTIVE",
      vps_fee_idr: 128000,
      vps_fee_usdt: 8.00,
      vps_expires_at: "06 Okt 2026"
    },
    // LEVEL 1 DIRECT OF ADMIN
    {
      id: "USR-1001",
      userid: "maharindra",
      name: "Mahar Indra",
      email: "mahar.indra@gmail.com",
      phone: "+62 812-3037-7777",
      password: "admin123",
      readonly_password: "demo123456",
      rank: "V2 LEADER",
      fuel_balance: 64.50,
      referral_code: "MAHAR88",
      sponsor_code: "ADMIN888", // Direct L1
      join_date: "01 Sep 2026",
      deposit: 3000.00,
      mt5_master: { broker: "Prime Codex", server: "PrimeCodex-Live", login: 100870, equity: 3420.50, balance: 3000.00 },
      mt5_slave: { broker: "Prime Codex (bonus 20% LP)", server: "PrimeCodex-Bonus", login: 100871, equity: 2950.00, balance: 3000.00, credit: 600.00 },
      lots_traded: 18.4,
      total_profit: 672.35,
      vps_status: "ACTIVE",
      vps_fee_idr: 128000,
      vps_fee_usdt: 8.00,
      vps_expires_at: "06 Okt 2026"
    },
    {
      id: "USR-1002",
      userid: "hermawan",
      name: "Hermawan Lesmana",
      email: "hermawan@gmail.com",
      phone: "+62 812-3456-7890",
      password: "admin123",
      readonly_password: "",
      rank: "V1 PARTNER",
      fuel_balance: 50.00,
      referral_code: "HERMAWAN",
      sponsor_code: "ADMIN888", // Direct L1
      join_date: "06 Agu 2026",
      deposit: 3000.00,
      mt5_master: { broker: "Prime Codex", server: "PrimeCodex-Live", login: 100912, equity: 2210.00, balance: 2000.00 },
      mt5_slave: { broker: "Prime Codex (bonus 20% LP)", server: "PrimeCodex-Bonus", login: 100913, equity: 1980.00, balance: 2000.00, credit: 400.00 },
      lots_traded: 18.4,
      total_profit: 540.00,
      vps_status: "ACTIVE",
      vps_fee_idr: 128000,
      vps_fee_usdt: 8.00,
      vps_expires_at: "06 Okt 2026"
    },
    {
      id: "USR-1003",
      userid: "barry",
      name: "BARRY HII CHAY WEE",
      email: "barry@gmail.com",
      phone: "+60 12-345-6789",
      password: "admin123",
      readonly_password: "",
      rank: "V1 PARTNER",
      fuel_balance: 40.00,
      referral_code: "BARRY88",
      sponsor_code: "ADMIN888", // Direct L1
      join_date: "12 Agu 2026",
      deposit: 2000.00,
      mt5_master: { broker: "Prime Codex", server: "PrimeCodex-Live", login: 100922, equity: 2150.00, balance: 2000.00 },
      mt5_slave: { broker: "Prime Codex (bonus 20% LP)", server: "PrimeCodex-Bonus", login: 100923, equity: 1920.00, balance: 2000.00, credit: 400.00 },
      lots_traded: 10.2,
      total_profit: 320.00,
      vps_status: "ACTIVE",
      vps_fee_idr: 128000,
      vps_fee_usdt: 8.00,
      vps_expires_at: "06 Okt 2026"
    },
    // LEVEL 2 (INDIRECT - SPONSORED BY HERMAWAN)
    {
      id: "USR-1004",
      userid: "yeoh",
      name: "Yeoh Kok Wooi",
      email: "yeoh@gmail.com",
      phone: "+60 19-888-9999",
      password: "admin123",
      readonly_password: "",
      rank: "V1 MEMBER",
      fuel_balance: 35.00,
      referral_code: "YEOH88",
      sponsor_code: "HERMAWAN", // L2 of Admin
      join_date: "18 Agu 2026",
      deposit: 2000.00,
      mt5_master: { broker: "Prime Codex", server: "PrimeCodex-Live", login: 100934, equity: 2100.00, balance: 2000.00 },
      mt5_slave: { broker: "Prime Codex (bonus 20% LP)", server: "PrimeCodex-Bonus", login: 100935, equity: 1890.00, balance: 2000.00, credit: 400.00 },
      lots_traded: 8.5,
      total_profit: 260.00,
      vps_status: "ACTIVE",
      vps_fee_idr: 128000,
      vps_fee_usdt: 8.00,
      vps_expires_at: "06 Okt 2026"
    },
    // LEVEL 3 (SUB-INDIRECT - SPONSORED BY YEOH)
    {
      id: "USR-1005",
      userid: "kevin",
      name: "Kevin Sanjaya",
      email: "kevin@gmail.com",
      phone: "+62 813-9999-1234",
      password: "admin123",
      readonly_password: "",
      rank: "V1 MEMBER",
      fuel_balance: 25.00,
      referral_code: "KEVIN88",
      sponsor_code: "YEOH88", // L3 of Admin
      join_date: "25 Agu 2026",
      deposit: 1500.00,
      mt5_master: { broker: "Prime Codex", server: "PrimeCodex-Live", login: 100946, equity: 1580.00, balance: 1500.00 },
      mt5_slave: { broker: "Prime Codex (bonus 20% LP)", server: "PrimeCodex-Bonus", login: 100947, equity: 1420.00, balance: 1500.00, credit: 300.00 },
      lots_traded: 5.0,
      total_profit: 180.00,
      vps_status: "ACTIVE",
      vps_fee_idr: 128000,
      vps_fee_usdt: 8.00,
      vps_expires_at: "06 Okt 2026"
    }
  ],
  reset_tokens: {},
  daily_revenue: [
    { date: "2026-09-01", master_profit: 672.35, gross_tp: 960.50, investor_net: 672.35, fuel_fee_30: 288.15 }
  ],
  settlements: []
};

/**
 * 3-LEVEL PROFIT SHARING & REBATE ALGORITHM ENGINE
 */
function getTierRateByDeposit(deposit) {
  if (deposit >= 20000) return { tier: "VIP Whale", perfFee: 0.20, investorRate: 0.80 };
  if (deposit >= 5000) return { tier: "Growth Pro", perfFee: 0.25, investorRate: 0.75 };
  return { tier: "Starter", perfFee: 0.30, investorRate: 0.70 };
}

function calculate3TierNetworkReport(adminUserid) {
  const root = db.users.find(u => u.userid === adminUserid) || db.users[0];
  const rootRef = root.referral_code;

  // 1. Find Level 1 (Directs)
  const level1Users = db.users.filter(u => u.sponsor_code === rootRef);
  const l1Refs = level1Users.map(u => u.referral_code);

  // 2. Find Level 2 (Indirects)
  const level2Users = db.users.filter(u => l1Refs.includes(u.sponsor_code));
  const l2Refs = level2Users.map(u => u.referral_code);

  // 3. Find Level 3 (Sub-Indirects)
  const level3Users = db.users.filter(u => l2Refs.includes(u.sponsor_code));

  // Compute L1 Stats
  const l1Omzet = level1Users.reduce((sum, u) => sum + (u.deposit || 0), 0);
  const l1Lots = level1Users.reduce((sum, u) => sum + (u.lots_traded || 0), 0);
  const l1Profit = level1Users.reduce((sum, u) => sum + (u.total_profit || 0), 0);
  const l1Commissions = (l1Profit * 0.10) + (l1Lots * 4.00);

  // Compute L2 Stats
  const l2Omzet = level2Users.reduce((sum, u) => sum + (u.deposit || 0), 0);
  const l2Lots = level2Users.reduce((sum, u) => sum + (u.lots_traded || 0), 0);
  const l2Profit = level2Users.reduce((sum, u) => sum + (u.total_profit || 0), 0);
  const l2Commissions = (l2Profit * 0.03) + (l2Lots * 2.00);

  // Compute L3 Stats
  const l3Omzet = level3Users.reduce((sum, u) => sum + (u.deposit || 0), 0);
  const l3Lots = level3Users.reduce((sum, u) => sum + (u.lots_traded || 0), 0);
  const l3Profit = level3Users.reduce((sum, u) => sum + (u.total_profit || 0), 0);
  const l3Commissions = (l3Profit * 0.02) + (l3Lots * 1.00);

  const totalOmzet = l1Omzet + l2Omzet + l3Omzet;
  const totalMembers = level1Users.length + level2Users.length + level3Users.length;
  const totalCommissions = l1Commissions + l2Commissions + l3Commissions;

  return {
    summary: {
      total_omzet: totalOmzet,
      total_members: totalMembers,
      total_commissions: totalCommissions,
      l1_summary: { members: level1Users.length, omzet: l1Omzet, lots: l1Lots, commission: l1Commissions },
      l2_summary: { members: level2Users.length, omzet: l2Omzet, lots: l2Lots, commission: l2Commissions },
      l3_summary: { members: level3Users.length, omzet: l3Omzet, lots: l3Lots, commission: l3Commissions }
    },
    levels: {
      level1: level1Users.map(u => ({ ...u, level: 1, share_earned: (u.total_profit * 0.10), rebate_earned: (u.lots_traded * 4.00) })),
      level2: level2Users.map(u => ({ ...u, level: 2, share_earned: (u.total_profit * 0.03), rebate_earned: (u.lots_traded * 2.00) })),
      level3: level3Users.map(u => ({ ...u, level: 3, share_earned: (u.total_profit * 0.02), rebate_earned: (u.lots_traded * 1.00) }))
    }
  };
}

// NOTE: global.live_mt5_states = { [masterLogin]: {...telemetry} } — keyed per MT5
// master login (multi-investor safe). Dibaca oleh endpoint /api/mt5/live.
//
// HANYA ditulis di modul ini. Aman untuk Vercel serverless: setiap lambda instance
// memegang store-nya sendiri (telemetry sender selalu POST /api/mt5/sync dan GET
// /api/mt5/live datang ke instance yang sama karena traffic hangat).

/**
 * Request handler — kompatibel kontrak @vercel/node (module.exports = fn(req, res)).
 * Juga dipakai oleh http.createServer di mode lokal (`node server.js`)
 * dan oleh test_platform.js.
 */
async function novaHedgeHandler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = parsedUrl.pathname;

  // 1. 3-TIER NETWORK & OMZET REPORT API
  if (req.method === 'GET' && pathname === '/api/network/3tier-report') {
    const userid = parsedUrl.searchParams.get('userid') || 'admin';
    const report = calculate3TierNetworkReport(userid);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, report }));
    return;
  }

  // 2. USER REGISTRATION API
  if (req.method === 'POST' && pathname === '/api/auth/register') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const email = (p.email || '').trim().toLowerCase();
        const userid = (p.userid || '').trim().toLowerCase();
        const password = p.password || '';
        const name = p.name || 'Member Baru';
        const phone = p.phone || '';
        const sponsor = p.sponsor || 'ADMIN888';

        if (!email || !userid || !password) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Email, User ID, dan Password wajib diisi!" }));
          return;
        }

        const exists = db.users.find(u => u.email === email || u.userid === userid);
        if (exists) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Email atau User ID sudah terdaftar. Silakan login!" }));
          return;
        }

        const newUser = {
          id: `USR-${Math.floor(1000 + Math.random() * 9000)}`,
          userid: userid,
          name: name,
          email: email,
          phone: phone,
          password: password,
          readonly_password: "",
          rank: "V1 MEMBER",
          fuel_balance: 0.00,
          referral_code: userid.toUpperCase(),
          sponsor_code: sponsor,
          join_date: new Date().toLocaleDateString("id-ID", { day: '2-digit', month: 'short', year: 'numeric' }),
          deposit: 1000.00,
          mt5_master: null,
          mt5_slave: null,
          lots_traded: 0.0,
          total_profit: 0.00
        };

        db.users.push(newUser);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: "Pendaftaran berhasil! Silakan login.", user: newUser }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 3. USER LOGIN API
  if (req.method === 'POST' && pathname === '/api/auth/login') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const loginId = (p.login_id || '').trim().toLowerCase();
        const password = p.password || '';

        // Full login: user must match by email/userid AND their own password.
        // (Removed universal 'admin123' bypass — it allowed anyone to log in as any user.)
        const fullUser = db.users.find(u => 
          (u.email.toLowerCase() === loginId || u.userid.toLowerCase() === loginId) && 
          u.password === password
        );

        if (fullUser) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ success: true, is_readonly: false, user: fullUser }));
          return;
        }

        // Read-only presentation password: per-user, only when that user set one.
        const readOnlyUser = db.users.find(u => 
          (u.email.toLowerCase() === loginId || u.userid.toLowerCase() === loginId) && 
          u.readonly_password && u.readonly_password === password
        );

        if (readOnlyUser) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ 
            success: true, 
            is_readonly: true, 
            message: "Masuk dalam Mode Presentasi (Read-Only). Semua data hanya bisa dilihat!",
            user: readOnlyUser 
          }));
          return;
        }

        res.writeHead(401, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: "User ID / Email atau Password salah!" }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 3b. FORGOT PASSWORD — issue OTP token (valid 5 minutes)
  if (req.method === 'POST' && pathname === '/api/auth/forgot-password') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const email = (p.email || '').trim().toLowerCase();
        const user = db.users.find(u => u.email.toLowerCase() === email);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Email tidak ditemukan." }));
          return;
        }
        const otp = String(Math.floor(100000 + Math.random() * 900000));
        if (!db.reset_tokens) db.reset_tokens = {};
        db.reset_tokens[email] = { otp, expires: Date.now() + 5 * 60 * 1000 };
        console.log(`🔑 [RESET OTP] ${email}: ${otp} (valid 5 menit)`);
        // Demo mode: OTP dikembalikan ke client karena belum ada email service terpasang.
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: "Kode OTP berhasil dibuat (demo mode).", demo_otp_code: otp }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 3c. RESET PASSWORD — verify OTP, then set new password
  if (req.method === 'POST' && pathname === '/api/auth/reset-password') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const email = (p.email || '').trim().toLowerCase();
        const otp = String(p.otp || '').trim();
        const newPass = p.new_password || '';

        if (!newPass || newPass.length < 6) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Password baru minimal 6 karakter." }));
          return;
        }

        const token = db.reset_tokens ? db.reset_tokens[email] : null;
        if (!token || token.otp !== otp) {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "OTP salah atau tidak valid." }));
          return;
        }
        if (Date.now() > token.expires) {
          delete db.reset_tokens[email];
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "OTP sudah kedaluwarsa. Minta kode baru." }));
          return;
        }

        const user = db.users.find(u => u.email.toLowerCase() === email);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Email tidak ditemukan." }));
          return;
        }

        user.password = newPass;
        delete db.reset_tokens[email];
        console.log(`🔑 [PASSWORD RESET] ${email} berhasil reset password.`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: "Password berhasil direset! Silakan login dengan password baru." }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 3d. CHANGE PASSWORD — authenticated user replaces their own login password
  // (dipakai untuk mengganti password default 'admin123' setelah deployment)
  if (req.method === 'POST' && pathname === '/api/auth/change-password') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const userid = (p.userid || '').trim().toLowerCase();
        const currentPass = p.current_password || '';
        const newPass = p.new_password || '';

        const user = db.users.find(u => u.userid.toLowerCase() === userid);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "User tidak ditemukan." }));
          return;
        }
        if (user.password !== currentPass) {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Password saat ini salah!" }));
          return;
        }
        if (!newPass || newPass.length < 6) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Password baru minimal 6 karakter." }));
          return;
        }
        if (newPass === currentPass) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Password baru harus berbeda dari password saat ini." }));
          return;
        }

        user.password = newPass;
        console.log(`🔑 [PASSWORD CHANGE] ${user.userid} mengganti password login.`);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, message: "Password login berhasil diganti! Gunakan password baru untuk login berikutnya." }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 4. SET / UPDATE READ-ONLY PASSWORD API
  if (req.method === 'POST' && pathname === '/api/user/set-readonly-password') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const userid = p.userid;
        const currentPass = p.current_password;
        const newReadonlyPass = (p.readonly_password || '').trim();

        const user = db.users.find(u => u.userid === userid);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "User tidak ditemukan." }));
          return;
        }
        // Verifikasi password login sebelum boleh mengubah password read-only
        if (user.password !== currentPass) {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Password login saat ini salah!" }));
          return;
        }
        user.readonly_password = newReadonlyPass;

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
          success: true, 
          readonly_enabled: !!newReadonlyPass,
          message: newReadonlyPass ? "Password Read-Only Presentasi aktif!" : "Password Read-Only dinonaktifkan." 
        }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 5. BINDING DUAL-MT5 ACCOUNT API
  if (req.method === 'POST' && pathname === '/api/user/bind-mt5') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const user = db.users.find(u => u.userid === p.userid);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "User tidak ditemukan." }));
          return;
        }

        user.mt5_master = {
          broker: "Prime Codex",
          server: "PrimeCodex-Live",
          login: parseInt(p.master_login || 100870),
          equity: parseFloat(p.deposit || 2000),
          balance: parseFloat(p.deposit || 2000)
        };
        user.mt5_slave = {
          broker: "Prime Codex (bonus 20% LP)",
          server: "PrimeCodex-Bonus",
          login: parseInt(p.slave_login || 100871),
          equity: parseFloat(p.deposit || 2000) * 1.20,
          balance: parseFloat(p.deposit || 2000),
          credit: parseFloat(p.deposit || 2000) * 0.20
        };

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, user }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 6. TOP UP FUEL GAS API
  if (req.method === 'POST' && pathname === '/api/user/topup-fuel') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const amount = parseFloat(p.amount || 50);
        const user = db.users.find(u => u.userid === p.userid);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "User tidak ditemukan." }));
          return;
        }
        if (!Number.isFinite(amount) || amount <= 0) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Nominal top-up tidak valid." }));
          return;
        }

        user.fuel_balance += amount;

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, balance: user.fuel_balance }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 6b. PAY / EXTEND VPS SUBSCRIPTION API ($8.00 / 8 USDT per bulan)
  if (req.method === 'POST' && pathname === '/api/user/pay-vps') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);
        const user = db.users.find(u => u.userid === p.userid);
        if (!user) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "User tidak ditemukan." }));
          return;
        }

        const vpsFeeUSDT = 8.00; // Flat $8 / 8 USDT per bulan (~Rp 128.000)
        if (user.fuel_balance < vpsFeeUSDT) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ 
            error: `Saldo Gas Fuel tidak cukup untuk membayar sewa VPS. Butuh minimal ${vpsFeeUSDT.toFixed(2)} USDT ($8.00). Silakan isi Gas Fuel terlebih dahulu.` 
          }));
          return;
        }

        // Deduct VPS fee from fuel balance
        user.fuel_balance = Number((user.fuel_balance - vpsFeeUSDT).toFixed(2));
        user.vps_status = "ACTIVE";

        // Extend expiry by 30 days
        const curExp = user.vps_expires_at && user.vps_expires_at !== '-' ? new Date(user.vps_expires_at) : new Date();
        const baseDate = (curExp > new Date()) ? curExp : new Date();
        baseDate.setDate(baseDate.getDate() + 30);
        user.vps_expires_at = baseDate.toLocaleDateString("id-ID", { day: '2-digit', month: 'short', year: 'numeric' });

        // Record in settlements
        if (!db.settlements) db.settlements = [];
        db.settlements.unshift({
          type: "VPS_FEE",
          userid: user.userid,
          amount_usdt: vpsFeeUSDT,
          amount_idr: 128000,
          date: new Date().toISOString(),
          description: "Biaya Sewa VPS Cloud MT5 Eropa (30 Hari / $8.00)"
        });

        console.log(`🖥️ [VPS SUBSCRIPTION PAID] User ${user.userid}: Paid ${vpsFeeUSDT} USDT ($8.00). Exp: ${user.vps_expires_at}`);

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
          success: true, 
          message: `Sewa VPS berhasil diperpanjang 30 hari hingga ${user.vps_expires_at}!`,
          balance: user.fuel_balance,
          vps_status: user.vps_status,
          vps_expires_at: user.vps_expires_at
        }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 7. REAL-TIME MT5 CLOUD SYNC CONNECTOR (VPS -> WEB)
  if (req.method === 'POST' && (pathname === '/api/mt5/sync' || pathname === '/api/telemetry')) {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const p = JSON.parse(body);

        // NaN-safe numeric parser — bad/missing telemetry must never poison balances
        const num = (v, fb) => { const n = Number(v); return Number.isFinite(n) ? n : fb; };

        // Build position pairs
        let pairs = [];
        if (p.pairs && Array.isArray(p.pairs) && p.pairs.length > 0) {
          pairs = p.pairs.map((pr, idx) => ({
            layer: pr.layer || idx + 1,
            master: pr.master || {
              ticket: pr.master_ticket || pr.ticket || 0,
              type: pr.master_type || pr.type || "SELL",
              volume: Number(pr.master_vol || pr.volume || 0.15),
              price_open: Number(pr.master_price || pr.price_open || 0.0),
              profit: Number(pr.master_profit || pr.profit || 0.0)
            },
            slave: pr.slave || {
              ticket: pr.slave_ticket || 0,
              type: pr.slave_type || "BUY",
              volume: Number(pr.slave_vol || 0.17),
              price_open: Number(pr.slave_price || 0.0),
              profit: Number(pr.slave_profit || 0.0)
            },
            net_profit: Number(pr.net_profit !== undefined ? pr.net_profit : ((pr.master_profit || 0) + (pr.slave_profit || 0))).toFixed(2)
          }));
        } else {
          const masterPositions = p.master?.positions || [];
          const slavePositions = p.slave?.positions || [];
          masterPositions.forEach((mp, idx) => {
            const expectedTag = `CT#${mp.ticket}`;
            let sp = slavePositions.find(s => s.comment && String(s.comment).includes(expectedTag));
            if (!sp && slavePositions[idx]) {
              sp = slavePositions[idx];
            }
            const mProf = Number(mp.profit || 0);
            const sProf = sp ? Number(sp.profit || 0) : 0;
            const netP = Number((mProf + sProf).toFixed(2));

            pairs.push({
              layer: idx + 1,
              master: {
                ticket: mp.ticket,
                type: mp.type || "SELL",
                volume: Number(mp.volume || 0.15),
                price_open: Number(mp.price_open || 0.0),
                profit: mProf
              },
              slave: sp ? {
                ticket: sp.ticket,
                type: sp.type || "BUY",
                volume: Number(sp.volume || 0.17),
                price_open: Number(sp.price_open || 0.0),
                profit: sProf
              } : null,
              net_profit: netP
            });
          });
        }

        // Update Live Telemetry Store
        const mEq = Number(p.master?.equity || 0);
        const sEq = Number(p.slave?.equity || 0);
        const mBal = Number(p.master?.balance || 0);
        const sBal = Number(p.slave?.balance || 0);

        // Update Live Telemetry Store — keyed per MT5 master login (multi-investor safe).
        const stateLogin = String(p.master?.login || p.login || '').trim();
        if (!stateLogin) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: "Telemetry sync wajib menyertakan master.login sebagai identifier." }));
          return;
        }

        if (!global.live_mt5_states) global.live_mt5_states = {};
        global.live_mt5_states[stateLogin] = {
          login: stateLogin,
          updated_at: new Date().toISOString(),
          online: true,
          master: p.master || {},
          slave: p.slave || {},
          pairs: pairs,
          total_floating: p.net_floating !== undefined ? num(p.net_floating, 0).toFixed(2) : (num(p.master?.profit, 0) + num(p.slave?.profit, 0)).toFixed(2),
          total_equity: p.total_equity || (mEq + sEq) || 0,
          pure_cash_equity: p.pure_cash_equity || (mBal + sBal) || 0,
          surplus: p.surplus || 0.0,
          status_engine: p.status_engine || "🟢 ACTIVE HEDGING (Live MT5)",
          recent_cycles: p.recent_cycles || []
        };

        // If cycle event arrived, update admin profit, daily revenue, and DEDUCT user fuel balance automatically
        if (p.cycle_event) {
          const ev = p.cycle_event;
          const todayStr = new Date().toISOString().split('T')[0];
          if (!db.daily_revenue) db.daily_revenue = [];
          let todayRev = db.daily_revenue.find(r => r.date === todayStr);
          if (!todayRev) {
            todayRev = { date: todayStr, master_profit: 0, gross_tp: 0, investor_net: 0, fuel_fee_30: 0 };
            db.daily_revenue.push(todayRev);
          }
          // NaN-safe parsing: missing/garbage fields fall back to 0, never NaN
          const grossProfit = num(ev.gross_profit, 0);
          const fee = num(ev.share_fee, grossProfit * 0.3);
          const netProfit = num(ev.investor_net, grossProfit * 0.7);
          const evMasterProfit = num(ev.master_profit, grossProfit);

          todayRev.master_profit += evMasterProfit;
          todayRev.gross_tp += grossProfit;
          todayRev.investor_net += netProfit;
          todayRev.fuel_fee_30 += fee;
          // (Removed: db.users[0].total_profit += netProfit — it double-credited the
          //  admin because targetUser.total_profit is credited again below.)

          // Find target investor account & automatically deduct fuel balance.
          // (Removed silent fallback to 'maharindra' — no login match means no credit.)
          const masterLogin = p.master?.login || p.login;
          const targetUser = db.users.find(u => u.mt5_master?.login == masterLogin);
          if (targetUser) {
            targetUser.fuel_balance = Math.max(0, Number((targetUser.fuel_balance - fee).toFixed(2)));
            targetUser.total_profit = Number((targetUser.total_profit + netProfit).toFixed(2));
            console.log(`⚡ [AUTO PROFIT SHARING DEDUCTED] User ${targetUser.userid}: Fee -${fee.toFixed(2)} USDT deducted. Remaining Fuel: ${targetUser.fuel_balance.toFixed(2)} USDT`);

            // AUTOMATIC 3-LEVEL UPLINE COMMISSION DISTRIBUTION
            if (grossProfit > 0) {
              // Level 1 Upline (10% profit sharing)
              let uplineL1 = db.users.find(u => u.referral_code === targetUser.sponsor_code);
              if (uplineL1) {
                const commL1 = Number((grossProfit * 0.10).toFixed(2));
                uplineL1.fuel_balance = Number((uplineL1.fuel_balance + commL1).toFixed(2));
                uplineL1.total_commission = Number(((uplineL1.total_commission || 0) + commL1).toFixed(2));
                console.log(`💰 [L1 COMMISSION PAID] ${uplineL1.userid} earned +${commL1} USDT (10%) from ${targetUser.userid}`);

                // Level 2 Upline (3% profit sharing)
                let uplineL2 = db.users.find(u => u.referral_code === uplineL1.sponsor_code);
                if (uplineL2) {
                  const commL2 = Number((grossProfit * 0.03).toFixed(2));
                  uplineL2.fuel_balance = Number((uplineL2.fuel_balance + commL2).toFixed(2));
                  uplineL2.total_commission = Number(((uplineL2.total_commission || 0) + commL2).toFixed(2));
                  console.log(`💰 [L2 COMMISSION PAID] ${uplineL2.userid} earned +${commL2} USDT (3%) from ${targetUser.userid}`);

                  // Level 3 Upline (2% profit sharing)
                  let uplineL3 = db.users.find(u => u.referral_code === uplineL2.sponsor_code);
                  if (uplineL3) {
                    const commL3 = Number((grossProfit * 0.02).toFixed(2));
                    uplineL3.fuel_balance = Number((uplineL3.fuel_balance + commL3).toFixed(2));
                    uplineL3.total_commission = Number(((uplineL3.total_commission || 0) + commL3).toFixed(2));
                    console.log(`💰 [L3 COMMISSION PAID] ${uplineL3.userid} earned +${commL3} USDT (2%) from ${targetUser.userid}`);
                  }
                }
              }
            }
          }
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
          success: true, 
          message: "Live MT5 Telemetry synced successfully!", 
          timestamp: new Date().toISOString() 
        }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // 8. GET REAL-TIME LIVE MT5 STATUS API (FOR FRONTEND)
  //    Each investor reads only their own telemetry: /api/mt5/live?login=<master_login>
  //    Single-account deployment without ?login= still works: serves the only known stream.
  if (req.method === 'GET' && pathname === '/api/mt5/live') {
    const requestedLogin = String(parsedUrl.searchParams.get('login') || '').trim();
    const STALE_MS = 15000; // >15s tanpa sync = anggap offline

    const store = global.live_mt5_states || {};
    let liveState = requestedLogin ? store[requestedLogin] : null;
    if (!liveState && !requestedLogin) {
      const allStates = Object.values(store);
      if (allStates.length > 0) {
        // Fallback to the most recently active telemetry stream
        allStates.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
        liveState = allStates[0];
      }
    }

    if (liveState) {
      const ageMs = Date.now() - new Date(liveState.updated_at).getTime();
      liveState = { ...liveState, online: Number.isFinite(ageMs) && ageMs <= STALE_MS };
    }

    if (!liveState) {
      // No fake demo data — honest standby state until the VPS sender syncs.
      liveState = {
        updated_at: new Date().toISOString(),
        online: false,
        master: {},
        slave: {},
        pairs: [],
        total_floating: "0.00",
        total_equity: 0,
        pure_cash_equity: 0,
        surplus: 0,
        status_engine: "⚪ STANDBY — Menunggu telemetry MT5...",
        recent_cycles: []
      };
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(liveState));
    return;
  }

  // 7. SERVE STATIC FILES
  if (req.method === 'GET') {
    // Unknown API routes → JSON 404 (bukan fallback ke index.html)
    if (pathname.startsWith('/api/')) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'API endpoint tidak ditemukan' }));
      return;
    }

    const publicDir = path.join(__dirname, 'public');
    let filePath = path.join(publicDir, pathname === '/' ? 'index.html' : pathname);

    if (!filePath.startsWith(publicDir)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    fs.readFile(filePath, (err, content) => {
      if (err) {
        fs.readFile(path.join(publicDir, 'index.html'), (err2, indexContent) => {
          if (err2) {
            res.writeHead(404);
            res.end('Page Not Found');
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
}

// Kontrak @vercel/node: default export harus berupa fungsi handler (req, res) => void.
// (Sebelumnya mengekspor instance http.Server — itu sebabnya API call di Vercel gagal
//  dan frontend butuh fallback mock.)
module.exports = novaHedgeHandler;

// Dipakai test_platform.js untuk listen di port ephemeral; tidak berdampak di Vercel.
module.exports.server = novaHedgeHandler.server = http.createServer(novaHedgeHandler);

// Mode lokal: `node server.js` / `npm start` — jalan sebagai server HTTP biasa.
if (require.main === module) {
  novaHedgeHandler.server.listen(PORT, () => {
    console.log('=====================================================================');
    console.log(' 🛡️ NOVA HEDGE // 3-TIER MLM REVENUE & OMZET REPORT ENGINE ONLINE');
    console.log(` 📍 Web Portal : http://localhost:${PORT}`);
    console.log(` 💎 3-Level    : L1 (10% + $4/L), L2 (3% + $2/L), L3 (2% + $1/L)`);
    console.log('=====================================================================');
  });
}
