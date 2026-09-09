/**
 * Smoke test — NOVA HEDGE platform bug fixes
 * Jalankan: node test_platform.js
 * Server di-require sebagai module & listen di port ephemeral, lalu assertions dijalankan.
 */
const http = require('http');

const novaHedgeHandler = require('./server.js');

// Kontrak @vercel/node: export harus function, bukan instance http.Server
if (typeof novaHedgeHandler !== 'function' || typeof novaHedgeHandler.call !== 'function') {
  console.error('❌ FATAL: module.exports bukan fungsi handler — deploy Vercel akan gagal');
  process.exit(1);
}
if (typeof novaHedgeHandler.server !== 'object' || typeof novaHedgeHandler.server.listen !== 'function') {
  console.error('❌ FATAL: .server (http.Server untuk mode lokal) hilang');
  process.exit(1);
}
console.log('✅ Export check: handler function + .server (http.Server) ada — kontrak Vercel & lokal OK');

const server = novaHedgeHandler.server;

let passed = 0, failed = 0;
function check(name, cond, extra) {
  if (cond) { passed++; console.log(`  ✅ ${name}`); }
  else { failed++; console.log(`  ❌ ${name}${extra ? ' — ' + extra : ''}`); }
}

function req(method, path, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const options = {
      host: '127.0.0.1',
      port: server.address().port,
      path,
      method,
      headers: data ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } : {}
    };
    const r = http.request(options, res => {
      let out = '';
      res.on('data', c => out += c);
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(out); } catch (e) {}
        resolve({ status: res.statusCode, json, raw: out });
      });
    });
    r.on('error', reject);
    if (data) r.write(data);
    r.end();
  });
}

async function main() {
  await new Promise(r => server.close(r)); // tutup dulu (jaga-jaga double require)
  await new Promise(r => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  console.log(`\n🧪 Testing on ${base}\n`);

  // ---------- 1. AUTH BYPASS DIHAPUS ----------
  console.log('1) Auth: universal password bypass');
  let r = await req('POST', '/api/auth/register', { email: 'tester1@test.io', userid: 'tester1', password: 'uniquepass1', name: 'Tester One' });
  check('register user baru untuk test', r.status === 200, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'hermawan', password: 'uniquepass1' });
  check('password milik user lain tidak bisa login ke akun lain (401)', r.status === 401, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'admin', password: 'admin123' });
  check('login admin dengan password benarnya tetap sukses', r.status === 200 && r.json.success, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'admin', password: 'demo123456' });
  check('read-only admin via demo123456 tetap jalan', r.status === 200 && r.json.is_readonly === true, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'hermawan', password: 'demo123456' });
  check('read-only user TANPA readonly_password ditolak', r.status === 401, `got ${r.status}`);

  // ---------- 2. FORGOT / RESET PASSWORD ----------
  console.log('2) Forgot & reset password endpoint');
  r = await req('POST', '/api/auth/forgot-password', { email: 'hermawan@gmail.com' });
  const otp = r.json && r.json.demo_otp_code;
  check('forgot-password menghasilkan OTP', r.status === 200 && !!otp, `got ${r.status}`);
  r = await req('POST', '/api/auth/reset-password', { email: 'hermawan@gmail.com', otp: '000000', new_password: 'newpass99' });
  check('reset dengan OTP salah ditolak (401)', r.status === 401, `got ${r.status}`);
  r = await req('POST', '/api/auth/reset-password', { email: 'hermawan@gmail.com', otp, new_password: 'short' });
  check('reset dengan password terlalu pendek ditolak', r.status === 400, `got ${r.status}`);
  r = await req('POST', '/api/auth/reset-password', { email: 'hermawan@gmail.com', otp, new_password: 'newpass99' });
  check('reset dengan OTP benar sukses', r.status === 200 && r.json.success, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'hermawan@gmail.com', password: 'newpass99' });
  check('login dengan password hasil reset sukses', r.status === 200 && r.json.success, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'hermawan', password: 'admin123' });
  check('password LAMA hermawan (admin123) tidak berlaku lagi — bypass universal hilang', r.status === 401, `got ${r.status}`);

  // ---------- 3. SET-READONLY WAJIB VERIFIKASI PASSWORD ----------
  console.log('3) Set read-only password: verifikasi current_password');
  r = await req('POST', '/api/user/set-readonly-password', { userid: 'hermawan', current_password: 'SALAH', readonly_password: 'ro12345' });
  check('current_password salah ditolak (401)', r.status === 401, `got ${r.status}`);
  r = await req('POST', '/api/user/set-readonly-password', { userid: 'hermawan', current_password: 'newpass99', readonly_password: 'ro12345' });
  check('current_password benar → read-only aktif', r.status === 200 && r.json.success, `got ${r.status}`);
  r = await req('POST', '/api/user/set-readonly-password', { userid: 'TIDAK ADA', current_password: 'x', readonly_password: 'ro12345' });
  check('userid tidak dikenal ditolak (404), bukan fallback ke admin', r.status === 404, `got ${r.status}`);

  // ---------- 3b. CHANGE PASSWORD ----------
  console.log('3b) Change password endpoint');
  r = await req('POST', '/api/auth/change-password', { userid: 'hermawan', current_password: 'SALAH', new_password: 'newherma77' });
  check('change-password current_password salah ditolak (401)', r.status === 401, `got ${r.status}`);
  r = await req('POST', '/api/auth/change-password', { userid: 'hermawan', current_password: 'newpass99', new_password: 'abc' });
  check('password baru terlalu pendek ditolak (400)', r.status === 400, `got ${r.status}`);
  r = await req('POST', '/api/auth/change-password', { userid: 'hermawan', current_password: 'newpass99', new_password: 'newpass99' });
  check('password baru sama dengan lama ditolak (400)', r.status === 400, `got ${r.status}`);
  r = await req('POST', '/api/auth/change-password', { userid: 'TIDAK ADA', current_password: 'x', new_password: 'newherma77' });
  check('userid tidak dikenal ditolak (404), bukan fallback ke admin', r.status === 404, `got ${r.status}`);
  r = await req('POST', '/api/auth/change-password', { userid: 'hermawan', current_password: 'newpass99', new_password: 'newherma77' });
  check('change-password sukses', r.status === 200 && r.json.success, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'hermawan', password: 'newpass99' });
  check('password LAMA tidak berlaku setelah change (401)', r.status === 401, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'hermawan', password: 'newherma77' });
  check('login dengan password BARU sukses', r.status === 200 && r.json.success, `got ${r.status}`);
  // default admin123 bisa diganti juga (pakai akun barry yang masih default)
  r = await req('POST', '/api/auth/change-password', { userid: 'barry', current_password: 'admin123', new_password: 'barrysecure1' });
  check('password default admin123 bisa diganti via endpoint', r.status === 200 && r.json.success, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'barry', password: 'admin123' });
  check('login barry dengan admin123 ditolak setelah diganti (401)', r.status === 401, `got ${r.status}`);

  // ---------- 4. TELEMETRY PER-LOGIN ----------
  console.log('4) Telemetry keyed per MT5 login');
  r = await req('POST', '/api/mt5/sync', { master: { balance: 2000, equity: 2100, profit: 100 } }); // tanpa login
  check('sync tanpa master.login ditolak (400)', r.status === 400, `got ${r.status}`);
  r = await req('POST', '/api/mt5/sync', {
    master: { login: 100912, balance: 2000, equity: 2100, profit: 100.5 },
    slave: { login: 100913, balance: 2000, equity: 1900, profit: -99.5 },
    net_floating: 1.0
  });
  check('sync dengan master.login sukses', r.status === 200, `got ${r.status}`);
  r = await req('GET', '/api/mt5/live?login=100912');
  check('live?login=100912 balikin data miliknya', r.status === 200 && r.json.master && Number(r.json.master.login) === 100912, JSON.stringify(r.json).slice(0, 80));
  r = await req('GET', '/api/mt5/live?login=999999');
  check('live?login=999999 → standby offline (bukan data orang lain)', r.status === 200 && r.json.online === false && r.json.pairs.length === 0, `online=${r.json && r.json.online}`);
  r = await req('POST', '/api/mt5/sync', {
    master: { login: 100912, balance: 2000, equity: 2100 },
    slave: { login: 100913, balance: 2000, equity: 1900 },
    cycle_event: { gross_profit: 'BUKAN ANGKA' } // garbage → NaN guard
  });
  check('sync cycle_event dengan gross_profit garbage tetap sukses (NaN guard)', r.status === 200, `got ${r.status} ${r.raw.slice(0, 80)}`);

  // ---------- 5. DOUBLE CREDIT DIHAPUS ----------
  console.log('5) Cycle event: profit tidak di-credit ganda ke admin');
  r = await req('POST', '/api/auth/login', { login_id: 'admin', password: 'admin123' });
  const adminBefore = r.json.user.total_profit;
  r = await req('POST', '/api/mt5/sync', {
    master: { login: 100870, balance: 3000, equity: 3100 },
    slave: { login: 100871, balance: 3000, equity: 2900 },
    cycle_event: { gross_profit: 100, master_profit: 60 }
  });
  check('cycle_event sukses', r.status === 200, `got ${r.status}`);
  r = await req('POST', '/api/auth/login', { login_id: 'admin', password: 'admin123' });
  const adminAfter = r.json.user.total_profit;
  // admin punya mt5_master.login 100870 → dia targetUser tunggal: +70 (70% dari 100), tepat sekali
  check(`admin total_profit naik tepat +70 sekali (${adminBefore} → ${adminAfter})`, Math.abs((adminAfter - adminBefore) - 70) < 0.01, `delta=${(adminAfter - adminBefore).toFixed(2)}`);

  // ---------- 6. TOPUP VALIDASI ----------
  console.log('6) Top-up fuel validasi');
  r = await req('POST', '/api/user/topup-fuel', { userid: 'TIDAK ADA', amount: 50 });
  check('topup user tidak dikenal ditolak (404)', r.status === 404, `got ${r.status}`);
  r = await req('POST', '/api/user/topup-fuel', { userid: 'kevin', amount: -5 });
  check('topup nominal negatif ditolak (400)', r.status === 400, `got ${r.status}`);
  r = await req('POST', '/api/user/topup-fuel', { userid: 'kevin', amount: 10 });
  check('topup valid sukses', r.status === 200 && r.json.balance === 35, `got ${r.status} balance=${r.json && r.json.balance}`);

  // ---------- 7. STATIC FILE SERVING ----------
  console.log('7) Static file serving');
  r = await req('GET', '/');
  check('GET / menyajikan index.html', r.status === 200 && r.raw.includes('<!DOCTYPE html>'), `status=${r.status}`);
  r = await req('GET', '/api/tidak-ada');
  check('GET /api/tidak-ada → 404 JSON', r.status === 404, `got ${r.status}`);

  console.log(`\n==============================`);
  console.log(`RESULT: ${passed} passed, ${failed} failed`);
  console.log(`==============================\n`);
  server.close();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => { console.error('TEST RUNNER ERROR:', e); process.exit(1); });
