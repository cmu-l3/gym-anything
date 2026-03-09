#!/usr/bin/env python3
"""
Verifier for offshore_passage_plan task.

Scoring (100 pts total, pass >= 60):
  - GPX file exists and is new                      : gate
  - 10 required waypoints present by name            : 10 × 5 = 50 pts
  - Route 'NEWPORT BERMUDA 2024 RHUMB' found         :  6 pts
  - Rhumb route 8-point correct order                : 10 pts
  - Route 'NEWPORT BERMUDA 2024 WEATHER ALT' found   :  6 pts
  - Weather alt route 8-point correct order          :  8 pts
  - BRENTON REEF WHISTLE symbol = 'Buoy, White'      :  5 pts
  - ST. DAVIDS HEAD FINISH symbol = 'Flag, Blue'     :  5 pts
  - Both EMERGENCY waypoints have Medical Facility   :  5 pts
  - Gulf Stream waypoints have 'Danger' symbol       :  5 pts
  Total: 100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_WPTS = [
    "BRENTON REEF WHISTLE",
    "NANTUCKET LS FLOAT",
    "GEORGES BANK SE",
    "GULF STREAM ENTRY",
    "GULF STREAM EXIT",
    "BERMUDA APPROACH N",
    "NORTH ROCK BUOY",
    "ST. DAVIDS HEAD FINISH",
    "EMERGENCY - HALIFAX NS",
    "EMERGENCY - AZORES",
]

RHUMB_NAME = "NEWPORT BERMUDA 2024 RHUMB"
RHUMB_ORDER = [
    "BRENTON REEF WHISTLE",
    "NANTUCKET LS FLOAT",
    "GEORGES BANK SE",
    "GULF STREAM ENTRY",
    "GULF STREAM EXIT",
    "BERMUDA APPROACH N",
    "NORTH ROCK BUOY",
    "ST. DAVIDS HEAD FINISH",
]

WEATHER_ALT_NAME = "NEWPORT BERMUDA 2024 WEATHER ALT"
WEATHER_ALT_ORDER = [
    "BRENTON REEF WHISTLE",
    "NANTUCKET LS FLOAT",
    "EMERGENCY - HALIFAX NS",
    "GULF STREAM ENTRY",
    "GULF STREAM EXIT",
    "BERMUDA APPROACH N",
    "NORTH ROCK BUOY",
    "ST. DAVIDS HEAD FINISH",
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


def verify_offshore_passage_plan(traj, env_info, task_info):
    cfenv = env_info.get("copy_from_env")
    if not callable(cfenv):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        cfenv(r"C:\Users\Docker\offshore_passage_plan_result.json", tmp.name)
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
                "feedback": "GATE FAIL: Newport_Bermuda_2024_PassagePlan.gpx not found on Desktop."}

    if not data.get("gpx_is_new"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: GPX file predates task start."}

    wpts   = data.get("waypoints", [])
    routes = data.get("routes",    [])
    score  = 0
    fb     = []

    # ------------------------------------------------ Waypoints (50 pts)
    for req in REQUIRED_WPTS:
        w = _find_wpt(wpts, req)
        if w:
            score += 5
            fb.append(f"WPT OK: '{req}'")
        else:
            fb.append(f"WPT MISSING: '{req}'")

    # ------------------------------------------------ Rhumb route (16 pts)
    rhumb_rt = _find_route(routes, RHUMB_NAME)
    if rhumb_rt:
        score += 6
        fb.append(f"ROUTE OK: '{RHUMB_NAME}'")
        order_pts = _route_order_score(rhumb_rt["points"], RHUMB_ORDER, 10)
        score += order_pts
        fb.append(f"  Rhumb order: {order_pts}/10")
    else:
        fb.append(f"ROUTE MISSING: '{RHUMB_NAME}'")

    # ------------------------------------------------ Weather alt route (14 pts)
    alt_rt = _find_route(routes, WEATHER_ALT_NAME)
    if alt_rt:
        score += 6
        fb.append(f"ROUTE OK: '{WEATHER_ALT_NAME}'")
        order_pts = _route_order_score(alt_rt["points"], WEATHER_ALT_ORDER, 8)
        score += order_pts
        fb.append(f"  Weather alt order: {order_pts}/8")
    else:
        fb.append(f"ROUTE MISSING: '{WEATHER_ALT_NAME}'")

    # ------------------------------------------------ Symbol checks (20 pts)
    brenton = _find_wpt(wpts, "BRENTON REEF WHISTLE")
    if brenton and "buoy" in brenton.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: BRENTON REEF WHISTLE = Buoy, White")
    else:
        sym = brenton.get("sym", "") if brenton else "not found"
        fb.append(f"SYMBOL MISS: BRENTON REEF WHISTLE sym='{sym}'")

    finish = _find_wpt(wpts, "ST. DAVIDS HEAD FINISH")
    if finish and "flag" in finish.get("sym", "").lower() and "blue" in finish.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: ST. DAVIDS HEAD FINISH = Flag, Blue")
    else:
        sym = finish.get("sym", "") if finish else "not found"
        fb.append(f"SYMBOL MISS: ST. DAVIDS HEAD FINISH sym='{sym}'")

    emerg_med = sum(
        1 for n in ["EMERGENCY - HALIFAX NS", "EMERGENCY - AZORES"]
        if (w := _find_wpt(wpts, n)) and "medical" in w.get("sym", "").lower()
    )
    if emerg_med >= 2:
        score += 5
        fb.append("SYMBOL OK: Both EMERGENCY waypoints = Medical Facility")
    elif emerg_med == 1:
        score += 2
        fb.append("SYMBOL PARTIAL: 1 of 2 EMERGENCY waypoints = Medical Facility")
    else:
        fb.append("SYMBOL MISS: EMERGENCY waypoints missing Medical Facility symbol")

    gs_danger = sum(
        1 for n in ["GULF STREAM ENTRY", "GULF STREAM EXIT"]
        if (w := _find_wpt(wpts, n)) and "danger" in w.get("sym", "").lower()
    )
    if gs_danger >= 2:
        score += 5
        fb.append("SYMBOL OK: Both Gulf Stream waypoints = Danger")
    elif gs_danger == 1:
        score += 2
        fb.append("SYMBOL PARTIAL: 1 of 2 Gulf Stream waypoints = Danger")
    else:
        fb.append("SYMBOL MISS: Gulf Stream waypoints missing Danger symbol")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb),
        "subscores": {
            "waypoints_present": sum(1 for r in REQUIRED_WPTS if _find_wpt(wpts, r)),
            "routes_found": sum(1 for n in [RHUMB_NAME, WEATHER_ALT_NAME]
                                if _find_route(routes, n)),
        },
    }
