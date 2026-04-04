#!/usr/bin/env python3
"""
Verifier for laser_cut_nesting task.
Checks DXF file for correct layers, geometry, colors, and nesting.
"""

import json
import os
import tempfile
import math
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing ezdxf
try:
    import ezdxf
    from ezdxf.math import Vec3
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False
    logger.warning("ezdxf not installed. Verification will be limited.")

def verify_laser_cut_nesting(traj, env_info, task_info):
    """
    Verify the laser cut nesting task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file existence and timing
    if not result_meta.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result_meta.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not modified during the task."}

    # If ezdxf is missing, we can't do deep verification
    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": 20, "feedback": "File created, but verification library (ezdxf) missing."}

    # Load the DXF file
    dxf_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(task_info['metadata']['expected_output_path'], dxf_temp.name)
        doc = ezdxf.readfile(dxf_temp.name)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Invalid DXF file: {e}"}
    finally:
        if os.path.exists(dxf_temp.name):
            os.unlink(dxf_temp.name)

    score = 10  # Base score for valid file
    feedback_parts = ["Valid DXF file"]

    # --- Criteria ---

    # 1. Layer Existence and Colors (15 points)
    layers = doc.layers
    layer_score = 0
    
    # Check CUT (Red/1)
    if 'CUT' in layers:
        l = layers.get('CUT')
        if l.color == 1:
            layer_score += 5
        else:
            feedback_parts.append(f"Layer CUT exists but wrong color ({l.color} != 1)")
            layer_score += 2 # Partial for name
    else:
        feedback_parts.append("Missing layer: CUT")

    # Check ETCH (Blue/5)
    if 'ETCH' in layers:
        l = layers.get('ETCH')
        if l.color == 5:
            layer_score += 5
        else:
            feedback_parts.append(f"Layer ETCH exists but wrong color ({l.color} != 5)")
            layer_score += 2
    else:
        feedback_parts.append("Missing layer: ETCH")

    # Check STOCK (White/7 or Black/0)
    if 'STOCK' in layers:
        l = layers.get('STOCK')
        if l.color in [0, 7]:
            layer_score += 5
        else:
            layer_score += 2
    else:
        feedback_parts.append("Missing layer: STOCK")
    
    score += layer_score
    feedback_parts.append(f"Layer Setup: {layer_score}/15")


    # 2. Stock Geometry (10 points)
    # Expecting lines or polyline forming approx 200x200 box on STOCK layer
    stock_ents = list(msp.query('LINE LWPOLYLINE[layer=="STOCK"]'))
    stock_bbox_valid = False
    
    if len(stock_ents) > 0:
        # Calculate bounding box of stock layer
        min_x, min_y, max_x, max_y = float('inf'), float('inf'), float('-inf'), float('-inf')
        
        # Simple bbox approximation for lines/polylines
        has_points = False
        for e in stock_ents:
            if e.dxftype() == 'LINE':
                pts = [e.dxf.start, e.dxf.end]
            elif e.dxftype() == 'LWPOLYLINE':
                pts = e.get_points()
            else:
                continue
            
            for p in pts:
                has_points = True
                min_x = min(min_x, p[0])
                min_y = min(min_y, p[1])
                max_x = max(max_x, p[0])
                max_y = max(max_y, p[1])

        if has_points:
            width = max_x - min_x
            height = max_y - min_y
            # Allow tolerance
            if abs(width - 200) < 5 and abs(height - 200) < 5:
                score += 10
                stock_bbox_valid = True
                feedback_parts.append("Stock geometry correct (200x200)")
            else:
                feedback_parts.append(f"Stock size incorrect: {width:.1f}x{height:.1f}")
        else:
            feedback_parts.append("Stock layer empty")
    else:
        feedback_parts.append("No geometry on STOCK layer")


    # 3. Gasket Geometry & Color Mapping (40 points split)
    # Need to find circles on CUT layer
    cut_circles = list(msp.query('CIRCLE[layer=="CUT"]'))
    
    # Classify circles by radius
    outer_circles = [] # Radius ~40
    inner_circles = [] # Radius ~25
    bolt_circles = []  # Radius ~3
    
    wrong_color_circles = list(msp.query('CIRCLE[layer!="CUT"]')) # Should be 0 geometry circles elsewhere

    for c in cut_circles:
        r = c.dxf.radius
        if abs(r - 40) < 1.0:
            outer_circles.append(c)
        elif abs(r - 25) < 1.0:
            inner_circles.append(c)
        elif abs(r - 3) < 1.0:
            bolt_circles.append(c)
    
    # Scoring Geometry Counts
    geo_score = 0
    
    # Expect 4 Outer
    if len(outer_circles) == 4:
        geo_score += 5
    elif len(outer_circles) > 0:
        geo_score += 2
        
    # Expect 4 Inner
    if len(inner_circles) == 4:
        geo_score += 5
    elif len(inner_circles) > 0:
        geo_score += 2
        
    # Expect 16 Bolt holes (4 * 4)
    if len(bolt_circles) >= 16:
        geo_score += 10
    elif len(bolt_circles) > 0:
        geo_score += 5
        
    # Check Bolt Circle Diameter (distance from center)
    # This is complex to check automatically without grouping, but if counts match, likely good.
    # We can check if bolt holes are approx 32.5mm from an outer circle center.
    
    # Color Mapping check
    color_score = 0
    all_red = True
    for c in cut_circles:
        # Entity color can be ByLayer (256) if layer is Red, or explicitly Red (1)
        # We checked layer color earlier. If color is 256, it inherits.
        c_color = c.dxf.color
        if c_color != 1 and c_color != 256: 
            # If 256, it means ByLayer. Since we checked layer is 1, this is valid.
            # But if layer wasn't 1, this is invalid.
            # Simplify: strict check.
            all_red = False
    
    if all_red and len(cut_circles) > 0:
        color_score += 10
    
    score += geo_score + color_score
    feedback_parts.append(f"Geometry Counts: Out={len(outer_circles)} In={len(inner_circles)} Bolt={len(bolt_circles)}")


    # 4. Text / Etch Layer (10 points)
    texts = list(msp.query('TEXT MTEXT'))
    etch_texts = [t for t in texts if t.dxf.layer == 'ETCH']
    
    text_score = 0
    if len(etch_texts) >= 4:
        text_score += 5
    
    # Check content
    content_match = False
    for t in etch_texts:
        # text content access differs for TEXT and MTEXT slightly in ezdxf versions, but usually .text or .plain_text()
        content = ""
        if t.dxftype() == 'TEXT':
            content = t.dxf.text
        elif t.dxftype() == 'MTEXT':
            content = t.text
        
        if "G-01" in content:
            content_match = True
    
    if content_match:
        text_score += 5
    
    score += text_score
    feedback_parts.append(f"Etch Text Score: {text_score}/10")


    # 5. Nesting Verification (15 points)
    # Check that all CUT geometry is within the 200x200 box (assuming box is at 0,0)
    nesting_score = 0
    all_inside = True
    
    if len(cut_circles) > 0:
        for c in cut_circles:
            r = c.dxf.radius
            center = c.dxf.center
            # Check bounds (center +/- radius)
            min_x = center[0] - r
            max_x = center[0] + r
            min_y = center[1] - r
            max_y = center[1] + r
            
            # Assuming stock is 0,0 to 200,200
            if min_x < 0 or min_y < 0 or max_x > 200 or max_y > 200:
                all_inside = False
                break
        
        if all_inside:
            nesting_score += 15
            feedback_parts.append("Nesting: All parts inside 200x200 bounds")
        else:
            feedback_parts.append("Nesting: Parts extend outside 200x200 bounds")
    else:
         feedback_parts.append("Nesting: No parts to check")

    score += nesting_score

    # Final result
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }