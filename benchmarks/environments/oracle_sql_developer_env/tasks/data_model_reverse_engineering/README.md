# Task: Legacy Schema Data Model Reverse Engineering

## Overview

Your organization has inherited a legacy Oracle schema called `LEGACY_OPS` from an acquired company. The schema contains 8 tables with cryptic single-letter abbreviations as names, no primary key constraints on most tables, no foreign key relationships defined, no column comments, and no table-level documentation. The previous DBA left no documentation.

You are a Database Architect. Your job is to reverse-engineer the data model by examining the data, inferring relationships, and documenting the schema thoroughly using Oracle SQL Developer's Data Modeler and SQL features.

## Context

Database architects routinely inherit undocumented legacy schemas during system migrations, acquisitions, and modernization projects. The ability to reverse-engineer a data model — inferring entity relationships from data patterns, naming conventions, and cardinality — is a core skill. Oracle SQL Developer includes a built-in Data Modeler that can reverse-engineer schemas graphically.

## Goal

1. **Explore the LEGACY_OPS schema** — examine all 8 tables (T_CLI, T_ORD, T_ORD_ITM, T_PRD, T_CAT, T_EMP, T_DEPT, T_LOG) to understand their structure and content.

2. **Add Oracle COMMENT statements** to document the tables and their key columns:
   - At minimum: add `COMMENT ON TABLE` for all 8 tables
   - At minimum: add `COMMENT ON COLUMN` for at least 15 columns across the 8 tables
   - Comments must be meaningful (not generic placeholders like "column 1")

3. **Add primary key constraints** to the tables that are missing them:
   - T_CLI: PK on CLI_ID
   - T_ORD: PK on ORD_ID
   - T_PRD: PK on PRD_ID
   - T_CAT: PK on CAT_ID
   - T_EMP: PK on EMP_ID
   - T_DEPT: PK on DEPT_ID

4. **Add foreign key constraints** to document the relationships:
   - T_ORD.CLI_ID references T_CLI.CLI_ID
   - T_ORD.EMP_ID references T_EMP.EMP_ID
   - T_ORD_ITM.ORD_ID references T_ORD.ORD_ID
   - T_ORD_ITM.PRD_ID references T_PRD.PRD_ID
   - T_PRD.CAT_ID references T_CAT.CAT_ID
   - T_EMP.DEPT_ID references T_DEPT.DEPT_ID

5. **Export a schema analysis report** to `/home/ga/Documents/exports/legacy_ops_analysis.txt` containing your findings about what each table represents, the relationships you identified, and a data quality assessment.

## Login Credentials

- **Oracle SQL Developer**: Use "HR Database" connection (hr/hr123) or connect as SYSTEM (system/OraclePassword123)
- The LEGACY_OPS schema has password: `LegacyOps2024`
- You can connect directly as legacy_ops/LegacyOps2024

## LEGACY_OPS Schema Guide

Decode the cryptic table names:
- `T_CLI` → Clients (customers)
- `T_ORD` → Orders
- `T_ORD_ITM` → Order Items (line items)
- `T_PRD` → Products
- `T_CAT` → Product Categories
- `T_EMP` → Employees (sales staff)
- `T_DEPT` → Departments
- `T_LOG` → Activity Log

## Success Criteria

- Table comments exist for all 8 LEGACY_OPS tables
- Column comments exist for at least 15 columns
- Primary key constraints added to at least 4 tables
- Foreign key constraints added for at least 3 relationships
- Schema analysis report file exists with meaningful content (>500 bytes)

## Verification Strategy

1. **Table comments** (25 pts): Count of `COMMENT ON TABLE` entries in ALL_TAB_COMMENTS for LEGACY_OPS
2. **Column comments** (20 pts): Count of meaningful `COMMENT ON COLUMN` entries in ALL_COL_COMMENTS for LEGACY_OPS
3. **Primary key constraints** (20 pts): Count of PK constraints added to LEGACY_OPS tables
4. **Foreign key constraints** (10 pts): Count of FK relationships defined
5. **Schema analysis report** (25 pts): Report exists and has meaningful content

Pass threshold: 60 pts

## Technical Notes

- Add comments: `COMMENT ON TABLE legacy_ops.t_cli IS 'Client/customer master table';`
- Add PK: `ALTER TABLE legacy_ops.t_cli ADD CONSTRAINT pk_t_cli PRIMARY KEY (cli_id);`
- Add FK: `ALTER TABLE legacy_ops.t_ord ADD CONSTRAINT fk_ord_cli FOREIGN KEY (cli_id) REFERENCES legacy_ops.t_cli(cli_id);`
- Check existing comments: `SELECT table_name, comments FROM all_tab_comments WHERE owner='LEGACY_OPS';`
- Check constraints: `SELECT constraint_name, constraint_type FROM all_constraints WHERE owner='LEGACY_OPS';`
- SQL Developer Data Modeler: File → Data Modeler → Import → Import DDL, or use the Connections panel to browse tables

## Schema Reference

Key columns per table:
- T_CLI: CLI_ID, CLI_NM (name), CLI_EMAIL, CLI_REGION, CLI_SINCE
- T_ORD: ORD_ID, CLI_ID (FK→T_CLI), EMP_ID (FK→T_EMP), ORD_DT, ORD_AMT, ORD_STATUS
- T_ORD_ITM: ITM_ID, ORD_ID (FK→T_ORD), PRD_ID (FK→T_PRD), QTY, UNIT_PRC, LINE_TOT
- T_PRD: PRD_ID, PRD_NM, CAT_ID (FK→T_CAT), UNIT_PRC, STOCK_QTY
- T_CAT: CAT_ID, CAT_NM, CAT_DESC
- T_EMP: EMP_ID, EMP_NM, DEPT_ID (FK→T_DEPT), HIRE_DT, SALARY
- T_DEPT: DEPT_ID, DEPT_NM, DEPT_LOC
- T_LOG: LOG_ID, LOG_DT, ENTITY_TYPE, ENTITY_ID, ACTION, USR
