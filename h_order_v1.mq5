//+------------------------------------------------------------------+
//|                                        h_order_v1.mq5            |
//|      4 Pending Order Buttons + SL + Information Panel            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+

input double InpLotSize   = 0.01;     // Lot size

//--- Button settings
input int InpButtonWidth  = 123;      // Button width
input int InpButtonHeight = 33;       // Button height
input int InpButtonX      = 10;       // Button X position
input int InpButtonY      = 25;       // Button Y position
input int InpButtonGap    = 10;       // Gap between buttons

//--- Information panel
input int InpInfoX        = 10;       // Information X position
input int InpInfoY        = 70;       // Information Y position
input int InpInfoFontSize = 8;        // Information font size
input color InpInfoColor  = clrWhite; // Information color

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
   CreateLabel(INFO_SPREAD, "", InpInfoX, InpInfoY + 15);
   CreateLabel(INFO_HIGH, "", InpInfoX, InpInfoY + 30);
   CreateLabel(INFO_LOW, "", InpInfoX, InpInfoY + 45);
   UpdateInformation();
   ChartRedraw();
   return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   ObjectDelete(0, BUY_STOP_BUTTON);
   ObjectDelete(0, SELL_STOP_BUTTON);
   ObjectDelete(0, BUY_LIMIT_BUTTON);
   ObjectDelete(0, SELL_LIMIT_BUTTON);
   ObjectDelete(0, DEL_PENDING_BUTTON);
   ObjectDelete(0, INFO_LOT);
   ObjectDelete(0, INFO_SPREAD);
   ObjectDelete(0, INFO_HIGH);
   ObjectDelete(0, INFO_LOW);
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
   double currentOpen = GetCurrentCandleOpen();
   double todayHigh = GetTodayHighest();
   double todayHighestOpen = GetTodayHighestOpen();
   double todayLow = GetTodayLowest();
   double todayLowestOpen = GetTodayLowestOpen();
   ObjectSetString(0, INFO_LOT, OBJPROP_TEXT, "LOT SIZE : " + DoubleToString(InpLotSize, 2));
   ObjectSetString(0, INFO_SPREAD, OBJPROP_TEXT, "SPREAD : " + IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   ObjectSetString(0, INFO_HIGH, OBJPROP_TEXT, "TODAY HIGHEST : " + DoubleToString(todayHigh, _Digits) + " | " + DoubleToString(todayHighestOpen, _Digits));
   ObjectSetString(0, INFO_LOW, OBJPROP_TEXT, "TODAY LOWEST : " + DoubleToString(todayLow, _Digits) + " | " + DoubleToString(todayLowestOpen, _Digits));
   ChartRedraw();
}

double GetCurrentCandleOpen() {
   return (iOpen(_Symbol, _Period, 0));
}

datetime GetTodayStart() {
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;
   return (StructToTime(timeStruct));
}

double GetTodayLowest() {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, _Period, todayStart, false);
   if (startShift < 0) {
      return (0);
   }
   int candleCount = startShift + 1;
   double lowestPrice = DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleLow = iLow(_Symbol, _Period, i);
      if (candleLow > 0 && candleLow < lowestPrice) {
         lowestPrice = candleLow;
      }
   }
   if (lowestPrice == DBL_MAX) {
      return (0);
   }
   return (NormalizeDouble(lowestPrice, _Digits));
}

double GetTodayHighest() {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, _Period, todayStart, false);
   if (startShift < 0) {
      return (0);
   }
   int candleCount = startShift + 1;
   double highestPrice = -DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleHigh = iHigh(_Symbol, _Period, i);
      if (candleHigh > 0 && candleHigh > highestPrice) {
         highestPrice = candleHigh;
      }
   }
   if (highestPrice == -DBL_MAX) {
      return (0);
   }
   return (NormalizeDouble(highestPrice, _Digits));
}

double GetTodayLowestOpen() {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, _Period, todayStart, false);
   if (startShift < 0) {
      Print("Cannot find today's first candle.");
      return (0);
   }
   int candleCount = startShift + 1;
   double lowestOpen = DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleOpen = iOpen(_Symbol, _Period, i);
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

double GetTodayHighestOpen() {
   datetime todayStart = GetTodayStart();
   int startShift = iBarShift(_Symbol, _Period, todayStart, false);
   if (startShift < 0) {
      Print("Cannot find today's first candle.");
      return (0);
   }
   int candleCount = startShift + 1;
   double highestOpen = -DBL_MAX;
   for (int i = 0; i < candleCount; i++) {
      double candleOpen = iOpen(_Symbol, _Period, i);
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

void PlaceBuyStop() {
   double entry = GetTodayLowestOpen();
   double sl = GetTodayLowest();
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
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   bool result = trade.BuyStop(InpLotSize, entry, _Symbol, sl, 0, ORDER_TIME_GTC, 0, "BUY STOP - Current Open");
   if (result) {
      Print("BUY STOP placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits));
   } else {
      Print("BUY STOP failed | ", trade.ResultRetcodeDescription());
   }
}

void PlaceSellStop() {
   double entry = GetTodayHighestOpen();
   double sl = GetTodayHighest();
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
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   bool result = trade.SellStop(InpLotSize, entry, _Symbol, sl, 0, ORDER_TIME_GTC, 0, "SELL STOP - Current Open");
   if (result) {
      Print("SELL STOP placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits));
   } else {
      Print("SELL STOP failed | ", trade.ResultRetcodeDescription());
   }
}

void PlaceBuyLimit() {
   double entry = GetTodayLowestOpen();
   double sl = GetTodayLowest();
   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minimumDistance = GetMinimumDistance();
   if (entry >= ask - minimumDistance) {
      Alert("BUY LIMIT rejected: Entry must be below Ask.");
      return;
   }
   if (sl >= entry) {
      Alert("BUY LIMIT rejected: SL must be below Entry.");
      return;
   }
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   bool result = trade.BuyLimit(InpLotSize, entry, _Symbol, sl, 0, ORDER_TIME_GTC, 0, "BUY LIMIT - Current Open");
   if (result) {
      Print("BUY LIMIT placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits));
   } else {
      Print("BUY LIMIT failed | ", trade.ResultRetcodeDescription());
   }
}

void PlaceSellLimit() {
   double entry = GetTodayHighestOpen();
   double sl = GetTodayHighest();
   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minimumDistance = GetMinimumDistance();
   if (entry <= bid + minimumDistance) {
      Alert("SELL LIMIT rejected: Entry must be above Bid.");
      return;
   }
   if (sl <= entry) {
      Alert("SELL LIMIT rejected: SL must be above Entry.");
      return;
   }
   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);
   bool result = trade.SellLimit(InpLotSize, entry, _Symbol, sl, 0, ORDER_TIME_GTC, 0, "SELL LIMIT - Current Open");
   if (result) {
      Print("SELL LIMIT placed | ", "Lot=", DoubleToString(InpLotSize, 2), " | Entry=", DoubleToString(entry, _Digits), " | SL=", DoubleToString(sl, _Digits));
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
