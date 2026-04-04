#!/usr/bin/env python3
"""
Verifier for Web Accessibility Audit task.

Scoring (100 points):
- Report file exists and was written after task start: 10 points
- Both ssa.gov and irs.gov visited (browser history): 20 points
- Report mentions both sites explicitly: 10 points
- Report contains WCAG/accessibility vocabulary (≥4 terms): 20 points
- Report contains Lighthouse scores: 15 points
- Report contains severity classification (critical/serious/moderate): 15 points
- Report is substantive (≥800 characters): 10 points

Pass threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/web_accessibility_audit_result.json"
PASS_THRESHOLD = 65


def verify_web_accessibility_audit(traj, env_info, task_info):
    """Verify the Web Accessibility Audit task."""
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
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

        score = 0
        feedback_parts = []
        subscores = {}

        report = result.get("report", {})
        history = result.get("history", {})

        # Criterion 1: Report file exists and was written after task start (10 pts)
        if report.get("exists") and report.get("modified_after_start"):
            score += 10
            subscores["report_exists"] = True
            feedback_parts.append("Accessibility report created after task start (10/10)")
        elif report.get("exists"):
            score += 4
            subscores["report_exists"] = "stale"
            feedback_parts.append("Report exists but may be pre-existing (4/10)")
        else:
            subscores["report_exists"] = False
            feedback_parts.append(
                "Report not found at /home/ga/Desktop/accessibility_audit_report.txt (0/10)"
            )

        # Criterion 2: Both ssa.gov and irs.gov visited in history (20 pts)
        ssa_new = history.get("ssa_new", False)
        irs_new = history.get("irs_new", False)
        ssa_pages = history.get("ssa_pages_visited", 0)
        irs_pages = history.get("irs_pages_visited", 0)
        if ssa_new and irs_new:
            score += 20
            subscores["sites_visited"] = True
            feedback_parts.append(
                f"Both ssa.gov ({ssa_pages} pages) and irs.gov ({irs_pages} pages) visited (20/20)"
            )
        elif ssa_new or irs_new:
            score += 10
            subscores["sites_visited"] = "partial"
            visited = "ssa.gov" if ssa_new else "irs.gov"
            missing = "irs.gov" if ssa_new else "ssa.gov"
            feedback_parts.append(f"Only {visited} visited, {missing} not detected (10/20)")
        else:
            subscores["sites_visited"] = False
            feedback_parts.append("Neither ssa.gov nor irs.gov detected in browser history (0/20)")

        # Criterion 3: Report mentions both sites explicitly (10 pts)
        mentions_ssa = report.get("mentions_ssa", False)
        mentions_irs = report.get("mentions_irs", False)
        if mentions_ssa and mentions_irs:
            score += 10
            subscores["sites_mentioned"] = True
            feedback_parts.append("Report explicitly covers both ssa.gov and irs.gov (10/10)")
        elif mentions_ssa or mentions_irs:
            score += 5
            subscores["sites_mentioned"] = "partial"
            mentioned = "ssa.gov/Social Security" if mentions_ssa else "irs.gov/IRS"
            feedback_parts.append(f"Report mentions only {mentioned} (5/10)")
        else:
            subscores["sites_mentioned"] = False
            feedback_parts.append("Report does not name either site (0/10)")

        # Criterion 4: Report contains WCAG/accessibility vocabulary (20 pts)
        has_vocab = report.get("has_accessibility_vocab", False)
        vocab_found = report.get("vocab_found", [])
        if has_vocab and len(vocab_found) >= 6:
            score += 20
            subscores["accessibility_vocab"] = True
            feedback_parts.append(
                f"Report has rich accessibility vocabulary ({len(vocab_found)} terms) (20/20)"
            )
        elif has_vocab:
            score += 12
            subscores["accessibility_vocab"] = "partial"
            feedback_parts.append(
                f"Report has some accessibility vocabulary ({len(vocab_found)} terms) (12/20)"
            )
        elif len(vocab_found) >= 2:
            score += 6
            subscores["accessibility_vocab"] = "minimal"
            feedback_parts.append(
                f"Report has minimal accessibility terms ({vocab_found}) (6/20)"
            )
        else:
            subscores["accessibility_vocab"] = False
            feedback_parts.append(
                "Report lacks WCAG/accessibility vocabulary (WCAG, ARIA, contrast, etc.) (0/20)"
            )

        # Criterion 5: Report contains Lighthouse scores (15 pts)
        if report.get("has_lighthouse_score"):
            score += 15
            subscores["lighthouse_scores"] = True
            feedback_parts.append("Report includes Lighthouse accessibility scores (15/15)")
        else:
            subscores["lighthouse_scores"] = False
            feedback_parts.append(
                "No Lighthouse accessibility scores detected in report (0/15)"
            )

        # Criterion 6: Report contains severity classification (15 pts)
        has_severity = report.get("has_severity_classification", False)
        severity_found = report.get("severity_terms_found", [])
        if has_severity and len(severity_found) >= 2:
            score += 15
            subscores["severity_classification"] = True
            feedback_parts.append(
                f"Report uses severity classifications ({severity_found[:3]}) (15/15)"
            )
        elif has_severity:
            score += 8
            subscores["severity_classification"] = "partial"
            feedback_parts.append(
                f"Report has some severity terms ({severity_found}) (8/15)"
            )
        else:
            subscores["severity_classification"] = False
            feedback_parts.append(
                "Report lacks severity classification (critical/serious/moderate) (0/15)"
            )

        # Criterion 7: Report is substantive (≥800 characters) (10 pts)
        char_count = report.get("char_count", 0)
        if char_count >= 1500:
            score += 10
            subscores["report_length"] = True
            feedback_parts.append(f"Report is comprehensive ({char_count} chars) (10/10)")
        elif char_count >= 800:
            score += 6
            subscores["report_length"] = "adequate"
            feedback_parts.append(f"Report is adequate length ({char_count} chars) (6/10)")
        elif char_count >= 300:
            score += 3
            subscores["report_length"] = "brief"
            feedback_parts.append(f"Report is too brief ({char_count} chars, need ≥800) (3/10)")
        else:
            subscores["report_length"] = False
            feedback_parts.append(f"Report is too short ({char_count} chars) (0/10)")

        score = min(score, 100)
        passed = score >= PASS_THRESHOLD

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores,
            "debug": {
                "ssa_pages_visited": history.get("ssa_pages_visited", 0),
                "irs_pages_visited": history.get("irs_pages_visited", 0),
                "report_char_count": char_count,
                "vocab_found": vocab_found[:10],
                "severity_found": severity_found,
            },
        }

    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass
