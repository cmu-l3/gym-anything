# Analytics Data Warehouse Build

## Domain Context

Data Warehousing Specialists and BI Analysts regularly build dimensional data warehouses on top of operational systems. A star schema — with a central fact table surrounded by dimension tables — is the foundation of most business intelligence platforms. This task reflects the real workflow of transforming HR operational data into an analytics-ready dimensional model, a task performed routinely in organizations using Oracle-based analytics infrastructure.

## Task Overview

Build an analytics data warehouse using the pre-loaded staging tables in the ANALYTICS schema. The staging tables (STG_EMPLOYEES, STG_DEPARTMENTS, STG_JOBS, STG_JOB_HISTORY) have been loaded from the HR operational system.

Your deliverables:

1. **Star Schema Design and Implementation**: Create a fact table `FACT_EMPLOYEE_SNAPSHOT` and at least 3 dimension tables. Required dimensions: `DIM_DEPARTMENT`, `DIM_JOB`. Third dimension is your design choice (e.g., `DIM_TIME`, `DIM_SALARY_BAND`, `DIM_LOCATION`).
2. **Data Loading**: Populate all tables by transforming data from the STG_* staging tables using INSERT...SELECT statements.
3. **Analytical View**: Create a view named `RPT_DEPT_SALARY_SUMMARY` that shows department name, employee headcount, total salary, and average salary per department.

## Credentials

- Analytics schema: `analytics` / `Analytics2024`
- HR source data: `hr` / `hr123`
- System (if needed): `system` / `OraclePassword123`

## Success Criteria

- A fact table (FACT_EMPLOYEE_SNAPSHOT or similar) exists in the ANALYTICS schema with data
- At least 2 required dimension tables (DIM_DEPARTMENT and DIM_JOB) exist in ANALYTICS
- The fact table contains at least 50 rows
- The `RPT_DEPT_SALARY_SUMMARY` view exists and returns data

## Verification Strategy

- **Fact table**: `ALL_TABLES` queried for FACT_* tables in ANALYTICS schema
- **Dimension tables**: Checked for DIM_DEPARTMENT and DIM_JOB in ANALYTICS schema
- **Data volume**: Row count on fact table checked for >= 50 rows
- **View**: `ALL_VIEWS` checked for RPT_DEPT_SALARY_SUMMARY; data returned from it
- **GUI usage**: SQL Developer history and session evidence

## Schema Reference

```sql
-- Staging tables (pre-loaded, use these as source):
ANALYTICS.STG_EMPLOYEES  -- 107 rows; columns mirror hr.employees
ANALYTICS.STG_DEPARTMENTS -- 27 rows; columns mirror hr.departments
ANALYTICS.STG_JOBS         -- 19 rows; columns mirror hr.jobs
ANALYTICS.STG_JOB_HISTORY  -- ~10 rows; columns mirror hr.job_history
```

## Difficulty: very_hard

Agent must independently design and implement:
- Star schema architecture (no prescribed table structure)
- ETL queries (no sample code given)
- Analytical view logic (aggregation/join structure)
