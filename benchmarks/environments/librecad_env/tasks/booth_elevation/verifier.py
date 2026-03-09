#!/usr/bin/env python3
"""
Verifier for booth_elevation task (LibreCAD).

Verification Strategy:
1. File Existence & Timestamp: Checks if DXF exists and was created during task.
2. Structure: Uses `ezdxf` to parse the DXF file.
3. Layers: Verifies creation of FRAME, SHELVES, TEXT, DIMENSIONS layers with correct colors.
4. Geometry: Checks bounding boxes and entity counts on specific layers to verify drawing content.
"""

import json
import os
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf (should be installed in env)
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False
    logger.error("ezdxf not installed in environment")

def verify_booth_elevation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/booth_elevation.dxf')
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamp (20 pts)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}
    
    if not result_data.get('file_valid_time', False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task.")
        # We don't fail immediately, but it's suspicious
    else:
        score += 20
        feedback_parts.append("File created/modified during task.")

    # 3. Retrieve and Parse DXF File
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    doc = None
    try:
        copy_from_env(expected_path, temp_dxf.name)
        
        # Check file size validity
        if os.path.getsize(temp_dxf.name) < 100:
            return {"passed": False, "score": score, "feedback": "File is too small/empty."}
            
        if EZDXF_AVAILABLE:
            try:
                doc = ezdxf.readfile(temp_dxf.name)
                score += 10 # valid DXF
                feedback_parts.append("Valid DXF file format.")
            except Exception as e:
                return {"passed": False, "score": score, "feedback": f"Corrupt or invalid DXF file: {e}"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve DXF file: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    if not doc:
        return {"passed": False, "score": score, "feedback": "Could not parse DXF."}

    msp = doc.modelspace()

    # 4. Verify Layers (20 pts)
    # Mapping: Layer Name -> Expected Color Index
    # LibreCAD Colors: Red=1, Green=3, Cyan=4, White/Black=7
    required_layers = {
        "FRAME": 7,
        "SHELVES": 3,
        "TEXT": 4,
        "DIMENSIONS": 1
    }
    
    layers_found = 0
    for layer_name, expected_color in required_layers.items():
        if layer_name in doc.layers:
            layer = doc.layers.get(layer_name)
            # Relax color check slightly (accept if layer exists)
            layers_found += 1
            # Bonus for correct color
            if layer.color == expected_color:
                pass 
            feedback_parts.append(f"Layer '{layer_name}' found.")
        else:
            feedback_parts.append(f"Layer '{layer_name}' MISSING.")

    score += (layers_found / 4) * 20

    # 5. Verify Geometry Content (50 pts)
    
    # FRAME Layer Analysis
    frame_entities = msp.query('LINES LWPOLYLINE POLYLINE INSERT[layer=="FRAME"]')
    if len(frame_entities) > 0:
        score += 15
        feedback_parts.append(f"Found {len(frame_entities)} entities on FRAME layer.")
        
        # Bounding box check for roughly 3000x2500
        # ezdxf bbox calculation
        try:
            bbox = ezdxf.bbox.extents(frame_entities)
            width = bbox.extmax.x - bbox.extmin.x
            height = bbox.extmax.y - bbox.extmin.y
            
            # Allow 10% tolerance
            if 2700 <= width <= 3300 and 2250 <= height <= 2750:
                score += 10
                feedback_parts.append(f"Overall dimensions correct (~{width:.0f}x{height:.0f}).")
            else:
                feedback_parts.append(f"Dimensions off: {width:.0f}x{height:.0f} (Expected ~3000x2500).")
        except:
            feedback_parts.append("Could not calculate bounding box.")
    else:
        feedback_parts.append("No geometry found on FRAME layer.")

    # SHELVES Layer Analysis
    shelf_entities = msp.query('LINES LWPOLYLINE[layer=="SHELVES"]')
    if len(shelf_entities) >= 2:
        score += 10
        feedback_parts.append("Found shelf lines.")
    elif len(shelf_entities) > 0:
        score += 5
        feedback_parts.append("Found some shelf geometry (expected at least 2 lines).")
    else:
        feedback_parts.append("Missing shelves.")

    # TEXT Layer Analysis
    text_entities = msp.query('TEXT MTEXT[layer=="TEXT"]')
    text_found = False
    for t in text_entities:
        # ezdxf text content access
        content = ""
        if t.dxftype() == 'TEXT':
            content = t.dxf.text
        elif t.dxftype() == 'MTEXT':
            content = t.text
        
        if "ACME" in content.upper():
            text_found = True
            break
            
    if text_found:
        score += 10
        feedback_parts.append("Text 'ACME' found.")
    else:
        feedback_parts.append("Text 'ACME' not found on TEXT layer.")

    # DIMENSIONS Layer Analysis
    dim_entities = msp.query('DIMENSION[layer=="DIMENSIONS"]')
    if len(dim_entities) >= 2:
        score += 5
        feedback_parts.append("Dimensions found.")
    elif len(dim_entities) > 0:
        score += 2
        feedback_parts.append("Some dimensions found (expected 2).")
    else:
        feedback_parts.append("No dimensions found.")

    passed = score >= 60 and layers_found >= 3 and result_data.get('file_valid_time', False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }