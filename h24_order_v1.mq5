//+------------------------------------------------------------------+
//|                                      h24_order_v1.mq5            |
//|      4 Pending Order Buttons + SL + Information Panel            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+

//--- Trade
input double InpLotSize       = 0.01;      // Lot size
input double RiskReward       = 1.33;       // Risk Reward

//--- Indicator
input ENUM_TIMEFRAMES markTF  = PERIOD_H1; // Time Frame Target
input int   theNumOfBars      = 0;         // NumberOfBars
input string TargetDateTime   = "";        // Spesific DateTime ==> 2026.09.01 01:00:00
input int   TargetDay         = 0;         // 0 = Today | 1 = Yesterday | 2 = Day Before Yesterday
input int   Vline             = 0;         // Create Vertlical Line
input bool  ShowAlert         = true;      // Turn on Alert
input int   AlertDelaySeconds = 9;         // Alert Delay in Second
input color ColorHighest      = clrMaroon;
input color ColorLowest       = clrDarkGreen;

//--- Button settings
input int InpButtonWidth      = 99;       // Button width
input int InpButtonHeight     = 22;        // Button height
input int InpButtonX          = 10;        // Button X position
input int InpButtonY          = 30;        // Button Y position
input int InpButtonGap        = 10;        // Gap between buttons

//--- Information panel
input int InpInfoX            = 10;        // Information X position
input int InpInfoY            = 70;        // Information Y position
input int InpInfoFontSize     = 8;         // Information font size
input color InpInfoColor      = clrWhite;  // Information color

datetime LastAlertTime        = 0;
string   objectName           = "holo";
int      NumOfBars            = 0;
string   symbols[];                        // list of symbols from Market Watch

//+------------------------------------------------------------------+
//| BUTTON NAMES                                                     |
//+------------------------------------------------------------------+
string BUTTON_A = objectName + "BUTTON_BUY_STOP";
string BUTTON_B = objectName + "BUTTON_SELL_STOP";
string BUTTON_C = objectName + "BUTTON_DEL_PENDING";
string BUTTON_D = objectName + "BUTTON_BUY";
string BUTTON_E = objectName + "BUTTON_SELL";

//+------------------------------------------------------------------+
//| INFORMATION OBJECTS                                              |
//+------------------------------------------------------------------+
string INFO_A = objectName + "INFO_A";
string INFO_B = objectName + "INFO_B";
string INFO_C = objectName + "INFO_C";
string INFO_D = objectName + "INFO_D";
string INFO_E = objectName + "INFO_E";
string INFO_F = objectName + "INFO_F";
string INFO_G = objectName + "INFO_G";

int OnInit() {
   CreateButton(BUTTON_A, "BUY STOP", InpButtonX, InpButtonY);
   CreateButton(BUTTON_B, "SELL STOP", InpButtonX + 1 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateButton(BUTTON_C, "DEL PENDING", InpButtonX + 2 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateButton(BUTTON_D, "BUY NOW", InpButtonX + 3 * (InpButtonWidth + InpButtonGap), InpButtonY);
   CreateButton(BUTTON_E, "SELL NOW", InpButtonX + 4 * (InpButtonWidth + InpButtonGap), InpButtonY);
   
   // Create background rectangle
   string bgColorLabel = objectName + "BG_COLOR";
   ObjectCreate(0, bgColorLabel, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_XDISTANCE, 5);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_YDISTANCE, InpInfoY - 5);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_XSIZE, 350);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_YSIZE, 70);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgColorLabel, OBJPROP_COLOR, clrBlack);
   
   CreateLabel(INFO_A, "", InpInfoX, InpInfoY + 0);
   CreateLabel(INFO_B, "", InpInfoX, InpInfoY + 15);
   CreateLabel(INFO_C, "", InpInfoX, InpInfoY + 30);
   CreateLabel(INFO_D, "", InpInfoX, InpInfoY + 45);
   CreateLabel(INFO_E, "", InpInfoX, InpInfoY + 60);
   CreateLabel(INFO_F, "", InpInfoX, InpInfoY + 75);
   CreateLabel(INFO_G, "", InpInfoX, InpInfoY + 90);
   
   UpdateInformation();
   if (Vline > 0) {
      CreateVerticalLines(Vline, markTF);
   }
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
   if (sparam == BUTTON_A) {
      PlaceBuyStop();
   } else if (sparam == BUTTON_B) {
      PlaceSellStop();
   } else if (sparam == BUTTON_C) {
      DeleteAllPendingOrders();
   } else if (sparam == BUTTON_D) {
      PlaceBuyNow();
   } else if (sparam == BUTTON_E) {
      PlaceSellNow();
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
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrLimeGreen);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
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
   if (theNumOfBars != 0) {
      NumOfBars = theNumOfBars;
   }
   if (TargetDateTime != "") {
      NumOfBars = iBarShift(_Symbol, markTF, StringToTime(TargetDateTime), false);
   }
   if (theNumOfBars == 0 && TargetDateTime == "") {
      NumOfBars = GetBarsDay(_Symbol, markTF, TargetDay);
   }
   double currentPrice = (last_tick.bid + last_tick.ask) / 2.0;
   double Highest = GetHighest(markTF, NumOfBars);
   double HighestOpen = GetHighestOpen(markTF, NumOfBars);
   double Lowest = GetLowest(markTF, NumOfBars);
   double LowestOpen = GetLowestOpen(markTF, NumOfBars);
   double PnL = GetTotalPnLPips();
   datetime timeStart = iTime(_Symbol, markTF, NumOfBars);
   datetime timeNow = TimeCurrent();
   string HighestLowestLineName = objectName + "HighestLowest";
   if (!ObjectCreate(0, HighestLowestLineName, OBJ_FIBO, 0, timeStart, Lowest, timeNow, Highest)) {
      Print("Failed to create Fibonacci");
      return;
   }
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELS, 4);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 0, ColorHighest);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 1, ColorLowest);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_BACK, true);
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_STYLE, STYLE_DASHDOTDOT);
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 0, 0.0);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 0, GetPeriodString(markTF) + " Highest" + " = %$  ");
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 1, 1.0);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 1, GetPeriodString(markTF) + " Lowest" + " = %$  ");
   double rangeHighestLowest = Highest - Lowest;
   if (MathAbs(rangeHighestLowest) <= _Point) {
      Print("Range not ready yet, skip fibo calculation");
      return;
   }
   double MarkHighestOpenLevel = ((Highest - HighestOpen) / rangeHighestLowest) * 1.0;
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 2, ColorHighest);
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 2, MarkHighestOpenLevel);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 2, "Highest Open = %$  ");
   double MarkLowestOpenLevel = ((Highest - LowestOpen) / rangeHighestLowest) * 1.0;
   ObjectSetInteger(0, HighestLowestLineName, OBJPROP_LEVELCOLOR, 3, ColorLowest);
   ObjectSetDouble(0, HighestLowestLineName, OBJPROP_LEVELVALUE, 3, MarkLowestOpenLevel);
   ObjectSetString(0, HighestLowestLineName, OBJPROP_LEVELTEXT, 3, "Lowest Open = %$  ");
   string CornerName = objectName + "CornerText";
   string CornerText = _Symbol + " " + GetPeriodString(PERIOD_CURRENT) + " " + TimeToString((iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period)) - TimeCurrent(), TIME_SECONDS);
   ObjectCreate(0, CornerName, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, CornerName, OBJPROP_TEXT, CornerText);
   ObjectSetString(0, CornerName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, CornerName, OBJPROP_FONTSIZE, 19);
   ObjectSetInteger(0, CornerName, OBJPROP_COLOR, clrAqua);
   ObjectSetInteger(0, CornerName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, CornerName, OBJPROP_XDISTANCE, 333);
   ObjectSetInteger(0, CornerName, OBJPROP_YDISTANCE, 33);
   
   string Warning = "";
   
   if (iHigh(_Symbol, markTF, 0) == Highest) {
      Warning = GetPeriodString(markTF) + " HIGH BREAKOUT";
   }
   if (iLow(_Symbol, markTF, 0) == Lowest) {
      Warning = GetPeriodString(markTF) + " LOW BREAKOUT";
   }
   
   bool timeToSell = iOpen(_Symbol, PERIOD_CURRENT, 0) < HighestOpen && iOpen(_Symbol, PERIOD_CURRENT, 1) > HighestOpen;
   if (timeToSell) {
      Warning = "TIME TO SELL";
   }
   
   bool timeToBuy = iOpen(_Symbol, PERIOD_CURRENT, 0) > LowestOpen && iOpen(_Symbol, PERIOD_CURRENT, 1) < LowestOpen;
   if (timeToBuy) {
      Warning = "TIME TO BUY";
   }
   
   if (Warning == "") {
      Warning = "NO WARNING";
   }
   
   ObjectSetString(0, INFO_A, OBJPROP_TEXT, "BARS : " + IntegerToString(NumOfBars) + " | TARGET: " + GetPeriodString(markTF) + " | END : " + TimeToString((iTime(_Symbol, markTF, 0) + PeriodSeconds(markTF)) - TimeCurrent(), TIME_SECONDS));
   ObjectSetString(0, INFO_B, OBJPROP_TEXT, "SPREAD : " + IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + " | PRICE : " + DoubleToString(currentPrice, Digits()));
   ObjectSetString(0, INFO_C, OBJPROP_TEXT, "LOT : " + DoubleToString(InpLotSize, 2) + " | RR : " + DoubleToString(RiskReward, 2) + " | PNL : " + DoubleToString(PnL, 0) + " PIPS");
   ObjectSetString(0, INFO_D, OBJPROP_TEXT, "WARNING : " + Warning);
   ObjectSetString(0, INFO_E, OBJPROP_TEXT, " ");
   ObjectSetString(0, INFO_F, OBJPROP_TEXT, " ");
   ObjectSetString(0, INFO_G, OBJPROP_TEXT, " ");
   
   if (ShowAlert) {
   //if (ShowAlert && (StringFind(Warning, "NO WARNING") >= 0)) {
      datetime CurrentTime = TimeCurrent();
      if (LastAlertTime == 0 || (CurrentTime - LastAlertTime) >= AlertDelaySeconds) {
         double currentBid = last_tick.bid;
         if (currentBid > HighestOpen && currentBid < Highest) {
            Alert("Alhamdulillah, " + _Symbol + " " + GetPeriodString(markTF));
         }
         double currentAsk = last_tick.ask;
         if (currentAsk < LowestOpen && currentAsk > Lowest) {
            Alert("Alhamdulillah, " + _Symbol + " " + GetPeriodString(markTF));
         }
         LastAlertTime = CurrentTime;
      }
   }
   
   ChartRedraw();
}

double GetLowest(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT, int BarCount = 24) {
   double lowestPrice = DBL_MAX;
   for (int i = 0; i < BarCount; i++) {
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

double GetHighest(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT, int BarCount = 24) {
   double highestPrice = -DBL_MAX;
   for (int i = 0; i < BarCount; i++) {
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

double GetLowestOpen(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT, int BarCount = 24) {
   double lowestOpen = DBL_MAX;
   for (int i = 0; i < BarCount; i++) {
      double candleOpen = iOpen(_Symbol, targetTimeFrame, i);
      if (candleOpen > 0 && candleOpen < lowestOpen) {
         lowestOpen = candleOpen;
      }
   }
   if (lowestOpen == DBL_MAX) {
      Print("Cannot calculate lowest OPEN price.");
      return (0);
   }
   return (NormalizeDouble(lowestOpen, _Digits));
}

double GetHighestOpen(ENUM_TIMEFRAMES targetTimeFrame = PERIOD_CURRENT, int BarCount = 24) {
   double highestOpen = -DBL_MAX;
   for (int i = 0; i < BarCount; i++) {
      double candleOpen = iOpen(_Symbol, targetTimeFrame, i);
      if (candleOpen > 0 && candleOpen > highestOpen) {
         highestOpen = candleOpen;
      }
   }
   if (highestOpen == -DBL_MAX) {
      Print("Cannot calculate highest OPEN price.");
      return (0);
   }
   return (NormalizeDouble(highestOpen, _Digits));
}

double GetMinimumDistance() {
   int stopsLevel = (int) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (stopsLevel * _Point);
}

void PlaceBuyStop() {
   double entry = GetLowestOpen(markTF, NumOfBars);
   double sl = GetLowest(markTF, NumOfBars);
   double tp = 0;
   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minimumDistance = GetMinimumDistance();
   if (entry <= ask + minimumDistance) {
      Alert("BUY STOP rejected: Entry must be above Ask.");
      return;
   }
   if (sl >= entry) {
      Alert("BUY STOP rejected: SL must be below Entry.");
      return;
   }
   if (RiskReward != 0) {
      double risk = entry - sl;
      tp = entry + (risk * RiskReward);
   }
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   if (RiskReward != 0) tp = NormalizeDouble(tp, _Digits);
   bool result = trade.BuyStop(InpLotSize, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "BUY STOP - Current Open");
   if (result) {
      Print("BUY STOP placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits), " | TP=", (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE"));
   } else {
      Print("BUY STOP failed | ", trade.ResultRetcodeDescription());
   }
}

void PlaceSellStop() {
   double entry = GetHighestOpen(markTF, NumOfBars);
   double sl = GetHighest(markTF, NumOfBars);
   double tp = 0;
   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minimumDistance = GetMinimumDistance();
   if (entry >= bid - minimumDistance) {
      Alert("SELL STOP rejected: Entry must be below Bid.");
      return;
   }
   if (sl <= entry) {
      Alert("SELL STOP rejected: SL must be above Entry.");
      return;
   }
   if (RiskReward != 0) {
      double risk = sl - entry;
      tp = entry - (risk * RiskReward);
   }
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   if (RiskReward != 0) tp = NormalizeDouble(tp, _Digits);
   bool result = trade.SellStop(InpLotSize, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SELL STOP - Current Open");
   if (result) {
      Print("SELL STOP placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits), " | TP=", (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE"));
   } else {
      Print("SELL STOP failed | ", trade.ResultRetcodeDescription());
   }
}

void PlaceBuyNow() {
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = GetLowest(markTF, NumOfBars);
   double tp = 0;
   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }
   if (sl >= entry) {
      Alert("BUY NOW rejected: SL must be below Entry.");
      return;
   }
   if (RiskReward != 0) {
      double risk = entry - sl;
      tp = entry + (risk * RiskReward);
   }
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   if (RiskReward != 0) tp = NormalizeDouble(tp, _Digits);
   bool result = trade.Buy(InpLotSize, _Symbol, 0, sl, tp, "BUY NOW - Current Market");
   if (result) {
      Print("BUY NOW placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits), " | TP=", (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE"));
   } else {
      Print("BUY NOW failed | ", trade.ResultRetcodeDescription());
   }
}

void PlaceSellNow() {
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = GetHighest(markTF, NumOfBars);
   double tp = 0;
   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }
   if (sl <= entry) {
      Alert("SELL NOW rejected: SL must be above Entry.");
      return;
   }
   if (RiskReward != 0) {
      double risk = sl - entry;
      tp = entry - (risk * RiskReward);
   }
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   if (RiskReward != 0) tp = NormalizeDouble(tp, _Digits);
   bool result = trade.Sell(InpLotSize, _Symbol, 0, sl, tp, "SELL NOW - Current Market");
   if (result) {
      Print("SELL NOW placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits), " | TP=", (RiskReward != 0 ? DoubleToString(tp, _Digits) : "NONE"));
   } else {
      Print("SELL NOW failed | ", trade.ResultRetcodeDescription());
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

void CreateVerticalLines(int bars = 5, ENUM_TIMEFRAMES period = PERIOD_H1) {
   if (bars <= 0) return;
   for (int shift = 0; shift < bars; shift++) {
      datetime candleTime = iTime(_Symbol, period, shift);
      if (candleTime <= 0) continue;
      string lineName = objectName + "VLine_" + IntegerToString((long) candleTime);
      if (ObjectFind(0, lineName) >= 0) continue;
      if (ObjectCreate(0, lineName, OBJ_VLINE, 0, candleTime, 0)) {
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);
      }
   }
}

int GetBarsDay(string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, int day = 0) {
   if (day < 0) day = 0;
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime start_of_day = StructToTime(dt);
   datetime start_time = start_of_day - (day * 86400);
   datetime end_time = start_time + 86400 - 1;
   int bars_count = Bars(symbol, timeframe, start_time, end_time);
   return bars_count;
}
