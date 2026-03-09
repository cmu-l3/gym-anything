# Microsoft Excel 2010 Environment - Evidence Documentation

## Environment Overview

- **Environment ID**: `microsoft_excel_2010_env@0.1`
- **Base**: Windows 11 (dockur/windows QEMU VM)
- **Application**: Microsoft Excel 2010 (Office 14.0, Professional Plus, MSI-based)
- **Installation**: Office 2010 Professional Plus ISO from Internet Archive (~731MB)
- **Login/Activation**: None required (grace/trial mode)
- **Resolution**: 1280x720

## Installation

Excel 2010 installs via MSI-based `setup.exe /config office_config.xml`. The config.xml enables only Excel (`EXCELFiles State="local"`) and disables all other Office apps. Install exit code 3010 (reboot recommended) is normal and Excel works without reboot.

**Installation path**: `C:\Program Files (x86)\Microsoft Office\Office14\EXCEL.EXE`
**Version**: 14.0.4734.1000

### Install Script Log (pre_start hook)

The install_excel.ps1 script:
1. Checks if Excel already installed (skips if found)
2. Downloads ISO from Internet Archive if not pre-staged
3. Mounts ISO, runs `setup.exe /config office_config.xml`
4. Accepts exit codes 0 and 3010 as success
5. Verifies EXCEL.EXE exists post-install
6. Unmounts ISO and cleans up temp files

### Setup Script Log (post_start hook)

```
=== Setting up Excel 2010 environment ===
Data files copied to: C:\Users\Docker\Desktop\ExcelTasks
Disabling OneDrive...
OneDrive uninstalled.
Setting Office 14.0 registry keys...
Warming up Excel 2010 (first-run cycle)...
Excel executable: C:\Program Files (x86)\Microsoft Office\Office14\EXCEL.EXE
First-run dialog dismissal attempted.
Excel warm-up complete.
Available data files in C:\Users\Docker\Desktop\ExcelTasks:
  - sales_report.xlsx
  - stock_market_data.xlsx
  - us_census_population.xlsx
=== Excel 2010 environment setup complete ===
```

## Task Start States Verified

### 1. sum_formula (Easy)
- **Screenshot**: `sum_formula_start_state.png`
- **File opened**: `us_census_population.xlsx`
- **Title bar**: "us_census_population.xlsx - Microsoft Excel"
- **Data visible**: US state population data with columns: Rank, State, Population (2020 Census), Population (2010 Census), Change, Percent Change
- **Sheet tab**: "State Population"
- **Data rows**: 51 rows (50 states + DC), rows 2-52
- **Status**: VERIFIED - data loads correctly, full ribbon visible, no dialogs

### 2. create_chart (Medium)
- **Screenshot**: `create_chart_start_state.png`
- **File opened**: `stock_market_data.xlsx`
- **Title bar**: "stock_market_data.xlsx - Microsoft Excel"
- **Data visible**: AAPL stock data with columns: Date, Open, High, Low, Close, Volume
- **Sheet tab**: "AAPL Stock Data"
- **Status**: VERIFIED - data loads correctly, Insert tab has chart tools

### 3. conditional_formatting (Medium)
- **Screenshot**: `conditional_formatting_start_state.png`
- **File opened**: `sales_report.xlsx`
- **Title bar**: "sales_report.xlsx - Microsoft Excel"
- **Data visible**: US retail sales data with columns: Month, Geography, Category, Units, Revenue
- **Sheet tab**: "Retail Sales"
- **Revenue values**: All above 21,000 (FRED series MRTSSM448USS, millions of dollars)
- **Status**: VERIFIED - data loads correctly, Conditional Formatting button visible on Home ribbon

## Task Completability Verified

### sum_formula - Interactive Completion Test
- **Screenshot**: `sum_formula_completed.png`
- **Action performed**: Navigated to end of column C data (C52 = Wyoming, 576,851), entered `=SUM(C2:C52)` in C53
- **Result**: 331,449,281 (total US population, matches expected value)
- **Formula bar**: Shows `=SUM(C2:C52)` when C53 selected
- **Saved**: Ctrl+S successful, no dialogs
- **Status**: COMPLETABLE - SUM formula works, file saves without issues

## Technical Notes

- **No sign-in dialogs**: Office 2010 does not require Microsoft account sign-in
- **No activation prompts**: Grace mode works without any activation prompts on fresh install
- **Clean ribbon**: Full Home ribbon with all expected tools (Conditional Formatting, Format as Table, Cell Styles, AutoSum, etc.)
- **schtasks /IT pattern**: Required to launch GUI apps from SSH Session 0
- **Batch file wrapper**: Required because paths with `(x86)` break schtasks parsing
- **Document Recovery panel**: May appear if Excel is force-killed between tasks; handled by Dismiss-ExcelDialogsBestEffort clicking Close button at (216, 628)

## VM Details (Testing Session)

- **SSH Port**: 2359
- **VNC Port**: 5942
- **PyAutoGUI TCP Port**: 5712 (host) → 5555 (guest)
- **User**: Docker / GymAnything123!
- **Windows version**: Windows 11 (NT 10.0.26200.0)
- **Excel version**: 14.0.4734.1000 (32-bit, installed to Program Files (x86))
