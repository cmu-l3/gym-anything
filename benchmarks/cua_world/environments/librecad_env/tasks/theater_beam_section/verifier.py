#!/usr/bin/env python3
"""
Verifier for theater_beam_section task.
Uses ezdxf to validate geometric construction of lighting beam section.
"""

import json
import math
import os
import tempfile
import logging
from typing import Dict, Any, List, Tuple

# Try importing ezdxf, but handle failure gracefully if environment issue
try:
    import ezdxf
    from ezdxf.document import Drawing
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_angle(angle_deg):
    """Normalize angle to 0-360 range."""
    return angle_deg % 360

def verify_theater_beam_section(traj, env_info, task_info):
    """
    Verify the beam section drawing.
    
    Criteria:
    1. File creation/validity (10 pts)
    2. Layer structure (10 pts)
    3. Pipe geometry (Position & Radius) (20 pts)
    4. Beam geometry (Angles & Intercepts) (40 pts)
    5. Dimensioning (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function missing"}

    metadata = task_info.get('metadata', {})
    
    # Scoring breakdown
    score = 0
    feedback = []
    
    # 1. READ TASK RESULT JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "DXF file not found. Did you save it to the correct path?"}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during this task session."}

    score += 10
    feedback.append("File created successfully.")

    # 2. PARSE DXF FILE
    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": score, "feedback": "Verifier Error: ezdxf library missing."}

    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/LibreCAD/beam_study.dxf", temp_dxf.name)
        doc = ezdxf.readfile(temp_dxf.name)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Invalid DXF file: {str(e)}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # 3. CHECK LAYERS
    required_layers = ['ARCHITECTURE', 'RIGGING', 'LIGHTING', 'BEAM', 'DIMENSIONS']
    existing_layers = [layer.dxf.name.upper() for layer in doc.layers]
    missing_layers = [l for l in required_layers if l not in existing_layers]
    
    if not missing_layers:
        score += 10
        feedback.append("All required layers present.")
    else:
        # Partial credit for layers
        layer_score = int(10 * (len(required_layers) - len(missing_layers)) / len(required_layers))
        score += layer_score
        feedback.append(f"Missing layers: {', '.join(missing_layers)}")

    # 4. CHECK PIPE GEOMETRY (Circle at 2000, 5500)
    pipe_found = False
    pipe_correct = False
    
    circles = msp.query('CIRCLE')
    for circle in circles:
        center = circle.dxf.center
        radius = circle.dxf.radius
        # Check pos (2000, 5500) tolerance 5mm
        if (abs(center.x - 2000) < 5 and abs(center.y - 5500) < 5):
            pipe_found = True
            # Check radius 24mm tolerance 2mm
            if abs(radius - 24) < 2:
                pipe_correct = True
            break
            
    if pipe_correct:
        score += 20
        feedback.append("Pipe geometry correct.")
    elif pipe_found:
        score += 10
        feedback.append("Pipe position correct, but radius incorrect.")
    else:
        feedback.append("Pipe (circle at 2000,5500) not found.")

    # 5. CHECK BEAM GEOMETRY
    # We look for lines starting near (2000, 5500) on BEAM layer
    # Expected Angles: 333 (-27) and 297 (-63)
    beam_lines = []
    lines = msp.query('LINE')
    
    pipe_origin = (2000, 5500)
    
    valid_angles = []
    
    for line in lines:
        # Check layer
        if line.dxf.layer.upper() != 'BEAM':
            continue
            
        start = line.dxf.start
        end = line.dxf.end
        
        # Determine which end is near pipe
        vec = None
        if math.hypot(start.x - pipe_origin[0], start.y - pipe_origin[1]) < 50:
            vec = (end.x - start.x, end.y - start.y)
        elif math.hypot(end.x - pipe_origin[0], end.y - pipe_origin[1]) < 50:
            vec = (start.x - end.x, start.y - end.y)
            
        if vec:
            angle_rad = math.atan2(vec[1], vec[0])
            angle_deg = normalize_angle(math.degrees(angle_rad))
            valid_angles.append(angle_deg)
            
            # Check if line reaches floor (y=0)
            # Find y min of line
            min_y = min(start.y, end.y)
            if abs(min_y) < 50: # Tolerance for touching floor
                pass # Line reaches floor
    
    # Check for the two expected angles
    target_angles = [333, 297] # -27, -63
    matched_angles = 0
    
    for target in target_angles:
        found = False
        for angle in valid_angles:
            diff = abs(angle - target)
            if diff > 180: diff = 360 - diff
            if diff < 2.0: # 2 degree tolerance
                found = True
                break
        if found:
            matched_angles += 1
            
    if matched_angles == 2:
        score += 40
        feedback.append("Beam angles correct (approx 333° and 297°).")
    elif matched_angles == 1:
        score += 20
        feedback.append("One beam angle correct.")
    else:
        feedback.append(f"Beam angles incorrect. Found: {[round(a,1) for a in valid_angles]}. Expected: 333, 297.")

    # 6. CHECK DIMENSION
    # Look for a dimension entity with value ~7992
    dims = msp.query('DIMENSION')
    dim_found = False
    dim_val_correct = False
    
    expected_width = 7992
    
    for dim in dims:
        # ezdxf allows getting measurement, but sometimes it is dynamic
        # For linear dimensions, we can check measurement if available, 
        # or calculate from defpoints if not.
        try:
            val = dim.dxf.actual_measurement
            if val == 0: # If not set, try to calc distance between defpoints
                # This depends on dim type, simplified check:
                pass
            
            if abs(val - expected_width) < 100: # 100mm tolerance
                dim_found = True
                dim_val_correct = True
                break
        except:
            continue
            
    # Fallback: check text override or geometric defpoints
    if not dim_found and len(dims) > 0:
        dim_found = True # Found a dimension at least
        feedback.append("Dimension found but value could not be strictly verified.")
        
    if dim_val_correct:
        score += 20
        feedback.append(f"Dimension correct (approx {expected_width}mm).")
    elif dim_found:
        score += 10
        feedback.append("Dimension entity present.")
    else:
        feedback.append("No dimension entity found.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }