//+------------------------------------------------------------------+
//|                                                   HOLO_V2.mq5    |
//| Highest Open / Lowest Open Trade                                 |
//|                                                                  |
//| Version 2                                                        |
//|                                                                  |
//| Core strategy:                                                   |
//|  SELL: price breaks above highest H1 open, then returns to it.  |
//|  BUY : price breaks below lowest H1 open, then returns to it.   |
//|                                                                  |
//| Initial SL: current D1 high/low                                 |
//| +5 pips  -> BE +1                                                |
//| +10 pips -> BE +5                                                |
//+------------------------------------------------------------------+
#property copyright "HOLO V2"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// INPUTS
//====================================================================

//--- General
input ulong   InpMagicNumber          = 590623;
input double  InpRiskPercent          = 1.0;
input double  InpFixedLot             = 0.0;       // 0 = risk based

//--- Trade limits
input int     InpMaxTradesPerDay     = 2;
input bool    InpOnePositionOnly     = true;

//--- Spread / execution
input int     InpMaxSpreadPoints     = 30;
input int     InpDeviationPoints     = 10;

//--- Trading session
input bool    InpUseTradingSession   = false;
input int     InpStartHour           = 0;
input int     InpStartMinute         = 0;
input int     InpEndHour             = 23;
input int     InpEndMinute           = 59;

//--- Friday cutoff
input bool    InpUseFridayCutoff     = false;
input int     InpFridayCutoffHour    = 20;
input int     InpFridayCutoffMinute  = 0;

//--- HOLO entry
input double  InpBreakBufferPips     = 0.0;

//--- Optional M15 confirmation
input bool    InpUseM15Confirmation  = true;

//--- Initial SL
input double  InpSLBufferPips        = 0.0;

//--- Break-even
input bool    InpUseBreakEven        = true;

input double  InpBE1TriggerPips      = 5.0;
input double  InpBE1OffsetPips       = 1.0;

input bool    InpUseBE2              = true;
input double  InpBE2TriggerPips      = 10.0;
input double  InpBE2OffsetPips       = 5.0;

//--- Optional trailing
input bool    InpUseTrailing          = false;
input double  InpTrailingStartPips    = 10.0;
input double  InpTrailingDistancePips = 5.0;

//--- Daily loss protection
input bool    InpUseDailyLossLimit   = false;
input double  InpDailyLossPercent    = 3.0;

//--- Chart
input bool    InpDrawLevels           = true;
input color   InpHighestColor         = clrRed;
input color   InpLowestColor          = clrDodgerBlue;
input int     InpLineWidth            = 2;
input bool    InpShowChartComment     = true;


//====================================================================
// GLOBAL STATE
//====================================================================

datetime g_dayStart = 0;

double   g_highestOpen = 0.0;
double   g_lowestOpen  = 0.0;

bool     g_highBroken = false;
bool     g_lowBroken  = false;

bool     g_highTradeTaken = false;
bool     g_lowTradeTaken  = false;

double   g_dayStartEquity = 0.0;


//====================================================================
// OBJECT NAMES
//====================================================================

string HIGH_LINE_NAME = "HOLO_V2_HIGHEST_OPEN";
string LOW_LINE_NAME  = "HOLO_V2_LOWEST_OPEN";


//====================================================================
// INIT
//====================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_dayStart = GetBrokerDayStart();

   if(g_dayStart <= 0)
   {
      Print("HOLO V2: Unable to determine broker day.");
      return INIT_FAILED;
   }

   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   UpdateHOLOLevels();

   // Reconstruct state after EA restart
   RebuildBreakState();

   Print("HOLO V2 initialized: ", _Symbol);

   return INIT_SUCCEEDED;
}


//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   if(InpDrawLevels)
   {
      ObjectDelete(0, HIGH_LINE_NAME);
      ObjectDelete(0, LOW_LINE_NAME);
   }

   Comment("");
}


//====================================================================
// MAIN
//====================================================================

void OnTick()
{
   datetime currentDay = GetBrokerDayStart();

   if(currentDay <= 0)
      return;


   //===============================================================
   // NEW DAY
   //===============================================================

   if(currentDay != g_dayStart)
   {
      g_dayStart = currentDay;

      g_highBroken = false;
      g_lowBroken  = false;

      g_highTradeTaken = false;
      g_lowTradeTaken = false;

      g_highestOpen = 0.0;
      g_lowestOpen  = 0.0;

      g_dayStartEquity =
         AccountInfoDouble(ACCOUNT_EQUITY);
   }


   //===============================================================
   // UPDATE LEVELS
   //===============================================================

   UpdateHOLOLevels();


   //===============================================================
   // MANAGE EXISTING POSITIONS
   //===============================================================

   ManagePositions();


   //===============================================================
   // ENTRY CONDITIONS
   //===============================================================

   if(!TradingAllowedNow())
   {
      UpdateChartComment();
      return;
   }

   if(DailyLossLimitReached())
   {
      UpdateChartComment();
      return;
   }

   CheckEntries();


   //===============================================================
   // DISPLAY
   //===============================================================

   UpdateChartComment();
}


//====================================================================
// GET BROKER DAY START
//====================================================================

datetime GetBrokerDayStart()
{
   datetime now = TimeCurrent();

   MqlDateTime dt;

   if(!TimeToStruct(now, dt))
      return 0;

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   return StructToTime(dt);
}


//====================================================================
// UPDATE H1 LEVELS
//
// V2 behavior:
//
// If a new highest H1 open appears:
//   - highest level is replaced
//   - short break state is reset
//
// If a new lowest H1 open appears:
//   - lowest level is replaced
//   - long break state is reset
//
// This makes the setup dynamic throughout the broker day.
//====================================================================

void UpdateHOLOLevels()
{
   int bars = Bars(_Symbol, PERIOD_H1);

   if(bars <= 0)
      return;

   datetime now = TimeCurrent();

   double newHighest = 0.0;
   double newLowest  = 0.0;

   bool found = false;


   for(int i = 0; i < bars; i++)
   {
      datetime barTime =
         iTime(_Symbol, PERIOD_H1, i);

      if(barTime <= 0)
         continue;

      // Older than today's broker day
      if(barTime < g_dayStart)
         break;

      // Future bar protection
      if(barTime > now)
         continue;

      double openPrice =
         iOpen(_Symbol, PERIOD_H1, i);

      if(openPrice <= 0.0)
         continue;

      if(!found)
      {
         newHighest = openPrice;
         newLowest  = openPrice;
         found = true;
      }
      else
      {
         if(openPrice > newHighest)
            newHighest = openPrice;

         if(openPrice < newLowest)
            newLowest = openPrice;
      }
   }


   if(!found)
      return;


   //===============================================================
   // HIGHEST LEVEL CHANGED
   //===============================================================

   if(g_highestOpen <= 0.0)
   {
      g_highestOpen = newHighest;
   }
   else if(newHighest != g_highestOpen)
   {
      if(newHighest > g_highestOpen)
      {
         g_highestOpen = newHighest;

         // New level = new setup
         g_highBroken = false;

         // Don't automatically remove historical trade status.
         // One short per day remains the default.
      }
   }


   //===============================================================
   // LOWEST LEVEL CHANGED
   //===============================================================

   if(g_lowestOpen <= 0.0)
   {
      g_lowestOpen = newLowest;
   }
   else if(newLowest != g_lowestOpen)
   {
      if(newLowest < g_lowestOpen)
      {
         g_lowestOpen = newLowest;

         // New level = new setup
         g_lowBroken = false;
      }
   }


   if(InpDrawLevels)
      DrawHOLOLevels();
}


//====================================================================
// REBUILD BREAK STATE
//
// Used after EA restart.
//
// If current price is already above highest level,
// consider the highest level broken.
//
// If current price is already below lowest level,
// consider the lowest level broken.
//
// This avoids requiring a new break after restarting the EA.
//====================================================================

void RebuildBreakState()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   if(g_highestOpen > 0.0)
   {
      if(tick.bid > g_highestOpen +
         PipsToPrice(InpBreakBufferPips))
      {
         g_highBroken = true;
      }
   }

   if(g_lowestOpen > 0.0)
   {
      if(tick.ask < g_lowestOpen -
         PipsToPrice(InpBreakBufferPips))
      {
         g_lowBroken = true;
      }
   }
}


//====================================================================
// DRAW LEVELS
//====================================================================

void DrawHOLOLevels()
{
   if(g_highestOpen > 0.0)
   {
      DrawHorizontalLine(
         HIGH_LINE_NAME,
         g_highestOpen,
         InpHighestColor
      );
   }

   if(g_lowestOpen > 0.0)
   {
      DrawHorizontalLine(
         LOW_LINE_NAME,
         g_lowestOpen,
         InpLowestColor
      );
   }
}


//====================================================================
// DRAW HORIZONTAL LINE
//====================================================================

void DrawHorizontalLine(
   string name,
   double price,
   color lineColor
)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(
         0,
         name,
         OBJ_HLINE,
         0,
         0,
         price
      );
   }

   ObjectSetDouble(
      0,
      name,
      OBJPROP_PRICE,
      price
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      lineColor
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
      OBJPROP_STYLE,
      STYLE_SOLID
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
}


//====================================================================
// CHECK ENTRIES
//====================================================================

void CheckEntries()
{
   if(g_highestOpen <= 0.0 ||
      g_lowestOpen <= 0.0)
      return;


   if(!TradingConditionsOK())
      return;


   if(GetTradesToday() >= InpMaxTradesPerDay)
      return;


   if(InpOnePositionOnly &&
      HasOpenHOLOPosition())
      return;


   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;


   double breakBuffer =
      PipsToPrice(InpBreakBufferPips);


   //===============================================================
   // SELL
   //===============================================================

   if(!g_highTradeTaken)
   {
      // Step 1:
      // price must break above highest H1 open

      if(tick.bid >
         g_highestOpen + breakBuffer)
      {
         g_highBroken = true;
      }


      // Step 2:
      // price returns to / through highest open

      if(g_highBroken &&
         tick.bid <= g_highestOpen)
      {
         bool confirmed = true;

         if(InpUseM15Confirmation)
            confirmed = M15ShortConfirmation();

         if(confirmed)
         {
            if(OpenSell())
            {
               g_highTradeTaken = true;
               g_highBroken = false;
            }
         }
      }
   }


   //===============================================================
   // BUY
   //===============================================================

   if(!g_lowTradeTaken)
   {
      // Step 1:
      // price must break below lowest H1 open

      if(tick.ask <
         g_lowestOpen - breakBuffer)
      {
         g_lowBroken = true;
      }


      // Step 2:
      // price returns to / through lowest open

      if(g_lowBroken &&
         tick.ask >= g_lowestOpen)
      {
         bool confirmed = true;

         if(InpUseM15Confirmation)
            confirmed = M15LongConfirmation();

         if(confirmed)
         {
            if(OpenBuy())
            {
               g_lowTradeTaken = true;
               g_lowBroken = false;
            }
         }
      }
   }
}


//====================================================================
// M15 SHORT CONFIRMATION
//====================================================================

bool M15ShortConfirmation()
{
   double m15Open =
      iOpen(_Symbol, PERIOD_M15, 0);

   if(m15Open <= 0.0)
      return false;

   return m15Open > g_highestOpen;
}


//====================================================================
// M15 LONG CONFIRMATION
//====================================================================

bool M15LongConfirmation()
{
   double m15Open =
      iOpen(_Symbol, PERIOD_M15, 0);

   if(m15Open <= 0.0)
      return false;

   return m15Open < g_lowestOpen;
}


//====================================================================
// OPEN BUY
//====================================================================

bool OpenBuy()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;


   double entry = tick.ask;


   // Current daily low
   double dailyLow =
      iLow(_Symbol, PERIOD_D1, 0);

   if(dailyLow <= 0.0)
      return false;


   double sl =
      dailyLow -
      PipsToPrice(InpSLBufferPips);

   sl = NormalizePrice(sl);


   if(sl >= entry)
   {
      Print(
         "HOLO V2 BUY rejected: ",
         "daily low SL is not below entry."
      );

      return false;
   }


   sl =
      AdjustStopForBuy(
         sl,
         entry
      );


   double volume =
      CalculateLotSize(
         ORDER_TYPE_BUY,
         entry,
         sl
      );


   if(volume <= 0.0)
      return false;


   bool result =
      trade.Buy(
         volume,
         _Symbol,
         0.0,
         sl,
         0.0,
         "HOLO V2 BUY"
      );


   if(!result)
   {
      Print(
         "HOLO V2 BUY failed. Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }


   Print(
      "HOLO V2 BUY opened. ",
      "Volume=", volume,
      " Entry=", entry,
      " SL=", sl
   );

   return true;
}


//====================================================================
// OPEN SELL
//====================================================================

bool OpenSell()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return false;


   double entry = tick.bid;


   // Current daily high
   double dailyHigh =
      iHigh(_Symbol, PERIOD_D1, 0);

   if(dailyHigh <= 0.0)
      return false;


   double sl =
      dailyHigh +
      PipsToPrice(InpSLBufferPips);

   sl = NormalizePrice(sl);


   if(sl <= entry)
   {
      Print(
         "HOLO V2 SELL rejected: ",
         "daily high SL is not above entry."
      );

      return false;
   }


   sl =
      AdjustStopForSell(
         sl,
         entry
      );


   double volume =
      CalculateLotSize(
         ORDER_TYPE_SELL,
         entry,
         sl
      );


   if(volume <= 0.0)
      return false;


   bool result =
      trade.Sell(
         volume,
         _Symbol,
         0.0,
         sl,
         0.0,
         "HOLO V2 SELL"
      );


   if(!result)
   {
      Print(
         "HOLO V2 SELL failed. Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }


   Print(
      "HOLO V2 SELL opened. ",
      "Volume=", volume,
      " Entry=", entry,
      " SL=", sl
   );

   return true;
}


//====================================================================
// MANAGE POSITIONS
//====================================================================

void ManagePositions()
{
   int total =
      PositionsTotal();


   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;


      if(!PositionSelectByTicket(ticket))
         continue;


      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );

      if(symbol != _Symbol)
         continue;


      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );

      if((ulong)magic != InpMagicNumber)
         continue;


      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(
            POSITION_TYPE
         );


      double openPrice =
         PositionGetDouble(
            POSITION_PRICE_OPEN
         );


      double currentSL =
         PositionGetDouble(
            POSITION_SL
         );


      MqlTick tick;

      if(!SymbolInfoTick(
         _Symbol,
         tick
      ))
         continue;


      double profitPips = 0.0;


      if(type == POSITION_TYPE_BUY)
      {
         profitPips =
            PriceToPips(
               tick.bid - openPrice
            );
      }
      else
      {
         profitPips =
            PriceToPips(
               openPrice - tick.ask
            );
      }


      //============================================================
      // BE + 1
      //============================================================

      if(InpUseBreakEven &&
         profitPips >= InpBE1TriggerPips)
      {
         double newSL = 0.0;


         if(type == POSITION_TYPE_BUY)
         {
            newSL =
               openPrice +
               PipsToPrice(
                  InpBE1OffsetPips
               );

            newSL =
               NormalizePrice(newSL);


            if(currentSL == 0.0 ||
               newSL > currentSL)
            {
               ModifyPosition(
                  ticket,
                  newSL
               );
            }
         }
         else
         {
            newSL =
               openPrice -
               PipsToPrice(
                  InpBE1OffsetPips
               );

            newSL =
               NormalizePrice(newSL);


            if(currentSL == 0.0 ||
               newSL < currentSL)
            {
               ModifyPosition(
                  ticket,
                  newSL
               );
            }
         }
      }


      //============================================================
      // BE + 5
      //============================================================

      if(InpUseBE2 &&
         profitPips >= InpBE2TriggerPips)
      {
         double newSL = 0.0;


         if(type == POSITION_TYPE_BUY)
         {
            newSL =
               openPrice +
               PipsToPrice(
                  InpBE2OffsetPips
               );

            newSL =
               NormalizePrice(newSL);


            if(currentSL == 0.0 ||
               newSL > currentSL)
            {
               ModifyPosition(
                  ticket,
                  newSL
               );
            }
         }
         else
         {
            newSL =
               openPrice -
               PipsToPrice(
                  InpBE2OffsetPips
               );

            newSL =
               NormalizePrice(newSL);


            if(currentSL == 0.0 ||
               newSL < currentSL)
            {
               ModifyPosition(
                  ticket,
                  newSL
               );
            }
         }
      }


      //============================================================
      // OPTIONAL TRAILING
      //============================================================

      if(InpUseTrailing &&
         profitPips >= InpTrailingStartPips)
      {
         double newSL = 0.0;


         if(type == POSITION_TYPE_BUY)
         {
            newSL =
               tick.bid -
               PipsToPrice(
                  InpTrailingDistancePips
               );

            newSL =
               NormalizePrice(newSL);


            if(currentSL == 0.0 ||
               newSL > currentSL)
            {
               ModifyPosition(
                  ticket,
                  newSL
               );
            }
         }
         else
         {
            newSL =
               tick.ask +
               PipsToPrice(
                  InpTrailingDistancePips
               );

            newSL =
               NormalizePrice(newSL);


            if(currentSL == 0.0 ||
               newSL < currentSL)
            {
               ModifyPosition(
                  ticket,
                  newSL
               );
            }
         }
      }
   }
}


//====================================================================
// MODIFY POSITION
//====================================================================

bool ModifyPosition(
   ulong ticket,
   double newSL
)
{
   if(!PositionSelectByTicket(ticket))
      return false;


   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)
      PositionGetInteger(
         POSITION_TYPE
      );


   MqlTick tick;

   if(!SymbolInfoTick(
      _Symbol,
      tick
   ))
      return false;


   if(type == POSITION_TYPE_BUY)
   {
      newSL =
         AdjustStopForBuy(
            newSL,
            tick.bid
         );
   }
   else
   {
      newSL =
         AdjustStopForSell(
            newSL,
            tick.ask
         );
   }


   newSL =
      NormalizePrice(newSL);


   double currentTP =
      PositionGetDouble(
         POSITION_TP
      );


   bool result =
      trade.PositionModify(
         ticket,
         newSL,
         currentTP
      );


   if(!result)
   {
      Print(
         "HOLO V2 modify failed. ",
         "Ticket=", ticket,
         " Retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }


   return true;
}


//====================================================================
// TRADING CONDITIONS
//====================================================================

bool TradingConditionsOK()
{
   MqlTick tick;

   if(!SymbolInfoTick(
      _Symbol,
      tick
   ))
      return false;


   double spreadPoints =
      (tick.ask - tick.bid) /
      _Point;


   if(spreadPoints >
      InpMaxSpreadPoints)
   {
      return false;
   }


   return true;
}


//====================================================================
// TRADING SESSION
//====================================================================

bool TradingAllowedNow()
{
   datetime now =
      TimeCurrent();

   MqlDateTime dt;

   if(!TimeToStruct(
      now,
      dt
   ))
      return false;


   int currentMinutes =
      dt.hour * 60 +
      dt.min;


   //===============================================================
   // FRIDAY CUTOFF
   //===============================================================

   if(InpUseFridayCutoff &&
      dt.day_of_week == 5)
   {
      int cutoff =
         InpFridayCutoffHour * 60 +
         InpFridayCutoffMinute;


      if(currentMinutes >= cutoff)
         return false;
   }


   //===============================================================
   // SESSION
   //===============================================================

   if(!InpUseTradingSession)
      return true;


   int startMinutes =
      InpStartHour * 60 +
      InpStartMinute;


   int endMinutes =
      InpEndHour * 60 +
      InpEndMinute;


   // Normal session
   if(startMinutes <= endMinutes)
   {
      return (
         currentMinutes >= startMinutes &&
         currentMinutes <= endMinutes
      );
   }


   // Overnight session
   return (
      currentMinutes >= startMinutes ||
      currentMinutes <= endMinutes
   );
}


//====================================================================
// DAILY LOSS LIMIT
//====================================================================

bool DailyLossLimitReached()
{
   if(!InpUseDailyLossLimit)
      return false;


   if(g_dayStartEquity <= 0.0)
      return false;


   double equity =
      AccountInfoDouble(
         ACCOUNT_EQUITY
      );


   double lossPercent =
      ((g_dayStartEquity - equity) /
       g_dayStartEquity) * 100.0;


   if(lossPercent >=
      InpDailyLossPercent)
   {
      return true;
   }


   return false;
}


//====================================================================
// COUNT TODAY'S TRADES
//====================================================================

int GetTradesToday()
{
   datetime from =
      g_dayStart;

   datetime to =
      TimeCurrent();


   if(!HistorySelect(
      from,
      to
   ))
      return 0;


   int count = 0;

   int deals =
      HistoryDealsTotal();


   for(int i = 0;
       i < deals;
       i++)
   {
      ulong ticket =
         HistoryDealGetTicket(i);

      if(ticket == 0)
         continue;


      string symbol =
         HistoryDealGetString(
            ticket,
            DEAL_SYMBOL
         );

      if(symbol != _Symbol)
         continue;


      long magic =
         HistoryDealGetInteger(
            ticket,
            DEAL_MAGIC
         );

      if((ulong)magic !=
         InpMagicNumber)
         continue;


      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)
         HistoryDealGetInteger(
            ticket,
            DEAL_ENTRY
         );


      if(entry != DEAL_ENTRY_IN)
         continue;


      ENUM_DEAL_TYPE type =
         (ENUM_DEAL_TYPE)
         HistoryDealGetInteger(
            ticket,
            DEAL_TYPE
         );


      if(type == DEAL_TYPE_BUY ||
         type == DEAL_TYPE_SELL)
      {
         count++;
      }
   }


   return count;
}


//====================================================================
// CHECK EXISTING HOLO POSITION
//====================================================================

bool HasOpenHOLOPosition()
{
   int total =
      PositionsTotal();


   for(int i = 0;
       i < total;
       i++)
   {
      ulong ticket =
         PositionGetTicket(i);

      if(ticket == 0)
         continue;


      if(!PositionSelectByTicket(
         ticket
      ))
         continue;


      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );


      if(symbol != _Symbol)
         continue;


      long magic =
         PositionGetInteger(
            POSITION_MAGIC
         );


      if((ulong)magic ==
         InpMagicNumber)
      {
         return true;
      }
   }


   return false;
}


//====================================================================
// CALCULATE LOT SIZE
//====================================================================

double CalculateLotSize(
   ENUM_ORDER_TYPE orderType,
   double entryPrice,
   double stopPrice
)
{
   // Fixed lot mode
   if(InpFixedLot > 0.0)
      return NormalizeVolume(
         InpFixedLot
      );


   if(InpRiskPercent <= 0.0)
      return 0.0;


   double equity =
      AccountInfoDouble(
         ACCOUNT_EQUITY
      );


   double riskMoney =
      equity *
      InpRiskPercent /
      100.0;


   if(riskMoney <= 0.0)
      return 0.0;


   double profitForOneLot = 0.0;


   if(!OrderCalcProfit(
      orderType,
      _Symbol,
      1.0,
      entryPrice,
      stopPrice,
      profitForOneLot
   ))
   {
      Print(
         "HOLO V2: OrderCalcProfit failed. ",
         "Error=", GetLastError()
      );

      return 0.0;
   }


   double lossPerLot =
      MathAbs(
         profitForOneLot
      );


   if(lossPerLot <= 0.0)
      return 0.0;


   double volume =
      riskMoney /
      lossPerLot;


   return NormalizeVolume(
      volume
   );
}


//====================================================================
// NORMALIZE VOLUME
//====================================================================

double NormalizeVolume(
   double volume
)
{
   double minVolume =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );


   double maxVolume =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );


   double stepVolume =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );


   if(stepVolume <= 0.0)
      return 0.0;


   volume =
      MathFloor(
         volume /
         stepVolume
      ) *
      stepVolume;


   volume =
      MathMax(
         volume,
         minVolume
      );


   volume =
      MathMin(
         volume,
         maxVolume
      );


   int digits = 2;


   if(stepVolume >= 1.0)
      digits = 0;
   else if(stepVolume >= 0.1)
      digits = 1;
   else if(stepVolume >= 0.01)
      digits = 2;
   else
      digits = 3;


   return NormalizeDouble(
      volume,
      digits
   );
}


//====================================================================
// PIPS -> PRICE
//====================================================================

double PipsToPrice(
   double pips
)
{
   if(_Digits == 3 ||
      _Digits == 5)
   {
      return pips *
             _Point *
             10.0;
   }


   return pips *
          _Point;
}


//====================================================================
// PRICE -> PIPS
//====================================================================

double PriceToPips(
   double distance
)
{
   if(_Digits == 3 ||
      _Digits == 5)
   {
      return distance /
             (_Point * 10.0);
   }


   return distance /
          _Point;
}


//====================================================================
// NORMALIZE PRICE
//====================================================================

double NormalizePrice(
   double price
)
{
   return NormalizeDouble(
      price,
      _Digits
   );
}


//====================================================================
// BUY STOP ADJUSTMENT
//====================================================================

double AdjustStopForBuy(
   double sl,
   double referencePrice
)
{
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );


   double minDistance =
      stopsLevel *
      _Point;


   double maximumSL =
      referencePrice -
      minDistance;


   if(sl > maximumSL)
      sl = maximumSL;


   return NormalizePrice(
      sl
   );
}


//====================================================================
// SELL STOP ADJUSTMENT
//====================================================================

double AdjustStopForSell(
   double sl,
   double referencePrice
)
{
   long stopsLevel =
      SymbolInfoInteger(
         _Symbol,
         SYMBOL_TRADE_STOPS_LEVEL
      );


   double minDistance =
      stopsLevel *
      _Point;


   double minimumSL =
      referencePrice +
      minDistance;


   if(sl < minimumSL)
      sl = minimumSL;


   return NormalizePrice(
      sl
   );
}


//====================================================================
// CHART COMMENT
//====================================================================

void UpdateChartComment()
{
   if(!InpShowChartComment)
   {
      Comment("");
      return;
   }


   if(g_highestOpen <= 0.0 ||
      g_lowestOpen <= 0.0)
   {
      Comment(
         "HOLO V2\n",
         "Waiting for H1 data..."
      );

      return;
   }


   MqlTick tick;

   if(!SymbolInfoTick(
      _Symbol,
      tick
   ))
      return;


   string highState;


   if(g_highTradeTaken)
   {
      highState = "TRADE TAKEN";
   }
   else if(g_highBroken)
   {
      highState =
         "BROKEN - WAITING RETURN";
   }
   else
   {
      highState =
         "WAITING FOR BREAK";
   }


   string lowState;


   if(g_lowTradeTaken)
   {
      lowState = "TRADE TAKEN";
   }
   else if(g_lowBroken)
   {
      lowState =
         "BROKEN - WAITING RETURN";
   }
   else
   {
      lowState =
         "WAITING FOR BREAK";
   }


   int tradesToday =
      GetTradesToday();


   double spread =
      (tick.ask - tick.bid) /
      _Point;


   Comment(
      "HOLO V2\n",
      "================================\n",
      "Symbol: ",
      _Symbol,
      "\n\n",

      "HIGH LEVEL\n",
      DoubleToString(
         g_highestOpen,
         _Digits
      ),
      "\n",
      "State: ",
      highState,
      "\n\n",

      "LOW LEVEL\n",
      DoubleToString(
         g_lowestOpen,
         _Digits
      ),
      "\n",
      "State: ",
      lowState,
      "\n\n",

      "Trades today: ",
      tradesToday,
      " / ",
      InpMaxTradesPerDay,
      "\n",

      "Spread: ",
      DoubleToString(
         spread,
         1
      ),
      " points\n",

      "M15 confirmation: ",
      (InpUseM15Confirmation
       ? "ON"
       : "OFF"),
      "\n",

      "Session: ",
      (TradingAllowedNow()
       ? "OPEN"
       : "CLOSED")
   );
}
//+------------------------------------------------------------------+
