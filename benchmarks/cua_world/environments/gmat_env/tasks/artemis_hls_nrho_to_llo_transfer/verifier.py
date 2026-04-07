#!/usr/bin/env python3
"""
Verifier for artemis_hls_nrho_to_llo_transfer@1

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - targeting_logic (20): DifferentialCorrector (Target, Vary, Achieve) logic present in script
  - results_written (10): Results text file with required output lines
  - burn1_valid (15): Burn 1 Delta-V in valid range [15.0, 45.0] m/s (expected ~32.2 m/s)
  - burn2_valid (15): Burn 2 Delta-V in valid range [600.0, 700.0] m/s (expected ~647 m/s)
  - final_sma_valid (15): Final LLO SMA in valid range [1830.0, 1845.0] km
  - final_ecc_valid (15): Final LLO ECC < 0.01 (circularized)

Pass condition: score >= 60 AND targeting_logic AND (burn1_valid OR burn2_valid)
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_artemis_hls_transfer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    b1_min = metadata.get('burn1_min_mps', 15.0)
    b1_max = metadata.get('burn1_max_mps', 45.0)
    b2_min = metadata.get('burn2_min_mps', 600.0)
    b2_max = metadata.get('burn2_max_mps', 700.0)
    sma_min = metadata.get('final_sma_min_km', 1830.0)
    sma_max = metadata.get('final_sma_max_km', 1845.0)
    ecc_max = metadata.get('final_ecc_max', 0.01)

    scores = {
        "script_created": 10,
        "targeting_logic": 20,
        "results_written": 10,
        "burn1_valid": 15,
        "burn2_valid": 15,
        "final_sma_valid": 15,
        "final_ecc_valid": 15,
    }

    total_score = 0
    feedback = []
    has_targeting = False
    has_valid_burn = False

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

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Targeting logic parsed directly from the script content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/hls_transfer_script.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
            
            # Check for Target, Vary, Achieve loops
            if re.search(r'\bTarget\b', script_content) and re.search(r'\bVary\b', script_content) and re.search(r'\bAchieve\b', script_content):
                total_score += scores["targeting_logic"]
                has_targeting = True
                feedback.append("DifferentialCorrector targeting logic found in script.")
            else:
                feedback.append("Missing required targeting logic (Target/Vary/Achieve) in script.")
        except Exception as e:
            feedback.append(f"Failed to parse script for targeting logic: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)
    else:
        feedback.append("Cannot verify targeting logic; script file missing.")

    # 3. Results written
    results_file = task_result.get('results_file', {})
    if isinstance(results_file, dict) and results_file.get('created_during_task'):
        total_score += scores["results_written"]
        feedback.append("Results file written during task window.")
    else:
        feedback.append("Results file missing or not modified.")

    # Convert parsed report values
    try:
        b1_val = float(task_result.get('burn1_dv_mps', 0))
    except (ValueError, TypeError):
        b1_val = 0.0

    try:
        b2_val = float(task_result.get('burn2_dv_mps', 0))
    except (ValueError, TypeError):
        b2_val = 0.0

    try:
        sma_val = float(task_result.get('final_sma_km', 0))
    except (ValueError, TypeError):
        sma_val = 0.0

    try:
        ecc_val = float(task_result.get('final_ecc', 1.0))
    except (ValueError, TypeError):
        ecc_val = 1.0

    # 4. Check Burn 1
    if b1_val == 0.0 and b2_val == 0.0:
        feedback.append("No valid Delta-V values found in results.")
    else:
        if b1_min <= b1_val <= b1_max:
            total_score += scores["burn1_valid"]
            has_valid_burn = True
            feedback.append(f"Burn 1 (Apoapsis) Delta-V valid: {b1_val:.2f} m/s.")
        else:
            feedback.append(f"Burn 1 Delta-V out of bounds: {b1_val:.2f} m/s (Expected {b1_min}-{b1_max} m/s).")

        # 5. Check Burn 2
        if b2_min <= b2_val <= b2_max:
            total_score += scores["burn2_valid"]
            has_valid_burn = True
            feedback.append(f"Burn 2 (Circularization) Delta-V valid: {b2_val:.2f} m/s.")
        else:
            feedback.append(f"Burn 2 Delta-V out of bounds: {b2_val:.2f} m/s (Expected {b2_min}-{b2_max} m/s).")

    # 6. Check Final SMA
    if sma_min <= sma_val <= sma_max:
        total_score += scores["final_sma_valid"]
        feedback.append(f"Final SMA valid: {sma_val:.2f} km.")
    else:
        feedback.append(f"Final SMA out of bounds: {sma_val:.2f} km (Expected {sma_min}-{sma_max} km).")

    # 7. Check Final ECC
    if 0.0 <= ecc_val <= ecc_max:
        total_score += scores["final_ecc_valid"]
        feedback.append(f"Final ECC valid: {ecc_val:.5f}.")
    else:
        feedback.append(f"Final ECC out of bounds: {ecc_val:.5f} (Expected <= {ecc_max}).")

    # Pass condition
    passed = (total_score >= 60) and has_targeting and has_valid_burn

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "has_targeting": has_targeting,
            "has_valid_burn": has_valid_burn,
            "burn1_dv": b1_val,
            "burn2_dv": b2_val,
            "final_sma": sma_val,
            "final_ecc": ecc_val
        }
    }