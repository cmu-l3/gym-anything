#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rental_asset_location_management(traj, env_info, task_info):
    """
    Verify rental asset internal location management task.
    
    Scoring (100 pts total, pass threshold: 80):
      20 pts: Dispatch - RED Komodo serials 002 and 005 moved to WH/Out on Rent
      10 pts: Dispatch - 5 V-Mount Batteries moved to WH/Out on Rent
      15 pts: Return - Mixer SD-MIX-011 moved back to WH/Stock
      15 pts: Return - 2 good Boom Mics moved to WH/Stock (bringing total to 12)
      20 pts: Return - 1 damaged Boom Mic moved to WH/Maintenance
      10 pts: Anti-gaming - Other RED Komodos untouched (remain in Stock)
      10 pts: Anti-gaming - Sony Venice untouched (remains in Out on Rent)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/rental_asset_result.json')
    pass_threshold = metadata.get('pass_threshold', 80)

    score = 0
    feedback_parts = []

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse export result: {e}"
        }
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    if "error" in result:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export script error: {result['error']}"
        }

    # --- Criterion 1: Dispatch RED Komodos (20 pts) ---
    red_locs = result.get('red_komodo_locations', {})
    if red_locs.get('RED-KOM-002') == 'WH/Out on Rent' and red_locs.get('RED-KOM-005') == 'WH/Out on Rent':
        score += 20
        feedback_parts.append("PASS: RED-KOM-002 and 005 correctly dispatched to Rent (+20)")
    else:
        feedback_parts.append(f"FAIL: RED Komodos not correctly dispatched. 002 is in {red_locs.get('RED-KOM-002')}, 005 is in {red_locs.get('RED-KOM-005')}")

    # --- Criterion 2: Dispatch V-Mount Batteries (10 pts) ---
    vmount_rent = result.get('vmount_battery_rent', 0)
    if vmount_rent == 5:
        score += 10
        feedback_parts.append("PASS: 5 V-Mount Batteries dispatched to Rent (+10)")
    else:
        feedback_parts.append(f"FAIL: Expected 5 V-Mount Batteries in Rent, found {vmount_rent}")

    # --- Criterion 3: Return Mixer (15 pts) ---
    mixer_locs = result.get('mixer_locations', {})
    if mixer_locs.get('SD-MIX-011') == 'WH/Stock':
        score += 15
        feedback_parts.append("PASS: Mixer SD-MIX-011 returned to Stock (+15)")
    else:
        feedback_parts.append(f"FAIL: Mixer SD-MIX-011 is in {mixer_locs.get('SD-MIX-011')} (Expected WH/Stock)")

    # --- Criterion 4: Return Good Boom Mics (15 pts) ---
    boom_stock = result.get('boom_mic_stock', 0)
    # Started with 10 in stock, 2 returned -> should be 12
    if boom_stock == 12:
        score += 15
        feedback_parts.append("PASS: 2 good Boom Mics returned to Stock (Total 12) (+15)")
    else:
        feedback_parts.append(f"FAIL: Expected 12 Boom Mics in Stock, found {boom_stock}")

    # --- Criterion 5: Route Damaged Boom Mic (20 pts) ---
    boom_maint = result.get('boom_mic_maint', 0)
    # Started with 0 in maint, 1 routed -> should be 1
    if boom_maint == 1:
        score += 20
        feedback_parts.append("PASS: 1 damaged Boom Mic correctly routed to Maintenance (+20)")
    else:
        feedback_parts.append(f"FAIL: Expected 1 Boom Mic in Maintenance, found {boom_maint}")

    # --- Criterion 6: Anti-Gaming Other RED Komodos (10 pts) ---
    other_reds = ['RED-KOM-001', 'RED-KOM-003', 'RED-KOM-004']
    all_other_reds_in_stock = all(red_locs.get(r) == 'WH/Stock' for r in other_reds)
    if all_other_reds_in_stock:
        score += 10
        feedback_parts.append("PASS: Other RED Komodos left untouched in Stock (+10)")
    else:
        feedback_parts.append("FAIL: Other RED Komodos were improperly moved")

    # --- Criterion 7: Anti-Gaming Sony Venice (10 pts) ---
    sony_locs = result.get('sony_venice_locations', {})
    if sony_locs.get('SNY-VEN-001') == 'WH/Out on Rent':
        score += 10
        feedback_parts.append("PASS: Sony Venice camera left untouched in Rent (+10)")
    else:
        feedback_parts.append(f"FAIL: Sony Venice was improperly moved to {sony_locs.get('SNY-VEN-001')}")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }