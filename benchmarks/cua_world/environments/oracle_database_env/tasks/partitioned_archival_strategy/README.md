# Task: Oracle Partitioned Archival Strategy for Job History

## Overview

An IT manager at a health informatics company is modernizing the Oracle HR database's archival infrastructure. The `JOB_HISTORY` table (containing all historical employee role changes) lacks range partitioning, making time-based purges and reporting expensive. The manager needs a proper archival table with partitioning, bitmap indexes for low-cardinality reporting columns, and a materialized view for department-level turnover analytics.

## Goal

Complete all 5 of the following steps:

1. **Create `EMPLOYEE_HISTORY_ARCHIVE`** as a range-partitioned table (partition key: `END_DATE`) with at least 4 decade partitions covering different date ranges (e.g., pre-1990, 1990s, 2000s, 2010+). The table must have the same columns as `JOB_HISTORY` (EMPLOYEE_ID, START_DATE, END_DATE, JOB_ID, DEPARTMENT_ID).

2. **Migrate all rows** from `JOB_HISTORY` into `EMPLOYEE_HISTORY_ARCHIVE` using `INSERT INTO ... SELECT FROM`.

3. **Create bitmap indexes** on `JOB_ID` and `DEPARTMENT_ID` columns of the archive table (these are low-cardinality columns ideal for bitmap indexing in a data warehouse workload).

4. **Create a materialized view** named `MV_DEPT_TURNOVER` that shows per-department job change counts from the archive (e.g., `DEPARTMENT_ID`, `JOB_CHANGE_COUNT`).

5. **Save a partition analysis report** to `/home/ga/Desktop/archive_analysis.txt` showing the partition structure and row counts per partition.

## Environment

- **Database**: Oracle XE 21c (container: `oracle-xe`)
- **Schema**: HR (user: `hr`, password: `hr123`)
- **PDB**: XEPDB1 (port 1521)
- **Client**: DBeaver CE (pre-configured)

## JOB_HISTORY Table Structure

```sql
EMPLOYEE_ID   NUMBER(6)    NOT NULL
START_DATE    DATE         NOT NULL
END_DATE      DATE         NOT NULL
JOB_ID        VARCHAR2(10) NOT NULL
DEPARTMENT_ID NUMBER(4)
```

The standard HR schema contains 10 job history records, but the dataset may vary.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| EMPLOYEE_HISTORY_ARCHIVE table created | 10 |
| Table is range-partitioned | 10 |
| ≥4 partitions defined | 10 |
| All JOB_HISTORY rows migrated | 15 |
| Bitmap index on JOB_ID | 10 |
| Bitmap index on DEPARTMENT_ID | 10 |
| MV_DEPT_TURNOVER materialized view exists | 10 |
| MV is queryable and has rows | 5 |
| archive_analysis.txt exists on Desktop | 10 |
| File contains partition/row count data | 10 |
| **Total** | **100** |

Pass threshold: 55 points

## Verification Strategy

The verifier:
1. Queries `USER_TABLES` and `USER_TAB_PARTITIONS` for partition count
2. Counts rows in `EMPLOYEE_HISTORY_ARCHIVE` vs baseline JOB_HISTORY count
3. Queries `USER_INDEXES` filtering `INDEX_TYPE = 'BITMAP'`
4. Queries `USER_MVIEWS` for `MV_DEPT_TURNOVER` compile state
5. Checks `/home/ga/Desktop/archive_analysis.txt` for partition-related content

## Notes

- Oracle XE supports table partitioning (it's included in all editions since 12c)
- For CREATE MATERIALIZED VIEW, you may need `BUILD IMMEDIATE REFRESH COMPLETE`
- Example partition DDL syntax:
  ```sql
  CREATE TABLE employee_history_archive (...) PARTITION BY RANGE (end_date) (
    PARTITION p_pre1990  VALUES LESS THAN (DATE '1990-01-01'),
    PARTITION p_1990s    VALUES LESS THAN (DATE '2000-01-01'),
    PARTITION p_2000s    VALUES LESS THAN (DATE '2010-01-01'),
    PARTITION p_2010plus VALUES LESS THAN (MAXVALUE)
  );
  ```
- Query partition stats: `SELECT partition_name, num_rows FROM user_tab_partitions WHERE table_name = 'EMPLOYEE_HISTORY_ARCHIVE'`
- After `INSERT`, run `DBMS_STATS.GATHER_TABLE_STATS` to update partition row counts
