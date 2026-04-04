#!/usr/bin/env python3
"""
Verifier for bolt_circle_plate task in LibreCAD.
Verifies the geometry of the DXF file:
1. Plate outline (300x300 rect)
2. Central opening (r=75mm)
3. 8 Bolt holes (r=6mm) on 230mm bolt circle (r=115mm)
"""

import json
import os
import sys
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf, install if missing (standard pattern for verifiers)
try:
    import ezdxf
except ImportError:
    import subprocess
    logger.info("Installing ezdxf for verification...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
    import ezdxf

def verify_bolt_circle_plate(traj, env_info, task_info):
    """
    Verify the bolt circle plate drawing.
    """
    # 1. Setup and Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load task result JSON
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

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "DXF file was not saved to expected location."}

    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File timestamp predates task start (did you save?)."}
    
    score += 10 # File exists and is new
    feedback_parts.append("File saved successfully")

    # 3. Retrieve and Parse DXF File
    dxf_path = result.get('output_path')
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(dxf_path, temp_dxf.name)
        doc = ezdxf.readfile(temp_dxf.name)
        msp = doc.modelspace()
        score += 10 # File is valid DXF
        feedback_parts.append("Valid DXF format")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Invalid or corrupt DXF file: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # 4. Geometric Analysis
    
    # Collect all circles
    circles = []
    for entity in msp.query('CIRCLE'):
        circles.append({
            'center': (entity.dxf.center.x, entity.dxf.center.y),
            'radius': entity.dxf.radius
        })
    
    # A. Central Opening (Radius 75mm +/- 2mm, Center (0,0) +/- 3mm)
    central_hole = [c for c in circles if abs(c['radius'] - 75.0) <= 2.0]
    central_hole_valid = False
    
    if len(central_hole) == 1:
        cx, cy = central_hole[0]['center']
        dist = math.sqrt(cx**2 + cy**2)
        if dist <= 3.0:
            score += 15
            central_hole_valid = True
            feedback_parts.append("Central opening correct")
        else:
            feedback_parts.append(f"Central opening off-center by {dist:.1f}mm")
            score += 5
    elif len(central_hole) > 1:
        feedback_parts.append("Multiple central holes found")
    else:
        feedback_parts.append("Central opening missing (r=75mm)")

    # B. Bolt Holes (Radius 6mm +/- 1mm, 8 count)
    bolt_holes = [c for c in circles if abs(c['radius'] - 6.0) <= 1.0]
    
    if len(bolt_holes) == 8:
        score += 15
        feedback_parts.append("8 bolt holes found")
    elif len(bolt_holes) > 0:
        score += 5
        feedback_parts.append(f"Found {len(bolt_holes)} bolt holes (expected 8)")
    else:
        feedback_parts.append("No bolt holes found")

    # C. Bolt Circle Geometry
    bolt_circle_radius_ok = False
    angular_spacing_ok = False
    first_hole_ok = False
    
    if len(bolt_holes) >= 4:
        # Check radial distance (should be ~115mm)
        radial_dists = [math.sqrt(h['center'][0]**2 + h['center'][1]**2) for h in bolt_holes]
        avg_dist = sum(radial_dists) / len(radial_dists)
        if abs(avg_dist - 115.0) <= 3.0:
            score += 15
            bolt_circle_radius_ok = True
            feedback_parts.append("Bolt circle radius correct")
        else:
            feedback_parts.append(f"Bolt circle wrong radius (avg {avg_dist:.1f}mm)")

        # Check angular spacing
        angles = sorted([math.degrees(math.atan2(h['center'][1], h['center'][0])) % 360 for h in bolt_holes])
        spacings = []
        for i in range(len(angles)):
            diff = (angles[(i+1)%len(angles)] - angles[i]) % 360
            spacings.append(diff)
        
        # Expected spacing is 360/count (45 deg for 8 holes)
        expected_spacing = 360.0 / len(bolt_holes)
        if all(abs(s - expected_spacing) <= 3.0 for s in spacings):
            score += 15
            angular_spacing_ok = True
            feedback_parts.append("Hole spacing correct")
        else:
            feedback_parts.append("Hole spacing uneven")

        # Check for hole at 0 degrees (115, 0)
        # We look for a hole within 5 degrees of 0
        if any(a < 5 or a > 355 for a in angles):
            score += 5
            first_hole_ok = True
            feedback_parts.append("0-degree hole present")

    # D. Plate Outline (Rect 300x300)
    # Search in LINE and LWPOLYLINE entities
    bbox_valid = False
    
    # Calculate bounding box of all lines/polylines
    min_x, min_y, max_x, max_y = float('inf'), float('inf'), float('-inf'), float('-inf')
    has_lines = False
    
    # Check Lines
    for line in msp.query('LINE'):
        has_lines = True
        for pt in [line.dxf.start, line.dxf.end]:
            min_x = min(min_x, pt.x)
            min_y = min(min_y, pt.y)
            max_x = max(max_x, pt.x)
            max_y = max(max_y, pt.y)

    # Check Polylines
    for poly in msp.query('LWPOLYLINE'):
        has_lines = True
        # LWPolylines points are in object coordinates (usually WCS for 2D)
        with poly.points() as points:
            for pt in points:
                min_x = min(min_x, pt[0])
                min_y = min(min_y, pt[1])
                max_x = max(max_x, pt[0])
                max_y = max(max_y, pt[1])

    if has_lines:
        width = max_x - min_x
        height = max_y - min_y
        center_x = (max_x + min_x) / 2
        center_y = (max_y + min_y) / 2
        
        # Expect 300x300 centered at 0,0
        if abs(width - 300.0) <= 5.0 and abs(height - 300.0) <= 5.0:
            if abs(center_x) <= 5.0 and abs(center_y) <= 5.0:
                score += 15
                bbox_valid = True
                feedback_parts.append("Plate outline correct")
            else:
                score += 5
                feedback_parts.append("Plate size correct but off-center")
        else:
            if width > 0:
                feedback_parts.append(f"Plate bounds incorrect ({width:.1f}x{height:.1f}mm)")

    # 5. Final Pass/Fail Logic
    passed = (
        central_hole_valid and 
        (len(bolt_holes) == 8) and 
        bolt_circle_radius_ok and 
        bbox_valid
    )
    
    # Bonus check: If score is high but boolean failed (e.g. 7 holes), fail.
    # If boolean passed, ensure score is at least 70.
    if passed and score < 70:
        score = 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }