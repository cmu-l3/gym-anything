#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_cell_spacing(traj, env_info, task_info):
    """
    Verifies the cell spacing analysis task.
    """
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result_final.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. File-based Verification (85 points max)
    
    # Check 1: CSV Existence and Validity (25 pts)
    if result.get("csv_exists") and result.get("files_newly_created"):
        score += 15
        feedback.append("CSV file created.")
        
        # Check columns
        cols = result.get("csv_cols", [])
        required_keywords = ["cell", "x", "y", "area", "dist"] # Loose matching
        matches = sum(1 for req in required_keywords if any(req in c for c in cols))
        
        if matches >= 3:
            score += 5
            feedback.append("CSV columns look correct.")
        
        # Check rows (expecting at least 10 cells for a typical image)
        if result.get("csv_rows", 0) >= 10:
            score += 5
            feedback.append(f"Found {result['csv_rows']} cells.")
        else:
            feedback.append("Too few cells found.")
    else:
        feedback.append("CSV file missing or not created during task.")

    # Check 2: Distance Map (15 pts)
    if result.get("map_exists"):
        # Check size (TIF should be non-trivial)
        if result.get("map_size_mb", 0) > 0.01: 
            score += 15
            feedback.append("Distance map image created.")
        else:
            feedback.append("Distance map file is empty.")
    else:
        feedback.append("Distance map missing.")

    # Check 3: Report & Consistency (30 pts)
    if result.get("report_exists"):
        score += 15
        feedback.append("Report file created.")
        
        data = result.get("report_data", {})
        
        # Check for specific metrics
        metrics = ["mean_nn", "edm_mean", "num_cells"]
        found_metrics = sum(1 for m in metrics if any(m in k for k in data.keys()))
        
        if found_metrics >= 2:
            score += 5
            feedback.append("Report contains required metrics.")
            
        # Consistency Check: CSV row count vs Report count
        csv_count = result.get("csv_rows", 0)
        report_count = -1
        for k, v in data.items():
            if "num" in k or "count" in k:
                try:
                    report_count = int(v)
                    break
                except: pass
        
        if report_count != -1 and abs(csv_count - report_count) < 5:
            score += 10
            feedback.append("Report count matches CSV data.")
        elif report_count != -1:
            feedback.append(f"Inconsistency: Report says {report_count} cells, CSV has {csv_count}.")
    else:
        feedback.append("Report file missing.")

    # Check 4: QC Overlay (15 pts)
    if result.get("qc_exists"):
        score += 15
        feedback.append("QC Overlay created.")

    # 3. VLM Verification (15 points max)
    # We want to see if the agent actually computed the Distance Map (visible as a gradient image).
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of a user using Fiji/ImageJ. "
            "Look for a 'Distance Map' or 'EDM' image. This typically looks like a "
            "grayscale image with a gradient (bright in open spaces, dark near objects), "
            "or a 'Fire' LUT gradient. "
            "Also look for a 'Results' table. "
            "Did the user generate a Distance Map?"
        )
        
        vlm_response = query_vlm(
            images=frames + [final_screen], 
            prompt=vlm_prompt
        )
        
        is_edm_visible = vlm_response.get("success") and "yes" in vlm_response.get("result", "").lower()
        
        if is_edm_visible:
            score += 15
            feedback.append("VLM confirmed Distance Map generation.")
        else:
            feedback.append("VLM could not confirm Distance Map generation visually.")
    else:
        feedback.append("No trajectory frames for VLM.")

    # Final tally
    passed = score >= 60 and result.get("csv_exists") and result.get("report_exists")
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }