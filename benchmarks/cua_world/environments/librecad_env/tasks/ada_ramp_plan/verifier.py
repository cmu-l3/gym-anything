#!/usr/bin/env python3
"""
Verifier for ADA Ramp Plan task (LibreCAD).
"""

import json
import os
import tempfile
import logging
import math
import sys

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf (should be installed in environment)
try:
    import ezdxf
    from ezdxf.document import Drawing
except ImportError:
    logger.warning("ezdxf not found. Will attempt to install or fail gracefully.")
    ezdxf = None

def verify_ada_ramp_plan(traj, env_info, task_info):
    """
    Verify the ADA Ramp Plan task.
    """
    # 1. Setup and basic checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # Check file existence and timestamp
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    # 2. Download and parse DXF
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/LibreCAD/ada_ramp_plan.dxf", temp_dxf.name)
        doc = ezdxf.readfile(temp_dxf.name)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File created but valid DXF could not be parsed: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    msp = doc.modelspace()
    score = 10
    feedback_parts = ["Valid DXF file created"]

    # 3. Analyze Layers
    layers = [layer.dxf.name for layer in doc.layers]
    has_concrete = any(l.upper() == "CONCRETE" for l in layers)
    has_handrails = any(l.upper() == "HANDRAILS" for l in layers)

    if has_concrete:
        score += 5
        feedback_parts.append("Layer 'CONCRETE' found")
    else:
        feedback_parts.append("Layer 'CONCRETE' missing")

    if has_handrails:
        score += 5
        feedback_parts.append("Layer 'HANDRAILS' found")
    else:
        feedback_parts.append("Layer 'HANDRAILS' missing")

    # 4. Analyze Geometry
    # Helper to get bounding box of entities on a layer
    def get_layer_entities(layer_name):
        return [e for e in msp if e.dxf.layer.upper() == layer_name.upper()]

    concrete_ents = get_layer_entities("CONCRETE")
    handrail_ents = get_layer_entities("HANDRAILS")

    if not concrete_ents:
        feedback_parts.append("No geometry on CONCRETE layer")
        return {"passed": False, "score": score, "feedback": ". ".join(feedback_parts)}

    # Analyze CONCRETE geometry
    # We look for ramp runs (approx 48x360)
    # Since they might be drawn as lines, polylines, or rectangles, we analyze bounding boxes of connected components
    # For simplicity in this verifier, we check individual entity bounding boxes if they are polylines/rects,
    # or just gather all lines and check overall dimensions.
    
    # Let's try to identify the main components by bounding box dimensions
    # A ramp run is 48x360 (area ~17280). 
    # A top landing is 60x60.
    # An intermediate landing is 60x108.
    
    # We will look for entities that match these dimensions (allowing for rotation and tolerance)
    found_ramps = 0
    found_top_landing = False
    found_int_landing = False
    
    # Bounding box extraction helper
    def get_bbox(entity):
        try:
            if entity.dxftype() == 'LWPOLYLINE':
                # Simplified bbox for rectilinear aligned polylines
                xs = [p[0] for p in entity.get_points()]
                ys = [p[1] for p in entity.get_points()]
                return min(xs), min(ys), max(xs), max(ys)
            elif entity.dxftype() == 'LINE':
                start = entity.dxf.start
                end = entity.dxf.end
                return min(start.x, end.x), min(start.y, end.y), max(start.x, end.x), max(start.y, end.y)
            # Add other types if needed, or rely on ezdxf bbox tools if available
        except:
            return None
        return None

    # We'll treat the concrete layer as a collection of bounding boxes
    # If the user drew lines, this is harder. 
    # Heuristic: Check the EXTENTS of the CONCRETE layer.
    # Total width should be around 60 (top) + 360 (ramp) = 420ish OR 108 (width)
    # Total height should be roughly 360 + 60 = 420.
    # The U-shape means bounding box is roughly 108 x 420 or 420 x 108 depending on orientation.
    
    # Calculate global bbox of concrete layer
    min_x, min_y, max_x, max_y = float('inf'), float('inf'), float('-inf'), float('-inf')
    valid_geom = False
    
    for e in concrete_ents:
        try:
            # ezdxf >= 0.16 has bbox module, but let's stick to simple point extraction for compatibility
            if e.dxftype() in ['LINE', 'LWPOLYLINE', 'POLYLINE']:
                if e.dxftype() == 'LINE':
                    points = [e.dxf.start, e.dxf.end]
                elif e.dxftype() == 'LWPOLYLINE':
                    points = e.get_points()
                
                for p in points:
                    # points might be tuples or vectors
                    px = p[0]
                    py = p[1]
                    min_x = min(min_x, px)
                    min_y = min(min_y, py)
                    max_x = max(max_x, px)
                    max_y = max(max_y, py)
                valid_geom = True
        except:
            pass

    if valid_geom:
        width = max_x - min_x
        height = max_y - min_y
        
        # Check overall dimensions
        # Expecting approx 108 x 420 (vertical ramps) or 420 x 108 (horizontal ramps)
        # Tolerance of +/- 10 units
        is_vertical = (abs(width - 108) < 10 and abs(height - 420) < 20)
        is_horizontal = (abs(width - 420) < 20 and abs(height - 108) < 10)
        
        if is_vertical or is_horizontal:
            score += 30
            feedback_parts.append("Overall concrete footprint dimensions correct")
        else:
            feedback_parts.append(f"Footprint dimensions ({width:.1f}x{height:.1f}) don't match expected U-shape (~108x420)")
            # Partial credit if one dimension is correct (e.g. length of ramp)
            if abs(width - 420) < 20 or abs(height - 420) < 20:
                score += 10
                feedback_parts.append("Ramp length seems correct")

        # 5. Handrail Analysis
        # Handrails should be slightly INSIDE the concrete bounding box
        if handrail_ents:
            h_min_x, h_min_y, h_max_x, h_max_y = float('inf'), float('inf'), float('-inf'), float('-inf')
            h_valid = False
            for e in handrail_ents:
                try:
                    if e.dxftype() in ['LINE', 'LWPOLYLINE']:
                        if e.dxftype() == 'LINE':
                            points = [e.dxf.start, e.dxf.end]
                        else:
                            points = e.get_points()
                        for p in points:
                            h_min_x = min(h_min_x, p[0])
                            h_min_y = min(h_min_y, p[1])
                            h_max_x = max(h_max_x, p[0])
                            h_max_y = max(h_max_y, p[1])
                        h_valid = True
                except:
                    pass
            
            if h_valid:
                # Check containment
                # Handrails must be inside concrete bounds (min >= c_min, max <= c_max)
                inside_x = h_min_x >= min_x - 0.1 and h_max_x <= max_x + 0.1
                inside_y = h_min_y >= min_y - 0.1 and h_max_y <= max_y + 0.1
                
                # Check inset (should be smaller)
                smaller_w = (h_max_x - h_min_x) < (width - 2)
                smaller_h = (h_max_y - h_min_y) < (height - 2)
                
                if inside_x and inside_y and (smaller_w or smaller_h):
                    score += 30
                    feedback_parts.append("Handrails are correctly placed inside concrete geometry")
                else:
                    feedback_parts.append("Handrails found but not strictly inside concrete bounds")
                    score += 10
            else:
                feedback_parts.append("Handrail layer empty")
        else:
            feedback_parts.append("No handrails found")
            
        # 6. Gap verification (Heuristic)
        # If vertical: width is ~108. Ramp widths are 48+48=96. 108-96 = 12 gap.
        # This is implicitly checked by the footprint width check above.
        if is_vertical and abs(width - 108) < 5:
            score += 20
            feedback_parts.append("Ramp gap inferred correct from width")
        elif is_horizontal and abs(height - 108) < 5:
            score += 20
            feedback_parts.append("Ramp gap inferred correct from height")

    else:
        feedback_parts.append("Could not parse concrete geometry")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }