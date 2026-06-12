//+------------------------------------------------------------------+
//|                                          ExecutionEngine.mqh     |
//|                     Execution Engine - Spread & Slippage Check   |
//+------------------------------------------------------------------+
#property copyright "Sector51 Core"
#property link      "https://www.sector51.com"
#property version   "1.02"
#property strict

#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Execution Engine Configuration                                    |
//+------------------------------------------------------------------+
struct SExecutionEngineConfig
{
   double             max_spread_pips;         // Max allowed spread in pips (default)
   double             symbol_spread_xauusd;    // XAUUSD specific spread limit
   double             symbol_spread_eurusd;    // EURUSD specific spread limit
   double             symbol_spread_xagusd;    // XAGUSD specific spread limit
   bool               enable_spread_check;     // Enable spread filter
   
   SExecutionEngineConfig()
   {
      max_spread_pips = 1000.0; // Tăng default lên cao để test
      symbol_spread_xauusd = 500.0;
      symbol_spread_eurusd = 50.0;
      symbol_spread_xagusd = 300.0;
      enable_spread_check = true;
   }
};

//+------------------------------------------------------------------+
//| Execution Result Struct                                           |
//+------------------------------------------------------------------+
struct SExecutionResult
{
   bool               can_execute;
   double             current_spread_pips;
   double             avg_spread_pips;
   double             estimated_slippage_pips;
   double             estimated_execution_cost;
   double             score_adjustment;
   
   SExecutionResult()
   {
      can_execute = true;
      current_spread_pips = 0.0;
      avg_spread_pips = 0.0;
      estimated_slippage_pips = 0.0;
      estimated_execution_cost = 0.0;
      score_adjustment = 0.0;
   }
};

//+------------------------------------------------------------------+
//| Execution Engine Class                                            |
//+------------------------------------------------------------------+
class CExecutionEngine
{
private:
   SExecutionEngineConfig m_config;
   string              m_symbol;
   CSymbolInfo         m_symbol_info;
   double              m_spread_history[];     // Track spread history
   int                 m_spread_history_count;
   
public:
                     CExecutionEngine();
                    ~CExecutionEngine();
   
   bool              Init(const string symbol, const SExecutionEngineConfig &config);
   void              Deinit();
   bool              Update(SExecutionResult &result);
   double            GetSymbolSpreadLimit();
   double            PriceToPips(double price);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CExecutionEngine::CExecutionEngine() : m_spread_history_count(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CExecutionEngine::~CExecutionEngine()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Execution Engine                                       |
//+------------------------------------------------------------------+
bool CExecutionEngine::Init(const string symbol, const SExecutionEngineConfig &config)
{
   m_symbol = symbol;
   m_config = config;
   
   if(!m_symbol_info.Name(m_symbol))
      return false;
      
   ArrayResize(m_spread_history, 100); // Store last 100 spreads
   m_spread_history_count = 0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Execution Engine                                     |
//+------------------------------------------------------------------+
void CExecutionEngine::Deinit()
{
   ArrayFree(m_spread_history);
   m_spread_history_count = 0;
}

//+------------------------------------------------------------------+
//| Convert price difference to pips                                  |
//+------------------------------------------------------------------+
double CExecutionEngine::PriceToPips(double price)
{
   double point = m_symbol_info.Point();
   int digits = m_symbol_info.Digits();
   double point_adjust = (digits == 3 || digits == 5) ? 10 : 1;
   return price / (point * point_adjust);
}

//+------------------------------------------------------------------+
//| Get symbol-specific spread limit                                  |
//+------------------------------------------------------------------+
double CExecutionEngine::GetSymbolSpreadLimit()
{
   if(m_symbol == "XAUUSD") return m_config.symbol_spread_xauusd;
   if(m_symbol == "EURUSD") return m_config.symbol_spread_eurusd;
   if(m_symbol == "XAGUSD") return m_config.symbol_spread_xagusd;
   return m_config.max_spread_pips;
}

//+------------------------------------------------------------------+
//| Update Execution Engine                                           |
//+------------------------------------------------------------------+
bool CExecutionEngine::Update(SExecutionResult &result)
{
   result = SExecutionResult();
   
   if(!m_symbol_info.RefreshRates())
      return false;
   
   // Calculate current spread in pips
   double spread_price = m_symbol_info.Ask() - m_symbol_info.Bid();
   result.current_spread_pips = PriceToPips(spread_price);
   
   // Add to history
   if(m_spread_history_count < 100)
      m_spread_history[m_spread_history_count++] = result.current_spread_pips;
   else
   {
      for(int i = 1; i < 100; i++)
         m_spread_history[i-1] = m_spread_history[i];
      m_spread_history[99] = result.current_spread_pips;
   }
   
   // Calculate average spread
   if(m_spread_history_count > 0)
   {
      double sum = 0;
      for(int i = 0; i < m_spread_history_count; i++)
         sum += m_spread_history[i];
      result.avg_spread_pips = sum / m_spread_history_count;
   }
   
   // Estimate slippage (simple: 10-50% of average spread)
   result.estimated_slippage_pips = result.avg_spread_pips * 0.3;
   
   // Estimate execution cost
   result.estimated_execution_cost = result.current_spread_pips + result.estimated_slippage_pips;
   
   // Check spread limit
   if(m_config.enable_spread_check)
   {
      double limit = GetSymbolSpreadLimit();
      if(result.current_spread_pips > limit)
      {
         result.can_execute = false;
         result.score_adjustment = -50.0;
      }
      else
      {
         // Adjust score based on spread quality
         double ratio = result.current_spread_pips / limit;
         if(ratio < 0.3) result.score_adjustment = 10.0;
         else if(ratio < 0.6) result.score_adjustment = 5.0;
         else if(ratio < 0.9) result.score_adjustment = 0.0;
         else result.score_adjustment = -10.0;
      }
   }
   else
   {
      result.can_execute = true;
      result.score_adjustment = 0.0;
   }
   
   return true;
}
//+------------------------------------------------------------------+
