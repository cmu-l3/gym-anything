#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_particle_inclusion_analysis(traj, env_info, task_info):
    """
    Verifies the particle inclusion analysis task.
    Scoring Breakdown (100 pts total):
    - 25 pts: CSV Valid & Created (Count > 15, calibrated values)
    - 25 pts: Output files exist (Histogram, Annotated Image, Report)
    - 20 pts: Report Accuracy (Values match logic)
    - 30 pts: VLM Trajectory Verification (Scale set, Threshold used)
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result_data.get("files", {})
    csv_data = result_data.get("csv_data", {})
    report_data = result_data.get("report_data", {})

    # =========================================================
    # CRITERION 1: Measurement CSV (25 pts)
    # =========================================================
    csv_file = files.get("particle_measurements.csv", {})
    if csv_file.get("exists") and csv_file.get("created_during_task"):
        row_count = csv_data.get("row_count", 0)
        is_calibrated = csv_data.get("calibrated", False)
        
        if row_count >= 15:
            score += 10
            feedback.append("CSV row count sufficient.")
        else:
            feedback.append(f"CSV row count too low ({row_count}).")

        if is_calibrated:
            score += 15
            feedback.append("Measurements appear calibrated (µm).")
        else:
            feedback.append("Measurements appear uncalibrated (pixels) or invalid.")
    else:
        feedback.append("Measurement CSV not created.")

    # =========================================================
    # CRITERION 2: Output Files (25 pts)
    # =========================================================
    # Histogram
    hist = files.get("size_distribution.png", {})
    if hist.get("exists") and hist.get("size", 0) > 1000:
        score += 10
        feedback.append("Histogram created.")
    
    # Annotated Image
    anno = files.get("annotated_micrograph.png", {})
    if anno.get("exists") and anno.get("created_during_task") and anno.get("size", 0) > 5000:
        score += 15
        feedback.append("Annotated micrograph created.")
    
    # =========================================================
    # CRITERION 3: Report Content (20 pts)
    # =========================================================
    rep_file = files.get("inclusion_report.txt", {})
    if rep_file.get("exists") and report_data.get("valid_format"):
        content = report_data.get("content", {})
        if content.get("total_particles") and content.get("qc_result"):
            score += 20
            feedback.append("Report format valid.")
        else:
            score += 10
            feedback.append("Report created but missing required fields.")
    else:
        feedback.append("Report missing.")

    # =========================================================
    # CRITERION 4: VLM Trajectory Verification (30 pts)
    # =========================================================
    # We check if the agent actually used the necessary dialogs
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Analyze these screenshots of a Fiji/ImageJ session.
    I am looking for evidence of three specific steps:
    1. "Set Scale" dialog or setting spatial calibration (µm/pixel).
    2. "Threshold" dialog or a binary (black/white) image appearing.
    3. "Analyze Particles" dialog or a Results table appearing.
    
    Return JSON:
    {
        "set_scale_seen": boolean,
        "threshold_seen": boolean,
        "analyze_seen": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and "parsed" in vlm_result:
        parsed = vlm_result["parsed"]
        if parsed.get("set_scale_seen"): vlm_score += 10
        if parsed.get("threshold_seen"): vlm_score += 10
        if parsed.get("analyze_seen"): vlm_score += 10
        feedback.append(f"VLM Verification: {parsed.get('reasoning', 'No reasoning provided')}")
    else:
        feedback.append("VLM verification failed to parse.")
    
    score += vlm_score

    # Final Pass Determination
    # Pass if score >= 60 AND CSV is calibrated (critical skill)
    passed = (score >= 60) and csv_data.get("calibrated", False)
    
    if not csv_data.get("calibrated", False):
        feedback.append("CRITICAL FAIL: Data was not calibrated to physical units.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }