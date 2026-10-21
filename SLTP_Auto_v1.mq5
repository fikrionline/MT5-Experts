//+------------------------------------------------------------------+
//|                         AutoSLTP_Percent.mq5                     |
//|      Auto add SL by % balance and TP by Reward Multiplier        |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//--- input
input double RiskPercent      = 1.0;   // Stop Loss (% balance)
input double RewardMultiplier = 2.2;   // TP = SL x multiplier
input bool   ModifyMarket     = true;  // Modify open positions
input bool   ModifyPending    = true;  // Modify pending orders

//+------------------------------------------------------------------+
//| Calculate SL distance in points based on % balance               |
//+------------------------------------------------------------------+
double CalculateSLPoints(string symbol, double volume)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickValue <= 0 || tickSize <= 0 || volume <= 0)
      return 0;

   double valuePerPoint = (tickValue / tickSize) * point * volume;

   if(valuePerPoint <= 0)
      return 0;

   double slPoints = riskMoney / valuePerPoint;

   return MathMax(slPoints, 1);
}

//+------------------------------------------------------------------+
//| Process market positions                                         |
//+------------------------------------------------------------------+
void ProcessPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);

      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      // Skip if already has SL and TP
      if(sl != 0.0 && tp != 0.0)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);

      double slPoints = CalculateSLPoints(symbol, volume);
      if(slPoints <= 0)
         continue;

      double tpPoints = slPoints * RewardMultiplier;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      double newSL, newTP;

      if(type == POSITION_TYPE_BUY)
      {
         newSL = openPrice - slPoints * point;
         newTP = openPrice + tpPoints * point;
      }
      else
      {
         newSL = openPrice + slPoints * point;
         newTP = openPrice - tpPoints * point;
      }

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      newSL = NormalizeDouble(newSL, digits);
      newTP = NormalizeDouble(newTP, digits);

      trade.PositionModify(ticket, newSL, newTP);
   }
}

//+------------------------------------------------------------------+
//| Process pending orders                                           |
//+------------------------------------------------------------------+
void ProcessPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      // Only pending orders
      if(type != ORDER_TYPE_BUY_LIMIT &&
         type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP &&
         type != ORDER_TYPE_SELL_STOP &&
         type != ORDER_TYPE_BUY_STOP_LIMIT &&
         type != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      double sl = OrderGetDouble(ORDER_SL);
      double tp = OrderGetDouble(ORDER_TP);

      // Skip if already has SL and TP
      if(sl != 0.0 && tp != 0.0)
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price  = OrderGetDouble(ORDER_PRICE_OPEN);

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      double slPoints = CalculateSLPoints(symbol, volume);
      if(slPoints <= 0)
         continue;

      double tpPoints = slPoints * RewardMultiplier;

      double newSL, newTP;

      if(type == ORDER_TYPE_BUY_LIMIT ||
         type == ORDER_TYPE_BUY_STOP ||
         type == ORDER_TYPE_BUY_STOP_LIMIT)
      {
         newSL = price - slPoints * point;
         newTP = price + tpPoints * point;
      }
      else
      {
         newSL = price + slPoints * point;
         newTP = price - tpPoints * point;
      }

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      newSL = NormalizeDouble(newSL, digits);
      newTP = NormalizeDouble(newTP, digits);

      trade.OrderModify(ticket, price, newSL, newTP, ORDER_TIME_GTC, 0);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(ModifyMarket)
      ProcessPositions();

   if(ModifyPending)
      ProcessPendingOrders();
}
//+------------------------------------------------------------------+
