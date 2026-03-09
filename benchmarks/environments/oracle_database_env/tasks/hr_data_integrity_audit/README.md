# Task: HR Data Integrity Audit

## Difficulty: Very Hard

## Occupation Context
**Health Informatics Specialists** (highest Oracle Database GDP: $3.87B) — Backend data management, SQL querying, and database maintenance for health applications. This task reflects a common real-world scenario: auditing a database after a system migration to find and fix multiple categories of data quality issues.

## Task Description

The HR department's Oracle database has accumulated data quality issues following a recent system migration. The agent must:
1. Connect to the HR database
2. Investigate employee data for ALL categories of integrity violations
3. Remediate every issue found
4. Document findings in `/home/ga/Desktop/hr_audit_report.txt`

**Connection:** host=localhost, port=1521, database=XEPDB1, username=hr, password=hr123

## What Makes This Very Hard

- The agent receives no hint about what TYPES of issues exist (must discover independently)
- Multiple issue categories require different SQL queries to detect (JOIN to JOBS table, date comparison, NULL checks)
- Each category requires a different remediation approach
- Agent must track and document all changes
- Discovery-before-fixing pattern with genuine complexity

## Planted Issues (NOT in task description)

The setup script plants exactly 12 employees with 3 categories of issues:

### Category A: Salary range violations (IDs 300-304)
Employees whose salary is outside their job's MIN_SALARY/MAX_SALARY range:
- 300 (Marcus Webb): IT_PROG salary 1200, should be 4000-10000
- 301 (Elena Vasquez): IT_PROG salary 18500, should be 4000-10000
- 302 (Reginald Okafor): SA_REP salary 900, should be 6000-12008
- 303 (Priya Sharma): FI_ACCOUNT salary 25000, should be 4200-9000
- 304 (Antoine Leblanc): PU_CLERK salary 120, should be 2500-5500

**Discovery SQL:** `SELECT e.employee_id, e.salary, j.min_salary, j.max_salary FROM employees e JOIN jobs j ON e.job_id = j.job_id WHERE e.salary < j.min_salary OR e.salary > j.max_salary`

### Category B: Future hire dates (IDs 305-308)
Employees with hire_date after current date (2026-03-04):
- 305 (Yuki Tanaka): hire_date = 2028-01-15
- 306 (Fatima Al-Hassan): hire_date = 2027-06-30
- 307 (Carlos Gutierrez): hire_date = 2027-03-20
- 308 (Amara Diallo): hire_date = 2029-09-10

**Discovery SQL:** `SELECT employee_id, hire_date FROM employees WHERE hire_date > SYSDATE`

### Category C: NULL department with valid manager (IDs 309-311)
Employees with department_id IS NULL despite having a valid manager_id:
- 309 (Victor Petrov): manager=120, dept=NULL
- 310 (Mei Zhang): manager=121, dept=NULL
- 311 (Ibrahim Nkosi): manager=122, dept=NULL

**Discovery SQL:** `SELECT employee_id, manager_id, department_id FROM employees WHERE department_id IS NULL AND manager_id IS NOT NULL`

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Salary violations fixed | 30 | All 5 employees (300-304) in valid range (6 pts each) |
| Future dates fixed | 28 | All 4 employees (305-308) have past dates (7 pts each) |
| NULL dept fixed | 27 | All 3 employees (309-311) have valid dept (9 pts each) |
| Audit report exists | 10 | File at /home/ga/Desktop/hr_audit_report.txt ≥100 bytes |
| Report quality | 5 | Mentions specific IDs + issue categories |
| **Total** | **100** | **Pass threshold: 60 pts** |

## Notes for Evaluators

- Deleting a problematic employee IS accepted as remediation (counts as "fixed")
- Setting salary to job min/max boundary is correct
- For future dates: any past date is acceptable
- For NULL dept: agent must infer the correct department (e.g., from manager's dept)
- The audit report format is flexible — any text documenting findings qualifies
