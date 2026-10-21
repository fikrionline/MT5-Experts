//+------------------------------------------------------------------+
//|                                             HOLO_EA.mq5          |
//| Highest Open / Lowest Open Trading EA                            |
//| Based on HOLO methodology                                        |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUTS
//====================================================================

//--- HOLO signal settings
input ENUM_TIMEFRAMES InpConfirmationTF = PERIOD_M15;  // Signal timeframe
input double          InpLotSize        = 0.01;        // Lot size
input double          InpRiskReward     = 1.20;        // Risk : Reward
input ulong           InpMagicNumber    = 590623;      // Magic number
input int             InpDeviationPoints = 20;         // Deviation

//--- Signal control
input bool InpOneTradePerSetup = true;

//--- Trailing Stop
input bool InpEnableTrailingStop = true;
input int  InpTrailingStart      = 500;   // Start trailing after X points profit
input int  InpTrailingDistance   = 300;   // SL distance from current price
input int  InpTrailingStep       = 50;    // Minimum SL movement

//--- Horizontal lines
input bool InpShowLines = true;

input color InpHighestTodayColor = clrRed;
input color InpHighestOpenColor  = clrOrange;
input color InpLowestTodayColor  = clrBlue;
input color InpLowestOpenColor   = clrAqua;

input ENUM_LINE_STYLE InpLineStyle = STYLE_SOLID;
input int             InpLineWidth = 1;


//====================================================================
// GLOBAL VARIABLES
//====================================================================

datetime g_lastSignalBar = 0;

double g_highestOpenToday = 0.0;
double g_lowestOpenToday  = 0.0;

double g_todayHigh = 0.0;
double g_todayLow  = 0.0;


//====================================================================
// OBJECT NAMES
//====================================================================

string LINE_HIGHEST_TODAY = "HOLO_Highest_Today";
string LINE_HIGHEST_OPEN  = "HOLO_Highest_Open_Today";
string LINE_LOWEST_TODAY = "HOLO_Lowest_Today";
string LINE_LOWEST_OPEN   = "HOLO_Lowest_Open_Today";


//====================================================================
// ON INIT
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   if(InpLotSize <= 0.0)
   {
      Print("ERROR: Lot size must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpRiskReward < 0.0)
   {
      Print("ERROR: Risk Reward cannot be negative.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpTrailingStart < 0 ||
      InpTrailingDistance <= 0 ||
      InpTrailingStep <= 0)
   {
      Print("ERROR: Invalid trailing stop parameters.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpShowLines)
   {
      CreateHorizontalLine(
         LINE_HIGHEST_TODAY,
         InpHighestTodayColor,
         "Highest Today"
      );

      CreateHorizontalLine(
         LINE_HIGHEST_OPEN,
         InpHighestOpenColor,
         "Highest Open Today"
      );

      CreateHorizontalLine(
         LINE_LOWEST_TODAY,
         InpLowestTodayColor,
         "Lowest Today"
      );

      CreateHorizontalLine(
         LINE_LOWEST_OPEN,
         InpLowestOpenColor,
         "Lowest Open Today"
      );
   }

   Print("HOLO EA initialized successfully.");

   return(INIT_SUCCEEDED);
}


//====================================================================
// ON DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   ObjectDelete(0, LINE_HIGHEST_TODAY);
   ObjectDelete(0, LINE_HIGHEST_OPEN);
   ObjectDelete(0, LINE_LOWEST_TODAY);
   ObjectDelete(0, LINE_LOWEST_OPEN);

   ChartRedraw(0);
}


//====================================================================
// ON TICK
//====================================================================

void OnTick()
{
   //--- Always update today's levels
   if(!UpdateTodayLevels())
      return;

   //--- Update horizontal lines
   if(InpShowLines)
      UpdateHorizontalLines();

   //--- Manage trailing stop first
   if(InpEnableTrailingStop)
      ManageTrailingStop();

   //--- Only one position at a time for this EA/symbol
   if(HasOpenPosition())
      return;

   //--- Check HOLO signal
   CheckHOLOSignal();
}


//====================================================================
// GET START OF TODAY
//====================================================================

datetime GetStartOfToday()
{
   MqlDateTime dt;

   TimeToStruct(TimeCurrent(), dt);

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   return StructToTime(dt);
}


//====================================================================
// UPDATE TODAY'S LEVELS
//====================================================================

bool UpdateTodayLevels()
{
   datetime dayStart = GetStartOfToday();
   datetime now      = TimeCurrent();

   //--- Make sure we have enough history
   if(now <= dayStart)
      return false;

   //==============================================================
   // H1 DATA
   // Used for Highest Open / Lowest Open
   //==============================================================

   MqlRates h1Rates[];

   ArraySetAsSeries(h1Rates, false);

   int h1Count = CopyRates(
      _Symbol,
      PERIOD_H1,
      dayStart,
      now,
      h1Rates
   );

   if(h1Count <= 0)
   {
      Print("Unable to retrieve H1 data. Error: ", GetLastError());
      return false;
   }

   g_highestOpenToday = -DBL_MAX;
   g_lowestOpenToday  = DBL_MAX;

   for(int i = 0; i < h1Count; i++)
   {
      if(h1Rates[i].open > g_highestOpenToday)
         g_highestOpenToday = h1Rates[i].open;

      if(h1Rates[i].open < g_lowestOpenToday)
         g_lowestOpenToday = h1Rates[i].open;
   }


   //==============================================================
   // M1 DATA
   // Used for Today's Highest / Lowest Price
   //==============================================================

   MqlRates dayRates[];

   ArraySetAsSeries(dayRates, false);

   int dayCount = CopyRates(
      _Symbol,
      PERIOD_M1,
      dayStart,
      now,
      dayRates
   );

   if(dayCount <= 0)
   {
      Print("Unable to retrieve M1 data. Error: ", GetLastError());
      return false;
   }

   g_todayHigh = -DBL_MAX;
   g_todayLow  = DBL_MAX;

   for(int i = 0; i < dayCount; i++)
   {
      if(dayRates[i].high > g_todayHigh)
         g_todayHigh = dayRates[i].high;

      if(dayRates[i].low < g_todayLow)
         g_todayLow = dayRates[i].low;
   }

   return true;
}


//====================================================================
// CREATE HORIZONTAL LINE
//====================================================================

void CreateHorizontalLine(
   string name,
   color lineColor,
   string description
)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(
         0,
         name,
         OBJ_HLINE,
         0,
         0,
         0
      ))
      {
         Print(
            "Failed to create line ",
            name,
            ". Error: ",
            GetLastError()
         );

         return;
      }
   }

   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      lineColor
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_STYLE,
      InpLineStyle
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
      true
   );

   ObjectSetString(
      0,
      name,
      OBJPROP_TOOLTIP,
      description
   );
}


//====================================================================
// UPDATE HORIZONTAL LINES
//====================================================================

void UpdateHorizontalLines()
{
   if(g_todayHigh > 0.0)
   {
      ObjectSetDouble(
         0,
         LINE_HIGHEST_TODAY,
         OBJPROP_PRICE,
         g_todayHigh
      );
   }

   if(g_highestOpenToday > 0.0)
   {
      ObjectSetDouble(
         0,
         LINE_HIGHEST_OPEN,
         OBJPROP_PRICE,
         g_highestOpenToday
      );
   }

   if(g_todayLow > 0.0)
   {
      ObjectSetDouble(
         0,
         LINE_LOWEST_TODAY,
         OBJPROP_PRICE,
         g_todayLow
      );
   }

   if(g_lowestOpenToday > 0.0)
   {
      ObjectSetDouble(
         0,
         LINE_LOWEST_OPEN,
         OBJPROP_PRICE,
         g_lowestOpenToday
      );
   }

   ChartRedraw(0);
}


//====================================================================
// CHECK HOLO SIGNAL
//====================================================================

void CheckHOLOSignal()
{
   if(g_highestOpenToday <= 0.0 ||
      g_lowestOpenToday <= 0.0)
      return;

   //--- Get current confirmation timeframe candle
   MqlRates confirmRates[];

   ArraySetAsSeries(confirmRates, true);

   int copied = CopyRates(
      _Symbol,
      InpConfirmationTF,
      0,
      3,
      confirmRates
   );

   if(copied < 1)
      return;

   //--- Current confirmation candle
   double currentOpen = confirmRates[0].open;

   datetime currentBarTime = confirmRates[0].time;

   //==============================================================
   // SELL SETUP
   //
   // Confirmation candle OPEN must be above
   // today's Highest H1 Open.
   //
   // Current price then comes back DOWN to that level.
   //==============================================================

   if(currentOpen > g_highestOpenToday)
   {
      double bid = SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

      if(bid <= g_highestOpenToday)
      {
         //--- Prevent repeated signal on same candle
         if(InpOneTradePerSetup &&
            g_lastSignalBar == currentBarTime)
         {
            return;
         }

         if(OpenSell())
         {
            g_lastSignalBar = currentBarTime;
         }

         return;
      }
   }


   //==============================================================
   // BUY SETUP
   //
   // Confirmation candle OPEN must be below
   // today's Lowest H1 Open.
   //
   // Current price then comes back UP to that level.
   //==============================================================

   if(currentOpen < g_lowestOpenToday)
   {
      double ask = SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

      if(ask >= g_lowestOpenToday)
      {
         //--- Prevent repeated signal on same candle
         if(InpOneTradePerSetup &&
            g_lastSignalBar == currentBarTime)
         {
            return;
         }

         if(OpenBuy())
         {
            g_lastSignalBar = currentBarTime;
         }

         return;
      }
   }
}


//====================================================================
// OPEN BUY
//====================================================================

bool OpenBuy()
{
   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   if(ask <= 0.0)
      return false;

   //--- Initial SL = today's lowest price
   double sl = g_todayLow;

   if(sl <= 0.0)
      return false;

   //--- SL must be below entry
   if(sl >= ask)
   {
      Print(
         "BUY rejected: Today's Low is not below entry."
      );

      return false;
   }

   //--- Calculate risk
   double risk = ask - sl;

   //--- Calculate TP
   double tp = 0.0;

   if(InpRiskReward > 0.0)
      tp = ask + (risk * InpRiskReward);

   //--- Normalize
   sl = NormalizePrice(sl);

   if(tp > 0.0)
      tp = NormalizePrice(tp);

   //--- Check broker minimum stop distance
   if(!CheckBuyStops(ask, sl, tp))
      return false;

   //--- Normalize lot
   double lot = NormalizeLot(InpLotSize);

   if(lot <= 0.0)
      return false;

   //--- Open BUY
   bool result = trade.Buy(
      lot,
      _Symbol,
      0.0,
      sl,
      tp,
      "HOLO BUY"
   );

   if(!result)
   {
      Print(
         "BUY failed. Retcode: ",
         trade.ResultRetcode(),
         " - ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }

   Print(
      "HOLO BUY opened. Entry=",
      DoubleToString(ask, _Digits),
      " SL=",
      DoubleToString(sl, _Digits),
      " TP=",
      DoubleToString(tp, _Digits)
   );

   return true;
}


//====================================================================
// OPEN SELL
//====================================================================

bool OpenSell()
{
   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   if(bid <= 0.0)
      return false;

   //--- Initial SL = today's highest price
   double sl = g_todayHigh;

   if(sl <= 0.0)
      return false;

   //--- SL must be above entry
   if(sl <= bid)
   {
      Print(
         "SELL rejected: Today's High is not above entry."
      );

      return false;
   }

   //--- Calculate risk
   double risk = sl - bid;

   //--- Calculate TP
   double tp = 0.0;

   if(InpRiskReward > 0.0)
      tp = bid - (risk * InpRiskReward);

   //--- Normalize
   sl = NormalizePrice(sl);

   if(tp > 0.0)
      tp = NormalizePrice(tp);

   //--- Check broker minimum stop distance
   if(!CheckSellStops(bid, sl, tp))
      return false;

   //--- Normalize lot
   double lot = NormalizeLot(InpLotSize);

   if(lot <= 0.0)
      return false;

   //--- Open SELL
   bool result = trade.Sell(
      lot,
      _Symbol,
      0.0,
      sl,
      tp,
      "HOLO SELL"
   );

   if(!result)
   {
      Print(
         "SELL failed. Retcode: ",
         trade.ResultRetcode(),
         " - ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }

   Print(
      "HOLO SELL opened. Entry=",
      DoubleToString(bid, _Digits),
      " SL=",
      DoubleToString(sl, _Digits),
      " TP=",
      DoubleToString(tp, _Digits)
   );

   return true;
}


//====================================================================
// TRAILING STOP
//====================================================================

void ManageTrailingStop()
{
   int totalPositions = PositionsTotal();

   if(totalPositions <= 0)
      return;

   double point = SymbolInfoDouble(
      _Symbol,
      SYMBOL_POINT
   );

   if(point <= 0.0)
      return;

   //--- Broker stop/freeze distance
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   long freezeLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_FREEZE_LEVEL
      );

   long minimumLevel = MathMax(
      stopsLevel,
      freezeLevel
   );

   double minimumDistance =
      (double)minimumLevel * point;

   double trailingStart =
      (double)InpTrailingStart * point;

   double trailingDistance =
      (double)InpTrailingDistance * point;

   double trailingStep =
      (double)InpTrailingStep * point;


   //==============================================================
   // LOOP THROUGH POSITIONS
   //==============================================================

   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      //--- Only this symbol
      string symbol =
         PositionGetString(POSITION_SYMBOL);

      if(symbol != _Symbol)
         continue;

      //--- Only this EA's positions
      ulong magic =
         (ulong)PositionGetInteger(POSITION_MAGIC);

      if(magic != InpMagicNumber)
         continue;


      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(POSITION_TYPE);

      double openPrice =
         PositionGetDouble(POSITION_PRICE_OPEN);

      double currentSL =
         PositionGetDouble(POSITION_SL);

      double currentTP =
         PositionGetDouble(POSITION_TP);


      //============================================================
      // BUY TRAILING
      //============================================================

      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(
            _Symbol,
            SYMBOL_BID
         );

         if(bid <= 0.0)
            continue;

         //--- Current profit in price
         double profitDistance =
            bid - openPrice;

         //--- Trailing has not started yet
         if(profitDistance < trailingStart)
            continue;

         //--- New trailing SL
         double newSL =
            bid - trailingDistance;

         newSL = NormalizePrice(newSL);

         //--- SL must remain below current Bid
         if(newSL >= bid)
            continue;

         //--- Broker minimum distance
         if((bid - newSL) < minimumDistance)
            continue;

         //--- Never move SL backwards
         if(currentSL > 0.0 &&
            newSL <= currentSL)
         {
            continue;
         }

         //--- Only move if improvement is at least trailing step
         if(currentSL > 0.0 &&
            (newSL - currentSL) < trailingStep)
         {
            continue;
         }

         //--- Modify position
         if(trade.PositionModify(
               ticket,
               newSL,
               currentTP
            ))
         {
            Print(
               "BUY trailing SL moved to ",
               DoubleToString(newSL, _Digits)
            );
         }
         else
         {
            Print(
               "BUY trailing modification failed. Ticket=",
               ticket,
               " Retcode=",
               trade.ResultRetcode(),
               " - ",
               trade.ResultRetcodeDescription()
            );
         }
      }


      //============================================================
      // SELL TRAILING
      //============================================================

      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(
            _Symbol,
            SYMBOL_ASK
         );

         if(ask <= 0.0)
            continue;

         //--- Current profit in price
         double profitDistance =
            openPrice - ask;

         //--- Trailing has not started yet
         if(profitDistance < trailingStart)
            continue;

         //--- New trailing SL
         double newSL =
            ask + trailingDistance;

         newSL = NormalizePrice(newSL);

         //--- SL must remain above current Ask
         if(newSL <= ask)
            continue;

         //--- Broker minimum distance
         if((newSL - ask) < minimumDistance)
            continue;

         //--- Never move SL backwards
         if(currentSL > 0.0 &&
            newSL >= currentSL)
         {
            continue;
         }

         //--- Only move if improvement is at least trailing step
         if(currentSL > 0.0 &&
            (currentSL - newSL) < trailingStep)
         {
            continue;
         }

         //--- Modify position
         if(trade.PositionModify(
               ticket,
               newSL,
               currentTP
            ))
         {
            Print(
               "SELL trailing SL moved to ",
               DoubleToString(newSL, _Digits)
            );
         }
         else
         {
            Print(
               "SELL trailing modification failed. Ticket=",
               ticket,
               " Retcode=",
               trade.ResultRetcode(),
               " - ",
               trade.ResultRetcodeDescription()
            );
         }
      }
   }
}


//====================================================================
// CHECK BUY STOP LEVELS
//====================================================================

bool CheckBuyStops(
   double entry,
   double sl,
   double tp
)
{
   double point = SymbolInfoDouble(
      _Symbol,
      SYMBOL_POINT
   );

   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minDistance =
      (double)stopsLevel * point;

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   //--- SL must be sufficiently below Ask
   if(sl > 0.0)
   {
      if((ask - sl) < minDistance)
      {
         Print(
            "BUY rejected: SL is too close to current price."
         );

         return false;
      }
   }

   //--- TP must be sufficiently above Ask
   if(tp > 0.0)
   {
      if((tp - ask) < minDistance)
      {
         Print(
            "BUY rejected: TP is too close to current price."
         );

         return false;
      }
   }

   return true;
}


//====================================================================
// CHECK SELL STOP LEVELS
//====================================================================

bool CheckSellStops(
   double entry,
   double sl,
   double tp
)
{
   double point = SymbolInfoDouble(
      _Symbol,
      SYMBOL_POINT
   );

   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );

   double minDistance =
      (double)stopsLevel * point;

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   //--- SL must be sufficiently above Bid
   if(sl > 0.0)
   {
      if((sl - bid) < minDistance)
      {
         Print(
            "SELL rejected: SL is too close to current price."
         );

         return false;
      }
   }

   //--- TP must be sufficiently below Bid
   if(tp > 0.0)
   {
      if((bid - tp) < minDistance)
      {
         Print(
            "SELL rejected: TP is too close to current price."
         );

         return false;
      }
   }

   return true;
}


//====================================================================
// CHECK WHETHER EA ALREADY HAS AN OPEN POSITION
//====================================================================

bool HasOpenPosition()
{
   int totalPositions = PositionsTotal();

   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      if(symbol != _Symbol)
         continue;

      ulong magic =
         (ulong)PositionGetInteger(POSITION_MAGIC);

      if(magic != InpMagicNumber)
         continue;

      return true;
   }

   return false;
}


//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(double price)
{
   return NormalizeDouble(
      price,
      _Digits
   );
}


//====================================================================
// NORMALIZE LOT
//====================================================================

double NormalizeLot(double lot)
{
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   double lotStep =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   if(lotStep <= 0.0)
      return 0.0;

   lot = MathMax(
      minLot,
      MathMin(
         maxLot,
         lot
      )
   );

   lot =
      MathFloor(
         lot / lotStep
      ) * lotStep;

   return NormalizeDouble(
      lot,
      8
   );
}
//+------------------------------------------------------------------+
