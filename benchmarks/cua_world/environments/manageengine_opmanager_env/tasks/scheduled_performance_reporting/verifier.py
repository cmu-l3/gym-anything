#!/usr/bin/env python3
"""Verifier for scheduled_performance_reporting task.

Scoring (100 pts total, pass at 61):
  - Infrastructure-Availability-Report name found:    30 pts
  - Infrastructure-Availability-Report email correct: 20 pts  (it-ops@company.internal)
  - Executive-Performance-Summary name found:         30 pts
  - Executive-Performance-Summary email correct:      20 pts  (it-executive@company.internal)

Anti-pattern 4 check:
  Max partial (both names, no emails): 30 + 30 = 60 < 61 threshold ✓
  One complete report + other name: 50 + 30 = 80 ≥ 61 → PASS ✓
  Both complete: 100 ✓
"""
import json


# ---------------------------------------------------------------------------
# Target report definitions
# ---------------------------------------------------------------------------
REPORT_1_NAME  = "infrastructure-availability-report"
REPORT_1_EMAIL = "it-ops@company.internal"

REPORT_2_NAME  = "executive-performance-summary"
REPORT_2_EMAIL = "it-executive@company.internal"


def _text_contains(haystack: str, needle: str) -> bool:
    """Case-insensitive substring search."""
    return needle.lower() in haystack.lower()


def _search_all(data: dict) -> str:
    """Return a single lower-cased string of everything in the result dict."""
    return json.dumps(data).lower()


def _check_report_name(combined_text: str, name: str) -> bool:
    """Return True if the report name (case-insensitive) appears in any data source."""
    return name.lower() in combined_text


def _check_email(combined_text: str, email: str) -> bool:
    """Return True if the email address (case-insensitive) appears near the report name."""
    return email.lower() in combined_text


def _check_report_with_email(combined_text: str, name: str, email: str) -> bool:
    """
    Return True only when both the report name AND email appear together.
    We use a proximity window: search in a 2 000-character window around the name occurrence.
    """
    lower_text = combined_text.lower()
    lower_name  = name.lower()
    lower_email = email.lower()

    idx = lower_text.find(lower_name)
    if idx == -1:
        return False

    # Check within a generous window (2000 chars each side)
    window_start = max(0, idx - 2000)
    window_end   = min(len(lower_text), idx + len(lower_name) + 2000)
    window = lower_text[window_start:window_end]
    return lower_email in window


def verify_scheduled_performance_reporting(traj, env_info, task_info):
    """Main verifier entry point."""
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/reporting_result.json")
    local_path  = "/tmp/reporting_verify_result.json"

    # -----------------------------------------------------------------------
    # Retrieve the result file from the environment
    # -----------------------------------------------------------------------
    try:
        env_info["copy_from_env"](result_file, local_path)
    except Exception as e:
        return {
            "passed":   False,
            "score":    0,
            "feedback": (
                f"Could not retrieve result file '{result_file}': {e}. "
                "Ensure export_result.sh ran successfully."
            ),
        }

    # -----------------------------------------------------------------------
    # Parse the result file
    # -----------------------------------------------------------------------
    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed":   False,
            "score":    0,
            "feedback": f"Could not parse result file: {e}",
        }

    # Build a single searchable string from all collected data
    combined_text = _search_all(data)

    score   = 0
    details = []

    # -----------------------------------------------------------------------
    # Criterion 1a — Infrastructure-Availability-Report name exists (30 pts)
    # -----------------------------------------------------------------------
    r1_name_found = _check_report_name(combined_text, REPORT_1_NAME)
    if r1_name_found:
        score += 30
        details.append(
            "PASS: Report 'Infrastructure-Availability-Report' name found (+30)"
        )
    else:
        details.append(
            "FAIL: Report 'Infrastructure-Availability-Report' not found in any data source (0/30)"
        )

    # -----------------------------------------------------------------------
    # Criterion 1b — Infrastructure-Availability-Report email correct (20 pts)
    # -----------------------------------------------------------------------
    if r1_name_found:
        r1_email_ok = _check_report_with_email(combined_text, REPORT_1_NAME, REPORT_1_EMAIL)
        if not r1_email_ok:
            # Fallback: check if email appears anywhere (less strict)
            r1_email_ok = _check_email(combined_text, REPORT_1_EMAIL)
        if r1_email_ok:
            score += 20
            details.append(
                f"PASS: 'Infrastructure-Availability-Report' email '{REPORT_1_EMAIL}' correct (+20)"
            )
        else:
            details.append(
                f"FAIL: Email '{REPORT_1_EMAIL}' not found for Infrastructure-Availability-Report (0/20)"
            )
    else:
        details.append(
            f"SKIP: Cannot check email for Infrastructure-Availability-Report (report not found) (0/20)"
        )

    # -----------------------------------------------------------------------
    # Criterion 2a — Executive-Performance-Summary name exists (30 pts)
    # -----------------------------------------------------------------------
    r2_name_found = _check_report_name(combined_text, REPORT_2_NAME)
    if r2_name_found:
        score += 30
        details.append(
            "PASS: Report 'Executive-Performance-Summary' name found (+30)"
        )
    else:
        details.append(
            "FAIL: Report 'Executive-Performance-Summary' not found in any data source (0/30)"
        )

    # -----------------------------------------------------------------------
    # Criterion 2b — Executive-Performance-Summary email correct (20 pts)
    # -----------------------------------------------------------------------
    if r2_name_found:
        r2_email_ok = _check_report_with_email(combined_text, REPORT_2_NAME, REPORT_2_EMAIL)
        if not r2_email_ok:
            # Fallback: check if email appears anywhere (less strict)
            r2_email_ok = _check_email(combined_text, REPORT_2_EMAIL)
        if r2_email_ok:
            score += 20
            details.append(
                f"PASS: 'Executive-Performance-Summary' email '{REPORT_2_EMAIL}' correct (+20)"
            )
        else:
            details.append(
                f"FAIL: Email '{REPORT_2_EMAIL}' not found for Executive-Performance-Summary (0/20)"
            )
    else:
        details.append(
            f"SKIP: Cannot check email for Executive-Performance-Summary (report not found) (0/20)"
        )

    # -----------------------------------------------------------------------
    # Final verdict (pass threshold: 61 pts — prevents gaming with names-only = 60 pts)
    # -----------------------------------------------------------------------
    passed = score >= 61
    return {
        "passed":   passed,
        "score":    score,
        "feedback": " | ".join(details),
    }
