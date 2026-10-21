//+------------------------------------------------------------------+
//|                                   OrderButtons_v1.mq5            |
//|      4 Pending Order Buttons + SL + Information Panel            |
//+------------------------------------------------------------------+
#property strict
#property version   "4.00"

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
input int InpInfoFontSize = 9;        // Information font size
input color InpInfoColor  = clrWhite; // Information color

//+------------------------------------------------------------------+
//| BUTTON NAMES                                                     |
//+------------------------------------------------------------------+

string BUY_STOP_BUTTON   = "EA_BUY_STOP_BUTTON";
string SELL_STOP_BUTTON  = "EA_SELL_STOP_BUTTON";
string BUY_LIMIT_BUTTON  = "EA_BUY_LIMIT_BUTTON";
string SELL_LIMIT_BUTTON = "EA_SELL_LIMIT_BUTTON";
string CLEAR_BUTTON      = "EA_CLEAR_PENDING_BUTTON";

//+------------------------------------------------------------------+
//| INFORMATION OBJECTS                                              |
//+------------------------------------------------------------------+

string INFO_LOT   = "EA_INFO_LOT";
string INFO_OPEN  = "EA_INFO_OPEN";
string INFO_HIGH  = "EA_INFO_HIGH";
string INFO_LOW   = "EA_INFO_LOW";

string INFO_BUY_STOP   = "EA_INFO_BUY_STOP";
string INFO_SELL_STOP  = "EA_INFO_SELL_STOP";
string INFO_BUY_LIMIT  = "EA_INFO_BUY_LIMIT";
string INFO_SELL_LIMIT = "EA_INFO_SELL_LIMIT";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   //--- Create trading buttons
   CreateButton(
      BUY_STOP_BUTTON,
      "BUY STOP",
      InpButtonX,
      InpButtonY
   );

   CreateButton(
      SELL_STOP_BUTTON,
      "SELL STOP",
      InpButtonX + (InpButtonWidth + InpButtonGap),
      InpButtonY
   );

   CreateButton(
      BUY_LIMIT_BUTTON,
      "BUY LIMIT",
      InpButtonX + 2 * (InpButtonWidth + InpButtonGap),
      InpButtonY
   );

   CreateButton(
      SELL_LIMIT_BUTTON,
      "SELL LIMIT",
      InpButtonX + 3 * (InpButtonWidth + InpButtonGap),
      InpButtonY
   );
   
   //--- CLEAR PENDING
   CreateButton(
      CLEAR_BUTTON,
      "DEL PENDING",
      InpButtonX + 4 * (InpButtonWidth + InpButtonGap),
      InpButtonY
   );

   //--- Create information panel
   CreateLabel(
      INFO_LOT,
      "",
      InpInfoX,
      InpInfoY
   );

   CreateLabel(
      INFO_OPEN,
      "",
      InpInfoX,
      InpInfoY + 20
   );

   CreateLabel(
      INFO_HIGH,
      "",
      InpInfoX,
      InpInfoY + 40
   );

   CreateLabel(
      INFO_LOW,
      "",
      InpInfoX,
      InpInfoY + 60
   );

   CreateLabel(
      INFO_BUY_STOP,
      "",
      InpInfoX,
      InpInfoY + 100
   );

   CreateLabel(
      INFO_SELL_STOP,
      "",
      InpInfoX,
      InpInfoY + 120
   );

   CreateLabel(
      INFO_BUY_LIMIT,
      "",
      InpInfoX,
      InpInfoY + 140
   );

   CreateLabel(
      INFO_SELL_LIMIT,
      "",
      InpInfoX,
      InpInfoY + 160
   );

   //--- Update information immediately
   UpdateInformation();

   ChartRedraw();

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   //--- Delete buttons
   ObjectDelete(0, BUY_STOP_BUTTON);
   ObjectDelete(0, SELL_STOP_BUTTON);
   ObjectDelete(0, BUY_LIMIT_BUTTON);
   ObjectDelete(0, SELL_LIMIT_BUTTON);
   ObjectDelete(0, CLEAR_BUTTON);

   //--- Delete information
   ObjectDelete(0, INFO_LOT);
   ObjectDelete(0, INFO_OPEN);
   ObjectDelete(0, INFO_HIGH);
   ObjectDelete(0, INFO_LOW);

   ObjectDelete(0, INFO_BUY_STOP);
   ObjectDelete(0, INFO_SELL_STOP);
   ObjectDelete(0, INFO_BUY_LIMIT);
   ObjectDelete(0, INFO_SELL_LIMIT);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick() {
   //--- Update monitor information
   UpdateInformation();
}

//+------------------------------------------------------------------+
//| Chart event                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(
   const int id,
      const long & lparam,
         const double & dparam,
            const string & sparam
) {
   if (id != CHARTEVENT_OBJECT_CLICK)
      return;

   //--- BUY STOP
   if (sparam == BUY_STOP_BUTTON) {
      PlaceBuyStop();
   }

   //--- SELL STOP
   else if (sparam == SELL_STOP_BUTTON) {
      PlaceSellStop();
   }

   //--- BUY LIMIT
   else if (sparam == BUY_LIMIT_BUTTON) {
      PlaceBuyLimit();
   }

   //--- SELL LIMIT
   else if (sparam == SELL_LIMIT_BUTTON) {
      PlaceSellLimit();
   }
   
   //--- CLEAR PENDING
   else if(sparam == CLEAR_BUTTON) {
      DeleteAllPendingOrders();
   }
}

//+------------------------------------------------------------------+
//| Create button                                                    |
//+------------------------------------------------------------------+
void CreateButton(
   string name,
   string text,
   int x,
   int y
) {
   ObjectDelete(0, name);

   if (!ObjectCreate(
         0,
         name,
         OBJ_BUTTON,
         0,
         0,
         0
      )) {
      Print("Failed to create button: ", name);
      return;
   }

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XSIZE,
      InpButtonWidth
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_YSIZE,
      InpButtonHeight
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_FONT,
      "Arial"
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_FONTSIZE,
      10
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

   ObjectSetInteger(
      0,
      name,
      OBJPROP_HIDDEN,
      false
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_BACK,
      false
   );
}

//+------------------------------------------------------------------+
//| Create information label                                         |
//+------------------------------------------------------------------+
void CreateLabel(
   string name,
   string text,
   int x,
   int y
) {
   ObjectDelete(0, name);

   if (!ObjectCreate(
         0,
         name,
         OBJ_LABEL,
         0,
         0,
         0
      )) {
      Print("Failed to create label: ", name);
      return;
   }

   ObjectSetInteger(
      0,
      name,
      OBJPROP_XDISTANCE,
      x
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_YDISTANCE,
      y
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_TEXT,
      text
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_FONT,
      "Courier New"
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_FONTSIZE,
      InpInfoFontSize
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

   ObjectSetInteger(
      0,
      name,
      OBJPROP_HIDDEN,
      false
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_BACK,
      false
   );
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpInfoColor);
}

//+------------------------------------------------------------------+
//| Update information panel                                         |
//+------------------------------------------------------------------+
void UpdateInformation() {
   //--- Current candle open
   double currentOpen = GetCurrentCandleOpen();

   //--- Today's high
   double todayHigh = GetTodayHighest();

   //--- Today's low
   double todayLow = GetTodayLowest();

   //--- Lot information
   ObjectSetString(
      0,
      INFO_LOT,
      OBJPROP_TEXT,
      "LOT SIZE : " +
      DoubleToString(InpLotSize, 2)
   );

   //--- Current open
   ObjectSetString(
      0,
      INFO_OPEN,
      OBJPROP_TEXT,
      "CURRENT CANDLE OPEN : " +
      DoubleToString(currentOpen, _Digits)
   );

   //--- Today's high
   ObjectSetString(
      0,
      INFO_HIGH,
      OBJPROP_TEXT,
      "TODAY HIGH : " +
      DoubleToString(todayHigh, _Digits)
   );

   //--- Today's low
   ObjectSetString(
      0,
      INFO_LOW,
      OBJPROP_TEXT,
      "TODAY LOW : " +
      DoubleToString(todayLow, _Digits)
   );

   //--- BUY STOP description
   ObjectSetString(
      0,
      INFO_BUY_STOP,
      OBJPROP_TEXT,
      "BUY STOP -> Entry: Current Open | SL: Today Low"
   );

   //--- SELL STOP description
   ObjectSetString(
      0,
      INFO_SELL_STOP,
      OBJPROP_TEXT,
      "SELL STOP -> Entry: Current Open | SL: Today High"
   );

   //--- BUY LIMIT description
   ObjectSetString(
      0,
      INFO_BUY_LIMIT,
      OBJPROP_TEXT,
      "BUY LIMIT -> Entry: Current Open | SL: Today Low"
   );

   //--- SELL LIMIT description
   ObjectSetString(
      0,
      INFO_SELL_LIMIT,
      OBJPROP_TEXT,
      "SELL LIMIT -> Entry: Current Open | SL: Today High"
   );

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Get current candle OPEN price                                    |
//+------------------------------------------------------------------+
double GetCurrentCandleOpen() {
   return (
      iOpen(
         _Symbol,
         _Period,
         0
      )
   );
}

//+------------------------------------------------------------------+
//| Get start of today                                               |
//+------------------------------------------------------------------+
datetime GetTodayStart() {
   MqlDateTime timeStruct;

   TimeToStruct(
      TimeCurrent(),
      timeStruct
   );

   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;

   return (
      StructToTime(timeStruct)
   );
}

//+------------------------------------------------------------------+
//| Get today's lowest price                                         |
//+------------------------------------------------------------------+
double GetTodayLowest() {
   datetime todayStart = GetTodayStart();

   int startShift = iBarShift(
      _Symbol,
      _Period,
      todayStart,
      false
   );

   if (startShift < 0) {
      return (0);
   }

   int candleCount = startShift + 1;

   double lowestPrice = DBL_MAX;

   for (int i = 0; i < candleCount; i++) {
      double candleLow = iLow(
         _Symbol,
         _Period,
         i
      );

      if (candleLow > 0 && candleLow < lowestPrice) {
         lowestPrice = candleLow;
      }
   }

   if (lowestPrice == DBL_MAX) {
      return (0);
   }

   return (
      NormalizeDouble(
         lowestPrice,
         _Digits
      )
   );
}

//+------------------------------------------------------------------+
//| Get today's highest price                                        |
//+------------------------------------------------------------------+
double GetTodayHighest() {
   datetime todayStart = GetTodayStart();

   int startShift = iBarShift(
      _Symbol,
      _Period,
      todayStart,
      false
   );

   if (startShift < 0) {
      return (0);
   }

   int candleCount = startShift + 1;

   double highestPrice = -DBL_MAX;

   for (int i = 0; i < candleCount; i++) {
      double candleHigh = iHigh(
         _Symbol,
         _Period,
         i
      );

      if (candleHigh > 0 && candleHigh > highestPrice) {
         highestPrice = candleHigh;
      }
   }

   if (highestPrice == -DBL_MAX) {
      return (0);
   }

   return (
      NormalizeDouble(
         highestPrice,
         _Digits
      )
   );
}

//+------------------------------------------------------------------+
//| Get minimum stop distance                                        |
//+------------------------------------------------------------------+
double GetMinimumDistance() {
   int stopsLevel = (int) SymbolInfoInteger(
      _Symbol,
      SYMBOL_TRADE_STOPS_LEVEL
   );

   return (
      stopsLevel * _Point
   );
}

//+------------------------------------------------------------------+
//| BUY STOP                                                         |
//+------------------------------------------------------------------+
void PlaceBuyStop() {
   double entry = GetCurrentCandleOpen();
   double sl = GetTodayLowest();

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double minimumDistance = GetMinimumDistance();

   if (entry <= ask + minimumDistance) {
      Alert(
         "BUY STOP rejected: Entry must be above Ask."
      );
      return;
   }

   if (sl >= entry) {
      Alert(
         "BUY STOP rejected: SL must be below Entry."
      );
      return;
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   bool result = trade.BuyStop(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      0,
      ORDER_TIME_GTC,
      0,
      "BUY STOP - Current Open"
   );

   if (result) {
      Print(
         "BUY STOP placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits)
      );
   } else {
      Print(
         "BUY STOP failed | ",
         trade.ResultRetcodeDescription()
      );
   }
}

//+------------------------------------------------------------------+
//| SELL STOP                                                        |
//+------------------------------------------------------------------+
void PlaceSellStop() {
   double entry = GetCurrentCandleOpen();
   double sl = GetTodayHighest();

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double minimumDistance = GetMinimumDistance();

   if (entry >= bid - minimumDistance) {
      Alert(
         "SELL STOP rejected: Entry must be below Bid."
      );
      return;
   }

   if (sl <= entry) {
      Alert(
         "SELL STOP rejected: SL must be above Entry."
      );
      return;
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   bool result = trade.SellStop(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      0,
      ORDER_TIME_GTC,
      0,
      "SELL STOP - Current Open"
   );

   if (result) {
      Print(
         "SELL STOP placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits)
      );
   } else {
      Print(
         "SELL STOP failed | ",
         trade.ResultRetcodeDescription()
      );
   }
}

//+------------------------------------------------------------------+
//| BUY LIMIT                                                        |
//+------------------------------------------------------------------+
void PlaceBuyLimit() {
   double entry = GetCurrentCandleOpen();
   double sl = GetTodayLowest();

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double minimumDistance = GetMinimumDistance();

   if (entry >= ask - minimumDistance) {
      Alert(
         "BUY LIMIT rejected: Entry must be below Ask."
      );
      return;
   }

   if (sl >= entry) {
      Alert(
         "BUY LIMIT rejected: SL must be below Entry."
      );
      return;
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   bool result = trade.BuyLimit(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      0,
      ORDER_TIME_GTC,
      0,
      "BUY LIMIT - Current Open"
   );

   if (result) {
      Print(
         "BUY LIMIT placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits)
      );
   } else {
      Print(
         "BUY LIMIT failed | ",
         trade.ResultRetcodeDescription()
      );
   }
}

//+------------------------------------------------------------------+
//| SELL LIMIT                                                       |
//+------------------------------------------------------------------+
void PlaceSellLimit() {
   double entry = GetCurrentCandleOpen();
   double sl = GetTodayHighest();

   if (entry <= 0 || sl <= 0) {
      Alert("Invalid entry or Stop Loss price.");
      return;
   }

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double minimumDistance = GetMinimumDistance();

   if (entry <= bid + minimumDistance) {
      Alert(
         "SELL LIMIT rejected: Entry must be above Bid."
      );
      return;
   }

   if (sl <= entry) {
      Alert(
         "SELL LIMIT rejected: SL must be above Entry."
      );
      return;
   }

   entry = NormalizeDouble(entry, _Digits);
   sl = NormalizeDouble(sl, _Digits);

   bool result = trade.SellLimit(
      InpLotSize,
      entry,
      _Symbol,
      sl,
      0,
      ORDER_TIME_GTC,
      0,
      "SELL LIMIT - Current Open"
   );

   if (result) {
      Print(
         "SELL LIMIT placed | ",
         "Lot=", DoubleToString(InpLotSize, 2),
         " | Entry=", DoubleToString(entry, _Digits),
         " | SL=", DoubleToString(sl, _Digits)
      );
   } else {
      Print(
         "SELL LIMIT failed | ",
         trade.ResultRetcodeDescription()
      );
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| DELETE ALL PENDING ORDERS                                        |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders() {
   int total = OrdersTotal();

   int deletedCount = 0;
   int failedCount = 0;

   //--- Loop backwards because orders can be deleted
   for (int i = total - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);

      if (ticket == 0)
         continue;

      //--- Select order
      if (!OrderSelect(ticket))
         continue;

      //--- Get symbol
      string orderSymbol = OrderGetString(
         ORDER_SYMBOL
      );

      //--- Only current chart symbol
      if (orderSymbol != _Symbol)
         continue;

      //--- Get order type
      ENUM_ORDER_TYPE orderType =
         (ENUM_ORDER_TYPE) OrderGetInteger(
            ORDER_TYPE
         );

      //--- Check whether it is a pending order
      bool isPending = false;

      if (orderType == ORDER_TYPE_BUY_LIMIT ||
         orderType == ORDER_TYPE_SELL_LIMIT ||
         orderType == ORDER_TYPE_BUY_STOP ||
         orderType == ORDER_TYPE_SELL_STOP ||
         orderType == ORDER_TYPE_BUY_STOP_LIMIT ||
         orderType == ORDER_TYPE_SELL_STOP_LIMIT) {
         isPending = true;
      }

      if (!isPending)
         continue;

      //--- Delete pending order
      if (trade.OrderDelete(ticket)) {
         deletedCount++;

         Print(
            "Pending order deleted. Ticket = ",
            ticket
         );
      } else {
         failedCount++;

         Print(
            "Failed to delete pending order. ",
            "Ticket = ",
            ticket,
            " | ",
            trade.ResultRetcodeDescription()
         );
      }
   }

   //--- Message
   if (deletedCount > 0) {
      Alert(
         IntegerToString(deletedCount),
         " pending order(s) deleted."
      );
   } else {
      Alert(
         "No pending orders found for ",
         _Symbol
      );
   }

   if (failedCount > 0) {
      Print(
         "Failed to delete ",
         failedCount,
         " pending order(s)."
      );
   }
}
//+------------------------------------------------------------------+
