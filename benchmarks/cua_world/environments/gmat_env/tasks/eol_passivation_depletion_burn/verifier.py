#!/usr/bin/env python3
import tempfile
import json
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_eol_passivation_depletion_burn(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    exp_init_mass = metadata.get('expected_initial_mass_kg', 500.0)
    exp_final_mass = metadata.get('expected_final_mass_kg', 475.0)
    exp_duration = metadata.get('expected_burn_duration_sec', 2508.0)
    dur_tol = metadata.get('burn_duration_tolerance_sec', 50.0)
    alt_min = metadata.get('periapsis_alt_min_km', 300.0)
    alt_max = metadata.get('periapsis_alt_max_km', 650.0)

    scores = {
        "hardware_configured": 20,
        "burn_configured": 20,
        "mass_depletion_logic": 15,
        "mass_reported": 15,
        "duration_reported": 15,
        "perigee_lowered": 15
    }
    
    total_score = 0
    feedback = []
    
    # Flags for pass conditions
    has_burn = False
    perigee_ok = False

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    script_path = task_result.get('script_path', '/home/ga/Documents/missions/passivation.script')
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/passivation_report.txt')
    
    script_file = task_result.get('script_file', {})
    report_file = task_result.get('report_file', {})
    
    script_content = ""
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
                
    report_content = ""
    if isinstance(report_file, dict) and report_file.get('exists'):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read report file: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # 1. Hardware Configured
    has_tank = bool(re.search(r'Create\s+ChemicalTank', script_content, re.IGNORECASE))
    has_thruster = bool(re.search(r'Create\s+ChemicalThruster', script_content, re.IGNORECASE))
    if has_tank and has_thruster:
        total_score += scores["hardware_configured"]
        feedback.append("Hardware (Tank & Thruster) configured correctly.")
    else:
        feedback.append("Hardware configuration incomplete (missing Tank or Thruster).")
        
    # 2. Burn Configured
    if bool(re.search(r'Create\s+FiniteBurn', script_content, re.IGNORECASE)):
        total_score += scores["burn_configured"]
        has_burn = True
        feedback.append("FiniteBurn configured correctly.")
    else:
        feedback.append("FiniteBurn configuration missing.")
        
    # 3. Mass Depletion Logic
    mass_depletion = False
    propagate_blocks = re.findall(r'Propagate\s+.*?{(.*?)}', script_content, re.IGNORECASE | re.DOTALL)
    for block in propagate_blocks:
        if 'Mass' in block and ('0' in block or '475' in block):
            mass_depletion = True
            break
            
    if not mass_depletion and re.search(r'\.Mass\s*<[=]?\s*0\.?[0-9]*', script_content, re.IGNORECASE):
        mass_depletion = True
        
    if mass_depletion:
        total_score += scores["mass_depletion_logic"]
        feedback.append("Dynamic mass depletion stopping condition used.")
    else:
        feedback.append("Dynamic mass depletion logic not detected.")

    # 4. Extract values from report
    def get_val(key):
        match = re.search(fr'{key}\s*[:=]\s*([0-9eE\.\+\-]+)', report_content, re.IGNORECASE)
        if match:
            try: return float(match.group(1))
            except: return None
        return None

    init_mass = get_val('initial_mass_kg')
    final_mass = get_val('final_mass_kg')
    periapsis = get_val('final_periapsis_alt_km')
    burn_dur = get_val('burn_duration_sec')
    
    # Evaluate report values
    if init_mass is not None and final_mass is not None:
        if abs(init_mass - exp_init_mass) < 5.0 and abs(final_mass - exp_final_mass) < 5.0:
            total_score += scores["mass_reported"]
            feedback.append(f"Mass reported correctly ({init_mass}->{final_mass} kg).")
        else:
            feedback.append(f"Mass reported incorrectly (found {init_mass}->{final_mass} kg).")
    else:
        feedback.append("Mass values not found in report.")
        
    if burn_dur is not None:
        if abs(burn_dur - exp_duration) <= dur_tol:
            total_score += scores["duration_reported"]
            feedback.append(f"Burn duration correct ({burn_dur} s).")
        else:
            feedback.append(f"Burn duration incorrect or inaccurate (found {burn_dur} s, expected ~{exp_duration} s).")
    else:
        feedback.append("Burn duration not found in report.")
        
    if periapsis is not None:
        if alt_min <= periapsis <= alt_max:
            total_score += scores["perigee_lowered"]
            perigee_ok = True
            feedback.append(f"Final periapsis lowered successfully ({periapsis} km).")
        else:
            feedback.append(f"Final periapsis out of expected bounds ({periapsis} km).")
    else:
        feedback.append("Final periapsis not found in report.")

    passed = (total_score >= 70) and has_burn and perigee_ok
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }