//+------------------------------------------------------------------+
//|                                              HedgeTrendEA.mq5    |
//|                     Hedge Trending EA - Complete System          |
//+------------------------------------------------------------------+
#property copyright "Sector51 Core"
#property link      "https://www.sector51.com"
#property version   "1.02"
#property strict
#property description "Hedge Trending EA - Modular System with Signal, Execution, Risk, Position & Hedge Engines"

// Include all modules
#include <HedgeTrend/SignalEngine.mqh>
#include <HedgeTrend/ExecutionEngine.mqh>
#include <HedgeTrend/RiskManager.mqh>
#include <HedgeTrend/PositionManager.mqh>
#include <HedgeTrend/HedgeEngine.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// --- General Settings
input ENUM_TIMEFRAMES  InpTimeframe           = PERIOD_H1;     // Trading Timeframe
input ulong            InpMagicNumber         = 51000;         // EA Magic Number

// --- Signal Engine Settings
input group "=== Signal Engine ==="
input int              InpEmaFastPeriod       = 10;            // EMA Fast Period (very fast!)
input int              InpEmaSlowPeriod       = 20;            // EMA Slow Period (very fast!)
input int              InpRsiPeriod           = 14;            // RSI Period
input int              InpRsiOversold         = 40;            // RSI Oversold
input int              InpRsiOverbought       = 60;            // RSI Overbought
input int              InpAtrPeriod           = 14;            // ATR Period
input double           InpMinConfidence       = 0.0;           // Min Confidence Score (0-100, 0 = no filter)

// --- Execution Engine Settings
input group "=== Execution Engine ==="
input bool             InpEnableSpreadCheck   = false;         // Disable Spread Check temporarily for more trades
input double           InpMaxSpreadXAUUSD     = 99999.0;       // Max Spread XAUUSD (pips, huge limit)
input double           InpMaxSpreadEURUSD     = 99999.0;       // Max Spread EURUSD (pips, huge limit)
input double           InpMaxSpreadXAGUSD     = 99999.0;       // Max Spread XAGUSD (pips, huge limit)
input double           InpMaxSpreadDefault    = 99999.0;       // Max Spread Other Symbols (pips, huge limit)

// --- Risk Manager Settings
input group "=== Risk Manager ==="
input bool             InpUsePercentRisk      = false;         // Use Fixed Lot for testing first
input double           InpRiskPercent         = 1.0;           // Risk % per Trade
input double           InpFixedLot            = 0.01;          // Fixed Lot Size (smaller for XAUUSD)
input bool             InpUseFixedPipSLTP     = true;          // Use Fixed Pips for SL/TP instead of ATR
input double           InpFixedSLPips         = 500.0;         // Fixed SL (pips) for XAUUSD
input double           InpFixedTPPips         = 1000.0;        // Fixed TP (pips) for XAUUSD
input double           InpSlAtrMultiplier     = 1.5;           // SL = ATR * Multiplier (if not using fixed)
input double           InpTpAtrMultiplier     = 3.0;           // TP = ATR * Multiplier (if not using fixed)
input double           InpDailyLossLimit      = 50.0;          // Daily Loss Limit (%) (very high for testing)
input double           InpDailyProfitTarget   = 100.0;         // Daily Profit Target (%) (very high for testing)
input int              InpMaxPositionsPerSym  = 5;             // Max Positions per Symbol (5 for more trades)
input double           InpMaxExposurePercent  = 90.0;          // Max Exposure (%) (very high for testing)

// --- Position Manager Settings
input group "=== Position Manager ==="
input bool             InpEnableScaleIn       = true;          // Enable Scale In
input double           InpScaleInRR           = 1.0;           // Scale In at X RR
input double           InpScaleInLotMult      = 0.5;           // Scale In Lot Multiplier
input bool             InpEnablePartialClose  = true;          // Enable Partial Close
input double           InpPartialCloseRR      = 1.0;           // Partial Close at X RR
input double           InpPartialClosePercent = 50.0;          // Partial Close %
input bool             InpEnableTrailingStop  = true;          // Enable Trailing Stop
input double           InpTrailingStartRR     = 1.5;           // Start Trailing at X RR
input double           InpTrailingAtrMult     = 0.8;           // Trailing Distance (ATR * X)

// --- Hedge Engine Settings
input group "=== Hedge Engine ==="
input bool             InpEnableHedging       = true;          // Enable Hedging
input ulong            InpHedgeMagicNumber    = 99999;         // Hedge Magic Number
input double           InpHedgeLossThreshold  = 50.0;          // Hedge Loss Threshold (pips)
input double           InpHedgeLotCoefficient = 1.5;           // Hedge Lot Multiplier
input int              InpHedgeMaxCount       = 3;             // Max Hedges
input int              InpHedgeCooldownMin    = 5;             // Cooldown (minutes)

// --- Misc Settings
input group "=== Misc ==="
input bool             InpDebugMode           = false;         // Enable Debug Logs

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CSignalEngine        g_signal_engine;
CExecutionEngine     g_execution_engine;
CRiskManager         g_risk_manager;
CPositionManager     g_position_manager;
CHedgeEngine         g_hedge_engine;
CTrade               g_trade;
CSymbolInfo          g_symbol_info;
datetime             g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Get Symbol-Specific Spread Limit                                  |
//+------------------------------------------------------------------+
double GetSymbolSpreadLimit()
{
   if(_Symbol == "XAUUSD") return InpMaxSpreadXAUUSD;
   if(_Symbol == "EURUSD") return InpMaxSpreadEURUSD;
   if(_Symbol == "XAGUSD") return InpMaxSpreadXAGUSD;
   return InpMaxSpreadDefault;
}

//+------------------------------------------------------------------+
//| Expert Initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize symbol info
   if(!g_symbol_info.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
   }
   
   // Initialize Signal Engine
   SSignalEngineConfig signal_cfg;
   signal_cfg.ema_fast_period = InpEmaFastPeriod;
   signal_cfg.ema_slow_period = InpEmaSlowPeriod;
   signal_cfg.rsi_period = InpRsiPeriod;
   signal_cfg.rsi_oversold = InpRsiOversold;
   signal_cfg.rsi_overbought = InpRsiOverbought;
   signal_cfg.atr_period = InpAtrPeriod;
   signal_cfg.min_confidence_score = InpMinConfidence;
   
   if(!g_signal_engine.Init(_Symbol, InpTimeframe, signal_cfg))
   {
      Print("Failed to initialize Signal Engine");
      return INIT_FAILED;
   }
   
   // Initialize Execution Engine
   SExecutionEngineConfig exec_cfg;
   exec_cfg.enable_spread_check = InpEnableSpreadCheck;
   exec_cfg.symbol_spread_xauusd = InpMaxSpreadXAUUSD;
   exec_cfg.symbol_spread_eurusd = InpMaxSpreadEURUSD;
   exec_cfg.symbol_spread_xagusd = InpMaxSpreadXAGUSD;
   exec_cfg.max_spread_pips = InpMaxSpreadDefault;
   
   if(!g_execution_engine.Init(_Symbol, exec_cfg))
   {
      Print("Failed to initialize Execution Engine");
      return INIT_FAILED;
   }
   
   // Initialize Risk Manager
   SRiskManagerConfig risk_cfg;
   risk_cfg.use_percent_risk = InpUsePercentRisk;
   risk_cfg.risk_percent = InpRiskPercent;
   risk_cfg.fixed_lot = InpFixedLot;
   risk_cfg.sl_atr_multiplier = InpSlAtrMultiplier;
   risk_cfg.tp_atr_multiplier = InpTpAtrMultiplier;
   risk_cfg.daily_loss_limit = InpDailyLossLimit;
   risk_cfg.daily_profit_target = InpDailyProfitTarget;
   risk_cfg.max_positions_per_symbol = InpMaxPositionsPerSym;
   risk_cfg.max_exposure_percent = InpMaxExposurePercent;
   
   if(!g_risk_manager.Init(_Symbol, risk_cfg))
   {
      Print("Failed to initialize Risk Manager");
      return INIT_FAILED;
   }
   
   // Initialize Position Manager
   SPositionManagerConfig pos_cfg;
   pos_cfg.enable_scale_in = InpEnableScaleIn;
   pos_cfg.scale_in_profit_rr = InpScaleInRR;
   pos_cfg.scale_in_lot_multiplier = InpScaleInLotMult;
   pos_cfg.enable_partial_close = InpEnablePartialClose;
   pos_cfg.partial_close_rr = InpPartialCloseRR;
   pos_cfg.partial_close_percent = InpPartialClosePercent;
   pos_cfg.enable_trailing_stop = InpEnableTrailingStop;
   pos_cfg.trailing_start_rr = InpTrailingStartRR;
   pos_cfg.trailing_atr_multiplier = InpTrailingAtrMult;
   
   if(!g_position_manager.Init(_Symbol, pos_cfg, InpMagicNumber))
   {
      Print("Failed to initialize Position Manager");
      return INIT_FAILED;
   }
   
   // Initialize Hedge Engine
   SHedgeEngineConfig hedge_cfg;
   hedge_cfg.enable_hedging = InpEnableHedging;
   hedge_cfg.main_magic_number = InpMagicNumber;
   hedge_cfg.hedge_magic_number = InpHedgeMagicNumber;
   hedge_cfg.loss_threshold_pips = InpHedgeLossThreshold;
   hedge_cfg.lot_coefficient = InpHedgeLotCoefficient;
   hedge_cfg.max_hedges = InpHedgeMaxCount;
   hedge_cfg.cooldown_minutes = InpHedgeCooldownMin;
   
   if(!g_hedge_engine.Init(_Symbol, hedge_cfg))
   {
      Print("Failed to initialize Hedge Engine");
      return INIT_FAILED;
   }
   
   // Setup trade object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   Print("HedgeTrend EA v1.02 initialized successfully!");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(InpTimeframe));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_signal_engine.Deinit();
   g_execution_engine.Deinit();
   g_risk_manager.Deinit();
   g_position_manager.Deinit();
   g_hedge_engine.Deinit();
   
   Print("HedgeTrend EA deinitialized (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| Check for new bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current_bar_time = iTime(_Symbol, InpTimeframe, 0);
   if(current_bar_time != g_last_bar_time)
   {
      g_last_bar_time = current_bar_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if market is closed                                         |
//+------------------------------------------------------------------+
bool IsMarketClosed()
{
   MqlDateTime time_struct;
   TimeToStruct(TimeCurrent(), time_struct);
   int day_of_week = time_struct.day_of_week;
   
   // Check for weekend (Saturday=6, Sunday=0)
   if(day_of_week == 0 || day_of_week == 6)
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
//| Properly round price to symbol's digits                           |
//+------------------------------------------------------------------+
double RoundToDigits(double price)
{
   int digits = g_symbol_info.Digits();
   double point = g_symbol_info.Point();
   double p = MathPow(10, digits);
   return MathRound(price * p) / p;
}

//+------------------------------------------------------------------+
//| Adjust SL and TP to meet broker requirements (with big buffer)     |
//+------------------------------------------------------------------+
void AdjustSLTP(double &sl, double &tp, double entry, ENUM_SIGNAL signal)
{
   if(sl == 0 && tp == 0)
      return;
      
   double point = g_symbol_info.Point();
   double stops_level = g_symbol_info.StopsLevel();
   double freeze_level = g_symbol_info.FreezeLevel();
   // Add extra buffer of 100 points to be absolutely safe
   double min_distance = (stops_level + freeze_level + 100) * point;
   
   if(signal == SIGNAL_BUY)
   {
      if(sl != 0)
         sl = RoundToDigits(entry - min_distance - (20 * point));
      if(tp != 0)
         tp = RoundToDigits(entry + min_distance + (20 * point));
   }
   else if(signal == SIGNAL_SELL)
   {
      if(sl != 0)
         sl = RoundToDigits(entry + min_distance + (20 * point));
      if(tp != 0)
         tp = RoundToDigits(entry - min_distance - (20 * point));
   }
}

//+------------------------------------------------------------------+
//| Validate SL and TP prices                                         |
//+------------------------------------------------------------------+
bool ValidateSLTP(double entry, double sl, double tp, ENUM_SIGNAL signal)
{
   if(sl == 0 && tp == 0)
      return true;
      
   double point = g_symbol_info.Point();
   double stops_level = g_symbol_info.StopsLevel();
   double freeze_level = g_symbol_info.FreezeLevel();
   double min_distance = (stops_level + freeze_level) * point;
   
   if(signal == SIGNAL_BUY)
   {
      if(sl != 0 && sl >= entry - min_distance)
         return false;
      if(tp != 0 && tp <= entry + min_distance)
         return false;
   }
   else if(signal == SIGNAL_SELL)
   {
      if(sl != 0 && sl <= entry + min_distance)
         return false;
      if(tp != 0 && tp >= entry - min_distance)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                     |
//+------------------------------------------------------------------+
bool ExecuteTrade(ENUM_SIGNAL signal, double lot, double sl, double tp)
{
   if(signal == SIGNAL_BUY)
   {
      if(g_trade.Buy(lot, _Symbol, sl, tp))
      {
         Print("BUY executed: Ticket=", g_trade.ResultOrder(), " Lot=", lot, " SL=", sl, " TP=", tp);
         return true;
      }
      else
      {
         Print("BUY failed: Error=", GetLastError(), " Retcode=", g_trade.ResultRetcode(), " Desc=", g_trade.ResultRetcodeDescription());
         return false;
      }
   }
   else if(signal == SIGNAL_SELL)
   {
      if(g_trade.Sell(lot, _Symbol, sl, tp))
      {
         Print("SELL executed: Ticket=", g_trade.ResultOrder(), " Lot=", lot, " SL=", sl, " TP=", tp);
         return true;
      }
      else
      {
         Print("SELL failed: Error=", GetLastError(), " Retcode=", g_trade.ResultRetcode(), " Desc=", g_trade.ResultRetcodeDescription());
         return false;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check market closed
   if(IsMarketClosed())
      return;
      
   // Refresh symbol info
   if(!g_symbol_info.RefreshRates())
      return;
   
   // Update all engines every tick
   SSignalResult signal_result;
   g_signal_engine.Update(signal_result);
   
   SExecutionResult exec_result;
   g_execution_engine.Update(exec_result);
   
   SRiskManagerResult risk_result;
   g_risk_manager.Update(signal_result.atr_value, risk_result);
   
   // Manage positions every tick
   g_position_manager.ManagePositions(signal_result.atr_value);
   
   // Update hedge engine every tick
   g_hedge_engine.Update();
   
   // Only check for new trades on new bar
   if(!IsNewBar())
      return;
   
   // Debug log
   if(InpDebugMode)
   {
      Print("New bar - Signal=", EnumToString(signal_result.signal), 
            " Confidence=", signal_result.confidence_score,
            " Spread=", exec_result.current_spread_pips, " pips",
            " Spread OK=", exec_result.can_execute,
            " Risk OK=", risk_result.can_trade);
   }
   
   // Check if we have valid signal
   if(signal_result.signal == SIGNAL_NONE)
      return;
      
   // Check confidence score
   double adjusted_confidence = signal_result.confidence_score + exec_result.score_adjustment;
   if(adjusted_confidence < InpMinConfidence)
   {
      if(InpDebugMode) Print("Confidence too low: ", adjusted_confidence, " (min: ", InpMinConfidence, ")");
      return;
   }
   
   // Check execution
   if(!exec_result.can_execute)
   {
      if(InpDebugMode) Print("Execution not allowed: Spread=", exec_result.current_spread_pips, " pips (limit: ", GetSymbolSpreadLimit(), ")");
      return;
   }
   
   // Check risk
   if(!risk_result.can_trade)
   {
      if(InpDebugMode) Print("Risk limits reached: Daily P&L=", risk_result.current_daily_pnl_percent, "%, Exposure=", risk_result.current_exposure_percent, "%");
      return;
   }
   
   // Check max positions per symbol
   int open_positions = g_position_manager.CountOpenPositions();
   if(open_positions >= InpMaxPositionsPerSym)
   {
      if(InpDebugMode) Print("Max positions reached: ", open_positions, "/", InpMaxPositionsPerSym);
      return;
   }
   
   // Calculate SL and TP - DISABLED for testing to avoid "invalid stops"
   double sl = 0.0, tp = 0.0;
   
   // Calculate lot size
   double lot = risk_result.lot_size;
   
   // Double-check lot - ensure it's valid
   double lot_step = g_symbol_info.LotsStep();
   double min_lot = g_symbol_info.LotsMin();
   double max_lot = g_symbol_info.LotsMax();
   
   // Fallback to fixed lot if risk-based lot is invalid
   if(lot <= 0)
      lot = InpFixedLot;
      
   // Normalize and clamp lot size
   lot = MathMax(lot, min_lot);
   lot = MathMin(lot, max_lot);
   lot = lot_step * MathFloor(lot / lot_step);
   lot = NormalizeDouble(lot, (int)MathMax(0, -MathLog10(lot_step)));
      
   if(lot < min_lot)
   {
      if(InpDebugMode) Print("Lot size below minimum: ", lot, " < ", min_lot);
      return;
   }
   
   // Execute trade
   ExecuteTrade(signal_result.signal, lot, sl, tp);
}
//+------------------------------------------------------------------+
