# WPS Spreadsheet Environment - Evidence Documentation

## Environment Overview
- **Environment ID**: wps_spreadsheet_env@0.1
- **Base Image**: ubuntu-gnome-systemd_highres
- **Application**: WPS Office Spreadsheet (et command)
- **Version**: 11.1.0.11723

## Test Results Summary

### Baseline Verification (all tasks)

| Task | Baseline Score | Passed | Difficulty |
|------|---------------|--------|------------|
| create_sales_summary | 0 | false | medium |
| add_conditional_formatting | 0 | false | medium |
| create_pivot_table | 0 | false | medium |
| apply_data_validation | 0 | false | medium |
| sort_and_filter_data | 0 | false | medium |
| financial_consolidation_analysis | 0 | false | very_hard |
| production_capacity_planning | 0 | false | very_hard |
| compensation_equity_analysis | 0 | false | very_hard |
| budget_variance_dashboard | 0 | false | very_hard |
| loan_portfolio_amortization | 0 | false | very_hard |

### Installation Verification
- WPS Office installation: **SUCCESS**
- WPS Spreadsheet binary: `/usr/bin/et`
- Desktop shortcut created: **YES**
- Sample data files created: **YES**

## Evidence Screenshots

### 1. Desktop with WPS Icons
![Desktop with WPS icons](evidence/01_desktop.png)
- Shows WPS Spreadsheet desktop shortcut
- Desktop icons visible

### 2. Documents Folder
![Documents folder](evidence/02_documents_folder.png)
- sales_data.xlsx created in /home/ga/Documents/
- All task data files present

## Task Data Files

| Task | Data File | Records |
|------|-----------|---------|
| create_sales_summary | sales_data.xlsx | 60 |
| add_conditional_formatting | inventory.xlsx | 30 |
| create_pivot_table | employee_sales.xlsx | 20 |
| apply_data_validation | project_tracker.xlsx | 12 |
| sort_and_filter_data | customer_orders.xlsx | 40 |
| financial_consolidation_analysis | meridian_holdings_consolidation.xlsx | 5 sheets (3 subs + IC + PY) |
| production_capacity_planning | production_capacity_plan.xlsx | 3 sheets (Lines + Orders + Calendar) |
| compensation_equity_analysis | compensation_equity_review.xlsx | 2 sheets (36 employees + 24 benchmarks) |
| budget_variance_dashboard | budget_variance_analysis.xlsx | 2 sheets (Budget + Actuals, 28 line items × 12 months) |
| loan_portfolio_amortization | loan_portfolio_model.xlsx | 3 sheets (6 loans + Rate Curve + Property NOI) |

## New Very Hard Tasks (added 2026-03-06)

### Data Sources
- **SOFR rates**: Federal Reserve Bank of NY, 30-Day Average SOFR (FRED series SOFR30DAYAVG)
- **Salary benchmarks**: BLS OEWS May 2024 percentile wage estimates
- **Financial statements**: Calibrated to SEC EDGAR 10-K filing patterns and Census Bureau ASM
- **CRE loan terms**: Federal Reserve SLOOS and MBA Commercial/Multifamily Databook
- **Budget structure**: AICPA Management Accounting Practice, BLS QCEW for NAICS 54

### Evidence Screenshots
- `financial_consolidation_screenshot.png` - WPS open with 5-sheet consolidation workbook
- `production_capacity_planning_screenshot.png` - WPS open with production planning workbook
- `compensation_equity_analysis_screenshot.png` - WPS open with compensation review workbook
- `budget_variance_dashboard_screenshot.png` - WPS open with budget variance workbook
- `loan_portfolio_amortization_screenshot.png` - WPS open with loan portfolio workbook
- `new_tasks_evidence.json` - Complete evidence data for all 5 tasks

## Verification Criteria

### create_sales_summary
- Summary sheet exists
- SUMIF formulas (3+)
- AVERAGEIF formulas
- COUNTIF formulas
- Bold headers
- Currency formatting
- VLM visual verification

### add_conditional_formatting
- Conditional formatting rules present
- Color highlighting (red/green)
- Data bars
- Color scale
- VLM visual verification

### create_pivot_table
- Multiple sheets created
- Pivot table structure
- Department summary
- Grand totals
- VLM visual verification

### apply_data_validation
- Data validation rules present
- Freeze panes applied
- Dropdown menus
- VLM visual verification

### sort_and_filter_data
- AutoFilter applied
- Freeze panes
- Sorted by Amount (descending)
- Filter dropdowns
- VLM visual verification

## Installation Notes

### Key Patterns from wps_office_writer_env
- Uses same WPS installation (includes et/spreadsheet)
- Uses openpyxl for spreadsheet parsing
- Downloads WPS from official CDN
- Configures via wpsoffice.ini

### Dependencies
- openpyxl (for spreadsheet parsing)
- xlrd (legacy Excel support)
- pandas (data manipulation)
- python-docx (not needed but included)

## Known Limitations
- VLM verification may fail if local LLM is unavailable
- Conditional formatting in openpyxl has limited support
- Pivot table support is limited in openpyxl

## Environment Files
- `env.json` - Environment configuration
- `scripts/install_wps.sh` - Installation hook
- `scripts/setup_wps.sh` - Setup hook
- `utils/wps_verification_utils.py` - Verification utilities
- `tasks/*/task.json` - Task definitions
- `tasks/*/verifier.py` - Task verifiers

## Test Execution Time
- Environment setup: ~105-110 seconds
- Task setup: ~1-2 seconds
- Total per task: ~106-112 seconds
