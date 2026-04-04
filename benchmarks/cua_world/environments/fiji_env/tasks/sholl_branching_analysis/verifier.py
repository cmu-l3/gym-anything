#!/usr/bin/env python3
"""
Verifier for Sholl Analysis Task.

Criteria:
1. CSV file exists, is valid, and created during task.
2. Sholl profile plot exists and is a valid image.
3. Summary text file exists and contains required metrics.
4. Data Consistency: Summary metrics match the CSV data.
5. Biological Plausibility: Results fall within expected ranges for ddaC neurons.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sholl_analysis(traj, env_info, task_info):
    """
    Verify the Sholl analysis task output.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env not available"}

    # Get expected biological ranges from metadata or defaults
    metadata = task_info.get('metadata', {})
    bio_ranges = metadata.get('biological_ranges', {
        "max_intersections": [20, 45],
        "critical_radius": [30, 100],
        "enclosing_radius": [150, 300]
    })

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/sholl_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check CSV (30 points) ---
    csv_data = result.get("csv", {})
    rows = csv_data.get("rows", [])
    
    if csv_data.get("exists") and csv_data.get("modified_during_task"):
        if csv_data.get("valid") and len(rows) > 10:
            score += 30
            feedback.append("CSV output valid and data extracted.")
        else:
            score += 10
            feedback.append("CSV exists but content seems insufficient or invalid format.")
    else:
        feedback.append("CSV file not created or not modified during task.")

    # --- Check Plot (20 points) ---
    plot_data = result.get("plot", {})
    if plot_data.get("exists") and plot_data.get("modified_during_task"):
        if plot_data.get("size_bytes", 0) > 5000: # 5KB min
            score += 20
            feedback.append("Profile plot created successfully.")
        else:
            score += 5
            feedback.append("Profile plot exists but file size is suspiciously small.")
    else:
        feedback.append("Profile plot not created.")

    # --- Check Summary & Consistency (50 points) ---
    summary = result.get("summary", {})
    summary_data = summary.get("data", {})
    
    if summary.get("exists") and summary.get("modified_during_task"):
        required_keys = ["max_intersections", "critical_radius", "enclosing_radius", "total_intersections"]
        keys_present = [k for k in required_keys if k in summary_data]
        
        if len(keys_present) == len(required_keys):
            score += 10 # Basic presence
            
            # Extract values for checking
            s_max = summary_data.get("max_intersections", 0)
            s_crit = summary_data.get("critical_radius", 0)
            
            # 1. Biological Plausibility (10 pts)
            # Check max intersections (peak branching)
            r_min, r_max = bio_ranges["max_intersections"]
            if r_min <= s_max <= r_max:
                score += 10
                feedback.append(f"Max intersections ({s_max}) within expected biological range.")
            else:
                feedback.append(f"Max intersections ({s_max}) outside expected range [{r_min}, {r_max}].")
                
            # 2. Data Consistency with CSV (30 pts)
            if rows:
                # Find max in CSV
                csv_max_val = max(r["intersections"] for r in rows)
                # Find radius of max in CSV
                csv_crit_rad = next(r["radius"] for r in rows if r["intersections"] == csv_max_val)
                
                # Compare (allow slight tolerance for manual vs auto measurement differences)
                if abs(s_max - csv_max_val) <= 2.0:
                    score += 15
                    feedback.append("Summary Max Intersections matches CSV data.")
                else:
                    feedback.append(f"Mismatch: Summary says max={s_max}, CSV data says max={csv_max_val}.")
                    
                if abs(s_crit - csv_crit_rad) <= 20.0: # Wider tolerance for radius binning
                    score += 15
                    feedback.append("Summary Critical Radius matches CSV data.")
                else:
                    feedback.append(f"Mismatch: Summary says crit_rad={s_crit}, CSV data says crit_rad={csv_crit_rad}.")
            else:
                feedback.append("Cannot verify consistency because CSV data is missing.")
                
        else:
            score += 5
            feedback.append(f"Summary file missing required keys. Found: {keys_present}")
    else:
        feedback.append("Summary text file not created.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }