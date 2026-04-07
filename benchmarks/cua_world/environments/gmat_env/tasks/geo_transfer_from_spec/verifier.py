#!/usr/bin/env python3
"""
Verifier for geo_transfer_from_spec@1

Agent must read a spec document, design a GTO-to-GEO transfer, and produce
physically valid results matching the CommStar-7 specifications.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - gto_params_correct (15): Script contains GTO injection parameters from spec
  - impulsive_burn (10): ImpulsiveBurn used for AKM
  - targeting_logic (15): DifferentialCorrector / Target / Achieve logic present
  - results_written (10): Results file with required fields
  - deltav_valid (20): Total DeltaV in expected range [1400, 2000] m/s
  - geo_sma_valid (15): Final GEO SMA within 50 km of 42164.17 km
  - geo_orbit_quality (5): ECC < 0.005 and INC < 0.5 deg

Pass condition: score >= 60 AND targeting_logic AND deltav_valid
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_geo_transfer_from_spec(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    geo_sma_target = metadata.get('geo_sma_km', 42164.17)
    geo_sma_tol = metadata.get('geo_sma_tolerance_km', 50.0)
    geo_ecc_max = metadata.get('geo_ecc_max', 0.005)
    geo_inc_max = metadata.get('geo_inc_max_deg', 0.5)
    dv_min = metadata.get('total_deltav_min_mps', 1400.0)
    dv_max = metadata.get('total_deltav_max_mps', 2000.0)

    scores = {
        "script_created": 10,
        "gto_params_correct": 15,
        "impulsive_burn": 10,
        "targeting_logic": 15,
        "results_written": 10,
        "deltav_valid": 20,
        "geo_sma_valid": 15,
        "geo_orbit_quality": 5,
    }

    total_score = 0
    feedback = []
    targeting_ok = False
    deltav_ok = False

    # Load task result
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

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/geo_transfer.script')
    script_content = ""
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check GTO params from spec: SMA ~24505, ECC ~0.7315, INC ~7.0
            has_sma = bool(re.search(r'SMA\s*=\s*245[0-9][0-9](\.[0-9]+)?', script_content))
            has_ecc = bool(re.search(r'ECC\s*=\s*0\.7[0-9]{2,}', script_content))
            has_inc = bool(re.search(r'INC\s*=\s*7\.0', script_content))
            if has_sma and has_ecc:
                total_score += scores["gto_params_correct"]
                feedback.append("GTO parameters from spec found in script.")
            elif has_sma or has_ecc or has_inc:
                total_score += scores["gto_params_correct"] // 2
                feedback.append("Partial GTO parameters from spec found.")
            else:
                feedback.append("GTO parameters from spec not found in script.")

            # Check ImpulsiveBurn
            if "Create ImpulsiveBurn" in script_content or "ImpulsiveBurn" in script_content:
                total_score += scores["impulsive_burn"]
                feedback.append("ImpulsiveBurn (AKM) configured.")
            else:
                feedback.append("ImpulsiveBurn (AKM) not found.")

            # Check DifferentialCorrector targeting
            if ("Create DifferentialCorrector" in script_content and
                    "Target" in script_content and
                    "Vary" in script_content and
                    "Achieve" in script_content):
                total_score += scores["targeting_logic"]
                targeting_ok = True
                feedback.append("DifferentialCorrector targeting logic present.")
            else:
                feedback.append("DifferentialCorrector targeting logic missing.")

        except Exception as e:
            feedback.append(f"Error reading script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Results file
    results_file = task_result.get('results_file', {})
    results_path = task_result.get('results_path', '/home/ga/GMAT_output/geo_transfer_results.txt')
    # Use rerun results if available
    results_file_rerun = task_result.get('results_file_rerun', results_file)
    effective_results = results_file_rerun if isinstance(results_file_rerun, dict) and results_file_rerun.get('exists') else results_file

    if isinstance(effective_results, dict) and effective_results.get('exists'):
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(results_path, temp_rpt.name)
            with open(temp_rpt.name, 'r') as f:
                rpt = f.read()

            required_fields = ['DeltaV2_mps', 'TotalDeltaV_mps', 'GEO_SMA_km', 'GEO_ECC', 'GEO_INC_deg']
            found = sum(1 for f in required_fields if f in rpt)
            if found >= 3:
                total_score += scores["results_written"]
                feedback.append(f"Results file written with {found}/5 fields.")
            else:
                feedback.append(f"Results file incomplete ({found}/5 fields).")

        except Exception as e:
            feedback.append(f"Could not read results file: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Results file not found.")

    # 4. Validate numerical outputs from export
    try:
        total_dv = float(task_result.get('total_deltav_mps', 0))
    except (ValueError, TypeError):
        total_dv = 0.0

    try:
        dv2 = float(task_result.get('deltav2_mps', 0))
    except (ValueError, TypeError):
        dv2 = 0.0

    # Use whichever is larger (total or just AKM burn)
    effective_dv = max(total_dv, dv2)
    if dv_min <= effective_dv <= dv_max:
        total_score += scores["deltav_valid"]
        deltav_ok = True
        feedback.append(f"Total Delta-V valid: {effective_dv:.1f} m/s.")
    else:
        feedback.append(f"Total Delta-V out of range: {effective_dv:.1f} m/s (expected {dv_min}-{dv_max} m/s).")

    # 5. GEO SMA
    try:
        geo_sma = float(task_result.get('geo_sma_km', 0))
    except (ValueError, TypeError):
        geo_sma = 0.0

    if abs(geo_sma - geo_sma_target) <= geo_sma_tol and geo_sma > 40000:
        total_score += scores["geo_sma_valid"]
        feedback.append(f"GEO SMA valid: {geo_sma:.2f} km.")
    else:
        feedback.append(f"GEO SMA invalid or missing: {geo_sma:.2f} km (expected ~{geo_sma_target} km).")

    # 6. GEO orbit quality
    try:
        geo_ecc = float(task_result.get('geo_ecc', 1.0))
    except (ValueError, TypeError):
        geo_ecc = 1.0
    try:
        geo_inc = float(task_result.get('geo_inc_deg', 90.0))
    except (ValueError, TypeError):
        geo_inc = 90.0

    if geo_ecc <= geo_ecc_max and geo_inc <= geo_inc_max:
        total_score += scores["geo_orbit_quality"]
        feedback.append(f"GEO orbit quality good (ECC={geo_ecc:.5f}, INC={geo_inc:.3f} deg).")
    else:
        feedback.append(f"GEO orbit quality insufficient (ECC={geo_ecc:.5f}, INC={geo_inc:.3f} deg).")

    passed = total_score >= 60 and targeting_ok and deltav_ok

    return {
        "passed": passed,
        "score": min(total_score, 100),
        "feedback": " | ".join(feedback)
    }
