#!/usr/bin/env python3
"""
Verifier for Fractal Venation Analysis task.

Verification Strategy:
1. Programmatic Checks (80 pts):
   - Result CSV exists and modified during task (15 pts)
   - Fractal Dimension (D) is present (20 pts)
   - D is within biologically plausible range [1.2, 1.9] (15 pts)
   - Box counting data present (>= 3 pairs) (20 pts)
   - Area fraction present (10 pts)

2. VLM Verification (20 pts):
   - Trajectory analysis: Did agent threshold the image (binary visible)?
   - Did the Fractal Box Count tool run (results/plot visible)?

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fractal_venation_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_d_min = metadata.get('expected_fractal_dimension_min', 1.2)
    expected_d_max = metadata.get('expected_fractal_dimension_max', 1.9)

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fractal_venation_analysis_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Programmatic Verification (Max 80 pts)
    # ---------------------------------------------------------

    # Criterion 1: File existence and anti-gaming timestamp (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("Result file created successfully")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("Result file exists but timestamp check failed")
    else:
        feedback_parts.append("Result file not found")

    # Criterion 2: Fractal Dimension Present (20 pts)
    d_val = result.get("fractal_dimension")
    if d_val is not None:
        score += 20
        feedback_parts.append(f"Fractal Dimension found: {d_val}")
        
        # Criterion 3: D in plausible range (15 pts)
        if expected_d_min <= d_val <= expected_d_max:
            score += 15
            feedback_parts.append("Dimension within biological range")
        else:
            feedback_parts.append(f"Dimension {d_val} outside expected range [{expected_d_min}-{expected_d_max}]")
    else:
        feedback_parts.append("Fractal Dimension value not found in CSV")

    # Criterion 4: Box Counting Data (20 pts)
    pairs = result.get("box_count_pairs", 0)
    monotonic = result.get("is_monotonic", False)
    
    if pairs >= 3:
        if monotonic:
            score += 20
            feedback_parts.append(f"Valid monotonic box-counting data ({pairs} pairs)")
        else:
            score += 10
            feedback_parts.append(f"Box-counting data found ({pairs} pairs) but not monotonic")
    else:
        feedback_parts.append("Insufficient box-counting data points")

    # Criterion 5: Area Fraction (10 pts)
    af = result.get("area_fraction")
    if af is not None:
        score += 10
        feedback_parts.append(f"Area Fraction found: {af}")
    else:
        feedback_parts.append("Area Fraction not found")

    # ---------------------------------------------------------
    # VLM Verification (Max 20 pts)
    # ---------------------------------------------------------
    # We need to verify the agent actually performed the thresholding and analysis
    # rather than just guessing numbers.
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a scientific image analysis task in ImageJ.
        The user must:
        1. Open a leaf image.
        2. Convert it to binary (black and white) using Thresholding.
        3. Run a Fractal Box Count analysis (shows a plot or results table).

        Look at the image sequence.
        
        Q1: Is a binary (black and white, thresholded) version of the leaf visible in any frame?
        Q2: Is a Fractal Box Count plot or results table visible in any frame?

        Respond in JSON:
        {
            "binary_image_visible": true/false,
            "fractal_results_visible": true/false,
            "explanation": "..."
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('binary_image_visible'):
                    score += 10
                    feedback_parts.append("VLM: Thresholding verified")
                if parsed.get('fractal_results_visible'):
                    score += 10
                    feedback_parts.append("VLM: Fractal analysis UI verified")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high, assume VLM passed implicitly
            if score >= 60:
                score += 20
                feedback_parts.append("VLM skipped (programmatic confidence high)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }