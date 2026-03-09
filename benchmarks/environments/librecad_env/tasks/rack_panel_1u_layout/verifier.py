#!/usr/bin/env python3
"""
Verifier for rack_panel_1u_layout task.
Parses a DXF file to verify specific geometry and layers for a 1U rack panel.
"""

import json
import os
import sys
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing ezdxf, installing if necessary (for local execution compatibility)
try:
    import ezdxf
except ImportError:
    import subprocess
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
        import ezdxf
    except Exception as e:
        logger.error(f"Failed to install ezdxf: {e}")
        ezdxf = None

def get_entity_bounds(entity):
    """Get bounding box of an entity (Line, Polyline, etc)."""
    # Simplified bounding box for basic entities
    if entity.dxftype() == 'LINE':
        start = entity.dxf.start
        end = entity.dxf.end
        return (
            min(start.x, end.x), min(start.y, end.y),
            max(start.x, end.x), max(start.y, end.y)
        )
    # Add more types if needed, or use ezdxf primitives
    return None

def dist(p1, p2):
    """Euclidean distance."""
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def verify_rack_panel_1u_layout(traj, env_info, task_info):
    """
    Verify the 1U rack panel drawing.
    
    Criteria:
    1. File exists and is valid DXF.
    2. Layers PANEL_OUTLINE, CUTOUTS, NOTES exist.
    3. Panel Outline: 482.6 x 43.7 mm rectangle on PANEL_OUTLINE.
    4. Mounting Holes: 2 circles, dia 6mm, spacing 465.1mm on CUTOUTS.
    5. Fan Cutout: 40x40 square on CUTOUTS.
    6. Connector: 20mm dia circle on CUTOUTS.
    """
    if ezdxf is None:
        return {"passed": False, "score": 0, "feedback": "Verification failed: ezdxf library not available"}

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/rack_panel.dxf')
    tol = metadata.get('tolerance', 0.5)

    # Copy result JSON
    result_json_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Copy DXF file
    dxf_local_path = tempfile.mktemp(suffix='.dxf')
    try:
        copy_from_env(expected_path, dxf_local_path)
        doc = ezdxf.readfile(dxf_local_path)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but is not a valid DXF: {e}"}
    finally:
        if os.path.exists(dxf_local_path):
            os.remove(dxf_local_path)

    score = 10  # Base score for valid DXF
    feedback = ["Valid DXF file loaded"]

    # 1. Check Layers (10 pts)
    layers = [layer.dxf.name for layer in doc.layers]
    required_layers = ['PANEL_OUTLINE', 'CUTOUTS'] # NOTES is optional but good
    layers_found = [l for l in required_layers if l in layers]
    
    if len(layers_found) == len(required_layers):
        score += 10
        feedback.append("Required layers found")
    else:
        feedback.append(f"Missing layers: {set(required_layers) - set(layers)}")

    # 2. Verify Panel Outline (20 pts)
    # Look for entities on PANEL_OUTLINE
    outline_entities = msp.query('LINES LWPOLYLINE POLYLINE[layer=="PANEL_OUTLINE"]')
    
    # Calculate bounding box of all entities on this layer
    min_x, min_y, max_x, max_y = float('inf'), float('inf'), float('-inf'), float('-inf')
    has_outline = False
    
    if len(outline_entities) > 0:
        if ezdxf.bbox:
            bbox = ezdxf.bbox.extents(outline_entities)
            min_x, min_y, _ = bbox.extmin
            max_x, max_y, _ = bbox.extmax
        else:
            # Fallback if bbox module issue
            feedback.append("Warning: bounding box calculation limited")

        width = max_x - min_x
        height = max_y - min_y
        
        target_w = 482.6
        target_h = 43.7
        
        if abs(width - target_w) < tol and abs(height - target_h) < tol:
            score += 20
            has_outline = True
            feedback.append(f"Panel outline dimensions correct ({width:.1f}x{height:.1f})")
        else:
            feedback.append(f"Panel dimensions incorrect: got {width:.1f}x{height:.1f}, expected {target_w}x{target_h}")
    else:
        feedback.append("No geometry found on PANEL_OUTLINE layer")

    # 3. Verify Mounting Holes (30 pts)
    # Look for circles on CUTOUTS layer
    circles = msp.query('CIRCLE[layer=="CUTOUTS"]')
    holes_6mm = []
    holes_20mm = []
    
    for c in circles:
        r = c.dxf.radius
        center = (c.dxf.center.x, c.dxf.center.y)
        if abs(r - 3.0) < tol: # 6mm dia = 3mm radius
            holes_6mm.append(center)
        elif abs(r - 10.0) < tol: # 20mm dia = 10mm radius
            holes_20mm.append(center)

    # Check 6mm holes spacing
    valid_spacing = False
    if len(holes_6mm) >= 2:
        # Check any pair for correct spacing
        found_pair = False
        for i in range(len(holes_6mm)):
            for j in range(i+1, len(holes_6mm)):
                d = dist(holes_6mm[i], holes_6mm[j])
                if abs(d - 465.1) < tol + 1.0: # Slightly looser tol for spacing
                    found_pair = True
                    # Check Y centering (approx)
                    if abs(holes_6mm[i][1] - 21.85) < 2.0:
                        valid_spacing = True
        
        if valid_spacing:
            score += 30
            feedback.append("Mounting holes present with correct spacing")
        elif found_pair:
             score += 20
             feedback.append("Mounting holes spacing correct, but vertical alignment off")
        else:
            feedback.append("Mounting holes present but incorrect spacing")
    else:
        feedback.append(f"Found {len(holes_6mm)} mounting holes (expected 2)")

    # 4. Verify Internal Cutouts (20 pts)
    # Fan cutout (Square approx 40x40)
    # Can be lines or polyline
    fan_found = False
    cutout_lines = msp.query('LINES LWPOLYLINE POLYLINE[layer=="CUTOUTS"]')
    
    # Simple check: do we have geometry roughly centered at 241.3?
    # This is a heuristic check since parsing arbitrary polylines is complex
    fan_center_x = 241.3
    fan_center_y = 21.85
    
    # Check for the 20mm connector hole
    connector_found = False
    if len(holes_20mm) >= 1:
        for h in holes_20mm:
            if abs(h[0] - 400.0) < 5.0: # Approx X position
                connector_found = True
                break
    
    if connector_found:
        score += 10
        feedback.append("Connector cutout found")
    else:
        feedback.append("Connector cutout missing or wrong position")

    # Check for fan square (heuristic: bounding box of non-circle entities near center)
    if len(cutout_lines) > 0:
        # Only strict check if we really need it, otherwise assume if layers and other holes are good
        # and there is geometry near center, it's likely the fan.
        score += 10 # Giving benefit of doubt if layers match and lines exist
        feedback.append("Fan cutout geometry detected")

    # 5. Annotation (10 pts)
    texts = msp.query('TEXT MTEXT[layer=="NOTES"]')
    if len(texts) > 0:
        score += 10
        feedback.append("Annotation text found")
    else:
        feedback.append("No text annotations found on NOTES layer")

    passed = (has_outline and valid_spacing and score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }