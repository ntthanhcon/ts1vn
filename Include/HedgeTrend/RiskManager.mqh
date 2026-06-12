//+------------------------------------------------------------------+
//|                                             RiskManager.mqh      |
//|                    Risk Manager - Lot Sizing & Limits            |
//+------------------------------------------------------------------+
#property copyright "Sector51 Core"
#property link      "https://www.sector51.com"
#property version   "1.00"
#property strict

#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Risk Manager Configuration                                       |
//+------------------------------------------------------------------+
struct SRiskManagerConfig
{
   double             risk_percent;            // Risk % per trade (0-10)
   double             sl_atr_multiplier;       // SL = ATR * multiplier
   double             tp_atr_multiplier;       // TP = ATR * multiplier
   double             daily_loss_limit;        // Max daily loss (%)
   double             daily_profit_target;     // Daily profit target (%)
   int                max_positions_per_symbol;// Max open positions per symbol
   double             max_exposure_percent;    // Max total exposure (%)
   double             fixed_lot;               // Fixed lot (if not using % risk)
   bool               use_percent_risk;        // True = % risk, False = fixed lot
   
   SRiskManagerConfig()
   {
      risk_percent = 1.0;
      sl_atr_multiplier = 1.5;
      tp_atr_multiplier = 3.0;
      daily_loss_limit = 5.0;
      daily_profit_target = 10.0;
      max_positions_per_symbol = 3;
      max_exposure_percent = 30.0;
      fixed_lot = 0.1;
      use_percent_risk = true;
   }
};

//+------------------------------------------------------------------+
//| Risk Manager Result Struct                                       |
//+------------------------------------------------------------------+
struct SRiskManagerResult
{
   bool               can_trade;
   double             lot_size;
   double             stop_loss;
   double             take_profit;
   double             current_daily_pnl_percent;
   double             current_exposure_percent;
   
   SRiskManagerResult()
   {
      can_trade = true;
      lot_size = 0.0;
      stop_loss = 0.0;
      take_profit = 0.0;
      current_daily_pnl_percent = 0.0;
      current_exposure_percent = 0.0;
   }
};

//+------------------------------------------------------------------+
//| Risk Manager Class                                               |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   SRiskManagerConfig  m_config;
   string              m_symbol;
   CSymbolInfo         m_symbol_info;
   CAccountInfo        m_account_info;
   double              m_start_balance;
   datetime            m_last_reset_day;
   
public:
                     CRiskManager();
                    ~CRiskManager();
   
   bool              Init(const string symbol, const SRiskManagerConfig &config);
   void              Deinit();
   bool              Update(double atr, SRiskManagerResult &result);
   double            CalculateLotSize(double sl_distance);
   double            CalculateCurrentExposure();
   double            CalculateDailyPnLPercent();
   void              CheckAndResetDaily();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager() : m_start_balance(0), m_last_reset_day(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Risk Manager                                          |
//+------------------------------------------------------------------+
bool CRiskManager::Init(const string symbol, const SRiskManagerConfig &config)
{
   m_symbol = symbol;
   m_config = config;
   
   if(!m_symbol_info.Name(m_symbol))
      return false;
      
   m_start_balance = m_account_info.Balance();
   MqlDateTime time_struct;
   TimeToStruct(TimeCurrent(), time_struct);
   m_last_reset_day = StructToTime(time_struct) - (time_struct.hour * 3600 + time_struct.min * 60 + time_struct.sec);
   
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Risk Manager                                        |
//+------------------------------------------------------------------+
void CRiskManager::Deinit()
{
}

//+------------------------------------------------------------------+
//| Check and reset daily tracking if new day                        |
//+------------------------------------------------------------------+
void CRiskManager::CheckAndResetDaily()
{
   MqlDateTime time_struct;
   TimeToStruct(TimeCurrent(), time_struct);
   datetime current_day_start = StructToTime(time_struct) - (time_struct.hour * 3600 + time_struct.min * 60 + time_struct.sec);
   
   if(current_day_start > m_last_reset_day)
   {
      m_start_balance = m_account_info.Balance();
      m_last_reset_day = current_day_start;
   }
}

//+------------------------------------------------------------------+
//| Calculate current exposure percentage                            |
//+------------------------------------------------------------------+
double CRiskManager::CalculateCurrentExposure()
{
   double total_margin_used = m_account_info.Margin();
   double balance = m_account_info.Balance();
   if(balance <= 0) return 0.0;
   return (total_margin_used / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Calculate daily P&L percentage                                   |
//+------------------------------------------------------------------+
double CRiskManager::CalculateDailyPnLPercent()
{
   double equity = m_account_info.Equity();
   if(m_start_balance <= 0) return 0.0;
   return ((equity - m_start_balance) / m_start_balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk %                               |
//+------------------------------------------------------------------+
double CRiskManager::CalculateLotSize(double sl_distance)
{
   if(!m_config.use_percent_risk)
      return m_config.fixed_lot;
      
   if(sl_distance <= 0) return 0.0;
   
   double balance = m_account_info.Balance();
   double risk_amount = balance * (m_config.risk_percent / 100.0);
   
   double tick_value = m_symbol_info.TradeTickValue();
   double tick_size = m_symbol_info.TradeTickSize();
   if(tick_size <= 0 || tick_value <= 0) return 0.0;
   
   double value_per_lot = (sl_distance / tick_size) * tick_value;
   if(value_per_lot <= 0) return 0.0;
   
   double lot = risk_amount / value_per_lot;
   
   // Normalize lot
   double step = m_symbol_info.LotsStep();
   lot = step * MathFloor(lot / step);
   
   // Check min/max
   double min_lot = m_symbol_info.LotsMin();
   double max_lot = m_symbol_info.LotsMax();
   
   if(lot < min_lot) lot = 0.0;
   if(lot > max_lot) lot = max_lot;
   
   return NormalizeDouble(lot, (int)MathMax(0, -MathLog10(step)));
}

//+------------------------------------------------------------------+
//| Update Risk Manager                                              |
//+------------------------------------------------------------------+
bool CRiskManager::Update(double atr, SRiskManagerResult &result)
{
   result = SRiskManagerResult();
   
   CheckAndResetDaily();
   
   result.current_daily_pnl_percent = CalculateDailyPnLPercent();
   result.current_exposure_percent = CalculateCurrentExposure();
   
   // Check daily limits
   if(result.current_daily_pnl_percent <= -m_config.daily_loss_limit)
   {
      result.can_trade = false;
      return true;
   }
   if(result.current_daily_pnl_percent >= m_config.daily_profit_target)
   {
      result.can_trade = false;
      return true;
   }
   
   // Check max exposure
   if(result.current_exposure_percent >= m_config.max_exposure_percent)
   {
      result.can_trade = false;
      return true;
   }
   
   // Calculate SL and TP distances (not final SL/TP prices)
   double sl_distance = atr * m_config.sl_atr_multiplier;
   double tp_distance = atr * m_config.tp_atr_multiplier;
   
   // Calculate lot size
   result.lot_size = CalculateLotSize(sl_distance);
   
   return true;
}
//+------------------------------------------------------------------+

