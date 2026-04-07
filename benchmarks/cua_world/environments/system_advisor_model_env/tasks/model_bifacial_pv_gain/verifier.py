#!/usr/bin/env python3
"""
Verifier for model_bifacial_pv_gain task.

Validates that the agent executed the Python PySAM script correctly, 
produced physically plausible energy values, strictly adhered to the 
required JSON output structure, and properly calculated bifacial gain.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _get_float_or_first_element(val):
    """Helper to handle if agent exported an array (like [0.2]*12) instead of float."""
    if isinstance(val, list) and len(val) > 0:
        return float(val[0])
    try:
        return float(val)
    except (TypeError, ValueError):
        return None

def verify_model_bifacial_pv_gain(traj, env_info, task_info):
    """Verify PySAM bifacial comparison script execution and output."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_capacity = metadata.get('expected_capacity', 10000)
    expected_bifaciality = metadata.get('expected_bifaciality', 0.70)
    expected_mono_albedo = metadata.get('expected_mono_albedo', 0.20)
    expected_bi_albedo = metadata.get('expected_bi_albedo', 0.30)
    expected_energy_min = metadata.get('expected_energy_min', 15000000)
    expected_energy_max = metadata.get('expected_energy_max', 25000000)
    expected_gain_min = metadata.get('expected_gain_min', 2.0)
    expected_gain_max = metadata.get('expected_gain_max', 20.0)

    # 1. Read the export meta-data
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read meta result: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback_parts = []
    
    # Check Meta
    file_exists = meta_result.get('file_exists', False)
    file_modified = meta_result.get('file_modified', False)
    python_ran = meta_result.get('python_ran', False)
    
    if file_exists:
        score += 10
        feedback_parts.append("✅ Output file exists")
    else:
        feedback_parts.append("❌ Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if file_modified:
        score += 10
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("❌ File existed before task (possible gaming)")
        
    if not python_ran:
        feedback_parts.append("⚠️ Python usage not detected in bash history")
        
    # 2. Independently copy and verify the target JSON
    target_json_path = "/home/ga/Documents/SAM_Projects/bifacial_comparison.json"
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(target_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            bifacial_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"❌ Output file is not valid JSON: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Verify JSON contents & schema
    required_keys = [
        "system_capacity_kw", "dc_ac_ratio", "array_type", "gcr", 
        "losses_percent", "bifaciality", "monofacial_albedo", 
        "bifacial_albedo", "monofacial_annual_energy_kwh", 
        "bifacial_annual_energy_kwh", "bifacial_gain_percent"
    ]
    
    missing_keys = [k for k in required_keys if k not in bifacial_data]
    if not missing_keys:
        score += 15
        feedback_parts.append("✅ Schema complete")
    else:
        feedback_parts.append(f"❌ Missing keys: {missing_keys}")
        
    # Check parameters
    capacity = _get_float_or_first_element(bifacial_data.get("system_capacity_kw"))
    if capacity == expected_capacity:
        score += 5
        
    bifaciality = _get_float_or_first_element(bifacial_data.get("bifaciality"))
    if bifaciality is not None and abs(bifaciality - expected_bifaciality) < 0.01:
        score += 5
        
    mono_albedo = _get_float_or_first_element(bifacial_data.get("monofacial_albedo"))
    bi_albedo = _get_float_or_first_element(bifacial_data.get("bifacial_albedo"))
    
    if (mono_albedo is not None and bi_albedo is not None and 
        abs(mono_albedo - expected_mono_albedo) < 0.01 and 
        abs(bi_albedo - expected_bi_albedo) < 0.01):
        score += 5
        
    # Check realistic energy calculations
    mono_energy = _get_float_or_first_element(bifacial_data.get("monofacial_annual_energy_kwh"))
    bi_energy = _get_float_or_first_element(bifacial_data.get("bifacial_annual_energy_kwh"))
    gain_percent = _get_float_or_first_element(bifacial_data.get("bifacial_gain_percent"))

    if mono_energy and bi_energy and gain_percent is not None:
        # Realistic monofacial
        if expected_energy_min <= mono_energy <= expected_energy_max:
            score += 10
            feedback_parts.append("✅ Monofacial energy realistic")
        else:
            feedback_parts.append(f"❌ Monofacial energy unrealistic ({mono_energy})")
            
        # Strict inequality
        if bi_energy > mono_energy:
            score += 15
            feedback_parts.append("✅ Bifacial energy > Monofacial")
            
            # Plausible gain
            actual_gain = ((bi_energy - mono_energy) / mono_energy) * 100
            if expected_gain_min <= actual_gain <= expected_gain_max:
                score += 15
                feedback_parts.append("✅ Bifacial gain physically plausible")
            else:
                feedback_parts.append(f"❌ Gain magnitude unrealistic: {actual_gain:.2f}%")
                
            # Internal consistency (did they do the math right in the script?)
            if abs(actual_gain - gain_percent) < 0.5:
                score += 10
                feedback_parts.append("✅ Internal consistency verified")
            else:
                feedback_parts.append(f"❌ Gain mismatch: reported {gain_percent}%, derived {actual_gain:.2f}%")
        else:
            feedback_parts.append("❌ Bifacial energy NOT greater than Monofacial")
            
    else:
        feedback_parts.append("❌ Missing or invalid simulation results")

    passed = score >= 70 and file_modified and (bi_energy and mono_energy and bi_energy > mono_energy)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }