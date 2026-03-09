#!/usr/bin/env python3
"""
Verifier for hr_data_integrity_audit task.

The agent must discover and fix three categories of data quality issues
planted in the HR employee table:
  - Category A: 5 employees (IDs 300-304) with salary outside their job's MIN/MAX range
  - Category B: 4 employees (IDs 305-308) with hire_date in the future
  - Category C: 3 employees (IDs 309-311) with NULL department_id despite having a manager

Scoring (100 points total):
  - Salary violations fixed (IDs 300-304): up to 30 pts (6 pts each)
  - Future hire dates fixed (IDs 305-308): up to 28 pts (7 pts each)
  - NULL department fixed (IDs 309-311):   up to 27 pts (9 pts each)
  - Audit report file exists:              10 pts
  - Report content mentions issues/IDs:     5 pts (bonus)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)


def verify_hr_data_integrity_audit(traj, env_info, task_info):
    """Verify HR data integrity audit task completion."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    planted_salary_ids = set(metadata.get("planted_salary_violation_ids", [300, 301, 302, 303, 304]))
    planted_date_ids   = set(metadata.get("planted_future_date_ids",      [305, 306, 307, 308]))
    planted_dept_ids   = set(metadata.get("planted_null_dept_ids",        [309, 310, 311]))

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Copy result JSON from VM ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/hr_data_integrity_audit_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    if "db_error" in result:
        return {"passed": False, "score": 0, "feedback": f"DB connection error: {result['db_error']}"}

    # ---------------------------------------------------------------
    # Criterion A: Salary violations fixed (30 pts, 6 pts each)
    # "Fixed" = salary now within job MIN/MAX, OR employee was deleted
    # ---------------------------------------------------------------
    sal_remaining = result.get("salary_violations_remaining", len(planted_salary_ids))
    sal_remaining_ids = set(result.get("salary_violations_remaining_ids", []))
    sal_fixed = len(planted_salary_ids) - len(sal_remaining_ids & planted_salary_ids)
    sal_pts = sal_fixed * 6
    score += sal_pts
    subscores["salary_violations_fixed"] = sal_fixed
    if sal_fixed == len(planted_salary_ids):
        feedback_parts.append(f"All {len(planted_salary_ids)} salary violations remediated (+{sal_pts}pts)")
    elif sal_fixed > 0:
        feedback_parts.append(f"{sal_fixed}/{len(planted_salary_ids)} salary violations fixed (+{sal_pts}pts)")
    else:
        feedback_parts.append("No salary violations fixed (0pts)")

    # ---------------------------------------------------------------
    # Criterion B: Future hire dates fixed (28 pts, 7 pts each)
    # ---------------------------------------------------------------
    date_remaining_ids = set(result.get("future_dates_remaining_ids", []))
    date_fixed = len(planted_date_ids) - len(date_remaining_ids & planted_date_ids)
    date_pts = date_fixed * 7
    score += date_pts
    subscores["future_dates_fixed"] = date_fixed
    if date_fixed == len(planted_date_ids):
        feedback_parts.append(f"All {len(planted_date_ids)} future hire dates corrected (+{date_pts}pts)")
    elif date_fixed > 0:
        feedback_parts.append(f"{date_fixed}/{len(planted_date_ids)} future dates fixed (+{date_pts}pts)")
    else:
        feedback_parts.append("No future hire dates fixed (0pts)")

    # ---------------------------------------------------------------
    # Criterion C: NULL department fixed (27 pts, 9 pts each)
    # ---------------------------------------------------------------
    dept_remaining_ids = set(result.get("null_dept_remaining_ids", []))
    dept_fixed = len(planted_dept_ids) - len(dept_remaining_ids & planted_dept_ids)
    dept_pts = dept_fixed * 9
    score += dept_pts
    subscores["null_dept_fixed"] = dept_fixed
    if dept_fixed == len(planted_dept_ids):
        feedback_parts.append(f"All {len(planted_dept_ids)} NULL department issues resolved (+{dept_pts}pts)")
    elif dept_fixed > 0:
        feedback_parts.append(f"{dept_fixed}/{len(planted_dept_ids)} NULL department issues fixed (+{dept_pts}pts)")
    else:
        feedback_parts.append("No NULL department issues fixed (0pts)")

    # ---------------------------------------------------------------
    # Criterion D: Audit report exists (10 pts)
    # ---------------------------------------------------------------
    if result.get("audit_report_exists") and result.get("audit_report_size", 0) >= 100:
        score += 10
        subscores["audit_report"] = True
        feedback_parts.append("Audit report created (+10pts)")
    else:
        subscores["audit_report"] = False
        feedback_parts.append("Audit report not found or empty (0pts)")

    # ---------------------------------------------------------------
    # Criterion E: Report content quality bonus (5 pts)
    # Report should mention employee IDs or issue categories
    # ---------------------------------------------------------------
    report_preview = result.get("audit_report_preview", "")
    if report_preview:
        # Check for mentions of specific IDs or issue categories
        has_ids = bool(re.search(r'\b(300|301|302|303|304|305|306|307|308|309|310|311)\b', report_preview))
        has_categories = bool(re.search(
            r'(salary|hire.date|department|null|future|violation|out.of.range)',
            report_preview, re.IGNORECASE
        ))
        if has_ids and has_categories:
            score += 5
            subscores["report_quality"] = True
            feedback_parts.append("Report contains specific findings (+5pts)")
        else:
            subscores["report_quality"] = False

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No issues fixed",
        "subscores": subscores,
    }
