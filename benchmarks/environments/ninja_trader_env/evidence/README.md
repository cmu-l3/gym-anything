# NinjaTrader Environment Evidence

## Screenshots

1. **01_after_boot_get_connected.png** - NinjaTrader first boot showing "Get Connected" dialog asking to connect to a live data feed. Skip button visible.

2. **02_control_center_clean.png** - Clean NinjaTrader Control Center after all startup dialogs dismissed. Shows menu bar, orders grid, and Market Analyzer panel.

3. **03_relaunch_with_dialogs.png** - NinjaTrader relaunch showing "Getting Started" tips panel and "Warning" dialog about windows outside viewable range. These appear on every launch.

4. **04_aapl_daily_chart_with_data.png** - AAPL daily candlestick chart displaying imported Yahoo Finance data (Oct-Dec 2024, price range ~$220-$260). Confirms data import works correctly.

5. **05_data_import_success.png** - Successful import confirmation dialog showing "502 data record(s) successfully imported" via Tools > Import > Historical Data.

## Key Findings

- NinjaTrader 8.1.x Enterprise Evaluation mode does NOT require login (63-day trial)
- Silent MSI install works: `msiexec.exe /i "NinjaTrader.Install.V8.msi" /qn /norestart`
- Win32 API clicks (SetCursorPos + mouse_event) do NOT work for NinjaTrader dialogs
- PyAutoGUI TCP server (port 5555) clicks DO work from SSH (Session 0)
- Yahoo Finance data imports correctly in NinjaTrader semicolon format
- Dialog sequence: Get Connected → Warning → Getting Started → SuperDOM
