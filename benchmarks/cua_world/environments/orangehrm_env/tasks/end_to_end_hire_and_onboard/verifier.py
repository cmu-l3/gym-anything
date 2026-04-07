#!/usr/bin/env python3
"""
Verifier for end_to_end_hire_and_onboard task.

Context: Execute the full recruitment-to-onboarding pipeline — create a vacancy,
add candidates, process hiring decisions, and complete the new hire's full profile
setup including job assignment, contact details, emergency contact, pay grade,
salary, leave entitlements, and performance review.

Scoring (100 pts total, pass threshold 60):

Recruitment Phase (33 pts):
  - Vacancy created:                                      5 pts
  - All 3 candidates added (3 x 3):                      9 pts
  - Rajesh reached Hired/Offered status:                  7 pts
  - Elena reached Rejected status:                        7 pts
  - Rajesh employee record created (via Hire action):     5 pts

Onboarding Phase (67 pts):
  - Job title set to Senior DevOps Engineer:              5 pts
  - Department set to Engineering:                        5 pts
  - Work email set:                                       5 pts
  - Emergency contact added:                              4 pts
  - Emergency contact name is Priya Krishnamurthy:        3 pts
  - Pay grade 'Grade D - DevOps Senior' created:          5 pts
  - Pay grade USD range correct (±5000):                  5 pts
  - Salary assigned ~$120,000 (±5000):                    8 pts
  - Annual Leave entitlement ~20 days:                    7 pts
  - Sick Leave entitlement ~10 days:                      7 pts
  - Performance review scheduled:                         6 pts
  - Performance review reviewer is EMP001:                4 pts
  - Performance review dates correct:                     3 pts

Total: 100 pts. Pass threshold: 60.
Do-nothing: score=0 (all recruitment data cleared by setup).
"""

import json
import os
import tempfile

TOLERANCE = 5000  # USD tolerance for salary checks


def verify_end_to_end_hire_and_onboard(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/end_to_end_hire_and_onboard_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_path, local_tmp)
        with open(local_tmp, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file '{result_path}': {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.remove(local_tmp)

    score = 0
    feedback = []

    def within(actual, expected, tol=TOLERANCE):
        try:
            return abs(float(actual) - float(expected)) <= tol
        except (TypeError, ValueError):
            return False

    # ===========================================================
    # RECRUITMENT PHASE (33 pts)
    # ===========================================================

    # 1. Vacancy created (5 pts)
    if int(data.get("vacancy_exists", 0)) >= 1:
        score += 5
        feedback.append("PASS: Vacancy created (+5)")
    else:
        feedback.append("FAIL: Vacancy not found (+0)")

    # 2. All 3 candidates added (9 pts)
    for name, key in [
        ("Rajesh", "rajesh_candidate_exists"),
        ("Elena", "elena_candidate_exists"),
        ("Thomas", "thomas_candidate_exists"),
    ]:
        if int(data.get(key, 0)) >= 1:
            score += 3
            feedback.append(f"PASS: {name} candidate added (+3)")
        else:
            feedback.append(f"FAIL: {name} candidate not found (+0)")

    # 3. Rajesh hiring outcome (7 pts)
    rajesh_cv = str(data.get("rajesh_cv_status", "")).upper()
    rajesh_label = str(data.get("rajesh_status_label", "")).upper()
    if "HIRE" in rajesh_cv or "HIRE" in rajesh_label:
        score += 7
        feedback.append(f"PASS: Rajesh hired (status={rajesh_cv}) (+7)")
    elif "OFFER" in rajesh_cv or "OFFER" in rajesh_label:
        score += 5
        feedback.append(f"PARTIAL: Rajesh offered but not hired ({rajesh_cv}) (+5)")
    elif "SHORT" in rajesh_cv:
        score += 2
        feedback.append(f"PARTIAL: Rajesh shortlisted only ({rajesh_cv}) (+2)")
    else:
        feedback.append(f"FAIL: Rajesh status={rajesh_cv} label={rajesh_label} (+0)")

    # 4. Elena rejection (7 pts)
    elena_cv = str(data.get("elena_cv_status", "")).upper()
    if "REJECT" in elena_cv:
        score += 7
        feedback.append("PASS: Elena rejected (+7)")
    elif "SHORT" in elena_cv or "INTERVIEW" in elena_cv:
        score += 3
        feedback.append(f"PARTIAL: Elena status={elena_cv}, not rejected (+3)")
    else:
        feedback.append(f"FAIL: Elena status={elena_cv} (+0)")

    # 5. Employee record created via Hire (5 pts)
    if int(data.get("rajesh_employee_exists", 0)) >= 1:
        score += 5
        feedback.append("PASS: Rajesh employee record created (+5)")
    else:
        feedback.append("FAIL: Rajesh employee record not found (+0)")

    # ===========================================================
    # ONBOARDING PHASE (67 pts)
    # ===========================================================

    # 6. Job title (5 pts)
    job_title = str(data.get("rajesh_job_title", "")).lower()
    if "devops" in job_title:
        score += 5
        feedback.append("PASS: Job title set correctly (+5)")
    elif job_title:
        score += 2
        feedback.append(f"PARTIAL: Job title='{data.get('rajesh_job_title')}' (+2)")
    else:
        feedback.append("FAIL: No job title set (+0)")

    # 7. Department (5 pts)
    dept = str(data.get("rajesh_department", "")).lower()
    if "engineering" in dept:
        score += 5
        feedback.append("PASS: Department set to Engineering (+5)")
    elif dept:
        score += 2
        feedback.append(f"PARTIAL: Department='{data.get('rajesh_department')}' (+2)")
    else:
        feedback.append("FAIL: No department set (+0)")

    # 8. Work email (5 pts)
    email = str(data.get("rajesh_work_email", "")).lower()
    if "rajesh" in email and "@" in email:
        score += 5
        feedback.append("PASS: Work email set (+5)")
    elif "@" in email:
        score += 2
        feedback.append(f"PARTIAL: Work email='{data.get('rajesh_work_email')}' (+2)")
    else:
        feedback.append("FAIL: Work email not set (+0)")

    # 9. Emergency contact (7 pts)
    ec_count = int(data.get("rajesh_ec_count", 0))
    if ec_count >= 1:
        score += 4
        feedback.append("PASS: Emergency contact added (+4)")
        ec_name = str(data.get("rajesh_ec_name", "")).lower()
        if "priya" in ec_name:
            score += 3
            feedback.append("PASS: EC name is Priya Krishnamurthy (+3)")
        else:
            feedback.append(
                f"PARTIAL: EC name='{data.get('rajesh_ec_name')}' (+0)"
            )
    else:
        feedback.append("FAIL: No emergency contact added (+0)")

    # 10. Pay grade created (10 pts)
    pg_exists = int(data.get("pay_grade_exists", 0))
    if pg_exists >= 1:
        score += 5
        feedback.append("PASS: Pay grade 'Grade D - DevOps Senior' created (+5)")
        try:
            pg_min = float(data.get("pay_grade_min", 0))
            pg_max = float(data.get("pay_grade_max", 0))
            if within(pg_min, 95000) and within(pg_max, 145000):
                score += 5
                feedback.append(
                    f"PASS: Pay grade range ${pg_min}-${pg_max} correct (+5)"
                )
            else:
                score += 2
                feedback.append(
                    f"PARTIAL: Pay grade range ${pg_min}-${pg_max} (+2)"
                )
        except (TypeError, ValueError):
            feedback.append("FAIL: Could not parse pay grade range (+0)")
    else:
        feedback.append("FAIL: Pay grade not found (+0)")

    # 11. Salary (8 pts)
    try:
        salary = float(data.get("rajesh_salary", 0))
        if within(salary, 120000):
            score += 8
            feedback.append(f"PASS: Salary=${salary} ≈ $120,000 (+8)")
        elif salary > 0:
            score += 3
            feedback.append(f"PARTIAL: Salary=${salary} (+3)")
        else:
            feedback.append("FAIL: No salary assigned (+0)")
    except (TypeError, ValueError):
        feedback.append("FAIL: Could not parse salary (+0)")

    # 12. Annual Leave entitlement (7 pts)
    try:
        al_days = float(data.get("rajesh_al_days", 0))
        if al_days >= 19.5:
            score += 7
            feedback.append(f"PASS: Annual Leave={al_days} days (+7)")
        elif al_days > 0:
            score += 3
            feedback.append(f"PARTIAL: Annual Leave={al_days} days (+3)")
        else:
            feedback.append("FAIL: No Annual Leave entitlement (+0)")
    except (TypeError, ValueError):
        feedback.append("FAIL: Could not parse AL days (+0)")

    # 13. Sick Leave entitlement (7 pts)
    try:
        sl_days = float(data.get("rajesh_sl_days", 0))
        if sl_days >= 9.5:
            score += 7
            feedback.append(f"PASS: Sick Leave={sl_days} days (+7)")
        elif sl_days > 0:
            score += 3
            feedback.append(f"PARTIAL: Sick Leave={sl_days} days (+3)")
        else:
            feedback.append("FAIL: No Sick Leave entitlement (+0)")
    except (TypeError, ValueError):
        feedback.append("FAIL: Could not parse SL days (+0)")

    # 14. Performance review (13 pts)
    review_count = int(data.get("rajesh_review_count", 0))
    if review_count >= 1:
        score += 6
        feedback.append("PASS: Performance review scheduled (+6)")

        reviewer = str(data.get("rajesh_review_reviewer_empid", "")).strip()
        if reviewer == "EMP001":
            score += 4
            feedback.append("PASS: Reviewer is James Anderson (EMP001) (+4)")
        elif reviewer:
            score += 1
            feedback.append(f"PARTIAL: Reviewer={reviewer}, expected EMP001 (+1)")
        else:
            feedback.append("FAIL: No reviewer assigned (+0)")

        # Check review dates
        review_start = str(data.get("rajesh_review_start", "")).strip()
        review_end = str(data.get("rajesh_review_end", "")).strip()
        review_due = str(data.get("rajesh_review_due", "")).strip()
        dates_correct = (
            "2025-04-01" in review_start
            and "2025-06-30" in review_end
            and "2025-07-15" in review_due
        )
        if dates_correct:
            score += 3
            feedback.append("PASS: Review dates correct (+3)")
        elif review_start or review_end:
            score += 1
            feedback.append(
                f"PARTIAL: Review dates {review_start}–{review_end} due {review_due} (+1)"
            )
        else:
            feedback.append("FAIL: Review dates not set (+0)")
    else:
        feedback.append("FAIL: No performance review scheduled (+0)")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
