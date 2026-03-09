#!/usr/bin/env python3
"""
Verifier for four_bar_linkage_study task in LibreCAD.
Verifies geometric accuracy of a Crank-Rocker mechanism.
"""

import json
import os
import math
import sys
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing ezdxf (should be installed in environment)
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False
    logger.warning("ezdxf module not found. Geometric verification will be limited.")

def calculate_intersection_circle_circle(x1, y1, r1, x2, y2, r2):
    """
    Calculate intersection points of two circles.
    Returns list of (x, y) tuples.
    """
    d = math.sqrt((x1 - x2)**2 + (y1 - y2)**2)
    
    if d > r1 + r2 or d < abs(r1 - r2) or d == 0:
        return []  # No intersection or concentric
    
    a = (r1**2 - r2**2 + d**2) / (2 * d)
    h = math.sqrt(max(0, r1**2 - a**2))
    
    x2_prime = x1 + a * (x2 - x1) / d
    y2_prime = y1 + a * (y2 - y1) / d
    
    x3_1 = x2_prime + h * (y2 - y1) / d
    y3_1 = y2_prime - h * (x2 - x1) / d
    
    x3_2 = x2_prime - h * (y2 - y1) / d
    y3_2 = y2_prime + h * (x2 - x1) / d
    
    return [(x3_1, y3_1), (x3_2, y3_2)]

def verify_four_bar_linkage_study(traj, env_info, task_info):
    """
    Verifies the four-bar linkage drawing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function unavailable"}

    # =========================================================
    # 1. Retrieve Task Result Metadata
    # =========================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task session (anti-gaming check)."}

    # =========================================================
    # 2. Retrieve and Parse DXF File
    # =========================================================
    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": 0, "feedback": "Verification environment missing 'ezdxf' library."}

    temp_dxf_file = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/LibreCAD/linkage_study.dxf", temp_dxf_file.name)
        doc = ezdxf.readfile(temp_dxf_file.name)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": 5, "feedback": f"Failed to parse DXF file: {str(e)}"}
    finally:
        if os.path.exists(temp_dxf_file.name):
            os.unlink(temp_dxf_file.name)

    # =========================================================
    # 3. Geometric Ground Truth Calculation
    # =========================================================
    # Constants from task description
    A = (0.0, 0.0)
    D = (200.0, 0.0)
    crank_len = 60.0
    crank_angle_deg = 60.0
    coupler_len = 250.0
    rocker_len = 150.0
    
    # Calculate B (Crank end)
    bx = crank_len * math.cos(math.radians(crank_angle_deg))
    by = crank_len * math.sin(math.radians(crank_angle_deg))
    B = (bx, by)
    
    # Calculate C (Intersection of Coupler radius from B and Rocker radius from D)
    intersections = calculate_intersection_circle_circle(bx, by, coupler_len, D[0], D[1], rocker_len)
    
    # We expect the upper intersection (y > 0) usually for this mechanism configuration
    # but we will accept either valid geometric solution.
    valid_Cs = intersections
    if not valid_Cs:
        return {"passed": False, "score": 0, "feedback": "Internal error: Impossible mechanism geometry."}

    logger.info(f"Target Geometry: A={A}, D={D}, B={B}, Valid Cs={valid_Cs}")

    # =========================================================
    # 4. Verification Logic
    # =========================================================
    score = 0
    feedback = []
    
    # 4.1 Layer Checks (10 pts)
    layers = [layer.dxf.name.upper() for layer in doc.layers]
    required_layers = ["MECHANISM", "CONSTRUCTION", "DIMENSIONS"]
    layers_found = [l for l in required_layers if l in layers]
    
    if len(layers_found) == 3:
        score += 10
        feedback.append("All required layers found.")
    else:
        score += 3 * len(layers_found)
        feedback.append(f"Missing layers. Found: {layers_found}")

    # 4.2 Entity Extraction
    lines_mech = []
    circles_const = []
    dimensions = []

    for e in msp:
        layer_name = e.dxf.layer.upper()
        if e.dxftype() == 'LINE' and layer_name == 'MECHANISM':
            lines_mech.append(((e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y)))
        elif e.dxftype() == 'CIRCLE' and layer_name == 'CONSTRUCTION':
            circles_const.append({'center': (e.dxf.center.x, e.dxf.center.y), 'radius': e.dxf.radius})
        elif 'DIMENSION' in e.dxftype() and layer_name == 'DIMENSIONS':
            dimensions.append(e)

    # 4.3 Verify Mechanism Links (60 pts total)
    
    def distance(p1, p2):
        return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

    def points_match(p1, p2, tol=1.0):
        return distance(p1, p2) < tol

    def line_matches(line, start_target, end_target, tol=1.0):
        l_start, l_end = line
        return (points_match(l_start, start_target, tol) and points_match(l_end, end_target, tol)) or \
               (points_match(l_start, end_target, tol) and points_match(l_end, start_target, tol))

    # Check Ground (10 pts)
    if any(line_matches(l, A, D) for l in lines_mech):
        score += 10
        feedback.append("Ground link correct.")
    else:
        feedback.append("Ground link missing or incorrect.")

    # Check Crank (20 pts)
    if any(line_matches(l, A, B) for l in lines_mech):
        score += 20
        feedback.append("Crank link correct.")
    else:
        feedback.append(f"Crank link incorrect. Expected endpoint near ({B[0]:.1f}, {B[1]:.1f}).")

    # Check Coupler and Rocker connectivity (30 pts)
    # We check if there exists a point C in the drawing that matches one of our valid Cs
    # and connects to B and D.
    
    c_found = False
    for target_C in valid_Cs:
        # Look for Coupler (B-C)
        has_coupler = any(line_matches(l, B, target_C) for l in lines_mech)
        # Look for Rocker (C-D)
        has_rocker = any(line_matches(l, target_C, D) for l in lines_mech)
        
        if has_coupler and has_rocker:
            c_found = True
            break
    
    if c_found:
        score += 30
        feedback.append("Coupler and Rocker links positioned correctly.")
    else:
        # Partial credit if lines exist but strictly incorrect geometry
        feedback.append("Coupler/Rocker geometry incorrect or not fully connected.")

    # 4.4 Construction Geometry (15 pts)
    # Expect circles centered at B (r=250) and D (r=150)
    has_circle_b = False
    has_circle_d = False
    
    for c in circles_const:
        if points_match(c['center'], B, tol=2.0) and abs(c['radius'] - 250) < 2.0:
            has_circle_b = True
        if points_match(c['center'], D, tol=2.0) and abs(c['radius'] - 150) < 2.0:
            has_circle_d = True
            
    if has_circle_b and has_circle_d:
        score += 15
        feedback.append("Construction circles correctly drawn.")
    elif has_circle_b or has_circle_d:
        score += 7
        feedback.append("One construction circle found.")
    else:
        feedback.append("Missing construction circles on CONSTRUCTION layer.")

    # 4.5 Dimensions (15 pts)
    if len(dimensions) > 0:
        score += 15
        feedback.append("Dimension entity found.")
    else:
        feedback.append("No dimensions found on DIMENSIONS layer.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }