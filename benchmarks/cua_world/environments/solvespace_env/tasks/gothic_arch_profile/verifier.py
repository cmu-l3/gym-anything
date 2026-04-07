#!/usr/bin/env python3
"""
Verifier for gothic_arch_profile task.
Combines programmatic .slvs file parsing with VLM trajectory verification.
"""

import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_slvs(content):
    """Parse a .slvs file into blocks keyed by 'Add*' markers."""
    blocks = []
    current = {}
    for line in content.split('\n'):
        line = line.strip()
        if not line:
            continue
        if line.startswith('Add'):
            current['_type'] = line
            blocks.append(current)
            current = {}
        elif '=' in line:
            parts = line.split('=', 1)
            if len(parts) == 2:
                current[parts[0].strip()] = parts[1].strip()
    return blocks

def verify_gothic_arch_profile(traj, env_info, task_info):
    """Verifies the SolveSpace gothic arch profile task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_span = metadata.get('expected_span', 60.0)
    expected_radius = metadata.get('expected_radius', 60.0)
    expected_height = metadata.get('expected_apex_height', 51.96)
    tolerance = metadata.get('tolerance_mm', 3.0)

    score = 0
    feedback_parts = []
    
    # 1. Fetch export JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "File /home/ga/Documents/SolveSpace/gothic_arch.slvs was not found."}
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "File exists but was not created/modified during task."}

    score += 10
    feedback_parts.append("File created successfully (+10)")

    # 2. Fetch and parse SLVS file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/gothic_arch.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read slvs file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    blocks = parse_slvs(slvs_content)
    
    requests = [b for b in blocks if b.get('_type') == 'AddRequest']
    entities = [b for b in blocks if b.get('_type') == 'AddEntity']
    constraints = [b for b in blocks if b.get('_type') == 'AddConstraint']
    params = [b for b in blocks if b.get('_type') == 'AddParam']

    # Build param value lookup
    param_vals = {}
    for p in params:
        hv = p.get('Param.h.v.', '')
        val = p.get('Param.val', None)
        if hv and val is not None:
            try:
                param_vals[hv] = float(val)
            except ValueError:
                pass

    # --- Programmatic Geometry Checks ---
    
    # Check Arcs (type 500)
    arc_requests = [r for r in requests if r.get('Request.type') in ('500', '600')]
    if len(arc_requests) >= 2:
        score += 10
        feedback_parts.append(f"Found {len(arc_requests)} arcs (+10)")
    elif len(arc_requests) == 1:
        score += 5
        feedback_parts.append("Found only 1 arc (+5)")
    else:
        feedback_parts.append("No arcs found")

    # Check Baseline (type 200)
    line_requests = [r for r in requests if r.get('Request.type') == '200']
    if len(line_requests) >= 1:
        score += 10
        feedback_parts.append("Found baseline (+10)")
    else:
        feedback_parts.append("No baseline found")

    # Check Dimension Constraint (~60)
    dim_constraints = [c for c in constraints if c.get('Constraint.type') in ('30', '31', '32')]
    found_span = False
    for c in dim_constraints:
        try:
            val = float(c.get('Constraint.valA', '0'))
            if abs(val - expected_span) <= tolerance:
                found_span = True
                break
        except ValueError:
            pass
            
    if found_span:
        score += 10
        feedback_parts.append("Span constraint correct (+10)")
    else:
        feedback_parts.append("No valid span constraint (~60mm) found")

    # Check Apex Height
    y_coords = []
    for e in entities:
        y_val = e.get('Entity.actPoint.y')
        if y_val:
            try:
                y_coords.append(float(y_val))
            except ValueError:
                pass
                
    if len(y_coords) >= 3:
        height = max(y_coords) - min(y_coords)
        if abs(height - expected_height) <= tolerance:
            score += 10
            feedback_parts.append(f"Apex height correct: {height:.1f}mm (+10)")
        elif abs(height - expected_height) <= 10.0:
            score += 5
            feedback_parts.append(f"Apex height close: {height:.1f}mm (+5)")
        else:
            feedback_parts.append(f"Apex height incorrect: {height:.1f}mm")

    # Check Symmetry / Constraints
    sym_constraints = [c for c in constraints if c.get('Constraint.type') in ('44', '45', '46', '47')]
    coincident_constraints = [c for c in constraints if c.get('Constraint.type') == '20']
    
    if sym_constraints or len(coincident_constraints) >= 2:
        score += 10
        feedback_parts.append("Symmetry/closure constraints present (+10)")

    # --- VLM Verification ---
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames to prove progression
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if final_frame:
                all_frames = frames + [final_frame]
                
                vlm_prompt = """Look at these screenshots of a SolveSpace CAD session.
The user is supposed to be drawing an equilateral Gothic pointed arch (a horizontal baseline and two circular arcs that meet at a sharp point at the top).
1. Do these images show the progression of drawing this arch shape?
2. In the final image, is the pointed arch shape clearly visible and closed?
3. Does it look symmetric?

Respond in JSON format:
{
    "shows_progression": true/false,
    "shows_pointed_arch": true/false,
    "is_symmetric": true/false
}"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("shows_progression"):
                        vlm_score += 15
                        feedback_parts.append("VLM confirmed workflow progression (+15)")
                    if parsed.get("shows_pointed_arch"):
                        vlm_score += 15
                        feedback_parts.append("VLM confirmed pointed arch shape (+15)")
                    if parsed.get("is_symmetric"):
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed symmetry (+10)")
                else:
                    feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")
        except Exception as e:
            feedback_parts.append(f"VLM verification error: {e}")
    else:
        feedback_parts.append("VLM querying not available")

    score += vlm_score

    # To pass: MUST have file, must have arcs, and overall score >= 60
    key_criteria_met = output_exists and file_created and (len(arc_requests) >= 2)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }