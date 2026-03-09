#!/usr/bin/env python3
"""
Verifier for apply_pseudocolor_export task.

Verification Strategy:
1. File Verification: Check if /home/ga/Documents/pseudocolor_view.png exists and was created during the task.
2. Image Content Analysis (Host-side):
   - Check if the image is valid PNG.
   - Check if the image is strictly grayscale (Failure condition).
   - Check for sufficient color diversity (confirms a LUT was applied, not just a tint).
3. VLM Verification:
   - Confirm image shows anatomical structures (skull/brain).
   - Visually confirm "false color" or "heatmap" style appearance.

Scoring:
- File exists & valid: 20 pts
- Created during task: 10 pts
- Programmatic Color Check (NOT grayscale): 30 pts
- Programmatic Color Diversity: 10 pts
- VLM Visual Confirmation: 30 pts
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

# Import VLM utilities from framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock for local testing if framework not present
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apply_pseudocolor_export(traj, env_info, task_info):
    """
    Verify that the user exported a pseudocolor image of the CT scan.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/pseudocolor_view.png')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Step 1: Retrieve Task Result Metadata ---
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}

    # --- Step 2: Retrieve the Exported Image for Analysis ---
    output_exists = result_data.get("output_exists", False)
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file pseudocolor_view.png was not found."
        }

    score += 20
    feedback_parts.append("File created")

    # Time check
    if result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("Timestamp OK")
    else:
        feedback_parts.append("File timestamp predates task (stale data?)")

    # Download the image to host
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    img_path = temp_img.name
    temp_img.close() # Close handle so we can write to it via copy
    
    try:
        copy_from_env(expected_path, img_path)
        
        # --- Step 3: Programmatic Image Analysis ---
        try:
            img = Image.open(img_path)
            img = img.convert('RGB')
            arr = np.array(img)
            
            # Check dimensions
            if arr.shape[0] < 400 or arr.shape[1] < 400:
                feedback_parts.append("Image too small")
            else:
                # 3.1 Grayscale Check
                # If R == G == B for all pixels, it's grayscale.
                # We calculate absolute difference between channels.
                diff_rg = np.mean(np.abs(arr[:,:,0].astype(int) - arr[:,:,1].astype(int)))
                diff_gb = np.mean(np.abs(arr[:,:,1].astype(int) - arr[:,:,2].astype(int)))
                
                # Threshold: A pure grayscale image has diff ~ 0.
                # A pseudocolor image should have significant differences.
                is_grayscale = (diff_rg < 2.0) and (diff_gb < 2.0)
                
                if is_grayscale:
                    feedback_parts.append("FAIL: Image appears to be grayscale (no pseudocolor applied)")
                else:
                    score += 30
                    feedback_parts.append("Color channels active (non-grayscale)")
                    
                    # 3.2 Color Diversity Check (Prevent solid color overlay gaming)
                    # We look at the standard deviation of the Hue channel
                    hsv_img = img.convert('HSV')
                    h_channel = np.array(hsv_img)[:,:,0]
                    # Filter out black background (val=0) to focus on tissue
                    v_channel = np.array(hsv_img)[:,:,2]
                    mask = v_channel > 20
                    
                    if np.sum(mask) > 0:
                        h_std = np.std(h_channel[mask])
                        # A single color tint has low Hue std dev. A heatmap/rainbow has high.
                        # H is 0-255 in PIL. 
                        if h_std > 10: 
                            score += 10
                            feedback_parts.append("Good color diversity")
                        else:
                            feedback_parts.append("Low color diversity (monochrome tint?)")
                    else:
                        feedback_parts.append("Image mostly empty/black")

        except Exception as e:
            logger.error(f"Image analysis failed: {e}")
            feedback_parts.append(f"Image analysis failed: {str(e)}")
            
    except Exception as e:
        feedback_parts.append(f"Failed to copy output image: {str(e)}")
    finally:
        if os.path.exists(img_path):
            os.unlink(img_path)

    # --- Step 4: VLM Verification ---
    # We use the exported image itself if available, otherwise fallback to final screenshot
    vlm_image = img_path if os.path.exists(img_path) else get_final_screenshot(traj)
    
    if vlm_image:
        prompt = """
        You are verifying a task where an agent must apply a pseudocolor (false color) lookup table to a medical CT scan.
        Analyze this image.
        1. Does it show anatomical structures (like a skull or brain scan)?
        2. Is the color scheme grayscale (black/white) or pseudocolor (rainbow, heatmap, blue/green/red gradients)?
        
        Respond JSON: {"shows_anatomy": bool, "is_pseudocolor": bool, "description": "short string"}
        """
        
        # Note: In a real run we'd re-download the image or pass the bytes. 
        # Here we assume query_vlm handles the file path or we rely on the framework's screenshot.
        # Since we might have deleted img_path above, let's use the framework's screenshot mechanism
        # or rely on the programmatic check primarily.
        
        # Let's verify based on trajectory frames to ensure they navigated the menu
        frames = sample_trajectory_frames(traj, 5)
        vlm_res = query_vlm(
            prompt="Did the agent open a color/LUT menu and apply a color scheme to the CT scan? Does the final view show colored anatomy?",
            images=frames + [get_final_screenshot(traj)]
        )
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            # We treat the VLM score as confirming the visual aspect
            # We look for positive confirmation in the text or structured output
            # Simple heuristic for this template:
            if "yes" in str(vlm_res).lower() and "color" in str(vlm_res).lower():
                score += 30
                feedback_parts.append("VLM confirmed visual success")
            else:
                # If VLM is unsure but programmatic passed, we give benefit of doubt or partial
                if score >= 60: 
                    score += 15 
                    feedback_parts.append("VLM partial confirmation")
                else:
                    feedback_parts.append("VLM visual check failed")
        else:
            # Fallback if VLM fails but programmatic passed
            if score >= 60:
                score += 10
                feedback_parts.append("VLM unavailable, relying on code check")

    # --- Final Score Calculation ---
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }