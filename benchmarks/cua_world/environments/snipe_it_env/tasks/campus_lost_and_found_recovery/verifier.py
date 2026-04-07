#!/usr/bin/env python3
"""
Verifier for campus_lost_and_found_recovery task.

Scoring breakdown (100 points):
  C1: Location 'Security Holding' created (10 pts)
  C2: Status Label 'Recovered - Holding' created & Undeployable (10 pts)
  C3: Device 1 (SNDELL-992211) checked in, status updated, location updated (20 pts)
  C4: Device 2 (SNAPPLE-445566) status updated, location updated (no check-in needed) (20 pts)
  C5: Device 3 (SNPOLY-778899) checked in, status updated, location updated (20 pts)
  C6: Check-in note 'Recovered by Campus Security' applied to Device 1 & 3 (10 pts)
  C7: Anti-gaming / No collateral damage (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/lost_and_found_result.json"

def verify_lost_and_found_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    loc = result.get("location", {})
    stat = result.get("status_label", {})
    assets = result.get("assets", {})
    logs = result.get("logs", {})
    ag = result.get("anti_gaming", {})

    target_loc_id = str(loc.get("id", "loc_none"))
    target_stat_id = str(stat.get("id", "stat_none"))

    # Check Do-Nothing
    if not loc.get("found") and not stat.get("found") and logs.get("total_checkin_notes_count", 0) == 0:
        a1 = assets.get("device_1", {})
        if a1.get("found") and a1.get("is_assigned") == True:
            return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No required entities created and no devices checked in."}

    # C1: Location
    if loc.get("found"):
        score += 10
        feedback.append("C1: Location 'Security Holding' exists (+10)")
    else:
        feedback.append("C1: Location 'Security Holding' not found (+0)")

    # C2: Status Label
    if stat.get("found"):
        # Undeployable means deployable=0, pending=0, archived=0
        if str(stat.get("deployable")) == "0" and str(stat.get("pending")) == "0" and str(stat.get("archived")) == "0":
            score += 10
            feedback.append("C2: Status Label 'Recovered - Holding' exists and is Undeployable (+10)")
        else:
            score += 5
            feedback.append("C2: Status Label exists but is NOT configured as 'Undeployable' (+5)")
    else:
        feedback.append("C2: Status Label 'Recovered - Holding' not found (+0)")

    # Asset Verification Helper
    def verify_asset(name, asset_data, requires_checkin):
        pts = 0
        msgs = []
        if not asset_data.get("found"):
            return 0, [f"{name} not found in database (was it deleted?) (+0)"]

        # 1. Location matches
        if str(asset_data.get("location_id")) == target_loc_id and loc.get("found"):
            pts += 8
            msgs.append(f"{name} location updated")
        else:
            msgs.append(f"{name} location incorrect")

        # 2. Status matches
        if str(asset_data.get("status_id")) == target_stat_id and stat.get("found"):
            pts += 8
            msgs.append(f"{name} status updated")
        else:
            msgs.append(f"{name} status incorrect")

        # 3. Assignment
        if asset_data.get("is_assigned"):
            msgs.append(f"{name} is still checked out")
        else:
            if requires_checkin:
                pts += 4
                msgs.append(f"{name} checked in")
            else:
                pts += 4
                msgs.append(f"{name} unassigned (correct)")

        return pts, msgs

    # C3: Device 1 (Needs checkin)
    a1_pts, a1_msgs = verify_asset("Device 1", assets.get("device_1", {}), True)
    score += a1_pts
    feedback.append(f"C3: {', '.join(a1_msgs)} (+{a1_pts})")

    # C4: Device 2 (Was never checked out, shouldn't be assigned)
    a2_pts, a2_msgs = verify_asset("Device 2", assets.get("device_2", {}), False)
    score += a2_pts
    feedback.append(f"C4: {', '.join(a2_msgs)} (+{a2_pts})")

    # C5: Device 3 (Needs checkin)
    a3_pts, a3_msgs = verify_asset("Device 3", assets.get("device_3", {}), True)
    score += a3_pts
    feedback.append(f"C5: {', '.join(a3_msgs)} (+{a3_pts})")

    # C6: Checkin Notes
    notes_score = 0
    a1_note = int(logs.get("a1_has_note", 0)) > 0
    a3_note = int(logs.get("a3_has_note", 0)) > 0
    
    if a1_note:
        notes_score += 5
    if a3_note:
        notes_score += 5
        
    score += notes_score
    if notes_score == 10:
        feedback.append("C6: Correct check-in notes applied to both checked-out devices (+10)")
    elif notes_score > 0:
        feedback.append(f"C6: Correct check-in note applied to some devices (+{notes_score})")
    else:
        feedback.append("C6: Missing required check-in notes 'Recovered by Campus Security' (+0)")

    # C7: Anti-gaming
    try:
        init_cnt = int(ag.get("initial_asset_count", 0))
        cur_cnt = int(ag.get("current_asset_count", 0))
    except (ValueError, TypeError):
        init_cnt = 0
        cur_cnt = 0

    if cur_cnt >= init_cnt and assets.get("device_1", {}).get("found") and assets.get("device_2", {}).get("found") and assets.get("device_3", {}).get("found"):
        score += 10
        feedback.append("C7: Anti-gaming checks passed (no original assets deleted) (+10)")
    else:
        feedback.append("C7: Anti-gaming check failed - assets were deleted (+0)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }