#!/usr/bin/env python3
"""
Verifier for commercial_truck_route_plan task.

Occupation: Transportation Dispatcher (Heavy/Tractor-Trailer Truck Drivers, $399M GDP)
Industry: Transportation and Material Moving

Scoring (100 pts total, pass >= 60):
  - GPX file exists and is new              : gate (0 if fails)
  - 7 required waypoints present by name    : 7 × 6 = 42 pts
  - Route BOSTON-FALL RIVER FREIGHT RUN found : 8 pts
  - Route has correct 6-point order         : 12 pts
  - BRIDGE HAZARD RT116 has Danger symbol   : 10 pts
  - DEPOT SOUTH BOSTON has Building symbol  :  8 pts
  - WEIGH STATION RT44 has Car symbol       :  8 pts
  - ≥3 STOP waypoints have comments         : 12 pts
  Total: 100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_WPTS = [
    "DEPOT SOUTH BOSTON",
    "BRIDGE HAZARD RT116",
    "STOP 1 NORTON DIST",
    "WEIGH STATION RT44",
    "STOP 2 TAUNTON CTR",
    "STOP 3 FALL RIVER IND",
    "REST STOP I95 S",
]

ROUTE_NAME  = "BOSTON-FALL RIVER FREIGHT RUN"
ROUTE_ORDER = [
    "DEPOT SOUTH BOSTON",
    "STOP 1 NORTON DIST",
    "WEIGH STATION RT44",
    "STOP 2 TAUNTON CTR",
    "STOP 3 FALL RIVER IND",
    "REST STOP I95 S",
]

STOP_WPTS = ["STOP 1 NORTON DIST", "STOP 2 TAUNTON CTR", "STOP 3 FALL RIVER IND"]


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
    """Award full_pts if required_order is a strict subsequence of route_points."""
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


def verify_commercial_truck_route_plan(traj, env_info, task_info):
    cfenv = env_info.get("copy_from_env")
    if not callable(cfenv):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        cfenv(r"C:\Users\Docker\commercial_truck_route_plan_result.json", tmp.name)
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
                "feedback": "GATE FAIL: BostonFallRiver_FreightRoute.gpx not found on Desktop. "
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
            score += 6
            fb.append(f"WPT OK: '{req}'")
        else:
            fb.append(f"WPT MISSING: '{req}'")

    # ------------------------------------------------ Route (20 pts)
    rt = _find_route(routes, ROUTE_NAME)
    if rt:
        score += 8
        fb.append(f"ROUTE OK: '{ROUTE_NAME}'")
        order_pts = _route_order_score(rt["points"], ROUTE_ORDER, 12)
        score += order_pts
        fb.append(f"  Route order: {order_pts}/12 (points: {rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{ROUTE_NAME}'")

    # ------------------------------------------------ Symbol checks (26 pts)
    bridge = _find_wpt(wpts, "BRIDGE HAZARD RT116")
    if bridge and "danger" in bridge.get("sym", "").lower():
        score += 10
        fb.append("SYMBOL OK: BRIDGE HAZARD RT116 = Danger")
    else:
        sym = bridge.get("sym", "") if bridge else "not found"
        fb.append(f"SYMBOL MISS: BRIDGE HAZARD RT116 sym='{sym}'")

    depot = _find_wpt(wpts, "DEPOT SOUTH BOSTON")
    if depot and "building" in depot.get("sym", "").lower():
        score += 8
        fb.append("SYMBOL OK: DEPOT SOUTH BOSTON = Building")
    else:
        sym = depot.get("sym", "") if depot else "not found"
        fb.append(f"SYMBOL MISS: DEPOT SOUTH BOSTON sym='{sym}'")

    weigh = _find_wpt(wpts, "WEIGH STATION RT44")
    if weigh and "car" in weigh.get("sym", "").lower():
        score += 8
        fb.append("SYMBOL OK: WEIGH STATION RT44 = Car")
    else:
        sym = weigh.get("sym", "") if weigh else "not found"
        fb.append(f"SYMBOL MISS: WEIGH STATION RT44 sym='{sym}'")

    # ------------------------------------------------ Comment quality (12 pts)
    stop_with_cmt = sum(
        1 for name in STOP_WPTS
        if (w := _find_wpt(wpts, name)) and (w.get("cmt") or w.get("desc"))
    )
    if stop_with_cmt >= 3:
        score += 12
        fb.append(f"COMMENTS OK: {stop_with_cmt}/3 STOP waypoints have comments")
    elif stop_with_cmt >= 1:
        score += 6
        fb.append(f"COMMENTS PARTIAL: {stop_with_cmt}/3 STOP waypoints have comments")
    else:
        fb.append("COMMENTS MISS: No STOP waypoints have comments")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb),
        "subscores": {
            "waypoints_present": sum(1 for r in REQUIRED_WPTS if _find_wpt(wpts, r)),
            "route_found": 1 if rt else 0,
            "stops_with_comments": stop_with_cmt,
        },
    }
