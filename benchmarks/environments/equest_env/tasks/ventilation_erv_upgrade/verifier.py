#!/usr/bin/env python3
"""
Verifier for ventilation_erv_upgrade task (eQUEST).

Task Requirements:
1. Update all Floor 3 (3.*) systems (5 total)
2. MIN-OUTSIDE-AIR = 0.30
3. RECOVER-EXHAUST = YES
4. ERV-RECOVER-TYPE = ENTHALPY
5. ERV-SENSIBLE-EFF = 0.76
6. ERV-LATENT-EFF = 0.65
7. Run Simulation (fresh .SIM file)

Scoring (100 pts total):
- Simulation ran: 10 pts
- Per system (5 systems total):
  - MIN-OUTSIDE-AIR (6 pts)
  - RECOVER-EXHAUST (4 pts)
  - ERV-RECOVER-TYPE (2 pts)
  - ERV-SENSIBLE-EFF (3 pts)
  - ERV-LATENT-EFF (3 pts)
  Total per system = 18 pts * 5 = 90 pts
  Grand Total = 90 + 10 = 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Windows path where result is saved inside the VM
RESULT_PATH = "C:\\Users\\Docker\\ventilation_erv_upgrade_result.json"

def verify_ventilation_erv_upgrade(traj, env_info, task_info):
    """
    Verify the ventilation and ERV upgrades in eQUEST.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data from environment. Ensure task script ran successfully."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Execution (10 pts)
    sim_ran = result.get('sim_file_is_new', False)
    if sim_ran:
        score += 10
        feedback_parts.append("Simulation executed successfully (+10).")
    else:
        feedback_parts.append("Simulation NOT run or file not saved after start time (0/10).")

    # 2. Verify System Parameters
    systems_data = result.get('systems_analyzed', {})
    
    # Filter for systems starting with "3."
    target_systems = {k: v for k, v in systems_data.items() if k.startswith("3.")}
    
    if len(target_systems) == 0:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No Floor 3 systems found in project file."
        }

    systems_checked = 0
    total_system_score = 0
    
    for sys_name, params in target_systems.items():
        systems_checked += 1
        sys_feedback = []
        sys_score = 0
        
        # Check MIN-OUTSIDE-AIR (Target: 0.30 ± 0.02)
        moa = params.get('min_outside_air')
        try:
            moa_val = float(moa) if moa is not None else 0.0
            if 0.28 <= moa_val <= 0.32:
                sys_score += 6
            else:
                sys_feedback.append(f"OA={moa_val} (exp 0.30)")
        except:
            sys_feedback.append("OA=Missing")

        # Check RECOVER-EXHAUST (Target: YES)
        re = str(params.get('recover_exhaust', 'NO')).upper()
        if re == 'YES':
            sys_score += 4
        else:
            sys_feedback.append(f"Recov={re} (exp YES)")

        # Check ERV-RECOVER-TYPE (Target: ENTHALPY)
        ert = str(params.get('erv_recover_type', 'None')).upper()
        if ert == 'ENTHALPY':
            sys_score += 2
        else:
            sys_feedback.append(f"Type={ert} (exp ENTHALPY)")

        # Check ERV-SENSIBLE-EFF (Target: 0.76 ± 0.02)
        ese = params.get('erv_sensible_eff')
        try:
            ese_val = float(ese) if ese is not None else 0.0
            if 0.74 <= ese_val <= 0.78:
                sys_score += 3
            else:
                sys_feedback.append(f"Sens={ese_val} (exp 0.76)")
        except:
            sys_feedback.append("Sens=Missing")

        # Check ERV-LATENT-EFF (Target: 0.65 ± 0.02)
        ele = params.get('erv_latent_eff')
        try:
            ele_val = float(ele) if ele is not None else 0.0
            if 0.63 <= ele_val <= 0.67:
                sys_score += 3
            else:
                sys_feedback.append(f"Lat={ele_val} (exp 0.65)")
        except:
            sys_feedback.append("Lat=Missing")

        total_system_score += sys_score
        
        # Add feedback for failures only to keep it concise
        if sys_score < 18:
            feedback_parts.append(f"{sys_name}: [{', '.join(sys_feedback)}]")

    score += total_system_score
    
    # Calculate summary feedback
    feedback_parts.append(f"Systems Checked: {systems_checked}. System Score: {total_system_score}/90.")

    # Pass Criteria
    # Need score >= 60 AND Simulation must have run
    passed = (score >= 60) and sim_ran

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }