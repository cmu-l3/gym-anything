#!/usr/bin/env python3
"""
Verifier for create_medical_illustration_base task.

Criteria:
1. Output PNG file exists and was created during task (10 pts)
2. Image content analysis (Python):
   - Background is white (20 pts)
   - Object is red (20 pts)
   - Valid dimensions (10 pts)
3. Visual Verification (VLM):
   - View is Anterior/Frontal (20 pts)
   - No UI overlays (Bounding Box/Axes) (20 pts)

Total: 100 pts
Pass Threshold: 80 pts (Must have correct file and aesthetics)
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_medical_illustration_base(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # --- 1. Load Result Metadata ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- 2. File Existence & Creation Check (10 pts) ---
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not result.get("file_created_during_task", False):
         feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session")
         # We penalize but continue check in case of clock skew, though ideally this fails
    else:
        score += 10
        feedback_parts.append("File created successfully")

    # --- 3. Image Analysis (Python) (50 pts total) ---
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    img_valid = False
    try:
        copy_from_env(result.get("output_path", ""), temp_img.name)
        with Image.open(temp_img.name) as img:
            img = img.convert('RGB')
            width, height = img.size
            pixels = np.array(img)
            img_valid = True
            
            # Dimensions Check (10 pts)
            if width > 400 and height > 400:
                score += 10
                feedback_parts.append(f"Dimensions OK ({width}x{height})")
            else:
                feedback_parts.append(f"Image too small ({width}x{height})")

            # Background Check (20 pts)
            # Sample corners (10x10 patches)
            corners = [
                pixels[0:10, 0:10],          # Top-left
                pixels[0:10, -10:],          # Top-right
                pixels[-10:, 0:10],          # Bottom-left
                pixels[-10:, -10:]           # Bottom-right
            ]
            is_white = True
            for patch in corners:
                # Allow slight compression artifacts, but roughly 255
                if np.mean(patch) < 250:
                    is_white = False
                    break
            
            if is_white:
                score += 20
                feedback_parts.append("Background is white")
            else:
                feedback_parts.append("Background is NOT white")

            # Object Color Check (20 pts)
            # Filter out white background pixels
            # Mask: pixels where R,G,B are NOT all > 250
            non_white_mask = np.any(pixels < 250, axis=2)
            object_pixels = pixels[non_white_mask]
            
            if len(object_pixels) > 1000: # Ensure there is an object
                avg_color = np.mean(object_pixels, axis=0)
                r, g, b = avg_color
                # Red dominance check: R significantly greater than G and B
                if r > g + 30 and r > b + 30:
                    score += 20
                    feedback_parts.append("Object color is Red")
                else:
                    feedback_parts.append(f"Object color is not Red (Avg RGB: {int(r)},{int(g)},{int(b)})")
            else:
                feedback_parts.append("Image appears empty/blank")

    except Exception as e:
        feedback_parts.append(f"Image analysis failed: {e}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # --- 4. VLM Verification (40 pts total) ---
    # Only proceed if image was valid, otherwise VLM is useless
    if img_valid:
        final_screenshot = get_final_screenshot(traj) # We check the UI context if possible, or the exported file
        # Actually, for this task, the exported file IS the primary evidence for the "clean view" requirement.
        # But we also want to ensure they didn't just download a picture.
        # Let's verify the exported image itself using VLM.
        
        # We need to re-read the temp image for VLM or pass the path if the VLM tool supports it.
        # The query_vlm usually takes a PIL image or numpy array.
        # We'll use the temp_img path we downloaded earlier (we need to keep it or re-download).
        # Let's re-download to be safe/clean logic.
        
        temp_img_vlm = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result.get("output_path", ""), temp_img_vlm.name)
            
            prompt = """
            You are verifying a medical illustration task. 
            Look at this image of a skull.
            1. Is the view from the FRONT (Anterior)? (Face-on view).
            2. Are there any UI overlays visible ON TOP of the skull, like a colorful bounding box or 3D axis arrows?
            
            Respond in JSON:
            {
                "is_anterior_view": true/false,
                "has_bounding_box_or_axes": true/false,
                "reasoning": "..."
            }
            """
            
            vlm_res = query_vlm(prompt=prompt, image=temp_img_vlm.name)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("is_anterior_view"):
                    score += 20
                    feedback_parts.append("VLM: View is Anterior")
                else:
                    feedback_parts.append("VLM: View is NOT Anterior")
                    
                if not parsed.get("has_bounding_box_or_axes"):
                    score += 20
                    feedback_parts.append("VLM: View is clean (no UI)")
                else:
                    feedback_parts.append("VLM: Bounding box or axes visible")
            else:
                feedback_parts.append("VLM query failed")
                
        except Exception as e:
            feedback_parts.append(f"VLM step error: {e}")
        finally:
            if os.path.exists(temp_img_vlm.name):
                os.unlink(temp_img_vlm.name)

    # --- Final Score ---
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }