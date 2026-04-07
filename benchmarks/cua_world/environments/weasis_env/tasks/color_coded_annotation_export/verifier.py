#!/usr/bin/env python3
"""
Verifier for color_coded_annotation_export task.
Verifies programmatic image metadata, actual pixel colors, and utilizes VLM for semantic checks.
"""

import os
import json
import logging
import tempfile
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available - will fallback to programmatic evaluation only")

VLM_PROMPT = """You are evaluating an agent's completion of a medical imaging software task.
The agent was asked to annotate a finding on a DICOM image:
1. Draw an ellipse/oval around the finding.
2. Add text saying exactly "URGENT".
3. Change the properties of BOTH annotations' color to RED.

Look at the provided trajectory frames and final image:
1. Does the final image or any frame show a clear ellipse drawn on the medical image?
2. Is the exact text "URGENT" visible near the finding?
3. Are these annotations visibly RED?
4. Is there evidence the agent used the annotation/drawing toolbars or properties/color-picker menu?

Return a JSON with these booleans:
{
    "ellipse_drawn": true/false,
    "urgent_text_present": true/false,
    "annotations_are_red": true/false,
    "tools_used": true/false
}
"""

def analyze_image_colors(image_path):
    """
    Programmatic Image Analysis to ensure cheating didn't occur.
    Checks that the CT scan background remains grayscale while validating the
    presence of newly introduced purely red pixels (the annotations).
    """
    try:
        img = Image.open(image_path).convert("RGB")
        arr = np.array(img).astype(np.int32)
        
        r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
        total_pixels = r.size
        
        # Grayscale mask: R, G, B channels should be very close to each other
        gray_mask = (np.abs(r - g) < 25) & (np.abs(r - b) < 25) & (np.abs(g - b) < 25)
        gray_pixels = np.sum(gray_mask)
        gray_ratio = gray_pixels / total_pixels
        
        # Red Mask: Identifies explicit red pixels used for annotations
        # Using generous tolerances to account for anti-aliasing on text edges
        red_mask = (r > 120) & (g < 100) & (b < 100) & (r > g + 30) & (r > b + 30)
        red_pixels = np.sum(red_mask)
        
        return {
            "success": True,
            "gray_ratio": float(gray_ratio),
            "red_pixels": int(red_pixels)
        }
    except Exception as e:
        return {"success": False, "error": str(e)}

def verify_color_coded_annotation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1 & 2: Output file exists and was created during the task (20 pts)
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    expected_path = result.get('expected_path', '/home/ga/DICOM/exports/urgent_finding.jpg')
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and created_during_task:
        if output_size > 5000:
            score += 20
            feedback_parts.append("Valid exported JPEG found")
        else:
            score += 5
            feedback_parts.append("Exported file found but suspicious size (<5KB)")
    else:
        feedback_parts.append("Expected file not exported or pre-dated the task")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Retrieve the actual exported image for programmatic pixel analysis
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    try:
        copy_from_env(expected_path, temp_img.name)
        img_analysis = analyze_image_colors(temp_img.name)
        
        if img_analysis.get("success"):
            gray_ratio = img_analysis.get("gray_ratio", 0)
            red_pixels = img_analysis.get("red_pixels", 0)
            
            # Criterion 3: Background remains Grayscale (25 pts)
            if gray_ratio > 0.5:
                score += 25
                feedback_parts.append("Background image integrity confirmed (grayscale)")
            else:
                feedback_parts.append("Image is not predominantly grayscale (cheating detected)")
                
            # Criterion 4: Annotations are Red (25 pts)
            if red_pixels > 50:
                score += 25
                feedback_parts.append(f"Red annotation pixels verified (Count: {red_pixels})")
            else:
                feedback_parts.append(f"Red pixels not found (Count: {red_pixels})")
        else:
            feedback_parts.append(f"Failed to analyze image pixels: {img_analysis.get('error')}")
            
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # 3. VLM Verification of Semantic Content
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if final:
                images = frames + [final]
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("ellipse_drawn"): vlm_score += 7.5
                    if parsed.get("urgent_text_present"): vlm_score += 7.5
                    if parsed.get("annotations_are_red"): vlm_score += 7.5
                    if parsed.get("tools_used"): vlm_score += 7.5
                    
                    score += int(vlm_score)
                    feedback_parts.append(f"VLM Visual check passed ({vlm_score}/30 pts)")
                else:
                    feedback_parts.append("VLM query failed, skipping visual check")
        except Exception as e:
            logger.error(f"VLM validation error: {e}")
            feedback_parts.append("VLM error encountered")
    else:
        # If VLM is down/unavailable, give points if programmatic checks passed flawlessly
        if score == 70:
            score += 30
            feedback_parts.append("VLM unavailable - awarded points via programmatic success")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }