# Energy Portfolio Milestone Tracker

## Domain Context

Wind energy development managers oversee portfolios of utility-scale wind farm projects through multi-year development cycles. Each project follows a strict sequence of milestones from site assessment through commercial operation. Data integrity in project tracking systems is critical for regulatory compliance, investor reporting, and construction scheduling. This task reflects real-world project management workflows in the renewable energy industry.

**Occupation**: Wind Energy Development Managers (SOC 11-9199)
**Industry**: Utilities / Renewable Energy
**GDP Contribution**: $17.2B annually

## Task Overview

The ENERGY schema contains project tracking data for 8 real wind farms from the EIA-860 database. The milestone tracking system has data integrity issues that must be resolved before the quarterly board review:

1. **Fix Milestone Sequence Violations**: Four projects have impossible milestone sequences (e.g., "Construction Complete" dated before "Permitting Approved"). Identify and correct the dates to follow the logical sequence: Site Assessment → Environmental Review → Permitting → Financial Close → Construction Start → Grid Interconnection → Construction Complete → Commercial Operation.
2. **Create Hierarchical View**: Build PROJECT_HIERARCHY_VW using CONNECT BY to show Portfolio → Region → Project → Phase → Milestone hierarchy with LEVEL and SYS_CONNECT_BY_PATH.
3. **Create Pivot Dashboard**: Build PORTFOLIO_PIVOT_VW using PIVOT to cross-tabulate projects vs milestone status counts.
4. **Schedule Status Monitoring**: Create DBMS_SCHEDULER job MILESTONE_STATUS_CHECK that runs PROC_CHECK_OVERDUE_MILESTONES to flag overdue milestones in an ALERTS table.
5. **Add Constraint Enforcement**: Add CHECK constraints or triggers to prevent future milestone sequence violations.

## Credentials

- Energy schema: `energy_mgr` / `Energy2024`
- System: `system` / `OraclePassword123`

## Success Criteria

- All 4 contaminated projects have milestones in correct chronological order
- PROJECT_HIERARCHY_VW exists and uses CONNECT BY
- PORTFOLIO_PIVOT_VW exists and uses PIVOT
- MILESTONE_STATUS_CHECK scheduler job exists with PROC_CHECK_OVERDUE_MILESTONES procedure
- ALERTS table exists
- Constraint or trigger prevents future sequence violations
- SQL Developer GUI was used

## Verification Strategy

- **Milestone fixes**: Self-join query checks for any remaining out-of-order milestones per project
- **Views**: ALL_VIEWS checked for existence; view text checked for CONNECT BY and PIVOT keywords
- **Scheduler**: ALL_SCHEDULER_JOBS checked for job existence
- **Procedure**: ALL_PROCEDURES checked for procedure existence
- **Constraints**: ALL_TRIGGERS and ALL_CONSTRAINTS checked for enforcement mechanisms
- **GUI**: SQL history, MRU cache, active sessions

## Schema Reference

```sql
ENERGY_MGR.PORTFOLIO (portfolio_id, portfolio_name, manager)
ENERGY_MGR.REGIONS (region_id, region_name, portfolio_id)
ENERGY_MGR.PROJECTS (project_id, project_name, region_id, capacity_mw, turbine_count, state, county, latitude, longitude, developer, status, eia_plant_code)
ENERGY_MGR.PHASES (phase_id, project_id, phase_name, phase_order, start_date, end_date)
ENERGY_MGR.MILESTONES (milestone_id, phase_id, project_id, milestone_name, milestone_order, target_date, actual_date, status, notes)
ENERGY_MGR.ALERTS (alert_id, project_id, milestone_id, alert_type, alert_message, created_date, acknowledged)
```

## Real Data Sources

Wind farm data sourced from EIA-860 (Energy Information Administration) database:
- Shepherds Flat: 845MW, Oregon (Caithness Energy)
- Alta Wind Energy Center: 1548MW, California (Terra-Gen)
- Roscoe Wind Farm: 781.5MW, Texas (E.ON Climate)
- Horse Hollow Wind Energy Center: 735.5MW, Texas (NextEra Energy)
- Biglow Canyon: 450MW, Oregon (Portland General Electric)
- San Gorgonio Pass: 615MW, California
- Meadow Lake: 801MW, Indiana (EDP Renewables)
- Fowler Ridge: 750MW, Indiana (BP Wind Energy)

## Difficulty: very_hard

The agent must independently:
- Discover which projects have sequence violations (not told which ones)
- Understand milestone dependency logic to correct dates
- Write Oracle CONNECT BY hierarchical queries
- Write PIVOT queries for cross-tabulation
- Configure DBMS_SCHEDULER jobs
- Design constraint enforcement mechanisms
