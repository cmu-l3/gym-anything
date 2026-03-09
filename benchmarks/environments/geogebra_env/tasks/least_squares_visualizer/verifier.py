#!/usr/bin/env python3
"""
Verifier for Interactive Least Squares Visualizer task.

Scoring (100 points total):
  - File created during task:           10 pts
  - Data points correct (5 pts each):   25 pts
  - Residual Squares created:           30 pts (requires polygons)
  - Dynamic Sum calculated:             20 pts
  - FitLine command used:               15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import zipfile
import re
import logging
import math

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def parse_geogebra_xml_safe(ggb_path):
    """
    Extracts and parses geogebra.xml from a .ggb zip file.
    Returns the raw XML string and a list of command names.
    """
    try:
        with zipfile.ZipFile(ggb_path, 'r') as z:
            if 'geogebra.xml' not in z.namelist():
                return None, [], {}
            
            xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
            
            # Simple regex extraction for robustness against XML namespace issues
            commands = re.findall(r'<command name="([^"]+)"', xml_content)
            
            # Extract points
            # Pattern: <element type="point" label="A"> ... <coords x="1" y="2" z="1"/>
            # We'll do a simpler pass to just find coords
            import xml.etree.ElementTree as ET
            root = ET.fromstring(xml_content)
            
            points = []
            polygons = []
            numerics = []
            
            # Helper to strip namespaces if ElementTree adds them
            for elem in root.iter():
                # Check element type
                if 'type' in elem.attrib:
                    etype = elem.attrib['type']
                    label = elem.attrib.get('label', '')
                    
                    if etype == 'point':
                        coords = elem.find('coords')
                        if coords is not None:
                            try:
                                x = float(coords.get('x', 0))
                                y = float(coords.get('y', 0))
                                z = float(coords.get('z', 1))
                                if abs(z) > 1e-6:
                                    points.append({'label': label, 'x': x/z, 'y': y/z})
                            except: pass
                            
                    elif etype == 'polygon' or etype == 'quadrilateral':
                        polygons.append(label)
                        
                    elif etype == 'numeric':
                        # Check if it's a sum or expression
                        val_tag = elem.find('value')
                        val = float(val_tag.get('val', 0)) if val_tag is not None else 0
                        numerics.append({'label': label, 'val': val})

            return xml_content, commands, {'points': points, 'polygons': polygons, 'numerics': numerics}
            
    except Exception as e:
        logger.error(f"Failed to parse GGB file: {e}")
        return None, [], {}

def verify_least_squares_visualizer(traj, env_info, task_info):
    """Verify the Least Squares Visualizer task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Retrieve result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (10 pts)
    ggb_path = result.get('file_path')
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "File 'least_squares.ggb' not found or not created during task"}

    # 3. Retrieve and Parse .ggb file
    local_ggb = tempfile.NamedTemporaryFile(delete=False, suffix='.ggb')
    local_ggb.close()
    try:
        copy_from_env(ggb_path, local_ggb.name)
        xml_content, commands, elements = parse_geogebra_xml_safe(local_ggb.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve GGB file: {e}"}
    finally:
        if os.path.exists(local_ggb.name):
            os.unlink(local_ggb.name)

    if xml_content is None:
        return {"passed": False, "score": score, "feedback": "Corrupt or invalid .ggb file"}

    # 4. Criteria Verification
    
    # A. Data Points (25 pts)
    # Target: (1,2), (2,3), (3,5), (4,4), (5,7)
    targets = [(1,2), (2,3), (3,5), (4,4), (5,7)]
    found_points = elements.get('points', [])
    points_matched = 0
    
    for tx, ty in targets:
        # Find closest point
        match = False
        for p in found_points:
            dist = math.sqrt((p['x'] - tx)**2 + (p['y'] - ty)**2)
            if dist < 0.1:
                match = True
                break
        if match:
            points_matched += 1
            
    points_score = points_matched * 5
    score += points_score
    feedback_parts.append(f"Data points: {points_matched}/5 found (+{points_score})")

    # B. Residual Squares (30 pts)
    # Look for at least 5 polygons
    # Better check: Look for 'Polygon' command or polygon elements
    num_polys = len(elements.get('polygons', []))
    # Also check if commands contain 'Polygon'
    poly_cmds = [c for c in commands if c == 'Polygon']
    
    if num_polys >= 5 or len(poly_cmds) >= 5:
        score += 30
        feedback_parts.append("Residual squares found (+30)")
    elif num_polys > 0:
        partial = num_polys * 5
        score += partial
        feedback_parts.append(f"Some squares found ({num_polys}) (+{partial})")
    else:
        feedback_parts.append("No squares (polygons) found (0/30)")

    # C. Dynamic Sum (20 pts)
    # Check for 'Sum' command or manual addition of polygon areas
    # It's hard to verify dependency statically, so we check for the Sum command 
    # or if there's a numeric object that looks like a sum (not verifying value as line moves)
    has_sum_cmd = 'Sum' in commands
    # Alternatively, check for addition in XML expressions (complex regex, skip for now)
    
    if has_sum_cmd:
        score += 20
        feedback_parts.append("Sum command found (+20)")
    else:
        # Check if they just added them: poly1 + poly2...
        # We can look for a numeric object that isn't a coordinate
        if len(elements.get('numerics', [])) > 0:
            # Heuristic: If we have polygons and a number, assume they might be summing
            # Give partial credit
            score += 10
            feedback_parts.append("Numeric value found (likely sum) (+10)")
        else:
            feedback_parts.append("No sum calculation found (0/20)")

    # D. FitLine Command (15 pts)
    if 'FitLine' in commands:
        score += 15
        feedback_parts.append("FitLine regression found (+15)")
    else:
        feedback_parts.append("FitLine command not found (0/15)")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }