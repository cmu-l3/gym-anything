#!/usr/bin/env python3
"""
Verifier for Multi-Threshold Segmentation Comparison task.

Criteria:
1. File Creation (15 pts): CSV exists and created during task.
2. Data Quantity (20 pts): At least 4 rows of data.
3. Method Validity (20 pts): Method names match known ImageJ algorithms.
4. Data Validity (15 pts): Thresholds (0-255), Counts (>0), Areas (>0).
5. Procedure Verification (15 pts): Distinct threshold values (proves different algorithms used).
6. VLM Verification (15 pts): Trajectory shows workflow (Image -> Threshold -> Analyze).

Total: 100 points. Pass threshold: 60 points.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

KNOWN_METHODS = {
    'default', 'huang', 'intermodes', 'isodata', 'li', 'maxentropy',
    'mean', 'minerror', 'minimum', 'moments', 'otsu', 'percentile',
    'renyientropy', 'shanbhag', 'triangle', 'yen'
}

def verify_threshold_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Parse Programmatic Results
    # ---------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: File Existence & Freshness (15 pts)
    if data.get("file_exists") and data.get("file_created_during_task"):
        score += 15
        feedback.append("Result file created successfully.")
    elif data.get("file_exists"):
        score += 5
        feedback.append("Result file exists but timestamp is old (partial credit).")
    else:
        feedback.append("Result file not found.")

    # Criterion 2: Row Count (20 pts)
    row_count = data.get("row_count", 0)
    if row_count >= 4:
        score += 20
        feedback.append(f"Sufficient data rows ({row_count}).")
    elif row_count > 0:
        score += 5 * row_count
        feedback.append(f"Insufficient data rows ({row_count}/4).")
    else:
        feedback.append("No data rows found.")

    # Criterion 3: Method Validity (20 pts)
    methods = [m.lower().strip() for m in data.get("methods", [])]
    valid_methods = [m for m in methods if any(k in m for k in KNOWN_METHODS)]
    unique_valid = set(valid_methods)
    
    if len(unique_valid) >= 4:
        score += 20
        feedback.append(f"Valid methods used: {', '.join(unique_valid)}.")
    else:
        points = len(unique_valid) * 5
        score += points
        feedback.append(f"Only {len(unique_valid)} valid unique methods found (Need 4).")

    # Criterion 4: Data Validity (15 pts)
    thresholds = data.get("thresholds", [])
    counts = data.get("counts", [])
    
    valid_t = all(0 < t < 255 for t in thresholds)
    valid_c = all(c > 0 for c in counts)
    
    if row_count > 0 and valid_t and valid_c:
        score += 15
        feedback.append("Data values are valid.")
    elif row_count > 0:
        score += 5
        feedback.append("Some data values invalid (thresholds must be 1-254, counts > 0).")

    # Criterion 5: Distinct Thresholds (15 pts)
    # Different algorithms on the "Blobs" image MUST produce different thresholds.
    # If they are all the same, the agent likely didn't change the method.
    distinct = data.get("distinct_thresholds", 0)
    if distinct >= 3:
        score += 15
        feedback.append(f"Distinct thresholds found ({distinct}), indicating different methods.")
    elif distinct == 2:
        score += 8
        feedback.append("Only 2 distinct thresholds found.")
    elif distinct == 1 and row_count > 1:
        feedback.append("All threshold values are identical. Did you actually change the method?")

    # 2. VLM Verification
    # ---------------------------
    # Criterion 6: Visual Workflow Verification (15 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    if frames:
        prompt = (
            "Analyze these screenshots of a user working in ImageJ/Fiji.\n"
            "I need to verify they performed a segmentation benchmark workflow.\n"
            "Look for:\n"
            "1. The 'Blobs' sample image (white spots on black or vice versa).\n"
            "2. The 'Threshold' dialog window open.\n"
            "3. The 'Analyze Particles' dialog or a 'Results' table.\n"
            "Reply with JSON: {\"blobs_seen\": bool, \"threshold_dialog_seen\": bool, \"results_table_seen\": bool}"
        )
        
        try:
            res = query_vlm(images=frames + [final_screen], prompt=prompt)
            parsed = res.get("parsed", {})
            
            if parsed.get("blobs_seen"): vlm_score += 5
            if parsed.get("threshold_dialog_seen"): vlm_score += 5
            if parsed.get("results_table_seen"): vlm_score += 5
            
            score += vlm_score
            feedback.append(f"VLM verification score: {vlm_score}/15")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high (>70), grant VLM points automatically
            if score >= 70:
                score += 15
                feedback.append("VLM skipped but high programmatic confidence.")

    # Final Check
    passed = score >= 60 and row_count >= 4
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }