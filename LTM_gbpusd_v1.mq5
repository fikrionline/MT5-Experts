//+------------------------------------------------------------------+
//| PinkLine Trade Manager for MetaTrader 5                          |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"#include <Trade/Trade.mqh>

input double   LotSize              = 0.05;
input int      SL_Distance_Points   = 358;
input double   RiskRewardRatio      = 1.23;
input color    PointLineColor       = clrWhite;
input int      SlippagePoints       = 20;
input ulong    MagicNumber          = 575899;

CTrade trade;
string prefix = "LTM_";
string labels[9] = {
   "BUY NOW",
   "SELL NOW",
   "BUY LIMIT",
   "SELL LIMIT",
   "BUY STOP",
   "SELL STOP",
   "DEL PENDING ORDER",
   "CLOSE ALL ORDER",
   "DEL LINE"
};
string ids[9] = {
   "BUY",
   "SELL",
   "BL",
   "SL",
   "BS",
   "SS",
   "DELETE",
   "CLOSE",
   "DELLINE"
};

int OnInit() {
   if (LotSize <= 0 || SL_Distance_Points <= 0 || RiskRewardRatio <= 0 || SlippagePoints < 0)
      return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   for (int i = 0; i < 9; i++) {
      string name = prefix + ids[i];
      if (!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) return INIT_FAILED;
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 12 + (i % 2) * 155);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 30 + (i / 2) * 39);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 148);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 32);
      ObjectSetString(0, name, OBJPROP_TEXT, labels[i]);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, (i == 0 || i == 2 || i == 4) ? clrForestGreen : ((i == 1 || i == 3 || i == 5) ? clrFireBrick : clrDarkSlateGray));
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ChartRedraw();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   for (int i = 0; i < 9; i++) ObjectDelete(0, prefix + ids[i]);
   ChartRedraw();
}

void OnTick() {}

void Fail(string message) {
   Print("PinkLine Manager: ", message);
   Alert("PinkLine Manager: ", message);
}

bool ValidVolume() {
   double minvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (step <= 0 || LotSize < minvol - 1e-9 || LotSize > maxvol + 1e-9 ||
      MathAbs(LotSize / step - MathRound(LotSize / step)) > 1e-6) {
      Fail("Invalid lot size for this symbol. Check min/max/step volume.");
      return false;
   }
   return true;
}

bool AllowedTrading(ENUM_ORDER_TYPE type) {
   if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) {
      Fail("Trading is disabled in terminal, EA settings, or account.");
      return false;
   }
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if (mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY ||
      (mode == SYMBOL_TRADE_MODE_LONGONLY && (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)) ||
      (mode == SYMBOL_TRADE_MODE_SHORTONLY && (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP))) {
      Fail("Symbol trading mode does not allow this order.");
      return false;
   }
   if (type > ORDER_TYPE_SELL && (SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE) & SYMBOL_ORDER_LIMIT) == 0 &&
      (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)) {
      Fail("Limit orders are not supported for this symbol.");
      return false;
   }
   if ((type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP) &&
      (SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE) & SYMBOL_ORDER_STOP) == 0) {
      Fail("Stop orders are not supported for this symbol.");
      return false;
   }
   return ValidVolume();
}

bool GetPinkPrice(double & price) {
   // Uses the first matching pink horizontal line on the current chart.
   int count = ObjectsTotal(0, 0, -1);
   for (int i = 0; i < count; i++) {
      string name = ObjectName(0, i, 0, -1);
      if (ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_HLINE) continue;
      if ((color) ObjectGetInteger(0, name, OBJPROP_COLOR) != PointLineColor) continue;
      price = NormalizeDouble(ObjectGetDouble(0, name, OBJPROP_PRICE), _Digits);
      return true;
   }
   Fail("No pink horizontal line found. Draw an HLINE and set its color to Pink.");
   return false;
}

bool CheckMargin(ENUM_ORDER_TYPE type, double price) {
   ENUM_ORDER_TYPE side = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin = 0;
   if (!OrderCalcMargin(side, _Symbol, LotSize, price, margin)) {
      Fail("Cannot calculate margin: " + IntegerToString(GetLastError()));
      return false;
   }
   if (margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) {
      Fail("Insufficient free margin.");
      return false;
   }
   return true;
}

void PlaceOrder(ENUM_ORDER_TYPE type) {
   if (!AllowedTrading(type)) return;
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0 || tick.bid <= 0) {
      Fail("No valid live Bid/Ask prices.");
      return;
   }
   bool buy = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP);
   bool pending = (type != ORDER_TYPE_BUY && type != ORDER_TYPE_SELL);
   double entry = buy ? tick.ask : tick.bid;
   if (pending && !GetPinkPrice(entry)) return;
   double dist = SL_Distance_Points * _Point;
   double minDist = (double) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double sl = NormalizeDouble(entry + (buy ? -dist : dist), _Digits);
   double tp = NormalizeDouble(entry + (buy ? dist * RiskRewardRatio : -dist * RiskRewardRatio), _Digits);
   if (MathAbs(entry - sl) + 1e-9 < minDist || MathAbs(entry - tp) + 1e-9 < minDist) {
      Fail("SL/TP distance is smaller than broker minimum stop level.");
      return;
   }
   if (pending) {
      bool correct = (type == ORDER_TYPE_BUY_LIMIT && entry < tick.ask) ||
         (type == ORDER_TYPE_SELL_LIMIT && entry > tick.bid) ||
         (type == ORDER_TYPE_BUY_STOP && entry > tick.ask) ||
         (type == ORDER_TYPE_SELL_STOP && entry < tick.bid);
      if (!correct) {
         Fail("Invalid pending price direction. BUY LIMIT below Ask, SELL LIMIT above Bid, BUY STOP above Ask, SELL STOP below Bid.");
         return;
      }
      double reference = buy ? tick.ask : tick.bid;
      if (MathAbs(entry - reference) + 1e-9 < minDist) {
         Fail("Pending entry is too close to market price (broker stop level).");
         return;
      }
   }
   if (!CheckMargin(type, entry)) return;
   bool sent = false;
   switch (type) {
   case ORDER_TYPE_BUY:
      sent = trade.Buy(LotSize, _Symbol, 0, sl, tp, "PLTM Buy");
      break;
   case ORDER_TYPE_SELL:
      sent = trade.Sell(LotSize, _Symbol, 0, sl, tp, "PLTM Sell");
      break;
   case ORDER_TYPE_BUY_LIMIT:
      sent = trade.BuyLimit(LotSize, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PLTM Buy Limit");
      break;
   case ORDER_TYPE_SELL_LIMIT:
      sent = trade.SellLimit(LotSize, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PLTM Sell Limit");
      break;
   case ORDER_TYPE_BUY_STOP:
      sent = trade.BuyStop(LotSize, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PLTM Buy Stop");
      break;
   case ORDER_TYPE_SELL_STOP:
      sent = trade.SellStop(LotSize, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PLTM Sell Stop");
      break;
   default:
      return;
   }
   uint ret = trade.ResultRetcode();
   if (!sent || (ret != TRADE_RETCODE_DONE && ret != TRADE_RETCODE_PLACED && ret != TRADE_RETCODE_DONE_PARTIAL))
      Fail("Order failed: " + trade.ResultRetcodeDescription() + " (" + IntegerToString((int) ret) + ")");
   else Print("PinkLine Manager order accepted: ", trade.ResultRetcodeDescription());
}

void DeletePending() {
   bool errors = false;
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE);
      if (type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP &&
         type != ORDER_TYPE_BUY_STOP_LIMIT && type != ORDER_TYPE_SELL_STOP_LIMIT) continue;
      if (!trade.OrderDelete(ticket) || trade.ResultRetcode() != TRADE_RETCODE_DONE) {
         errors = true;
         Print("Could not delete order #", ticket, ": ", trade.ResultRetcodeDescription());
      }
   }
   if (errors) Fail("Some pending orders could not be deleted. Check Experts log.");
}

void CloseAll() {
   DeletePending();
   bool errors = false;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (!trade.PositionClose(ticket, SlippagePoints) || trade.ResultRetcode() != TRADE_RETCODE_DONE) {
         errors = true;
         Print("Could not close position #", ticket, ": ", trade.ResultRetcodeDescription());
      }
   }
   if (errors) Fail("Some positions could not be closed. Check Experts log.");
}

// Delete only horizontal lines whose color matches the configured pink color.
void DeletePinkLines() {
   int deleted = 0;
   int failed = 0;
   for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if (ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_HLINE) continue;
      if ((color) ObjectGetInteger(0, name, OBJPROP_COLOR) != PointLineColor) continue;
      if (ObjectDelete(0, name)) deleted++;
      else {
         failed++;
         Print("Could not delete pink line: ", name, " error: ", GetLastError());
      }
   }
   ChartRedraw(0);
   Print("PinkLine Manager: deleted ", deleted, " pink horizontal line(s).");
   if (failed > 0) Fail("Some pink horizontal lines could not be deleted. Check Experts log.");
}

void OnChartEvent(const int id,
   const long & lparam,
      const double & dparam,
         const string & sparam) {
   if (id != CHARTEVENT_OBJECT_CLICK) return;
   for (int i = 0; i < 9; i++) {
      if (sparam != prefix + ids[i]) continue;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ChartRedraw();
      switch (i) {
      case 0:
         PlaceOrder(ORDER_TYPE_BUY);
         break;
      case 1:
         PlaceOrder(ORDER_TYPE_SELL);
         break;
      case 2:
         PlaceOrder(ORDER_TYPE_BUY_LIMIT);
         break;
      case 3:
         PlaceOrder(ORDER_TYPE_SELL_LIMIT);
         break;
      case 4:
         PlaceOrder(ORDER_TYPE_BUY_STOP);
         break;
      case 5:
         PlaceOrder(ORDER_TYPE_SELL_STOP);
         break;
      case 6:
         DeletePending();
         break;
      case 7:
         CloseAll();
         break;
      case 8:
         DeletePinkLines();
         break;
      }
      break;
   }
}
