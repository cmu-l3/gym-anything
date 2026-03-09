#!/usr/bin/env python3
"""
Verifier for depth_color_coded_projection task.

Criteria:
1. Files exist and created during task (30 pts)
2. Coded Projection is RGB and has color diversity (indicating depth coding) (25 pts)
3. Standard MIP is grayscale/monochromatic (10 pts)
4. Report contains correct metadata (channels, slices) (10 pts)
5. VLM Verification of workflow (25 pts)
"""

import json
import os
import tempfile
import logging
from PIL import Image
import numpy as np

# Import VLM utilities from the environment framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback/mock for local testing
    def query_vlm(**kwargs): return {"passed": False, "score": 0, "feedback": "VLM not available"}
    def sample_trajectory_frames(traj, n=1): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_depth_color_coded_projection(traj, env_info, task_info):
    """
    Verify the depth color coding task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Load JSON Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. File Existence & Timing Checks (30 pts)
    files_ok = True
    
    # Check MIP
    if result['mip_file']['exists'] and result['mip_file']['created_during']:
        score += 10
        feedback.append("Standard MIP created.")
    else:
        feedback.append("Standard MIP missing or old.")
        files_ok = False

    # Check Coded Projection
    if result['coded_file']['exists'] and result['coded_file']['created_during']:
        score += 10
        feedback.append("Depth-coded projection created.")
    else:
        feedback.append("Depth-coded projection missing or old.")
        files_ok = False

    # Check Report
    if result['report_file']['exists'] and result['report_file']['created_during']:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing.")
        files_ok = False

    # 3. Image Analysis (35 pts)
    if files_ok:
        # Get images
        temp_mip = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        temp_coded = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name

        try:
            copy_from_env("/tmp/verify_mip.png", temp_mip)
            copy_from_env("/tmp/verify_coded.png", temp_coded)
            copy_from_env("/tmp/verify_report.txt", temp_report)

            # Analyze Coded Projection (25 pts)
            try:
                img_coded = Image.open(temp_coded)
                if img_coded.mode != 'RGB' and img_coded.mode != 'RGBA':
                    feedback.append("Coded projection is not RGB.")
                else:
                    # check color diversity (Hue histogram)
                    # Convert to HSV
                    hsv = img_coded.convert('HSV')
                    # Get Hue channel
                    h = np.array(hsv)[:,:,0]
                    # Get Saturation channel (filter background)
                    s = np.array(hsv)[:,:,1]
                    
                    # Consider only pixels with sufficient saturation (not gray/black background)
                    valid_pixels = h[s > 20]
                    
                    if len(valid_pixels) > 0:
                        # Calculate histogram of hues (0-255)
                        hist, _ = np.histogram(valid_pixels, bins=10, range=(0, 255))
                        # Count bins with significant pixels (> 5% of total valid)
                        significant_bins = np.sum(hist > (len(valid_pixels) * 0.05))
                        
                        if significant_bins >= 3:
                            score += 25
                            feedback.append("Coded projection shows good color diversity (Depth Coding confirmed).")
                        else:
                            score += 5
                            feedback.append("Coded projection lacks color diversity (looks monochromatic).")
                    else:
                        feedback.append("Image is mostly grayscale/black.")
            except Exception as e:
                feedback.append(f"Error analyzing coded image: {e}")

            # Analyze MIP (10 pts)
            try:
                img_mip = Image.open(temp_mip)
                # Should be grayscale or RGB with low saturation
                if img_mip.mode == 'L':
                    score += 10
                    feedback.append("MIP is grayscale.")
                else:
                    # Check if it looks grayscale
                    stat = np.array(img_mip.convert('HSV'))
                    mean_sat = np.mean(stat[:,:,1])
                    if mean_sat < 10: # Low saturation
                        score += 10
                        feedback.append("MIP looks grayscale.")
                    else:
                        feedback.append("MIP has high color saturation (unexpected).")
            except Exception as e:
                feedback.append(f"Error analyzing MIP: {e}")
                
            # Analyze Report Content (10 pts)
            try:
                with open(temp_report, 'r') as f:
                    content = f.read().lower()
                    # Check for keywords
                    if "channel" in content or "channels" in content:
                        score += 5
                    if "slice" in content or "slices" in content:
                        score += 5
            except Exception as e:
                feedback.append("Error reading report.")

        finally:
            if os.path.exists(temp_mip): os.unlink(temp_mip)
            if os.path.exists(temp_coded): os.unlink(temp_coded)
            if os.path.exists(temp_report): os.unlink(temp_report)

    # 4. VLM Verification (25 pts)
    # Use trajectory to ensure they actually used the plugin and didn't just paint
    frames = sample_trajectory_frames(traj, n=5)
    final_ss = get_final_screenshot(traj)
    
    if frames and final_ss:
        prompt = """
        Review these screenshots of a user working in Fiji (ImageJ).
        
        The user should have:
        1. Extracted a green channel from a microscopy stack.
        2. Created a standard black/white projection.
        3. Used 'Temporal-Color Code' (or Depth Coded Stack) plugin.
        4. Produced a colorful image where colors represent depth (rainbow/fire colors).
        
        Look for:
        - A dialog box titled "Temporal-Color Code".
        - A final image that looks like a cell with a rainbow gradient or distinct colors for different parts.
        
        Does the final state show a successfully created depth-coded projection?
        """
        
        vlm_res = query_vlm(images=frames + [final_ss], prompt=prompt)
        
        if vlm_res.get("success"):
            # Simple keyword check in reasoning or boolean parsed result
            # Assuming VLM returns a structured or positive sentiment
            # For this template, we trust a simple positive assessment
            # In production, use structured JSON output from VLM
            reasoning = vlm_res.get("result", "").lower()
            if "yes" in reasoning or "success" in reasoning or "true" in str(vlm_res.get("parsed", "")):
                score += 25
                feedback.append("VLM verified workflow steps.")
            else:
                feedback.append("VLM did not observe correct workflow.")
        else:
             # If VLM fails, we give partial credit if file analysis was perfect
             if score >= 65:
                 score += 25
                 feedback.append("VLM check skipped, trusted file analysis.")

    # Final tally
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }