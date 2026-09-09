//+------------------------------------------------------------------+
//|                                           BonusHedge_Master.mq5  |
//|                         All-in-One Dual-MT5 Bonus Hedging Master |
//|                                  Copyright 2026, Advanced Bot EA |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Bot EA"
#property link      "https://www.mql5.com"
#property version   "1.22"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== IDENTITAS PASANGAN TRADING (ANTI-TABRAKAN) ==="
input int      InpPairID            = 1;             // Pair Group ID (1 = Pasangan 1, 2 = Pasangan 2, 3 = Pasangan 3, dst)

input group "=== GRID STRATEGY PARAMETERS ==="
input string   InpSymbol            = "XAUUSD";      // Trading Symbol
input double   InpInitialLot        = 0.10;          // Base Lot Size (e.g. 0.10 or 0.30)
input bool     InpAutoScaleLot      = false;         // Auto-Scale Lot by Balance (false = Fixed Lot)
input double   InpGridStepPoints    = 2000.0;        // Grid Step Points ($20.00 on Gold)
input int      InpMaxLayers         = 3;             // Maximum Grid Layers (Max 3 Positions for Bonus Safety)

input group "=== TAKE PROFIT & SPREAD BUFFER ==="
input double   InpBasketTPDollars   = 31.74;         // Master Basket TP ($ Base per 0.10 Lot)
input double   InpSpreadBufferUSD   = 25.0;          // Flat Spread & Slippage Buffer (USD Flat, Not Multiplied)
input bool     InpPauseAfterCycle   = true;          // Pause Trading After 1 Cycle Closed (For EA Update/Maintenance)
input bool     InpIncludeManualTrades = true;        // Include Manual Positions (Magic 0) in Basket TP & Close

input group "=== MARGIN & CIRCUIT BREAKER PROTECTIONS ==="
input double   InpMinMarginLevel    = 150.0;         // Min Margin Level % (Stop opening if below)
input double   InpMinFreeMargin     = 150.0;         // Min Free Margin $ (Stop opening if below)
input bool     InpHarvestOnSlaveMC  = true;          // Auto Close Master if Slave hits Margin Call/StopOut
input int      InpUnhedgedWatchdogSec = 7;           // Unhedged Watchdog Timeout (Seconds, 0 = Disabled)

input group "=== TELEGRAM LIVE REPORT SETTINGS ==="
input bool     InpEnableTelegram       = true;                    // Enable Telegram Live Alerts
input string   InpTelegramBotToken     = "8841891391:AAFZX-wQSRd2oXOq5Qw52mWAkq_MPxO72_0"; // Telegram Bot Token
input string   InpTelegramChatID       = "164419860";             // Telegram Chat ID
input int      InpTelegramIntervalMin  = 5;                       // Periodic Report Interval (Minutes)

input group "=== CLOUD WEB DASHBOARD SETTINGS ==="
input bool     InpEnableWebDashboard   = false;                               // Enable Live Web Dashboard
input string   InpWebDashboardUrl      = "http://localhost:3000/api/telemetry"; // Cloud Telemetry API URL
input int      InpWebIntervalSec       = 2;                                   // Web Refresh Interval (Seconds)

input group "=== ADVANCED TIMING SETTINGS ==="
input int      InpTimerMS              = 50;                      // Sync Interval in ms

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
double         m_slave_free_margin  = 0.0;
double         m_slave_margin_level = 0.0;
double         m_slave_profit       = 0.0;
int            m_slave_pos_count    = 0;
bool           m_slave_online       = false;
long           m_slave_last_counter = -1;
datetime       m_slave_last_seen    = 0;

//--- Universal Anti-Flapping Circuit Breaker Shield
datetime       m_last_order_open_time   = 0;
datetime       m_last_order_close_time  = 0;
int            m_rapid_close_counter    = 0;
datetime       m_circuit_breaker_until  = 0;
string         m_circuit_breaker_reason = "";
bool           m_naked_alert_sent       = false;
void   ReadSlaveState();
void   CheckIncomingCommands();
bool   CheckSlaveLiquidationHarvest();
void   CheckUnhedgedOrphanWatchdog();
void   ManageGrid();
void   CloseAllMasterPositions();
void   BroadcastMasterState();
void   SendCommandToSlave(string cmd);
void   UpdateDashboard();
string UrlEncode(string text);
void   SendTelegramMessage(string raw_message);
void   SendWebTelemetry();
void   CheckSlaveTimeout();
void   CheckNakedExposureAlert();

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
   Print("🟢 [BonusHedge_Master v1.22] Initialized on ", m_symbol, " (Pair ID: ", InpPairID, ", Magic: ", m_magic, ")");

   // Immediate startup test ping to Telegram
   if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
   {
      SendTelegramMessage("🟢 <b>[DUAL-MT5 BONUS HEDGING v1.22 AKTIF]</b>\n" +
                          "👑 Akun Master: <b>" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "</b>\n" +
                          "📌 Pair ID: <b>#" + IntegerToString(InpPairID) + "</b> (Magic: " + IntegerToString(m_magic) + ")\n" +
                          "📊 Symbol: <b>" + m_symbol + "</b> | Base Lot: <b>" + DoubleToString(InpInitialLot, 2) + "L</b>\n" +
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
   Comment("");
}

//+------------------------------------------------------------------+
//| Chart Event function: Handle Click on RESUME button              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "BTN_RESUME_CYCLE")
   {
      m_cycle_paused = false;
      ObjectDelete(0, "BTN_RESUME_CYCLE");
      ChartRedraw(0);
      Print("▶️ [USER ACTION] Bot di-RESUME oleh user! Siap membuka siklus order baru.");
   }
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
   if(ok) { ResetLastError(); new_equity      = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_balance     = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_free_margin = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_margin_lvl  = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
   if(ok) { ResetLastError(); new_profit      = FileReadDouble(file_handle); ok = (GetLastError() == 0); }
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
   if(!ok || new_magic != 0x42484246 || new_version != 2)
   {
      CheckSlaveTimeout();
      return;
   }

   // Heartbeat: counter harus maju; nilai sama = writer berhenti menulis
   if(new_counter == m_slave_last_counter)
   {
      CheckSlaveTimeout();
      return;
   }

   m_slave_last_counter = new_counter;
   m_slave_time         = new_counter;
   m_slave_login        = new_login;
   m_slave_equity       = new_equity;
   m_slave_balance      = new_balance;
   m_slave_free_margin  = new_free_margin;
   m_slave_margin_level = new_margin_lvl;
   m_slave_profit       = new_profit;
   m_slave_pos_count    = new_pos_count;
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
      if(ticket > 0
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
         && (PositionGetInteger(POSITION_MAGIC) == (long)m_magic || (InpIncludeManualTrades && PositionGetInteger(POSITION_MAGIC) == 0)))
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
   // GENUINE LIQUIDATION HARVEST:
   // Jangan gunakan ambang Margin Level < 20%! Pada akumulasi 3-4 layer (lot besar), ML 20% terjadi saat
   // Equity masih tersisa $100-$150, sehingga bot menutup terlalu dini sebelum bonus broker terbakar habis!
   // Panen hanya boleh dipicu jika Equity Slave benar-benar menyentuh sisa terakhir (<= $10.0) atau sudah minus.
   bool is_slave_liquidated = (m_slave_login > 0 && m_slave_equity <= 10.0);

   if(is_slave_liquidated)
   {
      s_slave_mc_counter++;
      if(s_slave_mc_counter >= 3) // 3 siklus konfirmasi berturut-turut (150ms)
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
         m_cycle_paused = true;
         CreateResumeButton();
         Print("🛑 [HARVEST LOCKDOWN] Slave terbakar & Master berhasil panen profit! Bot Master DIKUNCI PAUSE permanen untuk mencegah re-entry.");
         if(InpEnableTelegram && StringLen(InpTelegramBotToken) > 0 && StringLen(InpTelegramChatID) > 0)
         {
            SendTelegramMessage("🛑 <b>[SLAVE TERBAKAR & MASTER PANEN SELESAI]</b>\n" +
                                "────────────────────────────\n" +
                                "💰 Akun Master #" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " berhasil menutup posisi dan mengunci profit kas!\n" +
                                "🔒 <b>Bot di-PAUSE secara permanen.</b>\n" +
                                "👉 Silakan reset deposit Slave #" + IntegerToString(m_slave_login) + " lalu tekan tombol <b>RESUME</b> di chart untuk memulai siklus baru.\n" +
                                "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
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
//| UNHEDGED ORPHAN WATCHDOG                                         |
//| Closes any Master position left unhedged by Slave for > 15s      |
//+------------------------------------------------------------------+
void CheckUnhedgedOrphanWatchdog()
{
   if(InpUnhedgedWatchdogSec <= 0) return;
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

   // Jika Master memiliki posisi lebih banyak daripada yang berhasil di-hedge oleh Slave
   if(master_count > 0 && master_count > m_slave_pos_count)
   {
      if(s_unhedged_start_tick == 0)
      {
         s_unhedged_start_tick = GetTickCount64();
      }
      else if(GetTickCount64() - s_unhedged_start_tick > (ulong)(InpUnhedgedWatchdogSec * 1000))
      {
         Print("🚨 [UNHEDGED WATCHDOG TRIGGERED] Master memiliki ", master_count, " posisi tapi Slave hanya meng-hedge ",
               m_slave_pos_count, " posisi selama > ", InpUnhedgedWatchdogSec, " detik! Menutup posisi unhedged demi keselamatan modal!");
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
                                "⚠️ Ditemukan posisi Master yang tidak di-hedge oleh Slave selama > " + IntegerToString(InpUnhedgedWatchdogSec) + " detik.\n" +
                                "🛡️ <b>Posisi Master ditutup otomatis demi keselamatan modal!</b>\n" +
                                "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
         }
      }
   }
   else
   {
      s_unhedged_start_tick = 0;
   }
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
      if(ticket > 0
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
         && (PositionGetInteger(POSITION_MAGIC) == (long)m_magic || (InpIncludeManualTrades && PositionGetInteger(POSITION_MAGIC) == 0)))
      {
         total_positions++;
         if(PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
            ea_positions++;
         total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
         if(open_p < min_price) min_price = open_p;
         if(open_p > max_price) max_price = open_p;
      }
   }

   double effective_lot = InpInitialLot;

   // FLAT SPREAD & SLIPPAGE BUFFER (v1.22):
   // Buffer dibuat FLAT (InpSpreadBufferUSD) dan TIDAK dikalikan jumlah layer,
   // sehingga target TP tetap stabil, lincah, dan cepat tercapai (seperti sistem pool / quick-basket),
   // namun tetap melindungi seluruh biaya spread XAUUSD secara penuh dan aman dari spike.
   double base_tp_amount = 0.0;
   if(InpBasketTPDollars > 0)
   {
      if(InpBasketTPDollars == 31.74)
         base_tp_amount = (InpInitialLot / 0.10) * 31.74;
      else
         base_tp_amount = InpBasketTPDollars; // Use custom if user explicitly typed a custom amount
   }

   double effective_basket_tp = (base_tp_amount > 0) ? (base_tp_amount + InpSpreadBufferUSD) : 0.0;

   // --- CHECK COMBINED NET PROFIT (MASTER + SLAVE GABUNGAN PLUS) ---
   // Wajib gabungan Master + Slave terkonfirmasi ONLINE agar 100% meng-cover semua spread dan komisi!
   // DILARANG KERAS menutup TP jika Slave belum terverifikasi online (mencegah false trigger profit sepihak)!
   if(!m_slave_online)
   {
      // Slave belum online: JANGAN buka posisi sendirian & jangan tutup TP sepihak!
      return;
   }

   double combined_net_profit = total_profit + m_slave_profit;

   if(total_positions > 0 && m_slave_pos_count > 0 && effective_basket_tp > 0 && combined_net_profit >= effective_basket_tp)
   {
      Print("🎉 [COMBINED NET TP TRIGGERED] Total Gabungan (Master: $", DoubleToString(total_profit, 2),
            " + Slave: $", DoubleToString(m_slave_profit, 2), ") = $", DoubleToString(combined_net_profit, 2),
            " >= Target $", DoubleToString(effective_basket_tp, 2), " (Base $", DoubleToString(base_tp_amount, 2),
            " + Flat Buffer $", DoubleToString(InpSpreadBufferUSD, 2), " Ter-Cover!)");
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 6; // 6-second closing lock
      
      // PARALLEL ATOMIC CLOSE DISPATCH:
      // Kirim sinyal tutup ke Slave LEBIH DULU agar kedua terminal MT5 menutup order di milidetik yang sama!
      // Menghilangkan jeda 1-2 detik yang menyebabkan slippage saat spike harga emas.
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

   // 1. Do not open if Master's own margin is critical
   if(my_free_margin < InpMinFreeMargin || (my_margin_level > 0 && my_margin_level < InpMinMarginLevel))
   {
      return; // Hold off, margin critical
   }

   // 2. Do not open if Slave's margin is critical or Slave cannot afford new hedge (Checks Layer 1 & Grid!)
   if(m_slave_online)
   {
      if(m_slave_balance <= 0.0 || m_slave_equity < 100.0 || m_slave_free_margin < InpMinFreeMargin || (m_slave_margin_level > 0 && m_slave_margin_level < InpMinMarginLevel))
      {
         // Slave kehabisan saldo/balance minus (butuh Rebalance/Deposit dari Master): JANGAN BUKA ORDER APAPUN!
         return;
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

   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick) || tick.bid <= 0) return;

   // --- LAYER 1 (INITIAL ORDER) ---
   if(total_positions == 0)
   {
      m_last_order_time = TimeCurrent(); // Update cooldown immediately to prevent rapid-fire loops
      m_last_order_open_time = TimeCurrent();
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

      // SAFETY CHECK 2: Jangan buka Layer baru jika profit gabungan saat ini sudah positif tebal (>= 60% dari Target TP),
      // agar tidak membuka posisi baru di pucuk/lembah sesaat sebelum Take Profit tercapai!
      if(effective_basket_tp > 0 && combined_net_profit >= (effective_basket_tp * 0.60))
      {
         return; // Keranjang sudah dekat target TP, biarkan posisi yang ada menyelesaikan TP!
      }

      double step_distance = InpGridStepPoints * m_point;
      bool should_open = false;

      if(min_price < DBL_MAX)
      {
         // BI-DIRECTIONAL BONUS EXTRACTION GRID:
         // 1. Buka Layer saat harga NAIK -> Panen TP Gabungan (+0.01 lot delta asimetris)
         if((tick.bid - max_price) >= step_distance) should_open = true;

         // 2. Buka Layer saat harga TURUN -> HANYA JIKA MARGIN SLAVE MASIH SEHAT!
         // Jika Slave sudah mendekati MC, DILARANG MENAMBAH LAYER KE BAWAH agar delta lot tidak menumpuk!
         if((min_price - tick.bid) >= step_distance)
         {
            if(m_slave_online && ((m_slave_margin_level > 0 && m_slave_margin_level < InpMinMarginLevel) || m_slave_free_margin < 200.0))
            {
               Print("⚠️ [DOWNWARD GRID SHIELD] Slave margin tertekan (ML: ", DoubleToString(m_slave_margin_level, 1),
                     "%, Free: $", DoubleToString(m_slave_free_margin, 2), ")! Menahan penambahan layer bawah.");
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
         && (PositionGetInteger(POSITION_MAGIC) == (long)m_magic || (InpIncludeManualTrades && PositionGetInteger(POSITION_MAGIC) == 0)))
      {
         if(m_trade.PositionClose(ticket)) closed_count++;
      }
   }

   if(closed_count > 0)
   {
      m_last_order_close_time = TimeCurrent();
      int lifespan = (m_last_order_open_time > 0) ? (int)(TimeCurrent() - m_last_order_open_time) : 999;

      // SHIELD: Jika posisi hidup kurang dari 20 detik (abnormal rapid close / flapping):
      if(m_last_order_open_time > 0 && lifespan <= 20)
      {
         m_rapid_close_counter++;
         Print("⚠️ [ANTI-FLAPPING MONITOR] Terdeteksi buka-tutup kilat (Umur: ", lifespan, "s). Counter: ", m_rapid_close_counter);

         // Jika terdeteksi 2x buka-tutup kilat abnormal: KUNCI MATI SELAMA 5 MENIT!
         if(m_rapid_close_counter >= 2)
         {
            m_circuit_breaker_until = TimeCurrent() + 300; // 5 Menit Lockout
            m_circuit_breaker_reason = "Terdeteksi 2x Buka-Tutup Kilat Abnormal (<20s)";
            Print("🚨 [CIRCUIT BREAKER ACTIVATED] Bot dikunci PAUSE selama 5 menit untuk melindungi modal!");
            if(InpEnableTelegram)
            {
               SendTelegramMessage("🚨 <b>[CIRCUIT BREAKER SHIELD DIAKTIFKAN]</b>\n" +
                                   "────────────────────────────\n" +
                                   "⚠️ Terdeteksi 2x buka-tutup cepat abnormal dalam hitungan detik.\n" +
                                   "🛑 <b>Trading DIKUNCI PAUSE selama 5 Menit</b> untuk melindungi modal Anda dari biaya spread!\n" +
                                   "⏰ <i>" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "</i>");
            }
         }
      }
      else
      {
         m_rapid_close_counter = 0;
      }
   }
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
      if(ticket > 0
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
         && (PositionGetInteger(POSITION_MAGIC) == (long)m_magic || (InpIncludeManualTrades && PositionGetInteger(POSITION_MAGIC) == 0)))
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

   FileFlush(file_handle);
   FileClose(file_handle);
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
      if(ticket > 0
         && PositionGetString(POSITION_SYMBOL) == m_symbol
         && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
      {
         total_positions++;
         total_profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double base_tp = (InpBasketTPDollars == 31.74) ? ((InpInitialLot / 0.10) * 31.74) : InpBasketTPDollars;
   if(InpAutoScaleLot) base_tp = (balance / 1000.0) * InpBasketTPDollars;
   double eff_target_tp = (base_tp > 0) ? (base_tp + InpSpreadBufferUSD) : 0.0;
   double comb_profit = total_profit + (m_slave_online ? m_slave_profit : 0.0);

   string slave_info = m_slave_online ?
      ("Login: " + IntegerToString(m_slave_login) + " | Free: $" + DoubleToString(m_slave_free_margin, 2) + " (" + DoubleToString(m_slave_margin_level, 1) + "%)") :
      "OFFLINE / Not Connected";

   string status_str = "⏳ IDLE - Waiting";
   if(TimeCurrent() < m_circuit_breaker_until)
   {
      int remain_sec = (int)(m_circuit_breaker_until - TimeCurrent());
      status_str = "🛑 CIRCUIT BREAKER LOCK (" + IntegerToString(remain_sec) + "s) - " + m_circuit_breaker_reason;
      ObjectDelete(0, "BTN_RESUME_CYCLE");
   }
   else if(m_cycle_paused && total_positions == 0)
   {
      status_str = "⏸️ PAUSED AFTER CYCLE: Siklus Selesai! Bot Dijeda (Siap Update/Setting)";
      CreateResumeButton();
   }
   else if(total_positions > 0)
   {
      status_str = "✅ GRID ACTIVE (SYNC 50ms)";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
   }
   else if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < InpMinFreeMargin || (AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) > 0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < InpMinMarginLevel))
   {
      status_str = "⚠️ PAUSED: Master Margin Rendah ($" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ") - Harap Rebalance!";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
   }
   else if(m_slave_online && (m_slave_balance <= 0.0 || m_slave_equity < 100.0 || m_slave_free_margin < InpMinFreeMargin || (m_slave_margin_level > 0 && m_slave_margin_level < InpMinMarginLevel)))
   {
      status_str = "⚠️ PAUSED: Slave Saldo/Balance Minus (Bal: $" + DoubleToString(m_slave_balance, 2) + ", Eq: $" + DoubleToString(m_slave_equity, 2) + ") - Harap Reset/Deposit!";
      ObjectDelete(0, "BTN_RESUME_CYCLE");
   }
   else
   {
      ObjectDelete(0, "BTN_RESUME_CYCLE");
   }

   string text = "\n" +
      "  ╔════════════════════════════════════════════════════════════════╗\n" +
      "  ║   ⚡ DUAL-MT5 BONUS HEDGING - MASTER ENGINE v1.22             ║\n" +
      "  ╠════════════════════════════════════════════════════════════════╣\n" +
      "    Pair Group ID   : #" + IntegerToString(InpPairID) + " (Magic: " + IntegerToString(m_magic) + ")\n" +
      "    Bridge Files    : " + m_master_file + " <-> " + m_slave_file + "\n" +
      "    Symbol          : " + m_symbol + "\n" +
      "    Account Login   : " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n" +
      "    Balance / Equity: $" + DoubleToString(balance, 2) + " / $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n" +
      "    Free Margin     : $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + " (" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 1) + "%)\n" +
      "    Active Layers   : " + IntegerToString(total_positions) + " / " + IntegerToString(InpMaxLayers) + "\n" +
      "    Master Floating : $" + DoubleToString(total_profit, 2) + "\n" +
      "    Net Combined P/L: $" + (comb_profit >= 0 ? "+" : "") + DoubleToString(comb_profit, 2) + "\n" +
      "    Target Basket TP: $" + DoubleToString(eff_target_tp, 2) + " (Base $" + DoubleToString(base_tp, 2) + " + Flat Buffer $" + DoubleToString(InpSpreadBufferUSD, 2) + ")\n" +
      "  ────────────────────────────────────────────────────────────────\n" +
      "    🔗 SLAVE TELEMETRY: " + slave_info + "\n" +
      "    Status          : " + status_str + "\n" +
      "  ╚════════════════════════════════════════════════════════════════╝\n";

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
            if(t > 0 && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0) && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
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
//| Helper: Stream Real-Time JSON Telemetry to Cloud Web API         |
//+------------------------------------------------------------------+
void SendWebTelemetry()
{
   if(!InpEnableWebDashboard || StringLen(InpWebDashboardUrl) == 0) return;
   if(TimeCurrent() - m_last_web_time < InpWebIntervalSec) return;
   m_last_web_time = TimeCurrent();

   int total_positions = 0;
   double total_profit = 0.0;
   string pairs_json = "";

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
         && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
      {
         total_positions++;
         double p_prof = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         total_profit += p_prof;

         // Find matching slave position
         string expected_comment = "CT#" + IntegerToString(ticket);
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

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double net_fl  = total_profit + (m_slave_online ? m_slave_profit : 0.0);
   double base_tp_calc = (InpBasketTPDollars == 31.74) ? ((InpInitialLot / 0.10) * 31.74) : InpBasketTPDollars;
   if(InpAutoScaleLot) base_tp_calc = (balance / 1000.0) * InpBasketTPDollars;
   double eff_telemetry_tp = (base_tp_calc > 0) ? (base_tp_calc + InpSpreadBufferUSD) : 0.0;

   string payload = "{\"login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                    ",\"symbol\":\"" + m_symbol + "\"" +
                    ",\"net_floating\":" + DoubleToString(net_fl, 2) +
                    ",\"target_tp\":" + DoubleToString(eff_telemetry_tp, 2) +
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
                                ",\"free_margin\":" + DoubleToString(m_slave_free_margin, 2) +
                                ",\"margin_level\":" + DoubleToString(m_slave_margin_level, 2) +
                                ",\"profit\":" + DoubleToString(m_slave_profit, 2) +
                                ",\"count\":" + IntegerToString(m_slave_pos_count) + "}" +
                    ",\"pairs\":[" + pairs_json + "]}";

   string headers = "Content-Type: application/json\r\n";
   char post_data[], result[];
   string result_headers;
   StringToCharArray(payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post_data, ArraySize(post_data) - 1);

   ResetLastError();
   WebRequest("POST", InpWebDashboardUrl, headers, 1000, post_data, result, result_headers);
}

