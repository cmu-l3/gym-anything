#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_shear_stress(traj, env_info, task_info):
    """
    Verifies the compute_shear_stress task.
    Checks existence of output files and accuracy of computed values against
    ground truth generated inside the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result.get("files", {})
    gt = result.get("ground_truth", {})
    agent = result.get("agent_data", {})
    summary_content = result.get("agent_summary_content", "").lower()

    # --- Criterion 1: Files Exist (25 pts) ---
    csv_exists = files.get("csv", {}).get("exists", False)
    summary_exists = files.get("summary", {}).get("exists", False)
    script_exists = files.get("script", {}).get("exists", False)
    hdf_exists = files.get("hdf", {}).get("exists", False)

    if hdf_exists:
        score += 5
        feedback.append("Simulation results found.")
    else:
        feedback.append("Simulation results HDF missing (did the simulation run?).")

    if script_exists:
        score += 10
        feedback.append("Analysis script found.")
    
    if csv_exists:
        score += 10
        feedback.append("CSV output found.")
    else:
        feedback.append("CSV output missing.")

    # --- Criterion 2: Data Validity (30 pts) ---
    # Compare counts
    gt_count = gt.get("count", 0)
    agent_count = agent.get("count", 0)

    if agent_count > 0:
        score += 10
        feedback.append(f"CSV contains {agent_count} rows.")
        
        # Tolerance for row count (sometimes header handling varies)
        if gt_count > 0 and abs(agent_count - gt_count) <= 2:
            score += 10
            feedback.append("Row count matches model cross-sections.")
        elif gt_count > 0:
            feedback.append(f"Row count mismatch (Expected ~{gt_count}, Got {agent_count}).")
    else:
        feedback.append("CSV is empty or unparseable.")

    # Compare mean value (sanity check)
    gt_mean = gt.get("mean_value_pa", 0)
    agent_mean = agent.get("mean_value_pa", 0)
    
    if agent_mean > 0 and gt_mean > 0:
        # Allow 25% error margin for formula implementation differences (e.g., using R vs A/P)
        error = abs(agent_mean - gt_mean) / gt_mean
        if error < 0.25:
            score += 10
            feedback.append(f"Mean shear stress ({agent_mean:.2f} Pa) is within tolerance of ground truth ({gt_mean:.2f} Pa).")
        else:
            feedback.append(f"Mean shear stress inaccurate (Expected ~{gt_mean:.2f}, Got {agent_mean:.2f}).")
    elif gt_mean > 0:
        feedback.append("Could not verify mean shear stress values.")

    # --- Criterion 3: Specific Accuracy (25 pts) ---
    # Compare specific station values
    gt_map = gt.get("full_map", {})
    agent_map = agent.get("full_map", {})
    
    matches = 0
    checks = 0
    if gt_map and agent_map:
        # Check a few random stations
        for stat, val in list(gt_map.items())[:10]:
            checks += 1
            # Try to find station in agent map
            agent_val = agent_map.get(stat)
            if agent_val is not None:
                # 25% tolerance
                if abs(agent_val - val) <= (0.25 * val + 0.1): 
                    matches += 1
    
    if checks > 0:
        match_rate = matches / checks
        if match_rate > 0.8:
            score += 25
            feedback.append("Individual cross-section values match ground truth.")
        elif match_rate > 0.5:
            score += 15
            feedback.append("Some cross-section values match ground truth.")
        else:
            feedback.append("Cross-section values diverge significantly from ground truth.")

    # --- Criterion 4: Summary File Content (20 pts) ---
    if summary_exists:
        gt_max_station = gt.get("max_station", "").lower()
        
        # Check if max station is mentioned
        if gt_max_station and gt_max_station in summary_content:
            score += 10
            feedback.append(f"Summary correctly identifies max shear station ({gt_max_station}).")
        else:
            feedback.append(f"Summary missing or incorrect max station (Expected {gt_max_station}).")
            
        # Check if mean/max values are mentioned (simple substring check for numbers)
        # This is loose, but prevents empty files
        if any(char.isdigit() for char in summary_content):
            score += 10
            feedback.append("Summary contains numerical data.")
        else:
            feedback.append("Summary file appears to lack numerical results.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }