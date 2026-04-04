#!/usr/bin/env python3
"""
Verifier for comparative_law_organization task.

Scoring (100 points total, pass threshold = 60):
  1. Parent collection 'Comparative Constitutional Law' exists:           10 pts
  2. Subcollections (5 pts each x 3):                                    15 pts
     - 'US Cases' subcollection exists
     - 'UK Cases' subcollection exists
     - 'Canada Cases' subcollection exists
  3. US cases assigned (>=4/5 = 20 pts, >=2/5 = 10 pts):               20 pts
  4. UK cases assigned (>=3/4 = 15 pts, >=1/4 = 7 pts):                15 pts
  5. Canada cases assigned (all 3 = 10 pts, >=1 = 5 pts):              10 pts
  6. Missing court fields fixed (>=2/3 = 15 pts, >=1/3 = 7 pts):       15 pts
  7. Wrong court fields fixed (>=1/2 correct now):                        5 pts
  8. Jurisdiction tags (>=8 items tagged = 10 pts, >=4 = 5 pts):        10 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

US_CASES = [
    "Brown v. Board of Education",
    "Miranda v. Arizona",
    "New York Times Co. v. Sullivan",
    "Obergefell v. Hodges",
    "Gideon v. Wainwright",
]
UK_CASES = [
    "Donoghue v Stevenson",
    "R v Brown",
    "Entick v Carrington",
    "R v Secretary of State for the Home Department ex p Simms",
]
CANADA_CASES = [
    "R v Oakes",
    "Vriend v Alberta",
    "Carter v Canada (Attorney General)",
]
MISSING_COURTS = [
    "Brown v. Board of Education",
    "Miranda v. Arizona",
    "Gideon v. Wainwright",
]
WRONG_COURTS = [
    "New York Times Co. v. Sullivan",  # should be "United States Supreme Court"
    "R v Brown",                        # should be "House of Lords"
]
JURISDICTION_TAGS = {"United States", "United Kingdom", "Canada", "US", "UK"}


def _normalize(s: str) -> str:
    """Normalize a case name for fuzzy comparison."""
    return s.lower().strip().replace(".", "").replace(",", "").replace("  ", " ")


def _fuzzy_match(expected: str, actual_list: List[str]) -> bool:
    """Return True if expected case name roughly matches any item in actual_list."""
    norm_exp = _normalize(expected)
    for actual in actual_list:
        norm_act = _normalize(actual)
        if norm_exp in norm_act or norm_act in norm_exp:
            return True
    return False


def verify_comparative_law_organization(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify the comparative law organization task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the environment
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/comparative_law_organization_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found. Was the post_task hook run?",
            }
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []
    details = {}

    # ---- Criterion 1: Parent collection exists (10 pts) ----
    try:
        parent_exists = result.get("parent_collection_exists", False)
        if parent_exists:
            score += 10
            feedback.append("Parent collection 'Comparative Constitutional Law' exists (+10)")
        else:
            feedback.append("Parent collection 'Comparative Constitutional Law' NOT found (0)")
        details["parent_collection_exists"] = parent_exists
    except Exception as e:
        logger.warning(f"Criterion 1 error: {e}")

    # ---- Criterion 2: Subcollections (5 pts each, 15 total) ----
    try:
        us_sub = result.get("us_subcollection_exists", False)
        uk_sub = result.get("uk_subcollection_exists", False)
        ca_sub = result.get("canada_subcollection_exists", False)
        sub_score = 0
        if us_sub:
            sub_score += 5
            feedback.append("'US Cases' subcollection exists (+5)")
        else:
            feedback.append("'US Cases' subcollection NOT found (0)")
        if uk_sub:
            sub_score += 5
            feedback.append("'UK Cases' subcollection exists (+5)")
        else:
            feedback.append("'UK Cases' subcollection NOT found (0)")
        if ca_sub:
            sub_score += 5
            feedback.append("'Canada Cases' subcollection exists (+5)")
        else:
            feedback.append("'Canada Cases' subcollection NOT found (0)")
        score += sub_score
        details["subcollection_score"] = sub_score
    except Exception as e:
        logger.warning(f"Criterion 2 error: {e}")

    # ---- Criterion 3: US cases assigned (20 pts) ----
    try:
        us_items = result.get("us_items", [])
        us_matched = sum(1 for case in US_CASES if _fuzzy_match(case, us_items))
        if us_matched >= 4:
            score += 20
            feedback.append(f"US cases assigned: {us_matched}/5 (>=4 required) (+20)")
        elif us_matched >= 2:
            score += 10
            feedback.append(f"US cases assigned: {us_matched}/5 (partial, >=2) (+10)")
        else:
            feedback.append(f"US cases assigned: {us_matched}/5 — too few correct (0)")
        details["us_matched"] = us_matched
    except Exception as e:
        logger.warning(f"Criterion 3 error: {e}")

    # ---- Criterion 4: UK cases assigned (15 pts) ----
    try:
        uk_items = result.get("uk_items", [])
        uk_matched = sum(1 for case in UK_CASES if _fuzzy_match(case, uk_items))
        if uk_matched >= 3:
            score += 15
            feedback.append(f"UK cases assigned: {uk_matched}/4 (>=3 required) (+15)")
        elif uk_matched >= 1:
            score += 7
            feedback.append(f"UK cases assigned: {uk_matched}/4 (partial, >=1) (+7)")
        else:
            feedback.append(f"UK cases assigned: {uk_matched}/4 — none correct (0)")
        details["uk_matched"] = uk_matched
    except Exception as e:
        logger.warning(f"Criterion 4 error: {e}")

    # ---- Criterion 5: Canada cases assigned (10 pts) ----
    try:
        canada_items = result.get("canada_items", [])
        ca_matched = sum(1 for case in CANADA_CASES if _fuzzy_match(case, canada_items))
        if ca_matched >= 3:
            score += 10
            feedback.append(f"Canada cases assigned: {ca_matched}/3 (all correct) (+10)")
        elif ca_matched >= 1:
            score += 5
            feedback.append(f"Canada cases assigned: {ca_matched}/3 (partial, >=1) (+5)")
        else:
            feedback.append(f"Canada cases assigned: {ca_matched}/3 — none correct (0)")
        details["ca_matched"] = ca_matched
    except Exception as e:
        logger.warning(f"Criterion 5 error: {e}")

    # ---- Criterion 6: Missing court fields fixed (15 pts) ----
    try:
        all_items_court = result.get("all_items_court", {})
        missing_fixed = 0
        for case_name in MISSING_COURTS:
            # Find matching key using fuzzy match
            matched_court = ""
            for key, court_val in all_items_court.items():
                if _fuzzy_match(case_name, [key]):
                    matched_court = court_val
                    break
            if matched_court and matched_court.lower() != "unknown court":
                missing_fixed += 1
        if missing_fixed >= 2:
            score += 15
            feedback.append(f"Missing courts fixed: {missing_fixed}/3 (>=2 required) (+15)")
        elif missing_fixed >= 1:
            score += 7
            feedback.append(f"Missing courts fixed: {missing_fixed}/3 (partial, >=1) (+7)")
        else:
            feedback.append(f"Missing courts fixed: {missing_fixed}/3 — none fixed (0)")
        details["missing_courts_fixed"] = missing_fixed
    except Exception as e:
        logger.warning(f"Criterion 6 error: {e}")

    # ---- Criterion 7: Wrong court fields fixed (5 pts) ----
    try:
        all_items_court = result.get("all_items_court", {})
        wrong_fixed = 0
        for case_name in WRONG_COURTS:
            matched_court = ""
            for key, court_val in all_items_court.items():
                if _fuzzy_match(case_name, [key]):
                    matched_court = court_val
                    break
            # Court is fixed if it's non-empty and not "Unknown Court"
            if matched_court and matched_court.lower() != "unknown court":
                wrong_fixed += 1
        if wrong_fixed >= 1:
            score += 5
            feedback.append(f"Wrong courts fixed: {wrong_fixed}/2 (>=1 required) (+5)")
        else:
            feedback.append(f"Wrong courts fixed: {wrong_fixed}/2 — none fixed (0)")
        details["wrong_courts_fixed"] = wrong_fixed
    except Exception as e:
        logger.warning(f"Criterion 7 error: {e}")

    # ---- Criterion 8: Jurisdiction tags (10 pts) ----
    try:
        item_tags = result.get("item_tags", {})
        tagged_count = 0
        for case_name, tags in item_tags.items():
            if any(t in JURISDICTION_TAGS for t in tags):
                tagged_count += 1
        if tagged_count >= 8:
            score += 10
            feedback.append(f"Jurisdiction tags: {tagged_count} items tagged (>=8 required) (+10)")
        elif tagged_count >= 4:
            score += 5
            feedback.append(f"Jurisdiction tags: {tagged_count} items tagged (partial, >=4) (+5)")
        else:
            feedback.append(f"Jurisdiction tags: {tagged_count} items tagged — too few (0)")
        details["jurisdiction_tagged_count"] = tagged_count
    except Exception as e:
        logger.warning(f"Criterion 8 error: {e}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": details,
    }
