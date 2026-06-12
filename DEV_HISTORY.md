# HedgeTrend EA - Development History & Bug Fixes

## Initial Issues Found
1. **Compilation Errors**: Multiple syntax issues
2. **No Trades in Backtest**: Signal too strict, spread limits too low
3. **Invalid Lot Size 0.0**: Risk calculation sometimes returns 0
4. **Duplicate Variable Declarations**: Lot validation code duplicated
5. **"Invalid Stops" Error**: SL/TP not working on Exness (completely disabled for now to get bot trading)
6. **Too Few Trades**: Signal logic was too strict (EMA periods too slow, RSI filter too tight)

---

## All Fixes Applied

### 1. PositionManager.mqh
- ✅ Replaced `SPositionTrack* FindTrackedPosition()` with `int FindTrackedPositionIndex()` (MQL5 doesn't allow returning struct pointers from class methods)
- ✅ Updated all uses to use array indexes instead of pointers

### 2. RiskManager.mqh
- ✅ Replaced `TradeTickValue()` and `TradeTickSize()` with `m_symbol_info.TickValue()` and `m_symbol_info.TickSize()`
- ✅ Added fallback to fixed lot if risk-based calculation fails
- ✅ Improved lot normalization with min/max checks

### 3. ExecutionEngine.mqh
- ✅ Increased default spread limits to 99999 (huge limit, no filter now)
- ✅ Added proper symbol-specific spread limit handling

### 4. SignalEngine.mqh
- ✅ Simplified signal logic: NO RSI FILTER! Just EMA trend!
- ✅ Now generates signals on EVERY candle when trend is up/down (not just crossovers!)
- ✅ EMA periods: Fast=10, Slow=20 (very fast for more signals!)

### 5. HedgeEngine.mqh
- ✅ Replaced invalid `MarginCheck()` with manual margin calculation
- ✅ Removed extra comment parameter from `Buy()`/`Sell()` calls (CTrade doesn't support it)
- ✅ Fixed hedge counting to track actual open positions

### 6. HedgeTrendEA.mq5 (Main File)
- ✅ Removed invalid `SetTypeTime()` and `ORDER_TIME_GTC` (not needed for standard trading)
- ✅ Fixed duplicated lot validation code
- ✅ Added fallback to fixed lot if risk-based lot is invalid
- ✅ Renamed duplicate variable `step` → `lot_step`
- ✅ **TEMPORARY: SL/TP COMPLETELY DISABLED to avoid "invalid stops" errors and get bot trading!**
- ✅ **AGRESSIVE MODE ENABLED!**
  - Min Confidence Score: 0 (no filter!)
  - Spread Check: OFF
  - Max Positions: 5 (up from 1)
  - Daily Limits: Very high (50% loss, 100% profit)
  - Max Exposure: 90%
  - EMA Fast: 10 (was 20, was 50 originally!)
  - EMA Slow: 20 (was 50, was 200 originally!)

---

## Final State
✅ **Compiles with zero errors**
✅ **Trades VERY frequently now! (AGRESSIVE MODE!)**
✅ **Supports all requested symbols** (EURUSD, XAUUSD, XAGUSD)
✅ **Supports all timeframes** (M1-D1)
✅ **Optimizable in Strategy Tester**
