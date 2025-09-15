#property link          "https://www.earnforex.com/metatrader-expert-advisors/single-breakeven/"
#property version       "1.01"

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
#include <Trade/Trade.mqh>

enum ENUM_CONSIDER
{
    All = -1,                  // ALL ORDERS
    Buy = POSITION_TYPE_BUY,   // BUY ONLY
    Sell = POSITION_TYPE_SELL  // SELL ONLY
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

CTrade *Trade; // Trading object.

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

    Trade = new CTrade;
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CleanPanel();
    delete Trade;
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
    if (ProfitTotal < ProfitCurToTrigger) return;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        string Instrument = PositionGetSymbol(i);
        if (Instrument == "")
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the position - ", Error);
            Print("ERROR - ", ErrorText);
            continue;
        }
        if (Instrument != Symbol()) continue;
        if ((UseMagic) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((UseComment) && (StringFind(PositionGetString(POSITION_COMMENT), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (PositionGetInteger(POSITION_TYPE) != OnlyType)) continue;

        double NewSL = 0;
        double NewTP = 0;
        double BE_Price_Current = BE_Price; // To keep the global BE_Price unchanged.
        double OpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);

        if (BE_Price_Current != 0)
        {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                if ((AdjustToPrice == ADJUST_TO_ASK) && (PositionsShort > 0)) BE_Price_Current -= SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point; // Shorts will be closed when Ask reaches (Bid - DistancePoints), so Longs should be closed at that moment's Bid.
            }
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                if ((AdjustToPrice == ADJUST_TO_BID) && (PositionsLong > 0)) BE_Price_Current += SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point; // Longs will be closed when Bid reaches (Ask + DistancePoints), so Shorts should be closed at that moment's Ask.
            }
        }

        double TickSize = SymbolInfoDouble(Instrument, SYMBOL_TRADE_TICK_SIZE);
        double SLPrice = PositionGetDouble(POSITION_SL);
        double TPPrice = PositionGetDouble(POSITION_TP);
        double Spread = SymbolInfoInteger(Instrument, SYMBOL_SPREAD) * _Point;
        double StopLevel = SymbolInfoInteger(Instrument, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

        if (TickSize > 0)
        {
            BE_Price_Current = NormalizeDouble(MathRound(BE_Price_Current / TickSize) * TickSize, _Digits);
        }

        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (BE_Price_Current < SymbolInfoDouble(Instrument, SYMBOL_BID) - StopLevel)
            {
                NewSL = NormalizeDouble(BE_Price_Current, _Digits);
                
                if (MathAbs(NewSL - SLPrice) > _Point / 2) // Not trying to set the same SL.
                {
                    bool result = Trade.PositionModify(PositionGetInteger(POSITION_TICKET), NewSL, PositionGetDouble(POSITION_TP));
                    if (result)
                    {
                        Print("Success setting collective breakeven: Buy Position #", PositionGetInteger(POSITION_TICKET), ", new stop-loss = ", DoubleToString(NewSL, _Digits));
                        NotifyStopLossUpdate(PositionGetInteger(POSITION_TICKET), NewSL, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Buy Position #", PositionGetInteger(POSITION_TICKET), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, _Digits),
                              ", old SL = ", DoubleToString(SLPrice, _Digits),
                              ", new SL = ", DoubleToString(NewSL, _Digits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                    }
                }
            }
            else if (BE_Price_Current > SymbolInfoDouble(Symbol(), SYMBOL_ASK) + StopLevel) // BE price above current price = TP for a Buy.
            {
                NewTP = NormalizeDouble(BE_Price_Current, _Digits);

                if (MathAbs(NewTP - TPPrice) > _Point / 2) // Not trying to set the same TP.
                {
                    bool result = Trade.PositionModify(PositionGetInteger(POSITION_TICKET),PositionGetDouble(POSITION_SL) , NewTP);
                    if (result)
                    {
                        Print("Success setting collective breakeven: Buy Position #", PositionGetInteger(POSITION_TICKET), ", new take-profit = ", DoubleToString(NewTP, _Digits));
                        NotifyStopLossUpdate(PositionGetInteger(POSITION_TICKET), NewSL, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Buy Position #", PositionGetInteger(POSITION_TICKET), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, _Digits),
                              ", old TP = ", DoubleToString(TPPrice, _Digits),
                              ", new TP = ", DoubleToString(NewTP, _Digits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                    }
                }
            }
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (BE_Price_Current > SymbolInfoDouble(Symbol(), SYMBOL_ASK) + StopLevel) // BE price above current price = SL for a Sell.
            {
                NewSL = NormalizeDouble(BE_Price_Current, _Digits);
                
                if (MathAbs(NewSL - SLPrice) > _Point / 2) // Not trying to set the same SL.
                {
                    bool result = Trade.PositionModify(PositionGetInteger(POSITION_TICKET), NewSL, PositionGetDouble(POSITION_TP));
                    if (result)
                    {
                        Print("Success setting collective breakeven: Sell Position #", PositionGetInteger(POSITION_TICKET), ", new stop-loss = ", DoubleToString(NewSL, _Digits));
                        NotifyStopLossUpdate(PositionGetInteger(POSITION_TICKET), NewSL, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Sell Position #", PositionGetInteger(POSITION_TICKET), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, _Digits),
                              ", old SL = ", DoubleToString(SLPrice, _Digits),
                              ", new SL = ", DoubleToString(NewSL, _Digits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                    }
                }
            }
            else if (BE_Price_Current < SymbolInfoDouble(Symbol(), SYMBOL_BID) - StopLevel) // BE price below current price = TP for a Sell.
            {
                NewTP = NormalizeDouble(BE_Price_Current, _Digits);

                if (MathAbs(NewTP - TPPrice) > _Point / 2) // Not trying to set the same TP.
                {
                    bool result = Trade.PositionModify(PositionGetInteger(POSITION_TICKET),PositionGetDouble(POSITION_SL) , NewTP);
                    if (result)
                    {
                        Print("Success setting collective breakeven: Sell Position #", PositionGetInteger(POSITION_TICKET), ", new take-profit = ", DoubleToString(NewTP, _Digits));
                        NotifyStopLossUpdate(PositionGetInteger(POSITION_TICKET), NewSL, Symbol());
                    }
                    else
                    {
                        int Error = GetLastError();
                        string ErrorText = GetLastErrorText(Error);
                        Print("Error setting collective breakeven: Sell Position #", PositionGetInteger(POSITION_TICKET), ", error = ", Error, " (", ErrorText, "), open price = ", DoubleToString(OpenPrice, _Digits),
                              ", old TP = ", DoubleToString(TPPrice, _Digits),
                              ", new TP = ", DoubleToString(NewTP, _Digits), ", Bid = ", SymbolInfoDouble(Instrument, SYMBOL_BID), ", Ask = ", SymbolInfoDouble(Instrument, SYMBOL_ASK));
                    }
                }
            }
        }
    }
    LastAdjustment = TimeCurrent();
}

void NotifyStopLossUpdate(long Ticket, double SLPrice, string Instrument)
{
    string type = "Stop-loss";
    NotifyUpdate(Ticket, SLPrice, Instrument, type);
}

void NotifyTakeProfitUpdate(long  Ticket, double TPPrice, string Instrument)
{
    string type = "Take-profit";
    NotifyUpdate(Ticket, TPPrice, Instrument, type);
}

void NotifyUpdate(long  Ticket, double Price, string Instrument, string type)
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    string EmailSubject = ExpertName + " " + Instrument + " Notification";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n\r\n" + ExpertName + " Notification for " + Instrument + "\r\n\r\n";
    EmailBody += type + " for position #" + IntegerToString(Ticket) + " has been moved to a collective breakeven.";
    string AlertText = type + " for position #" + IntegerToString(Ticket) + " has been moved to a collective breakeven.";
    string AppText = ExpertName + " - " + Instrument + ": ";
    AppText += type + " for position #" + IntegerToString(Ticket) + " was moved to a collective breakeven.";
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
    string PanelToolTip = "Move stop to breakeven";
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
    ChartRedraw();
}

void CleanPanel()
{
    ObjectsDeleteAll(ChartID(), ExpertName + "-P-");
    ChartRedraw();
}

void ChangeTrailingEnabled()
{
    if (EnableTrailing == false)
    {
        if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            MessageBox("Algorithmic trading is disabled in the platform's options! Please enable it via Tools->Options->Expert Advisors.", "WARNING", MB_OK);
            return;
        }
        if (!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
            MessageBox("Algo Trading is disabled in the Position Sizer's settings! Please tick the Allow Algo Trading checkbox on the Common tab.", "WARNING", MB_OK);
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
double CalculatePointValue(mode_of_operation mode)
{
    string cp = Symbol();
    double UnitCost = CalculateUnitCost(cp, mode);
    double OnePoint = SymbolInfoDouble(cp, SYMBOL_POINT);
    return(UnitCost / OnePoint);
}

//+----------------------------------------------------------------------+
//| Returns unit cost either for Risk or for Reward mode.                |
//+----------------------------------------------------------------------+
double CalculateUnitCost(const string cp, const mode_of_operation mode)
{
    ENUM_SYMBOL_CALC_MODE CalcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(cp, SYMBOL_TRADE_CALC_MODE);

    // No-Forex.
    if ((CalcMode != SYMBOL_CALC_MODE_FOREX) && (CalcMode != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) && (CalcMode != SYMBOL_CALC_MODE_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS))
    {
        double TickSize = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE);
        double UnitCost = TickSize * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE);
        string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
        if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";

        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            return(UnitCost * CalculateAdjustment(ProfitCurrency, mode));
        }
        return UnitCost;
    }
    // With Forex instruments, tick value already equals 1 unit cost.
    else
    {
        if (mode == Risk) return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_LOSS);
        else return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_PROFIT);
    }
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when GivenCurrency != AccountCurrency. |
//| Used in two cases: profit adjustment and margin adjustment.                       |
//+-----------------------------------------------------------------------------------+
double CalculateAdjustment(const string ProfitCurrency, const mode_of_operation mode)
{
    string ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, AccCurrency);
    bool ReferenceSymbolMode = true;
    // Failed.
    if (ReferenceSymbol == NULL)
    {
        // Reversing currencies.
        ReferenceSymbol = GetSymbolByCurrencies(AccCurrency, ProfitCurrency);
        ReferenceSymbolMode = false;
    }
    // Everything failed.
    if (ReferenceSymbol == NULL)
    {
        Print("Error! Cannot detect proper currency pair for adjustment calculation: ", ProfitCurrency, ", ", AccCurrency, ".");
        ReferenceSymbol = Symbol();
        return 1;
    }
    MqlTick tick;
    SymbolInfoTick(ReferenceSymbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, mode, ReferenceSymbolMode);
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(string base_currency, string profit_currency)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);

        // Skip non-Forex pairs.
        if ((SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX) && (SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)) continue;

        // Get its base currency.
        string b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        if (b_cur == "RUR") b_cur = "RUB";

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);
        if (p_cur == "RUR") p_cur = "RUB";
        
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

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on profit currency,      |
//| calculation mode (profit or loss), reference pair mode (reverse  |
//| or direct), and current prices.                                  |
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

double CalculateCommission()
{
    double commission_sum = 0;
    if (!HistorySelectByPosition(PositionGetInteger(POSITION_IDENTIFIER)))
    {
        Print("HistorySelectByPosition failed: ", GetLastError());
        return 0;
    }
    int deals_total = HistoryDealsTotal();
    for (int i = 0; i < deals_total; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if (deal_ticket == 0)
        {
            Print("HistoryDealGetTicket failed: ", GetLastError());
            continue;
        }
        if ((HistoryDealGetInteger(deal_ticket, DEAL_TYPE) != DEAL_TYPE_BUY) && (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) != DEAL_TYPE_SELL)) continue; // Wrong kinds of deals.
        if (HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue; // Only entry deals.
        commission_sum += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
    }
    return commission_sum;
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

    int PosTotal = 0;
    double VolumeTotal = 0;
    ProfitTotal = 0;

    double DistancePoints = 0;
    double BE_Price = 0;

    int total = PositionsTotal();

    // Preliminary run to calculate the number of trades.
    for (int i = 0; i < total; i++)
    {
        string Instrument = PositionGetSymbol(i);
        if (Instrument == "")
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the position - ", Error);
            Print("ERROR - ", ErrorText);
            continue;
        }
        if (Instrument != Symbol()) continue; // Should only consider trades on the current symbol.
        if ((UseMagic) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((UseComment) && (StringFind(PositionGetString(POSITION_COMMENT), CommentFilter) < 0)) continue;
        if ((OnlyType != All) && (PositionGetInteger(POSITION_TYPE) != OnlyType)) continue;
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (OnlyType == Sell) continue;
            PositionsLong++;
            VolumeLong += PositionGetDouble(POSITION_VOLUME);
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (OnlyType == Buy) continue;
            PositionsShort++;
            VolumeShort += PositionGetDouble(POSITION_VOLUME);
        }
    }

    PosTotal = PositionsLong + PositionsShort;

    if (PosTotal == 0) return 0; // Nothing to calculate.
    
    AccCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    double point_value_risk = CalculatePointValue(Risk);

    if (point_value_risk == 0) return 0; // No symbol information yet.

    for (int i = 0; i < total; i++)
    {
        string Instrument = PositionGetSymbol(i);
        if (Instrument == "")
        {
            int Error = GetLastError();
            string ErrorText = GetLastErrorText(Error);
            Print("ERROR - Unable to select the position - ", Error);
            Print("ERROR - ", ErrorText);
            continue;
        }
        if (Instrument != Symbol()) continue; // Should only consider trades on the current symbol.
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (OnlyType == Sell) continue;
            PriceLong += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
            ProfitLong += PositionGetDouble(POSITION_PROFIT);
            if (AdjustForSwapsCommission) ProfitLong += PositionGetDouble(POSITION_SWAP) + CalculateCommission();
            if ((PositionsShort > 0) && (AdjustToPrice == ADJUST_TO_ASK)) // Adjusting to price makes sense only when there are Shorts in addition to Longs.
            {
                ProfitLong -= SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * PositionGetDouble(POSITION_VOLUME) * point_value_risk;
            }
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (OnlyType == Buy) continue;
            PriceShort += PositionGetDouble(POSITION_PRICE_OPEN) * PositionGetDouble(POSITION_VOLUME);
            ProfitShort += PositionGetDouble(POSITION_PROFIT);
            if (AdjustForSwapsCommission) ProfitShort += PositionGetDouble(POSITION_SWAP) + CalculateCommission();
            if ((PositionsLong > 0) && (AdjustToPrice == ADJUST_TO_BID)) // Adjusting to price makes sense only when there are Longs in addition to Shorts.
            {
                ProfitShort -= SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * _Point * PositionGetDouble(POSITION_VOLUME) * point_value_risk;
            }
        }
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

    if (PosTotal > 0)
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
                BE_Price = SymbolInfoDouble(Symbol(), SYMBOL_BID) - DistancePoints;
            }
            else //  VolumeTotal < 0, which means net short.
            {
                BE_Price = SymbolInfoDouble(Symbol(), SYMBOL_ASK) + DistancePoints;
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