#!/usr/bin/env python3
"""
Verifier for Sheet Metal Flat Pattern Task in LibreCAD.
Uses ezdxf to parse the DXF file and verify geometry, layers, and attributes.
"""

import json
import os
import sys
import logging
import tempfile
import math
from typing import Dict, Any, List, Tuple

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Try importing ezdxf (should be installed in environment)
try:
    import ezdxf
    from ezdxf.document import Drawing
except ImportError:
    logger.error("ezdxf not found. Please install ezdxf in the environment.")
    ezdxf = None

def verify_sheet_metal_flat_pattern(traj, env_info, task_info):
    """
    Verifies the generated DXF file for the sheet metal task.
    
    Criteria:
    1. File creation (valid DXF).
    2. Required layers existence (CUT_EXTERIOR, BEND_LINES, CUT_HOLES).
    3. Layer colors match specs.
    4. BEND_LINES layer uses a dashed linetype.
    5. Exterior geometry dimensions (Bounding Box matches 170x130mm).
    6. Hole count (4) and diameter (6mm).
    7. Hole position (spacing).
    """
    
    # 0. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    if not ezdxf:
        return {"passed": False, "score": 0, "feedback": "System error: ezdxf library missing"}

    metadata = task_info.get('metadata', {})
    specs = metadata.get('specs', {})
    
    # Expected values
    EXP_TOTAL_W = specs.get('total_width', 170.0)
    EXP_TOTAL_H = specs.get('total_height', 130.0)
    EXP_HOLE_DIA = specs.get('hole_diameter', 6.0)
    TOLERANCE = 1.0  # mm
    
    # 1. Retrieve Result JSON and DXF File
    score = 0
    feedback = []
    passed = False
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    
    try:
        # Load JSON result
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get('file_exists'):
            return {"passed": False, "score": 0, "feedback": "DXF file was not saved."}
        
        if not result_data.get('file_created_during_task'):
             feedback.append("Warning: File timestamp suggests it wasn't created during this task session.")
             # We punish this heavily in strict mode, but here we just note it if score logic allows
             # Actually, let's enforce it partially
             score += 0 # No points for just existing if old
        else:
            score += 10 # Points for creating file
            feedback.append("New DXF file created.")

        # Load DXF File
        dxf_path_in_env = result_data.get('output_path')
        copy_from_env(dxf_path_in_env, temp_dxf.name)
        
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            score += 10 # Valid DXF
            feedback.append("Valid DXF structure.")
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid DXF file: {str(e)}"}

        # 2. Verify Layers (Names and Colors)
        # Specs: CUT_EXTERIOR(7), BEND_LINES(2), CUT_HOLES(1)
        required_layers = {
            "CUT_EXTERIOR": 7,
            "BEND_LINES": 2,
            "CUT_HOLES": 1
        }
        
        layers_found = 0
        for layer_name, exp_color in required_layers.items():
            if layer_name in doc.layers:
                layer = doc.layers.get(layer_name)
                # Check color (ezdxf color is int index)
                # Allow minor deviation or just existence if strict color fails
                if layer.color == exp_color:
                    layers_found += 1
                    feedback.append(f"Layer {layer_name} correct (exists + color).")
                else:
                    layers_found += 0.5
                    feedback.append(f"Layer {layer_name} exists but wrong color (got {layer.color}, expected {exp_color}).")
            else:
                feedback.append(f"Layer {layer_name} MISSING.")
        
        # Max 15 points for layers
        score += min(15, int(layers_found * 5))

        # 3. Verify BEND_LINES Linetype
        # The layer should have a linetype that isn't Continuous, OR the entities on it should.
        bend_linetype_ok = False
        bend_layer = doc.layers.get("BEND_LINES")
        
        dashed_keywords = ["dash", "dot", "hidden", "center", "divide"]
        
        # Check layer default
        if bend_layer:
            lt_name = bend_layer.linetype.lower()
            if any(k in lt_name for k in dashed_keywords) and "continuous" not in lt_name:
                bend_linetype_ok = True
                feedback.append(f"BEND_LINES layer uses correct linetype: {lt_name}")
        
        # If layer check failed, check entities
        if not bend_linetype_ok:
            bend_entities = msp.query('LINE[layer=="BEND_LINES"]')
            if len(bend_entities) > 0:
                # check if ALL bend lines have override
                overrides_correct = True
                for e in bend_entities:
                    elt = e.dxf.linetype.lower()
                    if not any(k in elt for k in dashed_keywords):
                        overrides_correct = False
                        break
                if overrides_correct:
                    bend_linetype_ok = True
                    feedback.append("BEND_LINES entities have correct linetype overrides.")
        
        if bend_linetype_ok:
            score += 15
        else:
            feedback.append("BEND_LINES must use a Dashed/Hidden line type (not Continuous).")

        # 4. Verify Geometry Dimensions (CUT_EXTERIOR)
        # We need the bounding box of everything on CUT_EXTERIOR
        ext_entities = msp.query('*[layer=="CUT_EXTERIOR"]')
        
        if len(ext_entities) > 0:
            # Calculate bounding box
            min_x, min_y = float('inf'), float('inf')
            max_x, max_y = float('-inf'), float('-inf')
            
            has_geom = False
            try:
                # Simple bbox for lines/polylines
                for e in ext_entities:
                    if e.dxftype() == 'LINE':
                        start = e.dxf.start
                        end = e.dxf.end
                        min_x = min(min_x, start.x, end.x)
                        max_x = max(max_x, start.x, end.x)
                        min_y = min(min_y, start.y, end.y)
                        max_y = max(max_y, start.y, end.y)
                        has_geom = True
                    elif e.dxftype() == 'LWPOLYLINE':
                        with e.points("xy") as points:
                            for p in points:
                                min_x = min(min_x, p[0])
                                max_x = max(max_x, p[0])
                                min_y = min(min_y, p[1])
                                max_y = max(max_y, p[1])
                        has_geom = True
                    # Add CIRCLE/ARC logic if needed, but profile usually lines
            except Exception as e:
                logger.warning(f"Error calculating bbox: {e}")

            if has_geom:
                width = max_x - min_x
                height = max_y - min_y
                
                # Check Total Width (170) and Height (130)
                # Allow +/- 2mm
                w_ok = abs(width - EXP_TOTAL_W) <= 2.0
                h_ok = abs(height - EXP_TOTAL_H) <= 2.0
                
                if w_ok and h_ok:
                    score += 20
                    feedback.append(f"Outer dimensions correct ({width:.1f}x{height:.1f}).")
                else:
                    feedback.append(f"Outer dimensions incorrect. Expected 170x130, got {width:.1f}x{height:.1f}.")
            else:
                feedback.append("No geometry found on CUT_EXTERIOR.")
        else:
            feedback.append("No entities on CUT_EXTERIOR layer.")

        # 5. Verify Bends (Geometry check)
        # Bend lines should form a 120x80 rectangle
        bend_entities = msp.query('LINE[layer=="BEND_LINES"]')
        # Similar bbox check for bends
        if len(bend_entities) > 0:
            b_min_x, b_min_y = float('inf'), float('inf')
            b_max_x, b_max_y = float('-inf'), float('-inf')
            for e in bend_entities:
                start = e.dxf.start
                end = e.dxf.end
                b_min_x = min(b_min_x, start.x, end.x)
                b_max_x = max(b_max_x, start.x, end.x)
                b_min_y = min(b_min_y, start.y, end.y)
                b_max_y = max(b_max_y, start.y, end.y)
            
            b_w = b_max_x - b_min_x
            b_h = b_max_y - b_min_y
            
            # Base is 120x80
            if abs(b_w - 120.0) <= 2.0 and abs(b_h - 80.0) <= 2.0:
                score += 10
                feedback.append("Bend line geometry dimensions correct (120x80).")
            else:
                feedback.append(f"Bend dimensions incorrect. Expected 120x80, got {b_w:.1f}x{b_h:.1f}.")
        else:
            feedback.append("No lines found on BEND_LINES.")

        # 6. Verify Holes (Count, Size, Position)
        holes = msp.query('CIRCLE[layer=="CUT_HOLES"]')
        
        # Check Count
        if len(holes) == 4:
            score += 10
            feedback.append("Hole count correct (4).")
        else:
            feedback.append(f"Hole count incorrect. Expected 4, got {len(holes)}.")
            
        # Check Size and Position
        # All holes should be dia 6 (radius 3)
        # Centers should be 90mm apart in X and 50mm apart in Y (Derived: 120 - 15*2, 80 - 15*2)
        if len(holes) > 0:
            sizes_ok = all(abs(h.dxf.radius - (EXP_HOLE_DIA/2)) < 0.1 for h in holes)
            if sizes_ok:
                score += 5
                feedback.append("Hole diameters correct.")
            else:
                feedback.append("Some hole diameters are incorrect.")
                
            # Check spacing
            # Get centers
            centers = [(h.dxf.center.x, h.dxf.center.y) for h in holes]
            xs = sorted([c[0] for c in centers])
            ys = sorted([c[1] for c in centers])
            
            # Range of centers
            x_span = xs[-1] - xs[0]
            y_span = ys[-1] - ys[0]
            
            # Expected spans: 120 - 30 = 90, 80 - 30 = 50
            if abs(x_span - 90.0) <= 2.0 and abs(y_span - 50.0) <= 2.0:
                score += 15
                feedback.append("Hole spacing correct (offsets verified).")
            else:
                feedback.append(f"Hole spacing incorrect. Expected span 90x50, got {x_span:.1f}x{y_span:.1f}.")

    except Exception as e:
        logger.exception("Verification failed with exception")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_dxf.name): os.unlink(temp_dxf.name)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }