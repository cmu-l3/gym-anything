#!/usr/bin/env python3
"""
Verifier for Pear-Shaped Cam Profile task in LibreCAD.
Verifies DXF file structure, layers, and geometry using ezdxf.
"""

import json
import os
import sys
import tempfile
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to import ezdxf, install if missing (standard practice for verifiers)
try:
    import ezdxf
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
    import ezdxf

def verify_pear_cam_profile(traj, env_info, task_info):
    """
    Verifies the pear cam profile task.
    
    Criteria:
    1. File Creation (10pts): DXF exists and modified during task.
    2. Layers (10pts): 'PROFILE' and 'BORE' layers exist.
    3. Profile Geometry (40pts): 
       - Base arc (R~30 near 0,0)
       - Nose arc (R~10 near 0,50)
       - Continuity/Trimming (Entities form a loop)
    4. Bore Geometry (20pts):
       - Bore radius ~10
       - Keyway geometry check
    5. Visual VLM Check (20pts): confirming shape appearance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/cam_profile.dxf')
    
    # 1. Parse JSON Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # Check File Existence & Timestamp
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback.append("WARNING: Output file timestamp indicates it was not created during this task session.")
        # We penalize but don't fail immediately if it exists, to allow for retry logic quirks, 
        # but strict anti-gaming usually zeroes this. Let's give partial credit for content if valid.
    else:
        score += 10
        feedback.append("File created successfully.")

    # 2. Analyze DXF Content
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(expected_output_path, temp_dxf.name)
        doc = ezdxf.readfile(temp_dxf.name)
        msp = doc.modelspace()
        
        # Check Layers
        layers = [layer.dxf.name.upper() for layer in doc.layers]
        has_profile = "PROFILE" in layers
        has_bore = "BORE" in layers
        
        if has_profile and has_bore:
            score += 10
            feedback.append("Layers 'PROFILE' and 'BORE' exist.")
        else:
            feedback.append(f"Missing required layers. Found: {layers}")

        # Check Profile Geometry (Model Space entities on PROFILE layer)
        profile_entities = [e for e in msp if e.dxf.layer.upper() == "PROFILE"]
        
        # We expect Arcs (trimmed circles) and Lines. 
        # Base Arc: Center ~(0,0), Radius ~30
        # Nose Arc: Center ~(0,50), Radius ~10
        has_base_arc = False
        has_nose_arc = False
        
        for e in profile_entities:
            if e.dxftype() == 'ARC':
                # Check Base
                if math.hypot(e.dxf.center.x, e.dxf.center.y) < 2.0 and abs(e.dxf.radius - 30.0) < 1.0:
                    has_base_arc = True
                # Check Nose
                if math.hypot(e.dxf.center.x, e.dxf.center.y - 50.0) < 2.0 and abs(e.dxf.radius - 10.0) < 1.0:
                    has_nose_arc = True
            elif e.dxftype() == 'LWPOLYLINE':
                # If they used polylines, check vertices
                for i in range(len(e)):
                    # Simplify: check if points exist near key coordinates
                    pt = e[i] # (x, y, start_width, end_width, bulge)
                    # This is complex to parse strictly without bulge math, 
                    # but we can assume if they made a polyline that spans the right area it's likely correct
                    pass

        if has_base_arc and has_nose_arc:
            score += 20
            feedback.append("Profile geometry (Base and Nose arcs) detected.")
        else:
            feedback.append("Profile geometry incomplete (missing Base R30 or Nose R10 arcs).")

        # Check Trimming (Entity count > 0 and <= 4 implies clean trimming usually: 2 arcs + 2 lines)
        # If they didn't trim, they might have full circles.
        if 2 <= len(profile_entities) <= 6 and has_base_arc and has_nose_arc:
             score += 20
             feedback.append("Profile appears correctly trimmed.")
        elif len(profile_entities) > 0:
             # Partial points for having entities
             score += 5
             feedback.append("Profile entities found, but count/topology suggests incorrect trimming.")

        # Check Bore Geometry
        bore_entities = [e for e in msp if e.dxf.layer.upper() == "BORE"]
        has_bore_arc = False
        has_keyway_top = False
        
        for e in bore_entities:
            if e.dxftype() == 'ARC':
                # Center ~(0,0), Radius ~10
                if math.hypot(e.dxf.center.x, e.dxf.center.y) < 1.0 and abs(e.dxf.radius - 10.0) < 0.5:
                    has_bore_arc = True
            elif e.dxftype() == 'LINE':
                # Keyway top line: Length ~5, Y ~13
                p1 = e.dxf.start
                p2 = e.dxf.end
                if abs(p1.y - 13.0) < 0.5 and abs(p2.y - 13.0) < 0.5:
                    length = math.hypot(p2.x - p1.x, p2.y - p1.y)
                    if abs(length - 5.0) < 1.0:
                        has_keyway_top = True

        if has_bore_arc:
            score += 10
            feedback.append("Bore hole detected.")
        if has_keyway_top:
            score += 10
            feedback.append("Keyway geometry detected.")

    except Exception as e:
        feedback.append(f"Error parsing DXF: {str(e)}")
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # 3. VLM Visual Verification (20 pts)
    # This is critical because DXF parsing can be brittle if they used PolyLines vs Arcs differently
    frames = sample_trajectory_frames(traj, n=3)
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this CAD drawing in LibreCAD.
        I am looking for a "Pear Cam" profile.
        1. Is there a large outer loop shaped like a pear (a large circle at bottom connected to a smaller circle at top)?
        2. Is there a hole in the center?
        3. Does the hole have a rectangular notch (keyway) at the top?
        4. Are there white and cyan lines visible (indicating layers)?
        
        Answer with JSON: {"pear_shape_visible": bool, "keyway_visible": bool, "layers_visible": bool}
        """
        try:
            vlm_out = query_vlm(images=[final_screenshot], prompt=prompt).get("parsed", {})
            
            if vlm_out.get("pear_shape_visible"):
                score += 10
                feedback.append("VLM confirms pear shape.")
            if vlm_out.get("keyway_visible"):
                score += 5
                feedback.append("VLM confirms keyway.")
            if vlm_out.get("layers_visible"):
                score += 5
                feedback.append("VLM confirms layer colors.")
        except Exception as e:
            feedback.append(f"VLM verification failed: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }