Build a professional MT5 Expert Advisor using MQL5.

Main trading symbols:

* XAUUSD (highest priority)
* EURUSD
* XAGUSD

Requirements:

Architecture must be modular and extensible.

Modules:

1. Signal Engine

* EMA50 and EMA200 trend detection
* RSI14 momentum confirmation
* ATR14 volatility measurement
* Confidence score system instead of hard filters
* Trade allowed when score >= configurable threshold

2. Execution Engine

* Spread monitoring
* Slippage risk estimation
* Reject trades when spread exceeds configurable limit
* Calculate expected execution cost before opening positions
* Include symbol-specific spread limits

3. Risk Manager

* Dynamic lot sizing based on account risk %
* ATR-based stop loss
* ATR-based take profit
* Daily loss limit
* Daily profit target
* Maximum open positions per symbol
* Maximum total account exposure

4. Position Manager

* Allow multiple positions in same direction
* No martingale
* No grid
* Scale-in only when existing trade is profitable
* Partial close functionality
* Basket profit management
* Trailing stop support

5. Hedge Engine

* Integrate existing HedgeCover logic
* One hedge per position
* Cooldown support
* Maximum hedge count
* Margin safety checks
* Hedge lot coefficient configurable

6. Smart Trade Cost Analysis
   Before every trade calculate:

* Current spread
* Average spread
* Estimated slippage
* Estimated execution cost
* Adjust confidence score based on execution quality

7. Extensibility
   Design interfaces for future filters:

* News Filter
* Session Filter
* AI Filter
* Correlation Filter

Code requirements:

* Clean architecture
* SOLID principles where possible
* Fully commented
* Separate classes for each module
* Input parameters grouped logically
* Optimized for MT5 Strategy Tester
* Safe for live trading on Exness

Goal:
Generate steady long-term profit while keeping drawdown low and maintaining high trade frequency.
