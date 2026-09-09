//+------------------------------------------------------------------+
//|                                            BonusHedge_Slave.mq5  |
//|                          All-in-One Dual-MT5 Bonus Hedger Slave  |
//|                                  Copyright 2026, Advanced Bot EA |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Advanced Bot EA"
#property link      "https://www.mql5.com"
#property version   "1.22"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== IDENTITAS PASANGAN TRADING (ANTI-TABRAKAN) ==="
input int      InpPairID            = 1;             // Pair Group ID (Samakan dengan Master: 1, 2, 3, dst)

input group "=== SLAVE HEDGING PARAMETERS ==="
input string   InpSymbol            = "XAUUSD";      // Trading Symbol
input double   InpLotMultiplier     = 1.10;          // Lot Multiplier (e.g. 0.15 Master -> 0.17 Slave)
input int      InpSlippage          = 50;            // Slippage Points
input double   InpMinBonusCredit    = 100.0;         // Min Bonus Credit $ Required to Start (0 = Disabled)
input bool     InpHarvestOnMasterMC = true;          // Auto Close Slave if Master hits Margin Call/StopOut

input group "=== ADVANCED TIMING SETTINGS ==="
input int      InpTimerMS           = 50;            // Sync Interval in ms

//--- Resolved Runtime Variables (Generated Automatically from InpPairID)
ulong          m_magic              = 888991;
string         m_comment_prefix     = "CT#";
string         m_master_file        = "bonus_hedge_master.dat";
string         m_slave_file         = "bonus_hedge_slave.dat";
string         m_cmd_to_slave       = "bonus_cmd_to_slave.dat";
string         m_cmd_to_master      = "bonus_cmd_to_master.dat";

//--- Structure for Master Position
struct SMasterPos
{
   ulong    ticket;
   int      type;       // 0=BUY, 1=SELL
   double   volume;
   double   price_open;
   double   profit;
   string   comment;
};

//--- Global Objects
CTrade         m_trade;
datetime       m_closing_lock_until = 0;
string         m_symbol             = "";
double         m_point              = 0.01;
int            m_digits             = 2;
bool           m_closing_active     = false;

// Anti-Flapping & Circuit Breaker Tracking
datetime       m_last_order_open_time   = 0;
datetime       m_last_order_close_time  = 0;
int            m_rapid_close_counter    = 0;
datetime       m_circuit_breaker_until  = 0;
string         m_circuit_breaker_reason = "";

// Stale-read confirmation tracking (Anti-Jitter)
struct SMissingTicket
{
   ulong ticket;
   int   missing_count;
};
SMissingTicket m_missing_tickets[];

// Master state snapshot
long           m_master_time        = 0;
long           m_master_login       = 0;
double         m_master_equity      = 0.0;
double         m_master_balance     = 0.0;
double         m_master_free_margin = 0.0;
double         m_master_margin_level= 0.0;
double         m_master_profit      = 0.0;
int            m_master_pos_count   = 0;
SMasterPos     m_master_positions[];
bool           m_master_online      = false;
long           m_master_last_counter = -1;
datetime       m_master_last_seen    = 0;
bool           m_comments_lost       = false;  // broker overwrite comment? (mode backstop)

//--- Forward Declarations
void   BroadcastSlaveState();
bool   ReadMasterState();
bool   CheckMasterLiquidationHarvest();
void   SyncOpenPositions();
void   SyncClosePositions();
double GetSlaveTotalProfit();
void   CloseAllSlavePositions();
void   SendCommandToMaster(string cmd);
void   CheckIncomingCommands();
void   UpdateDashboard(double slave_profit, double combined_net_profit);
void   UpdateDashboardOffline();
bool   IsMasterTimedOut();

//+------------------------------------------------------------------+
//| Deteksi: broker menimpa/menghapus comment posisi Slave?           |
//| Jika Slave punya hedge (magic+symbol ini) tapi TIDAK ADA yang     |
//| berkomentar CT#... padahal Master sedang punya posisi -> komentar  |
//| hilang (copy-order service, dst) -> aktifkan mode backstop bucket. |
//+------------------------------------------------------------------+
void DetectCommentLoss()
{
   if(m_master_pos_count == 0) return; // tak bisa menyimpulkan saat master flat
   int mine = 0;
   int tagged = 0;
   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      ulong s_ticket = PositionGetTicket(s);
      if(s_ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magic
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0))
      {
         mine++;
         if(StringFind(PositionGetString(POSITION_COMMENT), m_comment_prefix) == 0)
            tagged++;
      }
   }
   if(mine > 0 && tagged == 0)
   {
      if(!m_comments_lost)
      {
         m_comments_lost = true;
         Print("⚠️ [COMMENT-LOSS MODE] ", mine, " hedge Slave tidak memiliki tag '", m_comment_prefix,
               "' (kemungkinan broker menimpa comment). Beralih ke backstop bucket matching (anti double-hedge).");
      }
   }
   else if(tagged > 0 && m_comments_lost)
   {
      m_comments_lost = false;
      Print("✅ [COMMENT-LOSS MODE OFF] Tag comment terdeteksi lagi — kembali ke pencocokan per-tiket.");
   }
}

void InitPairConfiguration()
{
   int pid = (InpPairID <= 1) ? 1 : InpPairID;
   string suffix = (pid == 1) ? "" : ("_" + IntegerToString(pid));

   m_magic          = 888990 + (ulong)pid; // 888991, 888992, 888993, dst.
   m_comment_prefix = (pid == 1) ? "CT#" : ("CT" + IntegerToString(pid) + "#");
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
   m_trade.SetDeviationInPoints(InpSlippage);
   m_trade.SetTypeFillingBySymbol(m_symbol);

   EventSetMillisecondTimer(InpTimerMS);
   m_last_order_open_time  = TimeCurrent();
   m_last_order_close_time = 0;
   m_rapid_close_counter   = 0;
   m_circuit_breaker_until = 0;
   ArrayResize(m_missing_tickets, 0);

   Print("🟢 [BonusHedge_Slave v1.22] Initialized on ", m_symbol,
         " (Pair ID: #", InpPairID, ", Magic: ", m_magic, ", Mult: ", DoubleToString(InpLotMultiplier, 2), "x)");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   FileDelete(m_slave_file, FILE_COMMON);
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1. Broadcast Slave Telemetry to Master (Two-Way Communication)
   BroadcastSlaveState();

   // 1b. CHECK IF ALGO TRADING IS ALLOWED BY USER IN MT5 (setelah broadcast,
   //     agar Master tetap melihat Slave hidup walau algo sedang OFF)
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Comment("\n  ⚠️ [BonusHedge_Slave] ALGO TRADING IS DISABLED IN MT5!\n" +
              "  Klik tombol 'Algo Trading' di toolbar atas MT5 agar robot bisa bekerja.");
      return;
   }

   // 2. Read Master State from FILE_COMMON
   if(!ReadMasterState())
   {
      // Master is temporarily offline/lagging:
      // IRONCLAD HEDGE SAFETY: JANGAN PERNAH MENUTUP POSISI SLAVE SECARA SEPIHAK!
      // Posisi saat ini sedang mengunci (hedge) Master. Melepaskan kuncian akan membuat Master naked floating!
      // Slave hanya boleh tutup jika: (1) Perintah resmi CLOSE_ALL, atau (2) Master terbukti Liquidation/MC.
      UpdateDashboardOffline();
      return;
   }

   // 2b. Deteksi broker menimpa comment -> mode backstop bucket matching
   DetectCommentLoss();

   // 3. Check for incoming commands from Master (e.g. CLOSE_ALL Take Profit)
   CheckIncomingCommands();

   // 4. Calculate Slave Floating & Combined Net Profit
   double slave_profit        = GetSlaveTotalProfit();
   double combined_net_profit = m_master_profit + slave_profit;

   // 5. Check if Master was liquidated / hit MC -> Harvest Slave Profit immediately!
   if(InpHarvestOnMasterMC && CheckMasterLiquidationHarvest())
      return;

   // 6. Sync Open: Hedge any new Master position on Slave (guarded by closing lock)
   if(!m_closing_active && TimeCurrent() >= m_closing_lock_until)
      SyncOpenPositions();

   // 7. Sync Close: Close Slave position if Master position was closed
   if(!m_closing_active)
      SyncClosePositions();

   // 8. Update Dashboard
   UpdateDashboard(slave_profit, combined_net_profit);
}

//+------------------------------------------------------------------+
//| Broadcast Slave state to Master via FILE_COMMON                  |
//+------------------------------------------------------------------+
void BroadcastSlaveState()
{
   int count = 0;
   double total_prof = 0.0;
   ulong  tickets[];
   int    types[];
   double volumes[], prices[], profits[];
   string comments[];

   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      ulong ticket = PositionGetTicket(s);
      if(ticket > 0 && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0) && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
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

   int file_handle = FileOpen(m_slave_file, FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle == INVALID_HANDLE) return;

   static long s_slave_counter = 0;
   s_slave_counter++;
   FileWriteLong(file_handle, 0x42484246);       // magic "BHBF"
   FileWriteLong(file_handle, 2);                // protocol version
   FileWriteLong(file_handle, s_slave_counter);  // heartbeat counter
   FileWriteLong(file_handle, AccountInfoInteger(ACCOUNT_LOGIN));
   FileWriteDouble(file_handle, AccountInfoDouble(ACCOUNT_EQUITY));
   FileWriteDouble(file_handle, AccountInfoDouble(ACCOUNT_BALANCE));

   double reported_free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double reported_margin_lvl  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(InpMinBonusCredit > 0 && AccountInfoDouble(ACCOUNT_CREDIT) < InpMinBonusCredit)
   {
      reported_free_margin = 0.0; // Sinyal ke Master: Bonus belum masuk!
      reported_margin_lvl  = 0.0;
   }
   FileWriteDouble(file_handle, reported_free_margin);
   FileWriteDouble(file_handle, reported_margin_lvl);
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
//| Read Master state from FILE_COMMON                               |
//| v2 protocol: magic|version|counter|login|equity|balance|free|ml| |
//|              profit|count|positions...                           |
//| Partial/invalid reads KEEP the last good snapshot - offline      |
//| is only declared after 30s of continuous staleness (debounced).  |
//+------------------------------------------------------------------+
bool ReadMasterState()
{
   if(!FileIsExist(m_master_file, FILE_COMMON))
   {
      return IsMasterTimedOut();
   }

   int file_handle = FileOpen(m_master_file, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle == INVALID_HANDLE)
      return IsMasterTimedOut();

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

   if(!ok || new_magic != 0x42484246 || new_version != 2)
      return IsMasterTimedOut();

   if(new_counter == m_master_last_counter)
      return IsMasterTimedOut();

   m_master_last_counter = new_counter;
   m_master_time         = new_counter;
   m_master_login        = new_login;
   m_master_equity       = new_equity;
   m_master_balance      = new_balance;
   m_master_free_margin  = new_free_margin;
   m_master_margin_level = new_margin_lvl;
   m_master_profit       = new_profit;
   m_master_pos_count    = new_pos_count;
   ArrayResize(m_master_positions, new_pos_count);
   for(int i = 0; i < new_pos_count; i++)
   {
      m_master_positions[i].ticket     = t_tickets[i];
      m_master_positions[i].type       = t_types[i];
      m_master_positions[i].volume     = t_volumes[i];
      m_master_positions[i].price_open = t_prices[i];
      m_master_positions[i].profit     = t_profits[i];
      m_master_positions[i].comment    = t_comments[i];
   }
   m_master_last_seen    = TimeLocal();
   m_master_online       = true;
   return true;
}

//+------------------------------------------------------------------+
//| Rate-independent offline detection (120 detik grace period)      |
//+------------------------------------------------------------------+
bool IsMasterTimedOut()
{
   if(m_master_last_seen > 0 && (TimeLocal() - m_master_last_seen <= 120))
      return true; // masih dalam grace: lanjut dengan snapshot terakhir
   m_master_online = false;
   return false;
}

//+------------------------------------------------------------------+
//| Check if Master got closed / stopped out / liquidated            |
//| IRONCLAD SAFETY: Trigger ONLY when Master is genuinely MC/Liquidated|
//| Multi-Cycle Debounce (3 cycles = 150ms) + Supports Equity <= 0   |
//+------------------------------------------------------------------+
bool CheckMasterLiquidationHarvest()
{
   if(!m_master_online || m_closing_active) return false;

   static int s_master_mc_counter = 0;
   // GENUINE LIQUIDATION HARVEST:
   // Panen hanya boleh dipicu jika Equity Master benar-benar menyentuh sisa terakhir (<= $10.0) atau sudah minus.
   bool is_master_liquidated = (m_master_login > 0 && m_master_equity <= 10.0);

   if(is_master_liquidated)
   {
      s_master_mc_counter++;
      if(s_master_mc_counter >= 3) // 3 siklus konfirmasi berturut-turut (150ms)
      {
         Print("🚨 [CRITICAL HEDGE SAFETY] Master account (", m_master_login,
               ") TERKONFIRMASI HABIS / LIQUIDASI (Equity: $", DoubleToString(m_master_equity, 2),
               ")! Menutup semua posisi Slave untuk panen profit!");
         m_closing_active = true;
         m_closing_lock_until = TimeCurrent() + 6;
         CloseAllSlavePositions();
         m_closing_active = false;
         s_master_mc_counter = 0;
         return true;
      }
   }
   else
   {
      s_master_mc_counter = 0;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Sync Open: Open matching reverse positions on Slave              |
//+------------------------------------------------------------------+
void SyncOpenPositions()
{
   if(!m_master_online || m_master_pos_count == 0) return;
   if(TimeCurrent() < m_circuit_breaker_until) return;
   if(TimeCurrent() < m_closing_lock_until) return;
   if(TimeCurrent() - m_last_order_close_time < 10) return; // 10s cooldown after close

   MqlTick tick;
   if(!SymbolInfoTick(m_symbol, tick) || tick.ask <= 0) return;

   // Check if Bonus Credit is officially funded in Slave account
   double my_credit = AccountInfoDouble(ACCOUNT_CREDIT);
   if(InpMinBonusCredit > 0 && my_credit < InpMinBonusCredit)
   {
      return; // Hold off, bonus credit belum masuk
   }

   // SAFETY CAP: Jika jumlah posisi HEDGE Slave sendiri (magic+symbol ini)
   // sudah sama atau melebihi posisi Master, DILARANG membuka hedge baru
   // (mencegah over-hedge). PENTING: tidak boleh pakai PositionsTotal() mentah —
   // posisi manual/EA lain/simbol lain di terminal yang sama akan membuat cap
   // salah tembak dan hedge diblokir selamanya.
   int my_hedge_count = 0;
   for(int c = PositionsTotal() - 1; c >= 0; c--)
   {
      ulong c_ticket = PositionGetTicket(c);
      if(c_ticket > 0
         && PositionGetInteger(POSITION_MAGIC) == (long)m_magic
         && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0))
         my_hedge_count++;
   }
   if(my_hedge_count >= m_master_pos_count)
   {
      return;
   }

   static ulong s_last_hedged_master_ticket = 0;
   static ulong s_last_hedged_tick_ms       = 0;

   for(int m_idx = 0; m_idx < m_master_pos_count; m_idx++)
   {
      ulong  m_ticket         = m_master_positions[m_idx].ticket;
      string expected_comment = m_comment_prefix + IntegerToString(m_ticket);

      // ANTI-DOUBLE HEDGE DEBOUNCE GUARD:
      // Jika Slave baru saja menembakkan order hedge untuk tiket Master yang sama dalam 5 detik terakhir,
      // TAHAN! Jangan kirim lagi (menunggu cache PositionsTotal MT5 selesai di-update oleh broker).
      if(m_ticket == s_last_hedged_master_ticket && (GetTickCount64() - s_last_hedged_tick_ms < 5000))
      {
         continue; // Order sedang diproses bursa, tahan agar tidak terjadi order ganda!
      }

      bool already_hedged = false;
      double want_raw     = m_master_positions[m_idx].volume * InpLotMultiplier;
      double want_lot     = MathRound(want_raw * 100.0) / 100.0;
      want_lot            = MathMax(0.01, MathMin(50.0, want_lot));

      if(!m_comments_lost)
      {
         // MODE NORMAL: cocokkan per-tiket via tag comment "CT#<master_ticket>"
         for(int s = PositionsTotal() - 1; s >= 0; s--)
         {
            ulong s_ticket = PositionGetTicket(s);
            if(s_ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magic
               && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
               && PositionGetString(POSITION_COMMENT) == expected_comment)
            {
               already_hedged = true;
               break;
            }
         }
      }
      else
      {
         // MODE KOMENTAR HILANG (broker overwrite comment, mis. dari copy-order):
         // backstop bucket — hitung hedge milik sendiri dengan (tipe lawan + volume
         // want_lot) vs jumlah posisi Master yang butuh hedge itu. Jangan buka
         // duplicat; volume unik per bucket sehingga lot seragam antar layer aman.
         int want_type = ((int)m_master_positions[m_idx].type == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         int have_count = 0, need_count = 0;
         for(int mm = 0; mm < m_master_pos_count; mm++)
         {
            double wlot = MathRound(m_master_positions[mm].volume * InpLotMultiplier * 100.0) / 100.0;
            wlot = MathMax(0.01, MathMin(50.0, wlot));
            if(MathAbs(wlot - want_lot) < 0.005 && (int)m_master_positions[mm].type == (int)m_master_positions[m_idx].type)
               need_count++;
         }
         for(int s = PositionsTotal() - 1; s >= 0; s--)
         {
            ulong s_ticket = PositionGetTicket(s);
            if(s_ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magic
               && (StringCompare(PositionGetString(POSITION_SYMBOL), m_symbol, false) == 0 || StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol, false) == 0)
               && (int)PositionGetInteger(POSITION_TYPE) == want_type
               && MathAbs(PositionGetDouble(POSITION_VOLUME) - want_lot) < 0.005)
               have_count++;
         }
         already_hedged = (have_count >= need_count);
      }

      if(!already_hedged)
      {
         double slave_lot = want_lot;

         // ATOMIC IN-FLIGHT LOCK: Kunci tiket sebelum menembak order ke broker agar tidak bisa terjadi order kembar!
         s_last_hedged_master_ticket = m_ticket;
         s_last_hedged_tick_ms       = GetTickCount64();

         bool order_ok = false;
         if(m_master_positions[m_idx].type == 1) // Master SELL -> Slave BUY
         {
            order_ok = m_trade.Buy(slave_lot, m_symbol, tick.ask, 0, 0, expected_comment);
         }
         else if(m_master_positions[m_idx].type == 0) // Master BUY -> Slave SELL
         {
            order_ok = m_trade.Sell(slave_lot, m_symbol, tick.bid, 0, 0, expected_comment);
         }

         if(order_ok)
         {
            m_last_order_open_time      = TimeCurrent();
            Print("✅ [HEDGE OPEN SUCCESS] Master #", m_ticket, " -> Slave ", slave_lot, "L (", expected_comment, ")");
         }
         else
         {
            s_last_hedged_master_ticket = 0;
            s_last_hedged_tick_ms       = 0;
            // CRITICAL ROLLBACK: Jika Slave gagal buka hedge (misal not enough money),
            // Master WAJIB LANGSUNG DI-CLOSE agar tidak floating sendirian tanpa pasangan!
            Print("🚨 [HEDGE FAILED] Slave gagal buka order (Code=", m_trade.ResultRetcode(),
                  " ", m_trade.ResultComment(), ")! Mengirim sinyal CLOSE_ALL ke Master untuk keamanan!");
            SendCommandToMaster("CLOSE_ALL");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Sync Close: Close Slave positions when Master closed             |
//| IRONCLAD ANTI-STALE READ: Requires confirmed missing state for   |
//| at least 3 consecutive timer cycles (150ms) to prevent jitter    |
//+------------------------------------------------------------------+
void SyncClosePositions()
{
   if(!m_master_online) return;

   // Bersihkan tracker untuk tiket yang sudah tertutup / tidak ada lagi di MT5
   int cur_size = ArraySize(m_missing_tickets);
   for(int t = cur_size - 1; t >= 0; t--)
   {
      bool ticket_exists = false;
      for(int s = PositionsTotal() - 1; s >= 0; s--)
      {
         if(PositionGetTicket(s) == m_missing_tickets[t].ticket)
         {
            ticket_exists = true;
            break;
         }
      }
      if(!ticket_exists)
      {
         for(int k = t; k < cur_size - 1; k++)
            m_missing_tickets[k] = m_missing_tickets[k + 1];
         cur_size--;
         ArrayResize(m_missing_tickets, cur_size);
      }
   }

   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      ulong s_ticket = PositionGetTicket(s);
      if(s_ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)m_magic) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, m_comment_prefix) != 0) continue;

      string ticket_str = StringSubstr(comment, StringLen(m_comment_prefix));
      ulong  m_ticket   = (ulong)StringToInteger(ticket_str);
      if(m_ticket == 0) continue;

      bool master_still_open = false;
      for(int m_idx = 0; m_idx < m_master_pos_count; m_idx++)
      {
         if(m_master_positions[m_idx].ticket == m_ticket)
         {
            master_still_open = true;
            break;
         }
      }

      // Anti-jitter missing confirmation tracking
      int tracker_idx = -1;
      int total_tracked = ArraySize(m_missing_tickets);
      for(int t = 0; t < total_tracked; t++)
      {
         if(m_missing_tickets[t].ticket == s_ticket)
         {
            tracker_idx = t;
            break;
         }
      }

      if(master_still_open)
      {
         if(tracker_idx >= 0)
            m_missing_tickets[tracker_idx].missing_count = 0;
      }
      else
      {
         if(tracker_idx < 0)
         {
            ArrayResize(m_missing_tickets, total_tracked + 1);
            m_missing_tickets[total_tracked].ticket = s_ticket;
            m_missing_tickets[total_tracked].missing_count = 1;
            tracker_idx = total_tracked;
         }
         else
         {
            m_missing_tickets[tracker_idx].missing_count++;
         }

         // Jika Master sudah flat (0 posisi), langsung tutup seketika di siklus pertama (0ms lag)!
         // Jika parsial, butuh 2 siklus (100ms) untuk mencegah jitter baca parsial.
         int required_cycles = (m_master_pos_count == 0) ? 1 : 2;
         if(m_missing_tickets[tracker_idx].missing_count >= required_cycles)
         {
            Print("⚡ [FAST SYNC CLOSE] Master #", m_ticket, " closed -> Closing Slave #", s_ticket, " immediately!");
            if(m_trade.PositionClose(s_ticket))
            {
               m_last_order_close_time = TimeCurrent();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Get total profit of Slave positions                      |
//+------------------------------------------------------------------+
double GetSlaveTotalProfit()
{
   double total = 0.0;
   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      ulong s_ticket = PositionGetTicket(s);
      if(s_ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
         total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

//+------------------------------------------------------------------+
//| Helper: Close all Slave positions                                |
//+------------------------------------------------------------------+
void CloseAllSlavePositions()
{
   int closed_count = 0;
   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      ulong s_ticket = PositionGetTicket(s);
      if(s_ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
      {
         if(m_trade.PositionClose(s_ticket)) closed_count++;
      }
   }

   ArrayResize(m_missing_tickets, 0); // Clear tracker

   if(closed_count > 0)
   {
      m_last_order_close_time = TimeCurrent();
      int lifespan = (m_last_order_open_time > 0) ? (int)(TimeCurrent() - m_last_order_open_time) : 999;

      if(m_last_order_open_time > 0 && lifespan <= 20)
      {
         m_rapid_close_counter++;
         Print("⚠️ [SLAVE ANTI-FLAPPING] Buka-tutup kilat (Umur: ", lifespan, "s). Counter: ", m_rapid_close_counter);

         if(m_rapid_close_counter >= 2)
         {
            m_circuit_breaker_until = TimeCurrent() + 300; // 5 Menit Lockout
            m_circuit_breaker_reason = "Terdeteksi 2x Buka-Tutup Kilat (<20s)";
            Print("🚨 [SLAVE CIRCUIT BREAKER ACTIVATED] Slave dikunci PAUSE selama 5 menit untuk melindungi modal!");
         }
      }
      else
      {
         m_rapid_close_counter = 0;
      }
   }
}

void SendCommandToMaster(string cmd)
{
   int file_handle = FileOpen(m_cmd_to_master, FILE_WRITE|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(file_handle != INVALID_HANDLE)
   {
      FileWriteLong(file_handle, 0x4248434D); // "BHCM" command magic
      FileWriteLong(file_handle, (long)AccountInfoInteger(ACCOUNT_LOGIN)); // Tag with Slave's Unique Account Login
      int clen = StringLen(cmd);
      FileWriteInteger(file_handle, clen);
      if(clen > 0) FileWriteString(file_handle, cmd, clen);
      FileFlush(file_handle);
      FileClose(file_handle);
   }
}

//+------------------------------------------------------------------+
//| Check incoming commands from Master (e.g. CLOSE_ALL)             |
//+------------------------------------------------------------------+
void CheckIncomingCommands()
{
   if(!FileIsExist(m_cmd_to_slave, FILE_COMMON)) return;

   int file_handle = FileOpen(m_cmd_to_slave, FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
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

   // Isolation: Jika perintah bukan berasal dari Master pasangan akun ini, abaikan!
   if(cmd_magic == 0x4248434D && m_master_login > 0 && sender_login != 0 && sender_login != m_master_login)
   {
      return;
   }

   FileDelete(m_cmd_to_slave, FILE_COMMON);

   if(cmd == "CLOSE_ALL" && !m_closing_active)
   {
      Print("🚨 [SLAVE] Received CLOSE_ALL command from Master #", sender_login, "! Closing all positions.");
      m_closing_active = true;
      m_closing_lock_until = TimeCurrent() + 6;
      CloseAllSlavePositions();
      m_closing_active = false;
   }
}

//+------------------------------------------------------------------+
//| Draw On-Screen Dashboard                                         |
//+------------------------------------------------------------------+
void UpdateDashboard(double slave_profit, double combined_net_profit)
{
   int slave_pos_count = 0;
   for(int s = PositionsTotal() - 1; s >= 0; s--)
   {
      ulong s_ticket = PositionGetTicket(s);
      if(s_ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)m_magic)
         slave_pos_count++;
   }

   string profit_sign = (combined_net_profit >= 0) ? "🟢 +" : "🔴 ";
   string status_str  = (slave_pos_count > 0) ? "✅ HEDGING ACTIVE (50ms sync)" : "⏳ IDLE - Waiting Master";
   double my_credit   = AccountInfoDouble(ACCOUNT_CREDIT);

   if(TimeCurrent() < m_circuit_breaker_until)
   {
      int remain_sec = (int)(m_circuit_breaker_until - TimeCurrent());
      status_str = "🛑 CIRCUIT BREAKER PAUSE (" + IntegerToString(remain_sec) + "s) - " + m_circuit_breaker_reason;
   }
   else if(InpMinBonusCredit > 0 && my_credit < InpMinBonusCredit && slave_pos_count == 0)
   {
      status_str = "⏳ PAUSED: Menunggu Bonus Broker Masuk (Credit: $" + DoubleToString(my_credit, 2) + " < $" + DoubleToString(InpMinBonusCredit, 2) + ")";
   }

   string text = "\n" +
      "  ╔════════════════════════════════════════════════════════════════╗\n" +
      "  ║   ⚡ DUAL-MT5 BONUS HEDGING - SLAVE LP ENGINE v1.22           ║\n" +
      "  ╠════════════════════════════════════════════════════════════════╣\n" +
      "    Pair Group ID   : #" + IntegerToString(InpPairID) + " (Magic: " + IntegerToString(m_magic) + ")\n" +
      "    Bridge Files    : " + m_master_file + " <-> " + m_slave_file + "\n" +
      "    [MASTER ACCOUNT " + IntegerToString(m_master_login) + "]\n" +
      "      Equity / Balance: $" + DoubleToString(m_master_equity, 2) + " / $" + DoubleToString(m_master_balance, 2) + "\n" +
      "      Free Margin     : $" + DoubleToString(m_master_free_margin, 2) + " (" + DoubleToString(m_master_margin_level, 1) + "%)\n" +
      "      Floating        : $" + DoubleToString(m_master_profit, 2) + "\n" +
      "      Layers          : " + IntegerToString(m_master_pos_count) + " Active\n" +
      "  ────────────────────────────────────────────────────────────────\n" +
      "    [SLAVE ACCOUNT (BONUS LP)]\n" +
      "      Equity / Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + " / $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n" +
      "      Credit (Bonus)  : $" + DoubleToString(AccountInfoDouble(ACCOUNT_CREDIT), 2) + "\n" +
      "      Free Margin     : $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + " (" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 1) + "%)\n" +
      "      Floating        : $" + DoubleToString(slave_profit, 2) + "\n" +
      "      Hedges          : " + IntegerToString(slave_pos_count) + " Pairs (x" + DoubleToString(InpLotMultiplier, 2) + " Lot)\n" +
      "  ────────────────────────────────────────────────────────────────\n" +
      "    🎯 NET COMBINED PROFIT : " + profit_sign + DoubleToString(combined_net_profit, 2) + "\n" +
      "    Status : " + status_str + "\n" +
      "  ╚════════════════════════════════════════════════════════════════╝\n";

   Comment(text);
}

void UpdateDashboardOffline()
{
   Comment("\n  ⚠️ [BonusHedge_Slave] Menunggu data dari Master EA...\n" +
           "  Pastikan BonusHedge_Master.mq5 sudah aktif di chart MT5 Master (100870).");
}
