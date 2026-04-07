# Supply Chain Inventory Rebalance

## Domain Context

General and operations managers at consumer goods distributors must continuously optimize inventory levels across multi-warehouse networks. Key challenges include setting correct reorder points based on demand forecasting, calculating Economic Order Quantities (EOQ), identifying rebalancing opportunities between warehouses, and monitoring for stockout risks. This task reflects real-world inventory management workflows performed at distribution companies using Oracle-based ERP systems.

**Occupation**: General and Operations Managers (SOC 11-1021)
**Industry**: Wholesale Trade / Logistics
**GDP Contribution**: $13.2B annually

## Task Overview

The SUPPLY_CHAIN schema contains inventory and demand data for 25 products across 5 US distribution centers. The inventory parameter configuration has critical errors that must be fixed, and new analytical capabilities are needed:

1. **Analyze Demand Patterns**: Using window functions (LAG, LEAD, AVG OVER, STDDEV OVER), analyze 52 weeks of demand history to calculate moving averages, demand variability, and seasonal indices. Write results to DEMAND_ANALYSIS table.
2. **Fix Reorder Parameters**: Correct three types of configuration errors in INVENTORY_PARAMS:
   - 12 SKUs with reorder_point = 0 (causes stockouts)
   - 8 SKUs with safety_stock > 12x average demand (excessive capital)
   - 5 SKUs with lead_time_days = 0 (physically impossible)
   Use the EOQ formula and standard safety stock calculation (z=1.96 for 97.5% service level).
3. **Create Inventory Forecast**: Build INVENTORY_FORECAST_VW using Oracle's MODEL clause to project inventory levels for 13 weeks, accounting for demand, reorder triggers, and replenishment.
4. **Create Rebalance Recommendations**: Build REBALANCE_RECOMMENDATIONS_VW identifying cross-warehouse transfer opportunities using JSON output format.
5. **Schedule Monitoring**: Create DBMS_SCHEDULER job INVENTORY_MONITOR running PROC_CHECK_STOCKOUT_RISK daily, inserting alerts into INVENTORY_ALERTS.

## Credentials

- Supply Chain schema: `sc_manager` / `Supply2024`
- System: `system` / `OraclePassword123`

## Success Criteria

- DEMAND_ANALYSIS table exists with analytical results using window functions
- All zero reorder points corrected (remaining_zero_reorder = 0)
- Excessive safety stock corrected (remaining_excessive_safety = 0)
- Zero lead times corrected (remaining_zero_leadtime = 0)
- INVENTORY_FORECAST_VW exists and uses MODEL clause
- REBALANCE_RECOMMENDATIONS_VW exists and uses JSON functions
- INVENTORY_MONITOR scheduler job exists with PROC_CHECK_STOCKOUT_RISK
- INVENTORY_ALERTS table exists
- SQL Developer GUI was used

## Verification Strategy

- **Demand analysis**: ALL_TABLES checked; row count verified; ALL_SOURCE checked for window function usage
- **Parameter fixes**: Direct COUNT queries for remaining zero/excessive values
- **Forecast view**: ALL_VIEWS checked; view text checked for MODEL keyword
- **Rebalance view**: ALL_VIEWS checked; view text checked for JSON_OBJECT/JSON_ARRAY
- **Scheduler**: ALL_SCHEDULER_JOBS and ALL_PROCEDURES checked
- **GUI**: SQL history, MRU cache, active sessions

## Schema Reference

```sql
SC_MANAGER.WAREHOUSES (warehouse_id, warehouse_name, city, state, region, capacity_units, operating_cost_daily)
SC_MANAGER.PRODUCT_CATEGORIES (category_id, category_name, hs_code, description)
SC_MANAGER.PRODUCTS (product_id, sku, product_name, category_id, unit_cost, unit_price, weight_lbs, is_active)
SC_MANAGER.INVENTORY (inventory_id, warehouse_id, product_id, on_hand_qty, reserved_qty, last_count_date, shelf_location)
SC_MANAGER.INVENTORY_PARAMS (param_id, product_id, warehouse_id, reorder_point, safety_stock, reorder_quantity, lead_time_days, ordering_cost, holding_cost_pct, service_level)
SC_MANAGER.DEMAND_HISTORY (demand_id, product_id, warehouse_id, week_start_date, quantity_demanded, quantity_fulfilled, stockout_flag) -- Composite partitioned by date/warehouse
SC_MANAGER.INVENTORY_ALERTS (alert_id, product_id, warehouse_id, alert_type, alert_message, projected_stockout_date, created_date, resolved)
```

## Real Data Sources

- Product categories use real HS (Harmonized System) commodity codes from US International Trade Commission
- Warehouse locations based on major US distribution hub cities
- Demand patterns follow US Census Bureau retail trade seasonal indices

## Difficulty: very_hard

The agent must independently:
- Write complex window function queries for demand analysis
- Understand and implement the EOQ formula: Q = sqrt(2DS/H)
- Calculate safety stock using z-score * stddev * sqrt(lead_time)
- Use Oracle's MODEL clause (an advanced and rarely-used Oracle feature)
- Implement JSON output using Oracle JSON functions
- Configure DBMS_SCHEDULER with appropriate scheduling
- Understand inventory management domain concepts
