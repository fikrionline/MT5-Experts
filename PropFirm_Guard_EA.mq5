//+------------------------------------------------------------------+
//|                                           PropFirm_Guard_EA.mq5  |
//|  EMA trend + pullback EA with built-in prop firm risk guards     |
//|  NOT a guaranteed passer. Backtest and demo test before use.     |
//+------------------------------------------------------------------+
#property copyright "Template"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//--- Account / prop firm rules
input group "=== Prop Firm Rules ==="
input double InpInitialBalance   = 1000.00;   // Challenge account size (0 = use balance at first start)
input double InpDailyLossStopPct = 2.5;   // Stop for the day at this % loss (firm limit usually 5%)
input double InpMaxDDStopPct     = 6.0;   // Stop forever at this % total loss (firm limit usually 10%)
input double InpProfitTargetPct  = 8.0;   // Stop trading when profit reaches this % (0 = off). E.g. 8 (Step1), 5 (Step2)

//--- Risk
input group "=== Risk ==="
input double InpRiskPercent      = 1.00;  // Risk per trade (% of balance)
input int    InpMaxTradesPerDay  = 9;     // Max new trades per day
input int    InpMaxSpreadPoints  = 300;   // Max spread (points). Gold may need higher
input bool   InpOneTradeAtATime  = true;  // Only one open position

//--- Strategy
input group "=== Strategy ==="
input ENUM_TIMEFRAMES InpTF      = PERIOD_M5; // Trading timeframe
input int    InpEmaTrend         = 200;   // Trend EMA
input int    InpEmaMid           = 50;    // Mid EMA (must be on trend side of trend EMA)
input int    InpEmaPullback      = 20;    // Pullback EMA
input int    InpAtrPeriod        = 14;    // ATR period
input double InpAtrSlMult        = 1.5;   // SL = ATR x this
input double InpRR               = 2.0;   // Take profit = SL x this
input double InpMinAtrPoints     = 0;     // Skip if ATR smaller than this (points, 0 = off)

//--- Trade management
input group "=== Trade Management ==="
input bool   InpUseBreakEven     = true;  // Move SL to break-even
input double InpBEtriggerR       = 1.0;   // BE trigger (in R multiples)
input double InpBEoffsetPoints   = 10;    // Lock a few points beyond entry

//--- Time filter (broker SERVER time)
input group "=== Time Filter (server time) ==="
input bool   InpUseTimeFilter    = true;
input int    InpStartHour        = 17;     // Start hour
input int    InpEndHour          = 22;    // End hour (no new trades after)
input bool   InpCloseOnFriday    = true;  // Close all before weekend
input int    InpFridayCloseHour  = 22;    // Friday close hour

input group "=== Misc ==="
input long   InpMagic            = 20260101;
input string InpComment          = "PFG_EA";

//--- Handles
int hTrend = INVALID_HANDLE, hMid = INVALID_HANDLE, hPull = INVALID_HANDLE, hAtr = INVALID_HANDLE;

//--- State
double   g_initBalance = 0;
double   g_dayStartEq  = 0;
datetime g_dayStamp    = 0;
bool     g_haltDay     = false;
bool     g_haltAll     = false;
int      g_tradesToday = 0;
datetime g_lastBar     = 0;

string GVName(string key) { return "PFG_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + key; }

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);

   hTrend = iMA(_Symbol, InpTF, InpEmaTrend,    0, MODE_EMA, PRICE_CLOSE);
   hMid   = iMA(_Symbol, InpTF, InpEmaMid,      0, MODE_EMA, PRICE_CLOSE);
   hPull  = iMA(_Symbol, InpTF, InpEmaPullback, 0, MODE_EMA, PRICE_CLOSE);
   hAtr   = iATR(_Symbol, InpTF, InpAtrPeriod);
   if(hTrend == INVALID_HANDLE || hMid == INVALID_HANDLE || hPull == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("Indicator handle error");
      return INIT_FAILED;
   }

   // Initial balance (persisted so restarts don't reset it)
   if(InpInitialBalance > 0) g_initBalance = InpInitialBalance;
   else
   {
      if(GlobalVariableCheck(GVName("init"))) g_initBalance = GlobalVariableGet(GVName("init"));
      else
      {
         g_initBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         GlobalVariableSet(GVName("init"), g_initBalance);
      }
   }
   if(GlobalVariableCheck(GVName("haltall")) && GlobalVariableGet(GVName("haltall")) > 0)
      g_haltAll = true;

   // Restore day state
   if(GlobalVariableCheck(GVName("daystamp")) && GlobalVariableCheck(GVName("dayeq")))
   {
      g_dayStamp   = (datetime)GlobalVariableGet(GVName("daystamp"));
      g_dayStartEq = GlobalVariableGet(GVName("dayeq"));
   }
   UpdateDay();
   PrintFormat("PFG EA started. Initial balance reference: %.2f", g_initBalance);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hTrend);
   IndicatorRelease(hMid);
   IndicatorRelease(hPull);
   IndicatorRelease(hAtr);
}

//+------------------------------------------------------------------+
void UpdateDay()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != g_dayStamp)
   {
      g_dayStamp    = today;
      // Conservative: measure from the higher of balance/equity at day start
      g_dayStartEq  = MathMax(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
      g_haltDay     = false;
      g_tradesToday = 0;
      GlobalVariableSet(GVName("daystamp"), (double)g_dayStamp);
      GlobalVariableSet(GVName("dayeq"), g_dayStartEq);
   }
}

//+------------------------------------------------------------------+
int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) n++;
   }
   return n;
}

void CloseAllMine()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(t);
   }
}

//+------------------------------------------------------------------+
//| Risk guards: returns true if trading is allowed                  |
//+------------------------------------------------------------------+
bool RiskGuards()
{
   UpdateDay();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // Total drawdown (static, from initial balance)
   double ddPct = (g_initBalance - eq) / g_initBalance * 100.0;
   if(ddPct >= InpMaxDDStopPct && !g_haltAll)
   {
      PrintFormat("MAX DD guard hit (%.2f%%). Closing all and halting.", ddPct);
      CloseAllMine();
      g_haltAll = true;
      GlobalVariableSet(GVName("haltall"), 1);
   }

   // Profit target reached
   if(InpProfitTargetPct > 0 && !g_haltAll)
   {
      double profPct = (eq - g_initBalance) / g_initBalance * 100.0;
      if(profPct >= InpProfitTargetPct)
      {
         PrintFormat("Profit target reached (%.2f%%). Closing all and halting.", profPct);
         CloseAllMine();
         g_haltAll = true;
         GlobalVariableSet(GVName("haltall"), 1);
      }
   }

   // Daily loss
   double dayLossPct = (g_dayStartEq - eq) / g_initBalance * 100.0;
   if(dayLossPct >= InpDailyLossStopPct && !g_haltDay)
   {
      PrintFormat("DAILY loss guard hit (%.2f%%). Closing all and halting for today.", dayLossPct);
      CloseAllMine();
      g_haltDay = true;
   }

   return (!g_haltAll && !g_haltDay);
}

//+------------------------------------------------------------------+
bool InTradingHours()
{
   if(!InpUseTimeFilter) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week == 0 || t.day_of_week == 6) return false;
   if(t.hour < InpStartHour || t.hour >= InpEndHour) return false;
   if(InpCloseOnFriday && t.day_of_week == 5 && t.hour >= InpFridayCloseHour - 1) return false;
   return true;
}

double CalcLots(double slDistance)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickSize <= 0 || tickValue <= 0 || slDistance <= 0) return 0;

   double lossPerLot = slDistance / tickSize * tickValue;
   double lots = risk / lossPerLot;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   if(lots < vmin) return 0;           // would exceed intended risk -> skip
   if(lots > vmax) lots = vmax;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
void ManageBreakEven()
{
   if(!InpUseBreakEven) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      if(sl == 0) continue;
      double offset = InpBEoffsetPoints * _Point;

      if(type == POSITION_TYPE_BUY)
      {
         double risk = open - sl;
         if(sl >= open) continue; // already BE or better
         if(SymbolInfoDouble(_Symbol, SYMBOL_BID) - open >= risk * InpBEtriggerR)
            trade.PositionModify(t, NormalizeDouble(open + offset, _Digits), tp);
      }
      else
      {
         double risk = sl - open;
         if(sl <= open) continue;
         if(open - SymbolInfoDouble(_Symbol, SYMBOL_ASK) >= risk * InpBEtriggerR)
            trade.PositionModify(t, NormalizeDouble(open - offset, _Digits), tp);
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   bool allowed = RiskGuards();

   // Friday close
   if(InpCloseOnFriday)
   {
      MqlDateTime t; TimeToStruct(TimeCurrent(), t);
      if(t.day_of_week == 5 && t.hour >= InpFridayCloseHour) CloseAllMine();
   }

   ManageBreakEven();

   if(!allowed) return;

   // Run entry logic once per new bar
   datetime barTime = iTime(_Symbol, InpTF, 0);
   if(barTime == g_lastBar) return;
   g_lastBar = barTime;

   if(!InpOneTradeAtATime || CountMyPositions() == 0)
   {
      if(g_tradesToday >= InpMaxTradesPerDay) return;
      if(!InTradingHours()) return;

      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints) return;

      double trend[], mid[], pull[], atr[];
      ArraySetAsSeries(trend, true); ArraySetAsSeries(mid, true);
      ArraySetAsSeries(pull, true);  ArraySetAsSeries(atr, true);
      if(CopyBuffer(hTrend, 0, 0, 4, trend) < 4) return;
      if(CopyBuffer(hMid,   0, 0, 4, mid)   < 4) return;
      if(CopyBuffer(hPull,  0, 0, 4, pull)  < 4) return;
      if(CopyBuffer(hAtr,   0, 0, 4, atr)   < 4) return;

      double c1 = iClose(_Symbol, InpTF, 1);
      double c2 = iClose(_Symbol, InpTF, 2);

      double atrVal = atr[1];
      if(InpMinAtrPoints > 0 && atrVal / _Point < InpMinAtrPoints) return;

      double slDist = atrVal * InpAtrSlMult;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slDist < stopsLevel * _Point) slDist = stopsLevel * _Point;

      // LONG: uptrend, pulled back under pullback EMA, closed back above it
      bool longSig  = (mid[1] > trend[1] && c1 > trend[1] && c2 < pull[2] && c1 > pull[1]);
      // SHORT: downtrend, pulled back above pullback EMA, closed back below it
      bool shortSig = (mid[1] < trend[1] && c1 < trend[1] && c2 > pull[2] && c1 < pull[1]);

      if(longSig)
      {
         double lots = CalcLots(slDist);
         if(lots > 0)
         {
            double sl = NormalizeDouble(ask - slDist, _Digits);
            double tp = NormalizeDouble(ask + slDist * InpRR, _Digits);
            if(trade.Buy(lots, _Symbol, ask, sl, tp, InpComment)) g_tradesToday++;
         }
      }
      else if(shortSig)
      {
         double lots = CalcLots(slDist);
         if(lots > 0)
         {
            double sl = NormalizeDouble(bid + slDist, _Digits);
            double tp = NormalizeDouble(bid - slDist * InpRR, _Digits);
            if(trade.Sell(lots, _Symbol, bid, sl, tp, InpComment)) g_tradesToday++;
         }
      }
   }
}
//+------------------------------------------------------------------+
