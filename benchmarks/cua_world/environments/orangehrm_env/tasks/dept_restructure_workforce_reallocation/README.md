# dept_restructure_workforce_reallocation

## Domain Context

**Occupation**: Education Administrators, Postsecondary — managing faculty departmental assignments, tenure track alignment, and research budget allocation in university settings (544M GDP, top OrangeHRM user segment).

**Scenario**: Westbrook University's Engineering department has been voted by the faculty senate to divide into two specialized sub-units: "Engineering - Backend Systems" and "Engineering - Applied Research." The Director of Academic HR must create these organizational units in OrangeHRM and reassign affected faculty members to their new sub-units.

---

## Goal

Read the restructuring directive on the Desktop. Implement the two-step change in OrangeHRM:
1. Create the two new sub-units under "Engineering" in the organization structure
2. Reassign each listed employee to their designated new sub-unit

**End state**: `ohrm_subunit` contains "Engineering - Backend Systems" and "Engineering - Applied Research" as children of Engineering. James Anderson and Christopher Williams are assigned to Backend Systems; Daniel Wilson is assigned to Applied Research.

---

## Why This is Very Hard

- Organization structure management (Admin > Organization > Sub Units) is a non-obvious feature
- The nested-set tree structure in OrangeHRM makes sub-unit creation order-sensitive
- Agent must then separately update each employee's Job tab (PIM > Employee > Job) — a different UI section
- Both steps must be done in the right order (sub-units must exist before employees can be assigned to them)
- Description gives only the goal; agent discovers both UI paths independently

---

## Changes Required

### New Sub-Units (under Engineering)
| Sub-Unit Name | Parent |
|---------------|--------|
| Engineering - Backend Systems | Engineering |
| Engineering - Applied Research | Engineering |

### Employee Reassignments
| Employee | ID | Current Dept | New Dept |
|----------|----|--------------|----------|
| James Anderson | EMP001 | Engineering | Engineering - Backend Systems |
| Christopher Williams | EMP009 | Engineering | Engineering - Backend Systems |
| Daniel Wilson | EMP013 | Engineering | Engineering - Applied Research |

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| "Engineering - Backend Systems" sub-unit exists | 20 |
| "Engineering - Applied Research" sub-unit exists | 20 |
| James Anderson → Engineering - Backend Systems | 20 |
| Christopher Williams → Engineering - Backend Systems | 20 |
| Daniel Wilson → Engineering - Applied Research | 20 |
| **Total** | **100** |

Partial credit (5 pts per employee): employee moved to an Engineering sub-unit but the wrong one.

**Pass threshold**: 70

---

## Strategy Enumeration (Anti-Pattern 4 check)

| Strategy | Backend | Research | James | Chris | Daniel | Total | Pass? |
|----------|---------|----------|-------|-------|--------|-------|-------|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | No |
| Create Backend only + all 3 → Backend | 20 | 0 | 20 | 20 | 5(partial) | 65 | No (< 70) ✓ |
| Both sub-units + 2 correct + Daniel wrong | 40 | — | 20 | 20 | 5 | 85 | Yes (partial pass) ✓ |
| All correct | 20 | 20 | 20 | 20 | 20 | 100 | Yes ✓ |

---

## Verification Strategy

**export_result.sh** checks `ohrm_subunit` for the new sub-unit names, then queries each employee's `work_unit` FK joined to `ohrm_subunit.name`.

**verifier.py** uses substring matching: "Backend Systems" in dept name for James/Chris, "Applied Research" in dept name for Daniel.

---

## Setup State

`setup_task.sh`:
1. Removes any prior "Engineering - Backend Systems" / "Engineering - Applied Research" sub-units (idempotent)
2. Resets EMP001, EMP009, EMP013 `work_unit` back to parent "Engineering" sub-unit id
3. Records baseline sub-unit count
4. Creates `/home/ga/Desktop/dept_restructure_directive.txt`

---

## Schema Reference

```sql
ohrm_subunit:
  id          INT  (PK)
  name        VARCHAR
  unit_id     VARCHAR  (textual unit code)
  description TEXT
  lft, rgt    INT  (nested set tree bounds)
  level       INT  (depth in tree; root=0, top-level=1, ...)

hs_hr_employee:
  emp_number  INT  (PK)
  work_unit   INT  (FK → ohrm_subunit.id)
```

---

## Edge Cases

- Nested set tree (lft/rgt): OrangeHRM rebalances the tree when creating sub-units through the UI. The verifier only checks for name existence and employee assignment — not lft/rgt values.
- Employee lookup is by employee_id with name fallback
- If agent creates sub-units with slightly different names (e.g., "Engineering - Backend" instead of "Engineering - Backend Systems"), verifier will fail the sub-unit check but may still partially credit the employee assignments if the names match "Backend" or "Research" substrings
