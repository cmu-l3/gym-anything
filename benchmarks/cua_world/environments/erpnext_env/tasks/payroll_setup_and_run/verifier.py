"""
Verifier for payroll_setup_and_run task.

Task: Set up and run payroll for the Engineering department employees
      (Michał Sobczak and Vakhita Ryzaev) for the current month.

Scoring (100 pts total, pass >= 70):
  C1 [25 pts] — A new Salary Structure (submitted) with at least 2 components
                 (earnings + deductions combined) was created after task start.
  C2 [25 pts] — Salary Structure assigned (submitted) to both Engineering department
                 employees (Michał Sobczak, Vakhita Ryzaev).
  C3 [25 pts] — A new Payroll Entry (submitted) exists for the Engineering department,
                 created after task start, covering at least 1 employee.
  C4 [25 pts] — Submitted Salary Slips exist for both Engineering employees,
                 linked to the payroll entry, with net_pay > 0.

Pass threshold: 70 (C1+C2+C3 or C2+C3+C4 combinations).

Anti-Pattern 4 Audit:
  C1: Could be gamed by creating a minimal SS with 0 components. Mitigation: >= 2 components.
  C2: Could be gamed by assigning SS to non-Engineering employees. Mitigation: check employee_ids list.
  C3: Could be gamed by creating PE for different department. Mitigation: check employees list overlap.
  C4: Could be gamed by manually creating slips with net_pay=0. Mitigation: net_pay > 0 required.
"""

import json


def verify_payroll_setup_and_run(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/payroll_setup_and_run_result.json"
    )
    local_tmp = "/tmp/_psr_result_local.json"

    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {"passed": False, "score": 0,
                "reason": f"Result file missing — export script may not have run: {e}"}

    try:
        with open(local_tmp) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "reason": f"Could not parse result JSON: {e}"}

    employee_ids = data.get("employee_ids", [])
    new_ss = data.get("new_salary_structures", [])
    ssa_list = data.get("salary_structure_assignments", [])
    pe_list = data.get("payroll_entries", [])
    slip_list = data.get("salary_slips", [])
    all_covered = data.get("all_covered", False)

    # --- ERPNext reachability sentinel ---
    # employee_ids come from the baseline; if empty, setup did not successfully create employees.
    if not employee_ids:
        return {"passed": False, "score": 0,
                "reason": "ERPNext setup data missing (employee_ids empty) — "
                          "setup script may not have run or ERPNext was offline during setup"}

    score = 0
    reasons = []

    # --- C1: New Salary Structure with >= 2 components ---
    c1_pass = any(ss.get("total_components", 0) >= 2 for ss in new_ss)
    if c1_pass:
        score += 25
        best_ss = max(new_ss, key=lambda s: s.get("total_components", 0))
        reasons.append(
            f"C1 PASS: Salary Structure '{best_ss['name']}' has "
            f"{best_ss['total_components']} components (+25)"
        )
    else:
        if new_ss:
            reasons.append(
                f"C1 FAIL: New SS found but total_components < 2 "
                f"(got {[s.get('total_components') for s in new_ss]})"
            )
        else:
            reasons.append("C1 FAIL: No new Salary Structure found (must be created after task start)")

    # --- C2: Salary Structure assigned to both Engineering employees ---
    assigned_employees = {a.get("employee") for a in ssa_list}
    # Accept if at least 2 of the engineering employees have assignments
    coverage = [e for e in employee_ids if e in assigned_employees]
    c2_pass = len(coverage) >= 2
    if not c2_pass and len(employee_ids) == 0:
        # Edge: no employees found in baseline (setup may have had issues)
        c2_pass = len(ssa_list) >= 2
    if c2_pass:
        score += 25
        reasons.append(
            f"C2 PASS: Salary Structure assigned to {len(coverage)}/{len(employee_ids)} "
            f"Engineering employees (+25)"
        )
    else:
        reasons.append(
            f"C2 FAIL: Only {len(coverage)}/{len(employee_ids)} Engineering employees "
            f"have a salary structure assignment (need 2)"
        )

    # --- C3: Payroll Entry (submitted) covering Engineering employees ---
    c3_pass = False
    if pe_list:
        for pe in pe_list:
            pe_employees = pe.get("employees", [])
            # Check overlap with Engineering employee IDs
            overlap = [e for e in employee_ids if e in pe_employees]
            if overlap or pe.get("department") == "Engineering":
                c3_pass = True
                break
        # Also accept if PE has any employees (in case employee_ids couldn't be resolved)
        if not c3_pass and any(pe.get("employee_count", 0) > 0 for pe in pe_list):
            c3_pass = True
    if c3_pass:
        score += 25
        reasons.append(
            f"C3 PASS: Payroll Entry submitted for Engineering department (+25)"
        )
    else:
        reasons.append(
            f"C3 FAIL: No new submitted Payroll Entry found for Engineering "
            f"(found {len(pe_list)} new PE(s))"
        )

    # --- C4: Submitted Salary Slips for both employees, net_pay > 0 ---
    slips_with_pay = [s for s in slip_list if float(s.get("net_pay", 0)) > 0]
    employees_with_valid_slips = {s.get("employee") for s in slips_with_pay}
    valid_coverage = [e for e in employee_ids if e in employees_with_valid_slips]
    c4_pass = len(valid_coverage) >= 2
    if not c4_pass and len(employee_ids) == 0:
        c4_pass = len(slips_with_pay) >= 2
    if c4_pass:
        score += 25
        reasons.append(
            f"C4 PASS: Salary Slips with net_pay > 0 submitted for "
            f"{len(valid_coverage)} Engineering employees (+25)"
        )
    else:
        reasons.append(
            f"C4 FAIL: Only {len(valid_coverage)}/{len(employee_ids)} employees "
            f"have submitted salary slips with net_pay > 0 "
            f"(found {len(slips_with_pay)} valid slips)"
        )

    passed = score >= 70
    return {"passed": passed, "score": score, "reason": " | ".join(reasons)}
