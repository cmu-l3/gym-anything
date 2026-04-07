#!/usr/bin/env python3
"""Verifier for evaluate_tracker_backtracking_gcr task.

Verifies the output JSON structure, physics implications of backtracking,
mathematical correctness of the percentage, and execution evidence.
"""

import json
import tempfile
import os

def verify_backtracking_impact(traj, env_info, task_info):
    """Verify PySAM backtracking parameter sweep was completed successfully.

    Scoring: 100 points max
    - File exists & modified: 20
    - JSON Schema Valid (has required keys and 3 GCRs): 20
    - Capacity Valid (~100MW default): 10
    - Physics Check 1 (Higher GCR = Lower absolute energy when no backtrack): 20
    - Physics Check 2 (Backtrack > No Backtrack at GCR 0.5): 15
    - Math Check (Backtrack gain % matches raw output mathematically): 15
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read the export_result.sh metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback_parts = []

    file_exists = meta_result.get('file_exists') is True or str(meta_result.get('file_exists')).lower() == 'true'
    file_modified = meta_result.get('file_modified') is True or str(meta_result.get('file_modified')).lower() == 'true'

    if file_exists and file_modified:
        score += 20
        feedback_parts.append("File exists and was modified during task")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but was NOT modified during task (possible anti-gaming violation)")
    else:
        feedback_parts.append("Output file backtracking_impact.json NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Read the actual agent output JSON
    output_path = "/home/ga/Documents/SAM_Projects/backtracking_impact.json"
    temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(output_path, temp_out.name)
        with open(temp_out.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to parse output JSON: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_out.name):
            os.unlink(temp_out.name)

    # 3. Validate Schema
    has_capacity = "system_capacity_kw" in agent_data
    has_results = "results" in agent_data and isinstance(agent_data["results"], list)
    
    if not has_results:
        feedback_parts.append("Missing 'results' array in JSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    results = agent_data["results"]
    gcrs_found = []
    results_map = {}
    
    for r in results:
        gcr = r.get("gcr")
        if gcr is not None:
            gcrs_found.append(float(gcr))
            results_map[float(gcr)] = r

    expected_gcrs = [0.3, 0.4, 0.5]
    all_gcrs_present = all(any(abs(g - expected) < 0.01 for g in gcrs_found) for expected in expected_gcrs)

    if all_gcrs_present:
        score += 20
        feedback_parts.append("Schema valid with 0.3, 0.4, 0.5 GCRs present")
    else:
        feedback_parts.append(f"Missing required GCRs. Found: {gcrs_found}")

    # 4. Validate Capacity
    if has_capacity:
        cap = float(agent_data["system_capacity_kw"])
        # FlatPlatePVSingleOwner default is ~100MW (100,000 kW). Give generous bounds just in case version differs.
        if 80000 <= cap <= 120000:
            score += 10
            feedback_parts.append(f"Capacity reasonable ({cap} kW)")
        else:
            feedback_parts.append(f"Capacity out of expected default range ({cap} kW)")
    else:
        feedback_parts.append("system_capacity_kw missing")

    # Only perform physics/math checks if all GCRs are present and schema is roughly correct
    if all_gcrs_present:
        # Extract the specific GCR dictionaries safely
        res_03 = next((r for r in results if abs(float(r.get("gcr", 0)) - 0.3) < 0.01), None)
        res_05 = next((r for r in results if abs(float(r.get("gcr", 0)) - 0.5) < 0.01), None)

        if res_03 and res_05:
            # 5. Physics Check 1: Higher GCR = lower absolute energy when NO backtracking
            try:
                en_no_03 = float(res_03.get("annual_energy_no_backtrack_kwh", 0))
                en_no_05 = float(res_05.get("annual_energy_no_backtrack_kwh", 0))

                if en_no_03 > 0 and en_no_05 > 0 and en_no_03 > en_no_05:
                    score += 20
                    feedback_parts.append("Physics Check 1 passed (Higher GCR = lower yield without backtracking)")
                else:
                    feedback_parts.append(f"Physics Check 1 failed (en_no_03: {en_no_03}, en_no_05: {en_no_05})")
            except Exception as e:
                feedback_parts.append(f"Physics Check 1 Error: {e}")

            # 6. Physics Check 2: Backtracking > No Backtracking at high GCR (0.5)
            try:
                en_with_05 = float(res_05.get("annual_energy_with_backtrack_kwh", 0))
                en_no_05 = float(res_05.get("annual_energy_no_backtrack_kwh", 0))

                if en_with_05 > 0 and en_with_05 > en_no_05:
                    score += 15
                    feedback_parts.append("Physics Check 2 passed (Backtracking recovers energy at GCR 0.5)")
                else:
                    feedback_parts.append(f"Physics Check 2 failed (with_05: {en_with_05}, no_05: {en_no_05})")
            except Exception as e:
                feedback_parts.append(f"Physics Check 2 Error: {e}")

        # 7. Math Check: Verify backtrack_gain_percent computation for all valid records
        math_errors = 0
        valid_records = 0
        for r in results:
            try:
                en_with = float(r.get("annual_energy_with_backtrack_kwh", 0))
                en_no = float(r.get("annual_energy_no_backtrack_kwh", 0))
                reported_pct = float(r.get("backtrack_gain_percent", 0))

                if en_no > 0:
                    calculated_pct = (en_with - en_no) / en_no * 100
                    if abs(calculated_pct - reported_pct) > 0.1:
                        math_errors += 1
                    valid_records += 1
            except Exception:
                pass
        
        if valid_records == 3 and math_errors == 0:
            score += 15
            feedback_parts.append("Math Check passed (Percentage calculations are accurate)")
        elif valid_records > 0:
            feedback_parts.append(f"Math Check failed ({math_errors}/{valid_records} percentage calculations incorrect)")
        else:
            feedback_parts.append("Math Check failed (Invalid numeric data)")

    # 8. Determine pass/fail
    key_criteria_met = file_exists and file_modified and all_gcrs_present
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }