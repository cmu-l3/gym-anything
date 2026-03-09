import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PREEXISTING_NAMES = ["Marbury v. Madison", "Brown v. Board of Education"]


def fuzzy_match(expected, actual):
    """Return True if expected and actual share a meaningful prefix match."""
    return (
        expected.lower()[:20] in actual.lower()
        or actual.lower()[:20] in expected.lower()
    )


def case_matches_any(case_name, target_list):
    """Check if case_name fuzzy-matches any name in target_list."""
    for target in target_list:
        if fuzzy_match(target, case_name):
            return True
    return False


def find_case(all_cases, target_name):
    """Find a case dict by fuzzy name match."""
    for case in all_cases:
        if fuzzy_match(target_name, case.get("caseName", "")):
            return case
    return None


def verify_fourth_amendment_brief_research(traj, env_info, task_info):
    """
    Verifier for fourth_amendment_brief_research task.

    Scoring (100 pts, pass threshold = 60):
      1. Total 4th Amendment cases added   : 20 pts
      2. Terry v. Ohio present             : 10 pts
      3. Katz v. United States present     : 10 pts
      4. Carpenter v. United States present: 10 pts
      5. Collection hierarchy              : 15 pts
      6. Cases in subcollections           : 10 pts
      7. Notes on cases                    : 25 pts

    Penalty: if preexisting items (Marbury, Brown) are missing/deleted: -20 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available in env_info",
        }

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/fourth_amendment_brief_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "score": 0,
            "max_score": 100,
            "pass": False,
            "reason": f"Could not retrieve export result: {e}. Was the task completed?",
            "details": {}
        }

    all_cases = result.get("all_cases", [])
    all_case_tags = result.get("all_case_tags", {})
    parent_collection_exists = result.get("parent_collection_exists", False)
    favorable_collection_exists = result.get("favorable_collection_exists", False)
    adverse_collection_exists = result.get("adverse_collection_exists", False)
    favorable_items = result.get("favorable_items", [])
    adverse_items = result.get("adverse_items", [])
    notes = result.get("notes", [])
    preexisting_cases = result.get("preexisting_cases", [])

    details = {}
    score = 0
    penalty = 0

    # -------------------------------------------------------------------
    # WRONG-TARGET GATE: pre-existing items must still be present
    # -------------------------------------------------------------------
    preexisting_ok = all(
        any(fuzzy_match(name, pc) for pc in preexisting_cases)
        for name in PREEXISTING_NAMES
    )
    if not preexisting_ok:
        penalty = 20
        details["preexisting_gate"] = {
            "penalty": -penalty,
            "reason": "One or both pre-existing items (Marbury v. Madison, Brown v. Board of Education) were deleted or modified.",
            "preexisting_cases_found": preexisting_cases
        }
    else:
        details["preexisting_gate"] = {
            "penalty": 0,
            "reason": "Both pre-existing items are present.",
            "preexisting_cases_found": preexisting_cases
        }

    # -------------------------------------------------------------------
    # Count non-preexisting cases (Fourth Amendment cases added by agent)
    # -------------------------------------------------------------------
    fourth_amendment_cases = [
        case for case in all_cases
        if not case_matches_any(case.get("caseName", ""), PREEXISTING_NAMES)
    ]
    fa_count = len(fourth_amendment_cases)

    # -------------------------------------------------------------------
    # 1. Total 4th Amendment cases (20 pts)
    # -------------------------------------------------------------------
    if fa_count >= 6:
        count_pts = 20
    elif fa_count >= 4:
        count_pts = 10
    elif fa_count >= 2:
        count_pts = 5
    else:
        count_pts = 0
    score += count_pts
    details["fourth_amendment_case_count"] = {
        "points": count_pts,
        "max_points": 20,
        "count": fa_count,
        "cases": [c.get("caseName", "") for c in fourth_amendment_cases]
    }

    # -------------------------------------------------------------------
    # 2. Terry v. Ohio present (10 pts)
    # -------------------------------------------------------------------
    terry = find_case(all_cases, "Terry v. Ohio")
    if terry is not None and not case_matches_any(terry.get("caseName", ""), PREEXISTING_NAMES):
        terry_pts = 10
        terry_detail = f"FOUND (caseName='{terry['caseName']}')"
    else:
        terry_pts = 0
        terry_detail = "NOT FOUND"
    score += terry_pts
    details["terry_v_ohio"] = {
        "points": terry_pts,
        "max_points": 10,
        "status": terry_detail
    }

    # -------------------------------------------------------------------
    # 3. Katz v. United States present (10 pts)
    # -------------------------------------------------------------------
    katz = find_case(all_cases, "Katz v. United States")
    if katz is not None and not case_matches_any(katz.get("caseName", ""), PREEXISTING_NAMES):
        katz_pts = 10
        katz_detail = f"FOUND (caseName='{katz['caseName']}')"
    else:
        katz_pts = 0
        katz_detail = "NOT FOUND"
    score += katz_pts
    details["katz_v_united_states"] = {
        "points": katz_pts,
        "max_points": 10,
        "status": katz_detail
    }

    # -------------------------------------------------------------------
    # 4. Carpenter v. United States present (10 pts)
    # -------------------------------------------------------------------
    carpenter = find_case(all_cases, "Carpenter v. United States")
    if carpenter is not None and not case_matches_any(carpenter.get("caseName", ""), PREEXISTING_NAMES):
        carpenter_pts = 10
        carpenter_detail = f"FOUND (caseName='{carpenter['caseName']}')"
    else:
        carpenter_pts = 0
        carpenter_detail = "NOT FOUND"
    score += carpenter_pts
    details["carpenter_v_united_states"] = {
        "points": carpenter_pts,
        "max_points": 10,
        "status": carpenter_detail
    }

    # -------------------------------------------------------------------
    # 5. Collection hierarchy (15 pts)
    # -------------------------------------------------------------------
    collection_pts = 0
    if parent_collection_exists:
        collection_pts += 5
    if favorable_collection_exists:
        collection_pts += 5
    if adverse_collection_exists:
        collection_pts += 5
    score += collection_pts
    details["collection_hierarchy"] = {
        "points": collection_pts,
        "max_points": 15,
        "parent_collection_exists": parent_collection_exists,
        "favorable_collection_exists": favorable_collection_exists,
        "adverse_collection_exists": adverse_collection_exists
    }

    # -------------------------------------------------------------------
    # 6. Cases in subcollections (10 pts)
    # -------------------------------------------------------------------
    total_subcollection_cases = len(favorable_items) + len(adverse_items)
    if total_subcollection_cases >= 4:
        subcol_pts = 10
    elif total_subcollection_cases >= 2:
        subcol_pts = 5
    else:
        subcol_pts = 0
    score += subcol_pts
    details["cases_in_subcollections"] = {
        "points": subcol_pts,
        "max_points": 10,
        "favorable_items": favorable_items,
        "adverse_items": adverse_items,
        "total_in_subcollections": total_subcollection_cases
    }

    # -------------------------------------------------------------------
    # 7. Notes on Fourth Amendment cases (25 pts)
    # Note length >= 200 characters is required (approx 40 words).
    # Notes from preexisting cases do not count.
    # -------------------------------------------------------------------
    qualifying_notes = [
        n for n in notes
        if n.get("note_length", 0) >= 200
        and not case_matches_any(n.get("caseName", ""), PREEXISTING_NAMES)
    ]
    qualifying_note_count = len(qualifying_notes)

    if qualifying_note_count >= 4:
        note_pts = 25
    elif qualifying_note_count >= 2:
        note_pts = 12
    elif qualifying_note_count >= 1:
        note_pts = 6
    else:
        note_pts = 0
    score += note_pts
    details["notes_on_cases"] = {
        "points": note_pts,
        "max_points": 25,
        "qualifying_note_count": qualifying_note_count,
        "all_notes": notes
    }

    # -------------------------------------------------------------------
    # Apply penalty for deleted/modified preexisting items
    # -------------------------------------------------------------------
    final_score = max(0, score - penalty)
    passed = final_score >= 60

    return {
        "score": final_score,
        "max_score": 100,
        "pass": passed,
        "reason": (
            f"Raw score {score}/100, penalty {penalty}, "
            f"final score {final_score}/100 "
            f"({'PASS' if passed else 'FAIL'}, threshold=60)"
        ),
        "details": details
    }
