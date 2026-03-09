#!/usr/bin/env python3
"""
Verifier for Badminton Court Layout task.

Checks for:
1. Valid DXF file creation.
2. Correct Layer structure (Court_Lines, Net_Line, Annotations).
3. Geometric accuracy of court boundaries and lines.
4. Correct linetype usage for Net Line.
5. Presence of text annotations.
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

# Try to import ezdxf, install if missing (standard pattern for verifiers)
try:
    import ezdxf
    from ezdxf.document import Drawing
except ImportError:
    import subprocess
    logger.info("Installing ezdxf...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
        import ezdxf
        from ezdxf.document import Drawing
    except Exception as e:
        logger.error(f"Failed to install ezdxf: {e}")
        ezdxf = None

def get_entities_on_layer(doc: Drawing, layer_name: str):
    """Retrieve all entities on a specific layer."""
    try:
        msp = doc.modelspace()
        return [e for e in msp if e.dxf.layer.lower() == layer_name.lower()]
    except Exception:
        return []

def check_line_exists(entities, start, end, tolerance=20.0):
    """
    Check if a line exists between start and end coordinates within tolerance.
    Supports both LINE and LWPOLYLINE entities.
    """
    x1, y1 = start
    x2, y2 = end
    
    for e in entities:
        if e.dxftype() == 'LINE':
            s = e.dxf.start
            e_end = e.dxf.end
            # Check direct match
            if (math.hypot(s.x - x1, s.y - y1) < tolerance and math.hypot(e_end.x - x2, e_end.y - y2) < tolerance):
                return True
            # Check reversed match
            if (math.hypot(s.x - x2, s.y - y2) < tolerance and math.hypot(e_end.x - x1, e_end.y - y1) < tolerance):
                return True
                
        elif e.dxftype() == 'LWPOLYLINE':
            # Simplified check for polyline segments
            points = e.get_points()
            for i in range(len(points) - 1):
                p1 = points[i]
                p2 = points[i+1]
                # Check segment direct
                if (math.hypot(p1[0] - x1, p1[1] - y1) < tolerance and math.hypot(p2[0] - x2, p2[1] - y2) < tolerance):
                    return True
                # Check segment reversed
                if (math.hypot(p1[0] - x2, p1[1] - y2) < tolerance and math.hypot(p2[0] - x1, p2[1] - y1) < tolerance):
                    return True
                    
    return False

def check_rectangle_exists(entities, width, height, origin=(0,0), tolerance=20.0):
    """Check if a closed loop exists matching dimensions."""
    # Look for 4 connected lines or a closed polyline
    # For this task, we simplify to checking the 4 boundary lines
    ox, oy = origin
    l1 = check_line_exists(entities, (ox, oy), (ox + width, oy), tolerance)
    l2 = check_line_exists(entities, (ox + width, oy), (ox + width, oy + height), tolerance)
    l3 = check_line_exists(entities, (ox + width, oy + height), (ox, oy + height), tolerance)
    l4 = check_line_exists(entities, (ox, oy + height), (ox, oy), tolerance)
    return l1 and l2 and l3 and l4

def verify_badminton_court(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    if ezdxf is None:
        return {"passed": False, "score": 0, "feedback": "Verification failed: ezdxf library not available"}

    # Load result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check file existence
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}

    # Retrieve the DXF file
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env("/home/ga/Documents/LibreCAD/badminton_court.dxf", temp_dxf.name)
        try:
            doc = ezdxf.readfile(temp_dxf.name)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"File exists but is not a valid DXF: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve DXF file: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    score = 0
    feedback = []
    passed_criteria = 0
    
    # 1. File Validity (Already passed readfile)
    score += 10
    feedback.append("Valid DXF file created.")

    # 2. Layer Structure (15 pts)
    layers = [layer.dxf.name.lower() for layer in doc.layers]
    required_layers = ["court_lines", "net_line", "annotations"]
    missing_layers = [l for l in required_layers if l not in layers]
    
    if not missing_layers:
        score += 15
        feedback.append("Layer structure correct.")
    else:
        score += max(0, 15 - (len(missing_layers) * 5))
        feedback.append(f"Missing layers: {', '.join(missing_layers)}.")

    # Get entities by layer
    court_ents = get_entities_on_layer(doc, "Court_Lines")
    net_ents = get_entities_on_layer(doc, "Net_Line")
    anno_ents = get_entities_on_layer(doc, "Annotations")

    # If layers are mixed up, fallback to checking all entities for geometry
    all_ents = court_ents + net_ents + anno_ents
    if not court_ents and len(all_ents) > 0:
        court_ents = all_ents 
        feedback.append("Warning: Geometry not found on correct layer, checking all layers.")

    # 3. Outer Boundary (15 pts)
    if check_rectangle_exists(court_ents, 13400, 6100, (0,0)):
        score += 15
        feedback.append("Outer court boundary correct.")
    else:
        feedback.append("Outer boundary (13400x6100) not found or incorrect.")

    # 4. Internal Geometry (30 pts)
    geom_score = 0
    # Singles lines
    if check_line_exists(court_ents, (0, 460), (13400, 460)) and \
       check_line_exists(court_ents, (0, 5640), (13400, 5640)):
        geom_score += 10
        feedback.append("Singles sidelines correct.")
    
    # Short service lines
    if check_line_exists(court_ents, (4720, 0), (4720, 6100)) and \
       check_line_exists(court_ents, (8680, 0), (8680, 6100)):
        geom_score += 10
        feedback.append("Short service lines correct.")
        
    # Doubles service lines
    if check_line_exists(court_ents, (760, 0), (760, 6100)) and \
       check_line_exists(court_ents, (12640, 0), (12640, 6100)):
        geom_score += 5
        feedback.append("Doubles service lines correct.")
        
    # Center line (segments)
    if check_line_exists(court_ents, (0, 3050), (4720, 3050)) and \
       check_line_exists(court_ents, (8680, 3050), (13400, 3050)):
        geom_score += 5
        feedback.append("Center line segments correct.")
    
    score += geom_score

    # 5. Net Line & Style (20 pts)
    # Check geometry
    net_geom_ok = check_line_exists(net_ents if net_ents else all_ents, (6700, -500), (6700, 6600), tolerance=1000) # loose tolerance on Y length
    
    # Check linetype if possible
    net_style_ok = False
    for e in (net_ents if net_ents else all_ents):
        if e.dxftype() in ['LINE', 'LWPOLYLINE']:
            # Check proximity to X=6700
            is_net = False
            if e.dxftype() == 'LINE' and abs(e.dxf.start.x - 6700) < 10: is_net = True
            if e.dxftype() == 'LWPOLYLINE' and abs(e.get_points()[0][0] - 6700) < 10: is_net = True
            
            if is_net:
                ltype = e.dxf.linetype.lower()
                if "dash" in ltype or "hidden" in ltype:
                    net_style_ok = True
                    break
    
    if net_geom_ok:
        score += 10
        feedback.append("Net line position correct.")
        if net_style_ok:
            score += 10
            feedback.append("Net line linetype (Dashed) correct.")
        else:
            feedback.append("Net line exists but linetype is not Dashed.")
    else:
        feedback.append("Net line missing at X=6700.")

    # 6. Text Labels (10 pts)
    found_net_text = False
    found_service_text = False
    
    for e in (anno_ents if anno_ents else all_ents):
        if e.dxftype() in ['TEXT', 'MTEXT']:
            text = e.dxf.text if e.dxftype() == 'TEXT' else e.text
            if "NET" in text.upper():
                found_net_text = True
            if "SERVICE" in text.upper():
                found_service_text = True
                
    if found_net_text and found_service_text:
        score += 10
        feedback.append("Annotations correct.")
    elif found_net_text or found_service_text:
        score += 5
        feedback.append("Some annotations found.")
    else:
        feedback.append("Missing text annotations.")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }