//+------------------------------------------------------------------+
//|                                               Force_SLTP_All.mq5 |
//|                                 Force same SL/TP to all orders   |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//--- Inputs
//input bool   UseAllSymbols = true;   // true = all symbols, false = current symbol
input double StopLossPrice = 4222.66; // Fixed SL price
input double TakeProfitPrice = 4371.69; // Fixed TP price
enum TheAreYouSure {
   Yes,
   No
};
input TheAreYouSure AreYouSure = No;

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   ModifyAllPositions();
   ModifyAllPendingOrders();
}

//+------------------------------------------------------------------+
//| Modify all open positions                                        |
//+------------------------------------------------------------------+
void ModifyAllPositions() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);

      if (PositionSelectByTicket(ticket)) {
         string symbol = PositionGetString(POSITION_SYMBOL);

         //if(!UseAllSymbols && symbol != _Symbol)
         if (symbol != _Symbol && AreYouSure != Yes)
            continue;

         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);

         // Modify only if different
         if (NormalizeDouble(sl, _Digits) != NormalizeDouble(StopLossPrice, _Digits) ||
            NormalizeDouble(tp, _Digits) != NormalizeDouble(TakeProfitPrice, _Digits)) {
            if (trade.PositionModify(ticket, StopLossPrice, TakeProfitPrice)) {
               Print("Position modified: ", ticket,
                  " SL=", StopLossPrice,
                  " TP=", TakeProfitPrice);
            } else {
               Print("Failed to modify position: ", ticket,
                  " Error=", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify all pending orders                                        |
//+------------------------------------------------------------------+
void ModifyAllPendingOrders() {
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);

      if (OrderSelect(ticket)) {
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE) OrderGetInteger(ORDER_TYPE);

         // Only pending limit orders (can add stop orders if needed)
         if (type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
            continue;

         string symbol = OrderGetString(ORDER_SYMBOL);

         //if(!UseAllSymbols && symbol != _Symbol)
         if (symbol != _Symbol && AreYouSure != Yes)
            continue;

         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         double sl = OrderGetDouble(ORDER_SL);
         double tp = OrderGetDouble(ORDER_TP);
         datetime expiration = (datetime) OrderGetInteger(ORDER_TIME_EXPIRATION);

         if (NormalizeDouble(sl, _Digits) != NormalizeDouble(StopLossPrice, _Digits) ||
            NormalizeDouble(tp, _Digits) != NormalizeDouble(TakeProfitPrice, _Digits)) {
            if (trade.OrderModify(ticket, price, StopLossPrice, TakeProfitPrice,
                  ORDER_TIME_SPECIFIED, expiration)) {
               Print("Pending order modified: ", ticket,
                  " SL=", StopLossPrice,
                  " TP=", TakeProfitPrice);
            } else {
               Print("Failed to modify order: ", ticket,
                  " Error=", GetLastError());
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
