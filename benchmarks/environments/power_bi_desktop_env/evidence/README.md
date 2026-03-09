# Power BI Desktop Env - Evidence (Live Run)

This folder contains screenshots and documentation captured from a real Windows 11 QEMU VM run of `power_bi_desktop_env@0.1`.

## Environment Overview

- **Platform**: Windows 11 QEMU VM (1280x720 resolution)
- **Application**: Microsoft Power BI Desktop
- **Install method**: Silent EXE installer (`-quiet -norestart ACCEPT_EULA=1`)
- **Install path**: `C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe`

## Installation & Setup

### pre_start hook (install_powerbi.ps1)

Downloads and installs Power BI Desktop via the official Microsoft EXE installer:
```
PBIDesktopSetup_x64.exe -quiet -norestart ACCEPT_EULA=1 INSTALLDESKTOPSHORTCUT=0 DISABLE_UPDATE_NOTIFICATION=1 ENABLECXP=0
```

### post_start hook (setup_powerbi.ps1)

1. Copies CSV data files to `C:\Users\Docker\Desktop\PowerBITasks\`
2. Disables OneDrive (kill process, remove from startup, Group Policy disable, uninstall with 30s timeout)
3. Sets registry tweaks:
   - `HKCU:\Software\Microsoft\Microsoft Power BI Desktop\DisableUpdateNotification` = 1
   - `HKCU:\Software\Microsoft\Microsoft Power BI Desktop\CXP\Enabled` = 0
   - `HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent\DisableWindowsConsumerFeatures` = 1
4. Warm-up launch: launches Power BI Desktop via `schtasks /IT`, waits 20 seconds, then kills both `PBIDesktop` and `msmdsrv` processes
5. Minimizes any leftover terminal windows

### Dialog Dismissal (dismiss_dialogs.ps1)

Handles the following UI elements in sequence, running in the interactive desktop session via `schtasks /IT`:

**Phase 1 - Home Screen** (always shows on launch):
- Dismisses OneDrive popup if present
- Closes "Join us at FabCon Atlanta" promotional banner (X at 1247, 64)
- Clicks "Blank report" card at (328, 243) to enter the report canvas

**Phase 2 - Report Canvas Dialogs** (first launch from checkpoint only):
- Sends Escape key to dismiss front-most modal
- Closes "Dark mode is here" customization dialog (X at 884, 225)
- Sends Escape again for any stacked dialog
- Closes "Two ways to use sample data" tutorial dialog (X at 930, 147)
- Closes green "Live Edit semantic models in Direct Lake mode" banner (X at 640, 32)

**Phase 3 - Cleanup**:
- Multiple Escape keys for safety
- Clicks safe empty canvas area at (535, 550) -- avoids (500, 400) which hits "Import from SQL Server"
- Final Escape key

## Data Sources

Three real-world Kaggle CSV datasets are provided:

| File | Rows | Source | License |
|------|------|--------|---------|
| `sales_data.csv` | 1000 | [Kaggle: vinothkannaece/sales-dataset](https://www.kaggle.com/datasets/vinothkannaece/sales-dataset) | CC0 (Public Domain) |
| `employee_performance.csv` | 1000 | [Kaggle: nadeemajeedch/employee-performance-and-salary-dataset](https://www.kaggle.com/datasets/nadeemajeedch/employee-performance-and-salary-dataset) | CDLA-Sharing-1.0 |
| `website_analytics.csv` | 249 | [Kaggle: afranur/web-analytics-dataset](https://www.kaggle.com/datasets/afranur/web-analytics-dataset) | Kaggle default |

Data files are copied to `C:\Users\Docker\Desktop\PowerBITasks\` during `post_start`.

## Tasks

| Task ID | Difficulty | Description |
|---------|------------|-------------|
| `create_bar_chart@1` | Easy | Import `sales_data.csv`, create a Clustered Bar Chart (Region vs. Sum of Sales_Amount), save as `sales_report.pbix` |
| `dax_measure@1` | Medium | Import `employee_performance.csv`, create a DAX measure `Average_Rating = AVERAGE(employee_performance[Performance Score])`, display in a Card visual, save as `employee_report.pbix` |
| `add_slicer@1` | Medium | Import `website_analytics.csv`, create a Table visual (Source/Medium, Pageviews, Bounce Rate), add a Slicer for Year, save as `analytics_report.pbix` |

Each task uses a `setup_task.ps1` that:
1. Kills existing Power BI + msmdsrv processes
2. Ensures data file is on the Desktop
3. Launches Power BI via `schtasks /IT` (15s wait)
4. Runs `dismiss_dialogs.ps1` via `schtasks /IT` (28s wait)
5. Verifies Power BI is running

## Timing

| Phase | Duration | Notes |
|-------|----------|-------|
| post_start (from cache) | ~135s | Registry tweaks + OneDrive removal + warm-up launch (20s) + cleanup |
| pre_task: PBI launch | ~15s | Via schtasks with 15s sleep |
| pre_task: dialog dismiss | ~28s | dismiss_dialogs.ps1 full sequence |
| pre_task total | ~48s | Kill + launch + dismiss + overhead |

## Data Verification (from live VM)

```
C:\Users\Docker\Desktop\PowerBITasks\sales_data.csv        — 1000 rows
  Columns: Product_ID, Sale_Date, Sales_Rep, Region, Sales_Amount, Quantity_Sold, Product_Category, ...

C:\Users\Docker\Desktop\PowerBITasks\employee_performance.csv — 1000 rows
  Columns: ID, Name, Age, Gender, Department, Salary, Joining Date, Performance Score, Experience, ...

C:\Users\Docker\Desktop\PowerBITasks\website_analytics.csv    — 249 rows
  Columns: Source / Medium, Year, Month of the year, Users, New Users, Sessions, Bounce Rate, Pageviews, ...
```

## Screenshots

| File | Description |
|------|-------------|
| `pbi_v3_after_setup.png` | Home screen on fresh boot (after post_start, before dialog dismiss) |
| `pbi_v3_5s.png` | Canvas with green "Live Edit" banner visible (dismiss in progress) |
| `pbi_v3_15s.png` | Clean canvas (all dialogs dismissed) |
| `pbi_v3_30s.png` | Clean canvas (stable state, 30s after dismiss started) |
| `pbi_test5_final.png` | Clean canvas after manual dismiss test (verification run) |
| `pbi_v4_clean_canvas.png` | Clean canvas with real data files present (create_bar_chart task) |
| `pbi_v4_getdata_dialog.png` | "Get Data" dialog opened — confirms Text/CSV import is accessible |

## Verification Checklist

- [x] Power BI Desktop installs successfully via silent EXE installer
- [x] OneDrive is disabled and does not interfere
- [x] Warm-up launch completes first-run cycle
- [x] Home screen appears on subsequent launch
- [x] FabCon Atlanta banner dismissed correctly
- [x] "Blank report" click enters report canvas
- [x] Dark mode dialog dismissed
- [x] Sample data dialog dismissed
- [x] Green Live Edit banner dismissed
- [x] Clean canvas achieved with no stray dialogs
- [x] All three real-world Kaggle CSV data files present in PowerBITasks directory
- [x] Data file row counts verified: sales (1000), employee (1000), web analytics (249)
- [x] Data file columns match task descriptions
- [x] Safe canvas click at (535, 550) does not trigger any import wizards
- [x] Power BI process remains running after full dismiss sequence
- [x] Screenshots captured at multiple time points confirming stable state
- [x] "Get Data" dialog opens and shows Text/CSV import option (task completability verified)
- [x] Task start state correct: clean canvas, ribbon visible, data accessible on Desktop
