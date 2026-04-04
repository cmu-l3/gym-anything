import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

WRONG_REPORTER_CASES = ["Mapp v. Ohio", "United States v. Leon", "Weeks v. United States"]
WRONG_COURT_CASES = ["Illinois v. Gates", "Bivens v. Six Unknown Named Agents"]
WRONG_YEAR_CASE = "United States v. Cortez"
WRONG_PAGE_CASES = {"Terry v. Ohio": "1", "Katz v. United States": "347"}


def fuzzy_match(expected, actual):
    """Return True if expected and actual share a meaningful prefix match."""
    return (
        expected.lower()[:20] in actual.lower()
        or actual.lower()[:20] in expected.lower()
    )


def find_case(all_cases, target_name):
    """Find a case dict by fuzzy name match."""
    for case in all_cases:
        if fuzzy_match(target_name, case.get("caseName", "")):
            return case
    return None


def verify_citation_audit_repair(traj, env_info, task_info):
    """
    Verifier for citation_audit_repair task.

    Scoring (100 pts, pass threshold = 60):
      1. Wrong reporters fixed    : 20 pts
      2. Wrong courts fixed       : 15 pts
      3. Wrong year fixed         : 15 pts
      4. Wrong pages fixed        : 15 pts
      5. 'audited' tag on items   : 20 pts
      6. 'Audited Cases' collection: 15 pts
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
            copy_from_env("/tmp/citation_audit_repair_result.json", tmp.name)
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
    audited_tag_count = result.get("audited_tag_count", 0)
    audited_collection_exists = result.get("audited_collection_exists", False)
    audited_collection_item_count = result.get("audited_collection_item_count", 0)

    details = {}
    score = 0

    # -------------------------------------------------------------------
    # 1. Wrong reporters fixed (20 pts)
    # -------------------------------------------------------------------
    reporters_fixed = 0
    reporter_detail = {}
    for name in WRONG_REPORTER_CASES:
        case = find_case(all_cases, name)
        if case is None:
            reporter_detail[name] = "NOT FOUND"
        elif case.get("reporter", "").strip().lower() == "u.s.":
            reporter_detail[name] = f"FIXED (reporter='{case['reporter']}')"
            reporters_fixed += 1
        else:
            reporter_detail[name] = f"WRONG (reporter='{case.get('reporter', '')}')"

    if reporters_fixed >= 3:
        reporter_pts = 20
    elif reporters_fixed >= 2:
        reporter_pts = 20
    elif reporters_fixed >= 1:
        reporter_pts = 10
    else:
        reporter_pts = 0
    score += reporter_pts
    details["wrong_reporters"] = {
        "points": reporter_pts,
        "max_points": 20,
        "fixed_count": reporters_fixed,
        "cases": reporter_detail
    }

    # -------------------------------------------------------------------
    # 2. Wrong courts fixed (15 pts)
    # -------------------------------------------------------------------
    courts_fixed = 0
    court_detail = {}
    for name in WRONG_COURT_CASES:
        case = find_case(all_cases, name)
        if case is None:
            court_detail[name] = "NOT FOUND"
        elif "supreme court" in case.get("court", "").lower():
            court_detail[name] = f"FIXED (court='{case['court']}')"
            courts_fixed += 1
        else:
            court_detail[name] = f"WRONG (court='{case.get('court', '')}')"

    if courts_fixed >= 2:
        court_pts = 15
    elif courts_fixed >= 1:
        court_pts = 7
    else:
        court_pts = 0
    score += court_pts
    details["wrong_courts"] = {
        "points": court_pts,
        "max_points": 15,
        "fixed_count": courts_fixed,
        "cases": court_detail
    }

    # -------------------------------------------------------------------
    # 3. Wrong year fixed (15 pts)
    # -------------------------------------------------------------------
    cortez = find_case(all_cases, WRONG_YEAR_CASE)
    if cortez is not None and "1981" in cortez.get("dateDecided", ""):
        year_pts = 15
        year_detail = f"FIXED (dateDecided='{cortez['dateDecided']}')"
    elif cortez is None:
        year_pts = 0
        year_detail = "CASE NOT FOUND"
    else:
        year_pts = 0
        year_detail = f"WRONG (dateDecided='{cortez.get('dateDecided', '')}')"
    score += year_pts
    details["wrong_year"] = {
        "points": year_pts,
        "max_points": 15,
        "case": WRONG_YEAR_CASE,
        "status": year_detail
    }

    # -------------------------------------------------------------------
    # 4. Wrong pages fixed (15 pts)
    # -------------------------------------------------------------------
    pages_fixed = 0
    page_detail = {}
    for name, correct_page in WRONG_PAGE_CASES.items():
        case = find_case(all_cases, name)
        if case is None:
            page_detail[name] = "NOT FOUND"
        elif case.get("firstPage", "").strip() == correct_page:
            page_detail[name] = f"FIXED (firstPage='{case['firstPage']}')"
            pages_fixed += 1
        else:
            page_detail[name] = f"WRONG (firstPage='{case.get('firstPage', '')}', expected='{correct_page}')"

    if pages_fixed >= 2:
        page_pts = 15
    elif pages_fixed >= 1:
        page_pts = 7
    else:
        page_pts = 0
    score += page_pts
    details["wrong_pages"] = {
        "points": page_pts,
        "max_points": 15,
        "fixed_count": pages_fixed,
        "cases": page_detail
    }

    # -------------------------------------------------------------------
    # 5. 'audited' tag applied to items (20 pts)
    # -------------------------------------------------------------------
    if audited_tag_count >= 8:
        tag_pts = 20
    elif audited_tag_count >= 5:
        tag_pts = 10
    else:
        tag_pts = 0
    score += tag_pts
    details["audited_tag"] = {
        "points": tag_pts,
        "max_points": 20,
        "audited_tag_count": audited_tag_count
    }

    # -------------------------------------------------------------------
    # 6. 'Audited Cases' collection (15 pts)
    # -------------------------------------------------------------------
    if audited_collection_exists and audited_collection_item_count >= 8:
        collection_pts = 15
    elif audited_collection_exists:
        collection_pts = 5
    else:
        collection_pts = 0
    score += collection_pts
    details["audited_collection"] = {
        "points": collection_pts,
        "max_points": 15,
        "collection_exists": audited_collection_exists,
        "item_count": audited_collection_item_count
    }

    # -------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------
    passed = score >= 60
    return {
        "score": score,
        "max_score": 100,
        "pass": passed,
        "reason": f"Score {score}/100 ({'PASS' if passed else 'FAIL'}, threshold=60)",
        "details": details
    }
