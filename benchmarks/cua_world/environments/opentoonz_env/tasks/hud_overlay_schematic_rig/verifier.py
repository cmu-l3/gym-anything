#!/usr/bin/env python3
"""
Verifier for hud_overlay_schematic_rig task.

Verifies that:
1. The OpenToonz scene file (.tnz) contains proper schematic parenting (Child -> Camera).
2. The rendered output demonstrates the overlay stays fixed relative to the frame.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
from PIL import Image

def verify_hud_overlay_schematic_rig(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    
    # Temp file management
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_scene = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')
    temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load result JSON
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        scene_exists = result.get("scene_exists", False)
        output_new_count = result.get("output_new_count", 0)
        
        # --- CRITERION 1: Scene File Existence (10 pts) ---
        if scene_exists:
            score += 10
            feedback_parts.append("Scene file saved.")
        else:
            feedback_parts.append("Scene file NOT saved.")

        # --- CRITERION 2: Schematic Parenting Check (40 pts) ---
        # Parse the TNZ XML to check if any column is parented to Camera
        parenting_correct = False
        if scene_exists:
            try:
                copy_from_env("/tmp/hud_test_scene.tnz", temp_scene.name)
                tree = ET.parse(temp_scene.name)
                root = tree.getroot()
                
                # In OpenToonz TNZ XML:
                # <pegbar id="Col1"> ... <parent handle="B" id="Camera1" ...> </pegbar>
                # "Camera1" is the default ID for the camera node.
                
                for pegbar in root.findall(".//pegbar"):
                    parent_node = pegbar.find("parent")
                    if parent_node is not None:
                        parent_id = parent_node.get("id", "")
                        # Check if parent is a Camera node
                        if "Camera" in parent_id:
                            parenting_correct = True
                            break
                            
                if parenting_correct:
                    score += 40
                    feedback_parts.append("Schematic Verification Passed: Layer parented to Camera.")
                else:
                    feedback_parts.append("Schematic Verification Failed: No layer found parented to Camera.")
            except Exception as e:
                feedback_parts.append(f"Error parsing scene XML: {str(e)}")

        # --- CRITERION 3: Render Output Exists (20 pts) ---
        if output_new_count >= 5:
            score += 20
            feedback_parts.append(f"Render output found ({output_new_count} frames).")
        elif output_new_count > 0:
            score += 10
            feedback_parts.append("Render output incomplete.")
        else:
            feedback_parts.append("No new render output found.")

        # --- CRITERION 4: Visual Verification of HUD (30 pts) ---
        # Check the last frame for a red object in the center.
        # Since the camera moves, a non-parented object would likely drift.
        # A parented object stays in the center.
        visual_pass = False
        try:
            if result.get("verification_image_path"):
                copy_from_env("/tmp/hud_last_frame.png", temp_image.name)
                img = Image.open(temp_image.name)
                width, height = img.size
                
                # Define center region (e.g., 10% of center)
                cx, cy = width // 2, height // 2
                box_size = min(width, height) // 8
                center_crop = img.crop((cx - box_size, cy - box_size, cx + box_size, cy + box_size))
                
                # Check for significant red pixels
                # "Red" roughly means R > 100 and R > G+B
                pixels = list(center_crop.getdata())
                red_pixel_count = 0
                for p in pixels:
                    # Handle RGBA or RGB
                    r = p[0]
                    g = p[1]
                    b = p[2]
                    if r > 120 and r > (g + b) * 0.8:
                        red_pixel_count += 1
                
                # Threshold: At least 50 red pixels in the center
                if red_pixel_count > 50:
                    visual_pass = True
                    score += 30
                    feedback_parts.append("Visual Verification Passed: Red object detected in center of last frame.")
                else:
                    feedback_parts.append(f"Visual Verification Failed: No red object in center of last frame (Found {red_pixel_count} red pixels).")
        except Exception as e:
            feedback_parts.append(f"Visual analysis failed: {str(e)}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_scene.name): os.unlink(temp_scene.name)
        if os.path.exists(temp_image.name): os.unlink(temp_image.name)

    # Pass condition: 
    # Must have Scene File AND (Parenting Correct OR Visual Pass)
    # This allows for alternative rigging methods if they visually work, 
    # but strongly incentivizes the requested schematic approach.
    passed = scene_exists and (parenting_correct or visual_pass) and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }