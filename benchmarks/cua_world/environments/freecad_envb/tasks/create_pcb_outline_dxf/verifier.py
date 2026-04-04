#!/usr/bin/env python3
"""
Verifier for create_pcb_outline_dxf task.

Checks:
1. Files exist (FCStd and DXF) and were created during the task.
2. DXF content is parsed to verify:
   - Board outline: 80x60mm rectangle.
   - Mounting holes: 4 circles, 3.2mm diameter, correct positions.
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

def install_ezdxf():
    """Install ezdxf if not present."""
    try:
        import ezdxf
        return True
    except ImportError:
        logger.info("Installing ezdxf...")
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
            return True
        except Exception as e:
            logger.error(f"Failed to install ezdxf: {e}")
            return False

def dist(p1, p2):
    """Euclidean distance between two points."""
    return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

def verify_create_pcb_outline_dxf(traj, env_info, task_info):
    # 1. Setup Environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Install dependencies
    if not install_ezdxf():
        return {"passed": False, "score": 0, "feedback": "System error: Failed to install verification library (ezdxf)"}
    
    import ezdxf

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('board_width', 80.0)
    expected_height = metadata.get('board_height', 60.0)
    expected_hole_radius = metadata.get('hole_radius', 1.6)
    expected_holes = metadata.get('hole_positions', [[4,4], [76,4], [76,56], [4,56]])
    pos_tolerance = metadata.get('tolerance_mm', 0.5)
    rad_tolerance = metadata.get('radius_tolerance_mm', 0.1)

    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 3. Verify File Existence & Anti-Gaming
    dxf_status = result_data.get('dxf_file', {})
    project_status = result_data.get('project_file', {})

    if project_status.get('exists') and project_status.get('created_during_task'):
        score += 10
        feedback.append("FreeCAD project file created.")
    
    if not dxf_status.get('exists'):
        return {"passed": False, "score": score, "feedback": "DXF file not found. " + " ".join(feedback)}
    
    if not dxf_status.get('created_during_task'):
        return {"passed": False, "score": score, "feedback": "DXF file exists but was not created during the task (anti-gaming)."}

    score += 10 # DXF exists
    feedback.append("DXF file created.")

    # 4. Parse DXF Content
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/FreeCAD/pcb_outline.dxf", temp_dxf.name)
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid DXF file: {str(e)}"}
        
        # Analyze Entities
        circles = []
        lines = []
        polylines = []

        for e in msp:
            if e.dxftype() == 'CIRCLE':
                circles.append(e)
            elif e.dxftype() == 'LINE':
                lines.append(e)
            elif e.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
                polylines.append(e)

        # Check Board Outline (Rectangle 80x60 at 0,0)
        # It could be 4 lines or a polyline
        outline_found = False
        
        # Check Polylines
        for poly in polylines:
            # Simplify check: bounding box
            if not outline_found:
                pts = list(poly.points())
                # Handle different polyline formats, just extract xy
                pts_xy = [(p[0], p[1]) for p in pts]
                if not pts_xy: continue
                
                xs = [p[0] for p in pts_xy]
                ys = [p[1] for p in pts_xy]
                w = max(xs) - min(xs)
                h = max(ys) - min(ys)
                
                if abs(w - expected_width) < 1.0 and abs(h - expected_height) < 1.0:
                    # Check origin (optional but good)
                    if abs(min(xs) - 0) < 1.0 and abs(min(ys) - 0) < 1.0:
                        outline_found = True
        
        # Check Lines if polyline not found
        if not outline_found and len(lines) >= 4:
            # Gather endpoints
            points = []
            for l in lines:
                points.append(l.dxf.start)
                points.append(l.dxf.end)
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            if xs and ys:
                w = max(xs) - min(xs)
                h = max(ys) - min(ys)
                if abs(w - expected_width) < 1.0 and abs(h - expected_height) < 1.0:
                     if abs(min(xs) - 0) < 1.0 and abs(min(ys) - 0) < 1.0:
                        outline_found = True

        if outline_found:
            score += 25
            feedback.append("Board outline (80x60mm) verified.")
        else:
            feedback.append("Board outline dimensions incorrect or not found.")

        # Check Mounting Holes
        found_holes = 0
        correct_diameter_holes = 0
        
        # Create a list of found circle centers and radii
        found_circles = []
        for c in circles:
            found_circles.append({
                'center': (c.dxf.center.x, c.dxf.center.y),
                'radius': c.dxf.radius
            })

        # Match against expected holes
        for expected_pos in expected_holes:
            match = False
            for fc in found_circles:
                # Check position
                if dist(expected_pos, fc['center']) < pos_tolerance:
                    match = True
                    # Check radius
                    if abs(fc['radius'] - expected_hole_radius) < rad_tolerance:
                        correct_diameter_holes += 1
                    break
            if match:
                found_holes += 1

        # Scoring for holes
        # 10 points per correct position (max 40)
        score += found_holes * 10
        if found_holes > 0:
            feedback.append(f"Found {found_holes}/4 mounting holes at correct positions.")
        else:
            feedback.append("No mounting holes found at expected positions.")

        # 10 points bonus if ALL detected holes have correct diameter
        if found_holes == 4 and correct_diameter_holes == 4:
            score += 15
            feedback.append("All holes have correct diameter (3.2mm).")
        elif correct_diameter_holes > 0:
            score += int(correct_diameter_holes * 2.5) # Partial credit
            feedback.append(f"{correct_diameter_holes} holes have correct diameter.")

    except Exception as e:
        feedback.append(f"Error parsing DXF: {str(e)}")
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    passed = (score >= 60) and outline_found and (found_holes >= 2)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }