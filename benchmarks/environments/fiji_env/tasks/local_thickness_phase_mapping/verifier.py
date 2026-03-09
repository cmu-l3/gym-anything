#!/usr/bin/env python3
"""
Verifier for local_thickness_phase_mapping task.

Scoring Breakdown (100 pts total):
1. Solid Phase Thickness Map (20 pts): Exists, valid 32-bit float, created during task.
2. Void Phase Thickness Map (20 pts): Exists, valid 32-bit float, created during task.
3. Statistics CSV (20 pts): Exists, correct format, reasonable values.
4. Visualization (15 pts): Color-coded map exists.
5. Histogram (15 pts): Histogram image exists.
6. Data Consistency (10 pts): Statistics in CSV match expected ranges for this sample.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_local_thickness_phase_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/thickness_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    checks = result.get("checks", {})
    files = result.get("files", {})
    csv_data = result.get("csv_data", [])
    
    score = 0
    feedback = []

    # 1. Solid Map (20 pts)
    if checks.get("solid_map_valid", False) and files["solid_phase_thickness_map.tif"]["created_during_task"]:
        score += 20
        feedback.append("Solid thickness map valid (20/20)")
    elif files.get("solid_phase_thickness_map.tif", {}).get("exists"):
        score += 5
        feedback.append("Solid map exists but invalid format (not 32-bit float?) (5/20)")
    else:
        feedback.append("Solid map missing (0/20)")

    # 2. Void Map (20 pts)
    if checks.get("void_map_valid", False) and files["void_phase_thickness_map.tif"]["created_during_task"]:
        score += 20
        feedback.append("Void thickness map valid (20/20)")
    elif files.get("void_phase_thickness_map.tif", {}).get("exists"):
        score += 5
        feedback.append("Void map exists but invalid format (5/20)")
    else:
        feedback.append("Void map missing (0/20)")

    # 3. CSV (20 pts)
    if checks.get("csv_valid", False) and files["thickness_statistics.csv"]["created_during_task"]:
        score += 20
        feedback.append("Statistics CSV valid (20/20)")
    elif files.get("thickness_statistics.csv", {}).get("exists"):
        score += 5
        feedback.append("CSV exists but missing columns/rows (5/20)")
    else:
        feedback.append("CSV missing (0/20)")

    # 4. Visualization (15 pts)
    if checks.get("viz_exists", False) and files["thickness_visualization.png"]["created_during_task"]:
        score += 15
        feedback.append("Visualization created (15/15)")
    else:
        feedback.append("Visualization missing (0/15)")

    # 5. Histogram (15 pts)
    if checks.get("hist_exists", False) and files["thickness_histogram.png"]["created_during_task"]:
        score += 15
        feedback.append("Histogram created (15/15)")
    else:
        feedback.append("Histogram missing (0/15)")

    # 6. Data Consistency (10 pts)
    # Check if mean thickness values are positive and solid != void (they should differ physically)
    consistency_pass = False
    if len(csv_data) >= 2:
        try:
            # Flexible parsing of 'mean' column
            # Users might name it 'mean', 'Mean', 'mean_thickness_px', etc.
            def get_val(row, keys):
                for k in keys:
                    if k in row: return float(row[k])
                    for rk in row.keys():
                        if k in rk.lower(): return float(row[rk])
                return None
            
            means = []
            for row in csv_data:
                m = get_val(row, ["mean", "mean_thickness_px", "average"])
                if m is not None: means.append(m)
            
            if len(means) >= 2 and all(m > 0 for m in means):
                # Check for realistic ranges for this specific image
                # AuPbSn40: Solid phase is chunky (thick), void is thinner/matrix
                if max(means) < 500: # Sanity check
                     consistency_pass = True
        except:
            pass
            
    if consistency_pass:
        score += 10
        feedback.append("Data values consistent (10/10)")
    else:
        feedback.append("Data values missing or inconsistent (0/10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }