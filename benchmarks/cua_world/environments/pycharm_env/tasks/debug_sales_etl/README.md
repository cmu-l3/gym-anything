# debug_sales_etl

## Overview

**Occupation**: Data Engineers / Data Warehouse Specialists
**Industry**: Retail / E-Commerce Analytics
**Difficulty**: Hard

A Python ETL pipeline (`sales_etl`) that reads daily retail transaction records from a CSV file, applies business-logic transformations (date parsing, discount calculations), and loads results into a SQLite database. The nightly ETL run is producing incorrect figures — the test suite is failing and the reporting dashboard shows wrong discount amounts and unit-sold totals.

The agent must run the test suite, discover which functions contain bugs by reading the test failure output, fix all bugs, and confirm the complete test suite passes.

---

## Goal

All 7 tests in `tests/` must pass with `pytest exit code 0`.

The project is pre-opened in PyCharm. The agent must NOT be told which files or functions contain bugs.

---

## Starting State

The `sales_etl` project is at `/home/ga/PycharmProjects/sales_etl/` and contains:

```
sales_etl/
├── data/sales_sample.csv        # Real retail transaction fixture data (10 rows)
├── etl/
│   ├── extract.py               # CSV reader — no bugs
│   ├── transform.py             # Bug 1: parse_date, Bug 2: apply_discount
│   └── load.py                  # Bug 3: save_transaction INSERT column order
├── tests/
│   ├── conftest.py              # pytest fixtures
│   ├── test_extract.py          # 3 tests — all pass initially
│   ├── test_transform.py        # 5 tests — 2 fail initially
│   └── test_load.py             # 2 tests — 1 fails initially
├── main.py
└── requirements.txt
```

**Initially failing tests** (3 of 7):
- `test_parse_date_iso_format` — Bug 1: wrong `strptime` format string
- `test_apply_discount_ten_percent` — Bug 2: wrong discount formula
- `test_save_and_retrieve_quantity` — Bug 3: INSERT has `quantity`/`unit_price` swapped

---

## Bugs (Ground Truth — do not reveal in task description)

| Bug | File | Function | Description |
|-----|------|----------|-------------|
| 1 | `etl/transform.py` | `parse_date` | Uses `"%m/%d/%Y"` instead of `"%Y-%m-%d"` |
| 2 | `etl/transform.py` | `apply_discount` | Returns `unit_price * discount_pct/100` instead of `unit_price * (1 - discount_pct/100)` |
| 3 | `etl/load.py` | `save_transaction` | `cursor.execute()` tuple has `unit_price` and `quantity` swapped |

---

## Data Sources

The `data/sales_sample.csv` fixture contains 10 rows of retail transaction data representative of the standard e-commerce transaction schema. The data format (ISO 8601 dates, SKU product codes, unit prices in USD, discount percentages) is based on the schema of the UCI Machine Learning Repository Online Retail dataset (Chen et al., 2015 — https://archive.ics.uci.edu/dataset/352/online+retail). Values are illustrative examples consistent with realistic retail price ranges ($50–$500) and discount rates (0–20%).

---

## Verification Strategy

**Criterion 1 (30 pts)**: `bug1_fixed_parse_date` — `etl/transform.py` uses `"%Y-%m-%d"` format and `test_parse_date_iso_format` passes
**Criterion 2 (30 pts)**: `bug2_fixed_apply_discount` — correct formula `unit_price * (1 - discount_pct/100)` and `test_apply_discount_ten_percent` passes
**Criterion 3 (30 pts)**: `bug3_fixed_save_transaction` — INSERT tuple has `quantity` before `unit_price` and `test_save_and_retrieve_quantity` passes
**Criterion 4 (10 pts)**: `no_regression` — all 4 previously-passing tests still pass

**Pass threshold**: 65/100 (agent must fix at least 2 of 3 bugs)

---

## Edge Cases

- The agent must not modify the test files (but the verifier doesn't enforce this)
- All 3 bugs are in different functions/files, requiring independent diagnosis
- Bug 3 (column swap in INSERT) will only surface when actually fetching back the stored row
- Regression check prevents agents from "fixing" bugs by deleting existing passing tests
