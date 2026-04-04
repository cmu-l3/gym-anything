# Demand Forecast & Inventory Optimization Model

**Environment**: microsoft_excel_env
**Difficulty**: Very Hard
**Occupation**: Logisticians (SOC 13-1081)
**Industry**: Manufacturing / Industrial Supply Chain

## Task Overview

The agent receives an inventory planning workbook (`demand_inventory.xlsx`) with 24 months of real Federal Reserve Industrial Production indices for 20 manufacturing subsectors. The agent must implement demand forecasting (moving average and exponential smoothing), compute optimal inventory parameters using the Economic Order Quantity (EOQ) model, and perform an ABC classification analysis.

## Domain Context

Demand forecasting and inventory optimization are core supply chain management functions. The EOQ model (Harris 1913, Wilson formula) minimizes total inventory costs by balancing ordering costs against holding costs. Safety stock calculations ensure a target service level (95%) against demand variability. ABC classification (Pareto 80/20 rule) prioritizes cycle counting effort by revenue contribution.

## Data Sources

**Historical Sales Data** (Sheet 1, pre-filled, 20 SKUs x 24 months):
- Source: Federal Reserve Bank of St. Louis FRED
- Series: IPMAN, IPG3361T3S, IPG334S, IPG3254S, IPG325S, IPG332S, IPG333S, IPG335S, IPG336S, IPG311S, IPG312S, IPG321S, IPG322S, IPG323S, IPG326S, IPG327S, IPG331S, IPG337S, IPG339S, IPMANSICS
- Period: January 2022 - December 2023 (real monthly index values)
- URL: https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}

**Unit Costs**: BLS Producer Price Index commodity prices, December 2023
**Holding Cost Percentages**: APICS CPIM published benchmarks (A=25%, B=20%, C=15%)
**Lead Times**: ISM Report on Business December 2023
**Order Costs**: Aberdeen Group 2023 purchase order cost benchmarks

## Required Analysis

### Forecast_Sheet
Average monthly demand, standard deviation, 3-month moving average forecast, exponential smoothing (alpha=0.3), MAE for both methods, best method selection, Jan-Mar 2024 projections.

### Inventory_Parameters
Annual demand, EOQ = sqrt(2DS/H), safety stock at 95% (z=1.645), reorder point, min/max levels, annual holding/ordering/total costs, inventory turns. TOTAL row.

### ABC_Analysis
Annual revenue, cumulative percentage, ABC class assignment (A: top 80%, B: next 15%, C: bottom 5%), cycle count frequency (Monthly/Quarterly/Annual).

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Avg Monthly Demand for >= 16 of 20 SKUs | 20 | Values in [20, 200] |
| EOQ values for >= 16 of 20 SKUs | 20 | Values in [5, 5000] |
| >= 12 EOQ values within 20% of ground truth | 20 | Correct EOQ formula |
| Total annual inventory cost in [$50K, $200K] | 20 | Expected ~$83K |
| ABC classes: >= 4 A, >= 4 B, >= 3 C | 20 | Pareto distribution |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank)

## Why This Is Hard

- Exponential smoothing requires recursive formula across 24 periods per SKU
- EOQ formula requires combining data from multiple columns
- Safety stock requires z-score, daily demand std dev conversion, and lead time
- ABC analysis requires revenue ranking, cumulative percentages, and conditional classification
- 20 SKUs x 24 months = 480 data points to process
- 4 interconnected sheets with cross-references
