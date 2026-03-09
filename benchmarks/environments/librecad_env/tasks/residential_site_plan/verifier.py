#!/usr/bin/env python3
"""
Verifier for residential_site_plan task.
Checks DXF geometry for correct lot dimensions, setbacks, and house placement.
"""

import json
import os
import sys
import tempfile
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf (install if missing)
try:
    import ezdxf
except ImportError:
    import subprocess
    logger.info("ezdxf not found, installing...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
    import ezdxf

def get_bounding_box(entities):
    """Calculate bounding box for a list of entities."""
    min_x, min_y = float('inf'), float('inf')
    max_x, max_y = float('-inf'), float('-inf')
    found = False
    
    for e in entities:
        if e.dxftype() == 'LINE':
            found = True
            start = e.dxf.start
            end = e.dxf.end
            min_x = min(min_x, start.x, end.x)
            min_y = min(min_y, start.y, end.y)
            max_x = max(max_x, start.x, end.x)
            max_y = max(max_y, start.y, end.y)
        elif e.dxftype() == 'LWPOLYLINE':
            found = True
            with e.points() as points:
                for p in points:
                    min_x = min(min_x, p[0])
                    min_y = min(min_y, p[1])
                    max_x = max(max_x, p[0])
                    max_y = max(max_y, p[1])
    
    if not found:
        return None
    return (min_x, min_y, max_x, max_y)

def verify_residential_site_plan(traj, env_info, task_info):
    """
    Verify the residential site plan task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "DXF output file not found."}

    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

    # 2. Retrieve the DXF file
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/tmp/residential_site_plan.dxf", temp_dxf.name)
        doc = ezdxf.readfile(temp_dxf.name)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but is not a valid DXF: {str(e)}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    score = 10 # Base points for valid file
    feedback = []
    
    # 3. Verify Layers
    required_layers = ['LOT_LINES', 'SETBACKS', 'BUILDING', 'TEXT']
    existing_layers = [layer.dxf.name.upper() for layer in doc.layers]
    
    layers_found = 0
    for req in required_layers:
        if req in existing_layers:
            layers_found += 1
    
    if layers_found == 4:
        score += 10
        feedback.append("All layers present.")
    else:
        feedback.append(f"Found {layers_found}/4 required layers.")

    # 4. Verify Geometry
    # Tolerance for float comparisons
    TOL = 1.0 

    # Check LOT_LINES (60x100 at 0,0)
    lot_entities = msp.query('LINE LWPOLYLINE[layer=="LOT_LINES"]')
    lot_bbox = get_bounding_box(lot_entities)
    
    lot_ok = False
    if lot_bbox:
        lx1, ly1, lx2, ly2 = lot_bbox
        w = lx2 - lx1
        h = ly2 - ly1
        # Check dimensions and origin
        if abs(w - 60) < TOL and abs(h - 100) < TOL and abs(lx1) < TOL and abs(ly1) < TOL:
            score += 20
            lot_ok = True
            feedback.append("Lot geometry correct (60x100 at origin).")
        else:
            feedback.append(f"Lot geometry incorrect. Found bbox: ({lx1:.1f}, {ly1:.1f}) to ({lx2:.1f}, {ly2:.1f}).")
    else:
        feedback.append("No geometry found on LOT_LINES layer.")

    # Check SETBACKS
    # Front: 25, Rear: 100-10=90, Side: 5, Side: 60-5=55
    # Expected BBox: (5, 25) to (55, 90)
    setback_entities = msp.query('LINE LWPOLYLINE[layer=="SETBACKS"]')
    sb_bbox = get_bounding_box(setback_entities)
    
    if sb_bbox:
        sx1, sy1, sx2, sy2 = sb_bbox
        # Check if bounds match approximate setback lines
        if (abs(sx1 - 5) < TOL and abs(sx2 - 55) < TOL and 
            abs(sy1 - 25) < TOL and abs(sy2 - 90) < TOL):
            score += 25
            feedback.append("Setback geometry correct.")
        else:
            feedback.append(f"Setback geometry incorrect or misaligned. BBox: {sb_bbox}")
    else:
        feedback.append("No geometry found on SETBACKS layer.")

    # Check BUILDING (30x50)
    # Placement: Centered on X (30), Front on Setback (Y=25)
    # Expected X range: 15 to 45
    # Expected Y range: 25 to 75
    house_entities = msp.query('LINE LWPOLYLINE[layer=="BUILDING"]')
    house_bbox = get_bounding_box(house_entities)
    
    house_ok = False
    if house_bbox:
        hx1, hy1, hx2, hy2 = house_bbox
        if (abs(hx1 - 15) < TOL and abs(hx2 - 45) < TOL and 
            abs(hy1 - 25) < TOL and abs(hy2 - 75) < TOL):
            score += 25
            house_ok = True
            feedback.append("House geometry and placement correct.")
        else:
            feedback.append(f"House geometry/placement incorrect. BBox: {house_bbox}")
    else:
        feedback.append("No geometry found on BUILDING layer.")

    # Check TEXT
    text_entities = msp.query('TEXT MTEXT[layer=="TEXT"]')
    texts = [e.dxf.text for e in text_entities]
    combined_text = " ".join(texts).upper()
    
    if "STREET" in combined_text and "RESIDENCE" in combined_text:
        score += 10
        feedback.append("Required text labels found.")
    elif "STREET" in combined_text or "RESIDENCE" in combined_text:
        score += 5
        feedback.append("Some text labels found.")
    else:
        feedback.append("Text labels missing.")

    # Final logic
    passed = (score >= 70) and lot_ok and house_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }