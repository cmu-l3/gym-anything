#!/usr/bin/env python3
"""
Verifier for custom_macropad_plate task.
Checks DXF geometry for switch cutouts, plate outline, and mounting holes.
"""

import json
import os
import sys
import math
import tempfile
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing ezdxf (installed in environment)
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False


def verify_macropad_plate(traj, env_info, task_info):
    """
    Verify the DXF file for the macropad plate.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}
    
    if not task_result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during the task."}

    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": 0, "feedback": "Verifier Error: ezdxf library not available for checking."}

    # Fetch DXF file
    dxf_local_path = tempfile.mktemp(suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/LibreCAD/macropad_plate.dxf", dxf_local_path)
        doc = ezdxf.readfile(dxf_local_path)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse DXF file: {e}"}

    # Task Parameters
    meta = task_info.get('metadata', {})
    SWITCH_SIZE = meta.get('switch_size', 14.0)
    PITCH = meta.get('switch_pitch', 19.05)
    ROWS = meta.get('grid_rows', 2)
    COLS = meta.get('grid_cols', 3)
    START_X, START_Y = meta.get('top_left_center', [40, 80])
    MARGIN = meta.get('margin', 6.0)
    HOLE_DIA = meta.get('hole_diameter', 3.2)
    
    score = 10
    feedback = []
    
    # ---------------------------------------------------------
    # 1. LAYER CHECK
    # ---------------------------------------------------------
    layers = [layer.dxf.name for layer in doc.layers]
    required_layers = ['SWITCH_CUTS', 'PLATE_OUTLINE', 'MOUNTING_HOLES']
    missing_layers = [l for l in required_layers if l not in layers]
    
    if not missing_layers:
        score += 15
        feedback.append("Layer structure correct.")
    else:
        feedback.append(f"Missing layers: {', '.join(missing_layers)}")

    # ---------------------------------------------------------
    # 2. SWITCH CUTOUTS CHECK
    # ---------------------------------------------------------
    # Expected centers
    expected_centers = []
    for r in range(ROWS):
        for c in range(COLS):
            cx = START_X + (c * PITCH)
            cy = START_Y - (r * PITCH) # Going down in Y
            expected_centers.append((cx, cy))

    switches_found = 0
    switch_pos_correct = 0
    
    # Get entities on SWITCH_CUTS
    switch_entities = msp.query(f'*[layer=="SWITCH_CUTS"]')
    
    # Helper to get centroid of a closed polyline/lwpolyline
    def get_bbox_center(entity):
        try:
            if entity.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
                pts = list(entity.vertices())
                if not pts: return None
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                return (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            # Handle rectangles drawn as lines? (Complex, sticking to polylines/rectangles preferred)
            return None
        except:
            return None

    # Filter for roughly 14x14 boxes
    valid_switches = []
    for e in switch_entities:
        if e.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
            # approximate area check or bbox check
            try:
                pts = list(e.vertices())
                if len(pts) >= 4:
                    xs = [p[0] for p in pts]
                    ys = [p[1] for p in pts]
                    w = max(xs) - min(xs)
                    h = max(ys) - min(ys)
                    if 13.5 < w < 14.5 and 13.5 < h < 14.5:
                        valid_switches.append(e)
            except:
                pass

    if len(valid_switches) == 6:
        score += 15
        feedback.append("Found exactly 6 switch cutouts.")
        
        # Check positions
        matched_centers = 0
        for center in expected_centers:
            # Find a switch near this center
            found = False
            for s in valid_switches:
                c = get_bbox_center(s)
                if c and math.hypot(c[0]-center[0], c[1]-center[1]) < 0.5:
                    found = True
                    break
            if found:
                matched_centers += 1
        
        if matched_centers == 6:
            score += 20
            feedback.append("Switch positions correct.")
        else:
            feedback.append(f"Only {matched_centers}/6 switches at correct coordinates.")
            score += int((matched_centers/6) * 20)
    else:
        feedback.append(f"Found {len(valid_switches)} valid switch cutouts (expected 6).")

    # ---------------------------------------------------------
    # 3. PLATE OUTLINE CHECK
    # ---------------------------------------------------------
    # Calculate bounds
    # Switch half-size = 7
    min_x_switch = START_X - 7
    max_x_switch = START_X + ((COLS-1) * PITCH) + 7
    max_y_switch = START_Y + 7
    min_y_switch = START_Y - ((ROWS-1) * PITCH) - 7
    
    expected_bounds = {
        'min_x': min_x_switch - MARGIN,  # 27.0
        'max_x': max_x_switch + MARGIN,  # 91.1
        'min_y': min_y_switch - MARGIN,  # 47.95
        'max_y': max_y_switch + MARGIN   # 93.0
    }
    
    outline_entities = msp.query(f'*[layer=="PLATE_OUTLINE"]')
    outline_ok = False
    fillets_ok = False
    
    for e in outline_entities:
        if e.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
            try:
                pts = list(e.vertices())
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                
                # Check bounds (allow small tolerance)
                if (abs(min(xs) - expected_bounds['min_x']) < 1.0 and
                    abs(max(xs) - expected_bounds['max_x']) < 1.0 and
                    abs(min(ys) - expected_bounds['min_y']) < 1.0 and
                    abs(max(ys) - expected_bounds['max_y']) < 1.0):
                    outline_ok = True
                    
                    # Check for fillets (LWPolyline bulge != 0)
                    if e.dxftype() == 'LWPOLYLINE':
                        # Check if any segment has bulge
                        has_bulge = any(p[4] != 0 for p in e.get_points(format='xyseb') if len(p) >= 5)
                        if has_bulge:
                            fillets_ok = True
                    break
            except:
                pass

    if outline_ok:
        score += 15
        feedback.append("Plate outline dimensions correct.")
        if fillets_ok:
            score += 5
            feedback.append("Corner fillets detected.")
        else:
            feedback.append("Corner fillets missing or not detected.")
    else:
        feedback.append("Plate outline dimensions incorrect.")

    # ---------------------------------------------------------
    # 4. MOUNTING HOLES CHECK
    # ---------------------------------------------------------
    # Calculate hole positions
    offset = meta.get('hole_offset', 3.5)
    # Corners of the bounding box
    corners = [
        (expected_bounds['min_x'], expected_bounds['max_y']), # Top-Left
        (expected_bounds['max_x'], expected_bounds['max_y']), # Top-Right
        (expected_bounds['min_x'], expected_bounds['min_y']), # Bottom-Left
        (expected_bounds['max_x'], expected_bounds['min_y'])  # Bottom-Right
    ]
    
    # Inset corners
    hole_targets = [
        (corners[0][0] + offset, corners[0][1] - offset),
        (corners[1][0] - offset, corners[1][1] - offset),
        (corners[2][0] + offset, corners[2][1] + offset),
        (corners[3][0] - offset, corners[3][1] + offset)
    ]
    
    hole_entities = msp.query(f'CIRCLE[layer=="MOUNTING_HOLES"]')
    valid_holes = 0
    holes_positioned = 0
    
    radius = HOLE_DIA / 2
    
    found_holes = []
    for h in hole_entities:
        if abs(h.dxf.radius - radius) < 0.1:
            valid_holes += 1
            loc = h.dxf.center
            found_holes.append((loc.x, loc.y))
            
    if valid_holes == 4:
        score += 10
        feedback.append("Found 4 mounting holes of correct size.")
        
        # Check positions
        matched_holes = 0
        for target in hole_targets:
            for found in found_holes:
                if math.hypot(found[0]-target[0], found[1]-target[1]) < 0.5:
                    matched_holes += 1
                    break
        
        if matched_holes == 4:
            score += 10
            feedback.append("Mounting hole positions correct.")
        else:
            feedback.append(f"Only {matched_holes}/4 mounting holes at correct coordinates.")
            score += int((matched_holes/4) * 10)
    else:
        feedback.append(f"Found {valid_holes} valid mounting holes (expected 4).")

    # Cleanup
    if os.path.exists(dxf_local_path):
        os.unlink(dxf_local_path)

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }