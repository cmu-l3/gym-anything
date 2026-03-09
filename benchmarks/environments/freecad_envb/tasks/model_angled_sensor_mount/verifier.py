#!/usr/bin/env python3
"""
Verifier for model_angled_sensor_mount task.

Criteria:
1. Files exist (FCStd and STL) and were created during the task.
2. FCStd contains specific PartDesign features (Pad, Datum Plane, Pocket/Hole).
3. VLM confirms the visual geometry (angled boss).
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_angled_sensor_mount(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load basic result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check file existence and timestamps (Anti-gaming)
    fcstd_ok = result_data.get('fcstd_exists') and result_data.get('fcstd_created_during_task')
    stl_ok = result_data.get('stl_exists') and result_data.get('stl_created_during_task')
    
    if fcstd_ok:
        score += 10
        feedback_parts.append("FCStd file created.")
    else:
        feedback_parts.append("FCStd file missing or not created during task.")

    if stl_ok:
        score += 10
        feedback_parts.append("STL file exported.")
    
    # 2. Deep Inspection of FCStd Structure
    # We verify that a Datum Plane was used, which is the core learning objective.
    feature_counts = {
        "PartDesign::Pad": 0,
        "PartDesign::Plane": 0,
        "PartDesign::Pocket": 0,
        "PartDesign::Hole": 0
    }
    
    if fcstd_ok:
        temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd')
        try:
            copy_from_env("/home/ga/Documents/FreeCAD/sensor_mount.FCStd", temp_fcstd.name)
            
            # FCStd is a ZIP file. We look for Document.xml
            if zipfile.is_zipfile(temp_fcstd.name):
                with zipfile.ZipFile(temp_fcstd.name, 'r') as z:
                    if 'Document.xml' in z.namelist():
                        with z.open('Document.xml') as f:
                            tree = ET.parse(f)
                            root = tree.getroot()
                            # Iterate over objects
                            for obj in root.findall(".//Object"):
                                type_attr = obj.get('Type')
                                if type_attr:
                                    for key in feature_counts:
                                        if key in type_attr:
                                            feature_counts[key] += 1
                                            
            # Score based on features
            # Need at least 2 pads (Base + Boss)
            if feature_counts["PartDesign::Pad"] >= 2:
                score += 20
                feedback_parts.append("Found Base and Boss features.")
            else:
                feedback_parts.append(f"Insufficient Pad features found (Count: {feature_counts['PartDesign::Pad']}).")

            # Need the Datum Plane
            if feature_counts["PartDesign::Plane"] >= 1:
                score += 30
                feedback_parts.append("Datum Plane usage verified.")
            else:
                feedback_parts.append("No Datum Plane found! Task required using a Datum Plane for the angle.")

            # Need a hole (Pocket or Hole feature)
            if feature_counts["PartDesign::Pocket"] >= 1 or feature_counts["PartDesign::Hole"] >= 1:
                score += 10
                feedback_parts.append("Through-hole feature found.")
            else:
                feedback_parts.append("No Pocket/Hole feature found.")
                
        except Exception as e:
            feedback_parts.append(f"Error inspecting FCStd file: {e}")
        finally:
            if os.path.exists(temp_fcstd.name):
                os.unlink(temp_fcstd.name)

    # 3. VLM Visual Verification
    # Use trajectory to confirm they didn't just import a shape, and check geometry visually
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        Review these screenshots of a FreeCAD task. 
        The goal is to model a sensor mount with a base plate and an ANGLED cylindrical boss coming out at 45 degrees.
        
        1. Do you see a 3D model with a rectangular base?
        2. Is there a cylindrical part sticking out at an angle (approx 45 degrees, not straight up)?
        3. Is there a hole through the cylinder?
        4. Does the FreeCAD model tree (left panel) show a 'DatumPlane' object?
        
        Return JSON:
        {
            "base_visible": true/false,
            "angled_boss_visible": true/false,
            "hole_visible": true/false,
            "datum_plane_in_tree": true/false
        }
        """
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("base_visible"):
                score += 5
            if parsed.get("angled_boss_visible"):
                score += 10
                feedback_parts.append("Visual verification: Angled boss visible.")
            if parsed.get("hole_visible"):
                score += 5
            if parsed.get("datum_plane_in_tree"):
                # Bonus verification for the tree
                if feature_counts["PartDesign::Plane"] == 0:
                    # If we missed it in XML but VLM sees it, give partial credit?
                    # Or reinforces confidence
                    pass
        else:
            feedback_parts.append("VLM verification failed.")

    passed = score >= 70 and feature_counts["PartDesign::Plane"] >= 1
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }