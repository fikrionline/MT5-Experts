//+------------------------------------------------------------------+
//|                    Levels_20_80_EA.mq5                          |
//|                    Levels Trading Expert Advisor                 |
//+------------------------------------------------------------------+
#property copyright "Levels 20/80 EA"
#property version "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "=== LEVEL SETTINGS ==="

int BaseStep = 100;
int BarsBack = 500;
int BarsForward = 50;

input double ReminderA = 67;
input double ReminderB = 55;

input color colorReminderA = clrDarkGreen;
input color colorReminderB = clrMaroon;

input group "=== TRADING SETTINGS ==="

input double LotSize = 1.00;
input ulong MagicNumber = 1002080;

input group "=== TRAILING STOP SETTINGS ==="
input bool   EnableTrailingStop     = true;   // Enable or disable trailing stop
input double TrailingLockPercent    = 50.0;   // Lock this percentage of floating profit
input double MinimalFloatingProfit  = 100.00; // Minimal Profir before TraingStop Active    

//+------------------------------------------------------------------+
//| BUTTON SETTINGS                                                  |
//+------------------------------------------------------------------+

#define BTN_BUY "L2080_BTN_BUY"
#define BTN_SELL "L2080_BTN_SELL"
#define BTN_DELETE "L2080_BTN_DELETE"

#define BUTTON_WIDTH 99
#define BUTTON_HEIGHT 29
#define BUTTON_GAP 8

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+

int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   CreateButtons();
   DrawLevels();
   ChartRedraw();
   return (INIT_SUCCEEDED);
}
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "L2080_");
   ChartRedraw();
}
void OnTick() {
   DrawLevels();
   ManageTrailingStops();
}
void OnChartEvent(const int id,
   const long & lparam,
      const double & dparam,
         const string & sparam) {
   if (id == CHARTEVENT_CHART_CHANGE) {
      CreateButtons();
      ChartRedraw();
   }
   if (id == CHARTEVENT_OBJECT_CLICK) {
      if (sparam == BTN_BUY) {
         ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
         PlaceBuyLimit();
         ChartRedraw();
      }
      if (sparam == BTN_SELL) {
         ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
         PlaceSellLimit();
         ChartRedraw();
      }
      if (sparam == BTN_DELETE) {
         ObjectSetInteger(0, BTN_DELETE, OBJPROP_STATE, false);
         DeletePendingOrders();
         ChartRedraw();
      }
   }
}
void CreateButtons() {
   int chartWidth = (int) ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartHeight = (int) ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int totalWidth = BUTTON_WIDTH * 3 + BUTTON_GAP * 2;
   int startX = (chartWidth - totalWidth) / 2;
   int startY = (chartHeight - BUTTON_HEIGHT) / 2;
   CreateButton(BTN_BUY, "BUY LIMIT", startX, startY, clrDarkGreen);
   CreateButton(BTN_SELL, "SELL LIMIT", startX + BUTTON_WIDTH + BUTTON_GAP, startY, clrMaroon);
   CreateButton(BTN_DELETE, "DEL PENDING", startX + (BUTTON_WIDTH + BUTTON_GAP) * 2, startY, clrDimGray);
}
void CreateButton(string name, string text, int x, int y, color bgColor) {
   if (ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BUTTON_WIDTH);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BUTTON_HEIGHT);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
}
void DrawLevels() {
   if (BaseStep <= 0) return;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (price <= 0) return;
   double minPrice = price - 2000;
   double maxPrice = price + 2000;
   int startBlock = (int) MathFloor(minPrice / BaseStep);
   int endBlock = (int) MathCeil(maxPrice / BaseStep);
   datetime t1 = iTime(_Symbol, _Period, BarsBack);
   if (t1 == 0) {
      int totalBars = Bars(_Symbol, _Period);
      if (totalBars <= 0) return;
      t1 = iTime(_Symbol, _Period, totalBars - 1);
   }
   if (t1 == 0) return;
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * BarsForward;
   for (int b = startBlock; b <= endBlock; b++) {
      double base = b * BaseStep;
      double level20 = base + ReminderA;
      double level80 = base + ReminderB;
      DrawLine(level20, colorReminderA, t1, t2);
      DrawLine(level80, colorReminderB, t1, t2);
   }
}
void DrawLine(double price, color clr, datetime t1, datetime t2) {
   string name = "L2080_" + DoubleToString(price, _Digits);
   if (ObjectFind(0, name) >= 0) return;
   if (!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price)) {
      return;
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOTDOT);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}
double NormalizeToTick(double price) {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0) tickSize = _Point;
   price = MathRound(price / tickSize) * tickSize;
   return NormalizeDouble(price, _Digits);
}
double FindBuyLimitLevel() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minDistance = DBL_MAX;
   double bestPrice = 0;
   int startBlock = (int) MathFloor((ask - 2000) / BaseStep);
   int endBlock = (int) MathCeil((ask + 2000) / BaseStep);
   for (int b = startBlock; b <= endBlock; b++) {
      double base = b * BaseStep;
      double levels[2];
      levels[0] = NormalizeToTick(base + ReminderA);
      levels[1] = NormalizeToTick(base + ReminderB);
      for (int i = 0; i < 2; i++) {
         double level = levels[i];
         if (level >= ask) continue;
         if ((ask - level) < stopsLevel) continue;
         double distance = ask - level;
         if (distance < minDistance) {
            minDistance = distance;
            bestPrice = level;
         }
      }
   }
   return bestPrice;
}
double FindSellLimitLevel() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minDistance = DBL_MAX;
   double bestPrice = 0;
   int startBlock = (int) MathFloor((bid - 2000) / BaseStep);
   int endBlock = (int) MathCeil((bid + 2000) / BaseStep);
   for (int b = startBlock; b <= endBlock; b++) {
      double base = b * BaseStep;
      double levels[2];
      levels[0] = NormalizeToTick(base + ReminderA);
      levels[1] = NormalizeToTick(base + ReminderB);
      for (int i = 0; i < 2; i++) {
         double level = levels[i];
         if (level <= bid) continue;
         if ((level - bid) < stopsLevel) continue;
         double distance = level - bid;
         if (distance < minDistance) {
            minDistance = distance;
            bestPrice = level;
         }
      }
   }
   return bestPrice;
}
void PlaceBuyLimit() {
   double price = FindBuyLimitLevel();
   if (price <= 0) {
      Alert("No valid BUY LIMIT level found!");
      return;
   }
   bool result = trade.BuyLimit(LotSize, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "L2080 Buy Limit");
   if (result) {
      Print("BUY LIMIT placed at ", DoubleToString(price, _Digits));
   } else {
      Alert("BUY LIMIT failed: ", trade.ResultRetcodeDescription());
      Print("BUY LIMIT error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}
void PlaceSellLimit() {
   double price = FindSellLimitLevel();
   if (price <= 0) {
      Alert("No valid SELL LIMIT level found!");
      return;
   }
   bool result = trade.SellLimit(LotSize, price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, "L2080 Sell Limit");
   if (result) {
      Print("SELL LIMIT placed at ", DoubleToString(price, _Digits));
   } else {
      Alert("SELL LIMIT failed: ", trade.ResultRetcodeDescription());
      Print("SELL LIMIT error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| PROFIT-BASED TRAILING STOP                                       |
//| Example: 50% locks $50 when floating profit is $100.             |
//+------------------------------------------------------------------+
void ManageTrailingStops() {
   if (!EnableTrailingStop) return;
   if (TrailingLockPercent <= 0.0) return;
   if (PositionGetDouble(POSITION_PROFIT) < MinimalFloatingProfit) return;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if (tickValue <= 0.0)
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if (tickSize <= 0.0 || tickValue <= 0.0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (bid <= 0.0 || ask <= 0.0 || point <= 0.0) return;

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minimumDistance = (double)MathMax(stopsLevel, freezeLevel) * point;

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if (symbol != _Symbol || magic != MagicNumber) continue;

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double floatingProfit = PositionGetDouble(POSITION_PROFIT);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if (volume <= 0.0 || floatingProfit <= 0.0) continue;

      // Convert the desired locked profit (account currency) into a price distance.
      double lockedProfit = floatingProfit * TrailingLockPercent / 100.0;
      double priceDistance = (lockedProfit / (tickValue * volume)) * tickSize;
      if (priceDistance <= 0.0) continue;

      double newSL = 0.0;
      if (positionType == POSITION_TYPE_BUY) {
         newSL = NormalizeToTick(openPrice + priceDistance);
         // SL must remain below the current Bid and outside broker stop/freeze levels.
         if (newSL >= bid || (bid - newSL) < minimumDistance) continue;
         // Never loosen an existing stop loss.
         if (currentSL > 0.0 && newSL <= currentSL + tickSize * 0.5) continue;
      } else if (positionType == POSITION_TYPE_SELL) {
         newSL = NormalizeToTick(openPrice - priceDistance);
         // SL must remain above the current Ask and outside broker stop/freeze levels.
         if (newSL <= ask || (newSL - ask) < minimumDistance) continue;
         // Never loosen an existing stop loss.
         if (currentSL > 0.0 && newSL >= currentSL - tickSize * 0.5) continue;
      } else {
         continue;
      }

      if (!trade.PositionModify(ticket, newSL, currentTP)) {
         Print("Trailing stop modification failed for position ", ticket,
               ": ", trade.ResultRetcodeDescription());
      } else {
         Print("Trailing stop updated for position ", ticket,
               ". Locked profit target: ", DoubleToString(lockedProfit, 2),
               " | New SL: ", DoubleToString(newSL, _Digits));
      }
   }
}

void DeletePendingOrders() {
   int deleted = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if (ticket == 0) continue;
      string symbol = OrderGetString(ORDER_SYMBOL);
      ulong magic = (ulong) OrderGetInteger(ORDER_MAGIC);
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE);
      if (symbol != _Symbol) continue;
      if (magic != MagicNumber) continue;
      if (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT) {
         if (trade.OrderDelete(ticket)) {
            deleted++;
            Print("Pending order deleted: ", ticket);
         } else {
            Print("Failed to delete order ", ticket, ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}
