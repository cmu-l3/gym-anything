#!/usr/bin/env python3
"""
Verifier for Guitar Fretboard Template task.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fretboard(traj, env_info, task_info):
    """
    Verifies the guitar fretboard DXF drawing.
    
    Criteria:
    1. File exists and is a valid DXF (10 pts)
    2. Correct layers exist (OUTLINE, FRETS, INLAYS) (10 pts)
    3. Fret positions: 22 lines at correct X coordinates (+/- tolerance) (40 pts)
    4. Outline: Trapezoidal shape with correct widths at nut and heel (20 pts)
    5. Inlays: Circles at correct approximate locations (20 pts)
    """
    
    # 1. Setup and data loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_frets = metadata.get('fret_coords', [])
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check if file exists
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    dxf_data = result.get('dxf_analysis', {})
    if not dxf_data.get('valid_dxf', False):
         return {"passed": False, "score": 0, "feedback": "Output file is not a valid DXF or could not be parsed."}
         
    score = 0
    feedback_parts = []
    
    # CRITERION 1: File Validity (10 pts)
    score += 10
    feedback_parts.append("Valid DXF created")
    
    # CRITERION 2: Layers (10 pts)
    layers = [l.upper() for l in dxf_data.get('layers', [])]
    required_layers = ['OUTLINE', 'FRETS', 'INLAYS']
    missing_layers = [l for l in required_layers if l not in layers]
    
    if not missing_layers:
        score += 10
        feedback_parts.append("All layers present")
    else:
        feedback_parts.append(f"Missing layers: {', '.join(missing_layers)}")

    # CRITERION 3: Fret Positions (40 pts)
    # Check if we have 22 lines
    found_frets = sorted(dxf_data.get('frets_x', []))
    
    # Dedup close lines (sometimes users draw double lines)
    unique_frets = []
    if found_frets:
        unique_frets = [found_frets[0]]
        for f in found_frets[1:]:
            if abs(f - unique_frets[-1]) > 1.0: # 1mm threshold for uniqueness
                unique_frets.append(f)
    
    fret_matches = 0
    tolerance = 0.5 # mm
    
    if len(expected_frets) == 22:
        for expected in expected_frets:
            # Find closest match
            closest = min(unique_frets, key=lambda x: abs(x - expected)) if unique_frets else 9999
            if abs(closest - expected) <= tolerance:
                fret_matches += 1
                
    # Calculate score proportional to matches
    fret_score = (fret_matches / 22.0) * 40
    score += fret_score
    feedback_parts.append(f"Frets matched: {fret_matches}/22")
    
    # CRITERION 4: Outline Geometry (20 pts)
    # We look for lines that match the taper
    # Start: (0, +/- 21.5), End: (466.16, +/- 28)
    segments = dxf_data.get('outline_segments', [])
    taper_lines_found = 0
    
    # Check for upper taper line (approx (0, 21.5) to (466, 28))
    # and lower taper line (approx (0, -21.5) to (466, -28))
    has_upper = False
    has_lower = False
    
    for seg in segments:
        p1 = seg['start']
        p2 = seg['end']
        
        # Check against upper definition
        # Either p1 is near start and p2 near end, or vice versa
        if (math.isclose(p1[0], 0, abs_tol=1) and math.isclose(p1[1], 21.5, abs_tol=1) and 
            math.isclose(p2[0], 466.16, abs_tol=1) and math.isclose(p2[1], 28, abs_tol=1)):
            has_upper = True
        elif (math.isclose(p2[0], 0, abs_tol=1) and math.isclose(p2[1], 21.5, abs_tol=1) and 
              math.isclose(p1[0], 466.16, abs_tol=1) and math.isclose(p1[1], 28, abs_tol=1)):
            has_upper = True
            
        # Check against lower definition
        if (math.isclose(p1[0], 0, abs_tol=1) and math.isclose(p1[1], -21.5, abs_tol=1) and 
            math.isclose(p2[0], 466.16, abs_tol=1) and math.isclose(p2[1], -28, abs_tol=1)):
            has_lower = True
        elif (math.isclose(p2[0], 0, abs_tol=1) and math.isclose(p2[1], -21.5, abs_tol=1) and 
              math.isclose(p1[0], 466.16, abs_tol=1) and math.isclose(p1[1], -28, abs_tol=1)):
            has_lower = True

    if has_upper: score += 10
    if has_lower: score += 10
    if has_upper and has_lower:
        feedback_parts.append("Outline geometry correct")
    else:
        feedback_parts.append("Outline geometry incorrect or incomplete")

    # CRITERION 5: Inlays (20 pts)
    inlays = dxf_data.get('inlay_circles', [])
    inlay_score = 0
    
    # We expect roughly 10 circles (8 single + 2 double)
    if len(inlays) >= 9: 
        # Check radius
        correct_radius = sum(1 for c in inlays if math.isclose(c['radius'], 3.0, abs_tol=0.2))
        if correct_radius >= 9:
            inlay_score += 10
            
        # Check 12th fret double dots (Vertical spacing)
        # 12th fret is between Fret 11 (304.73) and Fret 12 (324.00) -> Mid X ~ 314.36
        twelfth_dots = [c for c in inlays if 310 < c['center'][0] < 320]
        if len(twelfth_dots) >= 2:
            # Check Y coords are roughly symmetric (+/- 12)
            ys = [c['center'][1] for c in twelfth_dots]
            if any(y > 5 for y in ys) and any(y < -5 for y in ys):
                inlay_score += 10
        
    score += inlay_score
    if inlay_score == 20:
        feedback_parts.append("Inlays correct")
    elif inlay_score > 0:
        feedback_parts.append("Inlays partially correct")
    else:
        feedback_parts.append("Inlays missing or incorrect")

    passed = score >= 70
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }