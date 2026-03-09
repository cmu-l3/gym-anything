#!/usr/bin/env python3
"""
Verifier for voronoi_territory_analysis@1 task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_voronoi_analysis(traj, env_info, task_info):
    """
    Verifies the Voronoi territory analysis task.
    
    Criteria:
    1. CSV file exists and is valid (has rows, correct columns).
    2. Overlay image exists.
    3. Summary file exists and contains stats.
    4. Data quality: Mean neighbors ~6, Area within reasonable bounds.
    5. Anti-gaming: Files created during task.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/voronoi_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Evaluate Criteria
    score = 0
    feedback = []
    
    # Criteria A: Files Exist and Timestamps Valid (25 pts)
    files_exist = result.get("csv_exists") and result.get("overlay_exists") and result.get("summary_exists")
    timestamps_valid = result.get("file_timestamps_valid")
    
    if files_exist:
        score += 15
        feedback.append("All output files found.")
    else:
        feedback.append("Missing one or more output files.")
        
    if timestamps_valid:
        score += 10
        feedback.append("Files created during task window.")
    elif files_exist:
        feedback.append("Files detected but timestamps are old (pre-existing data?).")
        
    # Criteria B: CSV Content (35 pts)
    # Check row count (expecting ~15-25 cells for this dataset, allowing for edge exclusion)
    row_count = result.get("row_count", 0)
    cols = result.get("columns_found", [])
    
    # Check columns
    required_cols = ["cell_id", "area", "neighbor"]
    # Relaxed matching
    cols_present = 0
    for req in required_cols:
        if any(req in c for c in cols):
            cols_present += 1
            
    if cols_present >= 3:
        score += 15
        feedback.append("CSV has required columns.")
    else:
        feedback.append(f"CSV missing columns (Found: {cols}).")
        
    # Check row count
    if row_count >= 8:
        score += 20
        feedback.append(f"Cell count sufficient ({row_count} cells).")
    else:
        feedback.append(f"Cell count too low ({row_count}). Expected >= 8.")
        
    # Criteria C: Data Consistency / Topology (25 pts)
    # Voronoi topology usually averages ~6 neighbors (Euler's formula for planar graphs)
    mean_neighbors = result.get("mean_neighbors", 0)
    
    if 4.0 <= mean_neighbors <= 8.0:
        score += 15
        feedback.append(f"Neighbor topology is realistic (Mean: {mean_neighbors:.2f}).")
    else:
        feedback.append(f"Neighbor count suspect (Mean: {mean_neighbors:.2f}). Expected 4-8.")
        
    # Check Area (Simulated 696x520 image, 25 cells -> ~14,000 px^2 avg, usually less due to background/edges)
    mean_area = result.get("mean_area", 0)
    if 500 < mean_area < 50000:
        score += 10
        feedback.append(f"Cell area is realistic ({mean_area:.1f} px²).")
    else:
        feedback.append(f"Cell area unrealistic ({mean_area:.1f} px²).")

    # Criteria D: Summary & Overlay (15 pts)
    if result.get("summary_content"):
        score += 10
        feedback.append("Summary file content parsed successfully.")
    
    if result.get("overlay_exists"):
        score += 5 # Basic check, VLM could do deeper check if implemented
        
    # 3. Final Verdict
    # Threshold: 60 points + Essential Criteria (CSV valid with rows)
    passed = (score >= 60) and (row_count >= 8)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }