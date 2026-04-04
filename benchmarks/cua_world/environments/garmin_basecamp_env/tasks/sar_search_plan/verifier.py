#!/usr/bin/env python3
"""
Verifier for sar_search_plan task.

Scoring (100 pts total, pass >= 60):
  - GPX file exists and is new (gate: return 0 if missing or stale)
  -  6 required waypoints present by name   : 6 × 7 = 42 pts
  - Route ALPHA SEARCH ROUTE found           :  8 pts
  - Route ALPHA has correct 5-point order    : 12 pts
  - Route BRAVO SEARCH ROUTE found           :  8 pts
  - Route BRAVO has correct 6-point order    : 12 pts
  - ICS COMMAND POST symbol == 'Building'    :  8 pts
  - HELICOPTER LZ NORTH symbol == 'Airport'  :  5 pts
  - LKP waypoint has comment set             :  5 pts
  Total: 100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_WPTS = [
    "LKP - HAWTHORN RD",
    "CP-ALPHA",
    "CP-BRAVO",
    "ICS COMMAND POST",
    "HELICOPTER LZ NORTH",
    "MEDICAL STAGING",
]

ALPHA_ROUTE_NAME = "ALPHA SEARCH ROUTE"
# Required waypoints in order (as subsequence)
ALPHA_ORDER = ["ICS COMMAND POST", "LKP - HAWTHORN RD", "CP-ALPHA", "CP-BRAVO", "ICS COMMAND POST"]

BRAVO_ROUTE_NAME = "BRAVO SEARCH ROUTE"
BRAVO_ORDER = ["ICS COMMAND POST", "MEDICAL STAGING", "LKP - HAWTHORN RD",
               "HELICOPTER LZ NORTH", "CP-BRAVO", "ICS COMMAND POST"]


def _normalise(s):
    return s.upper().strip()


def _find_wpt(wpts, name):
    """Find a waypoint by exact name (case-insensitive)."""
    nn = _normalise(name)
    for w in wpts:
        if _normalise(w.get("name", "")) == nn:
            return w
    return None


def _find_route(routes, name):
    """Find a route by name (case-insensitive)."""
    nn = _normalise(name)
    for r in routes:
        if _normalise(r.get("name", "")) == nn:
            return r
    return None


def _route_order_score(route_points, required_order, full_pts):
    """
    Award full_pts if required_order appears as a strict subsequence
    in route_points.  Award partial credit proportional to the
    longest matching prefix of required_order.
    """
    rp_norm = [_normalise(p) for p in route_points]
    req_norm = [_normalise(p) for p in required_order]

    # Check full subsequence
    idx = 0
    for r in rp_norm:
        if idx < len(req_norm) and r == req_norm[idx]:
            idx += 1
    if idx == len(req_norm):
        return full_pts

    # Partial credit: fraction of required_order matched
    frac = idx / len(req_norm)
    return int(full_pts * frac * 0.7)   # 70% of full for partial match


def verify_sar_search_plan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env") or env_info.get("exec_capture")
    if not callable(copy_from_env) and "copy_from_env" not in env_info:
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available in env_info"}

    cfenv = env_info.get("copy_from_env")
    if not callable(cfenv):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not callable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        cfenv(r"C:\Users\Docker\sar_search_plan_result.json", tmp.name)
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
                "feedback": "GATE FAIL: SAR_Middlesex_Fells_2024.gpx not found on Desktop. "
                            "Agent must export the collection as GPX."}

    if not data.get("gpx_is_new"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: GPX file predates task start — no new export detected."}

    wpts   = data.get("waypoints", [])
    routes = data.get("routes",    [])
    score  = 0
    fb     = []

    # ------------------------------------------------ Waypoint presence (42 pts)
    for req in REQUIRED_WPTS:
        w = _find_wpt(wpts, req)
        if w:
            score += 7
            fb.append(f"WPT OK: '{req}'")
        else:
            fb.append(f"WPT MISSING: '{req}'")

    # ------------------------------------------------ Route ALPHA (20 pts)
    alpha_rt = _find_route(routes, ALPHA_ROUTE_NAME)
    if alpha_rt:
        score += 8
        fb.append(f"ROUTE OK: '{ALPHA_ROUTE_NAME}'")
        order_pts = _route_order_score(alpha_rt["points"], ALPHA_ORDER, 12)
        score += order_pts
        fb.append(f"  ALPHA order score: {order_pts}/12 (points: {alpha_rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{ALPHA_ROUTE_NAME}'")

    # ------------------------------------------------ Route BRAVO (20 pts)
    bravo_rt = _find_route(routes, BRAVO_ROUTE_NAME)
    if bravo_rt:
        score += 8
        fb.append(f"ROUTE OK: '{BRAVO_ROUTE_NAME}'")
        order_pts = _route_order_score(bravo_rt["points"], BRAVO_ORDER, 12)
        score += order_pts
        fb.append(f"  BRAVO order score: {order_pts}/12 (points: {bravo_rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{BRAVO_ROUTE_NAME}'")

    # ------------------------------------------------ Symbol checks (13 pts)
    ics = _find_wpt(wpts, "ICS COMMAND POST")
    if ics and "building" in ics.get("sym", "").lower():
        score += 8
        fb.append("SYMBOL OK: ICS COMMAND POST = Building")
    else:
        fb.append(f"SYMBOL MISS: ICS COMMAND POST sym='{ics.get('sym','') if ics else 'not found'}'")

    lz = _find_wpt(wpts, "HELICOPTER LZ NORTH")
    if lz and "airport" in lz.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: HELICOPTER LZ NORTH = Airport")
    else:
        fb.append(f"SYMBOL MISS: HELICOPTER LZ NORTH sym='{lz.get('sym','') if lz else 'not found'}'")

    # ------------------------------------------------ LKP comment (5 pts)
    lkp = _find_wpt(wpts, "LKP - HAWTHORN RD")
    if lkp and (lkp.get("cmt") or lkp.get("desc")):
        score += 5
        fb.append("COMMENT OK: LKP - HAWTHORN RD has description/comment")
    else:
        fb.append("COMMENT MISS: LKP - HAWTHORN RD has no comment")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb),
        "subscores": {
            "waypoints_present": sum(1 for r in REQUIRED_WPTS if _find_wpt(wpts, r)),
            "routes_found": sum(1 for n in [ALPHA_ROUTE_NAME, BRAVO_ROUTE_NAME]
                                if _find_route(routes, n)),
        },
    }
