#!/usr/bin/env python3
"""
Verifier for ifr_valley_routing task.

Stub verifier — actual verification is done externally via VLM checklist
evaluator. This programmatic verifier provides basic checks on exported
artifacts for supplementary scoring.

Key findings from live testing:
- Avare uses 3-letter FAA codes (SJC, SAC, MOD) not 4-letter ICAO
- Plans stored in user.db SQLite (table 'plans'), not CSV files
- VOR entries have type "Navaid", airports have type "Base"
- ChartType key absent from preferences = default Sectional
- No TAS/fuel burn settings exist in Avare preferences UI

Scoring (100 points total), pass threshold = 65:

  Flight plan saved as IFR_VALLEY              :  5 pts
  Plan has correct waypoint count (5)           :  5 pts
  Plan has SJC as Navaid (VOR distinction #1)   : 12 pts
  Plan has MOD as Navaid (VOR distinction #2)   : 12 pts
  Plan has SAC as Navaid (VOR distinction #3)   : 12 pts
  Plan has SJC as Airport (departure)           :  4 pts
  Plan has SAC as Airport (destination)          :  4 pts
  No airport substitutions for VOR waypoints    : -15 pts penalty each
  Chart type = IFR Low                          : 16 pts
  Preferences were retrieved                    :  5 pts
  App was running                               :  5 pts
  VLM: A/FD (CSup) for SAC viewed              : 20 pts (via external VLM)
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_ifr_valley_routing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []

    # ------------------------------------------------------------------ #
    # Retrieve exported result JSON                                       #
    # ------------------------------------------------------------------ #
    result = {}
    with tempfile.TemporaryDirectory() as tmp:
        result_path = os.path.join(tmp, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", result_path)
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            logger.warning("Could not retrieve task_result.json: %s", e)
            return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}

    # ------------------------------------------------------------------ #
    # 1. Flight plan existence and VOR distinction (54 pts)               #
    # ------------------------------------------------------------------ #
    if result.get("plan_exists"):
        score += 5
        feedback.append("Plan IFR_VALLEY saved. (+5)")
    else:
        feedback.append("Plan IFR_VALLEY not found. (+0)")

    # Waypoint count
    wpt_count = result.get("plan_waypoint_count", 0)
    if wpt_count >= 5:
        score += 5
        feedback.append(f"Waypoint count {wpt_count} >= 5. (+5)")
    elif wpt_count >= 3:
        score += 2
        feedback.append(f"Waypoint count {wpt_count}, expected >= 5. (+2)")
    else:
        feedback.append(f"Waypoint count {wpt_count}, expected >= 5. (+0)")

    # VOR distinction checks — the critical challenge
    vor_correct_count = 0

    # SJC VOR (Navaid, not Airport)
    if result.get("plan_has_navaid_sjc"):
        score += 12
        vor_correct_count += 1
        feedback.append("SJC VOR (Navaid) in plan. (+12)")
    else:
        feedback.append("SJC VOR (Navaid) not found in plan. (+0)")

    # MOD VOR (Navaid, not Airport)
    if result.get("plan_has_navaid_mod"):
        score += 12
        vor_correct_count += 1
        feedback.append("MOD VOR (Navaid) in plan. (+12)")
    else:
        feedback.append("MOD VOR (Navaid) not found in plan. (+0)")

    if result.get("plan_has_airport_mod"):
        score -= 15
        feedback.append("MOD airport used instead of MOD VOR. (-15 penalty)")

    # SAC VOR (Navaid)
    if result.get("plan_has_navaid_sac"):
        score += 12
        vor_correct_count += 1
        feedback.append("SAC VOR (Navaid) in plan. (+12)")
    else:
        feedback.append("SAC VOR (Navaid) not found in plan. (+0)")

    # SJC as departure airport
    if result.get("plan_has_airport_sjc"):
        score += 4
        feedback.append("SJC airport (departure) in plan. (+4)")

    # SAC as destination airport
    if result.get("plan_has_airport_sac"):
        score += 4
        feedback.append("SAC airport (destination) in plan. (+4)")

    # ------------------------------------------------------------------ #
    # 2. Chart type (16 pts)                                              #
    # ------------------------------------------------------------------ #
    chart_type = result.get("chart_type", "")
    if chart_type and "ifr" in chart_type.lower() and "low" in chart_type.lower():
        score += 16
        feedback.append(f"Chart type is '{chart_type}'. (+16)")
    else:
        feedback.append(f"Chart type is '{chart_type}', expected IFR Low. (+0)")

    # ------------------------------------------------------------------ #
    # 3. App state and prefs (10 pts)                                     #
    # ------------------------------------------------------------------ #
    if result.get("app_running"):
        score += 5
        feedback.append("App was running at export time. (+5)")

    if result.get("prefs_copied"):
        score += 5
        feedback.append("Preferences file retrieved. (+5)")

    # ------------------------------------------------------------------ #
    # 4. VLM placeholder — CSup for SAC viewed (20 pts)                  #
    # Actual VLM verification is handled externally.                      #
    # ------------------------------------------------------------------ #
    if result.get("plan_exists") and vor_correct_count >= 2:
        score += 20
        feedback.append("Plan + VOR distinction; partial VLM credit. (+20)")

    # ------------------------------------------------------------------ #
    # Final assessment                                                    #
    # ------------------------------------------------------------------ #
    score = max(0, min(100, score))
    passed = score >= 65 and result.get("plan_exists", False) and vor_correct_count >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
