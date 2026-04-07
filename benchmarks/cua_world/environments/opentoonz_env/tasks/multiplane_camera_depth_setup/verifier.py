#!/usr/bin/env python3
"""
Verifier for multiplane_camera_depth_setup task.

Verifies:
1. Scene file (.tnz) exists and is valid XML.
2. Z-depth usage: At least one column has a Z position > 200 (or < -200).
3. Camera movement: Camera pegbar has keyframes or movement.
4. Render output: PNG sequence exists and was created during task.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multiplane_camera_depth_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scene_path = metadata.get('scene_file', '/home/ga/OpenToonz/projects/multiplane/multiplane.tnz')
    min_z_diff = metadata.get('min_z_depth_diff', 200)

    # Temporary files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_scene = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')

    try:
        # 1. Load result JSON
        copy_from_env("/tmp/multiplane_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        
        # 2. Load Scene File (if it exists)
        scene_content = None
        if result.get('scene_exists'):
            try:
                copy_from_env(scene_path, temp_scene.name)
                with open(temp_scene.name, 'r') as f:
                    scene_content = f.read()
            except Exception as e:
                logger.warning(f"Could not copy scene file: {e}")
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_scene.name): os.unlink(temp_scene.name)

    score = 0
    feedback_parts = []

    # --- Criterion 1: Scene File Existence (10 pts) ---
    if result.get('scene_exists'):
        score += 10
        feedback_parts.append("Scene file saved")
    else:
        feedback_parts.append("Scene file NOT found")
        return {"passed": False, "score": 0, "feedback": "Scene file missing"}

    # --- Criterion 2: Render Output (20 pts) ---
    render_count = result.get('render_newer_count', 0)
    if render_count >= 20:
        score += 20
        feedback_parts.append(f"Render complete ({render_count} frames)")
    elif render_count > 0:
        score += 10
        feedback_parts.append(f"Partial render ({render_count} frames)")
    else:
        feedback_parts.append("No rendered frames found")

    # --- Criterion 3: Analyze Scene XML for Z-Depth (40 pts) ---
    z_depth_found = False
    max_z = 0
    
    # --- Criterion 4: Analyze Scene XML for Camera Movement (30 pts) ---
    camera_moves = False

    if scene_content:
        try:
            root = ET.fromstring(scene_content)
            
            # Check Z-depth in Pegbars
            # OpenToonz stores pegbars in <xsheet><pegbar>
            # Look for <z> tag inside <pegbar>
            
            # Find all pegbars
            pegbars = root.findall(".//pegbar")
            for peg in pegbars:
                # check for z value
                z_elem = peg.find("z")
                if z_elem is not None:
                    # Check default value
                    default = z_elem.find("default")
                    if default is not None:
                        try:
                            val = float(default.text)
                            if abs(val) >= min_z_diff:
                                z_depth_found = True
                                max_z = val
                        except ValueError:
                            pass
                    
                    # Check keyframes
                    keyframes = z_elem.findall(".//L") # Keyframes are stored in <L> tags usually
                    for k in keyframes:
                        try:
                            # format is usually "frame value" e.g. "0 400"
                            parts = k.text.split()
                            if len(parts) >= 2:
                                val = float(parts[1])
                                if abs(val) >= min_z_diff:
                                    z_depth_found = True
                                    max_z = val
                        except:
                            pass

            # Check Camera Movement
            # Camera is usually pegbar id="Camera1" or similar
            for peg in pegbars:
                pid = peg.get("id", "")
                if "Camera" in pid:
                    # Check x or y movement
                    for axis in ['x', 'y']:
                        axis_elem = peg.find(axis)
                        if axis_elem is not None:
                            # Check if keyframes exist
                            kfs = axis_elem.findall(".//L")
                            if len(kfs) >= 2: # At least 2 keyframes imply movement
                                camera_moves = True
                            
                            # Or check if default is different from 0 (static offset, less likely for this task but possible)
                            
        except ET.ParseError:
            feedback_parts.append("Invalid .tnz XML structure")

    if z_depth_found:
        score += 40
        feedback_parts.append(f"Z-depth usage confirmed (Max Z: {max_z})")
    else:
        feedback_parts.append("No significant Z-depth usage found in scene file")

    if camera_moves:
        score += 30
        feedback_parts.append("Camera animation found")
    else:
        feedback_parts.append("No Camera keyframes found")

    # Final logic
    passed = (score >= 70) and z_depth_found and camera_moves

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }