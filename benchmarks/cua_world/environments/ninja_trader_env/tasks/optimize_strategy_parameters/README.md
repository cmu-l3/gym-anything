# Task: optimize_strategy_parameters

## Overview
A quantitative analyst runs a strategy parameter optimization to find optimal moving average crossover settings for MSFT.

## Goal
1. Open Strategy Analyzer in optimization mode
2. Configure SampleMACrossOver on MSFT daily
3. Set Fast MA range: 5-20 step 5 (4 values)
4. Set Slow MA range: 30-60 step 10 (4 values)
5. Run optimization (4x4 = 16 parameter combinations)
6. Export results to `C:\Users\Docker\Desktop\NinjaTraderTasks\msft_optimization_results.csv`

## Difficulty: Hard
The agent must:
1. Discover how to access Strategy Analyzer (New menu from Control Center)
2. Switch from Backtest to Optimization mode (non-obvious UI toggle)
3. Configure parameter ranges with min/max/step values
4. Run the optimization and wait for all combinations to complete
5. Export the results grid to a file

This is significantly harder than a simple backtest because the optimization interface has additional configuration for parameter ranges that the agent must discover.

## Data
Real Yahoo Finance MSFT daily data (Jan 2023 - Dec 2024, 502 trading days).

## Verification Strategy
- **Subtask 1 (20 pts)**: Export file exists at expected path
- **Subtask 2 (25 pts)**: File has valid structure with multiple rows (optimization results)
- **Subtask 3 (25 pts)**: File contains MSFT-related data
- **Subtask 4 (15 pts)**: File suggests multiple parameter combinations were tested
- **Subtask 5 (15 pts)**: File contains performance metrics (profit, drawdown, etc.)

Pass threshold: 70 points

## Schema / Data Reference
- Expected output: `C:\Users\Docker\Desktop\NinjaTraderTasks\msft_optimization_results.csv`
- Export result JSON: `C:\Users\Docker\Desktop\NinjaTraderTasks\optimize_strategy_parameters_result.json`
- MSFT detected by case-insensitive string search in file content
- Parameter variation detected by multiple distinct numeric patterns
- Performance metrics detected by keywords: `profit`, `net`, `drawdown`, `return`, `sharpe`, `ratio`, `trades`

## Ground Truth
- Strategy: SampleMACrossOver
- Instrument: MSFT
- Fast MA: 5, 10, 15, 20
- Slow MA: 30, 40, 50, 60
- Expected combinations: 16 (4 x 4)

## Edge Cases and Potential Issues
- Wrong-target gate: if file exists with >3 lines but MSFT not found, score=0 (agent optimized wrong instrument)
- The optimization mode in Strategy Analyzer requires switching from Backtest mode — a non-obvious toggle
- Parameter range configuration UI may change across NinjaTrader versions
- Alternative file paths are checked if primary path is empty
- If MSFT data wasn't imported during post_start, the optimization will produce no results
