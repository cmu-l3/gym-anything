# Task: dual_chart_technical_setup

## Overview
A technical analyst needs two side-by-side chart windows comparing AAPL and MSFT, each with distinct indicator configurations suited for different analysis approaches.

## Goal
Create two chart windows:
- **Chart 1 (AAPL daily)**: SMA(50), SMA(200), Volume
- **Chart 2 (MSFT daily)**: EMA(20), Bollinger Bands(20,2), MACD(12,26,9)

Save the workspace when complete.

## Difficulty: Hard
The agent must:
1. Create two separate chart windows for different instruments
2. Configure 3 indicators on each chart with correct parameters
3. Use different indicator types per chart (SMA vs EMA, Volume vs Bollinger Bands)
4. Save the workspace

This requires navigating multiple chart creation dialogs, indicator configuration dialogs (6 total indicator additions), and workspace saving — all without UI path instructions.

## Data
Real Yahoo Finance daily OHLCV data (Jan 2023 - Dec 2024, 502 trading days) for AAPL and MSFT.

## Verification Strategy
- **Subtask 1 (20 pts)**: Workspace modified (agent saved work)
- **Subtask 2 (25 pts)**: AAPL chart with SMA indicators
- **Subtask 3 (25 pts)**: MSFT chart with EMA/Bollinger/MACD
- **Subtask 4 (15 pts)**: Volume present on AAPL chart
- **Subtask 5 (15 pts)**: Both instruments present (two distinct charts)

Pass threshold: 70 points

## Schema / Data Reference
- Workspace XML files: `C:\Users\Docker\Documents\NinjaTrader 8\workspaces\` (content files, NOT `_Workspaces.xml`)
- Export result JSON: `C:\Users\Docker\Desktop\NinjaTraderTasks\dual_chart_technical_setup_result.json`
- Indicators detected by string matching in workspace XML: `SMA`/`SimpleMovingAverage`, `EMA`/`ExponentialMovingAverage`, `Bollinger`/`BollingerBands`, `MACD`, `Volume`/`VOL`

## Edge Cases and Potential Issues
- SMA and EMA are distinct indicator types; the verifier checks for specific ones per chart (SMA for AAPL, EMA for MSFT)
- The default workspace "Multi-Asset" has no XML content file until explicitly saved
- If the agent creates both charts but only saves one, partial credit is awarded
- Wrong-target: if neither AAPL nor MSFT appears, the instruments subtask scores 0
