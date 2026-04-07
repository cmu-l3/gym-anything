#!/usr/bin/env python3
"""
Verifier for the Inverted Finding Chart Generation task.

Combines programmatic file/pixel verification with VLM trajectory analysis.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt focuses on finding specific graphical additions the agent had to make
VLM_PROMPT = """You are verifying an agent's desktop trajectory while creating a finding chart in AstroImageJ.

Look at the trajectory frames and the final screenshot. We are looking for three specific features in the astronomical image:
1. INVERTED_IMAGE: Is the main astronomical image inverted? (It should have a white/light background with dark stars and dark nebula structures).
2. TEXT_ANNOTATION: Did the agent type the text "M16 Core" on the image?
3. MARKER_VISIBLE: Did the agent draw a marker (such as a drawn circle, box, crosshair, or arrow) pointing out a specific structure (the pillar) in the nebula?

Respond ONLY in valid JSON format:
{
    "inverted_image_visible": true/false,
    "text_annotation_visible": true/false,
    "marker_visible": true/false,
    "confidence": "low/medium/high",
    "observations": "brief reasoning"
}
"""

def verify_finding_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_correlation = metadata.get('min_correlation_score', 0.35)
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch the JSON evaluation written by the container
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

    # Criterion 1: Output File Exists & Anti-Gaming Timestamp (20 points)
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output PNG file was not found."}
        
    if result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("File created during session")
    else:
        feedback_parts.append("File found, but timestamp suggests it was NOT created during this session")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Dimensions Check (15 points)
    w, h = result.get("dimensions", [0, 0])
    if 450 <= w <= 550 and 450 <= h <= 550:
        score += 15
        feedback_parts.append(f"Dimensions accurate ({w}x{h})")
    elif 300 <= w <= 800 and 300 <= h <= 800:
        score += 5
        feedback_parts.append(f"Dimensions approximate ({w}x{h})")
    else:
        feedback_parts.append(f"Dimensions incorrect ({w}x{h})")

    # Criterion 3: Data Authenticity via Template Matching (25 points)
    corr_raw = result.get("correlation_raw", 0.0)
    corr_inv = result.get("correlation_inv", 0.0)
    best_corr = max(corr_raw, corr_inv)
    
    if best_corr >= min_correlation:
        score += 25
        feedback_parts.append(f"Authentic crop confirmed (correlation: {best_corr:.2f})")
    else:
        feedback_parts.append(f"Image match failed (correlation: {best_corr:.2f}) - likely a synthetic image or wrong region")

    # Criterion 4: Successfully Inverted (15 points)
    if corr_inv > (corr_raw + 0.05) and best_corr >= min_correlation:
        score += 15
        feedback_parts.append("LUT Inversion mathematically verified")
    elif best_corr >= min_correlation:
        feedback_parts.append("Image matches, but does NOT appear inverted relative to the FITS ground truth")

    # Criterion 5 & 6: VLM Verification of Overlays (25 points total)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    if final:
        frames.append(final)
        
    if query_vlm and frames:
        try:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res and vlm_res.get("success"):
                vlm_parsed = vlm_res.get("parsed", {})
                
                if vlm_parsed.get("text_annotation_visible"):
                    score += 15
                    feedback_parts.append("VLM confirmed 'M16 Core' text")
                else:
                    feedback_parts.append("VLM did not detect 'M16 Core' text")
                    
                if vlm_parsed.get("marker_visible"):
                    score += 10
                    feedback_parts.append("VLM confirmed target marker")
                else:
                    feedback_parts.append("VLM did not detect target marker")
            else:
                feedback_parts.append("VLM query failed")
        except Exception as e:
            feedback_parts.append(f"VLM exception: {e}")
    else:
        feedback_parts.append("VLM unavailable - skipped overlay checks")

    # Pass Condition: Must score >= 70, must have authentic data, and file must exist
    passed = (score >= 70) and (best_corr >= min_correlation) and result.get("output_exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }