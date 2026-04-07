#!/usr/bin/env python3
"""Verifier for model_generic_small_hydro task.

Checks mathematical consistency, valid ranges, and file artifacts to verify the 
small hydropower PySAM model.
"""

import json
import tempfile
import os
import math

def verify_model_generic_small_hydro(traj, env_info, task_info):
    """Verify generic small hydro model was created successfully.
    
    Scoring: 100 points max
    - Artifacts exist & modified (20 pts)
    - Python script contains PySAM imports (10 pts)
    - JSON contains all required keys (10 pts)
    - Inputs matched (nameplate, install cost) (10 pts)
    - Energy mathematically correct & in range (15 pts)
    - Capacity factor mathematically correct & in range (10 pts)
    - Monthly seasonal profile matches expected curve (10 pts)
    - LCOE mathematically correct & in range (15 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_energy_min = metadata.get('expected_energy_min', 2000000)
    expected_energy_max = metadata.get('expected_energy_max', 2300000)
    expected_cf_min = metadata.get('expected_cf_min', 45)
    expected_cf_max = metadata.get('expected_cf_max', 55)
    expected_lcoe_min = metadata.get('expected_lcoe_min', 7.0)
    expected_lcoe_max = metadata.get('expected_lcoe_max', 13.0)

    # 1. Copy the high-level task summary
    temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_summary.name)
        with open(temp_summary.name, 'r') as f:
            summary = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task summary: {e}"}
    finally:
        if os.path.exists(temp_summary.name):
            os.unlink(temp_summary.name)

    score = 0
    feedback_parts = []
    
    # Check artifacts
    script_exists = summary.get('script_exists', False)
    json_exists = summary.get('json_exists', False)
    script_modified = summary.get('script_modified', False)
    json_modified = summary.get('json_modified', False)
    has_imports = summary.get('has_imports', False)
    
    if script_exists and json_exists:
        if script_modified and json_modified:
            score += 20
            feedback_parts.append("Script and JSON created during task")
        else:
            score += 5
            feedback_parts.append("Files exist but may not be newly modified")
    else:
        feedback_parts.append("Missing required output files")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if has_imports:
        score += 10
        feedback_parts.append("PySAM imports found")
    else:
        feedback_parts.append("Missing required PySAM imports in script")

    # 2. Copy and inspect the actual user JSON output
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    user_data = None
    try:
        copy_from_env("/home/ga/Documents/SAM_Projects/small_hydro_results.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            user_data = json.load(f)
    except Exception as e:
        feedback_parts.append("Could not parse user JSON results")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not user_data:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Check Required Keys
    required_keys = [
        "system_nameplate_kw", 
        "annual_energy_kwh", 
        "annual_capacity_factor_pct", 
        "monthly_energy_kwh", 
        "lcoe_cents_per_kwh",
        "total_installed_cost_usd"
    ]
    
    missing_keys = [k for k in required_keys if k not in user_data]
    if not missing_keys:
        score += 10
        feedback_parts.append("All required JSON keys present")
    else:
        feedback_parts.append(f"Missing JSON keys: {', '.join(missing_keys)}")
        
    # Extract values safely
    try:
        nameplate = float(user_data.get("system_nameplate_kw", 0))
        installed_cost = float(user_data.get("total_installed_cost_usd", 0))
        energy = float(user_data.get("annual_energy_kwh", 0))
        cf = float(user_data.get("annual_capacity_factor_pct", 0))
        lcoe = float(user_data.get("lcoe_cents_per_kwh", 0))
        monthly = user_data.get("monthly_energy_kwh", [])
        
        # Check Inputs
        if math.isclose(nameplate, 500, rel_tol=0.01) and math.isclose(installed_cost, 2000000, rel_tol=0.01):
            score += 10
            feedback_parts.append("Input constraints maintained")
        else:
            feedback_parts.append("Input constraints (nameplate or cost) incorrect")
            
        # Check Energy
        if expected_energy_min <= energy <= expected_energy_max:
            score += 15
            feedback_parts.append(f"Energy physically valid ({energy:.0f} kWh)")
        else:
            feedback_parts.append(f"Energy out of bounds ({energy:.0f} kWh)")
            
        # Check CF
        if expected_cf_min <= cf <= expected_cf_max:
            # Cross-verify CF mathematically
            calculated_cf = (energy / (nameplate * 8760)) * 100 if nameplate > 0 else 0
            if math.isclose(cf, calculated_cf, abs_tol=1.0):
                score += 10
                feedback_parts.append(f"CF mathematically valid ({cf:.1f}%)")
            else:
                feedback_parts.append(f"CF reported ({cf:.1f}%) but math implies {calculated_cf:.1f}%")
        else:
            feedback_parts.append(f"CF out of bounds ({cf:.1f}%)")
            
        # Check Monthly
        if isinstance(monthly, list) and len(monthly) == 12:
            monthly = [float(m) for m in monthly]
            sum_monthly = sum(monthly)
            
            # Internal consistency: sum of monthly should approximate annual
            if math.isclose(sum_monthly, energy, rel_tol=0.05):
                # Check expected spring peak / fall trough pattern
                spring_peak = monthly[4] # May (index 4)
                fall_trough = monthly[8] # Sept (index 8)
                
                if spring_peak > fall_trough * 1.5:
                    score += 10
                    feedback_parts.append("Monthly distribution matches PNW hydro seasonal pattern")
                else:
                    feedback_parts.append("Monthly distribution lacks expected seasonal pattern")
            else:
                feedback_parts.append(f"Internal inconsistency: sum of monthly ({sum_monthly:.0f}) != annual ({energy:.0f})")
        else:
            feedback_parts.append("Invalid or missing monthly_energy_kwh array")
            
        # Check LCOE
        if expected_lcoe_min <= lcoe <= expected_lcoe_max:
            # Cross-check LCOE math roughly: (Cap*FCR + FixOM + VarOM*E) / E
            if energy > 0:
                expected_cost = (2000000 * 0.078) + 50000 + (0.005 * energy)
                expected_lcoe_cents = (expected_cost / energy) * 100
                if math.isclose(lcoe, expected_lcoe_cents, abs_tol=1.0):
                    score += 15
                    feedback_parts.append(f"LCOE mathematically valid ({lcoe:.2f} c/kWh)")
                else:
                    feedback_parts.append(f"LCOE reported ({lcoe:.2f}) but math implies {expected_lcoe_cents:.2f}")
        else:
            feedback_parts.append(f"LCOE out of bounds ({lcoe:.2f} c/kWh)")
            
    except Exception as e:
        feedback_parts.append(f"Data type error in JSON values: {str(e)}")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }