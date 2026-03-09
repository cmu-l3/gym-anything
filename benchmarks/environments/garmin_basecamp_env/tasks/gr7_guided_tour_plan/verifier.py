#!/usr/bin/env python3
"""
Verifier for gr7_guided_tour_plan task.

Scoring (100 pts total, pass >= 60):
  - GPX file exists and is new                 : gate
  - Track imported (>=1 track in GPX)          : 10 pts
  - 7 required waypoints present by name       : 7 × 7 = 49 pts
  - Route 'GR7 DOLE-LANGRES 5 JOURS' found    : 10 pts
  - Route 7-point correct order                : 15 pts
  - DEPART DOLE GARE has 'Car' symbol          :  5 pts
  - ARRIVEE LANGRES has 'Flag, Blue' symbol    :  5 pts
  - At least 2 NUIT waypoints have 'Building'  :  6 pts
  Total: 100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_WPTS = [
    "DEPART DOLE GARE",
    "REPAS LABERGEMENT",
    "NUIT 1 PESMES",
    "NUIT 2 GRAY",
    "RAVITAILLEMENT CHAMPLITTE",
    "NUIT 3 JUSSEY",
    "ARRIVEE LANGRES",
]

ROUTE_NAME = "GR7 DOLE-LANGRES 5 JOURS"
ROUTE_ORDER = [
    "DEPART DOLE GARE",
    "REPAS LABERGEMENT",
    "NUIT 1 PESMES",
    "NUIT 2 GRAY",
    "RAVITAILLEMENT CHAMPLITTE",
    "NUIT 3 JUSSEY",
    "ARRIVEE LANGRES",
]

NUIT_WPTS = ["NUIT 1 PESMES", "NUIT 2 GRAY", "NUIT 3 JUSSEY"]


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


def verify_gr7_guided_tour_plan(traj, env_info, task_info):
    cfenv = env_info.get("copy_from_env")
    if not callable(cfenv):
        return {"passed": False, "score": 0,
                "feedback": "ERROR: copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        cfenv(r"C:\Users\Docker\gr7_guided_tour_plan_result.json", tmp.name)
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
                "feedback": "GATE FAIL: GR7_Guide_DoleLangres.gpx not found on Desktop."}

    if not data.get("gpx_is_new"):
        return {"passed": False, "score": 0,
                "feedback": "GATE FAIL: GPX file predates task start."}

    wpts   = data.get("waypoints",   [])
    routes = data.get("routes",      [])
    trks   = data.get("track_count", 0)
    score  = 0
    fb     = []

    # ------------------------------------------------ Track import (10 pts)
    if trks >= 1:
        score += 10
        fb.append(f"TRACK OK: {trks} track(s) in exported GPX")
    else:
        fb.append("TRACK MISSING: No tracks in GPX — dole_langres_track.gpx was not imported")

    # ------------------------------------------------ Waypoints (49 pts)
    for req in REQUIRED_WPTS:
        w = _find_wpt(wpts, req)
        if w:
            score += 7
            fb.append(f"WPT OK: '{req}'")
        else:
            fb.append(f"WPT MISSING: '{req}'")

    # ------------------------------------------------ Route (25 pts)
    rt = _find_route(routes, ROUTE_NAME)
    if rt:
        score += 10
        fb.append(f"ROUTE OK: '{ROUTE_NAME}'")
        order_pts = _route_order_score(rt["points"], ROUTE_ORDER, 15)
        score += order_pts
        fb.append(f"  Route order: {order_pts}/15 (points: {rt['points']})")
    else:
        fb.append(f"ROUTE MISSING: '{ROUTE_NAME}'")

    # ------------------------------------------------ Symbol checks (16 pts)
    depart = _find_wpt(wpts, "DEPART DOLE GARE")
    if depart and "car" in depart.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: DEPART DOLE GARE = Car")
    else:
        sym = depart.get("sym", "") if depart else "not found"
        fb.append(f"SYMBOL MISS: DEPART DOLE GARE sym='{sym}'")

    arrivee = _find_wpt(wpts, "ARRIVEE LANGRES")
    if arrivee and "flag" in arrivee.get("sym", "").lower() and "blue" in arrivee.get("sym", "").lower():
        score += 5
        fb.append("SYMBOL OK: ARRIVEE LANGRES = Flag, Blue")
    else:
        sym = arrivee.get("sym", "") if arrivee else "not found"
        fb.append(f"SYMBOL MISS: ARRIVEE LANGRES sym='{sym}'")

    nuit_building = sum(
        1 for n in NUIT_WPTS
        if (w := _find_wpt(wpts, n)) and "building" in w.get("sym", "").lower()
    )
    if nuit_building >= 2:
        score += 6
        fb.append(f"SYMBOL OK: {nuit_building}/3 NUIT waypoints = Building")
    elif nuit_building == 1:
        score += 3
        fb.append("SYMBOL PARTIAL: 1/3 NUIT waypoints = Building")
    else:
        fb.append("SYMBOL MISS: NUIT waypoints missing Building symbol")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb),
        "subscores": {
            "track_imported": trks >= 1,
            "waypoints_present": sum(1 for r in REQUIRED_WPTS if _find_wpt(wpts, r)),
            "route_found": 1 if rt else 0,
        },
    }
