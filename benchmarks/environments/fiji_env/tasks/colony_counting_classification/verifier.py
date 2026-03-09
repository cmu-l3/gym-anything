#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_colony_counting(traj, env_info, task_info):
    """
    Verifies the Colony Counting and Classification task.
    
    Scoring Criteria (100 pts total):
    1. [20 pts] Measurements CSV exists, valid format, created during task.
    2. [15 pts] Colony count is within reasonable range (10-300).
    3. [15 pts] Size classification performed (Small/Medium/Large detected).
    4. [15 pts] Summary report exists and contains required keywords.
    5. [10 pts] Size distribution CSV exists and is valid.
    6. [10 pts] Overlay image exists (visual proof of segmentation).
    7. [15 pts] VLM verification of workflow (Analyze Particles usage).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    files = result.get("files", {})
    data = result.get("data", {})
    
    # --- Criterion 1: Measurements CSV (20 pts) ---
    meas_file = files.get("measurements", {})
    if meas_file.get("exists") and meas_file.get("created_after_start"):
        score += 20
        feedback.append("Measurements CSV created.")
    else:
        feedback.append("Measurements CSV missing or stale.")

    # --- Criterion 2: Colony Count Range (15 pts) ---
    count = data.get("colony_count", 0)
    # The image usually has ~50-150 colonies depending on segmentation parameters
    if 10 <= count <= 300:
        score += 15
        feedback.append(f"Colony count reasonable ({count}).")
    elif count > 0:
        score += 5
        feedback.append(f"Colony count detected but suspicious ({count}).")
    else:
        feedback.append("No colonies detected in CSV.")

    # --- Criterion 3: Size Classification (15 pts) ---
    classes = data.get("size_classes_found", [])
    if data.get("has_classification") and len(classes) >= 2:
        score += 15
        feedback.append(f"Size classification found ({', '.join(classes)}).")
    elif data.get("has_classification"):
        score += 10
        feedback.append("Partial size classification found.")
    else:
        feedback.append("No size classification labels found in CSV.")

    # --- Criterion 4: Summary Report (15 pts) ---
    summary = files.get("summary", {})
    if summary.get("exists") and data.get("summary_content_valid"):
        score += 15
        feedback.append("Summary report valid.")
    elif summary.get("exists"):
        score += 5
        feedback.append("Summary report exists but content missing keywords.")

    # --- Criterion 5: Distribution CSV (10 pts) ---
    dist = files.get("distribution", {})
    if dist.get("exists") and data.get("distribution_valid"):
        score += 10
        feedback.append("Distribution table valid.")

    # --- Criterion 6: Overlay Image (10 pts) ---
    overlay = files.get("overlay", {})
    if overlay.get("exists") and overlay.get("size", 0) > 1000:
        score += 10
        feedback.append("Overlay image created.")

    # --- Criterion 7: VLM Workflow Verification (15 pts) ---
    # Check if agent used "Analyze Particles" or "Threshold" UI
    trajectory_images = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        trajectory_images.append(final_img)

    vlm_prompt = """
    Review these screenshots of a Fiji/ImageJ workflow.
    Did the user perform image segmentation and particle analysis?
    Look for:
    1. A black and white binary mask image (thresholding).
    2. The "Analyze Particles" dialog or Results table.
    3. An image with outlines or numbers drawn on colonies.
    
    Answer YES or NO and provide a brief reason.
    """
    
    vlm_result = query_vlm(images=trajectory_images, prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and isinstance(vlm_result, dict):
        # Handle parsed JSON response if VLM wrapper returns it, or raw string
        response_text = vlm_result.get("response", "").upper()
        if "YES" in response_text:
            vlm_passed = True
    
    if vlm_passed:
        score += 15
        feedback.append("VLM verified visual workflow.")
    else:
        feedback.append("VLM could not verify visual workflow.")

    return {
        "passed": score >= 65, # Pass if reasonably complete
        "score": score,
        "feedback": " ".join(feedback)
    }