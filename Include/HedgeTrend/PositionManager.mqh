//+------------------------------------------------------------------+
//|                                          PositionManager.mqh     |
//|                 Position Manager - Scale In & Trailing           |
//+------------------------------------------------------------------+
#property copyright "Sector51 Core"
#property link      "https://www.sector51.com"
#property version   "1.00"
#property strict

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Position Manager Configuration                                   |
//+------------------------------------------------------------------+
struct SPositionManagerConfig
{
   bool               enable_scale_in;         // Enable scale in
   double             scale_in_profit_rr;     // Scale in when profit reaches X RR
   double             scale_in_lot_multiplier; // Scale in lot multiplier
   bool               enable_partial_close;    // Enable partial close
   double             partial_close_rr;        // Partial close at X RR
   double             partial_close_percent;   // % to close
   bool               enable_trailing_stop;    // Enable trailing stop
   double             trailing_start_rr;       // Start trailing at X RR
   double             trailing_atr_multiplier; // Trailing distance (ATR * multiplier)
   bool               enable_basket_management;// Enable basket management
   double             basket_take_profit_percent;// Basket TP %
   
   SPositionManagerConfig()
   {
      enable_scale_in = true;
      scale_in_profit_rr = 1.0;
      scale_in_lot_multiplier = 0.5;
      enable_partial_close = true;
      partial_close_rr = 1.0;
      partial_close_percent = 50.0;
      enable_trailing_stop = true;
      trailing_start_rr = 1.5;
      trailing_atr_multiplier = 0.8;
      enable_basket_management = false;
      basket_take_profit_percent = 5.0;
   }
};

//+------------------------------------------------------------------+
//| Position Info Tracking Struct                                    |
//+------------------------------------------------------------------+
struct SPositionTrack
{
   ulong              ticket;
   bool               partial_closed;
   bool               scaled_in;
   datetime           last_update;
   
   SPositionTrack()
   {
      ticket = 0;
      partial_closed = false;
      scaled_in = false;
      last_update = 0;
   }
};

//+------------------------------------------------------------------+
//| Position Manager Class                                           |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   SPositionManagerConfig m_config;
   string              m_symbol;
   CPositionInfo       m_position_info;
   CTrade              m_trade;
   CSymbolInfo         m_symbol_info;
   SPositionTrack      m_tracked_positions[];
   int                 m_tracked_count;
   
public:
                     CPositionManager();
                    ~CPositionManager();
   
   bool              Init(const string symbol, const SPositionManagerConfig &config, ulong magic_number);
   void              Deinit();
   void              ManagePositions(double atr);
   int               CountOpenPositions(ENUM_POSITION_TYPE type = WRONG_VALUE);
   
private:
   SPositionTrack*   FindTrackedPosition(ulong ticket);
   void              AddTrackedPosition(ulong ticket);
   double            CalculateRR(ulong ticket);
   bool              DoPartialClose(ulong ticket);
   bool              DoTrailingStop(ulong ticket, double atr);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPositionManager::CPositionManager() : m_tracked_count(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPositionManager::~CPositionManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Position Manager                                      |
//+------------------------------------------------------------------+
bool CPositionManager::Init(const string symbol, const SPositionManagerConfig &config, ulong magic_number)
{
   m_symbol = symbol;
   m_config = config;
   
   if(!m_symbol_info.Name(m_symbol))
      return false;
      
   m_trade.SetExpertMagicNumber(magic_number);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   ArrayResize(m_tracked_positions, 100);
   m_tracked_count = 0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Position Manager                                    |
//+------------------------------------------------------------------+
void CPositionManager::Deinit()
{
   ArrayFree(m_tracked_positions);
   m_tracked_count = 0;
}

//+------------------------------------------------------------------+
//| Find tracked position                                            |
//+------------------------------------------------------------------+
SPositionTrack* CPositionManager::FindTrackedPosition(ulong ticket)
{
   for(int i = 0; i < m_tracked_count; i++)
   {
      if(m_tracked_positions[i].ticket == ticket)
         return &m_tracked_positions[i];
   }
   return NULL;
}

//+------------------------------------------------------------------+
//| Add tracked position                                             |
//+------------------------------------------------------------------+
void CPositionManager::AddTrackedPosition(ulong ticket)
{
   if(FindTrackedPosition(ticket) != NULL)
      return;
      
   if(m_tracked_count < 100)
   {
      m_tracked_positions[m_tracked_count].ticket = ticket;
      m_tracked_positions[m_tracked_count].partial_closed = false;
      m_tracked_positions[m_tracked_count].scaled_in = false;
      m_tracked_positions[m_tracked_count].last_update = TimeCurrent();
      m_tracked_count++;
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CPositionManager::CountOpenPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position_info.SelectByIndex(i))
      {
         if(m_position_info.Symbol() == m_symbol)
         {
            if(type == WRONG_VALUE || m_position_info.PositionType() == type)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate RR for position                                        |
//+------------------------------------------------------------------+
double CPositionManager::CalculateRR(ulong ticket)
{
   if(!m_position_info.SelectByTicket(ticket))
      return 0.0;
      
   double entry = m_position_info.PriceOpen();
   double sl = m_position_info.StopLoss();
   double current = m_position_info.PriceCurrent();
   double sl_dist = MathAbs(entry - sl);
   if(sl_dist <= 0) return 0.0;
   
   if(m_position_info.PositionType() == POSITION_TYPE_BUY)
      return (current - entry) / sl_dist;
   else
      return (entry - current) / sl_dist;
}

//+------------------------------------------------------------------+
//| Do partial close                                                 |
//+------------------------------------------------------------------+
bool CPositionManager::DoPartialClose(ulong ticket)
{
   if(!m_position_info.SelectByTicket(ticket))
      return false;
      
   double lot = m_position_info.Volume();
   double step = m_symbol_info.LotsStep();
   double close_lot = NormalizeDouble(lot * (m_config.partial_close_percent / 100.0), (int)MathMax(0, -MathLog10(step)));
   
   if(close_lot < m_symbol_info.LotsMin())
      close_lot = m_symbol_info.LotsMin();
      
   return m_trade.PositionClosePartial(ticket, close_lot);
}

//+------------------------------------------------------------------+
//| Do trailing stop                                                 |
//+------------------------------------------------------------------+
bool CPositionManager::DoTrailingStop(ulong ticket, double atr)
{
   if(!m_position_info.SelectByTicket(ticket))
      return false;
      
   double entry = m_position_info.PriceOpen();
   double current_sl = m_position_info.StopLoss();
   double current = m_position_info.PriceCurrent();
   double trail_dist = atr * m_config.trailing_atr_multiplier;
   double new_sl = 0.0;
   
   if(m_position_info.PositionType() == POSITION_TYPE_BUY)
   {
      new_sl = current - trail_dist;
      if(new_sl > current_sl && new_sl > entry)
         return m_trade.PositionModify(ticket, new_sl, m_position_info.TakeProfit());
   }
   else
   {
      new_sl = current + trail_dist;
      if(new_sl < current_sl && new_sl < entry)
         return m_trade.PositionModify(ticket, new_sl, m_position_info.TakeProfit());
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage all positions                                             |
//+------------------------------------------------------------------+
void CPositionManager::ManagePositions(double atr)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position_info.SelectByIndex(i))
         continue;
         
      if(m_position_info.Symbol() != m_symbol)
         continue;
         
      ulong ticket = m_position_info.Ticket();
      AddTrackedPosition(ticket);
      
      SPositionTrack* track = FindTrackedPosition(ticket);
      if(track == NULL) continue;
      
      double rr = CalculateRR(ticket);
      
      // Partial close
      if(m_config.enable_partial_close && !track->partial_closed && rr >= m_config.partial_close_rr)
      {
         if(DoPartialClose(ticket))
         {
            track->partial_closed = true;
            track->last_update = TimeCurrent();
         }
      }
      
      // Trailing stop
      if(m_config.enable_trailing_stop && rr >= m_config.trailing_start_rr)
      {
         DoTrailingStop(ticket, atr);
      }
   }
}
//+------------------------------------------------------------------+

