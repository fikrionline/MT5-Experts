//+------------------------------------------------------------------+
//|                                           ManualTradeManager.mq5 |
//|                       Chart-button manual trading manager       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.02"
#property description "Manual trade manager with trade entry, TP/SL updates and close/delete controls."

#include <Trade/Trade.mqh>

input double InpLots                 = 1.00;       // Trading volume (lots)
input color  InpTakeProfitLineColor  = clrLime;   // TP horizontal-line color
input color  InpStopLossLineColor    = clrRed;    // SL horizontal-line color
input ulong  InpMagicNumber          = 575899;     // Magic number for new trades
input ulong  InpDeviationPoints      = 20;         // Maximum deviation (points)
input bool   InpCloseAllSymbols      = true;       // CLOSE ALL across the whole account?
input int    InpButtonWidth          = 110;        // Button width
input int    InpButtonHeight         = 32;         // Button height
input int    InpButtonGap            = 6;          // Gap between buttons

CTrade trade;

string PREFIX    = "MTM_";
string BTN_BUY   = "MTM_BUY";
string BTN_SELL  = "MTM_SELL";
string BTN_CHANGE_TP = "MTM_CHANGE_TP";
string BTN_CHANGE_SL = "MTM_CHANGE_SL";
string BTN_CLOSE = "MTM_CLOSE_ALL";
string BTN_DEL   = "MTM_DEL_LINE";

//+------------------------------------------------------------------+
//| Create a chart button                                            |
//+------------------------------------------------------------------+
bool CreateButton(const string name,
                  const string caption,
                  const int x,
                  const int y,
                  const color background,
                  const color foreground)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
   {
      Print("Failed to create button ", name, ". Error: ", GetLastError());
      return false;
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, InpButtonWidth);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, InpButtonHeight);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_COLOR, foreground);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, caption);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);

   return true;
}

//+------------------------------------------------------------------+
//| Center the button panel in the visible chart window              |
//+------------------------------------------------------------------+
void PositionPanel()
{
   long chart_width  = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   long chart_height = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   int panel_width  = 2 * InpButtonWidth + InpButtonGap;
   int panel_height = 3 * InpButtonHeight + 2 * InpButtonGap;
   int x = (int)((chart_width - panel_width) / 2);
   int y = (int)((chart_height - panel_height) / 2);

   // Keep the panel inside the chart if the chart is smaller than the panel.
   if(x < 0) x = 0;
   if(y < 0) y = 0;

   int step_x = InpButtonWidth + InpButtonGap;
   int step_y = InpButtonHeight + InpButtonGap;

   ObjectSetInteger(0, BTN_BUY,   OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BTN_BUY,   OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, BTN_SELL,  OBJPROP_XDISTANCE, x + step_x);
   ObjectSetInteger(0, BTN_SELL,  OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, BTN_CHANGE_TP, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BTN_CHANGE_TP, OBJPROP_YDISTANCE, y + step_y);
   ObjectSetInteger(0, BTN_CHANGE_SL, OBJPROP_XDISTANCE, x + step_x);
   ObjectSetInteger(0, BTN_CHANGE_SL, OBJPROP_YDISTANCE, y + step_y);
   ObjectSetInteger(0, BTN_CLOSE, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BTN_CLOSE, OBJPROP_YDISTANCE, y + 2 * step_y);
   ObjectSetInteger(0, BTN_DEL,   OBJPROP_XDISTANCE, x + step_x);
   ObjectSetInteger(0, BTN_DEL,   OBJPROP_YDISTANCE, y + 2 * step_y);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create all panel buttons                                         |
//+------------------------------------------------------------------+
void CreatePanel()
{
   CreateButton(BTN_BUY,       "BUY",       0, 0, clrForestGreen, clrWhite);
   CreateButton(BTN_SELL,      "SELL",      0, 0, clrFireBrick,   clrWhite);
   CreateButton(BTN_CHANGE_TP, "CHANGE TP", 0, 0, clrSeaGreen,    clrWhite);
   CreateButton(BTN_CHANGE_SL, "CHANGE SL", 0, 0, clrIndianRed,   clrWhite);
   CreateButton(BTN_CLOSE,     "CLOSE ALL", 0, 0, clrDodgerBlue,  clrWhite);
   CreateButton(BTN_DEL,       "DEL LINE",  0, 0, clrDimGray,     clrWhite);

   PositionPanel();
}

//+------------------------------------------------------------------+
//| Remove panel buttons                                             |
//+------------------------------------------------------------------+
void RemovePanel()
{
   ObjectDelete(0, BTN_BUY);
   ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_CHANGE_TP);
   ObjectDelete(0, BTN_CHANGE_SL);
   ObjectDelete(0, BTN_CLOSE);
   ObjectDelete(0, BTN_DEL);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Find the nearest matching horizontal line on the correct side   |
//+------------------------------------------------------------------+
bool FindNearestLine(const color target_color,
                     const bool is_take_profit,
                     const bool is_buy,
                     const double reference_price,
                     double &line_price)
{
   bool found = false;
   double best_distance = DBL_MAX;
   int total = ObjectsTotal(0, 0, -1);

   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(name == "")
         continue;

      if((ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_HLINE)
         continue;

      color object_color = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
      if(object_color != target_color)
         continue;

      double price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      if(price <= 0.0)
         continue;

      bool correct_side = false;

      if(is_buy)
      {
         if(is_take_profit)
            correct_side = (price > reference_price);
         else
            correct_side = (price < reference_price);
      }
      else
      {
         if(is_take_profit)
            correct_side = (price < reference_price);
         else
            correct_side = (price > reference_price);
      }

      if(!correct_side)
         continue;

      double distance = MathAbs(price - reference_price);
      if(distance < best_distance)
      {
         best_distance = distance;
         line_price = price;
         found = true;
      }
   }

   return found;
}

//+------------------------------------------------------------------+
//| Normalize requested volume to symbol volume rules                |
//+------------------------------------------------------------------+
double NormalizeLots(const string symbol, const double requested)
{
   double min_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || min_volume <= 0.0 || max_volume <= 0.0)
      return 0.0;

   double volume = MathMax(min_volume, MathMin(max_volume, requested));
   volume = MathFloor((volume + 1e-10) / step) * step;

   int digits = 0;
   double temp = step;
   while(digits < 8 && MathAbs(temp - MathRound(temp)) > 1e-8)
   {
      temp *= 10.0;
      digits++;
   }

   return NormalizeDouble(volume, digits);
}

//+------------------------------------------------------------------+
//| Open a market trade using matching chart lines                   |
//+------------------------------------------------------------------+
void OpenMarketTrade(const bool is_buy)
{
   string symbol = _Symbol;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("Trading is not allowed. Check the terminal and EA settings.");
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      Print("Cannot get current prices for ", symbol);
      return;
   }

   double entry_reference = is_buy ? tick.ask : tick.bid;
   double sl = 0.0;
   double tp = 0.0;
   double line_price = 0.0;

   if(FindNearestLine(InpTakeProfitLineColor, true, is_buy,
                      entry_reference, line_price))
      tp = NormalizeDouble(line_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   line_price = 0.0;
   if(FindNearestLine(InpStopLossLineColor, false, is_buy,
                      entry_reference, line_price))
      sl = NormalizeDouble(line_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   double lots = NormalizeLots(symbol, InpLots);
   if(lots <= 0.0)
   {
      Print("Invalid lot size. Check InpLots and the symbol volume settings.");
      return;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(symbol);
   trade.SetAsyncMode(false);

   bool result = false;

   if(is_buy)
      result = trade.Buy(lots, symbol, 0.0, sl, tp, "Manual Trade Manager BUY");
   else
      result = trade.Sell(lots, symbol, 0.0, sl, tp, "Manual Trade Manager SELL");

   if(result)
   {
      Print((is_buy ? "BUY" : "SELL"),
            " request accepted. Lots=", DoubleToString(lots, 8),
            " SL=", (sl == 0.0 ? "none" : DoubleToString(sl, _Digits)),
            " TP=", (tp == 0.0 ? "none" : DoubleToString(tp, _Digits)),
            ". Retcode=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
   }
   else
   {
      Print("Trade request failed. Retcode=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Find nearest horizontal line of a color, without direction filter|
//+------------------------------------------------------------------+
bool FindNearestColoredLine(const color target_color,
                            const double reference_price,
                            double &line_price)
{
   bool found = false;
   double best_distance = DBL_MAX;
   int total = ObjectsTotal(0, 0, -1);

   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if(name == "")
         continue;

      if((ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_HLINE)
         continue;

      if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != target_color)
         continue;

      double price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      if(price <= 0.0)
         continue;

      double distance = MathAbs(price - reference_price);
      if(distance < best_distance)
      {
         best_distance = distance;
         line_price = price;
         found = true;
      }
   }

   return found;
}

//+------------------------------------------------------------------+
//| Update TP or SL on all positions and pending orders for this      |
//| chart symbol. No matching line means remove that protection.     |
//+------------------------------------------------------------------+
void ChangeAllStops(const bool change_take_profit)
{
   const string symbol = _Symbol;
   const int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      Print("Cannot get current prices for ", symbol,
            ". CHANGE ", (change_take_profit ? "TP" : "SL"), " cancelled.");
      return;
   }

   double reference_price = (tick.bid + tick.ask) * 0.5;
   color target_color = change_take_profit ? InpTakeProfitLineColor
                                           : InpStopLossLineColor;

   double line_price = 0.0;
   bool has_line = FindNearestColoredLine(target_color, reference_price, line_price);
   if(has_line)
      line_price = NormalizeDouble(line_price, digits);

   trade.SetAsyncMode(false);
   int modified_positions = 0;
   int modified_pending = 0;
   int skipped = 0;
   int failed = 0;

   // Modify open positions on this chart symbol.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != symbol)
         continue;

      ENUM_POSITION_TYPE position_type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double old_sl = PositionGetDouble(POSITION_SL);
      double old_tp = PositionGetDouble(POSITION_TP);
      double new_sl = old_sl;
      double new_tp = old_tp;

      if(change_take_profit)
         new_tp = has_line ? line_price : 0.0;
      else
         new_sl = has_line ? line_price : 0.0;

      // Validate the line against the live market side for this position.
      if(has_line)
      {
         bool is_buy = (position_type == POSITION_TYPE_BUY);
         bool valid = true;

         if(change_take_profit)
            valid = is_buy ? (line_price > tick.bid) : (line_price < tick.ask);
         else
            valid = is_buy ? (line_price < tick.bid) : (line_price > tick.ask);

         if(!valid)
         {
            skipped++;
            Print("Skipped position #", ticket, ": ",
                  (change_take_profit ? "TP" : "SL"),
                  " line is on the wrong side of the market.");
            continue;
         }
      }

      if(trade.PositionModify(ticket, new_sl, new_tp))
         modified_positions++;
      else
      {
         failed++;
         Print("Failed to modify position #", ticket, ": ",
               trade.ResultRetcodeDescription());
      }
   }

   // Modify pending orders on this chart symbol too.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != symbol)
         continue;

      ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool is_buy_order = (order_type == ORDER_TYPE_BUY_LIMIT ||
                           order_type == ORDER_TYPE_BUY_STOP ||
                           order_type == ORDER_TYPE_BUY_STOP_LIMIT);
      bool is_sell_order = (order_type == ORDER_TYPE_SELL_LIMIT ||
                            order_type == ORDER_TYPE_SELL_STOP ||
                            order_type == ORDER_TYPE_SELL_STOP_LIMIT);

      // Ignore non-directional order types (if any).
      if(!is_buy_order && !is_sell_order)
      {
         skipped++;
         continue;
      }

      double old_sl = OrderGetDouble(ORDER_SL);
      double old_tp = OrderGetDouble(ORDER_TP);
      double new_sl = old_sl;
      double new_tp = old_tp;

      if(change_take_profit)
         new_tp = has_line ? line_price : 0.0;
      else
         new_sl = has_line ? line_price : 0.0;

      double order_entry = OrderGetDouble(ORDER_PRICE_OPEN);
      if(has_line)
      {
         bool valid = true;
         if(change_take_profit)
            valid = is_buy_order ? (line_price > order_entry)
                                 : (line_price < order_entry);
         else
            valid = is_buy_order ? (line_price < order_entry)
                                 : (line_price > order_entry);

         if(!valid)
         {
            skipped++;
            Print("Skipped pending order #", ticket, ": ",
                  (change_take_profit ? "TP" : "SL"),
                  " line is on the wrong side of its entry price.");
            continue;
         }
      }

      double order_price = OrderGetDouble(ORDER_PRICE_OPEN);
      double stop_limit = OrderGetDouble(ORDER_PRICE_STOPLIMIT);
      ENUM_ORDER_TYPE_TIME time_type =
         (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
      datetime expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);

      if(trade.OrderModify(ticket, order_price, new_sl, new_tp,
                           time_type, expiration, stop_limit))
         modified_pending++;
      else
      {
         failed++;
         Print("Failed to modify pending order #", ticket, ": ",
               trade.ResultRetcodeDescription());
      }
   }

   Print("CHANGE ", (change_take_profit ? "TP" : "SL"),
         " finished for ", symbol,
         ". Line=", (has_line ? DoubleToString(line_price, digits) : "none (removed)"),
         ", positions modified=", modified_positions,
         ", pending orders modified=", modified_pending,
         ", skipped=", skipped, ", failed=", failed);
}

//+------------------------------------------------------------------+
//| Close positions and delete pending orders                        |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   trade.SetAsyncMode(false);

   int closed_positions = 0;
   int deleted_orders = 0;
   int failed_actions = 0;

   // Close open positions, iterating backwards because the list changes.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!InpCloseAllSymbols && symbol != _Symbol)
         continue;

      if(trade.PositionClose(ticket))
         closed_positions++;
      else
      {
         failed_actions++;
         Print("Failed to close position #", ticket, ": ",
               trade.ResultRetcodeDescription());
      }
   }

   // Delete pending orders, including limit, stop and stop-limit orders.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      if(!InpCloseAllSymbols && symbol != _Symbol)
         continue;

      if(trade.OrderDelete(ticket))
         deleted_orders++;
      else
      {
         failed_actions++;
         Print("Failed to delete pending order #", ticket, ": ",
               trade.ResultRetcodeDescription());
      }
   }

   Print("CLOSE ALL finished. Positions closed=", closed_positions,
         ", pending orders deleted=", deleted_orders,
         ", failed actions=", failed_actions);
}

//+------------------------------------------------------------------+
//| Delete horizontal lines from the current chart                   |
//+------------------------------------------------------------------+
void DeleteHorizontalLines()
{
   int deleted = 0;

   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(name == "")
         continue;

      if((ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_HLINE)
      {
         if(ObjectDelete(0, name))
            deleted++;
      }
   }

   Print("DEL LINE: deleted ", deleted, " horizontal line(s) from this chart.");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   CreatePanel();
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);

   Print("Manual Trade Manager initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemovePanel();
}

//+------------------------------------------------------------------+
//| Handle chart button clicks                                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      PositionPanel();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == BTN_BUY)
   {
      ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
      OpenMarketTrade(true);
   }
   else if(sparam == BTN_SELL)
   {
      ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
      OpenMarketTrade(false);
   }
   else if(sparam == BTN_CHANGE_TP)
   {
      ObjectSetInteger(0, BTN_CHANGE_TP, OBJPROP_STATE, false);
      ChangeAllStops(true);
   }
   else if(sparam == BTN_CHANGE_SL)
   {
      ObjectSetInteger(0, BTN_CHANGE_SL, OBJPROP_STATE, false);
      ChangeAllStops(false);
   }
   else if(sparam == BTN_CLOSE)
   {
      ObjectSetInteger(0, BTN_CLOSE, OBJPROP_STATE, false);
      CloseAllTrades();
   }
   else if(sparam == BTN_DEL)
   {
      ObjectSetInteger(0, BTN_DEL, OBJPROP_STATE, false);
      DeleteHorizontalLines();
   }

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
