//+------------------------------------------------------------------+
//|                                           BonusHedge_Master_Pair2.mq5  |
//|                         All-in-One Dual-MT5 Bonus Hedging Master |
//|                                  Copyright 2026, Advanced Bot EA |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Bot EA"
#property link      "https://www.mql5.com"
#property version   "1.34"
#property strict

#include <Trade\Trade.mqh>

//--- User-Facing Input Parameters (Clean, Simple & Essential Only)
input group "=== IDENTITAS PASANGAN TRADING ==="
input int      InpPairID            = 2;             // [KHUSUS PAIR 2] Pair Group ID (Terkunci Otomatis untuk Pasangan 2)
input string   InpClientName        = "Pair #2";      // Identitas Pasangan (Pair #2)

input group "=== AUTO LOT DARI BALANCE ==="
input bool     InpAutoLotFromBalance = true;         // Auto-Scale Lot dari Balance ($2k->0.10, $5k->0.20, $10k->0.40)
input double   InpDepositBalanceOverride = 0.0;      // Input Modal ($) jika ingin override saldo (0 = baca saldo otomatis)

input group "=== GRID STRATEGY PARAMETERS ==="
input double   InpInitialLot        = 1.20;          // Base Lot Manual (Hanya dipakai jika Auto Lot = false)
input int      InpMaxLayers         = 3;             // Maximum Grid Layers (Max 3 Positions for Bonus Safety)
input double   InpGridStepPoints    = 1200.0;        // Grid Step Points (1200.0 = $12.00 on Gold, default 1000-1500)
input double   InpTargetProfitPct   = 1.2;           // Target Net Basket TP (% Total Modal 2 Akun, default 1.2% ideal)
input double   InpBasketTPDollars   = 0.0;           // Target Basket TP ($ Flat Dollar, isi > 0 jika ingin nominal fix, 0 = pakai %)
input double   InpSpreadBufferUSD   = 0.0;           // Spread Buffer USD (0 = Otomatis: $2k->$15, $5k->$25, $10k->$35, dst)
input bool     InpPauseAfterCycle   = false;         // Pause After Cycle (false = auto loop buka lagi terus-menerus)

input group "=== SLAVE HEDGING CONFIG (DARI MASTER) ==="
input double   InpSlaveMultiplier   = 1.15;          // Multiplier Lot Slave (1.15 = 1.00 Master -> 1.15 Slave, Pembakaran Bonus Optimal)

input group "=== INTERVENSI MANUAL ==="
input bool     InpCloseAll          = false;         // Intervensi Manual: Tutup SEMUA Posisi Master + Slave Sekarang (default: false)

input group "=== AUTO BONUS DRAINER (BURNER MODE) ==="
input bool     InpEnableBonusBurner = false;         // Auto-Burner: Kuras habis sisa bonus (false = panen tuntas lalu PAUSE)
input double   InpBurnerMinEquity   = 80.0;          // Min Equity Slave untuk Burner Mode (default: $80)
input double   InpBurnerLotSize     = 0.10;          // Lot Master saat Burner Mode (Slave x1.10 = 0.11L)
input double   InpBurnerTargetTP    = 20.0;          // Target Net TP ($) saat Burner Mode (default: $20.0)
input double   InpBurnerBuffer      = 10.0;          // Spread Buffer ($) saat Burner Mode (default: $10.0)

input group "=== PROTEKSI DARURAT MASTER & ANTI-SALDO MINUS ==="
input bool     InpEnableMasterShield     = true;   // Master Emergency Shield (Anti-StopOut Broker)
input double   InpMasterMinEquityBuffer  = 0.0;    // Batas Minimal Equity Master ($) Sebelum Tutup Darurat (0 = Otomatis 25% Saldo / Min $200)
input double   InpMasterMinMarginLevel   = 40.0;   // Batas Minimal Margin Level Master (%) (Default: 40.0%, StopOut Broker: 20%)

input group "=== PROTEKSI BERITA BESAR (PRE-NEWS AUTO FLAT) ==="
input bool     InpNewsPreCloseOrders     = false;  // Tutup Bersih Posisi Sebelum Berita High-Impact (Default: false, anti-cutloss spread)
input int      InpNewsPreCloseMinutes    = 30;     // Jeda Menit Sebelum Berita untuk Auto-Flat (Default: 30 Min)
input bool     InpNewsPreCloseOnlyIfProfit = true; // Opsi B: Hanya Tutup Jika Posisi Sudah Profit/BEP (Anti-Cutloss)

//--- Internal Engine Parameters (Auto-Configured & Locked for Optimal Safety)
const string   InpSymbol            = "XAUUSD";      // Trading Symbol
const bool     InpAutoScaleLot      = false;         // Fixed Lot
const bool     InpIncludeManualTrades = true;        // Include Manual Positions in Basket TP & Close
const double   InpMinMarginLevel    = 50.0;          // Min Margin Level % (Dilonggarkan agar tidak mogok di 100%)
const double   InpMinFreeMargin     = 50.0;          // Min Free Margin $ (Dilonggarkan agar tidak mogok di $150)
const bool     InpHarvestOnSlaveMC  = true;          // Auto Close Master if Slave hits Margin Call/StopOut
const int      InpUnhedgedWatchdogSec = 15;          // Unhedged Watchdog Timeout (Seconds)
const double   InpMaxSpreadPoints   = 60.0;          // Max Spread Points Allowed for Open & TP
const bool     InpEnableSpikeVelocity = false;       // Spike Velocity Guard
const double   InpSpikeVelocityUSD  = 15.00;         // Spike Candle Threshold
const int      InpSpikeCooldownMin  = 2;             // Spike Cooldown Duration
const bool     InpAutoNewsFilter    = true;          // Auto Economic News Filter (MQL5 Calendar)
const int      InpNewsPauseBeforeMin = 15;           // News Pause Before High-Impact USD
const int      InpNewsPauseAfterMin  = 15;           // News Pause After High-Impact USD
const string   InpReferralCode      = "";            // Kode Referral Partner / IB
const bool     InpEnableTelegram    = false;         // Enable Telegram Live Alerts
const string   InpTelegramBotToken  = "8841891391:AAFZX-wQSRd2oXOq5Qw52mWAkq_MPxO72_0";
const string   InpTelegramChatID    = "164419860";
const int      InpTelegramIntervalMin = 5;
input group "=== CLOUD WEB DASHBOARD MONITORING ==="
input bool     InpEnableWebDashboard= true;          // Enable Cloud Web Dashboard Telemetry
input string   InpWebDashboardUrl   = "https://thank-theoretical-cutting-inherited.trycloudflare.com/api/telemetry"; // Dashboard Telemetry URL
input int      InpWebIntervalSec    = 2;             // Telemetry Interval (Seconds)
const int      InpTimerMS           = 50;            // Sync Interval in ms

//--- Resolved Runtime Variables (Generated Automatically from InpPairID)
ulong          m_magic              = 888111;
string         m_comment_prefix     = "GRID_S";
string         m_master_file        = "bonus_hedge_master.dat";
string         m_slave_file         = "bonus_hedge_slave.dat";
string         m_cmd_to_slave       = "bonus_cmd_to_slave.dat";
string         m_cmd_to_master      = "bonus_cmd_to_master.dat";

//--- Global Objects
CTrade         m_trade;
datetime       m_last_order_time    = 0;
datetime       m_last_telegram_time = 0;
datetime       m_last_web_time      = 0;
datetime       m_closing_lock_until = 0;
string         m_symbol             = "";
double         m_point              = 0.01;
int            m_digits             = 2;
bool           m_closing_active     = false;
bool           m_cycle_paused       = false;

//--- Smart Auto-Migration Effective Variables (v1.27)
double         m_spread_buffer          = 35.0;
double         m_min_margin_level       = 100.0;
int            m_unhedged_watchdog      = 15;


// Slave Telemetry Snapshot
struct SlavePosInfo
{
   ulong  ticket;
   int    type;
   double volume;
   double price_open;
   double profit;
   string comment;
};

SlavePosInfo   m_slave_positions[];
long           m_slave_time         = 0;
long           m_slave_login        = 0;
double         m_slave_equity       = 0.0;
double         m_slave_balance      = 0.0;
double         m_slave_credit       = 0.0;
double         m_slave_free_margin  = 0.0;
double         m_slave_margin_level = 0.0;
double         m_slave_profit       = 0.0;
int            m_slave_pos_count    = 0;
bool           m_slave_online       = false;
bool           m_slave_trade_blocked = false;   // v1.25: Slave melapor tidak bisa eksekusi (algo OFF / CB)
long           m_slave_spread       = 0;       // v1.26: Live spread broker Slave (pts)
long           m_slave_last_counter = -1;
datetime       m_slave_last_seen    = 0;

//--- Universal Anti-Flapping Circuit Breaker Shield
datetime       m_cycle_start_time       = 0;       // v1.27: Waktu awal siklus (hanya dicatat saat Layer 1 buka)
datetime       m_last_order_open_time   = 0;
datetime       m_last_order_close_time  = 0;
int            m_rapid_close_counter    = 0;
datetime       m_circuit_breaker_until  = 0;
string         m_circuit_breaker_reason = "";
bool           m_naked_alert_sent       = false;
bool           m_blocked_alert_sent     = false;   // v1.25: alert Slave trade-blocked (sekali per episode)

//--- Big News & Volatility Guard State
datetime       m_spike_cooldown_until   = 0;
string         m_spike_reason           = "";
datetime       m_news_pause_until       = 0;
string         m_news_title             = "";
bool           m_spread_freeze_logged   = false;
bool           m_burner_alert_sent      = false;
bool           m_harvest_in_progress    = false;   // True saat panen berjenjang berlangsung (kunci buka layer baru)

bool   IsBurnerModeActive();
void   ReadSlaveState();
void   CheckIncomingCommands();
bool   CheckSlaveLiquidationHarvest();
bool   CheckMasterEmergencyPreservation();
bool   CheckPreNewsAutoFlat();
void   CheckUnhedgedOrphanWatchdog();
void   ManageGrid();
void   CloseAllMasterPositions();
bool   CloseMasterPositionByTicket(ulong target_ticket);
void   ExecuteManualCloseAll(string source_reason);
void   CreateResumeButton();
void   CreateManualCloseButton();
void   DeleteManualCloseButton();
void   BroadcastMasterState();
void   BroadcastSlaveConfig();
void   SendCommandToSlave(string cmd);
void   UpdateDashboard();
string UrlEncode(string text);
void   SendTelegramMessage(string raw_message);
void   SendWebTelemetry();
void   CheckSlaveTimeout();
void   CheckNakedExposureAlert();
bool   IsSpreadAcceptable();
bool   IsMasterPosition(ulong ticket);

bool IsMasterPosition(ulong ticket)
{
   if(ticket <= 0) return false;
   string pos_sym = PositionGetString(POSITION_SYMBOL);
   if(StringCompare(pos_sym, m_symbol, false) != 0 && StringCompare(pos_sym, _Symbol, false) != 0)
      return false;
   long magic = PositionGetInteger(POSITION_MAGIC);
   if(magic == (long)m_magic) return true;
   // STRICT MULTI-PAIR ISOLATION (v1.27):
   // Toleransi magic lama hanya berlaku untuk Pair 1. Pair 2 (888102) DILARANG keras menyentuh magic 888101!
   if(InpPairID <= 1 && (magic == 888111 || magic == 888101)) return true;
   if(InpIncludeManualTrades && magic == 0) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Get Effective Capital Balance                            |
//+------------------------------------------------------------------+
double GetReferenceBalance()
{
   if(InpDepositBalanceOverride > 0.0)
      return InpDepositBalanceOverride;

   double master_bal = AccountInfoDouble(ACCOUNT_BALANCE);

   // DUAL-ACCOUNT CROSS CHECK:
   // Membaca kapasitas kedua akun (Master & Slave).
   // Kapasitas Slave = Saldo Riil Slave + Kredit Bonus.
   // Bot mengambil nilai yang paling konservatif antara Master dan Slave,
   // agar Slave tidak mengalami overleverage jika saldonya lebih kecil dari Master!
   if(m_slave_online && (m_slave_balance > 0.0 || m_slave_equity > 0.0))
   {
      double slave_cap = m_slave_balance + m_slave_credit;
      if(slave_cap <= 0.0 && m_slave_equity > 0.0) slave_cap = m_slave_equity;

      if(slave_cap > 0.0)
      {
         return MathMin(master_bal, slave_cap);
      }
   }

   return (master_bal > 0.0) ? master_bal : 5000.0;
}

//+------------------------------------------------------------------+
//| Helper: Get Initial Locked Capital (Anti-Compounding / Fixed Base)|
//+------------------------------------------------------------------+
double GetInitialTotalCapital()
{
   if(InpDepositBalanceOverride > 0.0)
      return InpDepositBalanceOverride;

   string gv_key = "BH_INIT_CAP_" + IntegerToString(m_magic);
   bool has_active_trades = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && IsMasterPosition(t)) { has_active_trades = true; break; }
   }

   // Hanya gunakan cache jika sedang ada trade aktif berjalan (agar lot tidak berubah di tengah siklus):
   if(has_active_trades && GlobalVariableCheck(gv_key))
   {
      double saved_cap = GlobalVariableGet(gv_key);
      if(saved_cap > 0.0) return saved_cap;
   }

   // Hitung dari Total Modal Riil Kedua Akun (Mendukung Akun Bonus dengan Credit):
   double cur_master = AccountInfoDouble(ACCOUNT_BALANCE);
   double eff_slave  = (m_slave_equity > 0.0) ? m_slave_equity : ((m_slave_balance > 0.0) ? m_slave_balance : 0.0);
   double cur_slave  = m_slave_online ? eff_slave : 0.0;
   double total_cap  = cur_master + cur_slave;
   if(total_cap <= 0.0 || cur_slave <= 0.0)
   {
      total_cap = (cur_master > 0.0) ? (cur_master / 0.45) : 10000.0;
   }

   // Universal Tier Modal Awal (Anti-Compounding):
   // Rasio Dasar: 0.05 Lot Master per $1,000 Modal Gabungan
   // Tier $2,000  -> 0.10 Lot Master (Master ~$900 + Slave ~$1,100)
   // Tier $4,000  -> 0.20 Lot Master (Master ~$1,800 + Slave ~$2,200)
   // Tier $5,000  -> 0.25 Lot Master (Master ~$2,250 + Slave ~$2,750)
   // Tier $7,000  -> 0.35 Lot Master (Master ~$3,150 + Slave ~$3,850)
   // Tier $10,000 -> 0.50 Lot Master (Master ~$4,500 + Slave ~$5,500)
   double locked_cap = 2000.0;
   if(total_cap < 3000.0)
      locked_cap = 2000.0;
   else if(total_cap < 4500.0)
      locked_cap = 4000.0;
   else if(total_cap < 6000.0)
      locked_cap = 5000.0;
   else if(total_cap < 8500.0)
      locked_cap = 7000.0;
   else if(total_cap < 12500.0)
      locked_cap = 10000.0;
   else
      locked_cap = MathRound(total_cap / 5000.0) * 5000.0;

   if(locked_cap <= 0) locked_cap = 10000.0;

   // HANYA kunci permanen jika Slave sudah online dan melaporkan equity/balance valid:
   if(m_slave_online && (m_slave_equity > 0.0 || m_slave_balance > 0.0))
   {
      GlobalVariableSet(gv_key, locked_cap);
   }
   return locked_cap;
}

//+------------------------------------------------------------------+
//| Helper: Check if Auto Bonus Drainer (Burner Mode) is Active     |
//+------------------------------------------------------------------+
bool IsBurnerModeActive()
{
   if(!InpEnableBonusBurner) return false;
   if(!m_slave_online) return false;
   
   // Syarat Burner Mode:
   // 1. Slave memiliki credit bonus aktif (>= $40.0)
   // 2. Saldo kas riil Slave sudah habis / minus (Balance <= 50.0)
   // 3. TAPI Equity Slave masih bernilai cukup (>= InpBurnerMinEquity)
   if(m_slave_credit >= 40.0 && m_slave_balance <= 50.0 && m_slave_equity >= InpBurnerMinEquity)
   {
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Fixed Base Lot Sizing from Initial Capital (No Compound) |
//+------------------------------------------------------------------+
double GetEffectiveLot(double ref_bal)
{
   // CEK AUTO BONUS DRAINER (BURNER MODE):
   if(IsBurnerModeActive())
   {
      double burner_lot = (InpBurnerLotSize > 0.0) ? InpBurnerLotSize : 0.10;
      double min_l = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double max_l = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step_l = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(min_l <= 0) min_l = 0.01;
      if(max_l <= 0) max_l = 100.0;
      if(step_l <= 0) step_l = 0.01;
      burner_lot = MathMax(min_l, MathMin(max_l, burner_lot));
      burner_lot = MathFloor(burner_lot / step_l) * step_l;
      return burner_lot;
   }

   if(!InpAutoLotFromBalance)
      return (InpInitialLot > 0.0) ? InpInitialLot : 0.20;

   // FIXED TIER LOT SCALING (Anti-Compounding - Patokan Saldo Awal Terkunci):
   // Tier $2,000  Modal -> 0.10 lot Master (0.11 lot Slave)
   // Tier $4,000  Modal -> 0.20 lot Master (0.22 lot Slave)
   // Tier $5,000  Modal -> 0.25 lot Master (0.28 lot Slave)
   // Tier $7,000  Modal -> 0.35 lot Master (0.38 lot Slave)
   // Tier $10,000 Modal -> 0.50 lot Master (0.55 lot Slave)
   // Lot TIDAK AKAN bertambah saat saldo naik karena profit!
   double init_cap = GetInitialTotalCapital();
   double lot = 0.50;

   if(init_cap <= 2500.0)
      lot = 0.10;
   else if(init_cap <= 4500.0)
      lot = 0.20;
   else if(init_cap <= 6000.0)
      lot = 0.25;
   else if(init_cap <= 8500.0)
      lot = 0.35;
   else if(init_cap <= 12500.0)
      lot = 0.50;
   else
      lot = (init_cap / 1000.0) * 0.05;

   double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(min_lot <= 0) min_lot = 0.01;
   if(max_lot <= 0) max_lot = 100.0;
   if(step <= 0) step = 0.01;

   lot = MathMax(min_lot, MathMin(max_lot, lot));
   lot = MathFloor(lot / step) * step;
   return lot;
}

//+------------------------------------------------------------------+
//| Helper: Get Base Take Profit Target ($) (Anti-Compounding)       |
//+------------------------------------------------------------------+
double GetBaseTPAmount(double ref_bal)
{
   if(IsBurnerModeActive())
   {
      return (InpBurnerTargetTP > 0.0) ? InpBurnerTargetTP : 20.0;
   }

   if(InpBasketTPDollars > 0.0)
      return InpBasketTPDollars;
   if(InpTargetProfitPct > 0.0)
   {
      // Dihitung dari Modal Awal Terkunci (Anti-Compounding):
      double init_cap = GetInitialTotalCapital();
      return (init_cap * InpTargetProfitPct) / 100.0;
   }
   return 35.0; // Fallback default
}

//+------------------------------------------------------------------+
//| Helper: Dynamic Balance-Scaled Spread & Slippage Buffer ($)      |
//+------------------------------------------------------------------+
double GetEffectiveSpreadBuffer()
{
   if(IsBurnerModeActive())
   {
      return (InpBurnerBuffer > 0.0) ? InpBurnerBuffer : 10.0;
   }

   // Jika user manual menginput nilai buffer > 0, gunakan input user:
   if(InpSpreadBufferUSD > 0.0)
      return InpSpreadBufferUSD;

   // AUTO-BUFFER BERDASARKAN MODAL / BALANCE (0 = Full Otomatis):
   // Modal <= $2,500 ($2k)   -> Buffer $15.0
   // Modal <= $4,500 ($4k)   -> Buffer $20.0
   // Modal <= $6,000 ($5k)   -> Buffer $25.0
   // Modal <= $8,500 ($7k)   -> Buffer $30.0
   // Modal <= $12,500 ($10k) -> Buffer $35.0
   // Modal > $12,500         -> $35.0 + $15 per kelipatan $5,000 (proporsional volume)
   double init_cap = GetInitialTotalCapital();
   double auto_buf = 35.0;

   if(init_cap <= 2500.0)
      auto_buf = 15.0;
   else if(init_cap <= 4500.0)
      auto_buf = 20.0;
   else if(init_cap <= 6000.0)
      auto_buf = 25.0;
   else if(init_cap <= 8500.0)
      auto_buf = 30.0;
   else if(init_cap <= 12500.0)
      auto_buf = 35.0;
   else
   {
      double extra_tiers = MathFloor((init_cap - 10000.0) / 5000.0);
      auto_buf = 35.0 + (extra_tiers * 15.0);
   }

   return auto_buf;
}

//+------------------------------------------------------------------+
//| Helper: Estimasi Kebutuhan Margin Riil Slave untuk 1 Layer Baru  |
//| Melindungi Slave agar Master TIDAK BUKA LAYER jika Slave sesak!  |
//+------------------------------------------------------------------+
double EstimateSlaveRequiredMargin(double master_lot)
{
   double slave_lot = master_lot * InpSlaveMultiplier;
   double step_l = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(step_l <= 0) step_l = 0.01;
   slave_lot = MathFloor(slave_lot / step_l) * step_l;
   if(slave_lot < 0.01) slave_lot = 0.01;

   double margin_req = 0.0;
   // Cek kalkulasi margin resmi dari instrumen broker:
   if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, slave_lot, SymbolInfoDouble(m_symbol, SYMBOL_ASK), margin_req) || margin_req <= 0.0)
   {
      // Fallback konservatif: Asumsi leverage 1:500 pada XAUUSD (1 lot = ~$400 - $850 margin tergantung harga)
      double cur_ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(cur_ask <= 0.0) cur_ask = 2500.0;
      // Rumus standar forex/CFD: (Lot * Kontrak (100) * Harga) / Leverage (500)
      margin_req = (slave_lot * 100.0 * cur_ask) / 500.0;
   }
   return margin_req;
}

void InitPairConfiguration()
{
   int pid = (InpPairID <= 1) ? 1 : InpPairID;
   string suffix = (pid == 1) ? "" : ("_" + IntegerToString(pid));

   m_magic          = 888100 + (ulong)pid; // 888101, 888102, 888103, dst.
   m_comment_prefix = (pid == 1) ? "GRID_S" : ("GRID" + IntegerToString(pid) + "_S");
   m_master_file    = "bonus_hedge_master" + suffix + ".dat";
   m_slave_file     = "bonus_hedge_slave" + suffix + ".dat";
   m_cmd_to_slave   = "bonus_cmd_to_slave" + suffix + ".dat";
   m_cmd_to_master  = "bonus_cmd_to_master" + suffix + ".dat";
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitPairConfiguration();

   m_symbol = (InpSymbol == "" || InpSymbol == "0") ? _Symbol : InpSymbol;
   if(!SymbolSelect(m_symbol, true)) m_symbol = _Symbol;

   m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
   m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   if(m_point <= 0) m_point = 0.01;

   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(50);
   m_trade.SetTypeFillingBySymbol(m_symbol);

   EventSetMillisecondTimer(InpTimerMS);
   m_last_order_open_time  = TimeCurrent();
   m_last_order_close_time = 0;
   m_rapid_close_counter   = 0;
   m_circuit_breaker_until = 0;

   // SPREAD BUFFER CONFIGURATION (DYNAMIC LOT-SCALED):
   m_spread_buffer = GetEffectiveSpreadBuffer();

   m_min_margin_level  = (InpMinMarginLevel > 100.0) ? 100.0 : InpMinMarginLevel;
   m_unhedged_watchdog = (InpUnhedgedWatchdogSec > 0 && InpUnhedgedWatchdogSec < 15) ? 15 : InpUnhedgedWatchdogSec;

   double ref_bal = GetReferenceBalance();
   double eff_lot = GetEffectiveLot(ref_bal);
   double base_tp = GetBaseTPAmount(ref_bal);

   BroadcastSlaveConfig();

   Print("🟢 [BonusHedge_Master v1.34] Initialized on ", m_symbol, " (Pair ID: ", InpPairID, ", Magic: ", m_magic,
         ", Ref Balance: $", DoubleToString(ref_bal, 2),
         ", Lot: ", DoubleToString(eff_lot, 2), "L", (InpAutoLotFromBalance ? " [AUTO]" : " [MANUAL]"),
         ", Slave Mult: x", DoubleToString(InpSlaveMultiplier, 2),
         ", Target TP: $", DoubleToString(base_tp, 2), " (", (InpBasketTPDollars > 0.0 ? "Flat" : (DoubleToString(InpTargetProfitPct, 1) + "%")),
         " + Buffer $", DoubleToString(m_spread_buffer, 2), ")",
         ", GridStep: ", DoubleToString(InpGridStepPoints, 0), "pts, AutoLoop: ", (InpPauseAfterCycle ? "OFF" : "ON"), ")");

   // Set Chart Foreground Text to Bright Yellow for maximum crisp readability
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrYellow);

   // Immediate startup test ping to Telegram
   if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
   {
      SendTelegramMessage("🟢 <b>[DUAL-MT5 BONUS HEDGING v1.34 AKTIF]</b>\n" +
                          "👑 Akun Master: <b>" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "</b>\n" +
                          "📌 Pair ID: <b>#" + IntegerToString(InpPairID) + "</b> (Magic: " + IntegerToString(m_magic) + ")\n" +
                          "📊 Symbol: <b>" + m_symbol + "</b> | Base Lot: <b>" + DoubleToString(eff_lot, 2) + "L</b> (" + (InpAutoLotFromBalance ? "Auto Balance" : "Manual") + ")\n" +
                          "⏱️ Laporan live akan dikirim setiap " + IntegerToString(InpTelegramIntervalMin) + " menit.");
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   FileDelete(m_master_file, FILE_COMMON);
   ObjectDelete(0, "BTN_RESUME_CYCLE");
   ObjectDelete(0, "BTN_MANUAL_CLOSE");
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   Comment("");
}

//+------------------------------------------------------------------+
//| Chart Event function: Handle Click on buttons                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "BTN_RESUME_CYCLE")
      {
         if(InpCloseAll)
         {
            Print("⚠️ [RESUME DITAHAN] Parameter InpCloseAll masih bernilai TRUE! Ubah input InpCloseAll menjadi false di settingan EA (tekan F7) sebelum melanjutkan.");
            return;
         }
         m_cycle_paused = false;
         ObjectDelete(0, "BTN_RESUME_CYCLE");
         ChartRedraw(0);
         Print("▶️ [USER ACTION] Bot di-RESUME oleh user! Siap membuka siklus order baru.");
      }
      else if(sparam == "BTN_MANUAL_CLOSE")
      {
         ExecuteManualCloseAll("Tombol Chart [CLOSE ALL] Diklik");
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Execute Manual Close All on Both Master & Slave          |
//+------------------------------------------------------------------+
void ExecuteManualCloseAll(string source_reason)
{
   Print("🚨 [MANUAL CLOSE ALL TRIGGERED] Alasan: ", source_reason, "! Menutup semua posisi di 2 Akun (Master + Slave) secara simultan...");
   m_closing_active = true;
   m_closing_lock_until = TimeCurrent() + 6;

   // 1. Kirim sinyal tutup darurat ke Slave LEBIH DULU
   SendCommandToSlave("CLOSE_ALL");
   BroadcastMasterState(); // Flush file state seketika

   // 2. Tutup semua posisi Master
   CloseAllMasterPositions();
   m_closing_active = false;
   m_last_order_time = TimeCurrent();

   // 3. Pause bot agar tidak langsung membuka posisi baru
   m_cycle_paused = true;
   DeleteManualCloseButton();
   CreateResumeButton();
   Print("✅ [MANUAL CLOSE ALL DONE] Seluruh posisi Master dan Slave berhasil ditutup. Bot di-PAUSE secara aman.");
}

//+------------------------------------------------------------------+
//| Helper: Create On-Chart Interactive Resume Button                |
//+------------------------------------------------------------------+
void CreateResumeButton()
{
   string btn_name = "BTN_RESUME_CYCLE";
   if(ObjectFind(0, btn_name) < 0)
   {
      ObjectCreate(0, btn_name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, btn_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, btn_name, OBJPROP_XDISTANCE, 30);
      ObjectSetInteger(0, btn_name, OBJPROP_YDISTANCE, 245);
      ObjectSetInteger(0, btn_name, OBJPROP_XSIZE, 240);
      ObjectSetInteger(0, btn_name, OBJPROP_YSIZE, 36);
      ObjectSetString(0, btn_name, OBJPROP_TEXT, "▶ KLIK UNTUK RESUME TRADING");
      ObjectSetInteger(0, btn_name, OBJPROP_BGCOLOR, C'34,197,94'); // Bright Green
      ObjectSetInteger(0, btn_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btn_name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, btn_name, OBJPROP_SELECTABLE, false);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Helper: Create On-Chart Interactive Manual Close All Button      |
//+------------------------------------------------------------------+
void CreateManualCloseButton()
{
   string btn_name = "BTN_MANUAL_CLOSE";
   if(ObjectFind(0, btn_name) < 0)
   {
      ObjectCreate(0, btn_name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, btn_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, btn_name, OBJPROP_XDISTANCE, 30);
      ObjectSetInteger(0, btn_name, OBJPROP_YDISTANCE, 245);
      ObjectSetInteger(0, btn_name, OBJPROP_XSIZE, 240);
      ObjectSetInteger(0, btn_name, OBJPROP_YSIZE, 36);
      ObjectSetString(0, btn_name, OBJPROP_TEXT, "🛑 CLOSE ALL (2 AKUN)");
      ObjectSetInteger(0, btn_name, OBJPROP_BGCOLOR, C'220,38,38'); // Bright Red
      ObjectSetInteger(0, btn_name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, btn_name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, btn_name, OBJPROP_SELECTABLE, false);
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Helper: Delete Manual Close Button                               |
//+------------------------------------------------------------------+
void DeleteManualCloseButton()
{
   if(ObjectFind(0, "BTN_MANUAL_CLOSE") >= 0)
   {
      ObjectDelete(0, "BTN_MANUAL_CLOSE");
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Read Slave Telemetry (Two-Way Communication)
   ReadSlaveState();

   // 1b. NAKED EXPOSURE ALERT: Master punya posisi tapi Slave proof offline
   //     -> posisi terkunci tanpa lindung nilai bonus. Beri peringatan (sekali).
   CheckNakedExposureAlert();

   // 2. Check for incoming commands (e.g. CLOSE_ALL from Slave)
   CheckIncomingCommands();

   // 3. Always Broadcast Master State so Slave is NEVER left with stale data
   BroadcastMasterState();

   // 4. Update On-Screen Dashboard & Cloud Web Telemetry
   UpdateDashboard();
   SendWebTelemetry();

   // 5. CHECK IF ALGO TRADING IS ALLOWED BY USER IN MT5
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Comment("\n  ⚠️ [BonusHedge_Master] ALGO TRADING IS DISABLED IN MT5!\n" +
              "  Klik tombol 'Algo Trading' di toolbar atas MT5 agar robot bisa bekerja.");
      return;
   }

   // 6. Check if Slave was liquidated / hit MC -> Harvest Master Profit
   if(InpHarvestOnSlaveMC && CheckSlaveLiquidationHarvest())
      return;

   // 6B. Check Master Emergency Equity Shield -> Protect Master from ever hitting MC / Negative Balance!
   if(CheckMasterEmergencyPreservation())
      return;

   // 6C. Check Pre-News Auto Flat -> Closes clean 30 minutes before high-impact news!
   if(CheckPreNewsAutoFlat())
      return;

   // 7. Manage Grid Logic (with pre-trade margin verification)
   if(!m_closing_active)
      ManageGrid();

   // 8. UNHEDGED ORPHAN WATCHDOG:
   // Jika Master memiliki posisi terbuka tetapi Slave gagal meng-hedge selama > 15 detik:
   // Master WAJIB menutup posisi unhedged tersebut demi keselamatan modal!
   if(!m_closing_active && !m_cycle_paused)
      CheckUnhedgedOrphanWatchdog();
}

//+------------------------------------------------------------------+
//| Read Slave state from FILE_COMMON (Two-Way Telemetry)            |
//| v2 protocol: magic|version|counter|login|equity|balance|free|ml| |
//|              profit|count|positions...                           |
//| Partial/invalid reads KEEP the last good snapshot - destructive  |
//| actions require SUSTAINED state, never a single racy read.       |
//+------------------------------------------------------------------+
void ReadSlaveState()
{
   if(!FileIsExist(m_slave_file, FILE_COMMON))
   {
      CheckSlaveTimeout();
      return;
   }

   int file_handle = FileOpen(m_slave_file, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle == INVALID_HANDLE)
   {
      CheckSlaveTimeout();
      return;
   }

   // ANTI-STALE FILE SHIELD: File harus aktif dimodifikasi dalam 15 detik terakhir!
   // Mencegah Master membaca snapshot hantu/basi dari MT5 sebelum reset atau restart.
   datetime file_mod = (datetime)FileGetInteger(file_handle, FILE_MODIFY_DATE);
   if(file_mod > 0 && (TimeLocal() - file_mod > 15))
   {
      FileClose(file_handle);
      CheckSlaveTimeout();
      return;
   }

   ResetLastError();
   long new_magic   = FileReadLong(file_handle);
   bool ok          = (GetLastError() == 0);
   long new_version = 0;
   long new_counter = 0;
   if(ok) { ResetLastError(); new_version = FileReadLong(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_counter = FileReadLong(file_handle); ok = (GetLastError() == 0); }

   long   new_login       = 0;
   double new_equity      = 0.0;
   double new_balance     = 0.0;
   double new_free_margin = 0.0;
   double new_margin_lvl  = 0.0;
   double new_profit      = 0.0;
   int    new_pos_count   = 0;

   if(ok) { ResetLastError(); new_login       = FileReadLong(file_handle);   ok = (GetLastError() == 0); }
   double new_credit      = 0.0;
   int    new_trade_blocked = 0;
   if(ok) { ResetLastError(); new_equity      = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_balance     = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(new_version >= 3)
   {
      if(ok) { ResetLastError(); new_credit   = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   }
   if(new_version >= 4)
   {
      // v4: Slave melaporkan kemampuan eksekusi (1 = algo OFF / circuit breaker)
      if(ok) { ResetLastError(); new_trade_blocked = FileReadInteger(file_handle); ok = (GetLastError() == 0); }
   }
   if(ok) { ResetLastError(); new_free_margin = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_margin_lvl  = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_profit      = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   long new_slave_spread = 0;
   if(new_version >= 5)
   {
      if(ok) { ResetLastError(); new_slave_spread = FileReadLong(file_handle); ok = (GetLastError() == 0); }
   }
   if(ok) { ResetLastError(); new_pos_count   = FileReadInteger(file_handle); ok = (GetLastError() == 0); }

   // Baca ke array paralel primitif (struct ber-string tidak boleh lokal di MQL5)
   ulong  t_tickets[];
   int    t_types[];
   double t_volumes[], t_prices[], t_profits[];
   string t_comments[];
   ArrayResize(t_tickets, 0);
   ArrayResize(t_types, 0);
   ArrayResize(t_volumes, 0);
   ArrayResize(t_prices, 0);
   ArrayResize(t_profits, 0);
   ArrayResize(t_comments, 0);
   if(ok && new_pos_count >= 0 && new_pos_count <= 100)
   {
      ArrayResize(t_tickets,  new_pos_count);
      ArrayResize(t_types,    new_pos_count);
      ArrayResize(t_volumes,  new_pos_count);
      ArrayResize(t_prices,   new_pos_count);
      ArrayResize(t_profits,  new_pos_count);
      ArrayResize(t_comments, new_pos_count);
      for(int i = 0; i < new_pos_count; i++)
      {
         ResetLastError();
         t_tickets[i] = (ulong)FileReadLong(file_handle);
         ok = (GetLastError() == 0); if(!ok) break;
         ResetLastError();
         t_types[i] = FileReadInteger(file_handle);
         ok = (GetLastError() == 0); if(!ok) break;
         ResetLastError();
         t_volumes[i] = FileReadDouble(file_handle);
         ok = (GetLastError() == 0); if(!ok) break;
         ResetLastError();
         t_prices[i] = FileReadDouble(file_handle);
         ok = (GetLastError() == 0); if(!ok) break;
         ResetLastError();
         t_profits[i] = FileReadDouble(file_handle);
         ok = (GetLastError() == 0); if(!ok) break;
         ResetLastError();
         int clen = FileReadInteger(file_handle);
         ok = (GetLastError() == 0); if(!ok) break;
         if(clen > 0 && clen < 256)
            t_comments[i] = FileReadString(file_handle, clen);
         else
            t_comments[i] = "";
      }
      if(!ok)
      {
         ArrayResize(t_tickets,  0);
         ArrayResize(t_types,    0);
         ArrayResize(t_volumes,  0);
         ArrayResize(t_prices,   0);
         ArrayResize(t_profits,  0);
         ArrayResize(t_comments, 0);
      }
   }
   else if(ok)
   {
      ok = false; // pos_count di luar rentang = payload tidak valid
   }

   FileClose(file_handle);

   // Payload tidak valid / versi beda: jaga snapshot terakhir yang bagus
   if(!ok || new_magic != 0x42484246 || (new_version != 2 && new_version != 3 && new_version != 4 && new_version != 5))
   {
      CheckSlaveTimeout();
      return;
   }

   // Heartbeat: counter harus maju secara live; nilai sama = writer berhenti menulis / file mati
   if(m_slave_last_counter == -1)
   {
      // Cold-start baseline: catat counter awal, verifikasi tick berikutnya bahwa angka benar-benar bertambah live!
      m_slave_last_counter = new_counter;
      return;
   }

   if(new_counter <= m_slave_last_counter)
   {
      CheckSlaveTimeout();
      return;
   }

   m_slave_last_counter = new_counter;
   m_slave_time         = new_counter;
   m_slave_login        = new_login;
   m_slave_equity       = new_equity;
   m_slave_balance      = new_balance;
   m_slave_credit       = (new_version >= 3) ? new_credit : ((new_equity > new_balance) ? (new_equity - new_balance) : 0.0);
   m_slave_free_margin  = new_free_margin;
   m_slave_margin_level = new_margin_lvl;
   m_slave_profit       = new_profit;
   m_slave_pos_count    = new_pos_count;
   m_slave_trade_blocked = (new_version >= 4 && new_trade_blocked != 0);
   m_slave_spread        = (new_version >= 5) ? new_slave_spread : 0;
   ArrayResize(m_slave_positions, new_pos_count);
   for(int i = 0; i < new_pos_count; i++)
   {
      m_slave_positions[i].ticket     = t_tickets[i];
      m_slave_positions[i].type       = t_types[i];
      m_slave_positions[i].volume     = t_volumes[i];
      m_slave_positions[i].price_open = t_prices[i];
      m_slave_positions[i].profit     = t_profits[i];
      m_slave_positions[i].comment    = t_comments[i];
   }
   m_slave_last_seen    = TimeLocal();
   m_slave_online       = true;
}

//+------------------------------------------------------------------+
//| Rate-independent offline detection (120 detik grace period)     |
//+------------------------------------------------------------------+
void CheckSlaveTimeout()
{
   if(m_slave_last_seen > 0 && (TimeLocal() - m_slave_last_seen <= 120))
      return; // masih dalam grace: pertahankan snapshot & flag online
   m_slave_online = false;
}

//+------------------------------------------------------------------+
//| NAKED EXPOSURE ALERT                                             |
//| Master punya posisi terbuka tapi Slave TERBUKTI offline          |
//| (grace 120s habis) -> grid terkunci tanpa lindung nilai bonus.   |
//| Tidak auto-close (harga tak terkunci = slippage buta), tapi user |
//| wajib tahu dalam hitungan detik via Telegram (sekali per episode)|
//+------------------------------------------------------------------+
void CheckNakedExposureAlert()
{
   static int s_naked_streak = 0;
   int master_count = 0;
   if(m_slave_online)
   {
      m_naked_alert_sent = false;
      s_naked_streak = 0;
      return;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsMasterPosition(ticket))
         master_count++;
   }
   if(master_count == 0)
   {
      m_naked_alert_sent = false;
      s_naked_streak = 0;
      return;
   }
   s_naked_streak++;
   if(!m_naked_alert_sent && s_naked_streak >= 20) // ~1 detik stabil
   {
      m_naked_alert_sent = true;
      Print("🚨 [NAKED EXPOSURE] Master punya ", master_count, " posisi tapi Slave OFFLINE! Grid dikunci — tidak ada order baru. Cek terminal Slave!");
      if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
      {
         SendTelegramMessage("🚨 <b>[POSISI TANPA HEDGE / NAKED]</b>\n────────────────────────────\n⚠️ Master punya <b>" + IntegerToString(master_count) + " posisi terbuka</b> tapi Slave <b>OFFLINE</b>.\n🛡️ Grid DIKUNCI (tidak ada order baru) sampai Slave kembali.\n👉 Segera cek terminal/EA Slave. Jika Slave tidak kembali, tutup posisi Master secara manual dari HP.\n⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
      }
   }
}

//+------------------------------------------------------------------+
//| Check if Slave got closed / stopped out / liquidated             |
//| IRONCLAD SAFETY: Trigger ONLY when Slave is genuinely MC/Liquidated|
//| Multi-Cycle Debounce (3 cycles = 150ms) + Supports Equity <= 0   |
//+------------------------------------------------------------------+
bool CheckSlaveLiquidationHarvest()
{
   if(!m_slave_online || m_closing_active) return false;

   static int s_slave_mc_counter = 0;

   // Panen likuidasi hanya relevan jika Master memang sedang memegang posisi terbuka!
   int master_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && IsMasterPosition(ticket))
         master_count++;
   }
   if(master_count == 0)
   {
      s_slave_mc_counter = 0;
      return false;
   }

   // GENUINE LIQUIDATION HARVEST:
   // 1. ORDER OPENING GRACE PERIOD:
   // DILARANG KERAS memicu panen likuidasi jika posisi Master baru dibuka dalam 15 detik terakhir!
   // Berikan jeda waktu 15 detik bagi Slave untuk menerima sinyal dan mengeksekusi order hedging ke broker.
   if(m_last_order_open_time > 0 && (TimeCurrent() - m_last_order_open_time < 15))
   {
      s_slave_mc_counter = 0;
      return false; // Jangan memicu panen selama jeda eksekusi order (mencegah flapping 0 detik)
   }

   // 2. Evaluasi Likuidasi Riil Broker:
   bool is_slave_liquidated = false;
   if(m_slave_login > 0)
   {
      // A. Jika sisa Equity Slave benar-benar habis tuntas mendekati nol:
      if(m_slave_equity <= 15.0)
      {
         is_slave_liquidated = true;
      }
      // B. Jika posisi Slave ter-stop out oleh broker (posisi jadi 0 saat Master masih pegang):
      else if(m_slave_pos_count == 0 && master_count > 0)
      {
         // Jika Burner Mode aktif (sisa bonus masih diperjuangkan): HANYA anggap likuidasi jika equity <= $25
         if(IsBurnerModeActive())
         {
            if(m_slave_equity <= 25.0) is_slave_liquidated = true;
         }
         else
         {
            // Mode normal: Stop Out terjadi ketika equity <= $50 atau balance minus dan credit habis
            if(m_slave_equity <= 50.0 || (m_slave_balance <= 50.0 && m_slave_credit < 40.0))
               is_slave_liquidated = true;
         }
      }
   }

   if(is_slave_liquidated)
   {
      s_slave_mc_counter++;
      if(s_slave_mc_counter >= 20) // 20 siklus konfirmasi berturut-turut (1000ms / 1.0 detik stabil)
      {
         Print("🚨 [CRITICAL HEDGE SAFETY] Slave account (", m_slave_login,
               ") TERKONFIRMASI HABIS / LIQUIDASI (Equity: $", DoubleToString(m_slave_equity, 2),
               ", Bonus Terbakar Maksimal)! Menutup semua posisi Master untuk panen profit!");
         m_closing_active = true;
         m_closing_lock_until = TimeCurrent() + 6;
         CloseAllMasterPositions();
         m_closing_active = false;
         m_last_order_time = TimeCurrent();
         s_slave_mc_counter = 0;

         // HARD LOCKDOWN: Kunci mati bot Master setelah panen Slave MC!
         // KECUALI jika sisa Equity Slave masih cukup untuk Burner Mode (>= InpBurnerMinEquity):
         if(InpEnableBonusBurner && m_slave_equity >= InpBurnerMinEquity && m_slave_credit >= 40.0)
         {
            m_cycle_paused = false; // JANGAN DIKUNCI! Biarkan langsung masuk Burner Mode
            Print("🔥 [AUTO-DRAINER AKTIF] Slave terkena stop out tetapi sisa bonus masih $", DoubleToString(m_slave_equity, 2),
                  "! Memulai Burner Mode (Lot ", DoubleToString(InpBurnerLotSize, 2), "L) untuk menguras sisa bonus ke Master!");
            if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
            {
               SendTelegramMessage("🔥 <b>[AUTO BONUS DRAINER AKTIF]</b>\n" +
                                   "────────────────────────────\n" +
                                   "⚠️ Akun Slave #" + IntegerToString(m_slave_login) + " terkena likuidasi parsial broker.\n" +
                                   "💰 <b>Master berhasil panen & sisa Equity Slave masih $" + DoubleToString(m_slave_equity, 2) + "</b>\n" +
                                   "🚀 <b>Mengaktifkan Mode Kuras Bonus (Lot " + DoubleToString(InpBurnerLotSize, 2) + "L)</b> otomatis!\n" +
                                   "🎯 Sisa bonus akan terus ditradingkan sampai habis terserap ke Master.\n" +
                                   "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
            }
         }
         else
         {
            m_cycle_paused = true;
            CreateResumeButton();
            Print("🛑 [HARVEST LOCKDOWN] Slave terbakar tuntas & Master berhasil panen profit! Bot Master DIKUNCI PAUSE permanen.");
            if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
            {
               SendTelegramMessage("🛑 <b>[SLAVE TERBAKAR TUNTAS & MASTER PANEN SELESAI]</b>\n" +
                                   "────────────────────────────\n" +
                                   "💰 Akun Master #" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " berhasil menutup posisi dan mengunci profit kas!\n" +
                                   "🔒 <b>Seluruh bonus kredit telah terkuras habis. Bot di-PAUSE secara permanen.</b>\n" +
                                   "👉 Silakan reset deposit Slave #" + IntegerToString(m_slave_login) + " lalu tekan tombol <b>RESUME</b> di chart untuk memulai siklus baru.\n" +
                                   "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
            }
         }
         return true;
      }
   }
   else
   {
      s_slave_mc_counter = 0;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check Master Emergency Equity & Negative Balance Preservation    |
//| IRONCLAD SAFETY: Closes Master & Slave simultaneously BEFORE     |
//| Master touches broker stop-out (20%) or goes negative!           |
//+------------------------------------------------------------------+
bool CheckMasterEmergencyPreservation()
{
   if(m_closing_active || !InpEnableMasterShield) return false;

   // Hanya evaluasi jika Master memang memegang posisi terbuka
   int master_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && IsMasterPosition(ticket))
         master_count++;
   }
   if(master_count == 0) return false;

   double my_equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double my_margin_lvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double my_margin     = AccountInfoDouble(ACCOUNT_MARGIN);

   double my_balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double effective_buffer = (InpMasterMinEquityBuffer > 0.0) ? InpMasterMinEquityBuffer : MathMax(200.0, my_balance * 0.25);

   bool emergency_triggered = false;
   string reason = "";

   if(my_equity <= effective_buffer)
   {
      emergency_triggered = true;
      reason = "Equity Master tersisa $" + DoubleToString(my_equity, 2) + " <= Batas Pengaman Otomatis $" + DoubleToString(effective_buffer, 2);
   }
   else if(my_margin > 0.0 && my_margin_lvl > 0.0 && my_margin_lvl <= InpMasterMinMarginLevel)
   {
      emergency_triggered = true;
      reason = "Margin Level Master " + DoubleToString(my_margin_lvl, 1) + "% <= Batas Pengaman " + DoubleToString(InpMasterMinMarginLevel, 1) + "% (StopOut Broker: 20%)";
   }

   if(emergency_triggered)
   {
      Print("🚨 [MASTER EMERGENCY SHIELD TRIGGERED] ", reason,
            "! Menutup serentak Master & Slave agar saldo kas Master TIDAK PERNAH minus dan mengunci profit Slave!");
      
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 10;

      // PARALLEL ATOMIC CLOSE DISPATCH:
      // Kirim sinyal tutup darurat ke Slave terlebih dahulu agar profit Slave terkunci seketika!
      SendCommandToSlave("CLOSE_ALL");
      BroadcastMasterState();

      CloseAllMasterPositions();
      m_closing_active = false;
      m_last_order_time = TimeCurrent();

      // PAUSE PERMANEN SETELAH EMERGENCY SHIELD:
      m_cycle_paused = true;
      CreateResumeButton();

      if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
      {
         SendTelegramMessage("🚨 <b>[MASTER EMERGENCY SHIELD AKTIF]</b>\n" +
                             "────────────────────────────\n" +
                             "🛡️ " + reason + "\n" +
                             "💰 Seluruh posisi Master & Slave berhasil ditutup darurat.\n" +
                             "✅ <b>Saldo Kas Master berhasil diselamatkan (TIDAK MINUS)!</b>\n" +
                             "⏸️ Bot di-PAUSE secara aman. Silakan cek akun sebelum klik RESUME.\n" +
                             "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check Pre-News Auto Flat (Tutup Bersih Sebelum Berita Besar)    |
//+------------------------------------------------------------------+
bool CheckPreNewsAutoFlat()
{
   if(!InpAutoNewsFilter || !InpNewsPreCloseOrders || m_closing_active) return false;

   int master_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && IsMasterPosition(ticket))
         master_count++;
   }
   if(master_count == 0) return false;

   // DISTRIBUTED SAFETY INVARIANT:
   // Slave HARUS online dan jumlah hedge Slave HARUS lengkap mengunci seluruh posisi Master!
   // Jika Slave offline atau belum sinkron, DILARANG auto-flat karena perhitungan floating
   // gabungan akan invalid (hanya melihat floating Master yang semu).
   if(!m_slave_online || m_slave_pos_count < master_count)
   {
      return false;
   }

   datetime now = TimeCurrent();
   datetime from_time = now;
   datetime to_time   = now + (InpNewsPreCloseMinutes * 60);

   MqlCalendarValue values[];
   ResetLastError();
   int count = CalendarValueHistory(values, from_time, to_time, "US", "USD");
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               int mins_left = (int)((values[i].time - now) / 60);

               // Hitung Total Floating Profit Gabungan (Master + Slave)
               double total_master_profit = 0.0;
               for(int p = PositionsTotal() - 1; p >= 0; p--)
               {
                  ulong p_ticket = PositionGetTicket(p);
                  if(p_ticket > 0 && IsMasterPosition(p_ticket))
                     total_master_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               }
               double combined_net_profit = total_master_profit + (m_slave_online ? m_slave_profit : 0.0);

               // OPSI B: HANYA TUTUP JIKA POSISI SUDAH PROFIT / IMPAS (>= $0.0)
               if(InpNewsPreCloseOnlyIfProfit && combined_net_profit < 0.0)
               {
                  // Posisi masih floating minus: DILARANG CUT LOSS! Biarkan posisi tetap ter-hedge.
                  m_news_pause_until = values[i].time + (InpNewsPauseAfterMin * 60);
                  m_news_title = event.name;
                  static datetime s_last_news_minus_log = 0;
                  if(now - s_last_news_minus_log >= 30)
                  {
                     s_last_news_minus_log = now;
                     Print("📰 [PRE-NEWS HEDGE HOLD] Berita '", event.name, "' dalam ", mins_left,
                           " menit tapi posisi masih minus ($", DoubleToString(combined_net_profit, 2),
                           "). Menahan posisi tetap ter-hedge (ANTI-CUTLOSS) & mengunci grid (NEWS PAUSE)!");
                  }
                  return false; // JANGAN TUTUP ORDER!
               }

               Print("📰 [PRE-NEWS AUTO FLAT TRIGGERED] Berita High-Impact '", event.name,
                     "' akan rilis dalam ", mins_left, " menit (pukul ", TimeToString(values[i].time, TIME_MINUTES),
                     "). Posisi sudah profit/BEP ($", DoubleToString(combined_net_profit, 2),
                     "). Menutup bersih seluruh posisi Master & Slave sebelum badai berita!");

               m_closing_active = true;
               m_closing_lock_until = TimeCurrent() + 10;

               SendCommandToSlave("CLOSE_ALL");
               BroadcastMasterState();

               CloseAllMasterPositions();
               m_closing_active = false;
               m_last_order_time = TimeCurrent();

               m_news_pause_until = values[i].time + (InpNewsPauseAfterMin * 60);
               m_news_title = event.name;

               if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
               {
                  SendTelegramMessage("📰 <b>[PRE-NEWS AUTO FLAT SELESAI]</b>\n" +
                                      "────────────────────────────\n" +
                                      "⚠️ Berita High-Impact: <b>" + event.name + "</b>\n" +
                                      "⏰ Waktu Rilis: " + TimeToString(values[i].time, TIME_DATE|TIME_MINUTES) + " (" + IntegerToString(mins_left) + " menit lagi)\n" +
                                      "🛡️ <b>Seluruh posisi Master & Slave telah ditutup bersih pada spread normal.</b>\n" +
                                      "⏸️ Grid dikunci sampai berita selesai (" + TimeToString(m_news_pause_until, TIME_MINUTES) + ").");
               }
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| UNHEDGED ORPHAN WATCHDOG                                         |
//| Closes any Master position left unhedged by Slave for > 15s      |
//+------------------------------------------------------------------+
void CheckUnhedgedOrphanWatchdog()
{
   if(m_unhedged_watchdog <= 0) return;
   if(!m_slave_online || m_closing_active || m_cycle_paused) return;

   int master_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      // WATCHDOG hanya untuk posisi GRID EA (magic sendiri). Posisi manual
      // (magic 0) sengaja TIDAK dihedging Slave -> tidak boleh memicu watchdog
      // menutup seluruh grid hanya karena user buka posisi manual!
      if(ticket > 0
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
         && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
      {
         master_count++;
      }
   }

   static ulong s_unhedged_start_tick = 0;

   // 1. Kondisi normal: Master dan Slave seimbang -> RESET TIMER WATCHDOG KE 0! (v1.27 FIX)
   if(master_count == 0 || master_count <= m_slave_pos_count)
   {
      s_unhedged_start_tick = 0;
      if(!m_slave_trade_blocked) m_blocked_alert_sent = false;
      return;
   }

   // 2. Kondisi Slave trade-blocked (algo OFF / CB) -> Tahan, jangan bunuh posisi
   if(m_slave_trade_blocked)
   {
      s_unhedged_start_tick = 0; // Reset watchdog agar tidak menumpuk saat blocked
      if(!m_blocked_alert_sent)
      {
         m_blocked_alert_sent = true;
         Print("🚫 [SLAVE TRADE-BLOCKED] Slave online tapi tidak bisa eksekusi order (Algo OFF / Circuit Breaker). Grid DITAHAN - tidak ada watchdog close.");
         if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
         {
            SendTelegramMessage("🚫 <b>[SLAVE TIDAK BISA EKSEKUSI]</b>\n" +
                                "────────────────────────────\n" +
                                "⚠️ Slave online tapi <b>Algo Trading OFF / Circuit Breaker aktif</b> di terminal Slave.\n" +
                                "🛡️ Grid <b>DITAHAN</b> - tidak ada order baru (proteksi spread FOMC). Posisi existing tetap ter-hedge & aman.\n" +
                                "👉 Nyalakan tombol Algo Trading di terminal Slave, bot lanjut otomatis.\n" +
                                "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
         }
      }
      return;
   }

   // 3. Kondisi Unhedged Sungguhan: Master > Slave dan Slave tidak blocked
   m_blocked_alert_sent = false;
   if(s_unhedged_start_tick == 0)
   {
      s_unhedged_start_tick = GetTickCount64();
   }
   else if(GetTickCount64() - s_unhedged_start_tick > (ulong)(m_unhedged_watchdog * 1000))
   {
      Print("🚨 [UNHEDGED WATCHDOG TRIGGERED] Master memiliki ", master_count, " posisi tapi Slave hanya meng-hedge ",
            m_slave_pos_count, " posisi selama > ", m_unhedged_watchdog, " detik! Menutup posisi unhedged demi keselamatan modal!");
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 6;
      CloseAllMasterPositions();
      m_closing_active = false;
      m_last_order_time = TimeCurrent();
      s_unhedged_start_tick = 0;

      if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
      {
         SendTelegramMessage("🚨 <b>[UNHEDGED WATCHDOG TRIGGERED]</b>\n" +
                             "────────────────────────────\n" +
                             "⚠️ Ditemukan posisi Master yang tidak di-hedge oleh Slave selama > " + IntegerToString(m_unhedged_watchdog) + " detik.\n" +
                             "🛡️ <b>Posisi Master ditutup otomatis demi keselamatan modal!</b>\n" +
                             "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
      }
   }
}

//+------------------------------------------------------------------+
//| DUAL SPREAD-LOCK GUARD (v1.26): Memeriksa spread Master & Slave  |
//| Mencegah eksekusi close TP dan entry baru saat spread mekar liar  |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   if(InpMaxSpreadPoints <= 0) return true;
   long master_spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   long slave_spread  = (m_slave_online && m_slave_spread > 0) ? m_slave_spread : 0;
   long worst_spread  = MathMax(master_spread, slave_spread);

   if(worst_spread > (long)InpMaxSpreadPoints)
   {
      static datetime s_last_spread_log = 0;
      if(TimeCurrent() - s_last_spread_log >= 5)
      {
         Print("🛡️ [DUAL SPREAD-LOCK ACTIVE] Master Spread: ", master_spread,
               " pts | Slave Spread: ", slave_spread,
               " pts > batas ", (long)InpMaxSpreadPoints, " pts ($", DoubleToString(InpMaxSpreadPoints * m_point, 2),
               "). Menahan eksekusi untuk mencegah slippage!");
         s_last_spread_log = TimeCurrent();
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| SPIKE VELOCITY GUARD: Mendeteksi lonjakan lilin M1 liar           |
//| Mencegah bot membuka posisi di dasar jurang / pucuk spike berita  |
//+------------------------------------------------------------------+
bool CheckSpikeVelocity()
{
   if(!InpEnableSpikeVelocity || InpSpikeVelocityUSD <= 0) return false;

   if(TimeCurrent() < m_spike_cooldown_until)
      return true;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, PERIOD_M1, 0, 2, rates);
   if(copied >= 1)
   {
      double cur_range = (rates[0].high - rates[0].low);
      double prev_range = (copied >= 2) ? (rates[1].high - rates[1].low) : 0.0;
      double max_range = MathMax(cur_range, prev_range);

      if(max_range >= InpSpikeVelocityUSD)
      {
         m_spike_cooldown_until = TimeCurrent() + (InpSpikeCooldownMin * 60);
         m_spike_reason = "Spike $" + DoubleToString(max_range, 2) + " >= $" + DoubleToString(InpSpikeVelocityUSD, 2) + " in M1";
         Print("🚨 [SPIKE VELOCITY GUARD] Terdeteksi lilin lonjakan liar (", m_spike_reason,
               ")! Mengaktifkan Cooldown selama ", InpSpikeCooldownMin, " menit.");
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| ECONOMIC CALENDAR NEWS FILTER: Kalender Ekonomi Otomatis MT5     |
//| Jeda otomatis sebelum & sesudah berita High Impact USD            |
//+------------------------------------------------------------------+
bool IsHighImpactNewsNearby()
{
   if(!InpAutoNewsFilter) return false;

   static datetime s_last_calendar_check = 0;
   static bool     s_is_news_nearby      = false;

   datetime now = TimeCurrent();
   if(now < m_news_pause_until)
      return true;

   if(now - s_last_calendar_check < 10)
      return s_is_news_nearby;

   s_last_calendar_check = now;
   s_is_news_nearby = false;

   datetime from_time = now - (InpNewsPauseAfterMin * 60);
   datetime to_time   = now + (InpNewsPauseBeforeMin * 60);

   MqlCalendarValue values[];
   ResetLastError();
   int count = CalendarValueHistory(values, from_time, to_time, "US", "USD");
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               m_news_pause_until = values[i].time + (InpNewsPauseAfterMin * 60);
               m_news_title = event.name;
               s_is_news_nearby = true;
               Print("📰 [HIGH-IMPACT NEWS DETECTED] Acara: '", m_news_title, "' dijadwalkan pada ",
                     TimeToString(values[i].time, TIME_DATE|TIME_MINUTES), ". Grid dikunci hingga ",
                     TimeToString(m_news_pause_until, TIME_DATE|TIME_MINUTES));
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Main Grid Strategy Execution                                     |
//+------------------------------------------------------------------+
void ManageGrid()
{
   int    total_positions = 0;   // termasuk manual (untuk TP basket & close)
   int    ea_positions    = 0;   // hanya grid EA (untuk guard count hedge Slave)
   double total_profit    = 0.0;
   double min_price       = DBL_MAX;
   double max_price       = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsMasterPosition(ticket))
      {
         total_positions++;
         if(PositionGetInteger(POSITION_MAGIC) == (long)m_magic || PositionGetInteger(POSITION_MAGIC) == 888111)
            ea_positions++;
         total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
         if(open_p < min_price) min_price = open_p;
         if(open_p > max_price) max_price = open_p;
      }
   }

   // --- MANUAL INTERVENTION: CLOSE ALL 2 POSISI SEKETIKA ---
   static bool s_manual_close_input_done = false;
   if(InpCloseAll)
   {
      if(!s_manual_close_input_done)
      {
         s_manual_close_input_done = true;
         ExecuteManualCloseAll("Parameter InpCloseAll = TRUE");
      }
      return; // Kunci seluruh aktivitas grid selama parameter InpCloseAll masih true!
   }
   else
   {
      s_manual_close_input_done = false; // Reset ketika user mengembalikan ke false
   }

   double ref_bal          = GetReferenceBalance();
   double effective_lot    = GetEffectiveLot(ref_bal);
   double base_tp_amount   = GetBaseTPAmount(ref_bal);
   m_spread_buffer         = GetEffectiveSpreadBuffer();
   double effective_basket_tp = (base_tp_amount > 0) ? (base_tp_amount + m_spread_buffer) : 0.0;

   // --- CHECK COMBINED NET PROFIT (MASTER + SLAVE GABUNGAN PLUS) ---
   // Wajib gabungan Master + Slave terkonfirmasi ONLINE agar 100% meng-cover semua spread dan komisi!
   // DILARANG KERAS menutup TP jika Slave belum terverifikasi online (mencegah false trigger profit sepihak)!
   if(!m_slave_online)
   {
      // Slave belum online: JANGAN buka posisi sendirian & jangan tutup TP sepihak!
      return;
   }

   // FOMC / EXECUTION SHIELD (v1.25):
   // Slave melapor TIDAK BISA EKSEKUSI order (Algo Trading OFF / circuit breaker Slave).
   // Tahan SEMUA aktivitas grid: jangan buka layer baru, dan JANGAN tutup TP sepihak
   // (posisi Slave sedang mengunci Master - menutup sepihak = naked exposure).
   if(m_slave_trade_blocked)
   {
      return;
   }

   // WEEKEND / MARKET CLOSED LOCK:
   MqlDateTime dt_loc;
   TimeToStruct(TimeLocal(), dt_loc);
   if(dt_loc.day_of_week == 0 || dt_loc.day_of_week == 6) return; // Silent & standby on weekends!

   double combined_net_profit = total_profit + m_slave_profit;

   static int s_tp_confirm_counter = 0;

   // STRICT INVARIANT 1: HEDGE SYMMETRY REQUIREMENT (v1.28)
   // DILARANG KERAS mengevaluasi / memicu TP Gabungan jika jumlah posisi Slave kurang dari posisi Master!
   // Jika Master punya 4 posisi tapi Slave cuma melapor 3 posisi (asimetris), TP haram ditembak
   // karena ada 1 posisi unhedged yang menghasilkan keuntungan/kerugian semu!
   if(ea_positions > 0 && m_slave_pos_count < ea_positions)
   {
      s_tp_confirm_counter = 0;
      return; // Tahan sampai Slave 100% simetris meng-hedge seluruh layer Master!
   }

   if(total_positions > 0 && m_slave_pos_count >= ea_positions && effective_basket_tp > 0 && combined_net_profit >= effective_basket_tp)
   {
      // 1. DUAL SPREAD-LOCK PROTECTION:
      // Tahan eksekusi TP jika spread Master ATAU Slave sedang mekar (misal saat FOMC/CPI spike 200-500 poin).
      if(!IsSpreadAcceptable())
      {
         s_tp_confirm_counter = 0;
         return; // Tunda close basket sampai spread kedua broker aman
      }

      // 2. SPIKE VELOCITY GUARD ON TAKE PROFIT (v1.26):
      // Tahan eksekusi TP di detik lilin M1 meledak liar (anti-slippage Ask saat spike berita besar).
      if(CheckSpikeVelocity())
      {
         s_tp_confirm_counter = 0;
         return; // Tunda close basket sampai lonjakan lilin M1 reda
      }

      // 3. DIRECTIONAL REVERSAL GUARD:
      // Karena portofolio adalah Net BUY (+10% volume di Slave), Take Profit hanya boleh dipicu
      // saat harga sedang memantul naik (rebound), BUKAN di detik harga terjun bebas ke dasar lembah!
      double cur_bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(min_price < DBL_MAX && cur_bid < min_price)
      {
         s_tp_confirm_counter = 0;
         return; // Harga sedang di bawah titik open terendah (dasar jurang), tunda TP sampai rebound!
      }

      // 4. ANTI-PHANTOM DEBOUNCE CONFIRMATION:
      // Wajib bertahan terkonfirmasi positif minimal 3 siklus timer berturut-turut (150ms)
      // untuk mencegah pemicuan salah akibat jeda pembacaan file telemetry sesaat (anti-phantom profit)!
      s_tp_confirm_counter++;
      if(s_tp_confirm_counter < 3)
      {
         return; // Tunggu 150ms konfirmasi kestabilan angka Slave
      }
      s_tp_confirm_counter = 0;

      Print("🎉 [COMBINED NET TP TRIGGERED] Total Gabungan (Master: $", DoubleToString(total_profit, 2),
            " + Slave: $", DoubleToString(m_slave_profit, 2), ") = $", DoubleToString(combined_net_profit, 2),
            " >= Target $", DoubleToString(effective_basket_tp, 2), " (Base $", DoubleToString(base_tp_amount, 2),
            " + Buffer $", DoubleToString(m_spread_buffer, 2), " Ter-Cover!)");
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 6; // 6-second closing lock
      
      // PARALLEL ATOMIC CLOSE DISPATCH:
      // Kirim sinyal tutup ke Slave LEBIH DULU agar kedua terminal MT5 menutup order di milidetik yang sama!
      SendCommandToSlave("CLOSE_ALL");
      BroadcastMasterState(); // Flush file seketika
      
      CloseAllMasterPositions();
      m_closing_active = false;
      m_last_order_time = TimeCurrent();

      // PAUSE SETELAH SIKLUS SELESAI (JIKA DIAKTIFKAN OLEH USER):
      if(InpPauseAfterCycle)
      {
         m_cycle_paused = true;
         CreateResumeButton();
         Print("⏸️ [CYCLE COMPLETED & PAUSED] 1 Siklus selesai profit! Bot di-PAUSE secara aman untuk update/setting. Klik tombol RESUME di chart atau ubah setting untuk lanjut.");
      }
      return;
   }


   // --- PAUSE AFTER CYCLE GUARD ---
   if(m_cycle_paused && total_positions == 0)
   {
      // Bot dijeda menunggu user klik RESUME atau ganti settingan/update
      return;
   }


   // --- UNIVERSAL ANTI-FLAPPING CIRCUIT BREAKER SHIELD ---
   if(TimeCurrent() < m_circuit_breaker_until)
   {
      // HARD LOCKOUT: Master dilarang membuka order apapun selama masa circuit breaker!
      return;
   }

   // --- PRE-TRADE MARGIN CHECK (SELF & SLAVE) ---
   double my_free_margin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double my_margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   // 1. Do not open if Master's own margin or equity is critical
   double my_cur_eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double my_safe_buf = (InpMasterMinEquityBuffer > 0.0) ? InpMasterMinEquityBuffer : MathMax(200.0, AccountInfoDouble(ACCOUNT_BALANCE) * 0.25);
   if(my_cur_eq <= my_safe_buf || my_free_margin < InpMinFreeMargin || (my_margin_level > 0 && my_margin_level < m_min_margin_level))
   {
      return; // Hold off, margin/equity critical
   }

   // 2. Do not open if Slave's margin is critical or Slave cannot afford new hedge (Checks Layer 1 & Grid!)
   if(m_slave_online)
   {
      bool is_burner = IsBurnerModeActive();
      double min_fund_req = is_burner ? (InpBurnerMinEquity * 0.75) : 100.0;
      double min_free_req = is_burner ? 40.0 : InpMinFreeMargin;
      double min_lvl_req  = is_burner ? 50.0 : m_min_margin_level;

      // Akun Bonus: Balance bisa minus tetapi masih memiliki Equity / Free Margin dari Credit Bonus!
      double eff_slave_fund = (m_slave_equity > 0.0) ? m_slave_equity : m_slave_balance;
      double slave_dyn_req  = EstimateSlaveRequiredMargin(effective_lot) * 1.5;
      double eff_free_req   = MathMax(min_free_req, slave_dyn_req);

      if(eff_slave_fund < min_fund_req || m_slave_free_margin < eff_free_req || (m_slave_margin_level > 0 && m_slave_margin_level < min_lvl_req))
      {
         // Slave kehabisan margin/equity (butuh Rebalance/Deposit): JANGAN BUKA ORDER APAPUN!
         return;
      }

      if(is_burner && !m_burner_alert_sent)
      {
         m_burner_alert_sent = true;
         Print("🔥 [BURNER MODE RUNNING] Slave Balance: $", DoubleToString(m_slave_balance, 2),
               ", Equity: $", DoubleToString(m_slave_equity, 2), " (Credit $", DoubleToString(m_slave_credit, 2),
               "). Lot khusus kuras bonus: ", DoubleToString(InpBurnerLotSize, 2), "L");
      }
   }
   else if(!m_slave_online)
   {
      // Slave offline: Jangan buka posisi baru sendirian!
      return;
   }

   // Cooldown between orders (10 seconds) and Closing Lock guard
   if(TimeCurrent() < m_closing_lock_until) return;
   if(TimeCurrent() - m_last_order_time < 10) return;

   // --- BIG NEWS & SPREAD VOLATILITY SHIELD ---
   // 1. Spread-Lock Guard: Dilarang buka order baru jika spread sedang mekar liar
   if(!IsSpreadAcceptable()) return;

   // 2. Spike Velocity Guard: Dilarang buka order baru saat lilin M1 meledak liar (anti-tangkap pisau jatuh)
   if(CheckSpikeVelocity()) return;

   // 3. Economic Calendar Filter: Dilarang buka order baru 15 menit sebelum & sesudah High Impact USD news
   // 4. Layer-by-Layer Harvest Lock: Dilarang buka layer baru selama proses panen stop out sedang berlangsung!
   if(m_harvest_in_progress) return;

   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick) || tick.bid <= 0) return;

   // --- LAYER 1 (INITIAL ORDER) ---
   if(total_positions == 0)
   {
      // STRICT INITIAL LAYER 1 PREREQUISITE:
      // Master DILARANG KERAS membuka posisi awal (Layer 1) jika:
      // 1. Akun Slave kosong / belum login (Login <= 0 atau Equity <= 0)
      // 2. Saldo Slave <= 0 DAN belum ada credit bonus (Credit < $40.0)
      // 3. Slave Free Margin < $40.0
      if(m_slave_login <= 0 || m_slave_equity <= 0.0 || (m_slave_balance <= 0.0 && m_slave_credit < 40.0) || m_slave_free_margin < 40.0)
      {
         // Slave belum deposit / bonus belum masuk / akun kosong: JANGAN BUKA POSISI!
         return;
      }

      m_last_order_time = TimeCurrent(); // Update cooldown immediately to prevent rapid-fire loops
      m_last_order_open_time = TimeCurrent();
      m_cycle_start_time = TimeCurrent(); // v1.27: Waktu awal siklus HANYA dicatat saat Layer 1 dibuka!
      string comment = m_comment_prefix + "1";
      if(m_trade.Sell(effective_lot, m_symbol, tick.bid, 0, 0, comment))
      {
         Print("✅ [MASTER OPEN INITIAL] Layer 1: SELL ", effective_lot, "L @ ", tick.bid, " (", comment, ")");
         BroadcastMasterState(); // ZERO-LATENCY BROADCAST: Langsung kirim state ke Slave tanpa menunggu timer 50ms!
      }
      return;
   }

   // --- NEXT LAYERS (GRID STEPS) ---
   if(ea_positions < InpMaxLayers)
   {
      // SAFETY CHECK 1: Jangan pernah buka Layer berikutnya jika Slave belum berhasil
      // meng-hedge SEMUA layer grid EA sebelumnya! (Bandingkan dengan ea_positions —
      // posisi manual tidak pernah dihedging Slave, jadi tidak ikut dihitung.
      // Dengan InpIncludeManualTrades=true + manual open, total_positions > slave_count
      // selamanya; guard lama akan membekukan grid permanen — ini bug deadlock.)
      if(m_slave_online && m_slave_pos_count < ea_positions)
      {
         return; // Hold off, tunggu Slave selesai hedge
      }

      // SAFETY CHECK 2 (NEAR-TP EXIT SHIELD v1.27):
      // Jangan buka Layer baru jika profit gabungan saat ini sudah mendekati Target TP!
      // Ambang batas: >= 75% dari Target TP ATAU sisa jarak profit <= 25% Target TP (max $15)
      if(effective_basket_tp > 0)
      {
         double near_tp_margin = MathMin(15.0, effective_basket_tp * 0.25);
         if(combined_net_profit >= (effective_basket_tp * 0.75) || (effective_basket_tp - combined_net_profit) <= near_tp_margin)
         {
            Print("🛡️ [NEAR-TP SHIELD] Profit gabungan ($", DoubleToString(combined_net_profit, 2),
                  ") sudah mendekati target TP ($", DoubleToString(effective_basket_tp, 2),
                  "). Menahan penambahan layer baru agar keranjang menyelesaikan TP!");
            return;
         }
      }

      // SAFETY CHECK 3 (SLAVE MARGIN CAPACITY PRE-CHECK v1.34):
      // Sebelum Master membuka Layer berikutnya, Master WAJIB memvalidasi apakah Slave
      // memiliki Free Margin yang cukup untuk meng-hedge layer baru tersebut!
      // JIKA SLAVE TIDAK CUKUP MARGIN: DILARANG BUKA LAYER BARU! Tahan posisi yang ada (HOLD).
      if(m_slave_online)
      {
         double slave_req_margin = EstimateSlaveRequiredMargin(effective_lot);
         double safety_margin_buffer = slave_req_margin * 1.5; // Margin required + 50% safety cushion

         if(m_slave_free_margin < safety_margin_buffer || (m_slave_margin_level > 0.0 && m_slave_margin_level < 150.0))
         {
            static datetime s_last_slave_margin_alert = 0;
            if(TimeCurrent() - s_last_slave_margin_alert >= 60)
            {
               s_last_slave_margin_alert = TimeCurrent();
               Print("🛡️ [SLAVE MARGIN CAPACITY GUARD] Slave Free Margin ($", DoubleToString(m_slave_free_margin, 2),
                     ") tidak cukup untuk hedge layer baru (Butuh ~$ ", DoubleToString(safety_margin_buffer, 2),
                     " buffer | ML: ", DoubleToString(m_slave_margin_level, 1),
                     "%). Menahan Layer ", (ea_positions + 1), " (HOLD POSISI EKSISTING - ANTI-CLOSE ALL)!");
            }
            return; // TAHAN! JANGAN BUKA LAYER BARU! Biarkan posisi eksisting ter-hedge sampai TP.
         }
      }

      double step_distance = InpGridStepPoints * m_point;
      bool should_open = false;

      if(min_price < DBL_MAX)
      {
         // BI-DIRECTIONAL BONUS EXTRACTION GRID:
         // 1. Buka Layer saat harga NAIK -> Panen TP Gabungan (+0.01 lot delta asimetris)
         if((tick.bid - max_price) >= step_distance) should_open = true;

         // 2. Buka Layer saat harga TURUN -> HANYA JIKA SLAVE AMAN DARI LIQUIDASI! (v1.27)
         // DILARANG membuka layer ke bawah jika Slave sekarat (Equity < $150 atau Margin Level < InpMinMarginLevel)
         if((min_price - tick.bid) >= step_distance)
         {
            if(m_slave_online && (m_slave_equity < 150.0 || (m_slave_margin_level > 0 && m_slave_margin_level < m_min_margin_level) || m_slave_free_margin < 250.0))
            {
               Print("⚠️ [DOWNWARD GRID SHIELD] Slave mendekati likuidasi/MC (Equity: $", DoubleToString(m_slave_equity, 2),
                     ", ML: ", DoubleToString(m_slave_margin_level, 1),
                     "%, Free: $", DoubleToString(m_slave_free_margin, 2), ")! Menahan layer bawah untuk panen MC bersih.");
               should_open = false;
            }
            else
            {
               should_open = true;
            }
         }
      }

      if(should_open)
      {
         m_last_order_time = TimeCurrent(); // Update cooldown immediately
         m_last_order_open_time = TimeCurrent();
         string comment = m_comment_prefix + IntegerToString(total_positions + 1);
         if(m_trade.Sell(effective_lot, m_symbol, tick.bid, 0, 0, comment))
         {
            Print("✅ [MASTER OPEN NEXT LAYER] Layer ", (total_positions + 1), ": SELL ",
                  effective_lot, "L @ ", tick.bid, " (", comment, ")");
            BroadcastMasterState(); // ZERO-LATENCY BROADCAST: Langsung kirim state ke Slave tanpa jeda!
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all Master grid positions safely                           |
//+------------------------------------------------------------------+
void CloseAllMasterPositions()
{
   int closed_count = 0;
   for(int attempt = 0; attempt < 3; attempt++)
   {
      int remaining = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(IsMasterPosition(ticket))
         {
            if(m_trade.PositionClose(ticket))
               closed_count++;
            else
               remaining++;
         }
      }
      if(remaining == 0) break;
      Sleep(30);
   }

   if(closed_count > 0)
   {
      m_last_order_close_time = TimeCurrent();
      int cycle_lifespan = (m_cycle_start_time > 0) ? (int)(TimeCurrent() - m_cycle_start_time) : 999;

      // SHIELD: Umur siklus dihitung dari waktu Layer 1 dibuka (m_cycle_start_time).
      // Hanya jika satu siklus penuh dibuka dan ditutup <= 20 detik yang dianggap flapping abnormal:
      if(m_cycle_start_time > 0 && cycle_lifespan <= 20)
      {
         m_rapid_close_counter++;
         Print("⚠️ [ANTI-FLAPPING MONITOR] Terdeteksi siklus kilat abnormal (Umur Siklus: ", cycle_lifespan, "s). Counter: ", m_rapid_close_counter);

         // Jika terdeteksi 2x buka-tutup kilat abnormal: KUNCI MATI SELAMA 5 MENIT!
         if(m_rapid_close_counter >= 2)
         {
            m_circuit_breaker_until = TimeCurrent() + 300; // 5 Menit Lockout
            m_circuit_breaker_reason = "Terdeteksi 2x Siklus Kilat Abnormal (<20s)";
            Print("🚨 [CIRCUIT BREAKER ACTIVATED] Bot dikunci PAUSE selama 5 menit untuk melindungi modal!");
            if(InpEnableTelegram)
            {
               SendTelegramMessage("🚨 <b>[CIRCUIT BREAKER SHIELD DIAKTIFKAN]</b>\n" +
                                   "────────────────────────────\n" +
                                   "⚠️ Terdeteksi 2x siklus buka-tutup kilat abnormal berturut-turut (&lt;20 detik).\n" +
                                   "🛑 <b>Trading DIKUNCI PAUSE selama 5 Menit</b> untuk melindungi modal Anda dari biaya spread!\n" +
                                   "⏳ Trading akan otomatis resume pada: <b>" + TimeToString(m_circuit_breaker_until, TIME_MINUTES|TIME_SECONDS) + "</b>\n" +
                                   "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
            }
         }
      }
      else
      {
         m_rapid_close_counter = 0;
      }
      m_cycle_start_time = 0; // Reset waktu siklus setelah seluruh posisi ditutup
   }
}

//+------------------------------------------------------------------+
//| Close a Single Master Position by Ticket (Layer-by-Layer Harvest)|
//+------------------------------------------------------------------+
bool CloseMasterPositionByTicket(ulong target_ticket)
{
   if(target_ticket <= 0) return false;
   for(int attempt = 0; attempt < 3; attempt++)
   {
      if(PositionSelectByTicket(target_ticket))
      {
         if(m_trade.PositionClose(target_ticket))
         {
            Print("🎯 [MASTER HARVEST] Berhasil menutup tiket Master #", target_ticket, " @ ", SymbolInfoDouble(m_symbol, SYMBOL_BID));
            return true;
         }
      }
      Sleep(25);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Broadcast Master State via FILE_COMMON (Includes Margin Data)    |
//+------------------------------------------------------------------+
void BroadcastMasterState()
{
   int count = 0;
   double total_prof = 0.0;
   ulong  tickets[];
   int    types[];
   double volumes[], prices[], profits[];
   string comments[];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsMasterPosition(ticket))
      {
         ArrayResize(tickets,  count + 1);
         ArrayResize(types,    count + 1);
         ArrayResize(volumes,  count + 1);
         ArrayResize(prices,   count + 1);
         ArrayResize(profits,  count + 1);
         ArrayResize(comments, count + 1);

         tickets[count]  = ticket;
         types[count]    = (int)PositionGetInteger(POSITION_TYPE);
         volumes[count]  = PositionGetDouble(POSITION_VOLUME);
         prices[count]   = PositionGetDouble(POSITION_PRICE_OPEN);
         profits[count]  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         comments[count] = PositionGetString(POSITION_COMMENT);
         total_prof     += profits[count];
         count++;
      }
   }

   int file_handle = FileOpen(m_master_file, FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle == INVALID_HANDLE) return;

   static long s_broadcast_counter = 0;
   s_broadcast_counter++;
   FileWriteLong(file_handle, 0x42484246);         // magic "BHBF"
   FileWriteLong(file_handle, 2);                  // protocol version
   FileWriteLong(file_handle, s_broadcast_counter);// heartbeat counter
   FileWriteLong(file_handle, AccountInfoInteger(ACCOUNT_LOGIN));
   FileWriteDouble(file_handle, AccountInfoDouble(ACCOUNT_EQUITY));
   FileWriteDouble(file_handle, AccountInfoDouble(ACCOUNT_BALANCE));
   FileWriteDouble(file_handle, AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   FileWriteDouble(file_handle, AccountInfoDouble(ACCOUNT_MARGIN_LEVEL));
   FileWriteDouble(file_handle, total_prof);
   FileWriteInteger(file_handle, count);

   for(int i = 0; i < count; i++)
   {
      FileWriteLong(file_handle, (long)tickets[i]);
      FileWriteInteger(file_handle, types[i]);
      FileWriteDouble(file_handle, volumes[i]);
      FileWriteDouble(file_handle, prices[i]);
      FileWriteDouble(file_handle, profits[i]);
      int clen = StringLen(comments[i]);
      FileWriteInteger(file_handle, clen);
      if(clen > 0) FileWriteString(file_handle, comments[i], clen);
   }

   // Trailing Extension: Multiplier Sync (Tag 0x4D554C54 = 'MULT')
   FileWriteLong(file_handle, 0x4D554C54);
   FileWriteDouble(file_handle, InpSlaveMultiplier);

   FileFlush(file_handle);
   FileClose(file_handle);

   static datetime s_last_cfg_broadcast = 0;
   if(TimeLocal() - s_last_cfg_broadcast >= 2)
   {
      s_last_cfg_broadcast = TimeLocal();
      BroadcastSlaveConfig();
   }
}

//+------------------------------------------------------------------+
//| Broadcast Multiplier Config to dedicated Slave config file       |
//+------------------------------------------------------------------+
void BroadcastSlaveConfig()
{
   int pid = (InpPairID <= 1) ? 1 : InpPairID;
   string suffix = (pid == 1) ? "" : ("_" + IntegerToString(pid));
   string cfg_file = "bonus_slave_cfg" + suffix + ".dat";

   int handle = FileOpen(cfg_file, FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE) return;

   FileWriteLong(handle, 0x43464731); // "CFG1"
   FileWriteDouble(handle, InpSlaveMultiplier);
   FileFlush(handle);
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Check incoming commands from Slave                               |
//+------------------------------------------------------------------+
void CheckIncomingCommands()
{
   if(!FileIsExist(m_cmd_to_master, FILE_COMMON)) return;

   int file_handle = FileOpen(m_cmd_to_master, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle == INVALID_HANDLE) return;

   // Validated read: Magic Header + Sender Login + clen + cmd
   ResetLastError();
   long cmd_magic = FileReadLong(file_handle);
   bool ok = (GetLastError() == 0);
   long sender_login = 0;
   int clen = 0;
   string cmd = "";

   if(ok && cmd_magic == 0x4248434D) // Protocol v2 with Login Insulation
   {
      ResetLastError(); sender_login = FileReadLong(file_handle); ok = (GetLastError() == 0);
      if(ok) { ResetLastError(); clen = FileReadInteger(file_handle); ok = (GetLastError() == 0); }
      if(ok && clen > 0 && clen <= 64)
      {
         ResetLastError(); cmd = FileReadString(file_handle, clen); ok = (GetLastError() == 0);
      }
   }
   else if(ok) // Protocol v1 legacy fallback
   {
      clen = (int)cmd_magic;
      if(clen > 0 && clen <= 64)
      {
         ResetLastError(); cmd = FileReadString(file_handle, clen); ok = (GetLastError() == 0);
      }
   }
   FileClose(file_handle);

   if(!ok || clen <= 0 || clen > 64) return; // partial/invalid: biarkan file, retry next tick

   // Isolation: Jika perintah bukan berasal dari Slave terdaftar akun ini, abaikan!
   if(cmd_magic == 0x4248434D && m_slave_login > 0 && sender_login != 0 && sender_login != m_slave_login)
   {
      return;
   }

   FileDelete(m_cmd_to_master, FILE_COMMON);

   // --- PANEN BERJENJANG (LAYER-BY-LAYER HARVEST) ---
   if(StringFind(cmd, "SLAVE_SO_TICKET:") == 0 && !m_closing_active)
   {
      string ticket_str = StringSubstr(cmd, 16);
      ulong target_ticket = (ulong)StringToInteger(ticket_str);
      if(target_ticket > 0)
      {
         m_harvest_in_progress = true; // KUNCI: Dilarang buka layer baru selama panen berjenjang!
         m_closing_active = true;
         m_closing_lock_until = TimeCurrent() + 4;
         
         bool closed = CloseMasterPositionByTicket(target_ticket);
         m_closing_active = false;
         m_last_order_time = TimeCurrent();

         // Hitung sisa posisi Master
         int remaining_master = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong t = PositionGetTicket(i);
            if(t > 0 && IsMasterPosition(t)) remaining_master++;
         }

         if(remaining_master == 0)
         {
            m_cycle_paused = true;
            m_harvest_in_progress = false;
            CreateResumeButton();
            Print("🛑 [HARVEST FULLY COMPLETED] Seluruh tiket Master telah tuntas dipanen berjenjang! Bot Master di-PAUSE secara aman.");
         }
         else
         {
            Print("🎯⚡ [LAYER-BY-LAYER HARVEST] Tiket Master #", target_ticket, 
                  " BERHASIL DITUTUP! Sisa ", remaining_master, " layer Master tetap aktif ter-hedge untuk membakar sisa bonus Slave.");
         }
         return;
      }
   }

   if(cmd == "SLAVE_STOPPED_OUT" && !m_closing_active)
   {
      Print("🚨⚡ [ZERO-DELAY HARVEST TRIGGERED] Slave #", sender_login, " TER-STOP OUT BROKER! Menutup seketika seluruh posisi Master di milidetik yang sama tanpa jeda!");
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 6;
      m_harvest_in_progress = false;
      SendCommandToSlave("CLOSE_ALL"); // Garansi penutupan dua arah: pastikan Slave juga 100% flat
      BroadcastMasterState();
      CloseAllMasterPositions();
      m_closing_active = false;
      m_last_order_time = TimeCurrent();

      // PAUSE PERMANEN SETELAH PANEN STOP OUT SLAVE:
      m_cycle_paused = true;
      CreateResumeButton();
      Print("🛑 [HARVEST LOCKDOWN] Master berhasil panen profit instan di titik stop out Slave! Bot Master di-PAUSE secara aman.");
      return;
   }

   if(cmd == "CLOSE_ALL" && !m_closing_active)
   {
      Print("🚨 [MASTER] Received Emergency CLOSE_ALL from Slave #", sender_login, "! Closing all positions.");
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 4;
      CloseAllMasterPositions();
      m_closing_active = false;
      m_last_order_time = TimeCurrent();

      // HARD LOCKDOWN: Emergency CLOSE_ALL dari Slave artinya Slave gagal hedge (not enough money / MC).
      // DILARANG KERAS Master mencoba re-open sendiri! Kunci pause permanen sampai user cek & tekan Resume!
      m_cycle_paused = true;
      CreateResumeButton();
      Print("🛑 [EMERGENCY LOCKDOWN] Bot Master di-PAUSE secara permanen karena Slave mengalami kegagalan/darurat. Selesaikan kendala Slave lalu tekan tombol RESUME.");
   }
}

void SendCommandToSlave(string cmd)
{
   int file_handle = FileOpen(m_cmd_to_slave, FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle != INVALID_HANDLE)
   {
      FileWriteLong(file_handle, 0x4248434D); // "BHCM" command magic
      FileWriteLong(file_handle, (long)AccountInfoInteger(ACCOUNT_LOGIN)); // Tag with Master's Unique Account Login
      int clen = StringLen(cmd);
      FileWriteInteger(file_handle, clen);
      if(clen > 0) FileWriteString(file_handle, cmd, clen);
      FileFlush(file_handle);
      FileClose(file_handle);
   }
}

//+------------------------------------------------------------------+
//| Draw On-Screen Dashboard                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int    total_positions = 0;
   double total_profit    = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsMasterPosition(ticket))
      {
         total_positions++;
         total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
      }
   }

   double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   double ref_bal       = GetReferenceBalance();
   double effective_lot = GetEffectiveLot(ref_bal);
   double base_tp       = GetBaseTPAmount(ref_bal);
   m_spread_buffer      = GetEffectiveSpreadBuffer();
   double eff_target_tp = (base_tp > 0) ? (base_tp + m_spread_buffer) : 0.0;
   double comb_profit   = total_profit + (m_slave_online ? m_slave_profit : 0.0);

   string slave_info = m_slave_online ?
      ("Login: " + IntegerToString(m_slave_login) + " | Free: $" + DoubleToString(m_slave_free_margin, 2) + " (" + DoubleToString(m_slave_margin_level, 1) + "%) | Spread: " + IntegerToString(m_slave_spread) + "pts") :
      "OFFLINE / Not Connected";

   string status_str = "⏳ IDLE - Waiting";
   if(InpCloseAll)
   {
      status_str = "🛑 INTERVENSI MANUAL: InpCloseAll=TRUE (Kembalikan ke false di F7)";
      DeleteManualCloseButton();
      CreateResumeButton();
   }
   else if(TimeCurrent() < m_circuit_breaker_until)
   {
      int remain_sec = (int)(m_circuit_breaker_until - TimeCurrent());
      status_str = "🛑 CIRCUIT BREAKER LOCK (" + IntegerToString(remain_sec) + "s) - " + m_circuit_breaker_reason;
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_cycle_paused && total_positions == 0)
   {
      status_str = "⏸️ PAUSED AFTER CYCLE: Siklus Selesai! Bot Dijeda (Siap Update/Setting)";
      DeleteManualCloseButton();
      CreateResumeButton();
   }
   else if(total_positions > 0)
   {
      status_str = "✅ GRID ACTIVE (SYNC 50ms) - Floating: " + (comb_profit >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(comb_profit), 2);
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      CreateManualCloseButton();
   }
   else if(IsBurnerModeActive())
   {
      status_str = "🔥 BONUS BURNER AKTIF: Menguras Sisa Bonus Slave (Eq: $" + DoubleToString(m_slave_equity, 2) + " | Lot: " + DoubleToString(GetEffectiveLot(0), 2) + "L)";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < InpMinFreeMargin || (AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) > 0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < m_min_margin_level))
   {
      status_str = "⚠️ PAUSED: Master Margin Rendah ($" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ") - Harap Rebalance!";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_slave_online && m_slave_equity <= 0.0 && m_slave_credit <= 0.0)
   {
      status_str = "⏳ STANDBY: Akun Slave Kosong (Equity $0 | Credit $0) - Menunggu Deposit/Bonus!";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_slave_online && m_slave_credit < 40.0 && m_slave_balance <= 0.0)
   {
      status_str = "⏳ STANDBY: Menunggu Bonus Broker Masuk di Slave (Deposit: $" + DoubleToString(m_slave_balance, 2) + " | Credit: $" + DoubleToString(m_slave_credit, 2) + ")";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_slave_online && m_slave_credit < 100.0 && m_slave_equity >= 100.0)
   {
      status_str = "⏳ PAUSED: Menunggu Bonus Broker Masuk di Slave (Deposit: $" + DoubleToString(m_slave_balance, 2) + " | Credit: $" + DoubleToString(m_slave_credit, 2) + ")";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_slave_online && !IsBurnerModeActive() && ((m_slave_equity > 0.0 ? m_slave_equity : m_slave_balance) < 100.0))
   {
      status_str = "⚠️ PAUSED: Slave Margin/Equity Habis ($" + DoubleToString(m_slave_equity, 2) + ") - Harap Reset/Deposit!";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_slave_online && !IsBurnerModeActive() && (m_slave_free_margin < InpMinFreeMargin || (m_slave_margin_level > 0 && m_slave_margin_level < m_min_margin_level)))
   {
      status_str = "⚠️ PAUSED: Slave Margin Kritis (Free: $" + DoubleToString(m_slave_free_margin, 2) + ", Lvl: " + DoubleToString(m_slave_margin_level, 1) + "%) - Proteksi Margin Aktif!";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else if(m_slave_trade_blocked)
   {
      status_str = "🚫 SLAVE TRADE-BLOCKED: Algo Slave OFF / CB aktif - Grid DITAHAN (proteksi FOMC)";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }
   else
   {
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      DeleteManualCloseButton();
   }

   long cur_spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   long slave_sp   = (m_slave_online && m_slave_spread > 0) ? m_slave_spread : 0;
   long worst_sp   = MathMax(cur_spread, slave_sp);
   string sp_details = "(M:" + IntegerToString(cur_spread) + " | S:" + IntegerToString(slave_sp) + "pts)";

   string shield_info = "NORMAL " + sp_details;
   if(worst_sp > (long)InpMaxSpreadPoints)
      shield_info = "🛡️ SPREAD-LOCK " + sp_details + " > " + IntegerToString((long)InpMaxSpreadPoints) + "pts";
   else if(TimeCurrent() < m_spike_cooldown_until)
      shield_info = "🚨 SPIKE COOLDOWN (" + IntegerToString((int)(m_spike_cooldown_until - TimeCurrent())) + "s)";
   else if(IsHighImpactNewsNearby())
      shield_info = "📰 NEWS PAUSE (" + m_news_title + ")";

   double slave_lot_est = MathRound(effective_lot * InpSlaveMultiplier * 100.0) / 100.0;
   double init_cap      = GetInitialTotalCapital();

   string text = "\n" +
      "  ╔════════════════════════════════════════════════════════════════╗\n" +
      "  ║   ⚡ DUAL-MT5 BONUS HEDGING - MASTER ENGINE v1.34             ║\n" +
      "  ╠════════════════════════════════════════════════════════════════╣\n" +
      "    Pair Group ID   : #" + IntegerToString(InpPairID) + " (Magic: " + IntegerToString(m_magic) + ")\n" +
      "    Bridge Files    : " + m_master_file + " <-> " + m_slave_file + "\n" +
      "    Symbol          : " + m_symbol + "\n" +
      "    Account Login   : " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n" +
      "    Balance / Equity: $" + DoubleToString(balance, 2) + " / $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n" +
      "    Effective Lot   : " + DoubleToString(effective_lot, 2) + "L " + (InpAutoLotFromBalance ? ("(Tier $" + DoubleToString(init_cap, 0) + " Fix)") : "(Manual)") + " | Slave: " + DoubleToString(slave_lot_est, 2) + "L (x" + DoubleToString(InpSlaveMultiplier, 2) + ")\n" +
      "    Free Margin     : $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + " (" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 1) + "%)\n" +
      "    Active Layers   : " + IntegerToString(total_positions) + " / " + IntegerToString(InpMaxLayers) + "\n" +
      "    Master Floating : $" + DoubleToString(total_profit, 2) + "\n" +
      "    Net Combined P/L: $" + (comb_profit >= 0 ? "+" : "") + DoubleToString(comb_profit, 2) + "\n" +
      "    Target Basket TP: $" + DoubleToString(eff_target_tp, 2) + " (" + (InpBasketTPDollars > 0.0 ? ("$" + DoubleToString(InpBasketTPDollars, 2)) : (DoubleToString(InpTargetProfitPct, 1) + "% dari $" + DoubleToString(init_cap, 0) + " = $" + DoubleToString(base_tp, 2))) + " + Buffer $" + DoubleToString(m_spread_buffer, 2) + ")\n" +
      "    News/Spread     : " + shield_info + "\n" +
      "  ────────────────────────────────────────────────────────────────\n" +
      "    🔗 SLAVE TELEMETRY: " + slave_info + "\n" +
      "    Status          : " + status_str + "\n" +
      "  ╚════════════════════════════════════════════════════════════════╝\n";

   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrYellow);
   Comment(text);

   // Periodic Telegram Snapshot
   if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
   {
      if(TimeCurrent() - m_last_telegram_time >= InpTelegramIntervalMin * 60)
      {
         // Build Master position details
         string master_pos_details = "";
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong t = PositionGetTicket(i);
            if(IsMasterPosition(t))
            {
               double p_prof = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
               string p_sign = (p_prof >= 0) ? "+$" : "-$";
               string p_type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) ? "SELL" : "BUY";
               master_pos_details += "   └ #" + IntegerToString(t) + " " + p_type + " " + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + "L @ " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 2) + " (" + p_sign + DoubleToString(MathAbs(p_prof), 2) + ")\n";
            }
         }
         if(master_pos_details == "") master_pos_details = "   └ (Tidak ada posisi aktif)\n";

         // Build Slave position details
         string slave_pos_details = "";
         for(int i = 0; i < m_slave_pos_count; i++)
         {
            string s_type = (m_slave_positions[i].type == 1) ? "SELL" : "BUY";
            string s_sign = (m_slave_positions[i].profit >= 0) ? "+$" : "-$";
            slave_pos_details += "   └ #" + IntegerToString(m_slave_positions[i].ticket) + " " + s_type + " " + DoubleToString(m_slave_positions[i].volume, 2) + "L @ " + DoubleToString(m_slave_positions[i].price_open, 2) + " (" + s_sign + DoubleToString(MathAbs(m_slave_positions[i].profit), 2) + ")\n";
         }
         if(slave_pos_details == "") slave_pos_details = "   └ (Tidak ada posisi aktif)\n";

         double net_fl = total_profit + (m_slave_online ? m_slave_profit : 0.0);
         string sign = (net_fl >= 0) ? "+$" : "-$";

         string msg = "📊 <b>[LIVE DUAL-MT5 BONUS HEDGING]</b>\n" +
            "────────────────────────────\n" +
            "👑 <b>MASTER (" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ")</b>:\n" +
            "   • Equity / Bal : $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + " / $" + DoubleToString(balance, 2) + "\n" +
            "   • Margin Level : " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 1) + "% (Free: $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ")\n" +
            "   • Floating : $" + DoubleToString(total_profit, 2) + " (" + IntegerToString(total_positions) + " Layers)\n" +
            master_pos_details + "\n" +
            "🛡️ <b>SLAVE (" + IntegerToString(m_slave_login) + " - Bonus 20%)</b>:\n" +
            "   • Equity / Bal : $" + DoubleToString(m_slave_equity, 2) + " / $" + DoubleToString(m_slave_balance, 2) + "\n" +
            "   • Margin Level : " + DoubleToString(m_slave_margin_level, 1) + "% (Free: $" + DoubleToString(m_slave_free_margin, 2) + ")\n" +
            "   • Floating : $" + DoubleToString(m_slave_profit, 2) + " (" + IntegerToString(m_slave_pos_count) + " Hedges)\n" +
            slave_pos_details +
            "────────────────────────────\n" +
            "🎯 <b>NET COMBINED : " + sign + DoubleToString(MathAbs(net_fl), 2) + "</b>\n" +
            "🎯 <b>TARGET PLUS : +$" + DoubleToString(eff_target_tp, 2) + "</b>";

         SendTelegramMessage(msg);
      }
   }
}

//+------------------------------------------------------------------+
//| URL Encode Helper                                                |
//+------------------------------------------------------------------+
string UrlEncode(string text)
{
   string result = "";
   uchar bytes[];
   StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   int len = ArraySize(bytes) - 1; // exclude null terminator

   for(int i = 0; i < len; i++)
   {
      uchar c = bytes[i];
      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~')
      {
         result += CharToString(c);
      }
      else if(c == ' ')
      {
         result += "+";
      }
      else
      {
         result += StringFormat("%%%02X", c);
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Helper: Send Message to Telegram API via HTTP POST               |
//+------------------------------------------------------------------+
void SendTelegramMessage(string raw_message)
{
   if(!InpEnableTelegram || StringLen(InpTelegramBotToken) == 0 || StringLen(InpTelegramChatID) == 0) return;

   string url     = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string payload = "chat_id=" + InpTelegramChatID + "&parse_mode=HTML&text=" + UrlEncode(raw_message);

   char post_data[], result[];
   string result_headers;
   StringToCharArray(payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post_data, ArraySize(post_data) - 1); // remove null terminator

   ResetLastError();
   int http_code = WebRequest("POST", url, headers, 1000, post_data, result, result_headers);

   m_last_telegram_time = TimeCurrent(); // Update timestamp immediately to prevent tight retry loops

   if(http_code == 200)
   {
      Print("📱 [TELEGRAM SUCCESS] Laporan status berhasil terkirim ke Telegram!");
   }
   else
   {
      int err = GetLastError();
      Print("⚠️ [TELEGRAM FAILED] HTTP Code: ", http_code, " | Error Code: ", err);
      if(err == 4014)
      {
         Print("👉 Solusi: Buka MT5 Tools -> Options -> Expert Advisors -> Centang 'Allow WebRequest' dan tambahkan 'https://api.telegram.org'");
         // Mute telegram for 1 minute so it doesn't spam logs or block timer
         m_last_telegram_time = TimeCurrent() + 60;
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Calculate Realized Profit from MT5 Closed Deal History   |
//+------------------------------------------------------------------+
double GetRealizedProfit(datetime from_time)
{
   if(!HistorySelect(from_time, TimeCurrent())) return 0.0;
   int total_deals = HistoryDealsTotal();
   double sum_profit = 0.0;
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
         {
            long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
            {
               sum_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                           + HistoryDealGetDouble(ticket, DEAL_SWAP)
                           + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            }
         }
      }
   }
   return sum_profit;
}

//+------------------------------------------------------------------+
//| Helper: Stream Real-Time JSON Telemetry to Cloud Web API         |
//+------------------------------------------------------------------+
void SendWebTelemetry()
{
   if(!InpEnableWebDashboard || StringLen(InpWebDashboardUrl) == 0) return;
   if(TimeLocal() - m_last_web_time < InpWebIntervalSec) return;
   m_last_web_time = TimeLocal();

   int total_positions = 0;
   double total_profit = 0.0;
   string pairs_json = "";

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsMasterPosition(ticket))
      {
         total_positions++;
         double p_prof = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         total_profit += p_prof;

         // Find matching slave position
         string slave_prefix = (InpPairID <= 1) ? "CT#" : ("CT" + IntegerToString(InpPairID) + "#");
         string expected_comment = slave_prefix + IntegerToString(ticket);
         int s_idx = -1;
         for(int s = 0; s < m_slave_pos_count; s++)
         {
            if(StringFind(m_slave_positions[s].comment, expected_comment) >= 0)
            {
               s_idx = s;
               break;
            }
         }

         double s_prof = (s_idx >= 0) ? m_slave_positions[s_idx].profit : 0.0;
         double net_p  = p_prof + s_prof;
         ulong  s_t    = (s_idx >= 0) ? m_slave_positions[s_idx].ticket : 0;
         double s_v    = (s_idx >= 0) ? m_slave_positions[s_idx].volume : 0.0;
         double s_p    = (s_idx >= 0) ? m_slave_positions[s_idx].price_open : 0.0;

         if(pairs_json != "") pairs_json += ",";
         pairs_json += "{\"master_ticket\":" + IntegerToString(ticket) +
                       ",\"master_type\":\"" + ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) ? "SELL" : "BUY") + "\"" +
                       ",\"master_vol\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) +
                       ",\"master_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 2) +
                       ",\"master_profit\":" + DoubleToString(p_prof, 2) +
                       ",\"slave_ticket\":" + IntegerToString(s_t) +
                       ",\"slave_type\":\"" + ((s_idx >= 0 && m_slave_positions[s_idx].type == 1) ? "SELL" : "BUY") + "\"" +
                       ",\"slave_vol\":" + DoubleToString(s_v, 2) +
                       ",\"slave_price\":" + DoubleToString(s_p, 2) +
                       ",\"slave_profit\":" + DoubleToString(s_prof, 2) +
                       ",\"net_profit\":" + DoubleToString(net_p, 2) + "}";
      }
   }

   double balance          = AccountInfoDouble(ACCOUNT_BALANCE);
   double ref_bal          = GetReferenceBalance();
   double net_fl           = total_profit + (m_slave_online ? m_slave_profit : 0.0);
   double base_tp_calc     = GetBaseTPAmount(ref_bal);
   double eff_telemetry_tp = (base_tp_calc > 0) ? (base_tp_calc + m_spread_buffer) : 0.0;

   long cur_spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   string shield_status = "NORMAL";
   if(cur_spread > (long)InpMaxSpreadPoints) shield_status = "SPREAD_LOCK";
   else if(TimeCurrent() < m_spike_cooldown_until) shield_status = "SPIKE_COOLDOWN";
   else if(IsHighImpactNewsNearby()) shield_status = "NEWS_PAUSE";

   // Calculate real closed deal profits from MT5 History
   datetime t_now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(t_now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime t_today = StructToTime(dt);
   datetime t_week  = t_today - (dt.day_of_week * 86400);
   dt.day = 1;
   datetime t_month = StructToTime(dt);

   double prof_today = GetRealizedProfit(t_today);
   double prof_week  = GetRealizedProfit(t_week);
   double prof_month = GetRealizedProfit(t_month);
   double prof_all   = GetRealizedProfit(0);

   string payload = "{\"login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                    ",\"client_name\":\"" + InpClientName + "\"" +
                    ",\"referral_code\":\"" + InpReferralCode + "\"" +
                    ",\"symbol\":\"" + m_symbol + "\"" +
                    ",\"pair_id\":" + IntegerToString(InpPairID) +
                    ",\"shield_status\":\"" + shield_status + "\"" +
                    ",\"cur_spread\":" + IntegerToString(cur_spread) +
                    ",\"net_floating\":" + DoubleToString(net_fl, 2) +
                    ",\"target_tp\":" + DoubleToString(eff_telemetry_tp, 2) +
                    ",\"profit_today\":" + DoubleToString(prof_today, 2) +
                    ",\"profit_week\":" + DoubleToString(prof_week, 2) +
                    ",\"profit_month\":" + DoubleToString(prof_month, 2) +
                    ",\"profit_all_time\":" + DoubleToString(prof_all, 2) +
                    ",\"master\":{\"login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                                 ",\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
                                 ",\"balance\":" + DoubleToString(balance, 2) +
                                 ",\"free_margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) +
                                 ",\"margin_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) +
                                 ",\"profit\":" + DoubleToString(total_profit, 2) +
                                 ",\"count\":" + IntegerToString(total_positions) + "}" +
                    ",\"slave\":{\"login\":" + IntegerToString(m_slave_login) +
                                ",\"equity\":" + DoubleToString(m_slave_equity, 2) +
                                ",\"balance\":" + DoubleToString(m_slave_balance, 2) +
                                ",\"credit\":" + DoubleToString(m_slave_credit, 2) +
                                ",\"free_margin\":" + DoubleToString(m_slave_free_margin, 2) +
                                ",\"margin_level\":" + DoubleToString(m_slave_margin_level, 2) +
                                ",\"profit\":" + DoubleToString(m_slave_profit, 2) +
                                ",\"count\":" + IntegerToString(m_slave_pos_count) + "}" +
                    ",\"pairs\":[" + pairs_json + "]}";

   string headers = "Content-Type: application/json\r\nBypass-Tunnel-Reminder: true\r\nUser-Agent: MT5-BonusBot\r\n";
   char post_data[], result[];
   string result_headers;
   StringToCharArray(payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post_data, ArraySize(post_data) - 1);

   ResetLastError();
   int http_res = WebRequest("POST", InpWebDashboardUrl, headers, 1000, post_data, result, result_headers);
   if(http_res != 200)
   {
      int err = GetLastError();
      static datetime last_diag_time = 0;
      int alert_interval = (err == 4014) ? 3600 : 60; // Throttled to 1 hour for 4014 whitelist notice
      if(TimeLocal() - last_diag_time >= alert_interval)
      {
         last_diag_time = TimeLocal();
         PrintFormat("⚠️ [WebDashboard] Telemetry failed! HTTP=%d | Error=%d | URL: %s", http_res, err, InpWebDashboardUrl);
         if(err == 4014)
         {
            Print("❌ [WebDashboard] Error 4014: Domain belum di-whitelist di MT5! Buka Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL. (Peringatan ini di-throttle 1x per jam)");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Event Function (Real-Time Broker Execution)    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      long deal_entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      long deal_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
      long deal_magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

      // Jika ada tiket Master ditutup paksa oleh broker (Stop Out / Margin Call):
      if(deal_entry == DEAL_ENTRY_OUT && deal_reason == DEAL_REASON_SO)
      {
         if(deal_magic == (long)m_magic || (InpPairID <= 1 && (deal_magic == 888111 || deal_magic == 888101)) || deal_magic == 0)
         {
            Print("🚨⚡ [MASTER BROKER STOP OUT DETECTED] Tiket Master #", trans.position,
                  " (Deal #", trans.deal, ") TER-STOP OUT BROKER! Mengirim sinyal darurat CLOSE_ALL ke Slave!");
            
            m_closing_active = true;
            m_closing_lock_until = TimeCurrent() + 6;
            SendCommandToSlave("CLOSE_ALL");
            BroadcastMasterState();
            CloseAllMasterPositions();
            m_closing_active = false;
            m_last_order_time = TimeCurrent();
            m_cycle_paused = true;
            CreateResumeButton();
         }
      }
   }
}

