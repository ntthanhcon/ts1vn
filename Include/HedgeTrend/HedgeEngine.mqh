//+------------------------------------------------------------------+
//|                                             HedgeEngine.mqh      |
//|                   Hedge Engine - Based on HedgeCover 1.04        |
//+------------------------------------------------------------------+
#property copyright "Sector51 Core"
#property link      "https://www.sector51.com"
#property version   "1.00"
#property strict

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Hedge Engine Configuration                                       |
//+------------------------------------------------------------------+
struct SHedgeEngineConfig
{
   ulong              main_magic_number;       // Main strategy magic number
   ulong              hedge_magic_number;      // Hedge magic number (MUST be different)
   double             loss_threshold_pips;     // Loss threshold to trigger hedge
   double             lot_coefficient;         // Hedge lot multiplier
   int                max_hedges;              // Max total hedges
   int                cooldown_minutes;        // Cooldown between hedges
   bool               enable_hedging;          // Enable hedging
   
   SHedgeEngineConfig()
   {
      main_magic_number = 0;
      hedge_magic_number = 99999;
      loss_threshold_pips = 50.0;
      lot_coefficient = 1.5;
      max_hedges = 3;
      cooldown_minutes = 5;
      enable_hedging = true;
   }
};

//+------------------------------------------------------------------+
//| Hedge Engine Class                                               |
//+------------------------------------------------------------------+
class CHedgeEngine
{
private:
   SHedgeEngineConfig  m_config;
   string              m_symbol;
   CPositionInfo       m_position_info;
   CTrade              m_trade;
   CSymbolInfo         m_symbol_info;
   CAccountInfo        m_account_info;
   ulong               m_hedged_positions[];
   int                 m_hedged_count;
   datetime            m_last_hedge_time;
   
public:
                     CHedgeEngine();
                    ~CHedgeEngine();
   
   bool              Init(const string symbol, const SHedgeEngineConfig &config);
   void              Deinit();
   void              Update();
   
private:
   int               CountCurrentHedges();
   bool              IsPositionHedged(ulong ticket);
   void              MarkPositionHedged(ulong ticket);
   double            CalculateLossInPips(ulong ticket);
   double            NormalizeLot(double lot);
   bool              OpenHedge(ulong main_ticket, double lot);
   bool              CheckMargin(double lot, bool is_buy);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHedgeEngine::CHedgeEngine() : m_hedged_count(0), m_last_hedge_time(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHedgeEngine::~CHedgeEngine()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Hedge Engine                                          |
//+------------------------------------------------------------------+
bool CHedgeEngine::Init(const string symbol, const SHedgeEngineConfig &config)
{
   m_symbol = symbol;
   m_config = config;
   
   if(!m_symbol_info.Name(m_symbol))
      return false;
      
   m_trade.SetExpertMagicNumber(m_config.hedge_magic_number);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   ArrayResize(m_hedged_positions, 100);
   m_hedged_count = 0;
   m_last_hedge_time = 0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Hedge Engine                                        |
//+------------------------------------------------------------------+
void CHedgeEngine::Deinit()
{
   ArrayFree(m_hedged_positions);
   m_hedged_count = 0;
}

//+------------------------------------------------------------------+
//| Check if position is already hedged                              |
//+------------------------------------------------------------------+
bool CHedgeEngine::IsPositionHedged(ulong ticket)
{
   for(int i = 0; i < m_hedged_count; i++)
   {
      if(m_hedged_positions[i] == ticket)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Mark position as hedged                                          |
//+------------------------------------------------------------------+
void CHedgeEngine::MarkPositionHedged(ulong ticket)
{
   if(IsPositionHedged(ticket))
      return;
      
   if(m_hedged_count < 100)
   {
      m_hedged_positions[m_hedged_count] = ticket;
      m_hedged_count++;
   }
}

//+------------------------------------------------------------------+
//| Calculate loss in pips                                           |
//+------------------------------------------------------------------+
double CHedgeEngine::CalculateLossInPips(ulong ticket)
{
   if(!m_position_info.SelectByTicket(ticket))
      return 0.0;
      
   double point = m_symbol_info.Point();
   int digits = m_symbol_info.Digits();
   double point_adjust = (digits == 3 || digits == 5) ? 10 : 1;
   double open_price = m_position_info.PriceOpen();
   double current_price = m_position_info.PriceCurrent();
   double loss = 0.0;
   
   if(m_position_info.PositionType() == POSITION_TYPE_BUY)
      loss = (open_price - current_price) / (point * point_adjust);
   else
      loss = (current_price - open_price) / (point * point_adjust);
      
   return loss;
}

//+------------------------------------------------------------------+
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double CHedgeEngine::NormalizeLot(double lot)
{
   double step = m_symbol_info.LotsStep();
   lot = step * MathFloor(lot / step);
   
   double min_lot = m_symbol_info.LotsMin();
   double max_lot = m_symbol_info.LotsMax();
   
   if(lot < min_lot) return 0.0;
   if(lot > max_lot) lot = max_lot;
   
   return NormalizeDouble(lot, (int)MathMax(0, -MathLog10(step)));
}

//+------------------------------------------------------------------+
//| Check margin                                                     |
//+------------------------------------------------------------------+
bool CHedgeEngine::CheckMargin(double lot, bool is_buy)
{
   if(!m_symbol_info.RefreshRates())
      return false;
      
   double price = is_buy ? m_symbol_info.Ask() : m_symbol_info.Bid();
   double balance = m_account_info.Balance();
   double equity = m_account_info.Equity();
   double margin = m_account_info.Margin();
   double free_margin = m_account_info.FreeMargin();
   
   // Alternative way: calculate margin manually (since MarginCheck is not always available)
   double margin_level = (free_margin > 0) ? (equity / margin) * 100 : 0;
   
   // Simple check: ensure free margin is at least 120% of required (using leverage)
   double margin_required = lot * price / m_account_info.Leverage();
   
   return (free_margin >= margin_required * 1.2);
}

//+------------------------------------------------------------------+
//| Open hedge position                                              |
//+------------------------------------------------------------------+
bool CHedgeEngine::OpenHedge(ulong main_ticket, double lot)
{
   if(!m_position_info.SelectByTicket(main_ticket))
      return false;
      
   if(!CheckMargin(lot, m_position_info.PositionType() == POSITION_TYPE_SELL))
      return false;
      
   bool success = false;
   if(m_position_info.PositionType() == POSITION_TYPE_BUY)
      success = m_trade.Sell(lot, m_symbol, 0.0, 0.0, "Hedge for " + IntegerToString(main_ticket));
   else
      success = m_trade.Buy(lot, m_symbol, 0.0, 0.0, "Hedge for " + IntegerToString(main_ticket));
      
   return success;
}

//+------------------------------------------------------------------+
//| Count current hedge positions                                     |
//+------------------------------------------------------------------+
int CHedgeEngine::CountCurrentHedges()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position_info.SelectByIndex(i))
      {
         if(m_position_info.Symbol() == m_symbol && m_position_info.Magic() == m_config.hedge_magic_number)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Update Hedge Engine                                              |
//+------------------------------------------------------------------+
void CHedgeEngine::Update()
{
   if(!m_config.enable_hedging)
      return;
      
   if(!m_symbol_info.RefreshRates())
      return;
      
   // Check cooldown
   if(m_last_hedge_time > 0 && (TimeCurrent() - m_last_hedge_time) < (m_config.cooldown_minutes * 60))
      return;
      
   // Check max hedges
   int current_hedges = CountCurrentHedges();
   if(m_config.max_hedges > 0 && current_hedges >= m_config.max_hedges)
      return;
      
   // Iterate positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position_info.SelectByIndex(i))
         continue;
         
      // Check symbol
      if(m_position_info.Symbol() != m_symbol)
         continue;
         
      // Check magic number
      ulong magic = m_position_info.Magic();
      if(m_config.main_magic_number != 0 && magic != m_config.main_magic_number)
         continue;
      if(magic == m_config.hedge_magic_number) // Skip hedge positions
         continue;
         
      ulong ticket = m_position_info.Ticket();
      
      // Check if already hedged
      if(IsPositionHedged(ticket))
         continue;
         
      // Check loss threshold
      double loss_pips = CalculateLossInPips(ticket);
      if(loss_pips < m_config.loss_threshold_pips)
         continue;
         
      // Calculate hedge lot
      double hedge_lot = NormalizeLot(m_position_info.Volume() * m_config.lot_coefficient);
      if(hedge_lot <= 0)
         continue;
         
      // Open hedge
      if(OpenHedge(ticket, hedge_lot))
      {
         MarkPositionHedged(ticket);
         m_last_hedge_time = TimeCurrent();
      }
   }
}
//+------------------------------------------------------------------+

