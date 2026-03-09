#!/usr/bin/env python3
"""Verifier for add_study_site task."""

import json
import tempfile
import os
import logging
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vlm_utils import query_vlm as _query_vlm_direct

logger = logging.getLogger(__name__)


def _build_vlm_prompt():
    """Build VLM prompt to verify site creation and subject enrollment in OpenClinica."""
    return """Examine this screenshot of OpenClinica (a clinical trial management system).

Check the following:
1. Is OpenClinica visible in Firefox (not an error page, login page, or blank page)?
2. Is there a success message, confirmation banner, or site/subject details page visible?
3. Can you see any of the following: 'Boston Heart Institute', 'CV-BHI-001', 'CV-101', or 'CV-102' anywhere on the page?
4. Does the page show a study site list, subject list, subject details, or a success confirmation?

Respond in JSON format:
{
    "openclinica_visible": true/false,
    "success_message_visible": true/false,
    "site_or_subject_visible": true/false,
    "subject_list_or_details_visible": true/false,
    "page_description": "brief description of what you see",
    "confidence": "low"/"medium"/"high"
}
"""


def _verify_with_vlm(screenshot_path, query_vlm_func):
    """Run VLM verification on the final screenshot."""
    if not query_vlm_func:
        return {"success": False, "error": "VLM not available"}

    if not os.path.exists(screenshot_path):
        return {"success": False, "error": f"Screenshot not found: {screenshot_path}"}

    vlm_result = query_vlm_func(prompt=_build_vlm_prompt(), image=screenshot_path)
    if not vlm_result.get("success"):
        return {"success": False, "error": vlm_result.get("error", "VLM query failed")}

    parsed = vlm_result.get("parsed", {})
    return {
        "success": True,
        "openclinica_visible": parsed.get("openclinica_visible", False),
        "success_message_visible": parsed.get("success_message_visible", False),
        "site_or_subject_visible": parsed.get("site_or_subject_visible", False),
        "subject_list_or_details_visible": parsed.get("subject_list_or_details_visible", False),
        "confidence": parsed.get("confidence", "low"),
    }


def _safe_int(value, default=0):
    """Safely convert a value to int."""
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return default
    return default


def _check_dob(dob_str, expected_year, expected_month, expected_day):
    """
    Check if a date-of-birth string matches expected values.
    Returns (exact_match: bool, year_match: bool).
    """
    if not dob_str:
        return False, False
    try:
        # Strip time portion if present (e.g. "1952-03-18 00:00:00")
        dob_clean = dob_str.strip().split("T")[0].split(" ")[0]
        dob_date = datetime.strptime(dob_clean, "%Y-%m-%d").date()
        year_match = dob_date.year == expected_year
        exact_match = (
            year_match
            and dob_date.month == expected_month
            and dob_date.day == expected_day
        )
        return exact_match, year_match
    except (ValueError, AttributeError):
        # Fallback: check string containment
        year_match = str(expected_year) in dob_str
        date_str = f"{expected_year}-{expected_month:02d}-{expected_day:02d}"
        return date_str in dob_str, year_match


def verify_add_study_site(traj, env_info, task_info):
    """
    Verify that a study site was added and subjects enrolled in OpenClinica.

    Scoring breakdown (100 pts total before VLM):
      Criterion 1 — Site found in DB                        : 30 pts
      Criterion 2 — Site protocol ID is CV-BHI-001          : 10 pts
      Criterion 3 — CV-101 enrolled at parent study          : 25 pts
                    (partial 10 pts if found, wrong demo)
      Criterion 4 — CV-102 enrolled (site or parent)         : 25 pts
                    (bonus +5 pts if enrolled at site level)
      VLM visual check                                       : up to 10 pts
      Audit penalty                                          : -20 pts if no GUI interaction

    Pass threshold: 70 points
    """

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # -------------------------------------------------------------------------
    # Load result JSON from environment
    # -------------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/add_study_site_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # -------------------------------------------------------------------------
    # Verify nonce integrity
    # -------------------------------------------------------------------------
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, "r") as f:
            expected_nonce = f.read().strip()
    except Exception:
        expected_nonce = ""
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    result_nonce = result.get("result_nonce", "")
    if expected_nonce and result_nonce != expected_nonce:
        return {
            "passed": False,
            "score": 0,
            "feedback": "INTEGRITY FAIL: Result file nonce mismatch — possible tampering",
        }

    # -------------------------------------------------------------------------
    # Extract values
    # -------------------------------------------------------------------------
    score = 0
    feedback_parts = []

    site_found = result.get("site_found", False)
    site_name = result.get("site_name", "").strip()
    site_protocol_id = result.get("site_protocol_id", "").strip()
    site_pi = result.get("site_pi", "").strip()
    site_protocol_id_correct = result.get("site_protocol_id_correct", False)

    cv101_found = result.get("cv101_found", False)
    cv101_gender = result.get("cv101_gender", "").strip().lower()
    cv101_dob = result.get("cv101_dob", "").strip()
    cv101_gender_correct = result.get("cv101_gender_correct", False)
    cv101_dob_correct = result.get("cv101_dob_correct", False)

    cv102_found = result.get("cv102_found", False)
    cv102_at_site = result.get("cv102_at_site", False)
    cv102_gender = result.get("cv102_gender", "").strip().lower()
    cv102_dob = result.get("cv102_dob", "").strip()
    cv102_gender_correct = result.get("cv102_gender_correct", False)
    cv102_dob_correct = result.get("cv102_dob_correct", False)

    initial_site_count = _safe_int(result.get("initial_site_count", 0))
    current_site_count = _safe_int(result.get("current_site_count", 0))
    initial_subject_count = _safe_int(result.get("initial_subject_count", 0))
    current_subject_count = _safe_int(result.get("current_subject_count", 0))

    # -------------------------------------------------------------------------
    # Criterion 1: Boston Heart Institute site exists (30 pts)
    # -------------------------------------------------------------------------
    if site_found:
        score += 30
        # Check name quality
        site_name_lower = site_name.lower()
        if "boston" in site_name_lower and "heart" in site_name_lower:
            feedback_parts.append(f"Site found with correct name: '{site_name}'")
        elif "boston" in site_name_lower or "heart" in site_name_lower:
            feedback_parts.append(f"Site found but name only partially matches: '{site_name}'")
        else:
            feedback_parts.append(f"Site found but name differs from expected: '{site_name}'")
        # Check site is new (count increased)
        if current_site_count > initial_site_count:
            feedback_parts.append("Site count increased (newly added)")
        else:
            feedback_parts.append("Note: Site count unchanged — may have existed before setup")
    else:
        feedback_parts.append("FAIL: No site found under CV Registry (parent_study_id check failed)")
        # Hard fail — everything else is moot without the site
        # Still check subjects in case they were enrolled anyway
        # Fall through to allow partial scoring for subjects

    # -------------------------------------------------------------------------
    # Criterion 2: Site protocol ID is CV-BHI-001 (10 pts)
    # -------------------------------------------------------------------------
    if site_found:
        if site_protocol_id_correct:
            score += 10
            feedback_parts.append(f"Site protocol ID correct: '{site_protocol_id}'")
        elif site_protocol_id:
            feedback_parts.append(
                f"Site protocol ID set but incorrect: '{site_protocol_id}' (expected 'CV-BHI-001')"
            )
        else:
            feedback_parts.append("Site protocol ID not set")

        # PI sub-check (informational, not scored separately but noted)
        if site_pi:
            if "chen" in site_pi.lower():
                feedback_parts.append(f"Site PI correct: '{site_pi}'")
            else:
                feedback_parts.append(f"Site PI set but differs: '{site_pi}' (expected 'Dr. Sarah Chen')")
        else:
            feedback_parts.append("Site PI not set")

    # -------------------------------------------------------------------------
    # Criterion 3: CV-101 enrolled at parent study level (25 pts)
    # Partial 10 pts if found but demographics are wrong
    # -------------------------------------------------------------------------
    if cv101_found:
        # Validate demographics
        cv101_exact_dob, cv101_year_dob = _check_dob(cv101_dob, 1952, 3, 18)
        cv101_gender_ok = cv101_gender.startswith("m")

        if cv101_gender_ok and cv101_exact_dob:
            score += 25
            feedback_parts.append(
                f"CV-101 enrolled at parent study with correct demographics (gender={cv101_gender}, dob={cv101_dob})"
            )
        elif cv101_gender_ok and cv101_year_dob:
            score += 18
            feedback_parts.append(
                f"CV-101 enrolled at parent study; gender correct, DOB year correct but date off (dob={cv101_dob})"
            )
        elif cv101_gender_ok or cv101_exact_dob:
            score += 14
            feedback_parts.append(
                f"CV-101 enrolled at parent study; partial demographics match "
                f"(gender={cv101_gender}, dob={cv101_dob})"
            )
        else:
            score += 10
            feedback_parts.append(
                f"CV-101 found at parent study but demographics incorrect "
                f"(gender={cv101_gender}, dob={cv101_dob})"
            )
    else:
        feedback_parts.append("FAIL: CV-101 not found enrolled in parent CV Registry study")

    # -------------------------------------------------------------------------
    # Criterion 4: CV-102 enrolled (25 pts base + 5 pts bonus if at site)
    # -------------------------------------------------------------------------
    if cv102_found:
        cv102_exact_dob, cv102_year_dob = _check_dob(cv102_dob, 1967, 11, 5)
        cv102_gender_ok = cv102_gender.startswith("f")

        if cv102_gender_ok and cv102_exact_dob:
            base_pts = 25
            feedback_parts.append(
                f"CV-102 enrolled with correct demographics (gender={cv102_gender}, dob={cv102_dob})"
            )
        elif cv102_gender_ok and cv102_year_dob:
            base_pts = 18
            feedback_parts.append(
                f"CV-102 enrolled; gender correct, DOB year correct but date off (dob={cv102_dob})"
            )
        elif cv102_gender_ok or cv102_exact_dob:
            base_pts = 14
            feedback_parts.append(
                f"CV-102 enrolled; partial demographics match "
                f"(gender={cv102_gender}, dob={cv102_dob})"
            )
        else:
            base_pts = 10
            feedback_parts.append(
                f"CV-102 found but demographics incorrect "
                f"(gender={cv102_gender}, dob={cv102_dob})"
            )

        score += base_pts

        # Bonus: enrolled specifically at site level
        if cv102_at_site:
            score += 5
            feedback_parts.append("BONUS (+5): CV-102 enrolled at Boston Heart Institute site level")
        else:
            feedback_parts.append(
                "CV-102 enrolled at parent study level (not at site — no bonus, but accepted)"
            )
    else:
        feedback_parts.append("FAIL: CV-102 not found in CV Registry or its sites")

    # -------------------------------------------------------------------------
    # VLM visual check (up to 10 pts)
    # -------------------------------------------------------------------------
    query_vlm_func = env_info.get("query_vlm")
    vlm_score = 0
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    try:
        copy_from_env("/tmp/task_end_screenshot.png", temp_screenshot.name)
        vlm_result = _verify_with_vlm(temp_screenshot.name, query_vlm_func)

        if vlm_result.get("success"):
            # 5 pts for general OpenClinica success/details visible
            if vlm_result.get("success_message_visible") or vlm_result.get("subject_list_or_details_visible"):
                vlm_score += 5
            # 5 pts for site or subject identifiers visible on screen
            if vlm_result.get("site_or_subject_visible"):
                vlm_score += 5
            feedback_parts.append(
                f"VLM visual check: {vlm_score}/10 (confidence: {vlm_result.get('confidence', 'n/a')})"
            )
        else:
            vlm_score = 0
            feedback_parts.append(f"VLM unavailable: {vlm_score}/10")
    except Exception as e:
        vlm_score = 0
        feedback_parts.append(f"VLM check failed ({e}): {vlm_score}/10")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    score += vlm_score

    # -------------------------------------------------------------------------
    # Audit log penalty: -20 pts if no GUI interaction detected
    # -------------------------------------------------------------------------
    audit_count = _safe_int(result.get("audit_log_count", 0))
    audit_baseline = _safe_int(result.get("audit_baseline_count", 0))
    audit_delta = audit_count - audit_baseline

    gui_verified = audit_delta > 0
    if gui_verified:
        feedback_parts.append(
            f"GUI audit log: {audit_delta} new entries since setup (GUI interaction confirmed)"
        )
    else:
        score = max(0, score - 20)
        feedback_parts.append(
            "PENALTY (-20): No new audit log entries since setup — possible direct SQL bypass"
        )

    # -------------------------------------------------------------------------
    # Pass determination
    # -------------------------------------------------------------------------
    # Require: site found AND at least one subject present AND minimum score
    site_ok = site_found
    subjects_ok = cv101_found or cv102_found
    passed = score >= 70 and site_ok and subjects_ok and gui_verified

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
