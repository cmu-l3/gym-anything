#!/usr/bin/env python3
"""
Verifier for septic_drainfield_layout task.
Uses the JSON analysis generated inside the container to score the task.
"""

import json
import os
import tempfile
import math

def verify_septic_layout(traj, env_info, task_info):
    """
    Verify the septic drainfield layout.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    
    # Prepare temporary files
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    analysis_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Copy main result
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
            
        # Check if DXF analysis exists
        dxf_analysis = {}
        if result.get('output_exists'):
            try:
                copy_from_env("/tmp/dxf_analysis.json", analysis_file.name)
                with open(analysis_file.name, 'r') as f:
                    dxf_analysis = json.load(f)
            except Exception as e:
                return {"passed": False, "score": 0, "feedback": f"Failed to retrieve DXF analysis: {str(e)}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)
        if os.path.exists(analysis_file.name):
            os.unlink(analysis_file.name)

    # Begin Scoring
    score = 0
    feedback = []
    
    # 1. File Validity (10 pts)
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not result.get('file_created_during_task'):
        feedback.append("Warning: File timestamp indicates it wasn't modified during task")
    
    if dxf_analysis.get('valid_dxf'):
        score += 10
        feedback.append("Valid DXF file created")
    else:
        return {"passed": False, "score": 0, "feedback": "Invalid or corrupt DXF file"}

    entities = dxf_analysis.get('entities', {})

    # 2. Layer Structure (15 pts)
    required_layers = ["DBOX", "TRENCHES", "PIPES", "LABELS"]
    layers_found = [l for l in required_layers if l in entities]
    if len(layers_found) == 4:
        score += 15
        feedback.append("All required layers found")
    else:
        score += int(15 * (len(layers_found) / 4))
        feedback.append(f"Layers found: {layers_found}")

    # 3. D-Box Geometry (15 pts)
    # Expected: 24x24 rect centered at (-48, 0). Bounds: (-60, -12) to (-36, 12)
    dbox_data = entities.get('DBOX', {}).get('objects', [])
    dbox_correct = False
    
    for obj in dbox_data:
        if 'bbox' in obj:
            bbox = obj['bbox'] # [minx, miny, maxx, maxy]
            w = obj.get('width', 0)
            h = obj.get('height', 0)
            cx, cy = obj.get('center', [0, 0])
            
            # Check dimensions (allow 1 unit tolerance)
            if abs(w - 24) < 2 and abs(h - 24) < 2:
                # Check position
                if abs(cx - (-48)) < 2 and abs(cy - 0) < 2:
                    dbox_correct = True
                    break
    
    if dbox_correct:
        score += 15
        feedback.append("D-Box geometry correct")
    elif dbox_data:
        score += 5
        feedback.append("D-Box layer has objects but geometry mismatch")
    else:
        feedback.append("No objects on DBOX layer")

    # 4. Trench Geometry (25 pts)
    # Expected: 3 trenches, 600x36. Centers Y: 108, 0, -108. Start X: 48.
    trench_objects = entities.get('TRENCHES', {}).get('objects', [])
    valid_trenches = 0
    
    # We look for rectangles approx 600x36
    trench_centers_y = []
    
    for obj in trench_objects:
        if 'width' in obj and 'height' in obj:
            w, h = obj['width'], obj['height']
            # Allow swapping width/height if drawn rotated, though task implies horizontal
            if (abs(w - 600) < 10 and abs(h - 36) < 5) or (abs(w - 36) < 5 and abs(h - 600) < 10):
                valid_trenches += 1
                if 'center' in obj:
                    trench_centers_y.append(obj['center'][1])

    if valid_trenches >= 3:
        # Check spacing
        trench_centers_y.sort(reverse=True) # Should be ~108, 0, -108
        if len(trench_centers_y) >= 3:
            y1, y2, y3 = trench_centers_y[:3]
            if abs(y1 - 108) < 5 and abs(y2 - 0) < 5 and abs(y3 - (-108)) < 5:
                score += 25
                feedback.append("Trenches correctly sized and spaced")
            else:
                score += 15
                feedback.append(f"Trenches found but spacing/position incorrect (Ys: {y1:.1f}, {y2:.1f}, {y3:.1f})")
    elif valid_trenches > 0:
        score += 10
        feedback.append(f"Found {valid_trenches}/3 valid trenches")
    else:
        feedback.append("No valid trenches found")

    # 5. Pipe Connections (25 pts)
    # 3 Lines starting near (-36, 0) and ending near (48, 108), (48, 0), (48, -108)
    pipe_objects = entities.get('PIPES', {}).get('objects', [])
    valid_pipes = 0
    
    for obj in pipe_objects:
        if 'start' in obj and 'end' in obj:
            p1 = obj['start']
            p2 = obj['end']
            
            # Check if one end is near D-Box outlet (-36, 0)
            dist1 = math.hypot(p1[0] - (-36), p1[1] - 0)
            dist2 = math.hypot(p2[0] - (-36), p2[1] - 0)
            
            near_dbox = dist1 < 10 or dist2 < 10
            
            # Check if other end is near a trench inlet (X=48)
            other_end = p2 if dist1 < 10 else p1
            near_trench = abs(other_end[0] - 48) < 10
            
            if near_dbox and near_trench:
                valid_pipes += 1
                
    if valid_pipes >= 3:
        score += 25
        feedback.append("Pipe connections correct")
    elif valid_pipes > 0:
        score += int(25 * (valid_pipes / 3))
        feedback.append(f"Found {valid_pipes}/3 valid pipes")
    else:
        feedback.append("No valid pipe connections found")

    # 6. Labeling (10 pts)
    labels = entities.get('LABELS', {}).get('objects', [])
    label_text = [l.get('text', '').upper() for l in labels if 'text' in l]
    
    has_dbox_label = any('D-BOX' in t or 'DBOX' in t for t in label_text)
    has_trench_label = any('TRENCH' in t for t in label_text)
    
    if has_dbox_label and has_trench_label:
        score += 10
        feedback.append("Labels present")
    elif has_dbox_label or has_trench_label:
        score += 5
        feedback.append("Partial labels present")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }