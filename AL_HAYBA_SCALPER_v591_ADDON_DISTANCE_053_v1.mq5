//+------------------------------------------------------------------+
//| AL_HAYBA_SCALPER_v591_ADDON_DISTANCE_053.mq5                    |
//| Rapid multi-position XAUUSD M1 scalper with regime + ADX filter |
//+------------------------------------------------------------------+
#property strict
#property version "5.91"

#include <Trade/Trade.mqh>
CTrade trade;

//============================== CORE =================================
input double Lots                    = 0.01;
input int    MagicNumber             = 275000;
input int    MaxTradesPerDay         = 220;
input int    MaxOpenPositions        = 10;
input int    MaxPerDirection         = 8;
input double MaxSpreadDollars        = 0.30;
input int    EntryCooldownSeconds    = 10;
input double AddOnDistanceDollars    = 0.53;

//============================== TREND =================================
input int    FastEMA                 = 7;
input int    SlowEMA                 = 25;
input int    RSIPeriod               = 3;

input int    M5FastEMA               = 9;
input int    M5SlowEMA               = 21;
input int    ADXPeriod               = 7;
input double MinADX                  = 24.0;

input double BuyRSIMin               = 60.0;
input double SellRSIMax              = 40.0;
input double StrongBuyRSI            = 68.0;
input double StrongSellRSI           = 32.0;

input double MinM1EMAGap             = 0.12;
input double MinImpulse              = 0.16;
input double StrongImpulse           = 0.32;
input double MinBody                 = 0.12;


//============================== BREAKOUT ==============================
input int    BreakoutLookback        = 5;
input double BreakoutBuffer          = 0.04;

//============================== EXITS ================================
input double StopDollars             = 0.50;
input double TakeProfitDollars       = 1.20;

input bool   UseBreakEven            = true;
input double BreakEvenTrigger        = 0.30;
input double BreakEvenLock           = 0.10;

input bool   UseTrailing             = true;
input double TrailStart              = 0.48;
input double TrailDistance           = 0.22;

input bool   UseEarlyExit            = true;
input int    EarlyExitAfterMinutes   = 3;
input double EarlyExitLossDollars    = 0.16;

input bool   UseTimeStop             = true;
input int    MaxMinutesInTrade       = 10;
input double TimeStopMinProfit       = 0.03;

//============================== SAFETY ===============================
input double MaxFloatingLossDollars  = 2.20;

//============================== STATE ================================
int hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE, hRSI = INVALID_HANDLE;
int hM5Fast = INVALID_HANDLE, hM5Slow = INVALID_HANDLE, hADX = INVALID_HANDLE;

int dayOfYear = -1, tradesToday = 0;
datetime lastBuyTime = 0, lastSellTime = 0;

//+------------------------------------------------------------------+
double Buf(int handle, int buffer, int shift) {
   double a[];
   ArraySetAsSeries(a, true);
   if (CopyBuffer(handle, buffer, shift, 1, a) != 1) return EMPTY_VALUE;
   return a[0];
}

void ResetDay() {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if (t.day_of_year != dayOfYear) {
      dayOfYear = t.day_of_year;
      tradesToday = 0;
   }
}

bool SpreadOK() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask > 0 && bid > 0 && (ask - bid) <= MaxSpreadDollars);
}

double RecentHigh(int bars) {
   double hi = -DBL_MAX;
   for (int i = 1; i <= bars; i++) hi = MathMax(hi, iHigh(_Symbol, PERIOD_M1, i));
   return hi;
}

double RecentLow(int bars) {
   double lo = DBL_MAX;
   for (int i = 1; i <= bars; i++) lo = MathMin(lo, iLow(_Symbol, PERIOD_M1, i));
   return lo;
}

int CountOwnPositions(int direction = -1) {
   int c = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if (tk == 0 || !PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int) PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if (direction == -1 ||
         (direction == 0 && type == POSITION_TYPE_BUY) ||
         (direction == 1 && type == POSITION_TYPE_SELL))
         c++;
   }
   return c;
}

double OwnFloatingProfit() {
   double p = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if (tk == 0 || !PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int) PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      p += PositionGetDouble(POSITION_PROFIT);
   }
   return p;
}

double LatestOwnEntryPrice(int direction) {
   datetime latest = 0;
   double price = 0.0;

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if (tk == 0 || !PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int) PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if (direction == 0 && type != POSITION_TYPE_BUY) continue;
      if (direction == 1 && type != POSITION_TYPE_SELL) continue;

      datetime t = (datetime) PositionGetInteger(POSITION_TIME);
      if (t >= latest) {
         latest = t;
         price = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return price;
}

bool DistanceOK(int direction, double price) {
   double last = LatestOwnEntryPrice(direction);
   if (last <= 0.0) return true;
   return MathAbs(price - last) >= AddOnDistanceDollars;
}

bool CanOpen(int direction) {
   if (!SpreadOK()) return false;
   if (tradesToday >= MaxTradesPerDay) return false;
   if (CountOwnPositions() >= MaxOpenPositions) return false;
   if (CountOwnPositions(direction) >= MaxPerDirection) return false;
   if (OwnFloatingProfit() <= -MaxFloatingLossDollars) return false;

   datetime now = TimeCurrent();
   if (direction == 0 && lastBuyTime > 0 && (now - lastBuyTime) < EntryCooldownSeconds) return false;
   if (direction == 1 && lastSellTime > 0 && (now - lastSellTime) < EntryCooldownSeconds) return false;

   return true;
}

void CloseDirection(int direction) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if (tk == 0 || !PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int) PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if (direction == 0 && type != POSITION_TYPE_BUY) continue;
      if (direction == 1 && type != POSITION_TYPE_SELL) continue;

      trade.PositionClose(tk);
   }
}

void OpenBuy(string tag) {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if (!CanOpen(0) || !DistanceOK(0, ask)) return;

   double sl = NormalizeDouble(ask - StopDollars, _Digits);
   double tp = NormalizeDouble(ask + TakeProfitDollars, _Digits);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(80);

   bool ok = trade.Buy(Lots, _Symbol, 0.0, sl, tp, tag);
   if (ok && trade.ResultDeal() > 0) {
      tradesToday++;
      lastBuyTime = TimeCurrent();
   }
}

void OpenSell(string tag) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (!CanOpen(1) || !DistanceOK(1, bid)) return;

   double sl = NormalizeDouble(bid + StopDollars, _Digits);
   double tp = NormalizeDouble(bid - TakeProfitDollars, _Digits);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(80);

   bool ok = trade.Sell(Lots, _Symbol, 0.0, sl, tp, tag);
   if (ok && trade.ResultDeal() > 0) {
      tradesToday++;
      lastSellTime = TimeCurrent();
   }
}

void ManagePositions() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double fast = Buf(hFast, 0, 0);
   double slow = Buf(hSlow, 0, 0);
   double rsi = Buf(hRSI, 0, 0);

   if (fast == EMPTY_VALUE || slow == EMPTY_VALUE || rsi == EMPTY_VALUE) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int stopsLevel = (int) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevel * point;

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong tk = PositionGetTicket(i);
      if (tk == 0 || !PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int) PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT);
      datetime posTime = (datetime) PositionGetInteger(POSITION_TIME);
      int mins = (int)((TimeCurrent() - posTime) / 60);

      if (UseBreakEven) {
         if (type == POSITION_TYPE_BUY && (bid - open) >= BreakEvenTrigger) {
            double newSL = NormalizeDouble(MathMin(open + BreakEvenLock, bid - minStopDist), _Digits);
            if (newSL > open && (sl == 0.0 || newSL > sl))
               trade.PositionModify(tk, newSL, tp);
         } else if (type == POSITION_TYPE_SELL && (open - ask) >= BreakEvenTrigger) {
            double newSL = NormalizeDouble(MathMax(open - BreakEvenLock, ask + minStopDist), _Digits);
            if (newSL < open && (sl == 0.0 || newSL < sl))
               trade.PositionModify(tk, newSL, tp);
         }
      }

      if (UseTrailing) {
         if (type == POSITION_TYPE_BUY && (bid - open) >= TrailStart) {
            double newSL = NormalizeDouble(bid - TrailDistance, _Digits);
            if (newSL > open && (sl == 0.0 || newSL > sl))
               trade.PositionModify(tk, newSL, tp);
         } else if (type == POSITION_TYPE_SELL && (open - ask) >= TrailStart) {
            double newSL = NormalizeDouble(ask + TrailDistance, _Digits);
            if (newSL < open && (sl == 0.0 || newSL < sl))
               trade.PositionModify(tk, newSL, tp);
         }
      }

      if (UseEarlyExit && mins >= EarlyExitAfterMinutes && profit <= -EarlyExitLossDollars) {
         bool invalidBuy = (type == POSITION_TYPE_BUY && (fast < slow || rsi < 48.0));
         bool invalidSell = (type == POSITION_TYPE_SELL && (fast > slow || rsi > 52.0));
         if (invalidBuy || invalidSell) {
            trade.PositionClose(tk);
            continue;
         }
      }

      if (UseTimeStop && mins >= MaxMinutesInTrade && profit < TimeStopMinProfit) {
         trade.PositionClose(tk);
         continue;
      }
   }
}

void EvaluateEntries() {
   if (!SpreadOK()) return;

   double fast = Buf(hFast, 0, 0);
   double slow = Buf(hSlow, 0, 0);
   double rsi = Buf(hRSI, 0, 0);
   double m5f = Buf(hM5Fast, 0, 0);
   double m5s = Buf(hM5Slow, 0, 0);
   double adx = Buf(hADX, 0, 0);

   if (fast == EMPTY_VALUE || slow == EMPTY_VALUE || rsi == EMPTY_VALUE ||
      m5f == EMPTY_VALUE || m5s == EMPTY_VALUE || adx == EMPTY_VALUE) return;

   if (adx < MinADX) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = (ask + bid) / 2.0;

   double m1open = iOpen(_Symbol, PERIOD_M1, 0);
   double prevClose = iClose(_Symbol, PERIOD_M1, 1);

   double body = MathAbs(mid - m1open);
   double move = mid - prevClose;
   double gap = MathAbs(fast - slow);

   double hi = RecentHigh(BreakoutLookback);
   double lo = RecentLow(BreakoutLookback);

   bool bullTrend = (fast > slow && m5f > m5s);
   bool bearTrend = (fast < slow && m5f < m5s);

   bool buyImpulse = (move >= MinImpulse && body >= MinBody);
   bool sellImpulse = (move <= -MinImpulse && body >= MinBody);

   bool strongBuy = (move >= StrongImpulse || ask > hi + BreakoutBuffer);
   bool strongSell = (move <= -StrongImpulse || bid < lo - BreakoutBuffer);

   if (bullTrend && adx >= MinADX + 4.0) CloseDirection(1);
   if (bearTrend && adx >= MinADX + 4.0) CloseDirection(0);

   if (bullTrend && gap >= MinM1EMAGap && rsi >= BuyRSIMin && buyImpulse) {
      OpenBuy("HAYBA_V575_BUY");
      if (rsi >= StrongBuyRSI && strongBuy)
         OpenBuy("HAYBA_V575_BUY_ADD");
   }

   if (bearTrend && gap >= MinM1EMAGap && rsi <= SellRSIMax && sellImpulse) {
      OpenSell("HAYBA_V575_SELL");
      if (rsi <= StrongSellRSI && strongSell)
         OpenSell("HAYBA_V575_SELL_ADD");
   }
}

int OnInit() {
   hFast = iMA(_Symbol, PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_M1, RSIPeriod, PRICE_CLOSE);

   hM5Fast = iMA(_Symbol, PERIOD_M5, M5FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hM5Slow = iMA(_Symbol, PERIOD_M5, M5SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hADX = iADX(_Symbol, PERIOD_M5, ADXPeriod);

   if (hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hRSI == INVALID_HANDLE ||
      hM5Fast == INVALID_HANDLE || hM5Slow == INVALID_HANDLE || hADX == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDay();
   Print("AL HAYBA v5.75 PROFIT LOCK loaded | rapid multi-position | tighter loss control");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if (hFast != INVALID_HANDLE) IndicatorRelease(hFast);
   if (hSlow != INVALID_HANDLE) IndicatorRelease(hSlow);
   if (hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if (hM5Fast != INVALID_HANDLE) IndicatorRelease(hM5Fast);
   if (hM5Slow != INVALID_HANDLE) IndicatorRelease(hM5Slow);
   if (hADX != INVALID_HANDLE) IndicatorRelease(hADX);

}

void OnTick() {
   ResetDay();
   ManagePositions();
   EvaluateEntries();
}
//+------------------------------------------------------------------+
