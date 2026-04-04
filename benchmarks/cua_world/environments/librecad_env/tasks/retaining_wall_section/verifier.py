#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retaining_wall_section(traj, env_info, task_info):
    """
    Verifies the retaining wall cross-section task.
    
    Criteria:
    1. DXF file exists and is valid (parsed by ezdxf in export script).
    2. Required layers exist (WALL, DRAINAGE, DIMENSIONS, LABELS).
    3. Geometry check:
       - Drain pipe circle (Radius ~75, Center ~650,450)
       - Entity counts (Lines/Polylines present)
    4. Text labels present (Concrete, Gravel, Pipe, Footing).
    5. Dimensions present.
    6. VLM visual verification of the structure.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Basic File Checks (15 pts)
    output_exists = result.get('output_exists', False)
    file_fresh = result.get('file_created_during_task', False)
    dxf_data = result.get('dxf_analysis', {})
    valid_dxf = dxf_data.get('valid_dxf', False)

    if output_exists and file_fresh and valid_dxf:
        score += 15
        feedback_parts.append("Valid DXF file created")
    elif output_exists:
        score += 5
        feedback_parts.append("DXF file exists but validation failed or file old")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file created"}

    # 2. Layer Structure (15 pts)
    layers = set(dxf_data.get('layers', []))
    required_layers = {"WALL", "DRAINAGE", "DIMENSIONS", "LABELS"}
    # LibreCAD layer names might be case sensitive or have '0'
    found_layers = {l.upper() for l in layers}
    
    missing_layers = required_layers - found_layers
    if not missing_layers:
        score += 15
        feedback_parts.append("All required layers created")
    else:
        # Partial credit
        present = len(required_layers) - len(missing_layers)
        points = int((present / 4) * 15)
        score += points
        feedback_parts.append(f"Missing layers: {', '.join(missing_layers)}")

    # 3. Geometric Verification (30 pts)
    # Check for drain pipe (Circle on DRAINAGE)
    circles = dxf_data.get('circles', [])
    pipe_found = False
    for c in circles:
        # Check radius 75 +/- 5 and center near 650,450
        r = c.get('radius', 0)
        cx, cy = c.get('center', [0, 0])
        layer = c.get('layer', '').upper()
        
        if (70 <= r <= 80) and (600 <= cx <= 700) and (400 <= cy <= 500):
            pipe_found = True
            if layer == "DRAINAGE":
                score += 15
                feedback_parts.append("Drain pipe geometry correct on DRAINAGE layer")
            else:
                score += 10
                feedback_parts.append("Drain pipe geometry correct (wrong layer)")
            break
            
    if not pipe_found:
        feedback_parts.append("Drain pipe circle missing or incorrect size/pos")

    # Check for general geometry presence (Polylines/Lines)
    entity_counts = dxf_data.get('entity_counts', {})
    has_geometry = (entity_counts.get('LWPOLYLINE', 0) > 0 or 
                   entity_counts.get('POLYLINE', 0) > 0 or 
                   entity_counts.get('LINE', 0) > 4)
    
    if has_geometry:
        score += 15
        feedback_parts.append("Wall geometry detected")
    else:
        feedback_parts.append("No significant wall geometry found")

    # 4. Text Labels (15 pts)
    text_entries = dxf_data.get('text_content', [])
    found_keywords = set()
    required_keywords = ["CONCRETE", "GRAVEL", "PIPE", "FOOTING"]
    
    for entry in text_entries:
        content = entry.get('text', '').upper()
        for kw in required_keywords:
            if kw in content:
                found_keywords.add(kw)
    
    label_score = min(15, len(found_keywords) * 4)
    score += label_score
    if len(found_keywords) > 0:
        feedback_parts.append(f"Labels found: {len(found_keywords)}/4")

    # 5. Dimensions (10 pts)
    dim_count = dxf_data.get('dimensions', 0)
    if dim_count >= 3:
        score += 10
        feedback_parts.append(f"Dimensions found ({dim_count})")
    elif dim_count > 0:
        score += 5
        feedback_parts.append("Some dimensions found")

    # 6. VLM Verification (15 pts)
    # Check if visual representation looks like a retaining wall section
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + [final_img] if final_img else frames
    
    if images_to_check:
        prompt = """
        Review these screenshots of a LibreCAD drawing task.
        The user is supposed to draw a retaining wall cross-section.
        Look for:
        1. A 'L' or 'inverted T' shaped concrete structure (footing + stem).
        2. A rectangular zone behind it (gravel).
        3. A circle inside the gravel zone (pipe).
        4. Text labels and dimension lines.
        
        Does the drawing sequence show the creation of this specific engineering detail?
        """
        
        vlm_result = query_vlm(
            images=images_to_check,
            prompt=prompt
        )
        
        if vlm_result.get('success'):
            if vlm_result.get('positive_assessment', False): # assuming wrapper returns simple bool or we parse text
                score += 15
                feedback_parts.append("VLM confirms drawing structure")
            else:
                # Fallback if wrapper doesn't provide structured bool, parse text loosely
                resp = vlm_result.get('response', '').lower()
                if "yes" in resp or "correct" in resp or "shows" in resp:
                    score += 15
                    feedback_parts.append("VLM confirms drawing structure")
                else:
                    feedback_parts.append("VLM could not confirm drawing structure")
        else:
             feedback_parts.append("VLM check failed")
    
    passed = score >= 60 and output_exists and valid_dxf
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }