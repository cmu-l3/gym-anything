# Data Sources (Microsoft Excel Env)

All spreadsheets in `benchmarks/environments/microsoft_excel_env/data/` are generated from real, public sources by `create_excel_data.py`.

## 1) `us_census_population.xlsx`

- Source: US Census Bureau APIs
  - 2020 Census PL 94-171 (Redistricting) total population by state:
    - `https://api.census.gov/data/2020/dec/pl?get=NAME,P1_001N&for=state:*`
  - 2010 Census SF1 total population by state:
    - `https://api.census.gov/data/2010/dec/sf1?get=NAME,P001001&for=state:*`
- Notes:
  - Puerto Rico is excluded to match the “states + DC” framing of the task.
  - The file includes rank (by 2020 population), 2020 vs 2010 values, change, and percent change.

## 2) `stock_market_data.xlsx`

- Source: Stooq daily OHLCV CSV for AAPL.US
  - `https://stooq.com/q/d/l/?s=aapl.us&i=d`
- Notes:
  - The file is filtered to a fixed date window (currently 2024-01 through 2024-06) for a manageable but realistic timeseries.
  - Columns are ordered so that `Date` is column A and `Close` is column E (used by the chart task).

## 3) `sales_report.xlsx`

- Source: FRED (Federal Reserve Bank of St. Louis)
  - Series: `MRTSSM448USS` (Retail Sales: Clothing and Clothing Accessories Stores)
  - CSV export:
    - `https://fred.stlouisfed.org/graph/fredgraph.csv?id=MRTSSM448USS`
- Notes:
  - Values are in **millions of dollars**.
  - The file includes data from 2018 onward so the conditional-format thresholds (>10000, <5000) match real variation (including the 2020 dip).

