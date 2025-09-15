// -------------------------------------------------------------------------------
//   This cBot will set a single breakeven level for multiple trades on the same symbol.
//   WARNING: Use this software at your own risk.
//   The creator of this robot cannot be held responsible for any damage or loss.
//
//   Version 1.001
//   Copyright 2025, EarnForex.com
//   https://www.earnforex.com/metatrader-expert-advisors/single-breakeven/
// -------------------------------------------------------------------------------

using System;
using cAlgo.API;
using cAlgo.API.Internals;

namespace cAlgo.Robots
{
    [Robot(AccessRights = AccessRights.None)]
    public class SingleBreakeven : Robot
    {
        #region Parameters
        
        [Parameter("Total profit in currency to trigger single BE", DefaultValue = 100, Group = "Expert Advisor Settings")]
        public int ProfitCurToTrigger { get; set; }
        
        [Parameter("Additional profit in currency for single BE", DefaultValue = 0, Group = "Expert Advisor Settings")]
        public int AdditionalProfitCur { get; set; }
        
        public enum ENUM_ADJUST_TO
        {
            ADJUST_DONT,   // Don't adjust
            ADJUST_TO_ASK, // Adjust to Ask price
            ADJUST_TO_BID  // Adjust to Bid price
        }
        
        [Parameter("Adjust single BE to which price?", DefaultValue = ENUM_ADJUST_TO.ADJUST_TO_BID, Group = "Expert Advisor Settings")]
        public ENUM_ADJUST_TO AdjustToPrice { get; set; }
        
        [Parameter("Delay (sec) between adjustments", DefaultValue = 60, Group = "Expert Advisor Settings")]
        public int DelayBetweenAdjustments { get; set; }
        
        [Parameter("Adjust for swaps & commission?", DefaultValue = false, Group = "Expert Advisor Settings")]
        public bool AdjustForSwapsCommission { get; set; }
        
        public enum ENUM_CONSIDER
        {
            All = -1,  // ALL ORDERS
            Buy = 0,   // BUY ONLY
            Sell = 1   // SELL ONLY
        }
        
        [Parameter("Apply to", DefaultValue = ENUM_CONSIDER.All, Group = "Orders Filtering Options")]
        public ENUM_CONSIDER OnlyType { get; set; }
        
        [Parameter("Filter by label", DefaultValue = false, Group = "Orders Filtering Options")]
        public bool UseLabel { get; set; }
        
        [Parameter("Label (if above is true)", DefaultValue = "", Group = "Orders Filtering Options")]
        public string LabelFilter { get; set; }
        
        [Parameter("Filter by comment", DefaultValue = false, Group = "Orders Filtering Options")]
        public bool UseComment { get; set; }
        
        [Parameter("Comment (if above is true)", DefaultValue = "", Group = "Orders Filtering Options")]
        public string CommentFilter { get; set; }
        
        [Parameter("Enable Breakeven EA", DefaultValue = false, Group = "Orders Filtering Options")]
        public bool EnableTrailingParam { get; set; }
        
        [Parameter("Enable notifications feature", DefaultValue = false, Group = "Notification Options")]
        public bool EnableNotify { get; set; }
        
        [Parameter("Send alert notifications", DefaultValue = false, Group = "Notification Options")]
        public bool SendAlert { get; set; }
        
        [Parameter("Send notifications via email", DefaultValue = false, Group = "Notification Options")]
        public bool SendEmail { get; set; }
        
        [Parameter("Email Address", DefaultValue = "email@example.com", Group = "Notification Options")]
        public string EmailAddress { get; set; }

        [Parameter("Show graphical panel", DefaultValue = true, Group = "Graphical Window")]
        public bool ShowPanel { get; set; }
        
        [Parameter("Horizontal spacing for the control panel", DefaultValue = 20, Group = "Graphical Window")]
        public int Xoff { get; set; }
        
        [Parameter("Vertical spacing for the control panel", DefaultValue = 20, Group = "Graphical Window")]
        public int Yoff { get; set; }
        
        [Parameter("Font Size", DefaultValue = 18, Group = "Graphical Window")]
        public int FontSize { get; set; }
        
        #endregion

        #region Private Variables
        
        private bool EnableTrailing;
        private DateTime LastAdjustment;
        private int PositionsLong, PositionsShort;
        private double ProfitTotal;

        private Canvas ControlPanel;
        
        #endregion

        protected override void OnStart()
        {
            EnableTrailing = EnableTrailingParam;
            LastAdjustment = Server.Time.AddSeconds(-DelayBetweenAdjustments);
            
            if (ShowPanel) DrawPanel();
        }

        protected override void OnTick()
        {
            if (EnableTrailing) DoSingleBE();
        }

        private void DoSingleBE()
        {
            if (Server.Time < LastAdjustment.AddSeconds(DelayBetweenAdjustments)) return;
            
            double BE_Price = CalculateSingleBreakeven();
            if (BE_Price <= 0) return;
            if (ProfitTotal < ProfitCurToTrigger) return;
            
            foreach (var position in Positions)
            {
                if (position.SymbolName != SymbolName) continue;
                if ((UseLabel) && (position.Label != LabelFilter)) continue;
                if ((UseComment) && (!position.Comment.Contains(CommentFilter))) continue;
                if ((OnlyType == ENUM_CONSIDER.Buy) && (position.TradeType != TradeType.Buy)) continue;
                if ((OnlyType == ENUM_CONSIDER.Sell) && (position.TradeType != TradeType.Sell)) continue;
                
                double NewSL = 0;
                double NewTP = 0;
                double BE_Price_Current = BE_Price; // To keep the global BE_Price unchanged.
                
                if (BE_Price_Current != 0)
                {
                    if (position.TradeType == TradeType.Buy)
                    {
                        if ((AdjustToPrice == ENUM_ADJUST_TO.ADJUST_TO_ASK) && (PositionsShort > 0))
                        {
                            // Shorts will be closed when Ask reaches (Bid - DistancePoints), so Longs should be closed at that moment's Bid.
                            BE_Price_Current -= Symbol.Spread * Symbol.PipSize;
                        }
                    }
                    else if (position.TradeType == TradeType.Sell)
                    {
                        if ((AdjustToPrice == ENUM_ADJUST_TO.ADJUST_TO_BID) && (PositionsLong > 0))
                        {
                            // Longs will be closed when Bid reaches (Ask + DistancePoints), so Shorts should be closed at that moment's Ask.
                            BE_Price_Current += Symbol.Spread * Symbol.PipSize;
                        }
                    }
                }
                
                double AskStopLevelSL, BidStopLevelSL, AskStopLevelTP, BidStopLevelTP;
                if (Symbol.MinDistanceType == SymbolMinDistanceType.Pips)
                {
                    AskStopLevelSL = Symbol.Ask + Symbol.MinStopLossDistance * Symbol.PipSize;
                    BidStopLevelSL = Symbol.Bid - Symbol.MinStopLossDistance * Symbol.PipSize;
                    AskStopLevelTP = Symbol.Ask + Symbol.MinTakeProfitDistance * Symbol.PipSize;
                    BidStopLevelTP = Symbol.Bid - Symbol.MinTakeProfitDistance * Symbol.PipSize;
                }
                else // Percentage.
                {
                    AskStopLevelSL = Symbol.Ask * (1 + Symbol.MinStopLossDistance / 100);
                    BidStopLevelSL = Symbol.Bid * (1 + Symbol.MinStopLossDistance / 100);
                    AskStopLevelTP = Symbol.Ask * (1 + Symbol.MinTakeProfitDistance / 100);
                    BidStopLevelTP = Symbol.Bid * (1 + Symbol.MinTakeProfitDistance / 100);
                }
                if (position.TradeType == TradeType.Buy)
                {
                    if (BE_Price_Current < BidStopLevelSL)
                    {
                        NewSL = Math.Round(BE_Price_Current, Symbol.Digits);
                        
                        if (Math.Abs(NewSL - (position.StopLoss ?? 0)) > Symbol.TickSize / 2) // Not trying to set the same SL.
                        {
                            var result = position.ModifyStopLossPrice(NewSL);
                            if (result.IsSuccessful)
                            {
                                Print("Success setting collective breakeven: Buy Position #", position.Id, ", new stop-loss = ", NewSL.ToString("F" + Symbol.Digits));
                                NotifyStopLossUpdate(position.Id, NewSL, SymbolName);
                            }
                            else
                            {
                                Print("Error setting collective breakeven: Buy Position #", position.Id, ", error = ", result.Error,
                                      ", open price = ", position.EntryPrice.ToString("F" + Symbol.Digits),
                                      ", old SL = ", (position.StopLoss ?? 0).ToString("F" + Symbol.Digits),
                                      ", new SL = ", NewSL.ToString("F" + Symbol.Digits), 
                                      ", Bid = ", Symbol.Bid, ", Ask = ", Symbol.Ask);
                            }
                        }
                    }
                    else if (BE_Price_Current > AskStopLevelTP) // BE price above current price = TP for a Buy.
                    {
                        NewTP = Math.Round(BE_Price_Current, Symbol.Digits);
                        
                        if (Math.Abs(NewTP - (position.TakeProfit ?? 0)) > Symbol.TickSize / 2) // Not trying to set the same TP.
                        {
                            var result = position.ModifyTakeProfitPrice(NewTP);
                            if (result.IsSuccessful)
                            {
                                Print("Success setting collective breakeven: Buy Position #", position.Id, ", new take-profit = ", NewTP.ToString("F" + Symbol.Digits));
                                NotifyTakeProfitUpdate(position.Id, NewTP, SymbolName);
                            }
                            else
                            {
                                Print("Error setting collective breakeven: Buy Position #", position.Id, ", error = ", result.Error,
                                      ", open price = ", position.EntryPrice.ToString("F" + Symbol.Digits),
                                      ", old TP = ", (position.TakeProfit ?? 0).ToString("F" + Symbol.Digits),
                                      ", new TP = ", NewTP.ToString("F" + Symbol.Digits), 
                                      ", Bid = ", Symbol.Bid, ", Ask = ", Symbol.Ask);
                            }
                        }
                    }
                }
                else if (position.TradeType == TradeType.Sell)
                {
                    if (BE_Price_Current > AskStopLevelSL) // BE price above current price = SL for a Sell.
                    {
                        NewSL = Math.Round(BE_Price_Current, Symbol.Digits);
                        
                        if (Math.Abs(NewSL - (position.StopLoss ?? 0)) > Symbol.TickSize / 2) // Not trying to set the same SL.
                        {
                            var result = position.ModifyStopLossPrice(NewSL);
                            if (result.IsSuccessful)
                            {
                                Print("Success setting collective breakeven: Sell Position #", position.Id, ", new stop-loss = ", NewSL.ToString("F" + Symbol.Digits));
                                NotifyStopLossUpdate(position.Id, NewSL, SymbolName);
                            }
                            else
                            {
                                Print("Error setting collective breakeven: Sell Position #", position.Id, ", error = ", result.Error,
                                      ", open price = ", position.EntryPrice.ToString("F" + Symbol.Digits),
                                      ", old SL = ", (position.StopLoss ?? 0).ToString("F" + Symbol.Digits),
                                      ", new SL = ", NewSL.ToString("F" + Symbol.Digits), 
                                      ", Bid = ", Symbol.Bid, ", Ask = ", Symbol.Ask);
                            }
                        }
                    }
                    else if (BE_Price_Current < BidStopLevelTP) // BE price below current price = TP for a Sell.
                    {
                        NewTP = Math.Round(BE_Price_Current, Symbol.Digits);
                        
                        if (Math.Abs(NewTP - (position.TakeProfit ?? 0)) > Symbol.TickSize / 2) // Not trying to set the same TP.
                        {
                            var result = position.ModifyTakeProfitPrice(NewTP);
                            if (result.IsSuccessful)
                            {
                                Print("Success setting collective breakeven: Sell Position #", position.Id, ", new take-profit = ", NewTP.ToString("F" + Symbol.Digits));
                                NotifyTakeProfitUpdate(position.Id, NewTP, SymbolName);
                            }
                            else
                            {
                                Print("Error setting collective breakeven: Sell Position #", position.Id, ", error = ", result.Error,
                                      ", open price = ", position.EntryPrice.ToString("F" + Symbol.Digits),
                                      ", old TP = ", (position.TakeProfit ?? 0).ToString("F" + Symbol.Digits),
                                      ", new TP = ", NewTP.ToString("F" + Symbol.Digits), 
                                      ", Bid = ", Symbol.Bid, ", Ask = ", Symbol.Ask);
                            }
                        }
                    }
                }
            }
            LastAdjustment = Server.Time;
        }

        private void NotifyStopLossUpdate(long Ticket, double SLPrice, string Instrument)
        {
            string type = "Stop-loss";
            NotifyUpdate(Ticket, SLPrice, Instrument, type);
        }

        private void NotifyTakeProfitUpdate(long Ticket, double TPPrice, string Instrument)
        {
            string type = "Take-profit";
            NotifyUpdate(Ticket, TPPrice, Instrument, type);
        }

        private void NotifyUpdate(long Ticket, double Price, string Instrument, string type)
        {
            if (!EnableNotify) return;
            if ((!SendAlert) && (!SendEmail)) return;
            
            string AlertText = type + " for position #" + Ticket + " has been moved to a collective breakeven.";
            string EmailSubject = "Single BE " + Instrument + " Notification";
            string EmailBody = Account.BrokerName + " - " + Account.Number + "\r\n\r\n" + 
                              "Single BE  Notification for " + Instrument + "\r\n\r\n" +
                              type + " for position #" + Ticket + " has been moved to a collective breakeven.";
            
            if (SendAlert) 
            {
                Notifications.ShowPopup(EmailSubject, AlertText, PopupNotificationState.Information);
            }

            if (SendEmail)
            {
                Notifications.SendEmail(EmailAddress, EmailAddress, EmailSubject, EmailBody);
            }
        }

        // Calculates a common breakeven level for all trades on the current symbol.
        private double CalculateSingleBreakeven()
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

            // Preliminary run to calculate the number of trades.
            foreach (var position in Positions)
            {
                if (position.SymbolName != SymbolName) continue; // Should only consider trades on the current symbol.
                if ((UseLabel) && (position.Label != LabelFilter)) continue;
                if ((UseComment) && (!position.Comment.Contains(CommentFilter))) continue;
                if ((OnlyType == ENUM_CONSIDER.Buy) && (position.TradeType != TradeType.Buy)) continue;
                if ((OnlyType == ENUM_CONSIDER.Sell) && (position.TradeType != TradeType.Sell)) continue;
                
                if (position.TradeType == TradeType.Buy)
                {
                    PositionsLong++;
                    VolumeLong += position.VolumeInUnits;
                }
                else if (position.TradeType == TradeType.Sell)
                {
                    PositionsShort++;
                    VolumeShort += position.VolumeInUnits;
                }
            }

            PosTotal = PositionsLong + PositionsShort;

            if (PosTotal == 0) return 0; // Nothing to calculate.
            
            // Calculate pip value for the symbol.
            double pip_value = Symbol.PipValue;
            
            foreach (var position in Positions)
            {
                if (position.SymbolName != SymbolName) continue; // Should only consider trades on the current symbol.
                if ((UseLabel) && (position.Label != LabelFilter)) continue;
                if ((UseComment) && (!position.Comment.Contains(CommentFilter))) continue;
                
                if (position.TradeType == TradeType.Buy)
                {
                    if (OnlyType == ENUM_CONSIDER.Sell) continue;
                    PriceLong += position.EntryPrice * position.VolumeInUnits;
                    ProfitLong += position.GrossProfit;
                    
                    if (AdjustForSwapsCommission) 
                    {
                        ProfitLong += position.Swap + position.Commissions;
                    }
                    
                    if ((PositionsShort > 0) && (AdjustToPrice == ENUM_ADJUST_TO.ADJUST_TO_ASK)) // Adjusting to price makes sense only when there are Shorts in addition to Longs.
                    {
                        // Adjust for spread when calculating breakeven.
                        ProfitLong -= Symbol.Spread * position.VolumeInUnits * pip_value;
                    }
                }
                else if (position.TradeType == TradeType.Sell)
                {
                    if (OnlyType == ENUM_CONSIDER.Buy) continue;
                    PriceShort += position.EntryPrice * position.VolumeInUnits;
                    ProfitShort += position.GrossProfit;
                    
                    if (AdjustForSwapsCommission) 
                    {
                        ProfitShort += position.Swap + position.Commissions;
                    }
                    
                    if ((PositionsLong > 0) && (AdjustToPrice == ENUM_ADJUST_TO.ADJUST_TO_BID)) // Adjusting to price makes sense only when there are Longs in addition to Shorts.
                    {
                        // Adjust for spread when calculating breakeven.
                        ProfitShort -= Symbol.Spread * position.VolumeInUnits * pip_value;
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
                        // Convert profit in currency to distance in price.
                        // In cTrader, pip_value is already in account currency per pip per unit.
                        DistancePoints = (ProfitTotal - AdditionalProfitCur) / (Math.Abs(VolumeTotal) * pip_value);
                        DistancePoints *= Symbol.PipSize; // Convert from pips to price.
                    }
                    else return 0; // No BE if no profit!
                    
                    if (VolumeTotal > 0) // Net long.
                    {
                        BE_Price = Symbol.Bid - DistancePoints;
                    }
                    else //  VolumeTotal < 0, which means net short.
                    {
                        BE_Price = Symbol.Ask + DistancePoints;
                    }
                }
                else // VolumeTotal == 0
                {
                    // Don't do anything if the positions are perfectly hedged.
                }
            }

            return BE_Price;
        }

        private void DrawPanel()
        {
            ControlPanel = new Canvas
            {
                Opacity = 0.7,
            };
            string EnableDisabledText = EnableTrailing ? "Single Breakeven Enabled" : "Single Breakeven Disabled";
            Color TextColor = EnableTrailing ? Color.Green : Color.Red;
            var EnableDisableButton = new Button
            {
                Text = EnableDisabledText,
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Top,
                Left = Xoff,
                Top = Yoff,
                FontSize = FontSize,
                BackgroundColor = Color.LightGray,
                BorderColor = Color.SlateGray,
                ForegroundColor = TextColor,
                BorderThickness = 2,
                CornerRadius = 0,
                Width = 250,
                Height = 40
            };
            EnableDisableButton.Click += ChangeTrailingEnabled;
            ControlPanel.AddChild(EnableDisableButton);
            Chart.AddControl(ControlPanel);
        }

        private void ChangeTrailingEnabled(ButtonClickEventArgs obj)
        {
            if (EnableTrailing == false)
            {
                EnableTrailing = true;
                obj.Button.Text = "Single Breakeven Enabled";
                obj.Button.ForegroundColor = Color.Green;
            }
            else
            {
                EnableTrailing = false;
                obj.Button.Text = "Single Breakeven Disabled";
                obj.Button.ForegroundColor = Color.Red;
            }
        }
    }
}