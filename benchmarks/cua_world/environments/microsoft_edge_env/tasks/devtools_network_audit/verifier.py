#!/usr/bin/env python3
"""
Verifier for DevTools Network Audit task.

Scoring (100 points):
- Report exists and was modified after task start: 15 points
- BBC.com visited (history) AND mentioned in report: 15 points
- Reuters.com visited (history) AND mentioned in report: 15 points
- TheGuardian.com visited (history) AND mentioned in report: 15 points
- Report contains file size values (KB/MB numbers): 20 points
- Report contains request count values: 10 points
- Report is comprehensive (> 800 bytes): 10 points

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/devtools_network_audit_result.json"
PASS_THRESHOLD = 65


def verify_devtools_network_audit(traj, env_info, task_info):
    """Verify the DevTools Network Audit task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run correctly",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

        score = 0
        feedback_parts = []
        subscores = {}

        report = result.get("report", {})
        history = result.get("history", {})

        # Criterion 1: Report exists and was modified after task start (15 pts)
        if report.get("exists") and report.get("modified_after_start"):
            score += 15
            subscores["report_exists"] = True
            feedback_parts.append("Report file created after task start (15/15)")
        elif report.get("exists"):
            score += 5
            subscores["report_exists"] = "stale"
            feedback_parts.append("Report exists but may be pre-existing (5/15)")
        else:
            subscores["report_exists"] = False
            feedback_parts.append("Report file not found at /home/ga/Desktop/network_audit_report.txt (0/15)")

        # Criterion 2: BBC.com — visited AND mentioned in report (15 pts)
        bbc_visited = history.get("bbc_new_visits", False)
        bbc_in_report = report.get("has_bbc", False)
        if bbc_visited and bbc_in_report:
            score += 15
            subscores["bbc"] = True
            feedback_parts.append("BBC.com visited and documented (15/15)")
        elif bbc_visited or bbc_in_report:
            score += 7
            subscores["bbc"] = "partial"
            feedback_parts.append(f"BBC.com partially documented (visited={bbc_visited}, in_report={bbc_in_report}) (7/15)")
        else:
            subscores["bbc"] = False
            feedback_parts.append("BBC.com not visited or not in report (0/15)")

        # Criterion 3: Reuters.com — visited AND mentioned in report (15 pts)
        reuters_visited = history.get("reuters_new_visits", False)
        reuters_in_report = report.get("has_reuters", False)
        if reuters_visited and reuters_in_report:
            score += 15
            subscores["reuters"] = True
            feedback_parts.append("Reuters.com visited and documented (15/15)")
        elif reuters_visited or reuters_in_report:
            score += 7
            subscores["reuters"] = "partial"
            feedback_parts.append(f"Reuters.com partially documented (7/15)")
        else:
            subscores["reuters"] = False
            feedback_parts.append("Reuters.com not visited or not in report (0/15)")

        # Criterion 4: TheGuardian.com — visited AND mentioned in report (15 pts)
        guardian_visited = history.get("guardian_new_visits", False)
        guardian_in_report = report.get("has_guardian", False)
        if guardian_visited and guardian_in_report:
            score += 15
            subscores["guardian"] = True
            feedback_parts.append("TheGuardian.com visited and documented (15/15)")
        elif guardian_visited or guardian_in_report:
            score += 7
            subscores["guardian"] = "partial"
            feedback_parts.append(f"TheGuardian.com partially documented (7/15)")
        else:
            subscores["guardian"] = False
            feedback_parts.append("TheGuardian.com not visited or not in report (0/15)")

        # Criterion 5: Report contains file size values (KB/MB) (20 pts)
        if report.get("has_size_values"):
            score += 20
            subscores["size_values"] = True
            feedback_parts.append("Report contains resource size values (20/20)")
        else:
            subscores["size_values"] = False
            feedback_parts.append("Report missing resource size values in KB/MB (0/20)")

        # Criterion 6: Report contains request count information (10 pts)
        if report.get("has_request_count"):
            score += 10
            subscores["request_count"] = True
            feedback_parts.append("Report contains request count data (10/10)")
        else:
            subscores["request_count"] = False
            feedback_parts.append("Report missing request count information (0/10)")

        # Criterion 7: Report is comprehensive (> 800 bytes) (10 pts)
        report_size = report.get("size_bytes", 0)
        if report_size >= 800:
            score += 10
            subscores["comprehensive"] = True
            feedback_parts.append(f"Report is comprehensive ({report_size} bytes) (10/10)")
        elif report_size >= 300:
            score += 5
            subscores["comprehensive"] = "partial"
            feedback_parts.append(f"Report is brief ({report_size} bytes) — expected > 800 bytes (5/10)")
        else:
            subscores["comprehensive"] = False
            feedback_parts.append(f"Report too short or empty ({report_size} bytes) (0/10)")

        score = min(score, 100)
        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
        }

    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
