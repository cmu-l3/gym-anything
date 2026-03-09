# Task: create_reusable_chart_template

## Overview
A swing trader creates a reusable chart template with their preferred indicator configuration for quick application to any instrument.

## Goal
1. Open an AAPL daily chart
2. Add indicators: EMA(9), EMA(21), RSI(14), MACD(12,26,9)
3. Save as a chart template named "SwingTrading"

## Difficulty: Hard
The agent must:
1. Create a chart for AAPL (find the New > Chart workflow)
2. Add 4 indicators with correct parameters (navigate indicator dialogs 4 times)
3. Discover how to save a chart template (not the same as saving a workspace)
4. Name the template correctly

This is hard because saving a chart template is a distinct feature from saving a workspace — the agent must discover this feature independently.

## Data
Real Yahoo Finance AAPL daily data (Jan 2023 - Dec 2024, 502 trading days).

## Verification Strategy
- **Subtask 1 (25 pts)**: Template file exists with correct name in templates directory
- **Subtask 2 (25 pts)**: Template contains EMA indicators
- **Subtask 3 (25 pts)**: Template contains RSI and MACD indicators
- **Subtask 4 (15 pts)**: Template file has substantial content (not a stub)
- **Subtask 5 (10 pts)**: Workspace was also saved

Pass threshold: 70 points

## Schema / Data Reference
- Template directory: `C:\Users\Docker\Documents\NinjaTrader 8\templates\Chart\`
- Template name searched case-insensitively: `SwingTrading` or `swing.?trading`
- Export result JSON: `C:\Users\Docker\Desktop\NinjaTraderTasks\create_reusable_chart_template_result.json`
- Indicators in template: `EMA`/`ExponentialMovingAverage`, `RSI`/`RelativeStrengthIndex`, `MACD`
- EMA instance count tracked (need at least 2 for EMA(9) and EMA(21))

## Ground Truth
- Template name: SwingTrading
- Template directory: `C:\Users\Docker\Documents\NinjaTrader 8\templates\Chart\`
- Expected indicators: EMA(9), EMA(21), RSI(14), MACD(12,26,9)

## Edge Cases and Potential Issues
- Chart templates are saved via a different mechanism than workspaces; the agent must discover the template save feature
- RSI regex uses word boundaries (`\bRSI\b`) to avoid false positives with "version" in XML
- Templates directory (`templates\Chart\`) is initially empty; new files indicate agent work
- If the agent saves the template with a different name (e.g., "Swing Trading" with a space), the case-insensitive regex should still match
