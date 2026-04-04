# Task: backtest_strategy_and_export

## Overview
A quantitative analyst needs to evaluate SampleMACrossOver on SPY over 2 years and export the trade log for external analysis.

## Goal
1. Open Strategy Analyzer
2. Configure: SampleMACrossOver on SPY, daily bars, Jan 2023 - Dec 2024
3. Run the backtest
4. Export trade list to `C:\Users\Docker\Desktop\NinjaTraderTasks\spy_backtest_trades.csv`

## Difficulty: Hard
The agent must:
1. Discover where the Strategy Analyzer is
2. Configure the correct strategy, instrument, date range, and bar type
3. Run the backtest and wait for completion
4. Find the export functionality for trade results
5. Navigate the file save dialog to the correct path

No UI navigation steps are provided in the description.

## Data
Real Yahoo Finance SPY daily data (Jan 2023 - Dec 2024, 502 trading days).

## Verification Strategy
- **Subtask 1 (20 pts)**: Export file exists at the expected path
- **Subtask 2 (25 pts)**: File is non-empty and has valid CSV/text structure
- **Subtask 3 (25 pts)**: File contains SPY trade data
- **Subtask 4 (15 pts)**: Trades are within the expected date range
- **Subtask 5 (15 pts)**: File contains buy and sell entries (complete trades)

Pass threshold: 70 points

## Schema / Data Reference
- Expected output: `C:\Users\Docker\Desktop\NinjaTraderTasks\spy_backtest_trades.csv`
- Export result JSON: `C:\Users\Docker\Desktop\NinjaTraderTasks\backtest_strategy_and_export_result.json`
- SPY detected by case-insensitive string search in file content
- Buy/sell detected by keywords: `buy`, `long`, `entry`, `sell`, `short`, `exit`
- Date range detected by: `2023` or `2024` present in content

## Ground Truth
- Strategy: SampleMACrossOver (built-in)
- Instrument: SPY
- Period: Jan 3, 2023 to Dec 31, 2024
- Bar type: Daily
- Expected output: CSV with trade entries/exits

## Edge Cases and Potential Issues
- Wrong-target gate: if file exists with >3 lines but SPY not found, score=0 (agent backtested wrong instrument)
- Alternative file paths are checked if the primary path is empty (Desktop, Documents, .txt variant)
- NinjaTrader's Strategy Analyzer export format varies by context (right-click export vs File > Save As)
- The strategy must have data to backtest; if SPY data wasn't imported during post_start, the backtest will produce no trades
