//+------------------------------------------------------------------+
//|       HOL_Trade_EA.mq5                                           |
//|       Highest Open / Lowest Open Trading System                  |
//|       Based on ForexFactory Highest Open / Lowest Open concept   |
//+------------------------------------------------------------------+
#property copyright "HOL Trade EA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// ENUMS
//====================================================================

enum ENUM_LOT_MODE {
   LOT_FIXED = 0,
   LOT_RISK_EQUITY = 1
};

//====================================================================
// INPUTS
//====================================================================

//--- General
input ulong            InpMagicNumber         = 575899;
input ENUM_TIMEFRAMES  InpSignalTimeframe     = PERIOD_M5;
input ENUM_TIMEFRAMES  InpReferenceTF         = PERIOD_H1;
input int              InpDeviationPoints     = 20;

//--- Lot management
input ENUM_LOT_MODE    InpLotMode             = LOT_FIXED;
input double           InpFixedLot            = 0.01;
input double           InpRiskPercent         = 1.0;

//--- Stop Loss
input bool             InpUseSL               = true;

// SL based on current daily high/low
input bool             InpSL_DailyHighLow     = true;

// Additional SL buffer
input double           InpSLBufferPoints      = 0.0;

//--- Take Profit
input bool             InpUseTP               = true;
input double           InpRiskReward          = 3.0;

//--- Trailing Stop
input bool             InpUseTrailing         = true;
input double           InpTrailingStartPts    = 500.0;
input double           InpTrailingDistancePts = 250.0;

//--- Trading
input bool             InpOnePositionOnly     = true;
input bool             InpOneBuyPerDay        = true;
input bool             InpOneSellPerDay       = true;

//--- Display
input bool             InpDrawLevels          = true;
input bool             InpDrawSignals         = true;
input color            InpHighestColor        = clrMaroon;
input color            InpLowestColor         = clrGreen;
input color            InpBuyArrowColor       = clrAqua;
input color            InpSellArrowColor      = clrYellow;

//====================================================================
// GLOBAL VARIABLES
//====================================================================

datetime g_dayStart = 0;

double   g_highestOpen = 0.0;
double   g_lowestOpen  = 0.0;

bool     g_buyTriggeredToday  = false;
bool     g_sellTriggeredToday = false;

datetime g_lastSignalBar = 0;

string PREFIX = "HOL_EA_";

//====================================================================
// INITIALIZATION
//====================================================================

int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   UpdateDailyLevels();

   Print("================================================");
   Print("HOL Trade EA initialized");
   Print("Symbol: ", _Symbol);
   Print("Reference TF: ", EnumToString(InpReferenceTF));
   Print("Signal TF: ", EnumToString(InpSignalTimeframe));
   Print("Lot mode: ", EnumToString(InpLotMode));
   Print("================================================");

   return (INIT_SUCCEEDED);
}

//====================================================================
// DEINITIALIZATION
//====================================================================

void OnDeinit(const int reason) {
   DeleteObjects();
}

//====================================================================
// MAIN TICK
//====================================================================

void OnTick() {
   //--- Update daily data
   UpdateDailyLevels();

   //--- Draw levels
   if (InpDrawLevels)
      DrawDailyLevels();

   //--- Manage trailing stop
   if (InpUseTrailing)
      ManageTrailingStops();

   //--- Check trading signal
   CheckSignals();
}

//====================================================================
// UPDATE DAILY LEVELS
//====================================================================

void UpdateDailyLevels() {
   datetime currentDayStart = iTime(_Symbol, PERIOD_D1, 0);

   if (currentDayStart <= 0)
      return;

   //--- New broker day
   if (currentDayStart != g_dayStart) {
      g_dayStart = currentDayStart;

      g_highestOpen = 0.0;
      g_lowestOpen = 0.0;

      g_buyTriggeredToday = false;
      g_sellTriggeredToday = false;

      CalculateHighestLowestOpen();

      Print("New broker day: ",
         TimeToString(g_dayStart, TIME_DATE | TIME_MINUTES));

      Print("Highest H1 Open = ", DoubleToString(g_highestOpen, _Digits));
      Print("Lowest H1 Open  = ", DoubleToString(g_lowestOpen, _Digits));
   } else {
      // Recalculate because new H1 candles can appear
      CalculateHighestLowestOpen();
   }
}

//====================================================================
// CALCULATE HIGHEST / LOWEST H1 OPEN
//====================================================================

void CalculateHighestLowestOpen() {
   if (g_dayStart <= 0)
      return;

   int bars = iBars(_Symbol, InpReferenceTF);

   if (bars <= 0)
      return;

   double highest = -DBL_MAX;
   double lowest = DBL_MAX;

   bool found = false;

   for (int shift = 0; shift < bars; shift++) {
      datetime barTime = iTime(_Symbol, InpReferenceTF, shift);

      if (barTime <= 0)
         continue;

      // Stop when we reach previous broker day
      if (barTime < g_dayStart)
         break;

      // Ignore future bars
      if (barTime > TimeCurrent())
         continue;

      double openPrice = iOpen(_Symbol, InpReferenceTF, shift);

      if (openPrice <= 0)
         continue;

      if (openPrice > highest)
         highest = openPrice;

      if (openPrice < lowest)
         lowest = openPrice;

      found = true;
   }

   if (found) {
      g_highestOpen = highest;
      g_lowestOpen = lowest;
   }
}

//====================================================================
// CHECK SIGNALS
//====================================================================

void CheckSignals() {
   if (g_dayStart <= 0)
      return;

   if (g_highestOpen <= 0 || g_lowestOpen <= 0)
      return;

   //--- Only use current signal timeframe candle
   datetime signalBarTime = iTime(_Symbol, InpSignalTimeframe, 0);

   if (signalBarTime <= 0)
      return;

   double signalOpen = iOpen(_Symbol, InpSignalTimeframe, 0);

   if (signalOpen <= 0)
      return;

   //--- Current market prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if (bid <= 0 || ask <= 0)
      return;

   //===============================================================
   // BUY SIGNAL
   //
   // M15 candle opens BELOW lowest H1 open.
   // Price then returns upward to lowest H1 open.
   //===============================================================

   bool buySetup = false;

   if (signalOpen < g_lowestOpen) {
      // Price must return to the level
      if (ask >= g_lowestOpen)
         buySetup = true;
   }

   if (buySetup) {
      if (!InpOneBuyPerDay || !g_buyTriggeredToday) {
         if (!InpOnePositionOnly || !HasOurPosition()) {
            OpenBuy(g_lowestOpen);
         }
      }
   }

   //===============================================================
   // SELL SIGNAL
   //
   // M15 candle opens ABOVE highest H1 open.
   // Price then returns downward to highest H1 open.
   //===============================================================

   bool sellSetup = false;

   if (signalOpen > g_highestOpen) {
      // Price must return to the level
      if (bid <= g_highestOpen)
         sellSetup = true;
   }

   if (sellSetup) {
      if (!InpOneSellPerDay || !g_sellTriggeredToday) {
         if (!InpOnePositionOnly || !HasOurPosition()) {
            OpenSell(g_highestOpen);
         }
      }
   }
}

//====================================================================
// OPEN BUY
//====================================================================

void OpenBuy(double signalLevel) {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if (ask <= 0)
      return;

   double sl = 0.0;
   double tp = 0.0;

   //--- Stop Loss
   if (InpUseSL) {
      if (InpSL_DailyHighLow) {
         double dailyLow = iLow(_Symbol, PERIOD_D1, 0);

         if (dailyLow > 0)
            sl = dailyLow - InpSLBufferPoints * _Point;
      }

      //--- Safety check
      if (sl <= 0 || sl >= ask) {
         Print("BUY: Invalid SL. Daily low = ",
            DoubleToString(sl, _Digits));
         return;
      }
   }

   //--- Calculate TP using Risk : Reward
   if (InpUseTP && InpUseSL) {
      double riskDistance = ask - sl;

      if (riskDistance <= 0)
         return;

      tp = ask + riskDistance * InpRiskReward;
   }

   //--- Calculate lot
   double lot = CalculateLot(ORDER_TYPE_BUY, ask, sl);

   if (lot <= 0) {
      Print("BUY: Invalid lot size.");
      return;
   }

   //--- Normalize prices
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   //--- Make sure SL/TP satisfy broker distance
   AdjustBuyStops(ask, sl, tp);

   string comment = "HOL BUY";

   bool result = trade.Buy(
      lot,
      _Symbol,
      0.0,
      sl,
      tp,
      comment
   );

   if (result) {
      g_buyTriggeredToday = true;

      Print("========================================");
      Print("HOL BUY OPENED");
      Print("Lot       = ", DoubleToString(lot, 2));
      Print("Entry     = ", DoubleToString(ask, _Digits));
      Print("SL        = ", DoubleToString(sl, _Digits));
      Print("TP        = ", DoubleToString(tp, _Digits));
      Print("RR        = ", DoubleToString(InpRiskReward, 2));
      Print("========================================");

      if (InpDrawSignals)
         DrawBuyArrow();
   } else {
      Print("BUY failed.");
      Print("Retcode = ", trade.ResultRetcode());
      Print("Comment = ", trade.ResultRetcodeDescription());
   }
}

//====================================================================
// OPEN SELL
//====================================================================

void OpenSell(double signalLevel) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (bid <= 0)
      return;

   double sl = 0.0;
   double tp = 0.0;

   //--- Stop Loss
   if (InpUseSL) {
      if (InpSL_DailyHighLow) {
         double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);

         if (dailyHigh > 0)
            sl = dailyHigh + InpSLBufferPoints * _Point;
      }

      //--- Safety check
      if (sl <= 0 || sl <= bid) {
         Print("SELL: Invalid SL. Daily high = ",
            DoubleToString(sl, _Digits));
         return;
      }
   }

   //--- Calculate TP using Risk : Reward
   if (InpUseTP && InpUseSL) {
      double riskDistance = sl - bid;

      if (riskDistance <= 0)
         return;

      tp = bid - riskDistance * InpRiskReward;
   }

   //--- Calculate lot
   double lot = CalculateLot(ORDER_TYPE_SELL, bid, sl);

   if (lot <= 0) {
      Print("SELL: Invalid lot size.");
      return;
   }

   //--- Normalize
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   //--- Make sure SL/TP satisfy broker distance
   AdjustSellStops(bid, sl, tp);

   string comment = "HOL SELL";

   bool result = trade.Sell(
      lot,
      _Symbol,
      0.0,
      sl,
      tp,
      comment
   );

   if (result) {
      g_sellTriggeredToday = true;

      Print("========================================");
      Print("HOL SELL OPENED");
      Print("Lot       = ", DoubleToString(lot, 2));
      Print("Entry     = ", DoubleToString(bid, _Digits));
      Print("SL        = ", DoubleToString(sl, _Digits));
      Print("TP        = ", DoubleToString(tp, _Digits));
      Print("RR        = ", DoubleToString(InpRiskReward, 2));
      Print("========================================");

      if (InpDrawSignals)
         DrawSellArrow();
   } else {
      Print("SELL failed.");
      Print("Retcode = ", trade.ResultRetcode());
      Print("Comment = ", trade.ResultRetcodeDescription());
   }
}

//====================================================================
// CALCULATE LOT
//====================================================================

double CalculateLot(
   ENUM_ORDER_TYPE orderType,
   double entryPrice,
   double stopLoss
) {
   //===============================================================
   // FIXED LOT
   //===============================================================

   if (InpLotMode == LOT_FIXED) {
      return NormalizeVolume(InpFixedLot);
   }

   //===============================================================
   // RISK % OF EQUITY
   //===============================================================

   if (!InpUseSL) {
      Print("Risk percentage mode requires Stop Loss.");
      return 0.0;
   }

   if (stopLoss <= 0)
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if (equity <= 0)
      return 0.0;

   double riskMoney = equity * InpRiskPercent / 100.0;

   if (riskMoney <= 0)
      return 0.0;

   //--- Calculate loss for 1 lot
   double profit = 0.0;

   bool calculated = OrderCalcProfit(
      orderType,
      _Symbol,
      1.0,
      entryPrice,
      stopLoss,
      profit
   );

   if (!calculated) {
      Print("OrderCalcProfit failed. Error = ",
         GetLastError());
      return 0.0;
   }

   double lossPerLot = MathAbs(profit);

   if (lossPerLot <= 0)
      return 0.0;

   double lot = riskMoney / lossPerLot;

   return NormalizeVolume(lot);
}

//====================================================================
// NORMALIZE LOT
//====================================================================

double NormalizeVolume(double volume) {
   double minLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_MIN
   );

   double maxLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_MAX
   );

   double stepLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_STEP
   );

   if (stepLot <= 0)
      stepLot = 0.01;

   if (volume < minLot)
      volume = minLot;

   if (volume > maxLot)
      volume = maxLot;

   volume = MathFloor(volume / stepLot) * stepLot;

   if (volume < minLot)
      volume = minLot;

   return NormalizeDouble(volume, 2);
}

//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(double price) {
   if (price <= 0)
      return 0.0;

   return NormalizeDouble(price, _Digits);
}

//====================================================================
// ADJUST BUY STOPS
//====================================================================

void AdjustBuyStops(
   double entry,
   double & sl,
   double & tp
) {
   long stopsLevel = SymbolInfoInteger(
      _Symbol,
      SYMBOL_TRADE_STOPS_LEVEL
   );

   double minimumDistance = stopsLevel * _Point;

   if (minimumDistance <= 0)
      return;

   //--- BUY SL must be below entry
   if (InpUseSL) {
      if (entry - sl < minimumDistance)
         sl = entry - minimumDistance;
   }

   //--- BUY TP must be above entry
   if (InpUseTP) {
      if (tp > 0 && tp - entry < minimumDistance)
         tp = entry + minimumDistance;
   }

   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
}

//====================================================================
// ADJUST SELL STOPS
//====================================================================

void AdjustSellStops(
   double entry,
   double & sl,
   double & tp
) {
   long stopsLevel = SymbolInfoInteger(
      _Symbol,
      SYMBOL_TRADE_STOPS_LEVEL
   );

   double minimumDistance = stopsLevel * _Point;

   if (minimumDistance <= 0)
      return;

   //--- SELL SL must be above entry
   if (InpUseSL) {
      if (sl - entry < minimumDistance)
         sl = entry + minimumDistance;
   }

   //--- SELL TP must be below entry
   if (InpUseTP) {
      if (tp > 0 && entry - tp < minimumDistance)
         tp = entry - minimumDistance;
   }

   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
}

//====================================================================
// CHECK OUR POSITION
//====================================================================

bool HasOurPosition() {
   int total = PositionsTotal();

   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);

      if (ticket == 0)
         continue;

      if (!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);

      if (symbol != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);

      if ((ulong) magic != InpMagicNumber)
         continue;

      return true;
   }

   return false;
}

//====================================================================
// TRAILING STOP
//====================================================================

void ManageTrailingStops() {
   int total = PositionsTotal();

   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);

      if (ticket == 0)
         continue;

      if (!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);

      if (symbol != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);

      if ((ulong) magic != InpMagicNumber)
         continue;

      long positionType =
         PositionGetInteger(POSITION_TYPE);

      double openPrice =
         PositionGetDouble(POSITION_PRICE_OPEN);

      double currentSL =
         PositionGetDouble(POSITION_SL);

      double currentTP =
         PositionGetDouble(POSITION_TP);

      double bid =
         SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double ask =
         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //=============================================================
      // BUY TRAILING
      //=============================================================

      if (positionType == POSITION_TYPE_BUY) {
         double profitPoints =
            (bid - openPrice) / _Point;

         if (profitPoints < InpTrailingStartPts)
            continue;

         double newSL =
            bid - InpTrailingDistancePts * _Point;

         newSL = NormalizePrice(newSL);

         // New SL must be better than existing SL
         if (currentSL > 0 && newSL <= currentSL)
            continue;

         // SL must remain below current price
         if (newSL >= bid)
            continue;

         if (IsStopDistanceValid(true, bid, newSL)) {
            bool modified =
               trade.PositionModify(
                  ticket,
                  newSL,
                  currentTP
               );

            if (!modified) {
               Print("BUY trailing modification failed. Ticket=",
                  ticket,
                  " Retcode=",
                  trade.ResultRetcode(),
                  " ",
                  trade.ResultRetcodeDescription());
            }
         }
      }

      //=============================================================
      // SELL TRAILING
      //=============================================================

      if (positionType == POSITION_TYPE_SELL) {
         double profitPoints =
            (openPrice - ask) / _Point;

         if (profitPoints < InpTrailingStartPts)
            continue;

         double newSL =
            ask + InpTrailingDistancePts * _Point;

         newSL = NormalizePrice(newSL);

         // New SL must be better than existing SL
         if (currentSL > 0 && newSL >= currentSL)
            continue;

         // SL must remain above current price
         if (newSL <= ask)
            continue;

         if (IsStopDistanceValid(false, ask, newSL)) {
            bool modified =
               trade.PositionModify(
                  ticket,
                  newSL,
                  currentTP
               );

            if (!modified) {
               Print("SELL trailing modification failed. Ticket=",
                  ticket,
                  " Retcode=",
                  trade.ResultRetcode(),
                  " ",
                  trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

//====================================================================
// CHECK STOP DISTANCE
//====================================================================

bool IsStopDistanceValid(
   bool isBuy,
   double currentPrice,
   double stopPrice
) {
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minimumDistance =
      stopsLevel * _Point;

   if (minimumDistance <= 0)
      return true;

   if (isBuy) {
      if (currentPrice - stopPrice < minimumDistance)
         return false;
   } else {
      if (stopPrice - currentPrice < minimumDistance)
         return false;
   }

   return true;
}

//====================================================================
// DRAW DAILY LEVELS
//====================================================================

void DrawDailyLevels() {
   if (g_dayStart <= 0)
      return;

   string highestName = PREFIX + "HIGHEST_OPEN";
   string lowestName = PREFIX + "LOWEST_OPEN";

   //--- Highest
   if (g_highestOpen > 0) {
      if (ObjectFind(0, highestName) < 0) {
         ObjectCreate(
            0,
            highestName,
            OBJ_HLINE,
            0,
            0,
            g_highestOpen
         );
      }

      ObjectSetDouble(
         0,
         highestName,
         OBJPROP_PRICE,
         g_highestOpen
      );

      ObjectSetInteger(
         0,
         highestName,
         OBJPROP_COLOR,
         InpHighestColor
      );

      ObjectSetInteger(
         0,
         highestName,
         OBJPROP_STYLE,
         STYLE_DASHDOTDOT
      );

      ObjectSetInteger(
         0,
         highestName,
         OBJPROP_WIDTH,
         1
      );

      ObjectSetString(
         0,
         highestName,
         OBJPROP_TEXT,
         "Highest H1 Open"
      );
      
      ObjectSetInteger(0, highestName, OBJPROP_BACK, true);
   }

   //--- Lowest
   if (g_lowestOpen > 0) {
      if (ObjectFind(0, lowestName) < 0) {
         ObjectCreate(
            0,
            lowestName,
            OBJ_HLINE,
            0,
            0,
            g_lowestOpen
         );
      }

      ObjectSetDouble(
         0,
         lowestName,
         OBJPROP_PRICE,
         g_lowestOpen
      );

      ObjectSetInteger(
         0,
         lowestName,
         OBJPROP_COLOR,
         InpLowestColor
      );

      ObjectSetInteger(
         0,
         lowestName,
         OBJPROP_STYLE,
         STYLE_DASHDOTDOT
      );

      ObjectSetInteger(
         0,
         lowestName,
         OBJPROP_WIDTH,
         1
      );

      ObjectSetString(
         0,
         lowestName,
         OBJPROP_TEXT,
         "Lowest H1 Open"
      );
      
      ObjectSetInteger(0, lowestName, OBJPROP_BACK, true);
   }
}

//====================================================================
// DRAW BUY ARROW
//====================================================================

void DrawBuyArrow() {
   datetime time = TimeCurrent();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string name =
      PREFIX +
      "BUY_" +
      IntegerToString((int) time);

   if (ObjectCreate(
         0,
         name,
         OBJ_ARROW,
         0,
         time,
         price
      )) {
      ObjectSetInteger(
         0,
         name,
         OBJPROP_ARROWCODE,
         233
      );

      ObjectSetInteger(
         0,
         name,
         OBJPROP_COLOR,
         InpBuyArrowColor
      );

      ObjectSetInteger(
         0,
         name,
         OBJPROP_WIDTH,
         2
      );
   }
}

//====================================================================
// DRAW SELL ARROW
//====================================================================

void DrawSellArrow() {
   datetime time = TimeCurrent();
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   string name =
      PREFIX +
      "SELL_" +
      IntegerToString((int) time);

   if (ObjectCreate(
         0,
         name,
         OBJ_ARROW,
         0,
         time,
         price
      )) {
      ObjectSetInteger(
         0,
         name,
         OBJPROP_ARROWCODE,
         234
      );

      ObjectSetInteger(
         0,
         name,
         OBJPROP_COLOR,
         InpSellArrowColor
      );

      ObjectSetInteger(
         0,
         name,
         OBJPROP_WIDTH,
         2
      );
   }
}

//====================================================================
// DELETE EA OBJECTS
//====================================================================

void DeleteObjects() {
   int total = ObjectsTotal(0);

   for (int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i);

      if (StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| END OF EA                                                        |
//+------------------------------------------------------------------+
