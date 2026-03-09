# Task: configure_market_analyzer

## Overview
A financial services professional needs to set up a Market Analyzer in NinjaTrader 8 to monitor SPY, AAPL, and MSFT with key columns including an RSI indicator column.

## Goal
Create a Market Analyzer window with:
- 3 instruments: SPY, AAPL, MSFT
- Columns: Last price, Net Change, RSI(14)
- Save the workspace

## Difficulty: Hard
The agent must discover how to:
1. Open a Market Analyzer (from the New menu in Control Center)
2. Add instruments to rows
3. Add data columns (Last, Net Change)
4. Add an indicator-based column (RSI with period=14)
5. Save the workspace

No UI navigation steps are provided in the description.

## Data
Real Yahoo Finance daily OHLCV data (Jan 2023 - Dec 2024, 502 trading days) pre-imported for SPY, AAPL, MSFT.

## Verification Strategy
- **Subtask 1 (25 pts)**: Workspace file was modified (agent did something)
- **Subtask 2 (30 pts)**: Market Analyzer window exists with 3 instruments
- **Subtask 3 (25 pts)**: RSI indicator column present
- **Subtask 4 (20 pts)**: Last and Net Change columns present

Pass threshold: 70 points

## Schema / Data Reference
- Workspace XML files: `C:\Users\Docker\Documents\NinjaTrader 8\workspaces\` (content files, NOT `_Workspaces.xml` which is just an index)
- Export result JSON: `C:\Users\Docker\Desktop\NinjaTraderTasks\configure_market_analyzer_result.json`
- Instruments detected by string matching in workspace XML: `SPY`, `AAPL`, `MSFT`
- Indicators detected: `RSI`/`RelativeStrengthIndex`, `Last`/`LastPrice`, `NetChange`/`Net Change`

## Ground Truth
- Instruments: SPY, AAPL, MSFT
- RSI Period: 14
- Workspace saved to: `C:\Users\Docker\Documents\NinjaTrader 8\workspaces\`

## Edge Cases and Potential Issues
- NinjaTrader's default workspace ("Multi-Asset") is built-in and has no XML file on disk; workspace content only appears when saved/modified
- The `_Workspaces.xml` file is an index, not workspace content — excluded from analysis
- RSI regex uses word boundaries (`\bRSI\b`) to avoid matching "veRSIon" in XML declarations
- Instruments in Enterprise Evaluation mode may not have real-time data, but the Market Analyzer should still accept them as configured rows
- Wrong-target gate: if Market Analyzer is created but with zero matching instruments (SPY/AAPL/MSFT), score=0
