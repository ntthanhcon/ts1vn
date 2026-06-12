//+------------------------------------------------------------------+
//|                                              SignalEngine.mqh    |
//|                           Signal Engine - Trend & Momentum       |
//+------------------------------------------------------------------+
#property copyright "Sector51 Core"
#property link      "https://www.sector51.com"
#property version   "1.01"
#property strict

//+------------------------------------------------------------------+
//| Signal Engine Configuration                                       |
//+------------------------------------------------------------------+
struct SSignalEngineConfig
{
   int                ema_fast_period;        // EMA Fast (default 50)
   int                ema_slow_period;        // EMA Slow (default 200)
   int                rsi_period;             // RSI Period (default 14)
   int                rsi_oversold;           // RSI Oversold (default 30)
   int                rsi_overbought;         // RSI Overbought (default 70)
   int                atr_period;             // ATR Period (default 14)
   double             min_confidence_score;   // Min confidence to trade (0-100)
   
   SSignalEngineConfig()
   {
      ema_fast_period = 50;
      ema_slow_period = 200;
      rsi_period = 14;
      rsi_oversold = 30;
      rsi_overbought = 70;
      atr_period = 14;
      min_confidence_score = 60.0;
   }
};

//+------------------------------------------------------------------+
//| Signal Result Struct                                              |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY = 1,
   SIGNAL_SELL = 2
};

struct SSignalResult
{
   ENUM_SIGNAL        signal;
   double             confidence_score;       // 0-100
   double             atr_value;
   double             ema_fast;
   double             ema_slow;
   double             rsi_value;
   
   SSignalResult()
   {
      signal = SIGNAL_NONE;
      confidence_score = 0.0;
      atr_value = 0.0;
      ema_fast = 0.0;
      ema_slow = 0.0;
      rsi_value = 50.0;
   }
};

//+------------------------------------------------------------------+
//| Signal Engine Class                                               |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   SSignalEngineConfig m_config;
   string              m_symbol;
   ENUM_TIMEFRAMES     m_timeframe;
   
   // Indicators handles
   int                 m_handle_ema_fast;
   int                 m_handle_ema_slow;
   int                 m_handle_rsi;
   int                 m_handle_atr;
   
public:
                     CSignalEngine();
                    ~CSignalEngine();
   
   bool              Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const SSignalEngineConfig &config);
   void              Deinit();
   bool              Update(SSignalResult &result);
   
   double            CalculateConfidenceScore(bool is_trend_up, double rsi, double atr);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CSignalEngine::CSignalEngine()
   : m_handle_ema_fast(INVALID_HANDLE),
     m_handle_ema_slow(INVALID_HANDLE),
     m_handle_rsi(INVALID_HANDLE),
     m_handle_atr(INVALID_HANDLE)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CSignalEngine::~CSignalEngine()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Signal Engine                                          |
//+------------------------------------------------------------------+
bool CSignalEngine::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, const SSignalEngineConfig &config)
{
   m_symbol = symbol;
   m_timeframe = timeframe;
   m_config = config;
   
   // Create EMA Fast
   m_handle_ema_fast = iMA(m_symbol, m_timeframe, m_config.ema_fast_period, 0, MODE_EMA, PRICE_CLOSE);
   if(m_handle_ema_fast == INVALID_HANDLE) return false;
   
   // Create EMA Slow
   m_handle_ema_slow = iMA(m_symbol, m_timeframe, m_config.ema_slow_period, 0, MODE_EMA, PRICE_CLOSE);
   if(m_handle_ema_slow == INVALID_HANDLE) return false;
   
   // Create RSI
   m_handle_rsi = iRSI(m_symbol, m_timeframe, m_config.rsi_period, PRICE_CLOSE);
   if(m_handle_rsi == INVALID_HANDLE) return false;
   
   // Create ATR
   m_handle_atr = iATR(m_symbol, m_timeframe, m_config.atr_period);
   if(m_handle_atr == INVALID_HANDLE) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Signal Engine                                        |
//+------------------------------------------------------------------+
void CSignalEngine::Deinit()
{
   if(m_handle_ema_fast != INVALID_HANDLE) IndicatorRelease(m_handle_ema_fast);
   if(m_handle_ema_slow != INVALID_HANDLE) IndicatorRelease(m_handle_ema_slow);
   if(m_handle_rsi != INVALID_HANDLE) IndicatorRelease(m_handle_rsi);
   if(m_handle_atr != INVALID_HANDLE) IndicatorRelease(m_handle_atr);
   
   m_handle_ema_fast = INVALID_HANDLE;
   m_handle_ema_slow = INVALID_HANDLE;
   m_handle_rsi = INVALID_HANDLE;
   m_handle_atr = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Calculate Confidence Score                                        |
//+------------------------------------------------------------------+
double CSignalEngine::CalculateConfidenceScore(bool is_trend_up, double rsi, double atr)
{
   double score = 0.0;
   
   // Trend weight (50%)
   score += 50.0;
   
   // RSI weight (30%)
   if(is_trend_up)
   {
      if(rsi > m_config.rsi_oversold && rsi < 50) score += 30.0;
      else if(rsi >= 50 && rsi < m_config.rsi_overbought) score += 20.0;
      else score += 5.0;
   }
   else
   {
      if(rsi < m_config.rsi_overbought && rsi > 50) score += 30.0;
      else if(rsi <= 50 && rsi > m_config.rsi_oversold) score += 20.0;
      else score += 5.0;
   }
   
   // ATR volatility (20%) - give full score if ATR is valid
   if(atr > 0) score += 20.0;
   
   return NormalizeDouble(score, 1);
}

//+------------------------------------------------------------------+
//| Update Signal Engine                                              |
//+------------------------------------------------------------------+
bool CSignalEngine::Update(SSignalResult &result)
{
   result = SSignalResult();
   
   double ema_fast_arr[], ema_slow_arr[], rsi_arr[], atr_arr[];
   
   // Copy buffers - need 3 bars for crossover check
   int copied_fast = CopyBuffer(m_handle_ema_fast, 0, 0, 3, ema_fast_arr);
   int copied_slow = CopyBuffer(m_handle_ema_slow, 0, 0, 3, ema_slow_arr);
   int copied_rsi = CopyBuffer(m_handle_rsi, 0, 0, 2, rsi_arr);
   int copied_atr = CopyBuffer(m_handle_atr, 0, 0, 2, atr_arr);
   
   if(copied_fast < 3 || copied_slow < 3 || copied_rsi < 2 || copied_atr < 1) 
      return false;
   
   result.ema_fast = ema_fast_arr[0];
   result.ema_slow = ema_slow_arr[0];
   result.rsi_value = rsi_arr[0];
   result.atr_value = atr_arr[0];
   
   // Check for EMA crossover/crossunder using previous bar values
   bool prev_trend_up = (ema_fast_arr[1] > ema_slow_arr[1]);
   bool curr_trend_up = (result.ema_fast > result.ema_slow);
   bool prev_prev_trend_up = (ema_fast_arr[2] > ema_slow_arr[2]);
   
   // Generate signal only on valid crossover/crossunder
   bool bullish_crossover = !prev_prev_trend_up && prev_trend_up && curr_trend_up;
   bool bearish_crossunder = prev_prev_trend_up && !prev_trend_up && !curr_trend_up;
   
   if(bullish_crossover && result.rsi_value > m_config.rsi_oversold && result.rsi_value < m_config.rsi_overbought)
   {
      result.signal = SIGNAL_BUY;
      result.confidence_score = CalculateConfidenceScore(true, result.rsi_value, result.atr_value);
   }
   else if(bearish_crossunder && result.rsi_value < m_config.rsi_overbought && result.rsi_value > m_config.rsi_oversold)
   {
      result.signal = SIGNAL_SELL;
      result.confidence_score = CalculateConfidenceScore(false, result.rsi_value, result.atr_value);
   }
   else
   {
      result.signal = SIGNAL_NONE;
      result.confidence_score = 0.0;
   }
   
   return true;
}
//+------------------------------------------------------------------+
