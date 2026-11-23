//+------------------------------------------------------------------+
//|                                              KOF_Aggressive_EA.mq5 |
//|   M1 Countertrend Scalper (fade / mean-reversion) - Expert Advisor |
//|   Standalone conversion of KOF_Aggressive_Signals.mq5              |
//|                                                                    |
//|   Entry   : fresh far-above / far-below EMA50 fade (closed bar)    |
//|   Add     : EMA9 crosses the latest order level (capped)           |
//|   Exit TP : price reaches exit EMA (default EMA20), basket-wide    |
//|   Exit SL : ATR/pips stop from first entry + time stop + daily     |
//|             loss limit + optional server-side SL                   |
//|                                                                    |
//|   WARNING: countertrend + averaging. Test on DEMA / tester first.  |
//|   Use small lots. No guarantee of profit.                          |
//+------------------------------------------------------------------+
#property copyright "KOF Aggressive EA"
#property version   "1.00"
#property description "KOF countertrend fade EA with adds, EMA profit exit and multiple cut-loss protections."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_DIST_MODE { DIST_ATR = 0, DIST_PIPS = 1 };
enum ENUM_EXIT_EMA  { EXIT_EMA9 = 9, EXIT_EMA20 = 20, EXIT_EMA50 = 50, EXIT_EMA200 = 200 };
enum ENUM_SL_MODE   { SL_ATR = 0, SL_PIPS = 1, SL_OFF = 2 };
enum ENUM_LOT_MODE  { LOT_FIXED = 0, LOT_RISK = 1 };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== General ==="
input long           InpMagic        = 20250101;  // Magic number
input string         InpComment      = "KOF";     // Order comment
input int            InpSlippage     = 20;        // Max slippage (points)

input group "=== Lot sizing ==="
input ENUM_LOT_MODE  InpLotMode      = LOT_FIXED; // Lot mode
input double         InpLot          = 0.10;      // Fixed lot (first entry)
input double         InpRiskPct      = 1.0;       // Risk % of equity if the WHOLE sequence hits SL
input double         InpAddLotMult   = 1.0;       // Lot multiplier for each ADD (1.0 = same lot)
input double         InpMaxTotalLots = 0.10;      // Max total lots in one sequence

input group "=== EMA structure ==="
input int            InpEmaFast      = 9;         // EMA Fast
input int            InpEmaMid       = 20;        // EMA Mid
input int            InpEmaSlow      = 50;        // EMA Slow (main mean)
input int            InpEmaTrend     = 200;       // EMA Trend

input group "=== Entry: distance from EMA Slow ==="
input ENUM_DIST_MODE InpDistMode     = DIST_ATR;  // Distance mode
input int            InpAtrPeriod    = 14;        // ATR period
input double         InpAtrMult      = 1.0;       // ATR multiplier
input double         InpMinPips      = 8.0;       // Min distance (pips) in PIPS mode
input double         InpPipSize      = 0.0;       // Pip size override (0 = auto)

input group "=== Re-entry (averaging) ==="
input bool           InpUseAdds      = true;      // Allow ADD entries
input int            InpMaxAdds      = 3;         // Max ADDs per sequence
input double         InpAddMinAtr    = 0.5;       // Min gap from last level (x ATR). 0 = original

input group "=== EXIT: profit ==="
input ENUM_EXIT_EMA  InpExitEma      = EXIT_EMA20;// Exit EMA target
input bool           InpExitOnlyProfit = true;    // Exit only beyond average price
input double         InpMinProfitPips= 1.0;       // Min profit beyond average price (pips)

input group "=== EXIT: cut loss ==="
input ENUM_SL_MODE   InpSlMode       = SL_ATR;    // Stop-loss mode
input double         InpSlAtrMult    = 3.0;       // SL from FIRST entry (x ATR at entry)
input double         InpSlPips       = 30.0;      // SL from FIRST entry (pips) in PIPS mode
input bool           InpUseServerSL  = true;      // Also place SL on the server
input int            InpMaxBars      = 0;         // Time stop: max bars in sequence (0 = off)
input int            InpCooldownBars = 5;         // Cooldown bars after a loss exit
input double         InpMaxDailyLossPct = 5.0;    // Daily loss limit % of day-start balance (0 = off)

input group "=== Filters ==="
input int            InpMaxSpreadPts = 30;        // Max spread in points for new orders (0 = off)
input bool           InpUseSession   = false;     // Use trading session (server time)
input int            InpStartHour    = 5;         // Session start hour (inclusive)
input int            InpEndHour      = 22;        // Session end hour (exclusive)
input bool           InpFlatAtEnd    = true;      // Close everything outside the session (no overnight)

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade trade;

int hE9 = INVALID_HANDLE, hE20 = INVALID_HANDLE, hE50 = INVALID_HANDLE, hE200 = INVALID_HANDLE, hATR = INVALID_HANDLE;
double e9[], e20[], e50[], e200[], atr[];   // series arrays: [0]=forming, [1]=last closed, [2]=previous
bool   g_ready = false;

double g_pip = 0.0;

//--- sequence state
int      g_dir        = 0;       // 0 flat, 1 long, -1 short
double   g_first      = 0.0;     // first entry price
double   g_lastLevel  = 0.0;     // latest order level
double   g_atr0       = 0.0;     // ATR at first entry
int      g_n          = 0;       // number of entries in sequence
datetime g_entryTime  = 0;
int      g_cool       = 0;
bool     g_expectedClose = false;

//--- daily protection
double   g_dayBal     = 0.0;
int      g_dayKey     = -1;
bool     g_halted     = false;

struct PosInfo
{
   int      count;
   int      dir;
   double   vol;
   double   avg;
   double   firstOpen;
   double   lastOpen;
   datetime firstTime;
   datetime lastTime;
};

//+------------------------------------------------------------------+
//| Persistent state (survives EA restart)                           |
//+------------------------------------------------------------------+
string K(const string name) { return "KOF_" + IntegerToString((long)InpMagic) + "_" + _Symbol + "_" + name; }

void SaveState()
{
   GlobalVariableSet(K("first"), g_first);
   GlobalVariableSet(K("last"),  g_lastLevel);
   GlobalVariableSet(K("atr0"),  g_atr0);
   GlobalVariableSet(K("n"),     (double)g_n);
   GlobalVariableSet(K("time"),  (double)g_entryTime);
}
bool LoadState()
{
   if(!GlobalVariableCheck(K("first"))) return false;
   g_first      = GlobalVariableGet(K("first"));
   g_lastLevel  = GlobalVariableGet(K("last"));
   g_atr0       = GlobalVariableGet(K("atr0"));
   g_n          = (int)GlobalVariableGet(K("n"));
   g_entryTime  = (datetime)(long)GlobalVariableGet(K("time"));
   return true;
}
void ClearState()
{
   GlobalVariableDel(K("first")); GlobalVariableDel(K("last")); GlobalVariableDel(K("atr0"));
   GlobalVariableDel(K("n"));     GlobalVariableDel(K("time"));
   g_dir = 0; g_first = 0; g_lastLevel = 0; g_atr0 = 0; g_n = 0; g_entryTime = 0;
}

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pip = (InpPipSize > 0.0) ? InpPipSize : ((_Digits == 3 || _Digits == 5) ? _Point * 10.0 : _Point);

   hE9   = iMA(_Symbol, _Period, InpEmaFast,  0, MODE_EMA, PRICE_CLOSE);
   hE20  = iMA(_Symbol, _Period, InpEmaMid,   0, MODE_EMA, PRICE_CLOSE);
   hE50  = iMA(_Symbol, _Period, InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   hE200 = iMA(_Symbol, _Period, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   hATR  = iATR(_Symbol, _Period, InpAtrPeriod);
   if(hE9 == INVALID_HANDLE || hE20 == INVALID_HANDLE || hE50 == INVALID_HANDLE ||
      hE200 == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("KOF EA: failed to create indicator handles");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   ArraySetAsSeries(e9, true); ArraySetAsSeries(e20, true); ArraySetAsSeries(e50, true);
   ArraySetAsSeries(e200, true); ArraySetAsSeries(atr, true);

   g_ready = false;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(hE9   != INVALID_HANDLE) IndicatorRelease(hE9);
   if(hE20  != INVALID_HANDLE) IndicatorRelease(hE20);
   if(hE50  != INVALID_HANDLE) IndicatorRelease(hE50);
   if(hE200 != INVALID_HANDLE) IndicatorRelease(hE200);
   if(hATR  != INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
}

//+------------------------------------------------------------------+
//| Indicator cache                                                  |
//+------------------------------------------------------------------+
bool UpdateInd()
{
   if(CopyBuffer(hE9,   0, 0, 4, e9)   < 4) return false;
   if(CopyBuffer(hE20,  0, 0, 4, e20)  < 4) return false;
   if(CopyBuffer(hE50,  0, 0, 4, e50)  < 4) return false;
   if(CopyBuffer(hE200, 0, 0, 4, e200) < 4) return false;
   if(CopyBuffer(hATR,  0, 0, 4, atr)  < 4) return false;
   return true;
}
double Thresh(const int k)
{
   if(InpDistMode == DIST_ATR) return atr[k] * InpAtrMult;
   return InpMinPips * g_pip;
}
// dir = -1 : far BELOW (BUY setup);  dir = +1 : far ABOVE (SELL setup)
bool IsFar(const int k, const int dir)
{
   double c = iClose(_Symbol, _Period, k);
   double thr = Thresh(k);
   if(dir < 0) return (c < e9[k] && c < e20[k] && c < e50[k] && (e50[k] - c) >= thr);
   return (c > e9[k] && c > e20[k] && c > e50[k] && (c - e50[k]) >= thr);
}
bool IsStuck(const int k)
{
   double c  = iClose(_Symbol, _Period, k);
   double hi = MathMax(e9[k], MathMax(e20[k], e50[k]));
   double lo = MathMin(e9[k], MathMin(e20[k], e50[k]));
   return (c <= hi && c >= lo);
}
double ExitEmaVal()
{
   switch(InpExitEma)
   {
      case EXIT_EMA9:   return e9[1];
      case EXIT_EMA50:  return e50[1];
      case EXIT_EMA200: return e200[1];
      default:          return e20[1];
   }
}

//+------------------------------------------------------------------+
//| Stops / targets                                                  |
//+------------------------------------------------------------------+
double SlDistance(const double atrVal)
{
   if(InpSlMode == SL_ATR)  return InpSlAtrMult * atrVal;
   if(InpSlMode == SL_PIPS) return InpSlPips * g_pip;
   return 0.0;
}
double SlLevel()          // anchored to FIRST entry of the sequence
{
   if(InpSlMode == SL_OFF || g_dir == 0) return 0.0;
   return g_first - g_dir * SlDistance(g_atr0);
}
double TargetLevel(const double avg)
{
   double ex = ExitEmaVal();
   if(!InpExitOnlyProfit) return ex;
   if(g_dir > 0) return MathMax(ex, avg + InpMinProfitPips * g_pip);
   return MathMin(ex, avg - InpMinProfitPips * g_pip);
}

//+------------------------------------------------------------------+
//| Positions                                                        |
//+------------------------------------------------------------------+
void ScanPositions(PosInfo &p)
{
   p.count = 0; p.dir = 0; p.vol = 0; p.avg = 0; p.firstOpen = 0; p.lastOpen = 0; p.firstTime = 0; p.lastTime = 0;
   double sumPV = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double v  = PositionGetDouble(POSITION_VOLUME);
      double pr = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);

      p.count++;
      p.dir = (type == POSITION_TYPE_BUY) ? 1 : -1;
      p.vol += v;
      sumPV += pr * v;
      if(p.firstTime == 0 || t < p.firstTime) { p.firstTime = t; p.firstOpen = pr; }
      if(t >= p.lastTime)                     { p.lastTime  = t; p.lastOpen  = pr; }
   }
   if(p.vol > 0) p.avg = sumPV / p.vol;
}
void CloseSequence(const bool isLoss, const string why)
{
   g_expectedClose = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(!trade.PositionClose(ticket))
         PrintFormat("KOF EA: close failed #%I64u ret=%d (%s)", ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
   if(isLoss) g_cool = InpCooldownBars;
   PrintFormat("KOF EA: sequence closed -> %s", why);
}

//+------------------------------------------------------------------+
//| Lots                                                             |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lot = MathFloor(lot / step + 1e-9) * step;
   if(lot < vmin) lot = vmin;
   if(lot > vmax) lot = vmax;
   return NormalizeDouble(lot, 2);
}
double FirstLot()
{
   double lot = InpLot;
   if(InpLotMode == LOT_RISK && InpSlMode != SL_OFF)
   {
      double d  = SlDistance(atr[1]);
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(d > 0 && tv > 0 && ts > 0)
      {
         double perLot = d / ts * tv;                    // money lost per 1.0 lot if SL hit
         double units = 0, m = 1.0;
         int entries = 1 + (InpUseAdds ? InpMaxAdds : 0);
         for(int k = 0; k < entries; k++) { units += m; m *= InpAddLotMult; }
         double risk = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0;
         if(units > 0 && perLot > 0) lot = risk / (units * perLot);
      }
   }
   return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
//| Filters                                                          |
//+------------------------------------------------------------------+
bool InSession()
{
   if(!InpUseSession) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
}
bool SpreadOK()
{
   if(InpMaxSpreadPts <= 0) return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPts);
}
void DailyCheck()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int key = dt.year * 1000 + dt.day_of_year;
   if(key != g_dayKey)
   {
      g_dayKey = key;
      g_dayBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_halted = false;
   }
   if(InpMaxDailyLossPct > 0 && !g_halted)
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq <= g_dayBal * (1.0 - InpMaxDailyLossPct / 100.0))
      {
         g_halted = true;
         if(g_dir != 0 && !g_expectedClose) CloseSequence(true, "DAILY LOSS LIMIT");
         Print("KOF EA: daily loss limit reached - trading halted until next day");
      }
   }
}

//+------------------------------------------------------------------+
//| Order placement                                                  |
//+------------------------------------------------------------------+
bool OpenPos(const int dir, const double lot, const double slPrice, double &fill)
{
   double price = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0;
   if(InpUseServerSL && InpSlMode != SL_OFF && slPrice > 0)
   {
      double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      if(MathAbs(price - slPrice) > minDist * 1.2 && ((dir > 0 && slPrice < price) || (dir < 0 && slPrice > price)))
         sl = NormalizeDouble(slPrice, _Digits);
      else
         Print("KOF EA: server SL skipped (too close / invalid) - software SL still active");
   }

   bool ok = (dir > 0) ? trade.Buy(lot, _Symbol, 0.0, sl, 0.0, InpComment)
                       : trade.Sell(lot, _Symbol, 0.0, sl, 0.0, InpComment);
   uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("KOF EA: order failed ret=%u (%s)", rc, trade.ResultRetcodeDescription());
      return false;
   }
   fill = trade.ResultPrice();
   if(fill <= 0) fill = price;
   return true;
}

void TryEntry()
{
   if(g_halted || !InSession() || !SpreadOK()) return;
   if(IsStuck(1)) return;

   int dir = 0;
   if(IsFar(1, -1) && !IsFar(2, -1))      dir = 1;    // fresh BUY (fade down)
   else if(IsFar(1, +1) && !IsFar(2, +1)) dir = -1;   // fresh SELL (fade up)
   if(dir == 0) return;

   double lot = FirstLot();
   if(lot > InpMaxTotalLots) { Print("KOF EA: first lot exceeds InpMaxTotalLots - skipped"); return; }

   double atr0 = atr[1];
   double refPrice = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slApprox = (InpSlMode == SL_OFF) ? 0.0 : refPrice - dir * SlDistance(atr0);

   double fill = 0;
   if(OpenPos(dir, lot, slApprox, fill))
   {
      g_dir = dir; g_first = fill; g_lastLevel = fill; g_atr0 = atr0; g_n = 1; g_entryTime = TimeCurrent();
      g_expectedClose = false;
      SaveState();
      PrintFormat("KOF EA: %s @ %s lot %.2f", dir > 0 ? "BUY" : "SELL", DoubleToString(fill, _Digits), lot);
   }
}

void TryAdd(const PosInfo &p)
{
   if(!InpUseAdds || g_n > InpMaxAdds) return;
   if(g_halted || !InSession() || !SpreadOK()) return;

   bool cross;
   if(g_dir > 0) cross = (e9[1] < g_lastLevel && e9[2] >= g_lastLevel);
   else          cross = (e9[1] > g_lastLevel && e9[2] <= g_lastLevel);
   if(!cross) return;

   double c1 = iClose(_Symbol, _Period, 1);
   if((g_dir * (g_lastLevel - c1)) < InpAddMinAtr * atr[1]) return;

   // lot of this add = firstLot * mult^(g_n-1)
   double lot = NormalizeLot(FirstLot() * MathPow(InpAddLotMult, g_n));
   if(p.vol + lot > InpMaxTotalLots + 1e-9) { Print("KOF EA: ADD skipped - max total lots"); return; }

   double fill = 0;
   if(OpenPos(g_dir, lot, SlLevel(), fill))
   {
      g_n++; g_lastLevel = fill; SaveState();
      PrintFormat("KOF EA: ADD %s #%d @ %s lot %.2f", g_dir > 0 ? "BUY" : "SELL", g_n - 1, DoubleToString(fill, _Digits), lot);
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void ShowInfo(const PosInfo &p)
{
   string s = "KOF AGGRESSIVE EA  [" + _Symbol + "]\n";
   if(g_dir == 0)
   {
      s += "State : FLAT";
      if(g_cool > 0) s += "  (cooldown " + IntegerToString(g_cool) + " bars)";
      s += "\n";
   }
   else
   {
      s += StringFormat("State : %s x%d  vol %.2f  avg %s\n", g_dir > 0 ? "LONG" : "SHORT", g_n, p.vol, DoubleToString(p.avg, _Digits));
      if(g_ready)
         s += "TP    : " + DoubleToString(TargetLevel(p.avg), _Digits) + "   SL: " +
              (InpSlMode == SL_OFF ? "OFF" : DoubleToString(SlLevel(), _Digits)) + "\n";
   }
   if(g_halted) s += "!!! DAILY LOSS LIMIT - HALTED !!!\n";
   if(g_ready)  s += StringFormat("Dist50: %+.1f pips | need %.1f\n",
                     (iClose(_Symbol, _Period, 1) - e50[1]) / g_pip, Thresh(1) / g_pip);
   s += "Risk  : averaging into losers - use small lots";
   Comment(s);
}

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- first-time cache
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   bool newBar = (curBar != lastBar);

   if(!g_ready || newBar)
   {
      if(BarsCalculated(hE200) < 10 || BarsCalculated(hATR) < 10) return;
      if(UpdateInd()) g_ready = true;
      else return;
   }

   DailyCheck();

   //--- sync state with real positions
   PosInfo p;
   ScanPositions(p);
   if(p.count == 0)
   {
      if(g_dir != 0)
      {
         if(!g_expectedClose) g_cool = InpCooldownBars;   // closed by server SL / manually
         ClearState();
      }
      g_expectedClose = false;
   }
   else if(g_dir == 0)
   {
      g_dir = p.dir;
      if(!LoadState())
      {
         g_first = p.firstOpen; g_lastLevel = p.lastOpen; g_atr0 = atr[1];
         g_n = p.count; g_entryTime = p.firstTime;
         SaveState();
      }
      Print("KOF EA: existing sequence restored");
   }

   //--- session end: flatten (no overnight)
   if(g_dir != 0 && !g_expectedClose && InpUseSession && InpFlatAtEnd && !InSession())
   {
      CloseSequence(false, "SESSION END");
      ShowInfo(p);
      lastBar = curBar;
      return;
   }

   //--- tick-level exits (profit / cut loss)
   if(g_dir != 0 && !g_expectedClose && p.count > 0)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = SlLevel();
      double tp  = TargetLevel(p.avg);

      bool hitSL = false, hitTP = false;
      if(g_dir > 0) { hitSL = (InpSlMode != SL_OFF && bid <= sl); hitTP = (bid >= tp); }
      else          { hitSL = (InpSlMode != SL_OFF && ask >= sl); hitTP = (ask <= tp); }

      if(hitSL)      CloseSequence(true,  "CUT LOSS (SL)");
      else if(hitTP) CloseSequence(false, "EXIT PROFIT (EMA target)");
   }

   //--- new closed bar logic: time stop, adds, entries
   if(newBar)
   {
      lastBar = curBar;

      if(g_dir == 0)
      {
         if(g_cool > 0) g_cool--;
         else           TryEntry();
      }
      else if(!g_expectedClose)
      {
         if(InpMaxBars > 0 && g_entryTime > 0 && iBarShift(_Symbol, _Period, g_entryTime) >= InpMaxBars)
            CloseSequence(true, "TIME STOP");
         else
            TryAdd(p);
      }
   }

   ShowInfo(p);
}
//+------------------------------------------------------------------+
