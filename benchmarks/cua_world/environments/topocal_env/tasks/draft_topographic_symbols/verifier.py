#!/usr/bin/env python3
"""
Verifier for the draft_topographic_symbols task in TopoCal.
Parses the agent-exported DXF to ensure accurate CAD drafting.
"""

import json
import os
import tempfile
import logging
import math
import sys
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def ensure_ezdxf():
    """Ensure the ezdxf library is available for DXF parsing."""
    try:
        import ezdxf
        return True
    except ImportError:
        try:
            logger.info("Installing ezdxf for DXF verification...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf", "--quiet"])
            return True
        except Exception as e:
            logger.error(f"Failed to install ezdxf: {e}")
            return False

def verify_draft_topographic_symbols(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the Task Metadata JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env(r"C:\Users\Docker\Documents\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basics and anti-gaming
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "DXF output file not found."}
    
    if not result_data.get('file_created_during_task', False):
        # File existed before the task and wasn't updated
        return {"passed": False, "score": 0, "feedback": "DXF file was not created or modified during the task session."}

    if not ensure_ezdxf():
        return {"passed": False, "score": 0, "feedback": "Verifier failed: Missing dependencies."}

    import ezdxf

    # 3. Retrieve and Parse the exported DXF
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(r"C:\Users\Docker\Documents\utility_symbols.dxf", temp_dxf.name)
        try:
            doc = ezdxf.readfile(temp_dxf.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse DXF: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # Score Initializer
    score = 10
    feedback_parts = ["Valid DXF exported"]
    msp = doc.modelspace()
    
    # 4. Check layer existence
    layers = [layer.dxf.name.upper() for layer in doc.layers]
    has_pole_layer = 'UTILITIES-POLE' in layers
    has_water_layer = 'UTILITIES-WATER' in layers
    
    if has_pole_layer and has_water_layer:
        score += 10
        feedback_parts.append("Both target layers created")
    elif has_pole_layer or has_water_layer:
        score += 5
        feedback_parts.append("Only one target layer created")
    else:
        feedback_parts.append("Target layers missing")

    # Target ground truth coordinates
    target_up = [(476515.80, 4399840.10), (476535.40, 4399845.30), (476555.20, 4399860.60), (476575.10, 4399865.20)]
    target_fh = [(476510.25, 4399820.50), (476550.90, 4399830.15), (476590.40, 4399840.80)]
    
    # 5. Evaluate Pole Circles
    pole_circles = [e for e in msp.query('CIRCLE') if e.dxf.layer.upper() == 'UTILITIES-POLE']
    if len(pole_circles) == 4:
        score += 15
        feedback_parts.append("Correct number of UP circles")
        
        matched_up = 0
        for pt in target_up:
            for c in pole_circles:
                cx, cy = c.dxf.center.x, c.dxf.center.y
                r = c.dxf.radius
                if math.isclose(cx, pt[0], abs_tol=0.05) and math.isclose(cy, pt[1], abs_tol=0.05) and math.isclose(r, 0.5, abs_tol=0.05):
                    matched_up += 1
                    break
        
        if matched_up == 4:
            score += 25
            feedback_parts.append("All UP circles perfectly matched (position & radius)")
        else:
            score += (matched_up * 6)
            feedback_parts.append(f"{matched_up}/4 UP circles matched correctly")
    else:
        feedback_parts.append(f"Found {len(pole_circles)} UP circles, expected 4")

    # 6. Evaluate Water Circles
    water_circles = [e for e in msp.query('CIRCLE') if e.dxf.layer.upper() == 'UTILITIES-WATER']
    if len(water_circles) == 3:
        score += 15
        feedback_parts.append("Correct number of FH circles")
        
        matched_fh = 0
        for pt in target_fh:
            for c in water_circles:
                cx, cy = c.dxf.center.x, c.dxf.center.y
                r = c.dxf.radius
                if math.isclose(cx, pt[0], abs_tol=0.05) and math.isclose(cy, pt[1], abs_tol=0.05) and math.isclose(r, 0.75, abs_tol=0.05):
                    matched_fh += 1
                    break
                    
        if matched_fh == 3:
            score += 25
            feedback_parts.append("All FH circles perfectly matched (position & radius)")
        else:
            score += (matched_fh * 8)
            feedback_parts.append(f"{matched_fh}/3 FH circles matched correctly")
    else:
        feedback_parts.append(f"Found {len(water_circles)} FH circles, expected 3")

    # Summary
    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }