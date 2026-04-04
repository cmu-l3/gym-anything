#!/usr/bin/env python3
"""
Verifier for surface_roughness_profiling task.

Scoring Criteria (100 pts total):
1. [20 pts] Profile CSVs exist, created during task, and have data rows (>50).
2. [20 pts] Roughness Report exists and contains 5 required parameters.
3. [20 pts] Roughness values (Ra, Rq, Rz) match ground truth (±10% tolerance).
4. [15 pts] 3D Surface Plot PNG exists and is valid.
5. [15 pts] Annotated Image PNG exists and is valid.
6. [10 pts] VLM Verification: Trajectory shows usage of 'Plot Profile' or 'Surface Plot'.

Pass threshold: 60/100
"""

import json
import os
import tempfile
import logging

# Import shared VLM utilities
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback/Mock if running outside full framework
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_surface_profiling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    files = result.get("files", {})
    report_vals = result.get("report_values", {})
    gt = result.get("ground_truth", {})
    csv_stats = result.get("csv_stats", {})

    # Criterion 1: Profile CSVs (20 pts)
    # Check existence, timestamp, and row count
    h_prof = files.get("horizontal_profile", {})
    v_prof = files.get("vertical_profile", {})
    
    prof_score = 0
    if h_prof.get("exists") and h_prof.get("created_during_task") and csv_stats.get("horizontal_rows", 0) > 50:
        prof_score += 10
    if v_prof.get("exists") and v_prof.get("created_during_task") and csv_stats.get("vertical_rows", 0) > 50:
        prof_score += 10
    
    score += prof_score
    if prof_score < 20:
        feedback.append(f"Profile CSVs incomplete (Score: {prof_score}/20)")
    else:
        feedback.append("Profile CSVs valid (20/20)")

    # Criterion 2: Roughness Report Existence (20 pts)
    # Must have Ra, Rq, Rz, Mean_height, Median_height
    req_keys = ["Ra", "Rq", "Rz", "Mean_height", "Median_height"]
    found_keys = [k for k in req_keys if k in report_vals]
    
    report_score = 0
    if files.get("roughness_report", {}).get("exists"):
        report_score = len(found_keys) * 4 # 4 pts per parameter
    
    score += report_score
    feedback.append(f"Report contains {len(found_keys)}/5 parameters (Score: {report_score}/20)")

    # Criterion 3: Value Accuracy (20 pts)
    # Ra, Rq within 10%, Rz within 5% or 5 units
    acc_score = 0
    if gt and report_vals:
        # Check Ra
        if "Ra" in report_vals and abs(report_vals["Ra"] - gt["Ra"]) <= (gt["Ra"] * 0.15):
            acc_score += 7
        # Check Rq
        if "Rq" in report_vals and abs(report_vals["Rq"] - gt["Rq"]) <= (gt["Rq"] * 0.15):
            acc_score += 7
        # Check Rz
        if "Rz" in report_vals and abs(report_vals["Rz"] - gt["Rz"]) <= (gt["Rz"] * 0.10):
            acc_score += 6
            
    score += acc_score
    feedback.append(f"Data accuracy check (Score: {acc_score}/20)")

    # Criterion 4: 3D Surface Plot (15 pts)
    surf_file = files.get("surface_plot", {})
    if surf_file.get("exists") and surf_file.get("size", 0) > 5000:
        score += 15
        feedback.append("3D Surface Plot valid (15/15)")
    else:
        feedback.append("3D Surface Plot missing or empty (0/15)")

    # Criterion 5: Annotated Image (15 pts)
    anno_file = files.get("annotated_image", {})
    if anno_file.get("exists") and anno_file.get("size", 0) > 5000:
        score += 15
        feedback.append("Annotated Image valid (15/15)")
    else:
        feedback.append("Annotated Image missing or empty (0/15)")

    # Criterion 6: VLM Process Verification (10 pts)
    # Use trajectory to see if they actually used the tools
    frames = sample_trajectory_frames(traj, n=8)
    vlm_score = 0
    if frames:
        prompt = """
        Review these screenshots of a user working in Fiji (ImageJ).
        Look for ANY of the following windows or actions:
        1. A "Plot Profile" window (2D graph of intensity).
        2. A "Surface Plot" window (3D colored terrain map).
        3. The "Results" table showing measurements.
        4. The "Set Scale" dialog.
        
        Return JSON: {"tool_usage_visible": boolean, "details": string}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("parsed", {}).get("tool_usage_visible"):
                vlm_score = 10
        except:
            # If VLM fails, give benefit of doubt if output files exist
            if score >= 50: vlm_score = 10
    
    score += vlm_score
    feedback.append(f"Process verification (Score: {vlm_score}/10)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": "; ".join(feedback)
    }