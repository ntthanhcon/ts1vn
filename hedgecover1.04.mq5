//+------------------------------------------------------------------+
//|                 HedgeCover EA - Intelligent Position Protection  |
//|                               Copyright 2025, Lupus Materia Ltd. |
//|                                    https://www.lupusmateria.com/ |
//+------------------------------------------------------------------+
//| WARNING: This trading robot comes with no guarantees of profit.  |
//| Forex trading involves substantial risk of loss.                 |
//| Only use risk capital you can afford to lose.                    |
//| No liability accepted for any losses incurred.                   |
//| Always test thoroughly in demo account before live use.          |
//|                                                                  |
//| FEATURES:                                                        |
//| • One-hedge-per-position (no infinite loops)                     |
//| • Separate magic numbers for main/hedge positions                |
//| • Configurable loss threshold (30-100 pips recommended)          |
//| • Cooldown period between hedge trades (5-15 min)                |
//| • Maximum hedges limit for risk control                          |
//| • Margin safety checks (80% free margin requirement)             |
//| • Symbol filtering (only hedges current chart symbol)            |
//|                                                                  |
//| RISK CONTROLS:                                                   |
//| • Prevents hedging of hedge positions                            |
//| • Tracks already-hedged positions                                |
//| • Lot size validation and normalization                          |
//| • Optional maximum total hedges limit                            |
//|                                                                  |
//| RECOMMENDED SETTINGS:                                            |
//| • Main Magic: Your strategy's magic number                       |
//| • Hedge Magic: DIFFERENT value (e.g., 99999)                     |
//| • Loss Threshold: 50 pips                                        |
//| • Lot Coefficient: 1.5x                                          |
//| • Max Hedges: 3                                                  |
//| • Cooldown: 5 minutes                                            |
//+------------------------------------------------------------------+
#property version   "1.004"
#property description "HedgeCover EA - Intelligent Position Protection System"
#property description "Provides safe hedging with multiple risk controls"
#property description "Free for MT5 community - Use at your own risk"
//---
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
CPositionInfo  m_position;                   // trade position object
CTrade         m_trade;                      // trading object
CSymbolInfo    m_symbol;                     // symbol info object
CAccountInfo   m_account;                    // account info wrapper

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== MAIN STRATEGY SETTINGS ==="
input ulong    InpMagicNumber    = 0;        // Main strategy magic number (0=all positions)
input ushort   InpLosing         = 50;       // Loss threshold in pips (30-100 recommended)

input group "=== HEDGE SAFETY SETTINGS ==="
input ulong    InpHedgeMagicNumber = 99999;  // MUST be different from main magic!
input double   InpLotCoefficient = 1.5;      // Hedge lot multiplier (1.0-3.0)
input int      InpMaxHedges      = 3;        // Max total hedges (0=unlimited, 2-5 recommended)

input group "=== RISK MANAGEMENT ==="
input int      InpCooldownMinutes = 5;       // Minutes between hedge trades (5-15)
input bool     InpPrintResult    = true;     // Enable logging for monitoring

input group "=== SYMBOL SETTINGS ==="
// Note: EA only hedges positions on the current chart symbol
//+------------------------------------------------------------------+

//--- global variables
ulong          m_slippage=30;                // increased slippage
long           hedged_positions[];           // array of already hedged positions
datetime       last_hedge_time = 0;          // last hedge time

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayResize(hedged_positions, 0);
   last_hedge_time = 0;
   Print("SAFE Hedge EA initialized. Cooldown: ", InpCooldownMinutes, " minutes");
   if(InpHedgeMagicNumber == InpMagicNumber && InpHedgeMagicNumber != 0)
      Print("WARNING: Hedge Magic same as Main Magic - may lead to hedging of hedges");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("Hedge EA deinitialized. Total hedged positions: ", ArraySize(hedged_positions));
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  
//--- Use this snippet for stratedgy tester
// 
//if(PositionsTotal() == 0) {
// m_trade.Sell(0.1, _Symbol, 0, 0, 0, "Test Position");
// Print("Opened test BUY position for hedging simulation");
//}
//

//--- SAFETY: Cooldown period check
   if(last_hedge_time > 0 && (TimeCurrent() - last_hedge_time) < (InpCooldownMinutes * 60))
     {
      if(InpPrintResult)
         Print("Cooldown active. Next hedge in: ", (InpCooldownMinutes * 60) - (TimeCurrent() - last_hedge_time), " seconds");
      return;
     }

//--- Check all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!m_position.SelectByIndex(i))
         continue;

      //--- Magic number filter
      if(InpMagicNumber != 0 && m_position.Magic() != InpMagicNumber)
         continue;

      //--- Exclude hedge positions if hedge magic is set
      if(InpHedgeMagicNumber != 0 && m_position.Magic() == InpHedgeMagicNumber)
         continue;

      //--- Symbol filter (only current chart symbol)
      if(m_position.Symbol() != _Symbol)
         continue;

      long position_id = m_position.Identifier();

      //--- CRITICAL: Check if this position was already hedged
      if(IsPositionAlreadyHedged(position_id))
         continue;

      //--- Check max hedges limit
      if(InpMaxHedges > 0 && ArraySize(hedged_positions) >= InpMaxHedges)
        {
         Print("Max hedges reached: ", InpMaxHedges, ". Skipping further hedges.");
         continue;
        }

      //--- Refresh symbol data
      double freeze_level = 0.0, stop_level = 0.0;
      if(!RefreshRates(m_position.Symbol(), m_position.Magic(), freeze_level, stop_level))
         continue;

      //--- Calculate loss in pips
      double point_adjust = (m_symbol.Digits() == 3 || m_symbol.Digits() == 5) ? 10 : 1;
      double loss_in_pips = 0;

      if(m_position.PositionType() == POSITION_TYPE_BUY)
         loss_in_pips = (m_position.PriceOpen() - m_position.PriceCurrent()) / (m_symbol.Point() * point_adjust);
      else
         if(m_position.PositionType() == POSITION_TYPE_SELL)
            loss_in_pips = (m_position.PriceCurrent() - m_position.PriceOpen()) / (m_symbol.Point() * point_adjust);

      //--- Check if loss threshold reached
      if(loss_in_pips >= InpLosing)
        {
         Print("Hedge triggered! Position #", position_id, " Loss: ", DoubleToString(loss_in_pips, 1), " pips");

         double hedge_lot = LotCheck(m_position.Volume() * InpLotCoefficient);
         if(hedge_lot <= 0)
           {
            Print("Error: Invalid lot size calculated: ", hedge_lot);
            continue;
           }

         bool hedge_success = false;

         //--- Open opposite position
         if(m_position.PositionType() == POSITION_TYPE_BUY)
            hedge_success = OpenSell(hedge_lot, 0.0, 0.0);
         else
            if(m_position.PositionType() == POSITION_TYPE_SELL)
               hedge_success = OpenBuy(hedge_lot, 0.0, 0.0);

         if(hedge_success)
           {
            //--- CRITICAL: Mark this position as hedged
            MarkPositionAsHedged(position_id);
            last_hedge_time = TimeCurrent();
            Print("SUCCESS: Position #", position_id, " hedged with ", DoubleToString(hedge_lot, 2), " lots");
           }
         else
           {
            Print("FAILED: Could not hedge position #", position_id);
           }
        }
     }
  }
//+------------------------------------------------------------------+
//| Check if position was already hedged                            |
//+------------------------------------------------------------------+
bool IsPositionAlreadyHedged(long position_id)
  {
   for(int i = 0; i < ArraySize(hedged_positions); i++)
     {
      if(hedged_positions[i] == position_id)
         return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
//| Mark position as hedged                                         |
//+------------------------------------------------------------------+
void MarkPositionAsHedged(long position_id)
  {
   int size = ArraySize(hedged_positions);
   ArrayResize(hedged_positions, size + 1);
   hedged_positions[size] = position_id;
  }
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(const string symbol,const ulong magic,double &freeze_level,double &stop_level)
  {
   if(!m_symbol.Name(symbol))
      return false;

   if(!m_symbol.RefreshRates())
      return false;

   freeze_level = m_symbol.FreezeLevel() * m_symbol.Point();
   stop_level = m_symbol.StopsLevel() * m_symbol.Point();

   return (m_symbol.Ask() > 0 && m_symbol.Bid() > 0);
  }
//+------------------------------------------------------------------+
//| Lot Check                                                        |
//+------------------------------------------------------------------+
double LotCheck(double lots)
  {
   double volume = NormalizeDouble(lots, 2);
   double step_vol = m_symbol.LotsStep();

   if(step_vol > 0.0)
      volume = step_vol * MathFloor(volume / step_vol);

   if(volume < m_symbol.LotsMin())
      return 0.0;

   if(volume > m_symbol.LotsMax())
      volume = m_symbol.LotsMax();

   return volume;
  }
//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
bool OpenBuy(const double lot,double sl,double tp)
  {
   ulong hedge_magic = (InpHedgeMagicNumber != 0) ? InpHedgeMagicNumber : InpMagicNumber;
   if(hedge_magic != 0)
      m_trade.SetExpertMagicNumber(hedge_magic);

   sl = m_symbol.NormalizePrice(sl);
   tp = m_symbol.NormalizePrice(tp);

//--- Margin check
   double margin_required = m_account.MarginCheck(_Symbol, ORDER_TYPE_BUY, lot, m_symbol.Ask());
   double free_margin = m_account.FreeMargin();

   if(margin_required > free_margin * 0.8) // 80% safety margin
     {
      Print("Margin check failed: Required ", DoubleToString(margin_required, 2), ", Free: ", DoubleToString(free_margin, 2));
      return false;
     }

   return m_trade.Buy(lot, _Symbol, m_symbol.Ask(), sl, tp, "Hedge");
  }
//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
bool OpenSell(const double lot,double sl,double tp)
  {
   ulong hedge_magic = (InpHedgeMagicNumber != 0) ? InpHedgeMagicNumber : InpMagicNumber;
   if(hedge_magic != 0)
      m_trade.SetExpertMagicNumber(hedge_magic);

   sl = m_symbol.NormalizePrice(sl);
   tp = m_symbol.NormalizePrice(tp);

//--- Margin check
   double margin_required = m_account.MarginCheck(_Symbol, ORDER_TYPE_SELL, lot, m_symbol.Bid());
   double free_margin = m_account.FreeMargin();

   if(margin_required > free_margin * 0.8) // 80% safety margin
     {
      Print("Margin check failed: Required ", DoubleToString(margin_required, 2), ", Free: ", DoubleToString(free_margin, 2));
      return false;
     }

   return m_trade.Sell(lot, _Symbol, m_symbol.Bid(), sl, tp, "Hedge");
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| *** WARNING: This EA is designed for demo accounts and testing   |
//| purposes only. There is no stop loss or take profit. Do NOT use  |
//| this EA for live trading. ***                                    |                  |
//|                                                                  |
//| *** ADDITIONAL WARNING: Any use of this EA, including in demo    |
//| accounts or testing environments, is at your own risk. The       |
//| developer and distributor are not liable for any losses or issues|
//| arising from its use. ***                                        |    
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| MIT License                                                      |
//+------------------------------------------------------------------+
/* Copyright (c) 2025 Lupus Materia Ltd
   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED to the WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH the SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
*/
//+------------------------------------------------------------------+