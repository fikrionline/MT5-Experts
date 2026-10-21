//+------------------------------------------------------------------+
//|                                                   SymbolSwitcher |
//+------------------------------------------------------------------+
#property strict

string symbols[]; // list of symbols from Market Watch

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Get list of Market Watch symbols
   int total = SymbolsTotal(true);
   ArrayResize(symbols, total);
   for (int i = 0; i < total; i++) {
      symbols[i] = SymbolName(i, true);
   }
   
   // Sort
   SortStringArrayAscending(symbols);

   // Create buttons dynamically
   int x = 10, y = 100; // position
   for (int i = 0; i < total; i++) {
      string name = "btn_" + symbols[i];
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 80);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, name, OBJPROP_TEXT, symbols[i]);

      y += 25;
      if (y > 300) {
         y = 20;
         x += 90;
      } // new column if too low
   }

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
   const long & lparam,
      const double & dparam,
         const string & sparam) {
   if (id == CHARTEVENT_OBJECT_CLICK) {
      if (StringFind(sparam, "btn_") == 0) {
         string sym = StringSubstr(sparam, 4);
         if (SymbolSelect(sym, true))
            ChartSetSymbolPeriod(0, sym, PERIOD_CURRENT);
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   for (int i = 0; i < ArraySize(symbols); i++)
      ObjectDelete(0, "btn_" + symbols[i]);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Custom function to sort a string array in ascending order        |
//+------------------------------------------------------------------+
void SortStringArrayAscending(string &arr[])
  {
   int size = ArraySize(arr);
   if(size <= 1) return; // No sorting needed for 0 or 1 element

   // Bubble sort implementation
   for(int i = 0; i < size - 1; i++)
     {
      for(int j = 0; j < size - i - 1; j++)
        {
         // StringCompare returns > 0 if the first string is greater than the second
         if(StringCompare(arr[j], arr[j + 1]) > 0)
           {
            // Swap elements
            string temp = arr[j];
            arr[j] = arr[j + 1];
            arr[j + 1] = temp;
           }
        }
     }
  }
