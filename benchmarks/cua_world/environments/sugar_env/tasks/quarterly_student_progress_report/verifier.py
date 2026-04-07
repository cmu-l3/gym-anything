#!/usr/bin/env python3
"""Verifier stub for quarterly_student_progress_report task.

Full verification is handled by VLM checklist verifier.
This stub performs basic structural checks using the export result JSON.
"""

import json
import os
import tempfile


def verify_quarterly_student_progress_report(traj, env_info, task_info):
    """Verify the quarterly progress report task outputs."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/quarterly_progress_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Analysis script exists and has CSV processing logic (10 pts)
    if result.get("script_exists") and result.get("script_size", 0) > 50:
        content = result.get("script_content", "")
        if "class_records" in content and "open" in content:
            score += 10
            feedback.append("Analysis script with CSV I/O found")
        else:
            score += 5
            feedback.append("Script exists but may not read CSV")
    else:
        feedback.append("FAIL: class_analysis.py not found")

    # 2. HTML dashboard exists with table (15 pts)
    if result.get("html_exists"):
        score += 10
        feedback.append("HTML dashboard exists")
        if result.get("html_has_table"):
            score += 5
            feedback.append("HTML contains table elements")
    else:
        feedback.append("FAIL: class_dashboard.html not found")

    # 3. At-risk students identified in HTML (20 pts)
    gt = result.get("ground_truth", {})
    at_risk_count = gt.get("at_risk_count", 0)
    found_html = result.get("at_risk_html_count", 0)
    if at_risk_count > 0 and found_html > 0:
        ratio = found_html / at_risk_count
        pts = int(20 * ratio)
        score += pts
        feedback.append(f"At-risk in HTML: {found_html}/{at_risk_count} ({pts} pts)")
    else:
        feedback.append("No at-risk students found in HTML")

    # 4. Correlation value in HTML (10 pts)
    if result.get("correlation_in_html"):
        score += 10
        feedback.append("Correlation coefficient found in HTML")
    else:
        feedback.append("Correlation value not found in HTML")

    # 5. ODT progress report exists with table (15 pts)
    if result.get("odt_exists"):
        score += 10
        feedback.append("ODT progress report exists")
        if result.get("odt_has_table"):
            score += 5
            feedback.append("ODT contains table")
    else:
        feedback.append("FAIL: progress_report.odt not found")

    # 6. At-risk students listed in ODT (15 pts)
    found_odt = result.get("at_risk_odt_count", 0)
    if at_risk_count > 0 and found_odt > 0:
        ratio = found_odt / at_risk_count
        pts = int(15 * ratio)
        score += pts
        feedback.append(f"At-risk in ODT: {found_odt}/{at_risk_count} ({pts} pts)")
    else:
        feedback.append("No at-risk students found in ODT")

    # 7. Lowest Q4 subject mentioned in ODT (5 pts)
    lowest_subj = gt.get("lowest_q4_subject", "").lower()
    odt_text = result.get("odt_text", "")
    if lowest_subj and lowest_subj in odt_text:
        score += 5
        feedback.append(f"Lowest Q4 subject '{gt['lowest_q4_subject']}' in ODT")
    else:
        feedback.append("Lowest Q4 subject not found in ODT")

    # 8. Sugar Journal entry (10 pts)
    if result.get("journal_found"):
        score += 10
        feedback.append("Journal entry 'Q4 Progress Report' found")
    else:
        feedback.append("Journal entry not found")

    passed = (score >= 75
              and result.get("html_exists", False)
              and result.get("odt_exists", False)
              and result.get("script_exists", False))

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_exists": result.get("script_exists", False),
            "html_exists": result.get("html_exists", False),
            "odt_exists": result.get("odt_exists", False),
            "html_at_risk_found": found_html,
            "odt_at_risk_found": found_odt,
            "journal_found": result.get("journal_found", False),
            "browse_used": result.get("browse_used", False)
        }
    }
