#!/usr/bin/env python3
"""
Verifier for rig_hinge_pivot_point task.
"""

import json
import tempfile
import os
import logging
import math
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rig_hinge_pivot_point(traj, env_info, task_info):
    """
    Verifies that the agent correctly moved the pivot point before rotating.
    
    Strategy:
    1. Image Analysis: Calculate the centroid of the rendered lever arm.
       - If pivot is DEFAULT (Center), the arm spins in place. Centroid stays near screen center.
       - If pivot is HINGE (Top), the arm swings to the side. Centroid moves significantly.
    2. File Checks: Timestamps and existence.
    3. Scene Parsing: Check .tnz file for non-zero center values.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import image libraries safely
    try:
        import numpy as np
        import cv2
    except ImportError:
        return {"passed": False, "score": 0, "feedback": "Verification failed: missing dependencies (numpy/opencv)"}

    # Metadata thresholds
    metadata = task_info.get('metadata', {})
    # 1920x1080 resolution. Center is (960, 540).
    # Asset is ~300px tall. CoM is ~150px from center if not moved.
    # If rotated 90 deg around center: CoM stays at center (distance ~0).
    # If rotated 90 deg around top hinge: CoM moves ~150px away.
    MIN_DISPLACEMENT = metadata.get('expected_min_centroid_displacement', 80) 

    # Load result JSON
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

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Files Exist and Newer (30 pts)
    # ---------------------------------------------------------
    img_exists = result.get("img_exists", False)
    img_newer = result.get("img_newer", False)
    scene_exists = result.get("scene_exists", False)
    
    if img_exists and img_newer:
        score += 20
        feedback_parts.append("Rendered image created")
    elif img_exists:
        score += 10
        feedback_parts.append("Rendered image exists (but timestamp issue)")
    else:
        feedback_parts.append("Rendered image missing")
        
    if scene_exists:
        score += 10
        feedback_parts.append("Scene file saved")

    # ---------------------------------------------------------
    # Criterion 2: Visual Centroid Analysis (50 pts)
    # ---------------------------------------------------------
    centroid_passed = False
    
    if img_exists:
        # Copy image file
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result["img_path"], temp_img.name)
            
            # Read image using OpenCV
            img = cv2.imread(temp_img.name, cv2.IMREAD_UNCHANGED)
            
            if img is None:
                feedback_parts.append("Failed to decode image")
            else:
                # Get Alpha Channel or Convert to Grayscale (assuming white bg if no alpha)
                if img.shape[2] == 4:
                    alpha = img[:, :, 3]
                else:
                    # Assume white background, threshold dark pixels
                    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
                    _, alpha = cv2.threshold(gray, 240, 255, cv2.THRESH_BINARY_INV)

                # Find non-zero pixels
                points = cv2.findNonZero(alpha)
                
                if points is None:
                    feedback_parts.append("Rendered image is empty/blank")
                else:
                    # Calculate Centroid
                    M = cv2.moments(alpha)
                    if M["m00"] != 0:
                        cX = int(M["m10"] / M["m00"])
                        cY = int(M["m01"] / M["m00"])
                        
                        # Calculate distance from screen center (assuming 1920x1080)
                        # OpenToonz default camera is usually centered.
                        # If resolution differs, we might need to check dimensions, 
                        # but standard task setup implies 1920x1080 or default.
                        # We'll use the image dimensions to find center.
                        h, w = alpha.shape
                        screen_cx, screen_cy = w // 2, h // 2
                        
                        dist = math.sqrt((cX - screen_cx)**2 + (cY - screen_cy)**2)
                        
                        logger.info(f"Centroid: ({cX}, {cY}), Screen Center: ({screen_cx}, {screen_cy}), Dist: {dist}")
                        
                        if dist >= MIN_DISPLACEMENT:
                            score += 50
                            centroid_passed = True
                            feedback_parts.append(f"Visual Pivot Check Passed (Displacement: {dist:.1f}px)")
                        else:
                            feedback_parts.append(f"Visual Pivot Check Failed: Object is still centered (Displacement: {dist:.1f}px). Pivot likely not moved.")
                    else:
                        feedback_parts.append("Image empty (zero moments)")

        except Exception as e:
            feedback_parts.append(f"Image analysis error: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

    # ---------------------------------------------------------
    # Criterion 3: Scene File Inspection (20 pts)
    # ---------------------------------------------------------
    # Check if .tnz XML contains non-zero <center> tags
    if scene_exists:
        temp_scene = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')
        try:
            copy_from_env(result["scene_path"], temp_scene.name)
            
            import xml.etree.ElementTree as ET
            try:
                tree = ET.parse(temp_scene.name)
                root = tree.getroot()
                
                # Look for <center> <x>...</x> <y>...</y> </center>
                # Note: Structure varies, usually inside <pegbar>
                center_modified = False
                for elem in root.iter('center'):
                    x_node = elem.find('x')
                    y_node = elem.find('y')
                    if x_node is not None and y_node is not None:
                        try:
                            x_val = float(x_node.text)
                            y_val = float(y_node.text)
                            if abs(x_val) > 0.1 or abs(y_val) > 0.1:
                                center_modified = True
                                break
                        except ValueError:
                            pass
                
                if center_modified:
                    score += 20
                    feedback_parts.append("Scene file confirms pivot modification")
                else:
                    feedback_parts.append("Scene file shows default pivot (0,0)")

            except ET.ParseError:
                feedback_parts.append("Failed to parse scene file")
                
        except Exception as e:
            feedback_parts.append(f"Scene analysis error: {e}")
        finally:
            if os.path.exists(temp_scene.name):
                os.unlink(temp_scene.name)

    # Final Result
    # Must pass visual check to pass task
    passed = (score >= 70) and centroid_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }