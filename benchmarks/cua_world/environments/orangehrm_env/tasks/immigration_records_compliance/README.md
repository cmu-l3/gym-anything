# immigration_records_compliance

## Domain Context

**Occupation**: Medical and Health Services Managers — responsible for HR compliance, regulatory requirements, and personnel record management in healthcare settings (156M GDP, top OrangeHRM user segment).

**Scenario**: Northgate Medical Center is undergoing its annual Joint Commission accreditation audit. All international staff members must have their immigration documents (passports) recorded in OrangeHRM before the audit date. Three employees are flagged as missing passport records.

---

## Goal

For EACH of the three flagged employees, navigate to their employee profile in OrangeHRM and enter their passport information under the Immigration section. The desktop compliance notice specifies the exact passport details for each employee.

**End state**: All three employees have a passport record in OrangeHRM's `hs_hr_emp_passport` table, with the correct passport numbers.

---

## Why This is Very Hard

- The "Immigration" tab is a non-obvious feature within PIM (agent must discover it — not mentioned in description)
- Agent must find 3 specific employees by reading the desktop file, navigate to each profile
- Agent must correctly distinguish passport number fields from date fields
- Feature is genuinely new — unused by all other OrangeHRM benchmark tasks

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| David Nguyen passport record exists | 20 |
| David Nguyen passport number = VNB456123 | 15 |
| Jessica Liu passport record exists | 20 |
| Jessica Liu passport number = EA3456789 | 15 |
| Robert Patel passport record exists | 20 |
| Robert Patel passport number = K3812456 | 15 |
| **Total** | **105 → capped 100** |

**Pass threshold**: 80

**Note**: Expiry date is NOT scored — the year appears in the spec file, making it gameable without actually knowing the passport number. Only the passport NUMBER is evidence the agent read and entered the correct document.

---

## Strategy Enumeration

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing (no passports entered) | 0 | No |
| Add records for wrong employees | 0 | No |
| Add records with wrong passport numbers (all 3 exist) | 3×20 = 60 | No (< 80) |
| 1 correct passport number + 2 wrong-number records | 35+20+20 = 75 | No (< 80) |
| 2 correct passport numbers + 1 wrong-number record | 35+35+20 = 90 | **Yes** |
| All 3 correct passport numbers | 105 → capped 100 | **Yes** |

---

## Verification Strategy

**export_result.sh** queries `hs_hr_emp_passport` for each employee (looked up by employee_id then name fallback), returns:
- `{emp}_has_passport`: boolean record exists
- `{emp}_passport_no`: passport number string
- `{emp}_expiry`: expiry date string (YYYY-MM-DD)
- `{emp}_issue`: issue date string

**verifier.py** checks:
- 20 pts if record exists for employee
- 15 pts if passport number matches exactly (case-insensitive)

---

## Setup State

`setup_task.sh` deletes all rows from `hs_hr_emp_passport` for:
- David Nguyen (EMP003, emp_number looked up at runtime)
- Jessica Liu (EMP006)
- Robert Patel (EMP007)

Creates `/home/ga/Desktop/hr_compliance_audit_notice.txt` with full passport details.

---

## Schema Reference

```sql
hs_hr_emp_passport:
  emp_number       INT    (FK → hs_hr_employee)
  emp_pp_type      VARCHAR  ('Passport', 'Visa', etc.)
  emp_pp_number    VARCHAR  (document number)
  emp_pp_exp_date  DATE
  emp_pp_issue_date DATE
  country_of_issue VARCHAR
  review_date      DATE
  deleted          TINYINT  (0 = active)
```

---

## Edge Cases

- OrangeHRM may use different field names for document type ('PP', 'Passport', etc.) — verifier only checks number, not type
- Employee lookup uses employee_id first, name as fallback in case IDs differ across environments
