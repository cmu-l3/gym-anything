"""
Verifier for devtools_cascading_debug task.

Stub verifier — primary evaluation uses vlm_checklist_verifier.

Scoring breakdown (100 points total, pass >= 60):
- Bugs fixed in source code (50 pts, 10 per bug):
    Bug 1: script src app.jss -> app.js (index.html)
    Bug 2: fetch URL employee.json -> employees.json (app.js)
    Bug 3: data property data.employees -> data.staff (app.js)
    Bug 4: CSS class emp-row -> employee-row (app.js)
    Bug 5: event handler filterTable -> searchTable (index.html)
- Incident report (35 pts):
    File exists and valid JSON (10 pts)
    Documents >= 4 issues with required fields (15 pts)
    Report is fresh (created during task) (10 pts)
- Bookmark (15 pts):
    'Development' folder exists (10 pts)
    Contains localhost:8080 bookmark (5 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_devtools_cascading_debug(traj, env_info, task_info):
    """
    Verify that the agent debugged and fixed the cascading bugs in the
    employee directory web application.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable."}

    # Load result JSON from environment
    result_path = "/tmp/devtools_cascading_debug_result.json"
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(result_path, tmp_path)
        with open(tmp_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result from environment: {e}",
        }
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []

    # ── Anti-gaming gate ──
    bugs_fixed = data.get("bugs_fixed", {})
    bugs_fixed_count = data.get("bugs_fixed_count", 0)
    files_modified = data.get("source_files_modified", {})
    report_exists = data.get("incident_report", {}).get("exists", False)

    if bugs_fixed_count == 0 and not any(files_modified.values()) and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No evidence of task completion: no source files modified, no bugs fixed, no report created.",
        }

    # ── Section 1: Bugs fixed (50 pts, 10 each) ──
    bug_names = {
        "bug1_script_src": "Script src typo (app.jss -> app.js)",
        "bug2_fetch_url": "Fetch URL (employee.json -> employees.json)",
        "bug3_data_property": "Data property (data.employees -> data.staff)",
        "bug4_css_class": "CSS class (emp-row -> employee-row)",
        "bug5_handler_name": "Event handler (filterTable -> searchTable)",
    }

    bugs_score = 0
    fixed_list = []
    unfixed_list = []
    for bug_key, bug_desc in bug_names.items():
        if bugs_fixed.get(bug_key, False):
            bugs_score += 10
            fixed_list.append(bug_desc)
        else:
            unfixed_list.append(bug_desc)

    score += bugs_score
    feedback_parts.append(f"Bugs fixed: {bugs_fixed_count}/5 (+{bugs_score})")
    if unfixed_list:
        feedback_parts.append(f"Still broken: {'; '.join(unfixed_list)}")

    # ── Section 2: Incident report (35 pts) ──
    report = data.get("incident_report", {})
    report_score = 0

    if report.get("exists") and report.get("valid_json"):
        report_score += 10
        feedback_parts.append("Incident report: valid JSON (+10)")

        # Check freshness
        if report.get("fresh"):
            report_score += 10
            feedback_parts.append("Report is fresh (+10)")

        # Check issue documentation
        complete_count = report.get("complete_issue_count", 0)
        issue_count = report.get("issue_count", 0)

        if complete_count >= 4:
            report_score += 15
            feedback_parts.append(f"Report documents {complete_count} complete issues (+15)")
        elif complete_count >= 2:
            report_score += 8
            feedback_parts.append(f"Report documents {complete_count} complete issues (+8)")
        elif issue_count > 0:
            report_score += 4
            feedback_parts.append(f"Report has {issue_count} issues but missing required fields (+4)")

    elif report.get("exists"):
        report_score += 3
        feedback_parts.append("Report exists but invalid JSON (+3)")
    else:
        feedback_parts.append("No incident report found at ~/Documents/incident_report.json (+0)")

    score += report_score

    # ── Section 3: Bookmarks (15 pts) ──
    bookmark_score = 0

    if data.get("bookmark_folder_exists"):
        bookmark_score += 10
        feedback_parts.append("'Development' bookmark folder exists (+10)")

        if data.get("bookmark_count", 0) > 0:
            bookmark_score += 5
            feedback_parts.append(f"Folder has {data['bookmark_count']} bookmark(s) (+5)")
    else:
        feedback_parts.append("No 'Development' bookmark folder found (+0)")

    score += bookmark_score

    # ── Final ──
    passed = score >= 60

    status = "PASSED" if passed else "FAILED"
    feedback_parts.insert(0, f"{status} ({score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
