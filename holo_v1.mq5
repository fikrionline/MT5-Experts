//+------------------------------------------------------------------+
//|                                                   HOLO_V1.mq5    |
//| Highest Open / Lowest Open Trade                                 |
//| Version 1 - Clean implementation of the basic HOLO rules         |
//+------------------------------------------------------------------+
#property copyright "HOLO V1"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUTS
//====================================================================

//--- Trading
input ulong   InpMagicNumber          = 590623;
input double  InpRiskPercent          = 1.0;       // Risk per trade (%)
input double  InpFixedLot             = 0.0;       // 0 = use risk %
input int     InpMaxTradesPerDay      = 2;
input int     InpMaxSpreadPoints      = 100;
input int     InpDeviationPoints      = 10;

//--- HOLO entry
input bool    InpUseM15Confirmation   = true;
input double  InpBreakBufferPips      = 0.0;

//--- Initial stop
input double  InpSLBufferPips         = 0.0;

//--- Trade management
input bool    InpUseBreakEven         = true;
input double  InpBE1TriggerPips       = 5.0;
input double  InpBE1OffsetPips        = 1.0;

input bool    InpUseBE2               = true;
input double  InpBE2TriggerPips       = 10.0;
input double  InpBE2OffsetPips        = 5.0;

//--- Optional trailing stop
input bool    InpUseTrailing          = false;
input double  InpTrailingStartPips    = 10.0;
input double  InpTrailingDistancePips = 5.0;

//--- Chart
input bool    InpDrawLevels            = true;
input color   InpHighestColor          = clrRed;
input color   InpLowestColor           = clrDodgerBlue;
input int     InpLineWidth             = 1;

//====================================================================
// GLOBAL STATE
//====================================================================

datetime g_dayStart = 0;

double   g_highestOpen = 0.0;
double   g_lowestOpen  = 0.0;

bool     g_highBroken = false;
bool     g_lowBroken  = false;

bool     g_highTradeTaken = false;
bool     g_lowTradeTaken  = false;

//====================================================================
// CONSTANTS
//====================================================================

string HIGH_LINE_NAME = "HOLO_V1_HIGHEST_OPEN";
string LOW_LINE_NAME  = "HOLO_V1_LOWEST_OPEN";

//====================================================================
// INITIALIZATION
//====================================================================

int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_dayStart = GetBrokerDayStart();

   if (g_dayStart == 0) {
      Print("HOLO V1: Could not determine broker day start.");
      return INIT_FAILED;
   }

   UpdateHOLOLevels();

   Print("HOLO V1 initialized on ", _Symbol);

   return INIT_SUCCEEDED;
}

//====================================================================
// DEINITIALIZATION
//====================================================================

void OnDeinit(const int reason) {
   if (InpDrawLevels) {
      ObjectDelete(0, HIGH_LINE_NAME);
      ObjectDelete(0, LOW_LINE_NAME);
   }

   Comment("");
}

//====================================================================
// MAIN TICK
//====================================================================

void OnTick() {
   datetime currentDay = GetBrokerDayStart();

   if (currentDay == 0)
      return;

   //--- New broker day
   if (currentDay != g_dayStart) {
      g_dayStart = currentDay;

      g_highBroken = false;
      g_lowBroken = false;

      g_highTradeTaken = false;
      g_lowTradeTaken = false;

      g_highestOpen = 0.0;
      g_lowestOpen = 0.0;
   }

   //--- Update H1 highest/lowest opens
   UpdateHOLOLevels();

   //--- Manage existing positions
   ManagePositions();

   //--- Entry logic
   CheckEntries();

   //--- Chart information
   UpdateChartComment();
}

//====================================================================
// GET BROKER DAY START
//====================================================================

datetime GetBrokerDayStart() {
   datetime now = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now, dt);

   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;

   return StructToTime(dt);
}

//====================================================================
// UPDATE H1 LEVELS
//====================================================================

void UpdateHOLOLevels() {
   datetime now = TimeCurrent();

   double highest = 0.0;
   double lowest = 0.0;

   bool found = false;

   //--- Look through H1 bars belonging to today's broker day.
   //--- We intentionally include only bars that have already opened.
   int bars = Bars(_Symbol, PERIOD_H1);

   if (bars <= 0)
      return;

   for (int i = 0; i < bars; i++) {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);

      if (barTime == 0)
         continue;

      // Older than today's broker day
      if (barTime < g_dayStart)
         break;

      // Do not use future bars
      if (barTime > now)
         continue;

      double openPrice = iOpen(_Symbol, PERIOD_H1, i);

      if (openPrice <= 0.0)
         continue;

      if (!found) {
         highest = openPrice;
         lowest = openPrice;
         found = true;
      } else {
         if (openPrice > highest)
            highest = openPrice;

         if (openPrice < lowest)
            lowest = openPrice;
      }
   }

   if (!found)
      return;

   g_highestOpen = highest;
   g_lowestOpen = lowest;

   if (InpDrawLevels)
      DrawHOLOLevels();
}

//====================================================================
// DRAW HOLO LEVELS
//====================================================================

void DrawHOLOLevels() {
   DrawHorizontalLine(
      HIGH_LINE_NAME,
      g_highestOpen,
      InpHighestColor
   );

   DrawHorizontalLine(
      LOW_LINE_NAME,
      g_lowestOpen,
      InpLowestColor
   );
}

//====================================================================
// DRAW HORIZONTAL LINE
//====================================================================

void DrawHorizontalLine(string name, double price, color lineColor) {
   if (ObjectFind(0, name) < 0) {
      ObjectCreate(
         0,
         name,
         OBJ_HLINE,
         0,
         0,
         price
      );
   }

   ObjectSetDouble(
      0,
      name,
      OBJPROP_PRICE,
      price
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      lineColor
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_WIDTH,
      InpLineWidth
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_STYLE,
      STYLE_SOLID
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_SELECTABLE,
      false
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_SELECTED,
      false
   );
}

//====================================================================
// CHECK ENTRIES
//====================================================================

void CheckEntries() {
   if (g_highestOpen <= 0.0 || g_lowestOpen <= 0.0)
      return;

   if (!TradingConditionsOK())
      return;

   if (GetTradesToday() >= InpMaxTradesPerDay)
      return;

   MqlTick tick;

   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double breakBuffer = PipsToPrice(InpBreakBufferPips);

   //-----------------------------------------------------------------
   // SELL SETUP
   //
   // Price must first move ABOVE the highest H1 open.
   // Then price must return DOWN to the highest H1 open.
   //-----------------------------------------------------------------

   if (!g_highTradeTaken) {
      // First step: price goes above the highest open
      if (tick.bid > g_highestOpen + breakBuffer) {
         g_highBroken = true;
      }

      // Second step: price returns to the highest open
      if (g_highBroken &&
         tick.bid <= g_highestOpen) {
         if (!InpUseM15Confirmation || M15ShortConfirmation()) {
            if (OpenSell()) {
               g_highTradeTaken = true;
               g_highBroken = false;
            }
         }
      }
   }

   //-----------------------------------------------------------------
   // BUY SETUP
   //
   // Price must first move BELOW the lowest H1 open.
   // Then price must return UP to the lowest H1 open.
   //-----------------------------------------------------------------

   if (!g_lowTradeTaken) {
      // First step: price goes below the lowest open
      if (tick.ask < g_lowestOpen - breakBuffer) {
         g_lowBroken = true;
      }

      // Second step: price returns to the lowest open
      if (g_lowBroken &&
         tick.ask >= g_lowestOpen) {
         if (!InpUseM15Confirmation || M15LongConfirmation()) {
            if (OpenBuy()) {
               g_lowTradeTaken = true;
               g_lowBroken = false;
            }
         }
      }
   }
}

//====================================================================
// M15 SHORT CONFIRMATION
//
// Original thread clarification:
// M15 bar must open ABOVE the highest H1 open before short entry.
//====================================================================

bool M15ShortConfirmation() {
   double m15Open = iOpen(_Symbol, PERIOD_M15, 0);

   if (m15Open <= 0.0)
      return false;

   return (m15Open > g_highestOpen);
}

//====================================================================
// M15 LONG CONFIRMATION
//
// M15 bar must open BELOW the lowest H1 open before long entry.
//====================================================================

bool M15LongConfirmation() {
   double m15Open = iOpen(_Symbol, PERIOD_M15, 0);

   if (m15Open <= 0.0)
      return false;

   return (m15Open < g_lowestOpen);
}

//====================================================================
// OPEN BUY
//====================================================================

bool OpenBuy() {
   MqlTick tick;

   if (!SymbolInfoTick(_Symbol, tick))
      return false;

   double entry = tick.ask;

   // Current daily low
   double dailyLow = iLow(_Symbol, PERIOD_D1, 0);

   if (dailyLow <= 0.0)
      return false;

   double sl = dailyLow - PipsToPrice(InpSLBufferPips);

   sl = NormalizePrice(sl);

   //--- SL must be below entry
   if (sl >= entry) {
      Print("HOLO V1 BUY rejected: daily-low SL is not below entry.");
      return false;
   }

   //--- Respect broker stop distance
   sl = AdjustStopForBuy(sl, entry);

   double volume = CalculateLotSize(
      ORDER_TYPE_BUY,
      entry,
      sl
   );

   if (volume <= 0.0)
      return false;

   ResetLastError();

   bool result = trade.Buy(
      volume,
      _Symbol,
      0.0,
      sl,
      0.0,
      "HOLO V1 BUY"
   );

   if (!result) {
      Print(
         "HOLO V1 BUY failed. Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }

   Print(
      "HOLO V1 BUY opened. Volume=",
      volume,
      " Entry=",
      entry,
      " SL=",
      sl
   );

   return true;
}

//====================================================================
// OPEN SELL
//====================================================================

bool OpenSell() {
   MqlTick tick;

   if (!SymbolInfoTick(_Symbol, tick))
      return false;

   double entry = tick.bid;

   // Current daily high
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);

   if (dailyHigh <= 0.0)
      return false;

   double sl = dailyHigh + PipsToPrice(InpSLBufferPips);

   sl = NormalizePrice(sl);

   //--- SL must be above entry
   if (sl <= entry) {
      Print("HOLO V1 SELL rejected: daily-high SL is not above entry.");
      return false;
   }

   //--- Respect broker stop distance
   sl = AdjustStopForSell(sl, entry);

   double volume = CalculateLotSize(
      ORDER_TYPE_SELL,
      entry,
      sl
   );

   if (volume <= 0.0)
      return false;

   ResetLastError();

   bool result = trade.Sell(
      volume,
      _Symbol,
      0.0,
      sl,
      0.0,
      "HOLO V1 SELL"
   );

   if (!result) {
      Print(
         "HOLO V1 SELL failed. Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }

   Print(
      "HOLO V1 SELL opened. Volume=",
      volume,
      " Entry=",
      entry,
      " SL=",
      sl
   );

   return true;
}

//====================================================================
// MANAGE POSITIONS
//====================================================================

void ManagePositions() {
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

      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE) PositionGetInteger(POSITION_TYPE);

      double openPrice =
         PositionGetDouble(POSITION_PRICE_OPEN);

      double currentSL =
         PositionGetDouble(POSITION_SL);

      MqlTick tick;

      if (!SymbolInfoTick(_Symbol, tick))
         continue;

      double profitPips = 0.0;

      if (type == POSITION_TYPE_BUY) {
         profitPips =
            PriceToPips(tick.bid - openPrice);
      } else if (type == POSITION_TYPE_SELL) {
         profitPips =
            PriceToPips(openPrice - tick.ask);
      }

      //----------------------------------------------------------------
      // BE + 1 at +5 pips
      //----------------------------------------------------------------

      if (InpUseBreakEven &&
         profitPips >= InpBE1TriggerPips) {
         double newSL = 0.0;

         if (type == POSITION_TYPE_BUY) {
            newSL =
               openPrice +
               PipsToPrice(InpBE1OffsetPips);

            newSL = NormalizePrice(newSL);

            if (newSL > currentSL)
               ModifyPosition(ticket, newSL);
         } else if (type == POSITION_TYPE_SELL) {
            newSL =
               openPrice -
               PipsToPrice(InpBE1OffsetPips);

            newSL = NormalizePrice(newSL);

            if (currentSL == 0.0 || newSL < currentSL)
               ModifyPosition(ticket, newSL);
         }
      }

      //----------------------------------------------------------------
      // BE + 5 at +10 pips
      //----------------------------------------------------------------

      if (InpUseBE2 &&
         profitPips >= InpBE2TriggerPips) {
         double newSL = 0.0;

         if (type == POSITION_TYPE_BUY) {
            newSL =
               openPrice +
               PipsToPrice(InpBE2OffsetPips);

            newSL = NormalizePrice(newSL);

            if (newSL > currentSL)
               ModifyPosition(ticket, newSL);
         } else if (type == POSITION_TYPE_SELL) {
            newSL =
               openPrice -
               PipsToPrice(InpBE2OffsetPips);

            newSL = NormalizePrice(newSL);

            if (currentSL == 0.0 || newSL < currentSL)
               ModifyPosition(ticket, newSL);
         }
      }

      //----------------------------------------------------------------
      // Optional trailing
      //----------------------------------------------------------------

      if (InpUseTrailing &&
         profitPips >= InpTrailingStartPips) {
         double newSL = 0.0;

         if (type == POSITION_TYPE_BUY) {
            newSL =
               tick.bid -
               PipsToPrice(InpTrailingDistancePips);

            newSL = NormalizePrice(newSL);

            if (newSL > currentSL)
               ModifyPosition(ticket, newSL);
         } else if (type == POSITION_TYPE_SELL) {
            newSL =
               tick.ask +
               PipsToPrice(InpTrailingDistancePips);

            newSL = NormalizePrice(newSL);

            if (currentSL == 0.0 || newSL < currentSL)
               ModifyPosition(ticket, newSL);
         }
      }
   }
}

//====================================================================
// MODIFY POSITION
//====================================================================

bool ModifyPosition(ulong ticket, double newSL) {
   if (!PositionSelectByTicket(ticket))
      return false;

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE) PositionGetInteger(POSITION_TYPE);

   MqlTick tick;

   if (!SymbolInfoTick(_Symbol, tick))
      return false;

   //--- Make sure SL is still valid at the current market price
   if (type == POSITION_TYPE_BUY) {
      newSL = AdjustStopForBuy(newSL, tick.bid);
   } else {
      newSL = AdjustStopForSell(newSL, tick.ask);
   }

   newSL = NormalizePrice(newSL);

   double currentTP =
      PositionGetDouble(POSITION_TP);

   ResetLastError();

   bool result =
      trade.PositionModify(
         ticket,
         newSL,
         currentTP
      );

   if (!result) {
      Print(
         "HOLO V1 PositionModify failed. Ticket=",
         ticket,
         " Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }

   return true;
}

//====================================================================
// TRADING CONDITIONS
//====================================================================

bool TradingConditionsOK() {
   MqlTick tick;

   if (!SymbolInfoTick(_Symbol, tick))
      return false;

   double spreadPoints =
      (tick.ask - tick.bid) / _Point;

   if (spreadPoints > InpMaxSpreadPoints)
      return false;

   return true;
}

//====================================================================
// COUNT TODAY'S ENTRY DEALS
//
// We use account history so the daily trade count survives an EA
// restart. HistorySelect works with server time. 
//====================================================================

int GetTradesToday() {
   datetime from = g_dayStart;
   datetime to = TimeCurrent();

   if (!HistorySelect(from, to))
      return 0;

   int count = 0;

   int deals = HistoryDealsTotal();

   for (int i = 0; i < deals; i++) {
      ulong ticket = HistoryDealGetTicket(i);

      if (ticket == 0)
         continue;

      string symbol =
         HistoryDealGetString(
            ticket,
            DEAL_SYMBOL
         );

      if (symbol != _Symbol)
         continue;

      long magic =
         HistoryDealGetInteger(
            ticket,
            DEAL_MAGIC
         );

      if ((ulong) magic != InpMagicNumber)
         continue;

      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY) HistoryDealGetInteger(
            ticket,
            DEAL_ENTRY
         );

      if (entry != DEAL_ENTRY_IN)
         continue;

      ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE) HistoryDealGetInteger(
            ticket,
            DEAL_TYPE
         );

      if (type == DEAL_TYPE_BUY ||
         type == DEAL_TYPE_SELL) {
         count++;
      }
   }

   return count;
}

//====================================================================
// CALCULATE LOT SIZE
//====================================================================

double CalculateLotSize(
   ENUM_ORDER_TYPE orderType,
   double entryPrice,
   double stopPrice
) {
   //--- Fixed lot mode
   if (InpFixedLot > 0.0)
      return NormalizeVolume(InpFixedLot);

   if (InpRiskPercent <= 0.0)
      return 0.0;

   double riskMoney =
      AccountInfoDouble(ACCOUNT_EQUITY) *
      InpRiskPercent /
      100.0;

   if (riskMoney <= 0.0)
      return 0.0;

   double profitForOneLot = 0.0;

   if (!OrderCalcProfit(
         orderType,
         _Symbol,
         1.0,
         entryPrice,
         stopPrice,
         profitForOneLot)) {
      Print(
         "OrderCalcProfit failed. Error=",
         GetLastError()
      );

      return 0.0;
   }

   double lossPerLot = MathAbs(profitForOneLot);

   if (lossPerLot <= 0.0)
      return 0.0;

   double volume =
      riskMoney / lossPerLot;

   return NormalizeVolume(volume);
}

//====================================================================
// NORMALIZE VOLUME
//====================================================================

double NormalizeVolume(double volume) {
   double minVolume =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maxVolume =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   double stepVolume =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   if (stepVolume <= 0.0)
      return 0.0;

   volume =
      MathFloor(volume / stepVolume) *
      stepVolume;

   volume =
      MathMax(volume, minVolume);

   volume =
      MathMin(volume, maxVolume);

   int volumeDigits = 2;

   if (stepVolume == 1.0)
      volumeDigits = 0;
   else if (stepVolume == 0.1)
      volumeDigits = 1;
   else if (stepVolume == 0.01)
      volumeDigits = 2;
   else if (stepVolume == 0.001)
      volumeDigits = 3;

   return NormalizeDouble(
      volume,
      volumeDigits
   );
}

//====================================================================
// PIPS -> PRICE
//====================================================================

double PipsToPrice(double pips) {
   // 5-digit / 3-digit symbols:
   // 1 pip = 10 points
   //
   // 4-digit / 2-digit symbols:
   // 1 pip = 1 point

   if (_Digits == 3 || _Digits == 5)
      return pips * _Point * 10.0;

   return pips * _Point;
}

//====================================================================
// PRICE -> PIPS
//====================================================================

double PriceToPips(double priceDistance) {
   if (_Digits == 3 || _Digits == 5)
      return priceDistance / (_Point * 10.0);

   return priceDistance / _Point;
}

//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(double price) {
   return NormalizeDouble(
      price,
      _Digits
   );
}

//====================================================================
// ADJUST BUY STOP
//====================================================================

double AdjustStopForBuy(
   double sl,
   double referencePrice
) {
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minimumDistance =
      stopsLevel * _Point;

   double maximumSL =
      referencePrice -
      minimumDistance;

   if (sl > maximumSL)
      sl = maximumSL;

   return NormalizePrice(sl);
}

//====================================================================
// ADJUST SELL STOP
//====================================================================

double AdjustStopForSell(
   double sl,
   double referencePrice
) {
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minimumDistance =
      stopsLevel * _Point;

   double minimumSL =
      referencePrice +
      minimumDistance;

   if (sl < minimumSL)
      sl = minimumSL;

   return NormalizePrice(sl);
}

//====================================================================
// CHART COMMENT
//====================================================================

void UpdateChartComment() {
   if (g_highestOpen <= 0.0 ||
      g_lowestOpen <= 0.0) {
      Comment("HOLO V1\nWaiting for H1 data...");
      return;
   }

   MqlTick tick;

   if (!SymbolInfoTick(_Symbol, tick))
      return;

   string highState =
      g_highTradeTaken ?
      "TRADE TAKEN" :
      (g_highBroken ?
         "BROKEN - WAITING RETURN" :
         "WAITING FOR BREAK");

   string lowState =
      g_lowTradeTaken ?
      "TRADE TAKEN" :
      (g_lowBroken ?
         "BROKEN - WAITING RETURN" :
         "WAITING FOR BREAK");

   int tradesToday = GetTradesToday();

   Comment(
      "HOLO V1\n",
      "-----------------------------\n",
      "Symbol: ", _Symbol, "\n",
      "Highest H1 Open: ",
      DoubleToString(g_highestOpen, _Digits), "\n",
      "Highest state: ", highState, "\n",
      "\n",
      "Lowest H1 Open: ",
      DoubleToString(g_lowestOpen, _Digits), "\n",
      "Lowest state: ", lowState, "\n",
      "\n",
      "Trades today: ",
      tradesToday,
      " / ",
      InpMaxTradesPerDay, "\n",
      "M15 confirmation: ",
      (InpUseM15Confirmation ? "ON" : "OFF")
   );
}
//+------------------------------------------------------------------+
