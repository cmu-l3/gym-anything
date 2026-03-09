#!/usr/bin/env python3
"""
Verifier for race_course_certification task.

Scoring (100 pts total, pass >= 60):
  - GPX file exists and is new                     : gate (0 if fails)
  -  8 required waypoints present by name           : 8 × 5 = 40 pts
  - Route 'FELLS 25K OFFICIAL COURSE' found         : 10 pts
  - Route has all 9 waypoints in correct order      : 25 pts
  - START has 'Flag, Blue' symbol                   :  5 pts
  - At least 3 aid stations have 'Food/Water' sym   : 10 pts
  - MANDATORY CP has 'Danger' symbol                :  5 pts
  - MEDICAL CP has 'Medical Facility' symbol         :  5 pts
  Total: 100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_WPTS = [
    "START - BELLEVUE POND",
    "AS1 - NORTH LOOP",
    "AS2 - SHEEPFOLD NORTH",
    "AS3 - SOUTH FELLS",
    "MANDATORY CP",
    "CREW ACCESS A",
    "CREW ACCESS B",
    "MEDICAL CP",
]

COURSE_ROUTE_NAME = "FELLS 25K OFFICIAL COURSE"
COURSE_ORDER = [
    "START - BELLEVUE POND",
    "AS1 - NORTH LOOP",
    "AS2 - SHEEPFOLD NORTH",
    "MANDATORY CP",
    "AS3 - SOUTH FELLS",
    "CREW ACCESS B",
    "MEDICAL CP",
    "CREW ACCESS A",
    "START - BELLEVUE POND",
]

AID_STATION_NAMES = ["AS1 - NORTH LOOP", "AS2 - SHEEPFOLD NORTH", "AS3 - SOUTH FELLS"]


def _normalise(s):
    return s.upper().strip()


def _find_wpt(wpts, name):
    nn = _normalise(name)
    for w in wpts:
        if _normalise(w.get("name", "")) == nn:
            return w
    return None


def _find_route(routes, name):
    nn = _normalise(name)
    for r in routes:
        if _normalise(r.get("name", "")) == nn:
            return r
    return None


def _route_order_score(route_points, required_order, full_pts):
    """Award points based on how well required_order appears as subsequence."""
    rp_norm  = [_normalise(p) for p in route_points]
    req_norm = [_normalise(p) for p in required_order]

    idx = 0
    for r in rp_norm:
        if idx < len(req_norm) and r == req_norm[idx]:
            idx += 1
    if idx == len(req_norm):
        return full_pts

    frac = idx / len(req_norm)
    return int(full_pts * frac * 0.7)


def verify_race_course_certification(traj, env_info, task_info):
    cfenv = env_info.get("copy_from_env")
    if not callable(cfenv):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        cfenv(r"C:\Users\Docker\race_course_certification_result.json", tmp.name)
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0,
                "feedback": f"Result file not found on VM: {e}"}

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            data = json.load(f)
    except Exception as e:
        os.unlink(tmp.name)
        return {"passed": False, "score": 0, "feedback": f"JSON parse error: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    # ------------------------------------------------------------------ GATE
    if not data.get("gpx_exists"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: Fells25K_Official_Course_2024.gpx not found on Desktop."}

    if not data.get("gpx_is_new"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: GPX file predates task start."}

    wpts   = data.get("waypoints", [])
    routes = data.get("routes",    [])
    score  = 0
    fb     = []

    # ------------------------------------------------ Waypoint presence (40 pts)
    for req in REQUIRED_WPTS:
        w = _find_wpt(wpts, req)
        if w:
            score += 5
            fb.append(f"WPT OK: '{req}'")
        else:
            fb.append(f"WPT MISSING: '{req}'")

    # ------------------------------------------------ Route (35 pts)
    course_rt = _find_route(routes, COURSE_ROUTE_NAME)
    if course_rt:
        score += 10
        fb.append(f"ROUTE OK: '{COURSE_ROUTE_NAME}'")
        order_pts = _route_order_score(course_rt["points"], COURSE_ORDER, 25)
        score += order_pts
        fb.append(f"  Course order: {order_pts}/25 (points: {course_rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{COURSE_ROUTE_NAME}'")

    # ------------------------------------------------ Symbol checks (25 pts)
    start_wpt = _find_wpt(wpts, "START - BELLEVUE POND")
    if start_wpt and "flag" in start_wpt.get("sym", "").lower() and "blue" in start_wpt.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: START = Flag, Blue")
    else:
        sym = start_wpt.get("sym", "") if start_wpt else "not found"
        fb.append(f"SYMBOL MISS: START sym='{sym}'")

    as_with_fw = sum(
        1 for name in AID_STATION_NAMES
        if (w := _find_wpt(wpts, name)) and "food" in w.get("sym", "").lower()
    )
    if as_with_fw >= 3:
        score += 10
        fb.append(f"SYMBOL OK: {as_with_fw}/3 aid stations have Food/Water symbol")
    elif as_with_fw >= 1:
        score += 5
        fb.append(f"SYMBOL PARTIAL: {as_with_fw}/3 aid stations have Food/Water symbol")
    else:
        fb.append("SYMBOL MISS: No aid stations have Food/Water symbol")

    mcp = _find_wpt(wpts, "MANDATORY CP")
    if mcp and "danger" in mcp.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: MANDATORY CP = Danger")
    else:
        sym = mcp.get("sym", "") if mcp else "not found"
        fb.append(f"SYMBOL MISS: MANDATORY CP sym='{sym}'")

    med = _find_wpt(wpts, "MEDICAL CP")
    if med and "medical" in med.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: MEDICAL CP = Medical Facility")
    else:
        sym = med.get("sym", "") if med else "not found"
        fb.append(f"SYMBOL MISS: MEDICAL CP sym='{sym}'")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb),
        "subscores": {
            "waypoints_present": sum(1 for r in REQUIRED_WPTS if _find_wpt(wpts, r)),
            "route_found": 1 if course_rt else 0,
        },
    }
