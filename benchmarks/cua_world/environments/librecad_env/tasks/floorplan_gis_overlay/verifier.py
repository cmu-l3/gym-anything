#!/usr/bin/env python3
"""
Verifier for floorplan_gis_overlay task.
Uses ezdxf to parse the resulting CAD file and verify geometry, layers, and text.
"""

import json
import os
import sys
import tempfile
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Try to import ezdxf, installing if necessary (runs on host)
try:
    import ezdxf
except ImportError:
    try:
        import subprocess
        logger.info("Installing ezdxf for verification...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
        import ezdxf
    except Exception as e:
        logger.error(f"Failed to install ezdxf: {e}")
        sys.exit(1)

def verify_floorplan_gis_overlay(traj, env_info, task_info):
    """
    Verifies the LibreCAD task by parsing the output DXF file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    
    # Load task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence and creation
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    # Retrieve the DXF file
    output_path = task_result.get('output_path')
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(output_path, temp_dxf.name)
        
        # Parse DXF
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"File exists but is not a valid DXF: {str(e)}"}
            
        score = 0
        feedback = []
        
        # --- 1. Layer Verification (24 points) ---
        layers = doc.layers
        layer_specs = {
            "GIS_BOUNDARY": 1,  # Red
            "GIS_REFERENCE": 4, # Cyan
            "GIS_LABELS": 3     # Green
        }
        
        for layer_name, expected_color in layer_specs.items():
            if layer_name in layers:
                layer = layers.get(layer_name)
                if layer.color == expected_color:
                    score += 8
                    feedback.append(f"Layer '{layer_name}' correct (+8)")
                else:
                    score += 4
                    feedback.append(f"Layer '{layer_name}' exists but wrong color (got {layer.color}, expected {expected_color}) (+4)")
            else:
                feedback.append(f"Layer '{layer_name}' missing")

        # --- 2. Geometry Verification (31 points) ---
        TOL = 15.0 # Tolerance for coordinates
        
        # Rectangle on GIS_BOUNDARY (15 pts)
        rect_found = False
        rect_points = 0
        
        # Check for LWPOLYLINE (LibreCAD often saves rectangles as polylines)
        for e in msp.query('LWPOLYLINE[layer=="GIS_BOUNDARY"]'):
            pts = list(e.get_points()) # Returns list of (x, y, ...)
            # Check bounding box roughly covers 0,0 to 1500,1000
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            if (min(xs) > -TOL and min(xs) < TOL and 
                max(xs) > 1500-TOL and max(xs) < 1500+TOL and
                min(ys) > -TOL and min(ys) < TOL and 
                max(ys) > 1000-TOL and max(ys) < 1000+TOL):
                rect_found = True
                break
                
        # Also check for 4 individual lines if Polyline not found
        if not rect_found:
            lines = msp.query('LINE[layer=="GIS_BOUNDARY"]')
            # Heuristic: verify bounding box of all lines on this layer
            if len(lines) >= 4:
                xs, ys = [], []
                for l in lines:
                    xs.extend([l.dxf.start.x, l.dxf.end.x])
                    ys.extend([l.dxf.start.y, l.dxf.end.y])
                if (min(xs) > -TOL and min(xs) < TOL and 
                    max(xs) > 1500-TOL and max(xs) < 1500+TOL and
                    min(ys) > -TOL and min(ys) < TOL and 
                    max(ys) > 1000-TOL and max(ys) < 1000+TOL):
                    rect_found = True

        if rect_found:
            score += 15
            feedback.append("Rectangle geometry correct (+15)")
        else:
            feedback.append("Rectangle geometry missing or incorrect")

        # Crosshair on GIS_REFERENCE (16 pts)
        # Horizontal: (650,500) to (850,500)
        # Vertical: (750,400) to (750,600)
        h_line_found = False
        v_line_found = False
        
        ref_lines = msp.query('LINE[layer=="GIS_REFERENCE"]')
        for l in ref_lines:
            s, e = l.dxf.start, l.dxf.end
            # Check Horizontal
            if abs(s.y - 500) < TOL and abs(e.y - 500) < TOL:
                if (abs(s.x - 650) < TOL and abs(e.x - 850) < TOL) or (abs(s.x - 850) < TOL and abs(e.x - 650) < TOL):
                    h_line_found = True
            # Check Vertical
            if abs(s.x - 750) < TOL and abs(e.x - 750) < TOL:
                if (abs(s.y - 400) < TOL and abs(e.y - 600) < TOL) or (abs(s.y - 600) < TOL and abs(e.y - 400) < TOL):
                    v_line_found = True
        
        if h_line_found: score += 8; feedback.append("Crosshair horizontal line correct (+8)")
        if v_line_found: score += 8; feedback.append("Crosshair vertical line correct (+8)")

        # --- 3. Text Verification (25 points) ---
        text_entities = msp.query('TEXT MTEXT[layer=="GIS_LABELS"]')
        expected_texts = [
            ("PARCEL ID", 10, (50, 1050), 25),
            ("COORDINATE SYSTEM", 8, (50, 1100), 20),
            ("PREPARED BY", 7, (50, 1150), 20)
        ]
        
        for substr, pts, pos, height in expected_texts:
            found = False
            for t in text_entities:
                # Get text content
                content = t.dxf.text if t.dxftype() == 'TEXT' else t.text
                if substr.upper() in content.upper():
                    # Check position (approx)
                    insert = t.dxf.insert
                    if abs(insert.x - pos[0]) < 50 and abs(insert.y - pos[1]) < 50:
                        # Check height (approx)
                        h = t.dxf.height if t.dxftype() == 'TEXT' else t.dxf.char_height
                        if abs(h - height) < 5:
                            score += pts
                            feedback.append(f"Text '{substr}' correct (+{pts})")
                            found = True
                            break
            if not found:
                feedback.append(f"Text '{substr}' missing or incorrect properties")

        # --- 4. Data Preservation & File Validity (20 points) ---
        # File exists and is valid DXF (already checked implicitly by parsing)
        score += 10
        feedback.append("Output file is valid DXF (+10)")
        
        # Check if original entities are preserved
        # We assume the original floorplan has many entities on other layers
        other_entities = 0
        for e in msp:
            if e.dxf.layer not in layer_specs:
                other_entities += 1
        
        if other_entities > 100: # The floorplan sample is complex
            score += 10
            feedback.append("Original floorplan data preserved (+10)")
        elif other_entities > 0:
            score += 5
            feedback.append("Some original data preserved (+5)")
        else:
            feedback.append("Original floorplan data appears missing")

        # --- 5. Anti-gaming check ---
        if not task_result.get('original_preserved', False):
             score = max(0, score - 20)
             feedback.append("PENALTY: Original file was modified (-20)")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": "; ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)