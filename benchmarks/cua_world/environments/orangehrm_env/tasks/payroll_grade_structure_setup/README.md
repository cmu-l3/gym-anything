# payroll_grade_structure_setup

## Domain Context

**Occupation**: HR Managers and Compensation/Benefits Specialists in financial services — responsible for maintaining pay grade structures, salary bands, and individual compensation records in HRIS systems (90M GDP, top OrangeHRM user segment).

**Scenario**: ClearPath Financial Services is implementing a new Q3 2025 compensation framework. All legacy pay grades have been cleared from OrangeHRM. The Payroll Administrator must rebuild the grade structure from the approved compensation framework document on the Desktop, set USD salary ranges for each grade, and assign three employees to their appropriate grade with their individual salaries.

---

## Goal

Read the compensation framework document on the Desktop. Perform all three steps in OrangeHRM:
1. Create 3 pay grades (Grade A - Senior, Grade B - Mid-Level, Grade C - Junior)
2. Set the USD minimum and maximum salary for each grade
3. Assign each of 3 employees to their designated pay grade with their individual salary

**End state**: `ohrm_pay_grade` contains 3 new grades. `ohrm_pay_grade_currency` contains USD ranges for each. `hs_hr_emp_basicsalary` contains salary records for EMP001 (Grade A, $105k), EMP002 (Grade B, $75k), EMP003 (Grade C, $50k).

---

## Why This is Very Hard

- Pay grade creation (Admin > Pay Grades) and salary assignment (PIM > Employee > Salary) are separate UI sections
- Must do Admin work first, then PIM work — interdependent subtasks
- 3 grades × 2 boundary values + 3 employee salary entries = 9 data points to enter
- Description gives only the goal; agent must discover both Admin and PIM paths
- Currency (USD) must be explicitly selected in the salary range form

---

## Compensation Framework

### Pay Grades to Create

| Grade Name | Min USD | Max USD |
|------------|---------|---------|
| Grade A - Senior | 90,000 | 140,000 |
| Grade B - Mid-Level | 60,000 | 90,000 |
| Grade C - Junior | 40,000 | 60,000 |

### Employee Salary Assignments

| Employee | ID | Pay Grade | Salary |
|----------|----|-----------|--------|
| James Anderson | EMP001 | Grade A - Senior | $105,000 |
| Sarah Mitchell | EMP002 | Grade B - Mid-Level | $75,000 |
| David Nguyen | EMP003 | Grade C - Junior | $50,000 |

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| "Grade A - Senior" pay grade exists | 5 |
| Grade A USD min ≈ 90,000 (±5,000) | 5 |
| Grade A USD max ≈ 140,000 (±5,000) | 5 |
| "Grade B - Mid-Level" pay grade exists | 5 |
| Grade B USD min ≈ 60,000 (±5,000) | 5 |
| Grade B USD max ≈ 90,000 (±5,000) | 5 |
| "Grade C - Junior" pay grade exists | 5 |
| Grade C USD min ≈ 40,000 (±5,000) | 5 |
| Grade C USD max ≈ 60,000 (±5,000) | 5 |
| James Anderson in Grade A | 10 |
| James Anderson salary ≈ 105,000 (±5,000) | 10 |
| Sarah Mitchell in Grade B | 10 |
| Sarah Mitchell salary ≈ 75,000 (±5,000) | 10 |
| David Nguyen in Grade C | 10 |
| David Nguyen salary ≈ 50,000 (±5,000) | 10 |
| **Total (capped)** | **100** |

**Pass threshold**: 55

---

## Verification Strategy

**export_result.sh** queries `ohrm_pay_grade` for existence, `ohrm_pay_grade_currency` for USD min/max, and `hs_hr_emp_basicsalary` joined to `ohrm_pay_grade` for employee grade+salary pairs.

**verifier.py** uses ±5,000 tolerance on all salary range values. Grade assignment is verified by substring match ("Grade A", "Grade B", "Grade C") in the pay grade name.

---

## Setup State

`setup_task.sh`:
1. Removes "Grade A - Senior", "Grade B - Mid-Level", "Grade C - Junior" pay grades and their currency configs
2. Clears `hs_hr_emp_basicsalary` for EMP001, EMP002, EMP003
3. Ensures USD currency exists in `hs_hr_currency`
4. Creates `/home/ga/Desktop/compensation_framework_q3.txt`

---

## Schema Reference

```sql
ohrm_pay_grade:
  id    INT  (PK)
  name  VARCHAR

ohrm_pay_grade_currency:
  id           INT
  pay_grade_id INT  (FK → ohrm_pay_grade.id)
  currency_id  VARCHAR  ('USD', 'EUR', etc.)
  min_salary   DECIMAL
  max_salary   DECIMAL

hs_hr_emp_basicsalary:
  id                INT  (PK)
  emp_number        INT  (FK → hs_hr_employee)
  pay_grade_id      INT  (FK → ohrm_pay_grade.id)
  currency_id       VARCHAR
  ebsal_basic_salary DECIMAL
  salary_component  VARCHAR
```

---

## Edge Cases

- Verifier awards points even if exact salary is within ±5,000 of expected value (realistic tolerance for agent entering numbers)
- `hs_hr_emp_basicsalary.salary_component` can be any non-empty string (not checked)
- Score can exceed 100 pts before capping (total possible from formula = 45 + 60 = 105)
