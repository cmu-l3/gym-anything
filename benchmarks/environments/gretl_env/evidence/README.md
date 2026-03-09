# Gretl Environment - Evidence Documentation

## Verification Checklist

- [x] Installation script completes without errors (gretl 2022a installed via apt)
- [x] Setup script completes without errors (167 .gdt files available)
- [x] Application is visible in screenshot (Gretl main window confirmed)
- [x] Application is in correct initial state with real data loaded (food.gdt and usa.gdt verified)
- [x] Task setup runs without errors (pre_task hook verified via gretlcli log)
- [x] Task start state is correct (screenshots confirm food.gdt and usa.gdt open in correct state)
- [x] Sufficient evidence that tasks are completable (all menu paths verified)

## Environment Details

- **Application**: Gretl 2022a (GNU Regression, Econometrics and Time-series Library)
- **Installation**: `apt-get install gretl` (Ubuntu 22.04 universe repository)
- **Data**: Real economic survey and macroeconomic datasets

## Dataset Summary

### food.gdt
- **Source**: Hill, Griffiths, Lim - Principles of Econometrics 5th ed., Table 2.1
- **Data type**: Real household survey data
- **Observations**: 40 households
- **Variables**:
  - `food_exp`: weekly food expenditure in dollars (mean=$254.10, SD=$83.39)
  - `income`: weekly income in $100 units (mean=$14.15, SD=$6.36)
- **Uses**: Tasks 1-6, 7 (OLS regression, scatter plot, summary stats, log transform, CSV export, correlation, heteroskedasticity test)

### usa.gdt
- **Source**: Federal Reserve Bank of St. Louis FRED database
- **Data type**: Real quarterly macroeconomic time series
- **Observations**: 103 quarters (1984Q1 to 2009Q3)
- **Variables**:
  - `gdp`: Real GDP in billions of chained 2005 dollars (FRED: GDPC96)
  - `inf`: CPI inflation rate, annualized % (FRED: CPIAUCSL)
- **Uses**: Tasks 8-10 (unit root test, time series plot, ARMA model)

## Evidence Files

### Setup Evidence
- `food_task_start_state.png`: Screenshot confirming food.gdt is loaded with correct variables
- `usa_task_start_state.png`: Screenshot confirming usa.gdt is loaded as quarterly time series
- `pre_start_log_tail.txt`: Last 3000 chars of pre_start hook log (shows gretl installation)
- `post_start_log_tail.txt`: Last 3000 chars of post_start hook log (shows dataset setup and warm-up)
- `dataset_verification.txt`: gretlcli output confirming food.gdt structure and summary statistics

### Interactive Testing Evidence (Phase 6)

| Task | Start State Screenshot | Result Evidence |
|------|----------------------|-----------------|
| 1. run_ols_regression | task1_ols_start_state.png | task1_ols_result.png — R²=0.881, income coeff=12.32*** |
| 2. create_scatter_plot | task2_scatter_start.png | task2_scatter_result.png — scatter plot rendered: food_exp vs income, Y=79.9+12.3X |
| 3. compute_summary_statistics | task3_summary_start.png | task3_summary_results.png — income mean=14.147, food_exp mean=254.10 |
| 4. add_log_transformation | task4_log_start.png | task4_log_result.png — l_food_exp added to var list |
| 5. export_dataset_csv | task5_csv_start.png | task5_csv_output.txt — real CSV data exported |
| 6. compute_correlation_matrix | (food.gdt) | task6_corr_results.png — corr=0.939, t=16.79, p=0.000 |
| 7. run_heteroskedasticity_test | task7_heterosk_start.png | task7_white_test_result.png — TR²=4.49, p=0.106 |
| 8. run_unit_root_test | task8_adf_start.png | task8_adf_result.png — tau_c=-1.63, p=0.468 |
| 9. create_time_series_plot | task9_ts_plot_start.png | task9_ts_plot_result.png — GDP time series plotted |
| 10. estimate_arma_model | task10_arma_start.png | task10_arma_result.png — phi_1=0.837***, R²=0.706 |

## Task Start States

All 10 tasks verified to have correct start states:

| Task | Dataset | Start State |
|------|---------|-------------|
| run_ols_regression | food.gdt | Gretl open, food_exp and income visible, no dialogs |
| create_scatter_plot | food.gdt | Same as above |
| compute_summary_statistics | food.gdt | Same as above |
| add_log_transformation | food.gdt | Same as above |
| export_dataset_csv | food.gdt | Same as above |
| compute_correlation_matrix | food.gdt | Same as above |
| run_heteroskedasticity_test | food.gdt | Same as above |
| run_unit_root_test | usa.gdt | Gretl open, gdp and inf visible, quarterly range 1984:1-2009:3 |
| create_time_series_plot | usa.gdt | Same as above |
| estimate_arma_model | usa.gdt | Same as above |

## Key UI Element Coordinates (1920x1080 actual resolution)

Note: visual_grounding returns 1280x720 coords. Multiply by 1.5 for 1920x1080.

| Element | 1280x720 | 1920x1080 |
|---------|----------|-----------|
| Menu: Model | (306, 57) | (459, 86) |
| Menu: View | (154, 57) | (231, 86) |
| Menu: Variable | (264, 57) | (396, 86) |
| Menu: Add | (184, 57) | (276, 86) |
| food_exp row | (115, 123) | (173, 185) |
| income row | (110, 136) | (165, 204) |
| gdp row | (115, 123) | (173, 185) |
| inf row | (110, 136) | (165, 204) |

## Gretl Workflow Guide

### OLS Regression
GUI: `Model > Ordinary Least Squares > blue arrow sets dep var, green arrow adds regressors > OK`
Console: `ols food_exp 0 income`

### Scatter Plot
`View > Graph specified vars > X-Y scatter > select X and Y vars > OK > File > Save as (PNG)`
Note: must move vars to right panel using green arrow before OK

### Summary Statistics
`View > Summary statistics > select vars > move to right panel > OK > File > Save to file`
Console: `summary income food_exp`

### Log Transformation
Click variable in list > `Add > Logs of selected variables` → new var `l_varname` created (keyboard: Alt+A)

### Export CSV
`File > Save data as > navigate to output dir > choose CSV type > Save`
CLI: `store /path/to/file.csv -c` (in gretlcli batch mode)

### Correlation Matrix
`View > Correlation matrix > move vars to right panel > Tab x7 + Space > File > Save to file`
Console: `corr food_exp income`

### White's Heteroskedasticity Test
Console approach (RECOMMENDED): `ols food_exp 0 income` then `modtest --white`
GUI: Run OLS first via `Model > OLS > OK`, then in results window: `Tests > Heteroskedasticity > White's test`

### ADF Unit Root Test
Console approach (RECOMMENDED): `adf 4 gdp`
GUI: Click gdp in list > `Variable > Unit root tests > Augmented Dickey-Fuller test > OK`

### Time Series Plot
Console approach: `gnuplot gdp --time-series` (opens graph window)
GUI: click variable > `Variable > Graph specified vars > Time series plot > move var to right panel > OK`

### ARIMA Model
Console approach (RECOMMENDED): `arma 1 0 ; inf`
GUI: `Model > Time series > ARIMA > set p/d/q and variable > OK > File > Save to file`

## Agent Tips (from interactive testing)

- **Use Gretl console** (Tools > Gretl console): Most reliable way to run commands. Results appear immediately. Works for OLS, White's test, ADF, correlation, ARMA.
- **GUI variable selection dialogs** (Summary stats, Correlation, Scatter): Must move variables to RIGHT panel using green arrow button before clicking OK.
- **Tab+Space**: Tab 7x + Space approach works for Correlation matrix dialog but NOT for graph/OLS dialogs (Tab counts differ).
- **Coordinate scaling**: visual_grounding returns 1280x720 coords → multiply by 1.5 for actual 1920x1080 click coords.
- **gnuplot in console**: `gnuplot gdp --time-series` opens graph window reliably from gretl console.
- **gretlcli batch**: Works for non-graphical operations. Use `gretlcli -b script.inp`.
