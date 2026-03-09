#!/usr/bin/env python3
"""
Verifier for Isometric Fire Sprinkler Riser task.
Checks DXF geometry for specific isometric angles and lengths using ezdxf.
"""

import json
import os
import math
import tempfile
import logging
import sys

# Ensure ezdxf is available (it is installed in the env)
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_angle_length(start, end):
    """Calculate angle (0-360) and length of a line segment."""
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    length = math.hypot(dx, dy)
    angle_rad = math.atan2(dy, dx)
    angle_deg = math.degrees(angle_rad)
    if angle_deg < 0:
        angle_deg += 360
    return angle_deg, length

def is_close(val, target, tolerance):
    """Check if value is within tolerance of target."""
    return abs(val - target) <= tolerance

def normalize_angle_diff(a, b):
    """Calculate smallest difference between two angles."""
    diff = abs(a - b) % 360
    return min(diff, 360 - diff)

def verify_isometric_fire_riser(traj, env_info, task_info):
    """
    Verify the isometric drawing based on DXF geometry.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": 0, "feedback": "Verification failed: ezdxf library missing"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/fire_riser_iso.dxf')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check File Existence & Creation (10 pts)
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file was not created"}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during this task"}
    
    score += 10
    feedback_parts.append("DXF file created")

    # 3. Download and Parse DXF
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(expected_path, temp_dxf.name)
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            feedback_parts.append("DXF file valid")
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid DXF file: {e}"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve DXF file: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # 4. Analyze Layers (10 pts)
    # Expected layers: PIPE_CENTERLINE (Red/1), FITTINGS (Cyan/4), TEXT (White/7)
    layers_found = []
    for layer in doc.layers:
        layers_found.append(layer.dxf.name)
    
    required_layers = metadata.get('layer_specs', {})
    layers_score = 0
    for name, color in required_layers.items():
        if name in layers_found:
            # Check color if possible, but presence is primary
            layer_def = doc.layers.get(name)
            if layer_def.dxf.color == color:
                layers_score += 3.33
            else:
                layers_score += 1.5 # Layer exists but wrong color
    
    score += min(10, int(layers_score))
    if int(layers_score) >= 10:
        feedback_parts.append("Layers correct")
    else:
        feedback_parts.append("Layer setup incomplete")

    # 5. Analyze Pipe Geometry (50 pts total)
    # Strategy: Gather all lines on PIPE_CENTERLINE layer and check if required segments exist.
    # We don't demand perfect connectivity in data structure, just that visual lines exist.
    
    lines_on_layer = msp.query('LINE[layer=="PIPE_CENTERLINE"]')
    vectors = []
    for line in lines_on_layer:
        angle, length = calculate_angle_length(line.dxf.start, line.dxf.end)
        vectors.append({'angle': angle, 'length': length})
    
    geo_specs = metadata.get('geometry_specs', [])
    geo_found = [False] * len(geo_specs)
    
    # For each required spec, look for a matching line
    for i, spec in enumerate(geo_specs):
        for v in vectors:
            # Check angle (bidirectional check: 90 is same line as 270 physically, 
            # but task implies drawing direction. We'll be lenient and allow 180 flips)
            angle_diff = normalize_angle_diff(v['angle'], spec['angle'])
            angle_diff_flip = normalize_angle_diff(v['angle'], (spec['angle'] + 180) % 360)
            
            is_angle_match = (angle_diff <= spec['tolerance_angle']) or (angle_diff_flip <= spec['tolerance_angle'])
            is_len_match = is_close(v['length'], spec['length'], spec['tolerance_len'])
            
            if is_angle_match and is_len_match:
                geo_found[i] = True
                break
    
    # Score geometry
    # 4 segments, 12.5 pts each
    geo_score = 0
    if geo_found[0]: geo_score += 12.5 # Vertical UP
    if geo_found[1]: geo_score += 12.5 # Iso Left
    if geo_found[2]: geo_score += 12.5 # Iso Right
    if geo_found[3]: geo_score += 12.5 # Drop
    
    score += int(geo_score)
    feedback_parts.append(f"Geometry segments matched: {sum(geo_found)}/4")

    # 6. Analyze Fittings (20 pts)
    # Circle R=40 and Circle R=20 on FITTINGS layer
    circles = msp.query('CIRCLE[layer=="FITTINGS"]')
    r40_found = False
    r20_found = False
    
    for c in circles:
        if is_close(c.dxf.radius, 40, 2.0):
            r40_found = True
        if is_close(c.dxf.radius, 20, 2.0):
            r20_found = True
            
    if r40_found: score += 10
    if r20_found: score += 10
    
    if r40_found and r20_found:
        feedback_parts.append("Fittings correct")
    elif r40_found or r20_found:
        feedback_parts.append("Partial fittings found")
    else:
        feedback_parts.append("No correct fittings found")

    # 7. Analyze Text (10 pts)
    # Look for "RISER" and "DN" text entities
    text_entities = msp.query('TEXT[layer=="TEXT"]')
    has_riser = False
    has_dn = False
    
    for t in text_entities:
        content = t.dxf.text.upper()
        if "RISER" in content:
            has_riser = True
        if "DN" in content:
            has_dn = True
            
    if has_riser: score += 5
    if has_dn: score += 5
    
    if has_riser and has_dn:
        feedback_parts.append("Labels correct")
    
    # Final Decision
    # Need > 70 pts AND at least 3 geometry segments correct
    passed = (score >= 70) and (sum(geo_found) >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }