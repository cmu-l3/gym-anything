# Microsoft Excel Environment (Windows 11)

This environment provides a Windows 11 VM with Microsoft Excel installed for spreadsheet tasks (formulas, charts, conditional formatting) using **real-world datasets**.

## Environment

- Env ID: `microsoft_excel_env@0.1`
- Base: `windows-11` (QEMU/Apptainer runner)
- Default user: `Docker` / `GymAnything123!`
- Data location in VM: `C:\Users\Docker\Desktop\ExcelTasks\`

## Data Files (Real Sources)

The environment mounts these XLSX files from `examples/microsoft_excel_env/data/` and copies them to the Desktop on boot:

- `us_census_population.xlsx`
  - Source: US Census Bureau API (2010 SF1 + 2020 PL 94-171)
  - Columns include 2020 and 2010 populations, change, and percent change.
- `stock_market_data.xlsx`
  - Source: Stooq CSV export (AAPL.US daily OHLCV), filtered to 2024-01 through 2024-06.
  - Columns: Date (A) ... Close (E).
- `sales_report.xlsx`
  - Source: FRED series `MRTSSM448USS` (Retail Sales: Clothing and Clothing Accessories Stores), from 2018 onward.
  - Revenue values are **millions of dollars** (column E).

To regenerate datasets on the host:

```bash
python create_excel_data.py
```

## Tasks

- `sum_formula@1`
  - Open `us_census_population.xlsx` and add a SUM formula for the Population column.
- `create_chart@1`
  - Open `stock_market_data.xlsx` and insert a line chart for Date vs Close.
- `conditional_formatting@1`
  - Open `sales_report.xlsx` and apply conditional formatting to Revenue (column E).

## Running

```python
import os
os.environ["GYM_ANYTHING_RUNNER"] = "qemu"

from gym_anything.api import from_config

env = from_config("examples/microsoft_excel_env", task_id="sum_formula")
obs = env.reset(seed=42, use_cache=True, cache_level="pre_start", use_savevm=True)
print("SSH:", env._runner.ssh_port)
```

Notes:
- Office/Excel installation happens in the `pre_start` hook and is cached via the `pre_start` checkpoint.
- Task setup launches Excel via an *interactive* scheduled task (Windows Session 0 isolation prevents GUI apps from showing when started directly from SSH).

