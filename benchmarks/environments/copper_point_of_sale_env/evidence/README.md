# Copper Point of Sale Environment - Evidence Documentation

## Environment Overview

- **Application**: NCH Copper Point of Sale v3.06
- **Platform**: Windows 11 (QEMU VM)
- **Resources**: 4 CPU, 6GB RAM, no GPU
- **Resolution**: 1280x720

## Verification Checklist

### 1. Installation script completes without errors

**Evidence**: `env_setup_pre_start.log` excerpt:

```
=== Copper POS Pre-Start: Download and Stage ===
Copper POS not found. Downloading installer...
Attempting download from: https://www.nchsoftware.com/point-of-sale/possetupfree.exe
Download successful from: https://www.nchsoftware.com/point-of-sale/possetupfree.exe
Installer staged at: C:\Windows\Temp\possetup.exe (0.54 MB)
Copied data file: customers.csv
Copied data file: products.csv
Data files staged at: C:\Users\Docker\Documents\CopperData
=== Pre-start complete ===
```

### 2. Setup script completes without errors

**Evidence**: `env_setup_post_start.log` excerpt:

```
=== Setting up Copper Point of Sale environment ===
Disabling OneDrive...
OneDrive uninstalled.
Copper POS not installed. Running GUI installer via PyAutoGUI...
SUCCESS: The scheduled task "InstallCopper" has successfully been created.
SUCCESS: Attempted to run the scheduled task "InstallCopper".
Waiting for installer to load (20s)...
Pressing Escape to dismiss any OneDrive/notification popups...
Focusing installer dialog...
Clicking Next on EULA...
Waiting for Copper to install and launch (up to 120s)...
Copper installed at: C:\Program Files (x86)\NCH Software\Copper\copper.exe (after 0s)
Dismissing Quick Start Wizard...
Clicking OK on Wizard Cancelled dialog...
Copper POS installed and initial setup complete.
Saved exe path to copper_exe_path.txt
Killing Copper after warm-up...
Second warm-up launch to verify clean startup...
Copper POS launched (waited 15s).
Dismissing any remaining dialogs...
=== Dialog dismissal complete ===
Copper POS processes stopped.
Second warm-up complete.
=== Copper Point of Sale environment setup complete ===
```

### 3. Application is visible in screenshot

**Evidence**: All 5 task screenshots show the Copper POS main register window:
- `task_add_inventory_item.png`
- `task_process_sale.png`
- `task_generate_sales_report.png`
- `task_add_customer.png`
- `task_configure_receipt.png`

### 4. Application is in correct initial state with real data loaded

**Evidence**: Visual grounding analysis confirms:
- Title bar shows "Copper by NCH Software - [Change the company name] - (Unlicensed) Non-enterprise use only"
- Main register/transaction screen is displayed
- Menu bar visible: Copper, Reports, View, Restaurant, Tools, Help
- Transaction grid is empty and ready for use
- Total shows $0.00
- All action buttons visible: Select Customer, Select Item, Manual Item Entry, etc.
- Real data (100 products CSV, 30 customers CSV) staged at `C:\Users\Docker\Documents\CopperData`

### 5. Task setup runs without errors

**Evidence**: All 5 tasks complete `env.reset()` successfully with `pre_task` hooks running in ~42s each:
- `add_inventory_item`: 42.0s pre_task
- `process_sale`: 42.2s pre_task
- `generate_sales_report`: 42.5s pre_task
- `add_customer`: 42.4s pre_task
- `configure_receipt`: 42.9s pre_task

### 6. Task start state is correct (verified via visual_grounding)

**Evidence**: Each task screenshot was analyzed with the `visual_grounding` MCP tool:

- **add_inventory_item**: Main register screen visible, "Select Item" and "Manual Item Entry" buttons accessible
- **process_sale**: Empty transaction screen ready, "Enter Item Code" field, "Pay..." button, "New Transaction" button all visible
- **generate_sales_report**: Main screen visible, "Reports" menu at (79, 32) accessible for navigation
- **add_customer**: Main screen visible, "Select Customer" button at (874, 162) accessible
- **configure_receipt**: Main screen visible, "Tools" menu at (236, 32) and "Options" toolbar button at (189, 67) accessible for receipt settings

**New hard tasks (2026-02-28)**: All 5 screenshots confirmed by visual_grounding:
- **seasonal_clearance_markdown**: Copper POS v3.06 main register, empty transaction, $0.00 total, full menu bar visible. All action buttons accessible. clothing_inventory.csv and pricing_reference.csv staged on Desktop. Task start timestamp recorded.
- **shift_end_reconciliation**: Same empty register state, shift_items.csv and shift_log.txt staged on Desktop. Task start timestamp recorded.
- **corporate_customer_onboarding**: Empty register state, corporate_accounts.txt and existing_customers.csv staged on Desktop. Task start timestamp recorded.
- **new_store_configuration**: Empty register state with "[Change the company name]" confirming fresh configuration state. store_specs.txt staged on Desktop. Task start timestamp recorded.
- **multi_report_sales_analytics**: Empty register state, electronics_clothing_inventory.csv and analytics_brief.txt staged on Desktop. Task start timestamp recorded.

### 7. Task is completable interactively

All tasks present the agent with the main Copper POS register screen from which they can navigate to complete their assigned task using standard menu/button navigation.

### 8. Do-nothing test results (new tasks, 2026-02-28)

All 5 new tasks return score=0, passed=False immediately when no actions are taken:

| Task | Do-nothing score | Do-nothing passed | Feedback |
|------|-----------------|-------------------|---------|
| seasonal_clearance_markdown | 0 | False | No export file found |
| shift_end_reconciliation | 0 | False | No report file found |
| corporate_customer_onboarding | 0 | False | No export file found |
| new_store_configuration | 0 | False | No tax_verification.txt found |
| multi_report_sales_analytics | 0 | False | No output files found |

### 9. Partial completion test results (new tasks, 2026-02-28)

Partial results (offline injection) give partial credit without passing:

| Task | Partial scenario | Score | Passed |
|------|-----------------|-------|--------|
| seasonal_clearance_markdown | File exists + 3/8 clearance items correct | 45/100 | False |
| shift_end_reconciliation | File exists + 3 rows, no discount/void/total | 43/100 | False |
| corporate_customer_onboarding | File exists + 3/6 companies, no updates | 53/100 | False |
| new_store_configuration | File exists + biz name + tax rate (no amounts) | 60/100 | False (threshold=80) |
| multi_report_sales_analytics | 2/3 output files exist, no summary | 45/100 | False |

## Timing

| Phase | Duration |
|-------|----------|
| Pre-start (download installer + stage data) | ~2s |
| Post-start (GUI install + warm-up) | ~108s |
| Checkpoint creation (savevm) | ~40s |
| Pre-task (launch + dismiss dialogs) | ~42s |
| **Total env.reset() from cache** | **~130s** |
| **Total env.reset() fresh (no cache)** | **~240s** |

## Data Sources

- **products.csv** (100 items): Real retail product data from Shopify Partners product-csvs repo (apparel, home & garden, jewelry), GitHub Gist grocery dataset, and real electronics product names
- **customers.csv** (30 records): Real sample customer data from datablist/sample-csv-files GitHub repo
