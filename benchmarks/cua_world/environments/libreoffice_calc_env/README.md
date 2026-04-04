# LibreOffice Calc Environment

A comprehensive LibreOffice Calc spreadsheet application environment for `gym-anything`, designed for training agents on data manipulation, formula creation, charting, and analysis tasks.

## Overview

This environment provides a complete LibreOffice Calc setup with:
- **LibreOffice Calc 7.x+** with full suite capabilities
- **Python UNO API** for programmatic spreadsheet access and verification
- **Comprehensive verification utilities** for parsing ODS/XLSX files
- **7 progressive tasks** from basic formulas to advanced pivot tables
- **Multi-format support** (ODS, XLSX, CSV, PDF)
- **VNC access** for visual observation and debugging
- **Full GUI automation** support via `xdotool` and `wmctrl`

## Features

### Core Capabilities

1. **Spreadsheet Operations**
   - Cell data entry and editing
   - Formula creation (SUM, AVERAGE, VLOOKUP, IF, etc.)
   - Multi-sheet workbooks
   - Cell references and named ranges

2. **Data Analysis**
   - Sorting and filtering
   - Pivot tables
   - Conditional formatting
   - Data validation
   - Statistical functions

3. **Visualization**
   - Charts and graphs (bar, line, pie, scatter)
   - Chart customization and formatting
   - Embedded charts in sheets

4. **File Formats**
   - Native: ODS (Open Document Spreadsheet)
   - Import/Export: XLSX, XLS, CSV, TSV
   - Export: PDF, HTML

5. **Verification Access**
   - Parse ODS files via `odfpy` library
   - Parse XLSX files via `openpyxl` library
   - Headless mode for conversions and checks
   - UNO API for advanced inspection

## Directory Structure

```
libreoffice_calc_env/
├── env.json                          # Environment specification
├── README.md                         # This file
├── scripts/
│   ├── install_calc.sh              # LibreOffice installation script
│   └── setup_calc.sh                # Calc configuration script
├── config/
│   └── registrymodifications.xcu    # Calc preferences and settings
├── utils/
│   ├── __init__.py
│   └── calc_verification_utils.py   # Verification utilities
└── tasks/                            # Task definitions
    ├── README.md                     # Tasks overview
    ├── simple_sum_formula/           # Easy: Basic SUM formula
    ├── basic_formulas/               # Easy: Basic arithmetic formulas
    ├── csv_import/                   # Easy: CSV import and formatting
    ├── create_chart/                 # Medium: Chart creation
    ├── sort_data/                    # Easy: Sorting data
    ├── conditional_format/           # Medium: Conditional formatting
    └── vlookup_formula/              # Medium: VLOOKUP across sheets
```

## Usage

### Quick Start

```python
import gym_anything as ga

# Load the Calc environment
env = ga.from_config("libreoffice_calc_env")

# Reset the environment
obs = env.reset(seed=42)

# Environment is ready with Calc launched
# VNC viewer accessible on port 5952
```

### Running Tasks

```bash
# Run a specific task
python -m gym_anything.cli run libreoffice_calc_env --task simple_sum_formula

# Validate task configuration
python -m gym_anything.cli validate libreoffice_calc_env --task simple_sum_formula

# Run all tasks sequentially
python -m gym_anything.cli run libreoffice_calc_env --all-tasks
```

### Creating Custom Tasks

Tasks should be placed in the `tasks/` directory. Each task needs:

1. **`task.json`**: Task specification
2. **`setup_task.sh`**: Pre-task setup (create/open spreadsheet)
3. **`export_result.sh`**: Post-task export (save spreadsheet)
4. **`verifier.py`**: Verification logic
5. **`assets/`** (optional): CSV files, templates, reference data

Example task structure:

```json
{
  "id": "my_custom_task@1",
  "version": "1.0",
  "env_id": "libreoffice_calc_env@0.1",
  "description": "Perform a specific spreadsheet operation",
  "init": {
    "timeout_sec": 180,
    "max_steps": 50,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/my_custom_task/setup_task.sh",
    "post_task": "/workspace/tasks/my_custom_task/export_result.sh"
  },
  "success": {
    "spec": {
      "program": "verifier.py::check_my_task"
    }
  }
}
```

## Task Overview

### 🟢 Easy Tasks

1. **Simple Sum Formula** (`simple_sum_formula`)
   - Add SUM formula to calculate total
   - Verify correct formula syntax and result
   - **Skills**: Basic formula creation, cell references

2. **Basic Formulas** (`basic_formulas`)
   - Enter numerical data and apply basic arithmetic formulas
   - Use SUM and AVERAGE functions
   - **Skills**: Data entry, basic formulas, cell references

3. **CSV Import** (`csv_import`)
   - Import CSV data file
   - Format columns appropriately (currency, dates, numbers)
   - **Skills**: File import, data formatting

4. **Sort Data** (`sort_data`)
   - Sort dataset by specific column
   - Maintain data integrity during sorting
   - **Skills**: Data menu navigation, sorting operations

### 🟡 Medium Tasks

5. **Create Chart** (`create_chart`)
   - Generate bar chart from sales data
   - Position and format chart
   - **Skills**: Chart wizard, data range selection

6. **Conditional Format** (`conditional_format`)
   - Apply formatting rules to highlight values
   - Use color scales or condition-based formatting
   - **Skills**: Formatting dialogs, rule creation

7. **VLOOKUP Formula** (`vlookup_formula`)
   - Use VLOOKUP to match data across sheets
   - Populate results from lookup table
   - **Skills**: Advanced formulas, multi-sheet references

## User Accounts

The environment includes one pre-configured user account:

- **`ga`** (primary user)
  - Full sudo access
  - Home: `/home/ga`
  - VNC display: `:1`
  - Calc profile: `/home/ga/.config/libreoffice/4/user`

## Network Ports

- **5952**: VNC server (external access)

## File Locations

### LibreOffice Profile
- `/home/ga/.config/libreoffice/4/user/`

### Important Directories
- **User Profile**: `.config/libreoffice/4/user/`
- **Templates**: `.config/libreoffice/4/user/template/`
- **Extensions**: `.config/libreoffice/4/user/uno_packages/`
- **Recent Documents**: `.config/libreoffice/4/user/registrymodifications.xcu`

### Task Files
- **Workspace**: `/home/ga/Documents/`
- **Task Assets**: `/workspace/tasks/<task_id>/assets/`
- **Results**: `/home/ga/Documents/results/`

## Verification Utilities

The `utils/calc_verification_utils.py` module provides helper functions:

```python
from calc_verification_utils import *

# Parse spreadsheet files
ods_data = parse_ods_file("/path/to/file.ods")
xlsx_data = parse_xlsx_file("/path/to/file.xlsx")

# Verify cell values
value_ok = verify_cell_value(ods_data, "Sheet1", "A1", expected=100)

# Verify formulas
formula_ok = verify_cell_formula(ods_data, "Sheet1", "A11", expected="=SUM(A1:A10)")

# Check for charts
has_chart = check_chart_exists(ods_data, "Sheet1")

# Verify formatting
has_cond_format = check_conditional_formatting(ods_data, "Sheet1", "A1:A10")

# Check pivot tables
has_pivot = check_pivot_table_exists(ods_data, "Pivot1")
```

## GUI Automation

The environment includes `xdotool` and `wmctrl` for GUI automation:

```bash
# Focus Calc window
wmctrl -a "LibreOffice Calc"

# Type in cell
xdotool type "=SUM(A1:A10)"
xdotool key Return

# Take screenshot
import -window root screenshot.png
```

## Headless Mode

LibreOffice Calc can be used in headless mode for conversions and checks:

```bash
# Convert ODS to XLSX
libreoffice --headless --convert-to xlsx file.ods

# Convert to PDF
libreoffice --headless --convert-to pdf file.ods

# Execute macro
libreoffice --headless --invisible "macro:///Standard.Module1.MyMacro"
```

## Logs

- **Calc**: `/tmp/calc_ga.log`
- **Setup**: Check Docker logs or `/tmp/` directory

## Debugging

### Enable VNC Viewer
Connect to `localhost:5952` with password `password` to see the desktop.

### Check Calc Status
```bash
# Inside container
ps aux | grep soffice
ls -la /home/ga/.config/libreoffice/

# Test headless mode
libreoffice --headless --version
```

### Verify File Parsing
```bash
# Test ODS parsing
python3 -c "from odf import opendocument; doc = opendocument.load('file.ods'); print('OK')"

# Test XLSX parsing
python3 -c "from openpyxl import load_workbook; wb = load_workbook('file.xlsx'); print('OK')"
```

## Advanced Configuration

### Custom Preferences

Modify `config/registrymodifications.xcu` to set default preferences:

```xml
<item oor:path="/org.openoffice.Office.Calc/Calculate">
  <prop oor:name="DecimalPlaces" oor:op="fuse">
    <value>2</value>
  </prop>
</item>
