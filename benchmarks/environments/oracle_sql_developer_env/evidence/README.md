# Oracle SQL Developer Environment - Evidence Documentation

## Environment Overview

**Environment ID**: `oracle_sql_developer_env@0.1`
**Base image**: `ubuntu-gnome-systemd_highres` (1920x1080)
**Purpose**: Oracle SQL Developer IDE with Oracle Database XE 21c for SQL query development, database administration, and schema management tasks.

**Key Components**:
- Oracle SQL Developer 24.3.0.284.2209 (no-jre version)
- OpenJDK 17 + OpenJFX
- Oracle Database XE 21c via Docker (`gvenzl/oracle-xe:21-slim`)
- Oracle HR sample schema (107 employees, 27 departments, 19 jobs)
- SQLcl (Oracle SQL command-line tool)

## Tasks Implemented

### 1. Create Oracle Connection (`create_oracle_connection`) - Easy
**Description**: Create an "HR Database" connection to Oracle XE (localhost:1521/XEPDB1, hr/hr123)
**Verification**: 5 criteria - SQL Dev running, connection config found, Oracle accessible, new connection created, VLM

### 2. Query Employee Salary (`query_employee_salary`) - Medium
**Description**: Query Finance dept (dept 100) employees with salary > $7,000, export to CSV
**Expected**: 5 employees (Greenberg, Faviet, Chen, Sciarra, Urman)
**Verification**: 5 criteria - output file, correct count, known employees, query executed, VLM

### 3. Create Database Table (`create_database_table`) - Medium
**Description**: Create TRAINING_COURSES table with 6 columns, PK/FK constraints, insert 3+ rows
**Verification**: 5 criteria - table exists, correct columns, has data, has constraints, VLM

## Evidence Screenshots

### 01_sql_developer_welcome_page.png
SQL Developer launched with Welcome Page visible. Shows the application fully loaded with:
- Title bar: "Oracle SQL Developer : Welcome Page"
- Left panel: Connections tree
- "Database Detected" notification
- Version: 24.3.0.284.2209

### 02_new_connection_dialog.png
"New / Select Database Connection" dialog opened after clicking green plus icon.

### 03_connection_fields_filled.png
Connection dialog with fields filled: Name="HR Database", Username="hr", Service name="XEPDB1"

### 04_connection_test_success.png
Connection test shows "Status: Success" confirming Oracle XE is accessible.

### 05_connected_to_hr_database.png
Successfully connected to HR Database showing:
- Title bar: "Oracle SQL Developer : HR Database"
- Connections panel: Oracle Connections > HR Database
- SQL Worksheet tab open
- Reports panel visible

## Log Evidence (from log_output.txt)

### Pre-start Hook Output (last lines)
```
=== Installation Complete ===
SQL Developer: INSTALLED
SQLcl: INSTALLED
Docker: Docker version 24.0.7, build 24.0.7-0ubuntu2~22.04.1
Java: openjdk version "17.0.14" 2025-01-21
Oracle XE image: gvenzl/oracle-xe:21-slim
```

### Post-start Hook Output (last lines)
```
HR schema verified: 107 employees
SQL Developer window detected after 45s
SQL Developer ready
=== Oracle SQL Developer Setup Complete ===
Oracle Database XE: localhost:1521
  System: system / OraclePassword123
  HR Schema: hr / hr123
  PDB: XEPDB1
  Employees: 107
```

### HR Schema Statistics
```
REGIONS=4, COUNTRIES=25, LOCATIONS=23, DEPARTMENTS=27, EMPLOYEES=107, JOBS=19
```

## Clean Final Test Results (Phase 7)

All 3 tasks tested with fresh environment boot (no cache):

| Task | Setup OK | Export OK | SQL Dev Running | Oracle OK | Baseline Score |
|------|----------|-----------|-----------------|-----------|----------------|
| create_oracle_connection | Yes | Yes | True | 107 employees | 40/100 |
| query_employee_salary | Yes | Yes | True | 107 employees | 0/100 |
| create_database_table | Yes | Yes | True | 107 employees | 0/100 |

Baseline scores are correct:
- Task 1: 40/100 = SQL Dev running (20pt) + Oracle accessible (20pt), no connection yet
- Task 2: 0/100 = No output file exists yet (early exit)
- Task 3: 0/100 = Table doesn't exist yet (early exit)

### Interactive Test (with ask_cua.py + xdotool)
Completed create_oracle_connection task via:
1. ask_cua.py: Located green "+" button for new connection
2. xdotool: Clicked to open "New / Select Database Connection" dialog
3. ask_cua.py + xdotool: Filled Name, Username, Password fields
4. ask_cua.py: Located Service name radio button
5. xdotool: Switched to Service name, typed "XEPDB1"
6. ask_cua.py + xdotool: Clicked Test (Status: Success), then Connect

**Post-task verification score: 90/100** (4/4 non-VLM criteria passed)

## Real Data Usage

**Oracle HR Sample Schema** (official Oracle sample data):
- Source: Bundled with `gvenzl/oracle-xe:21-slim` Docker image
- Contains realistic employee/department/location data
- 107 employees across 27 departments in 23 locations worldwide
- Complex relationships (employees → departments → locations → countries → regions)
- Job history, salary ranges, manager hierarchies

## Critical Bugs Fixed

### JDK 17 Compatibility (3 crashes)
1. **`factory already defined`**: `--add-opens=java.base/java.net=ALL-UNNAMED`
2. **`IllegalAccessException` for sun.awt**: `--add-opens=java.desktop/sun.awt=ALL-UNNAMED`
3. **`RenderBadPicture` X11 error**: `-Dsun.java2d.xrender=false`

Flags applied in: `sqldeveloper.conf`, `product.conf`, `JAVA_TOOL_OPTIONS`

### SQL Developer 24.3 stores connections in JSON (not XML)
Path: `~/.sqldeveloper/system24.3.0.284.2209/o.jdeveloper.db.connection.24.2.0.284.2209/connections.json`

### Oracle sqlplus output whitespace
Use `tr -d '[:space:]'` not `tr -d ' '` (sqlplus includes tabs)

## Environment Setup Timing
- Pre-start (install): ~170s
- Post-start (setup): ~55s
- Task hooks: ~3s
- Total: ~228s
