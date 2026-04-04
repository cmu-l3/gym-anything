# Query Performance Tuning with Explain Plan

## Domain Context

Database Architects and BI Analysts routinely optimize slow-running queries against production Oracle databases. The Oracle SQL Developer Explain Plan feature is the standard tool for understanding query execution paths, identifying full table scans, missing indexes, and inefficient join orders. This task reflects the real workflow of a DBA or performance engineer receiving slow-query tickets and using Explain Plan + index creation to resolve them.

## Task Overview

The development team has reported 5 performance-critical queries documented in the `HR.TUNING_QUERIES` table that are causing application slowdowns. A large test table `HR.PERFORMANCE_ORDERS` (11,449 rows, derived from real HR employee cross-product data) has been created to simulate production load.

Your tasks:

1. **Analyze** each of the 5 queries in `HR.TUNING_QUERIES` using SQL Developer's **Explain Plan** feature (F10 or right-click → Explain Plan)
2. **Identify** the performance bottleneck in each query (most will show TABLE ACCESS FULL due to missing indexes)
3. **Create indexes** to resolve the full table scans — at minimum, create indexes on `ORDER_AMOUNT`, `ORDER_DATE`, and `CUSTOMER_ID` columns of `HR.PERFORMANCE_ORDERS`
4. **Document** your analysis in a tuning report saved to `/home/ga/Documents/exports/tuning_report.txt`

## Credentials

- HR schema: `hr` / `hr123`
- System (for index creation if needed): `system` / `OraclePassword123`

## Success Criteria

- At least 3 indexes created on `HR.PERFORMANCE_ORDERS` columns
- A tuning report file exists at the specified path with content
- Evidence of Explain Plan usage (SQL history, sessions)
- SQL Developer GUI was used

## Verification Strategy

- **Indexes**: `ALL_IND_COLUMNS` queried for indexes on `PERFORMANCE_ORDERS` specific columns
- **Tuning report**: File existence, size, and keyword content checked
- **GUI usage**: SQL history, active sessions evidence

## Schema Reference

```sql
-- Query this table to see the 5 problematic queries:
HR.TUNING_QUERIES (query_id, description, sql_text, performance_issue)

-- The table to optimize queries against:
HR.PERFORMANCE_ORDERS (
    order_id NUMBER,
    customer_id NUMBER,        -- FK to hr.employees
    salesperson_id NUMBER,     -- FK to hr.employees
    order_amount NUMBER(12,2),
    order_date DATE,
    customer_dept_id NUMBER,
    salesperson_dept_id NUMBER
)   -- 11,449 rows
```

## Difficulty: very_hard

Agent must independently:
- Navigate to and use the Explain Plan feature (not a trivial feature to find)
- Determine which indexes are needed from the execution plan output
- Create indexes with appropriate names on the right columns
- Write a substantive analysis report
