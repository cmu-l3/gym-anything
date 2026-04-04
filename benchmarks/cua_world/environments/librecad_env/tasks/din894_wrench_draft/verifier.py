#!/usr/bin/env python3
"""
Verifier for DIN 894 Wrench Construction Task.
Validates geometric precision using ezdxf.
"""

import json
import os
import sys
import tempfile
import math
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_din894_wrench(traj, env_info, task_info):
    """
    Verifies the DIN 894 wrench construction.
    Checks:
    1. DXF file existence and validity.
    2. Layer structure (PROFILE, CENTERS).
    3. Circle geometry (Head R=26, Tail R=13).
    4. Tangency of connecting lines (Mathematically precise).
    5. Jaw opening geometry.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check file existence and creation
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file din894_wrench.dxf not found."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

    # Load the DXF file
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/LibreCAD/din894_wrench.dxf", temp_dxf.name)
        
        # Import ezdxf here to ensure availability
        try:
            import ezdxf
        except ImportError:
            # Fallback if ezdxf is missing in verifier environment (should be installed)
            return {"passed": False, "score": 0, "feedback": "Verifier Error: ezdxf library not found."}

        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"Invalid DXF file: {e}"}

        # --- SCORING CRITERIA ---
        score = 10
        feedback = ["File valid."]
        
        # 1. Layer Check (10 pts)
        layers = [layer.dxf.name.upper() for layer in doc.layers]
        has_profile = "PROFILE" in layers
        has_centers = "CENTERS" in layers
        
        if has_profile and has_centers:
            score += 10
            feedback.append("Layers correct.")
        else:
            feedback.append(f"Missing layers. Found: {layers}")

        # 2. Geometry Extraction
        circles = []
        lines = []
        
        for entity in msp:
            if entity.dxftype() == 'CIRCLE':
                # Store (center_x, center_y, radius, layer)
                circles.append({
                    'center': entity.dxf.center,
                    'radius': entity.dxf.radius,
                    'layer': entity.dxf.layer.upper()
                })
            elif entity.dxftype() == 'LINE':
                # Store (start, end, layer)
                lines.append({
                    'start': entity.dxf.start,
                    'end': entity.dxf.end,
                    'layer': entity.dxf.layer.upper()
                })

        # 3. Circle Geometry Check (40 pts total)
        # Head: (0,0) R=26
        # Tail: (215,0) R=13
        head_found = False
        tail_found = False
        
        for c in circles:
            cx, cy = c['center'][:2]
            r = c['radius']
            
            # Check Head
            if math.isclose(cx, 0, abs_tol=1) and math.isclose(cy, 0, abs_tol=1) and math.isclose(r, 26, abs_tol=0.5):
                head_found = True
            
            # Check Tail
            if math.isclose(cx, 215, abs_tol=1) and math.isclose(cy, 0, abs_tol=1) and math.isclose(r, 13, abs_tol=0.5):
                tail_found = True

        if head_found:
            score += 20
            feedback.append("Head circle correct.")
        else:
            feedback.append("Head circle (R=26 at 0,0) not found.")

        if tail_found:
            score += 20
            feedback.append("Tail circle correct.")
        else:
            feedback.append("Tail circle (R=13 at 215,0) not found.")

        # 4. Tangency Check (30 pts)
        # We need two lines on PROFILE layer that connect the general areas of the two circles
        # and are tangent.
        # Tangency test: Distance from (0,0) to line ~= 26 AND Distance from (215,0) to line ~= 13
        
        tangent_lines_found = 0
        
        def point_line_distance(px, py, line_start, line_end):
            # Calculate distance from point (px,py) to line segment defined by start/end
            # Standard formula: |Ax + By + C| / sqrt(A^2 + B^2)
            x1, y1 = line_start[:2]
            x2, y2 = line_end[:2]
            
            # Line equation coefficients A, B, C
            A = y1 - y2
            B = x2 - x1
            C = x1*y2 - x2*y1
            
            denom = math.sqrt(A*A + B*B)
            if denom == 0: return float('inf')
            
            return abs(A*px + B*py + C) / denom

        for line in lines:
            if line['layer'] != 'PROFILE': continue
            
            # Filter lines that are roughly horizontal and long enough (>150mm)
            length = math.hypot(line['end'][0] - line['start'][0], line['end'][1] - line['start'][1])
            if length < 150: continue

            # Check distances to centers
            d_head = point_line_distance(0, 0, line['start'], line['end'])
            d_tail = point_line_distance(215, 0, line['start'], line['end'])
            
            # Tolerance 0.2mm for tangency
            is_tangent_head = math.isclose(d_head, 26, abs_tol=0.2)
            is_tangent_tail = math.isclose(d_tail, 13, abs_tol=0.2)
            
            if is_tangent_head and is_tangent_tail:
                tangent_lines_found += 1

        if tangent_lines_found >= 2:
            score += 30
            feedback.append(f"Tangent lines verified ({tangent_lines_found} found).")
        elif tangent_lines_found == 1:
            score += 15
            feedback.append("Only one tangent line found.")
        else:
            feedback.append("Tangency check failed. Lines are not precisely tangent.")

        # 5. Jaw Check (10 pts)
        # Look for horizontal lines at y=12 and y=-12 starting near x=0
        jaw_top = False
        jaw_bottom = False
        
        for line in lines:
            if line['layer'] != 'PROFILE': continue
            y1 = line['start'][1]
            y2 = line['end'][1]
            
            # Horizontal check
            if math.isclose(y1, y2, abs_tol=0.1):
                if math.isclose(y1, 12, abs_tol=0.5): jaw_top = True
                if math.isclose(y1, -12, abs_tol=0.5): jaw_bottom = True

        if jaw_top and jaw_bottom:
            score += 10
            feedback.append("Jaw opening lines correct.")
        
        # 6. Centerline Check (10 pts)
        centerline_found = False
        for line in lines:
            if line['layer'] == 'CENTERS':
                # Roughly horizontal near y=0
                if math.isclose(line['start'][1], 0, abs_tol=0.5) and math.isclose(line['end'][1], 0, abs_tol=0.5):
                    centerline_found = True
                    break
        
        if centerline_found:
            score += 10
            feedback.append("Centerline found.")

        final_passed = score >= 70 and head_found and tail_found and (tangent_lines_found >= 1)

        return {
            "passed": final_passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed with exception: {str(e)}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)