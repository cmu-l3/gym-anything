#!/usr/bin/env python3
"""
Verifier for compare_hcpv_vs_flatplate_yield task.

Validates capacity linkage, JSON structure, and physics sanity using 
independent file extraction via `copy_from_env`.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_hcpv_vs_flatplate_yield(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_json = metadata.get('expected_json', '/home/ga/Documents/SAM_Projects/technology_comparison.json')
    multiplier = metadata.get('multiplier', 1.2)
    
    # 1. Grab task_result.json (metadata created by export script)
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export meta: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback_parts = []
    
    file_exists = export_meta.get('file_exists', False)
    file_modified = export_meta.get('file_modified', False)
    evidence_exists = export_meta.get('evidence_exists', False)
    evidence_modified = export_meta.get('evidence_modified', False)

    # Criterion 1: Files existence & Modification (15 pts)
    if file_exists and file_modified and evidence_exists and evidence_modified:
        score += 15
        feedback_parts.append("JSON & evidence (.py/.sam) exist and modified")
    elif file_exists and evidence_exists:
        score += 7
        feedback_parts.append("Files exist but timestamps don't match task run")
    else:
        feedback_parts.append("Missing required JSON or evidence file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # 2. Grab actual user output JSON
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(expected_json, temp_output.name)
        with open(temp_output.name, 'r') as f:
            user_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to parse target JSON: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
            
    # Criterion 2: JSON Structure (10 pts)
    required_keys = [
        "weather_file", "hcpv_system_capacity_kw", "pv_system_capacity_kw",
        "hcpv_annual_energy_kwh", "pv_annual_energy_kwh",
        "hcpv_capacity_factor", "pv_capacity_factor"
    ]
    missing_keys = [k for k in required_keys if k not in user_data]
    if not missing_keys:
        score += 10
        feedback_parts.append("JSON structure correct")
    else:
        feedback_parts.append(f"JSON missing keys: {missing_keys}")
        
    # Helper to safely extract floats
    def get_float(k):
        try:
            return float(user_data.get(k, 0))
        except (ValueError, TypeError):
            return 0.0
            
    hcpv_cap = get_float("hcpv_system_capacity_kw")
    pv_cap = get_float("pv_system_capacity_kw")
    hcpv_energy = get_float("hcpv_annual_energy_kwh")
    pv_energy = get_float("pv_annual_energy_kwh")
    hcpv_cf = get_float("hcpv_capacity_factor")
    pv_cf = get_float("pv_capacity_factor")
    weather = str(user_data.get("weather_file", "")).lower()
    
    # Normalize CF to percentage if agent saved it as a fraction
    if 0 < hcpv_cf <= 1.0: hcpv_cf *= 100
    if 0 < pv_cf <= 1.0: pv_cf *= 100

    # Criterion 3: Location Accuracy (15 pts)
    if "phoenix" in weather or "az" in weather:
        score += 15
        feedback_parts.append("Weather location correct")
    else:
        feedback_parts.append(f"Weather location '{weather}' does not look like Phoenix")

    # Criterion 4: Capacity Linkage (20 pts)
    linkage_passed = False
    if hcpv_cap > 0:
        expected_pv_cap = hcpv_cap * multiplier
        diff_pct = abs(pv_cap - expected_pv_cap) / expected_pv_cap
        if diff_pct < 0.01: # allow tiny float imprecision
            score += 20
            feedback_parts.append(f"Capacity linkage correct (PV={pv_cap}, HCPV={hcpv_cap})")
            linkage_passed = True
        else:
            feedback_parts.append(f"Capacity linkage incorrect (PV={pv_cap}, expected={expected_pv_cap})")
    else:
        feedback_parts.append("Invalid HCPV capacity (<= 0)")

    # Criterion 5: HCPV Physics Check (20 pts)
    hcpv_cf_min = metadata.get('hcpv_cf_min', 20.0)
    hcpv_cf_max = metadata.get('hcpv_cf_max', 38.0)
    
    if hcpv_cap > 0 and hcpv_energy > 0:
        if hcpv_cf_min <= hcpv_cf <= hcpv_cf_max:
            score += 20
            feedback_parts.append(f"HCPV CF realistic ({hcpv_cf:.1f}%)")
        else:
            feedback_parts.append(f"HCPV CF {hcpv_cf:.1f}% outside realistic bounds")
    else:
        feedback_parts.append("HCPV energy/capacity missing")
        
    # Criterion 6: Flat-Plate PV Physics Check (20 pts)
    pv_cf_min = metadata.get('pv_cf_min', 16.0)
    pv_cf_max = metadata.get('pv_cf_max', 28.0)
    
    if pv_cap > 0 and pv_energy > 0:
        if pv_cf_min <= pv_cf <= pv_cf_max:
            score += 20
            feedback_parts.append(f"PV CF realistic ({pv_cf:.1f}%)")
        else:
            feedback_parts.append(f"PV CF {pv_cf:.1f}% outside realistic bounds")
    else:
        feedback_parts.append("PV energy/capacity missing")

    # Final pass logic
    key_criteria_met = file_exists and linkage_passed and not missing_keys
    passed = score >= 75 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }