#!/usr/bin/env python3
"""
Verifier for tactical_patrol_routes task.

Scoring (100 pts total, pass >= 60):
  - GPX file exists and is new                  : gate
  - 7 required waypoints present by name         : 7 × 6 = 42 pts
  - Route 'ROUTE BLACK PRIMARY' (4 pts, order)   : 12 pts (6 found + 6 order)
  - Route 'ROUTE RED ALTERNATE' (5 pts, order)   : 16 pts (8 found + 8 order)
  - Route 'ROUTE GREEN EXFIL' (3 pts, order)     : 12 pts (6 found + 6 order)
  - PATROL BASE FOXTROT has 'Flag, Blue'          :  5 pts
  - OBJ ALPHA TARGET has 'Flag, Red'              :  5 pts
  - LZ YANKEE MEDEVAC has 'Airport'               :  8 pts
  Total: 100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_WPTS = [
    "PATROL BASE FOXTROT",
    "OBJ ALPHA TARGET",
    "OBJ BRAVO COMMS",
    "RP1 CHECKPOINT IRON",
    "RP2 CHECKPOINT STEEL",
    "LZ YANKEE MEDEVAC",
    "BP NORTH BLOCK",
]

BLACK_NAME = "ROUTE BLACK PRIMARY"
BLACK_ORDER = [
    "PATROL BASE FOXTROT",
    "RP1 CHECKPOINT IRON",
    "OBJ ALPHA TARGET",
    "RP2 CHECKPOINT STEEL",
    "PATROL BASE FOXTROT",
]

RED_NAME = "ROUTE RED ALTERNATE"
RED_ORDER = [
    "PATROL BASE FOXTROT",
    "OBJ BRAVO COMMS",
    "RP2 CHECKPOINT STEEL",
    "OBJ ALPHA TARGET",
    "RP1 CHECKPOINT IRON",
    "PATROL BASE FOXTROT",
]

GREEN_NAME = "ROUTE GREEN EXFIL"
GREEN_ORDER = [
    "OBJ ALPHA TARGET",
    "LZ YANKEE MEDEVAC",
    "BP NORTH BLOCK",
    "PATROL BASE FOXTROT",
]


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


def verify_tactical_patrol_routes(traj, env_info, task_info):
    cfenv = env_info.get("copy_from_env")
    if not callable(cfenv):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        cfenv(r"C:\Users\Docker\tactical_patrol_routes_result.json", tmp.name)
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
                "feedback": "GATE FAIL: TacOp_Exercise_Foxtrot.gpx not found on Desktop."}

    if not data.get("gpx_is_new"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: GPX file predates task start."}

    wpts   = data.get("waypoints", [])
    routes = data.get("routes",    [])
    score  = 0
    fb     = []

    # ------------------------------------------------ Waypoints (42 pts)
    for req in REQUIRED_WPTS:
        w = _find_wpt(wpts, req)
        if w:
            score += 6
            fb.append(f"WPT OK: '{req}'")
        else:
            fb.append(f"WPT MISSING: '{req}'")

    # ------------------------------------------------ Route BLACK (12 pts)
    black_rt = _find_route(routes, BLACK_NAME)
    if black_rt:
        score += 6
        fb.append(f"ROUTE OK: '{BLACK_NAME}'")
        order_pts = _route_order_score(black_rt["points"], BLACK_ORDER, 6)
        score += order_pts
        fb.append(f"  BLACK order: {order_pts}/6 (points: {black_rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{BLACK_NAME}'")

    # ------------------------------------------------ Route RED (16 pts)
    red_rt = _find_route(routes, RED_NAME)
    if red_rt:
        score += 8
        fb.append(f"ROUTE OK: '{RED_NAME}'")
        order_pts = _route_order_score(red_rt["points"], RED_ORDER, 8)
        score += order_pts
        fb.append(f"  RED order: {order_pts}/8 (points: {red_rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{RED_NAME}'")

    # ------------------------------------------------ Route GREEN (12 pts)
    green_rt = _find_route(routes, GREEN_NAME)
    if green_rt:
        score += 6
        fb.append(f"ROUTE OK: '{GREEN_NAME}'")
        order_pts = _route_order_score(green_rt["points"], GREEN_ORDER, 6)
        score += order_pts
        fb.append(f"  GREEN order: {order_pts}/6 (points: {green_rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{GREEN_NAME}'")

    # ------------------------------------------------ Symbol checks (18 pts)
    pb = _find_wpt(wpts, "PATROL BASE FOXTROT")
    if pb and "flag" in pb.get("sym", "").lower() and "blue" in pb.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: PATROL BASE FOXTROT = Flag, Blue")
    else:
        sym = pb.get("sym", "") if pb else "not found"
        fb.append(f"SYMBOL MISS: PATROL BASE FOXTROT sym='{sym}'")

    alpha = _find_wpt(wpts, "OBJ ALPHA TARGET")
    if alpha and "flag" in alpha.get("sym", "").lower() and "red" in alpha.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: OBJ ALPHA TARGET = Flag, Red")
    else:
        sym = alpha.get("sym", "") if alpha else "not found"
        fb.append(f"SYMBOL MISS: OBJ ALPHA TARGET sym='{sym}'")

    lz = _find_wpt(wpts, "LZ YANKEE MEDEVAC")
    if lz and "airport" in lz.get("sym", "").lower():
        score += 8
        fb.append("SYMBOL OK: LZ YANKEE MEDEVAC = Airport")
    else:
        sym = lz.get("sym", "") if lz else "not found"
        fb.append(f"SYMBOL MISS: LZ YANKEE MEDEVAC sym='{sym}'")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb),
        "subscores": {
            "waypoints_present": sum(1 for r in REQUIRED_WPTS if _find_wpt(wpts, r)),
            "routes_found": sum(1 for n in [BLACK_NAME, RED_NAME, GREEN_NAME]
                                if _find_route(routes, n)),
        },
    }
