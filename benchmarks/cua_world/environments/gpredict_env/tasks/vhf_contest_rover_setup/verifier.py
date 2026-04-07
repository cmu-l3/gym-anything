#!/usr/bin/env python3
"""
Verifier for vhf_contest_rover_setup task.

Task: Configure GPredict for a VHF/UHF contest rover:
  1. Create Rover_EN82 ground station (42.5 N, 83.5 W, 250m)
  2. Create Rover_EN81 ground station (41.5 N, 83.5 W, 220m)
  3. Create Rover_EN91 ground station (41.5 N, 81.5 W, 200m)
  4. Create Contest_Rover module with sats: 7530, 24278, 27607, 43017, 43137
  5. Configure Contest_Rover layout to 'Polar only' (LAYOUT=2)
  6. Bind Contest_Rover to Rover_EN82 ground station
  7. Enable automatic TLE updates

Scoring (100 points, pass >= 70):
  - Ground stations (10 pts each): 30 pts
  - Contest_Rover module and satellites: 20 pts
  - Layout configured to Polar only: 20 pts
  - Module bound to Rover_EN82: 15 pts
  - Auto-update enabled: 15 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_vhf_contest_rover_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/vhf_contest_rover_setup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    
    # 1. Ground stations (10 pts each, total 30)
    en82 = result.get('en82', {})
    en81 = result.get('en81', {})
    en91 = result.get('en91', {})
    
    valid_qth_count = 0
    
    if en82.get('exists'):
        if (_close_enough(en82.get('lat'), 42.5) and 
            _close_enough(en82.get('lon'), -83.5) and 
            _close_enough(en82.get('alt'), 250, tolerance=10)):
            score += 10
            valid_qth_count += 1
            feedback_parts.append("Rover_EN82 correct")
        else:
            feedback_parts.append("Rover_EN82 exists but coords/alt incorrect")
    else:
        feedback_parts.append("Rover_EN82 NOT FOUND")

    if en81.get('exists'):
        if (_close_enough(en81.get('lat'), 41.5) and 
            _close_enough(en81.get('lon'), -83.5) and 
            _close_enough(en81.get('alt'), 220, tolerance=10)):
            score += 10
            valid_qth_count += 1
            feedback_parts.append("Rover_EN81 correct")
        else:
            feedback_parts.append("Rover_EN81 exists but coords/alt incorrect")
    else:
        feedback_parts.append("Rover_EN81 NOT FOUND")
        
    if en91.get('exists'):
        if (_close_enough(en91.get('lat'), 41.5) and 
            _close_enough(en91.get('lon'), -81.5) and 
            _close_enough(en91.get('alt'), 200, tolerance=10)):
            score += 10
            valid_qth_count += 1
            feedback_parts.append("Rover_EN91 correct")
        else:
            feedback_parts.append("Rover_EN91 exists but coords/alt incorrect")
    else:
        feedback_parts.append("Rover_EN91 NOT FOUND")

    # 2. Module & Satellites (20 pts)
    if result.get('mod_exists'):
        sats = result.get('mod_satellites', '')
        req_sats = ['7530', '24278', '27607', '43017', '43137']
        missing = [s for s in req_sats if s not in sats and str(int(s)) not in sats]
        
        if not missing:
            score += 20
            feedback_parts.append("Contest_Rover module has all required satellites")
        else:
            # Partial credit
            score += max(0, 20 - (len(missing) * 4))
            feedback_parts.append(f"Contest_Rover module missing: {', '.join(missing)}")
    else:
        feedback_parts.append("Contest_Rover module NOT FOUND")
        
    # 3. Module QTH Override (15 pts)
    if result.get('mod_exists'):
        mod_qth = result.get('mod_qth', '')
        if 'Rover_EN82' in mod_qth or 'rover_en82' in mod_qth.lower():
            score += 15
            feedback_parts.append("Contest_Rover module correctly bound to Rover_EN82")
        else:
            feedback_parts.append(f"Contest_Rover module bound to '{mod_qth}' instead of 'Rover_EN82.qth'")

    # 4. Layout (20 pts)
    layout_ok = False
    if result.get('mod_exists'):
        mod_layout = result.get('mod_layout', '')
        if mod_layout == '2':
            score += 20
            layout_ok = True
            feedback_parts.append("Contest_Rover layout correctly set to Polar only")
        else:
            feedback_parts.append(f"Contest_Rover layout is '{mod_layout}' (expected '2' for Polar only)")

    # 5. Auto Update (15 pts)
    if result.get('auto_update'):
        score += 15
        feedback_parts.append("Auto TLE update enabled")
    else:
        feedback_parts.append("Auto TLE update NOT enabled")

    # Pass condition: 70 points WITH Layout configured and at least 2 QTH
    passed = (score >= 70) and layout_ok and (valid_qth_count >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }