#property link          "https://www.earnforex.com/metatrader-expert-advisors/single-breakeven/"
#property version       "1.01"
#property strict
#property copyright     "EarnForex.com - 2025"
#property description   "This expert advisor will set a single breakeven level for multiple trades on the same symbol."
#property description   ""
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of this EA cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find more on EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>

enum ENUM_CONSIDER
{
    All = -1,      // ALL ORDERS
    Buy = OP_BUY,  // BUY ONLY
    Sell = OP_SELL // SELL ONLY
};

enum ENUM_ADJUST_TO
{
    ADJUST_DONT,   // Don't adjust
    ADJUST_TO_ASK, // Adjust to Ask price
    ADJUST_TO_BID  // Adjust to Bid price
};

input string Comment_1 = "====================";  // Expert Advisor Settings
input int ProfitCurToTrigger = 100;               // Total profit in currency to trigger single BE
input int AdditionalProfitCur = 0;                // Additional profit in currency for single BE
input ENUM_ADJUST_TO AdjustToPrice = ADJUST_TO_BID; // Adjust single BE to which price?
input int DelayBetweenAdjustments = 60;           // Delay (sec) between adjustments
input bool AdjustForSwapsCommission = false;      // Adjust for swaps & commission?
input string Comment_2 = "====================";  // Orders Filtering Options
input ENUM_CONSIDER OnlyType = All;               // Apply to
input bool UseMagic = false;                      // Filter by magic number
input int MagicNumber = 0;                        // Magic number (if above is true)
input bool UseComment = false;                    // Filter by comment
input string CommentFilter = "";                  // Comment (if above is true)
input bool EnableTrailingParam = false;           // Enable Breakeven EA
input string Comment_3 = "====================";  // Notification Options
input bool EnableNotify = false;                  // Enable notifications feature
input bool SendAlert = false;                     // Send alert notifications
input bool SendApp = false;                       // Send notifications to mobile
input bool SendEmail = false;                     // Send notifications via email
input string Comment_3a = "===================="; // Graphical Window
input bool ShowPanel = true;                      // Show graphical panel
input string ExpertName = "SBE";                  // Expert name (to name the objects)
input int Xoff = 20;                              // Horizontal spacing for the control panel
input int Yoff = 20;                              // Vertical spacing for the control panel
input ENUM_BASE_CORNER ChartCorner = CORNER_LEFT_UPPER; // Chart Corner
input int FontSize = 10;                          // Font Size

double DPIScale; // Scaling parameter for the panel based on the screen DPI.
int PanelMovY, PanelLabX, PanelLabY, PanelRecX;
bool EnableTrailing = EnableTrailingParam;
datetime LastAdjustment;

int OnInit()
{
    CleanPanel();
    EnableTrailing = EnableTrailingParam;

    DPIScale = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;

    PanelMovY = (int)MathRound(20 * DPIScale);
    PanelLabX = (int)MathRound(150 * DPIScale);
    PanelLabY = PanelMovY;
    PanelRecX = PanelLabX + 4;
    LastAdjustment = 0;

    if (ShowPanel) DrawPanel();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
}

void OnTick()
{
    if (EnableTrailing) DoSingleBE();
    if (ShowPanel) DrawPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
        if (sparam == PanelEnableDisable)
        {
            ChangeTrailingEnabled();
        }
    }
    else if (id == CHARTEVENT_KEYDOWN)
    {
        if (lparam == 27)
        {
            if (MessageBox("Are you sure you want to close the EA?", "EXIT ?", MB_YESNO) == IDYES)
            {
                ExpertRemove();
            }
        }
    }
}

void DoSingleBE()
{
    if (TimeCurrent() < LastAdjustment + DelayBetweenAdjustments) return;
    double BE_Price = CalculateSingleBreakeven();
    if (BE_Price <= 0) return;
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false)
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the order - ", Error);
            Print("ERROR - ", ErrorText);
            continue;
        }
        if (OrderSymbol() != Symbol()) continue;
        if ((UseMagic) && (OrderMagicNumber() != MagicNumber)) continue;
        if ((UseComment) && (StringFind(OrderComment(), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (OrderType() != OnlyType)) continue;

        double NewSL = 0;
        double NewTP = 0;
        double BE_Price_Current = BE_Price; // To keep the global BE_Price unchanged.
        double OpenPrice = OrderOpenPrice();

        if ((ProfitTotal >= ProfitCurToTrigger) && (BE_Price_Current != 0))
        {
            if (OrderType() == OP_BUY)
            {
                if ((AdjustToPrice == ADJUST_TO_ASK) && (PositionsShort > 0)) BE_Price_Current -= SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point; // Shorts will be closed when Ask reaches (Bid - DistancePoints), so Longs should be closed at that moment's Bid.
            }
            if (OrderType() == OP_SELL)
            {
                if ((AdjustToPrice == ADJUST_TO_BID) && (PositionsLong > 0)) BE_Price_Current += SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point; // Longs will be closed when Bid reaches (Ask + DistancePoints), so Shorts should be closed at that moment's Ask.
            }
        }
        
        double TickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        double SLPrice = OrderStopLoss();
        double TPPrice = OrderTakeProfit();
        double Spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point;
        double StopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * _Point;

        if (TickSize > 0)
        {
            BE_Price_Current = NormalizeDouble(MathRound(BE_Price_Current / TickSize) * TickSize, _Digits);
        }
        if (OrderType() == OP_BUY)
        {
            if (BE_Price_Current < SymbolInfoDouble(Symbol(), SYMBOL_BID) - StopLevel) // BE price below current price = SL for a Buy.
            {
                NewSL = NormalizeDouble(BE_Price_Current, _Digits);

                if (MathAbs(NewSL - SLPrice) > _Point / 2) // Not trying to set the same SL.
                {
                    bool result = OrderModify(OrderTicket(), OrderOpenPrice(), NewSL, OrderTakeProfit(), OrderExpiration());
                    if (result)
                    {
                        Print("Success setting collective breakeven: Buy Order #", OrderTicket(), ", new stop-loss = ", DoubleToString(NewSL, _Digits));
                        NotifyStopLossUpdate(OrderTicket(), NewSL, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Buy Order #", OrderTicket(), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OrderOpenPrice(), _Digits),
                              ", old SL = ", DoubleToString(SLPrice, _Digits),
                              ", new SL = ", DoubleToString(NewSL, _Digits), ", Bid = ", SymbolInfoDouble(Symbol(), SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Symbol(), SYMBOL_ASK));
                    }
                }
            }
            else if (BE_Price_Current > SymbolInfoDouble(Symbol(), SYMBOL_ASK) + StopLevel) // BE price above current price = TP for a Buy.
            {
                NewTP = NormalizeDouble(BE_Price_Current, _Digits);

                if (MathAbs(NewTP - TPPrice) > _Point / 2) // Not trying to set the same TP.
                {
                    bool result = OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), NewTP, OrderExpiration());
                    if (result)
                    {
                        Print("Success setting collective breakeven: Buy Order #", OrderTicket(), ", new take-profit = ", DoubleToString(NewTP, _Digits));
                        NotifyTakeProfitUpdate(OrderTicket(), NewTP, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Buy Order #", OrderTicket(), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OrderOpenPrice(), _Digits),
                              ", old TP = ", DoubleToString(TPPrice, _Digits),
                              ", new TP = ", DoubleToString(NewTP, _Digits), ", Bid = ", SymbolInfoDouble(Symbol(), SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Symbol(), SYMBOL_ASK));
                    }
                }
            }
        }
        else if (OrderType() == OP_SELL)
        {
            if (BE_Price_Current > SymbolInfoDouble(Symbol(), SYMBOL_ASK) + StopLevel) // BE price above current price = SL for a Sell.
            {
                NewSL = NormalizeDouble(BE_Price_Current, _Digits);
                
                if (MathAbs(NewSL - SLPrice) > _Point / 2) // Not trying to set the same SL.
                {
                    bool result = OrderModify(OrderTicket(), OrderOpenPrice(), NewSL, OrderTakeProfit(), OrderExpiration());
                    if (result)
                    {
                        Print("Success setting collective breakeven: Sell Order #", OrderTicket(), ", new stop-loss = ", DoubleToString(NewSL, _Digits));
                        NotifyStopLossUpdate(OrderTicket(), NewSL, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Sell Order #", OrderTicket(), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OrderOpenPrice(), _Digits),
                              ", old SL = ", DoubleToString(SLPrice, _Digits),
                              ", new SL = ", DoubleToString(NewSL, _Digits), ", Bid = ", SymbolInfoDouble(Symbol(), SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Symbol(), SYMBOL_ASK));
                    }
                }
            }
            else if (BE_Price_Current < SymbolInfoDouble(Symbol(), SYMBOL_BID) - StopLevel) // BE price below current price = TP for a Sell.
            {
                NewTP = NormalizeDouble(BE_Price_Current, _Digits);

                if (MathAbs(NewTP - TPPrice) > _Point / 2) // Not trying to set the same TP.
                {
                    bool result = OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), NewTP, OrderExpiration());
                    if (result)
                    {
                        Print("Success setting collective breakeven: Sell Order #", OrderTicket(), ", new take-profit = ", DoubleToString(NewTP, _Digits));
                        NotifyTakeProfitUpdate(OrderTicket(), NewTP, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Sell Order #", OrderTicket(), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OrderOpenPrice(), _Digits),
                              ", old TP = ", DoubleToString(TPPrice, _Digits),
                              ", new TP = ", DoubleToString(NewTP, _Digits), ", Bid = ", SymbolInfoDouble(Symbol(), SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Symbol(), SYMBOL_ASK));
                    }
                }
            }
        }
    }
    LastAdjustment = TimeCurrent();
}

void NotifyStopLossUpdate(int OrderNumber, double SLPrice, string Instrument)
{
    string type = "Stop-loss";
    NotifyUpdate(OrderNumber, SLPrice, Instrument, type);
}

void NotifyTakeProfitUpdate(int OrderNumber, double TPPrice, string Instrument)
{
    string type = "Take-profit";
    NotifyUpdate(OrderNumber, TPPrice, Instrument, type);
}

void NotifyUpdate(int OrderNumber, double Price, string Instrument, string type)
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    string EmailSubject = ExpertName + " " + Instrument + " Notification";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n\r\n" + ExpertName + " Notification for " + Instrument + "\r\n\r\n";
    EmailBody += type + " for order #" + IntegerToString(OrderNumber) + " has been moved to collective breakeven: " + DoubleToString(Price, _Digits);
    string AlertText = ExpertName + " - " + Instrument + ": ";
    AlertText += type + " for order #" + IntegerToString(OrderNumber) + " has been moved to collective breakeven: " + DoubleToString(Price, _Digits);
    string AppText = ExpertName + " - " + Instrument + ": ";
    AppText += type + " for order #" + IntegerToString(OrderNumber) + " was moved to collective breakeven: " + DoubleToString(Price, _Digits);
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
}

string PanelBase = ExpertName + "-P-BAS";
string PanelLabel = ExpertName + "-P-LAB";
string PanelEnableDisable = ExpertName + "-P-ENADIS";

void DrawPanel()
{
    int SignX = 1;
    int YAdjustment = 0;
    if ((ChartCorner == CORNER_RIGHT_UPPER) || (ChartCorner == CORNER_RIGHT_LOWER))
    {
        SignX = -1; // Correction for right-side panel position.
    }
    if ((ChartCorner == CORNER_RIGHT_LOWER) || (ChartCorner == CORNER_LEFT_LOWER))
    {
        YAdjustment = (PanelMovY + 2) * 2 + 1 - PanelLabY; // Correction for upper side panel position.
    }

    string PanelText = "SINGLE BE";
    string PanelToolTip = "Collective breakout for all trades on the current symbol";
    int Rows = 1;
    ObjectCreate(ChartID(), PanelBase, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_CORNER, ChartCorner);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_XDISTANCE, Xoff);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_YDISTANCE, Yoff + YAdjustment);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_XSIZE, PanelRecX);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_YSIZE, (PanelMovY + 1) * (Rows + 1) + 3);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_BGCOLOR, clrWhite);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_HIDDEN, true);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(ChartID(), PanelBase, OBJPROP_COLOR, clrBlack);

    DrawEdit(PanelLabel,
             Xoff + 2 * SignX,
             Yoff + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             PanelToolTip,
             ALIGN_CENTER,
             "Consolas",
             PanelText,
             false,
             clrNavy,
             clrKhaki,
             clrBlack);
    ObjectSetInteger(ChartID(), PanelLabel, OBJPROP_CORNER, ChartCorner);

    string EnableDisabledText = "";
    color EnableDisabledColor = clrNavy;
    color EnableDisabledBack = clrKhaki;
    if (EnableTrailing)
    {
        EnableDisabledText = "EXPERT ENABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkGreen;
    }
    else
    {
        EnableDisabledText = "EXPERT DISABLED";
        EnableDisabledColor = clrWhite;
        EnableDisabledBack = clrDarkRed;
    }

    if (ObjectFind(ChartID(), PanelEnableDisable) >= 0)
    {
        ObjectSetString(ChartID(), PanelEnableDisable, OBJPROP_TEXT, EnableDisabledText);
        ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_COLOR, EnableDisabledColor);
        ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_BGCOLOR, EnableDisabledBack);
    }
    else DrawEdit(PanelEnableDisable,
             Xoff + 2 * SignX,
             Yoff + (PanelMovY + 1) * Rows + 2,
             PanelLabX,
             PanelLabY,
             true,
             FontSize,
             "Click to enable or disable the breakeven feature.",
             ALIGN_CENTER,
             "Consolas",
             EnableDisabledText,
             false,
             EnableDisabledColor,
             EnableDisabledBack,
             clrBlack);
    ObjectSetInteger(ChartID(), PanelEnableDisable, OBJPROP_CORNER, ChartCorner);
}

void CleanPanel()
{
    ObjectsDeleteAll(ChartID(), ExpertName + "-P-");
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            MessageBox("Automated trading is disabled in the platform's options! Please enable it via Tools->Options->Expert Advisors.", "WARNING", MB_OK);
            return;
        }
        if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
            MessageBox("Live Trading is disabled in the expert advisors's settings! Please tick the Allow Live Trading checkbox on the Common tab.", "WARNING", MB_OK);
            return;
        }
        EnableTrailing = true;
    }
    else EnableTrailing = false;
    DrawPanel();
}

enum mode_of_operation
{
    Risk,
    Reward
};

string AccCurrency;
double CalculatePointValue(string cp, mode_of_operation mode)
{
    double UnitCost;

    int ProfitCalcMode = (int)MarketInfo(cp, MODE_PROFITCALCMODE);
    string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
    
    if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";
    // If Symbol is CFD or futures but with different profit currency.
    if ((ProfitCalcMode == 1) || ((ProfitCalcMode == 2) && ((ProfitCurrency != AccCurrency))))
    {

        if (ProfitCalcMode == 2) UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures, but will still have to be adjusted by CCC.
        else UnitCost = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE); // Apparently, it is more accurate than taking TICKVALUE directly in some cases.
        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            double CCC = CalculateAdjustment(ProfitCurrency, mode); // Valid only for loss calculation.
            // Adjust the unit cost.
            UnitCost *= CCC;
        }
    }
    else UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures or Forex.
    double OnePoint = MarketInfo(cp, MODE_POINT);

    if (OnePoint != 0) return(UnitCost / OnePoint);
    return UnitCost; // Only in case of an error with MODE_POINT retrieval.
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when ProfitCurrency != AccountCurrency.|
//| ReferenceSymbol changes every time because each symbol has its own RS.            |
//+-----------------------------------------------------------------------------------+
#define FOREX_SYMBOLS_ONLY 0
#define NONFOREX_SYMBOLS_ONLY 1
double CalculateAdjustment(const string profit_currency, const mode_of_operation calc_mode)
{
    string ref_symbol = NULL, add_ref_symbol = NULL;
    bool ref_mode = false, add_ref_mode = false;
    double add_coefficient = 1; // Might be necessary for correction coefficient calculation if two pairs are used for profit currency to account currency conversion. This is handled differently in MT5 version.

    if (ref_symbol == NULL) // Either first run or non-current symbol.
    {
        ref_symbol = GetSymbolByCurrencies(profit_currency, AccCurrency, FOREX_SYMBOLS_ONLY);
        if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(profit_currency, AccCurrency, NONFOREX_SYMBOLS_ONLY);
        ref_mode = true;
        // Failed.
        if (ref_symbol == NULL)
        {
            // Reversing currencies.
            ref_symbol = GetSymbolByCurrencies(AccCurrency, profit_currency, FOREX_SYMBOLS_ONLY);
            if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(AccCurrency, profit_currency, NONFOREX_SYMBOLS_ONLY);
            ref_mode = false;
        }
        if (ref_symbol == NULL)
        {
            if ((!FindDoubleReferenceSymbol("USD", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // USD should work in 99.9% of cases.
             && (!FindDoubleReferenceSymbol("EUR", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // For very rare cases.
             && (!FindDoubleReferenceSymbol("GBP", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // For extremely rare cases.
             && (!FindDoubleReferenceSymbol("JPY", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))) // For extremely rare cases.
            {
                Print("Adjustment calculation critical failure. Failed both simple and two-pair conversion methods.");
                return 1;
            }
        }
    }
    if (add_ref_symbol != NULL) // If two reference pairs are used.
    {
        // Calculate just the additional symbol's coefficient and then use it in final return's multiplication.
        MqlTick tick;
        SymbolInfoTick(add_ref_symbol, tick);
        add_coefficient = GetCurrencyCorrectionCoefficient(tick, calc_mode, add_ref_mode);
    }
    MqlTick tick;
    SymbolInfoTick(ref_symbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, calc_mode, ref_mode) * add_coefficient;
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(const string base_currency, const string profit_currency, const uint symbol_type)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);
        string b_cur;

        // Normal case - Forex pairs:
        if (MarketInfo(symbolname, MODE_PROFITCALCMODE) == 0)
        {
            if (symbol_type == NONFOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency.
            b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        }
        else // Weird case for brokers that set conversion pairs as CFDs.
        {
            if (symbol_type == FOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency as the initial three letters - prone to huge errors!
            b_cur = StringSubstr(symbolname, 0, 3);
        }

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);

        // If the currency pair matches both currencies, select it in Market Watch and return its name.
        if ((b_cur == base_currency) && (p_cur == profit_currency))
        {
            // Select if necessary.
            if (!(bool)SymbolInfoInteger(symbolname, SYMBOL_SELECT)) SymbolSelect(symbolname, true);

            return symbolname;
        }
    }
    return NULL;
}

//+----------------------------------------------------------------------------+
//| Finds reference symbols using 2-pair method.                               |
//| Results are returned via reference parameters.                             |
//| Returns true if found the pairs, false otherwise.                          |
//+----------------------------------------------------------------------------+
bool FindDoubleReferenceSymbol(const string cross_currency, const string profit_currency, string &ref_symbol, bool &ref_mode, string &add_ref_symbol, bool &add_ref_mode)
{
    // A hypothetical example for better understanding:
    // The trader buys CAD/CHF.
    // account_currency is known = SEK.
    // cross_currency = USD.
    // profit_currency = CHF.
    // I.e., we have to buy dollars with francs (using the Ask price) and then sell those for SEKs (using the Bid price).

    ref_symbol = GetSymbolByCurrencies(cross_currency, AccCurrency, FOREX_SYMBOLS_ONLY); 
    if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(cross_currency, AccCurrency, NONFOREX_SYMBOLS_ONLY);
    ref_mode = true; // If found, we've got USD/SEK.

    // Failed.
    if (ref_symbol == NULL)
    {
        // Reversing currencies.
        ref_symbol = GetSymbolByCurrencies(AccCurrency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(AccCurrency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        ref_mode = false; // If found, we've got SEK/USD.
    }
    if (ref_symbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Account currency: ", AccCurrency, ".");
        return false;
    }

    add_ref_symbol = GetSymbolByCurrencies(cross_currency, profit_currency, FOREX_SYMBOLS_ONLY); 
    if (add_ref_symbol == NULL) add_ref_symbol = GetSymbolByCurrencies(cross_currency, profit_currency, NONFOREX_SYMBOLS_ONLY);
    add_ref_mode = false; // If found, we've got USD/CHF. Notice that mode is swapped for cross/profit compared to cross/acc, because it is used in the opposite way.

    // Failed.
    if (add_ref_symbol == NULL)
    {
        // Reversing currencies.
        add_ref_symbol = GetSymbolByCurrencies(profit_currency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (add_ref_symbol == NULL) add_ref_symbol = GetSymbolByCurrencies(profit_currency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        add_ref_mode = true; // If found, we've got CHF/USD. Notice that mode is swapped for profit/cross compared to acc/cross, because it is used in the opposite way.
    }
    if (add_ref_symbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Chart's pair currency: ", profit_currency, ".");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on current prices.       |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick, const mode_of_operation mode, const bool ReferenceSymbolMode)
{
    if ((tick.ask == 0) || (tick.bid == 0)) return -1; // Data is not yet ready.
    if (mode == Risk)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Buy price for reverse quote.
            return tick.ask;
        }
        // Direct quote.
        else
        {
            // Using Sell price for direct quote.
            return(1 / tick.bid);
        }
    }
    else if (mode == Reward)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Sell price for reverse quote.
            return tick.bid;
        }
        // Direct quote.
        else
        {
            // Using Buy price for direct quote.
            return(1 / tick.ask);
        }
    }
    return -1;
}

// Calculates a common breakeven level for all trades on the current symbol.
int PositionsLong, PositionsShort;
double ProfitTotal;
double CalculateSingleBreakeven()
{
    PositionsLong = 0;
    double VolumeLong = 0;
    double PriceLong = 0;
    double ProfitLong = 0;

    PositionsShort = 0;
    double VolumeShort = 0;
    double PriceShort = 0;
    double ProfitShort = 0;

    int PositionsTotal = 0;
    double VolumeTotal = 0;
    ProfitTotal = 0;

    double DistancePoints = 0;
    double BE_Price = 0;

    int total = OrdersTotal();

    // Preliminary run to calculate the number of trades.
    for (int i = 0; i < total; i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() != Symbol()) continue; // Should only consider trades on the current symbol.
            if ((UseMagic) && (OrderMagicNumber() != MagicNumber)) continue;
            if ((UseComment) && (StringFind(OrderComment(), CommentFilter) < 0)) continue;
            if ((OnlyType != All) && (OrderType() != OnlyType)) continue;
            if (OrderType() == OP_BUY)
            {
                if (OnlyType == Sell) continue;
                PositionsLong++;
                VolumeLong += OrderLots();
            }
            else if (OrderType() == OP_SELL)
            {
                if (OnlyType == Buy) continue;
                PositionsShort++;
                VolumeShort += OrderLots();
            }
        }
        else Print("Error selecting order #", i, ": ", GetLastError());
    }

    PositionsTotal = PositionsLong + PositionsShort;

    if (PositionsTotal == 0) return 0; // Nothing to calculate.
    
    AccCurrency = AccountCurrency();
    double point_value_risk = CalculatePointValue(Symbol(), Risk);

    if (point_value_risk == 0) return 0; // No symbol information yet.

    for (int i = 0; i < total; i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderSymbol() != Symbol()) continue; // Should only consider trades on the current symbol.
            if (OrderType() == OP_BUY)
            {
                if (OnlyType == Sell) continue;
                PriceLong += OrderOpenPrice() * OrderLots();
                ProfitLong += OrderProfit();
                if (AdjustForSwapsCommission) ProfitLong += OrderSwap() + OrderCommission();
                if ((PositionsShort > 0) && (AdjustToPrice == ADJUST_TO_ASK)) // Adjusting to price makes sense only when there are Shorts in addition to Longs.
                {
                    ProfitLong -= SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * OrderLots() * point_value_risk;
                }
            }
            else if (OrderType() == OP_SELL)
            {
                if (OnlyType == Buy) continue;
                PriceShort += OrderOpenPrice() * OrderLots();
                ProfitShort += OrderProfit();
                if (AdjustForSwapsCommission) ProfitShort += OrderSwap() + OrderCommission();
                if ((PositionsLong > 0) && (AdjustToPrice == ADJUST_TO_BID)) // Adjusting to price makes sense only when there are Longs in addition to Shorts.
                {
                    ProfitShort -= SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * OrderLots() * point_value_risk;
                }
            }
        }
        else Print("Error selecting order #", i, ": ", GetLastError());
    }

    if (VolumeLong > 0)
    {
        PriceLong /= VolumeLong; // Average buy price.
    }
    if (VolumeShort > 0)
    {
        PriceShort /= VolumeShort; // Average sell price.
    }
    
    VolumeTotal = VolumeLong - VolumeShort;
    ProfitTotal = ProfitLong + ProfitShort;

    if (PositionsTotal > 0)
    {
        if (VolumeTotal != 0)
        {
            if ((ProfitTotal > 0) && (ProfitTotal > AdditionalProfitCur))
            {
                DistancePoints = (ProfitTotal - AdditionalProfitCur) / MathAbs(VolumeTotal * point_value_risk);
            }
            else return 0; // No BE if no profit!
            
            if (VolumeTotal > 0) // Net long.
            {
                BE_Price = Bid - DistancePoints;
            }
            else //  VolumeTotal < 0, which means net short.
            {
                BE_Price = Ask + DistancePoints;
            }
        }
        else // VolumeTotal == 0
        {
            // Don't do anything if the positions are perfectly hedged.
        }
    }

    return BE_Price;
}
//+------------------------------------------------------------------+