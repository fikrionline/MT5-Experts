//+------------------------------------------------------------------+
//|                                        h_order_v3.mq5            |
//|      4 Pending Order Buttons + SL + Information Panel            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
//--- Indicator
input ENUM_TIMEFRAMES markTF  = PERIOD_H1; // Time Frame Target
input bool  ShowAlert         = true;      // Turn on Alert
input int   AlertDelaySeconds = 8;         // Alert Delay in Second
input color ColorOpen         = clrPurple;
input color ColorHighest      = clrMaroon;
input color ColorLowest       = clrDarkGreen;

//--- Trade
input double InpLotSize       = 0.01;      // Lot size
input double RiskReward       = 2.2;       // Risk Reward

//--- Button settings
input int InpButtonWidth      = 123;       // Button width
input int InpButtonHeight     = 33;        // Button height
input int InpButtonX          = 10;        // Button X position
input int InpButtonY          = 25;        // Button Y position
input int InpButtonGap        = 10;        // Gap between buttons

//--- Information panel
input int InpInfoX            = 10;        // Information X position
input int InpInfoY            = 70;        // Information Y position
input int InpInfoFontSize     = 8;         // Information font size
input color InpInfoColor      = clrWhite;  // Information color

datetime LastAlertTime        = 0;
string   objectName           = "holo";
string   theWarning           = "";

//+------------------------------------------------------------------+
//| BUTTON NAMES                                                     |
//+------------------------------------------------------------------+
string BUY_STOP_BUTTON     = "EA_BUY_STOP_BUTTON";
string SELL_STOP_BUTTON    = "EA_SELL_STOP_BUTTON";
string BUY_LIMIT_BUTTON    = "EA_BUY_LIMIT_BUTTON";
string SELL_LIMIT_BUTTON   = "EA_SELL_LIMIT_BUTTON";
string DEL_PENDING_BUTTON  = "EA_CLEAR_PENDING_BUTTON";

//+------------------------------------------------------------------+
//| INFORMATION OBJECTS                                              |
//+------------------------------------------------------------------+
string INFO_LOT      = "EA_INFO_LOT";
string INFO_SPREAD   = "EA_INFO_SPREAD";
string INFO_HIGH     = "EA_INFO_HIGH";
string INFO_LOW      = "EA_INFO_LOW";
string INFO_TF       = "EA_INFO_TF";
string INFO_ADR      = "EA_INFO_ADR";
string INFO_PNL      = "EA_INFO_PNL";
string INFO_WARNING  = "EA_INFO_WARNING";

string INFO_BUY_STOP   = "EA_INFO_BUY_STOP";
string INFO_SELL_STOP  = "EA_INFO_SELL_STOP";
string INFO_BUY_LIMIT  = "EA_INFO_BUY_LIMIT";
string INFO_SELL_LIMIT = "EA_INFO_SELL_LIMIT";

int OnInit() {
   CreateButton(BUY_STOP_BUTTON, "BUY STOP", InpButtonX, InpButtonY);
   CreateButton(SELL_STOP_BUTTON, "SELL STOP", InpButtonX + 1 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateButton(BUY_LIMIT_BUTTON, "BUY LIMIT", InpButtonX + 2 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateButton(SELL_LIMIT_BUTTON, "SELL LIMIT", InpButtonX + 3 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateButton(DEL_PENDING_BUTTON, "DEL PENDING", InpButtonX + 4 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateLabel(INFO_LOT, "", InpInfoX, InpInfoY + 0);
   CreateLabel(INFO_TF, "", InpInfoX, InpInfoY + 15);
   CreateLabel(INFO_SPREAD, "", InpInfoX, InpInfoY + 30);
   CreateLabel(INFO_HIGH, "", InpInfoX, InpInfoY + 45);
   CreateLabel(INFO_LOW, "", InpInfoX, InpInfoY + 60);
   CreateLabel(INFO_ADR, "", InpInfoX, InpInfoY + 75);
   CreateLabel(INFO_PNL, "", InpInfoX, InpInfoY + 90);
   CreateLabel(INFO_WARNING, "", InpInfoX, InpInfoY + 105);
   UpdateInformation();
   ChartRedraw();
   return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   int total = ObjectsTotal(0, 0, -1);
   for (int i = total - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if (StringFind(name, objectName) >= 0) {
         ObjectDelete(0, name);
      }
   }
   Comment("");

   ObjectDelete(0, BUY_STOP_BUTTON);
   ObjectDelete(0, SELL_STOP_BUTTON);
   ObjectDelete(0, BUY_LIMIT_BUTTON);
   ObjectDelete(0, SELL_LIMIT_BUTTON);
   ObjectDelete(0, DEL_PENDING_BUTTON);
   ObjectDelete(0, INFO_LOT);
   ObjectDelete(0, INFO_SPREAD);
   ObjectDelete(0, INFO_HIGH);
   ObjectDelete(0, INFO_LOW);
   ObjectDelete(0, INFO_TF);
   ObjectDelete(0, INFO_ADR);
   ObjectDelete(0, INFO_PNL);
   ObjectDelete(0, INFO_WARNING);
   ObjectDelete(0, INFO_BUY_STOP);
   ObjectDelete(0, INFO_SELL_STOP);
   ObjectDelete(0, INFO_BUY_LIMIT);
   ObjectDelete(0, INFO_SELL_LIMIT);
   ChartRedraw();
}

void OnTick() {
   UpdateInformation();
}

void OnChartEvent(const int id,
   const long & lparam,
      const double & dparam,
         const string & sparam) {
   if (id != CHARTEVENT_OBJECT_CLICK) return;
   if (sparam == BUY_STOP_BUTTON) {
      PlaceBuyStop();
   } else if (sparam == SELL_STOP_BUTTON) {
      PlaceSellStop();
   } else if (sparam == BUY_LIMIT_BUTTON) {
      PlaceBuyLimit();
   } else if (sparam == SELL_LIMIT_BUTTON) {
      PlaceSellLimit();
   } else if (sparam == DEL_PENDING_BUTTON) {
      DeleteAllPendingOrders();
   }
}

void CreateButton(string name, string text, int x, int y) {
   ObjectDelete(0, name);
   if (!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) {
      Print("Failed to create button: ", name);
      return;
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, InpButtonWidth);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, InpButtonHeight);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void CreateLabel(string name, string text, int x, int y) {
   ObjectDelete(0, name);
   if (!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      Print("Failed to create label: ", name);
      return;
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpInfoFontSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpInfoColor);
}

void UpdateInformation() {
   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);

   double currentPrice = (last_tick.bid + last_tick.ask) / 2.0;
   double todayHighest = GetTodayHighest(markTF);
   double todayHighestOpen = GetTodayHighestOpen(markTF);
   double todayLowest = GetTodayLowest(markTF);
   double todayLowestOpen = GetTodayLowestOpen(markTF);

   double todayRange = iHigh(_Symbol, PERIOD_D1, 0) - iLow(_Symbol, PERIOD_D1, 0);
   if (MathAbs(todayRange) <= _Point) {
      Print("Range not ready yet, skip fibo calculation");
      return;
   }

   double PnL = GetTotalPnLPips();

   double averageRange = GetAverageDailyRange(99);
   double averageRangePoint = GetAverageDailyRangePoints(99);
   double todayRangePercent = (todayRange / averageRange) * 100.00;

   datetime startOfToday = iTime(_Symbol, PERIOD_D1, 0);
   datetime timeNow = TimeCurrent();

   string HighestLowestLineName = objectName + "HighestLowest";

   if (!ObjectCreate(0, HighestLowestLineName, OBJ_FIBO, 0, startOfToday, todayLowest, timeNow, todayHighest)) {
      Print("Failed to create Fibonacci");
      return;
   }

   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELS, 5);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 0, ColorHighest);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 1, ColorLowest);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 2, ColorOpen);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_BACK, true);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_STYLE, STYLE_DASHDOTDOT);
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 0, 0.0);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 0, "Highest" + " = %$  ");
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 1, 1.0);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 1, "Lowest" + " = %$  ");

   double rangeHighestLowest = todayHighest - todayLowest;
   if (MathAbs(rangeHighestLowest) <= _Point) {
      Print("Range not ready yet, skip fibo calculation");
      return;
   }

   double openLevel = ((todayHighest - iOpen(_Symbol, PERIOD_D1, 0)) / rangeHighestLowest) * 1.0;
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 2, openLevel);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 2, "Open" + " = %$  ");

   double MarkHighestOpenLevel = ((todayHighest - todayHighestOpen) / rangeHighestLowest) * 1.0;
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 3, ColorHighest);
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 3, MarkHighestOpenLevel);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 3, "%$  ");

   double MarkLowestOpenLevel = ((todayHighest - todayLowestOpen) / rangeHighestLowest) * 1.0;
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 4, ColorLowest);
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 4, MarkLowestOpenLevel);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 4, "%$  ");

   string CornerName = objectName + "CornerText";
   string CornerText = TimeToString((iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period)) - TimeCurrent(), TIME_SECONDS);
   ObjectCreate(0, CornerName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, CornerName, OBJPROP_TEXT, CornerText);
   ObjectSetString(0, CornerName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, CornerName, OBJPROP_FONTSIZE, 19);
   ObjectSetInteger(0, CornerName, OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, CornerName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, CornerName, OBJPROP_XDISTANCE, 111);
   ObjectSetInteger(0, CornerName, OBJPROP_YDISTANCE, 22);

   if (ShowAlert) {
      datetime CurrentTime = TimeCurrent();
      if (LastAlertTime == 0 || (CurrentTime - LastAlertTime) >= AlertDelaySeconds) {
         double currentBid = last_tick.bid;
         if (currentBid > todayHighestOpen && currentBid < todayHighest) {
            Alert("Alhamdulillah, " + _Symbol + " " + GetPeriodString(markTF));
         }

         double currentAsk = last_tick.ask;
         if (currentAsk < todayLowestOpen && currentAsk > todayLowest) {
            Alert("Alhamdulillah, " + _Symbol + " " + GetPeriodString(markTF));
         }

         LastAlertTime = CurrentTime;
      }

   }
   
   if(iHigh(_Symbol, markTF, 0) == todayHighest || iHigh(_Symbol, markTF, 1) == todayHighest) {
      theWarning = GetPeriodString(markTF) + " HIGH BREAKOUT";
   }
   
   if(iLow(_Symbol, markTF, 0) == todayLowest || iLow(_Symbol, markTF, 1) == todayLowest) {
      theWarning = GetPeriodString(markTF) + " LOW BREAKOUT";
   }
   
   if(theWarning == "") {
      theWarning = "NO WARNING";
   }

   ObjectSetString(0, INFO_LOT, OBJPROP_TEXT, "LOT SIZE : " + DoubleToString(InpLotSize, 2));
   ObjectSetString(0, INFO_SPREAD, OBJPROP_TEXT, "MID-PRICE : " + DoubleToString(currentPrice, Digits()) + " | SPREAD : " + IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   ObjectSetString(0, INFO_TF, OBJPROP_TEXT, "TIMEFRAME TARGET : " + GetPeriodString(markTF));
   ObjectSetString(0, INFO_HIGH, OBJPROP_TEXT, "TODAY HIGHEST : " + DoubleToString(todayHighest, _Digits) + " | HIGHEST OPEN : " + DoubleToString(todayHighestOpen, _Digits));
   ObjectSetString(0, INFO_LOW, OBJPROP_TEXT, "TODAY LOWEST : " + DoubleToString(todayLowest, _Digits) + " | LOWEST OPEN : " + DoubleToString(todayLowestOpen, _Digits));
   ObjectSetString(0, INFO_ADR, OBJPROP_TEXT, "ADR 99 DAYS : " + DoubleToString(averageRangePoint, 0) + " | TODAY RANGE = " + DoubleToString(todayRange / _Point, 0) + " (" + DoubleToString(todayRangePercent, 2) + "%)");
   ObjectSetString(0, INFO_PNL, OBJPROP_TEXT, "PNL : " + DoubleToString(PnL, 0) + " PIPS");
   ObjectSetString(0, INFO_WARNING, OBJPROP_TEXT, "WARNING : " + theWarning);

   ChartRedraw();

}

double GetCurrentCandleOpen(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT) {
   return (iOpen(_Symbol, targetTimeFrame, 0));
}

datetime GetTodayStart() {
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;
   return (StructToTime(timeStruct));
}

double GetTodayLowest(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT) {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, targetTimeFrame, todayStart, false);
   if (startShift < 0) {
      return (0);
   }
   int candleCount = startShift + 1;
   double lowestPrice = DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleLow = iLow(_Symbol, targetTimeFrame, i);
      if (candleLow > 0 && candleLow < lowestPrice) {
         lowestPrice = candleLow;
      }
   }
   if (lowestPrice == DBL_MAX) {
      return (0);
   }
   return (NormalizeDouble(lowestPrice, _Digits));
}

double GetTodayHighest(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT) {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, targetTimeFrame, todayStart, false);
   if (startShift < 0) {
      return (0);
   }
   int candleCount = startShift + 1;
   double highestPrice = -DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleHigh = iHigh(_Symbol, targetTimeFrame, i);
      if (candleHigh > 0 && candleHigh > highestPrice) {
         highestPrice = candleHigh;
      }
   }
   if (highestPrice == -DBL_MAX) {
      return (0);
   }
   return (NormalizeDouble(highestPrice, _Digits));
}

double GetTodayLowestOpen(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT) {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, targetTimeFrame, todayStart, false);
   if (startShift < 0) {
      Print("Cannot find today's first candle.");
      return (0);
   }
   int candleCount = startShift + 1;
   double lowestOpen = DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleOpen = iOpen(_Symbol, targetTimeFrame, i);
      if (candleOpen > 0 && candleOpen < lowestOpen) {
         lowestOpen = candleOpen;
      }
   }
   if (lowestOpen == DBL_MAX) {
      Print("Cannot calculate today's lowest OPEN price.");
      return (0);
   }
   return (NormalizeDouble(lowestOpen, _Digits));
}

double GetTodayHighestOpen(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT) {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, targetTimeFrame, todayStart, false);
   if (startShift < 0) {
      Print("Cannot find today's first candle.");
      return (0);
   }
   int candleCount = startShift + 1;
   double highestOpen = -DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleOpen = iOpen(_Symbol, targetTimeFrame, i);
      if (candleOpen > 0 && candleOpen > highestOpen) {
         highestOpen = candleOpen;
      }
   }
   if (highestOpen == -DBL_MAX) {
      Print("Cannot calculate today's highest OPEN price.");
      return (0);
   }
   return (NormalizeDouble(highestOpen, _Digits));
}

double GetMinimumDistance() {
   int stopsLevel = (int) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (stopsLevel * _Point);
}

//+------------------------------------------------------------------+
//| Place Buy Stop                                                   |
//+------------------------------------------------------------------+
void PlaceBuyStop() {
   double entry = GetTodayLowestOpen(markTF);
   double sl = GetTodayLowest();
   double tp = 0;

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minimumDistance = GetMinimumDistance();

   // BUY STOP entry must be above Ask
   if (entry <= ask + minimumDistance) {
      Alert("BUY STOP rejected: Entry must be above Ask.");
      return;
   }

   // SL must be below Entry
   if (sl >= entry) {
      Alert("BUY STOP rejected: SL must be below Entry.");
      return;
   }

   // Calculate TP only when RiskReward != 0
   if (RiskReward != 0) {
      double risk = entry - sl;
      tp = entry + (risk * RiskReward);
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   if (RiskReward != 0)
      tp = NormalizeDouble(tp, _Digits);

   bool result = trade.BuyStop(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      tp,
      ORDER_TIME_GTC,
      0,
      "BUY STOP - Current Open"
   );

   if (result) {
      Print(
         "BUY STOP placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits),
         " | TP=",
         (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE")
      );
   } else {
      Print("BUY STOP failed | ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Place Sell Stop                                                  |
//+------------------------------------------------------------------+
void PlaceSellStop() {
   double entry = GetTodayHighestOpen(markTF);
   double sl = GetTodayHighest();
   double tp = 0;

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minimumDistance = GetMinimumDistance();

   // SELL STOP entry must be below Bid
   if (entry >= bid - minimumDistance) {
      Alert("SELL STOP rejected: Entry must be below Bid.");
      return;
   }

   // SL must be above Entry
   if (sl <= entry) {
      Alert("SELL STOP rejected: SL must be above Entry.");
      return;
   }

   // Calculate TP only when RiskReward != 0
   if (RiskReward != 0) {
      double risk = sl - entry;
      tp = entry - (risk * RiskReward);
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   if (RiskReward != 0)
      tp = NormalizeDouble(tp, _Digits);

   bool result = trade.SellStop(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      tp,
      ORDER_TIME_GTC,
      0,
      "SELL STOP - Current Open"
   );

   if (result) {
      Print(
         "SELL STOP placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits),
         " | TP=",
         (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE")
      );
   } else {
      Print("SELL STOP failed | ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Place Buy Limit                                                  |
//+------------------------------------------------------------------+
void PlaceBuyLimit() {
   double entry = GetTodayLowestOpen(markTF);
   double sl = GetTodayLowest();
   double tp = 0;

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minimumDistance = GetMinimumDistance();

   // BUY LIMIT entry must be below Ask
   if (entry >= ask - minimumDistance) {
      Alert("BUY LIMIT rejected: Entry must be below Ask.");
      return;
   }

   // SL must be below Entry
   if (sl >= entry) {
      Alert("BUY LIMIT rejected: SL must be below Entry.");
      return;
   }

   // Calculate TP only when RiskReward != 0
   if (RiskReward != 0) {
      double risk = entry - sl;
      tp = entry + (risk * RiskReward);
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   if (RiskReward != 0)
      tp = NormalizeDouble(tp, _Digits);

   bool result = trade.BuyLimit(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      tp,
      ORDER_TIME_GTC,
      0,
      "BUY LIMIT - Current Open"
   );

   if (result) {
      Print(
         "BUY LIMIT placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits),
         " | TP=",
         (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE")
      );
   } else {
      Print("BUY LIMIT failed | ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Place Sell Limit                                                 |
//+------------------------------------------------------------------+
void PlaceSellLimit() {
   double entry = GetTodayHighestOpen(markTF);
   double sl = GetTodayHighest();
   double tp = 0;

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minimumDistance = GetMinimumDistance();

   // SELL LIMIT entry must be above Bid
   if (entry <= bid + minimumDistance) {
      Alert("SELL LIMIT rejected: Entry must be above Bid.");
      return;
   }

   // SL must be above Entry
   if (sl <= entry) {
      Alert("SELL LIMIT rejected: SL must be above Entry.");
      return;
   }

   // Calculate TP only when RiskReward != 0
   if (RiskReward != 0) {
      double risk = sl - entry;
      tp = entry - (risk * RiskReward);
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   if (RiskReward != 0)
      tp = NormalizeDouble(tp, _Digits);

   bool result = trade.SellLimit(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      tp,
      ORDER_TIME_GTC,
      0,
      "SELL LIMIT - Current Open"
   );

   if (result) {
      Print(
         "SELL LIMIT placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits),
         " | TP=",
         (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE")
      );
   } else {
      Print("SELL LIMIT failed | ", trade.ResultRetcodeDescription());
   }
}

void DeleteAllPendingOrders() {
   int total = OrdersTotal();
   int deletedCount = 0;
   int failedCount = 0;
   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0) continue;
      if (!OrderSelect(ticket)) continue;
      string orderSymbol = OrderGetString(ORDER_SYMBOL);
      if (orderSymbol != _Symbol) continue;
      ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE);
      bool isPending = false;
      if (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP || orderType == ORDER_TYPE_BUY_STOP_LIMIT || orderType == ORDER_TYPE_SELL_STOP_LIMIT) {
         isPending = true;
      }
      if (!isPending) continue;
      if (trade.OrderDelete(ticket)) {
         deletedCount++;
         Print("Pending order deleted. Ticket = ", ticket);
      } else {
         failedCount++;
         Print("Failed to delete pending order. ", "Ticket = ", ticket, " | ", trade.ResultRetcodeDescription());
      }
   }
   if (deletedCount > 0) {} else {
      Alert("No pending orders found for ", _Symbol);
   }
   if (failedCount > 0) {
      Print("Failed to delete ", failedCount, " pending order(s).");
   }
}

double GetAverageDailyRange(int days = 10) {
   double total = 0.0;
   int count = 0;
   for (int i = 1; i <= days; i++) {
      double high = iHigh(_Symbol, PERIOD_D1, i);
      double low = iLow(_Symbol, PERIOD_D1, i);
      if (high > 0 && low > 0) {
         total += (high - low);
         count++;
      }

   }

   if (count == 0) return 0.0;
   return total / count;
}

double GetAverageDailyRangePoints(int days = 10) {
   return GetAverageDailyRange(days) / _Point;
}

string GetPeriodString(ENUM_TIMEFRAMES period = PERIOD_CURRENT) {
   if (period == PERIOD_CURRENT) period = (ENUM_TIMEFRAMES) _Period;
   string rawEnum = EnumToString(period);
   return StringSubstr(rawEnum, 7);
}

double GetTotalPnLPips() {
   double total_pips = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionGetString(POSITION_SYMBOL) == _Symbol) {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double pnl_points = (current_price - open_price) / tick_size;
         double pnl_pips = pnl_points * (tick_size / point);
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) total_pips -= pnl_pips;
         else total_pips += pnl_pips;
      }

   }

   return total_pips;
}
