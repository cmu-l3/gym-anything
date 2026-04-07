#!/usr/bin/env python3
"""
Verifier for bookcase_equal_spacing task in SolveSpace.

Checks:
1. .slvs file and .dxf file were successfully created during the session.
2. The agent correctly applied 'Equal Length' parametric constraints inside the .slvs file.
3. The exported .dxf file mathematically contains 6 line segments (frame top/bottom + 4 shelves) 
   that are approximately 600mm long and perfectly separated by 360mm.
4. Trajectory frames are analyzed via VLM to prevent pure script-based cheating.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_dxf_lines(filepath):
    """Simple robust state-machine parser for basic DXF line entities."""
    lines = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = [line.strip() for line in f.read().splitlines()]
            
        i = 0
        while i < len(content):
            if content[i] == '0' and i+1 < len(content) and content[i+1] == 'LINE':
                i += 2
                line_data = {}
                while i < len(content) and content[i] != '0':
                    code = content[i]
                    val = content[i+1] if i+1 < len(content) else "0"
                    line_data[code] = val
                    i += 2
                try:
                    x1 = float(line_data.get('10', 0))
                    y1 = float(line_data.get('20', 0))
                    x2 = float(line_data.get('11', 0))
                    y2 = float(line_data.get('21', 0))
                    lines.append(((x1, y1), (x2, y2)))
                except ValueError:
                    pass
            else:
                i += 1
    except Exception as e:
        logger.error(f"Error parsing DXF: {e}")
    return lines


def verify_bookcase_equal_spacing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output JSON
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

    score = 0
    feedback_parts = []
    
    slvs_created = result.get('slvs_created', False)
    dxf_created = result.get('dxf_created', False)
    
    if not (slvs_created or dxf_created):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Required files (.slvs and .dxf) were not created during the task."
        }

    if slvs_created:
        score += 10
        feedback_parts.append("SLVS file created")
    if dxf_created:
        score += 10
        feedback_parts.append("DXF file created")

    # Fetch and check the SLVS plaintext for constraints
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    has_equal_length = False
    has_distance = False
    try:
        if result.get('slvs_exists'):
            copy_from_env("/home/ga/Documents/SolveSpace/bookcase.slvs", temp_slvs.name)
            with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
                slvs_content = f.read()
                if "Constraint.type=50" in slvs_content:  # SolveSpace constraint type 50 is EQUAL_LENGTH
                    has_equal_length = True
                if "Constraint.type=30" in slvs_content:  # SolveSpace constraint type 30 is DISTANCE
                    has_distance = True
    except Exception as e:
        logger.error(f"Error reading SLVS: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # Parametric layout enforcement 
    if has_equal_length:
        score += 20
        feedback_parts.append("Parametric Equal Length constraint verified")
    else:
        feedback_parts.append("FAIL: Equal Length constraint missing (manual math detected)")
        
    if has_distance:
        score += 10
        feedback_parts.append("Distance constraint verified")

    # Fetch and parse DXF for mathematical perfection
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    math_precise = False
    try:
        if result.get('dxf_exists'):
            copy_from_env("/home/ga/Documents/SolveSpace/bookcase.dxf", temp_dxf.name)
            dxf_lines = parse_dxf_lines(temp_dxf.name)
            
            horiz_600 = []
            vert_600 = []
            
            # Identify 600mm lines
            for (x1, y1), (x2, y2) in dxf_lines:
                length = ((x2 - x1)**2 + (y2 - y1)**2)**0.5
                if 590 < length < 610:
                    if abs(y1 - y2) < 5:  # Line is horizontal
                        horiz_600.append(((x1+x2)/2, (y1+y2)/2))
                    elif abs(x1 - x2) < 5: # Line is vertical
                        vert_600.append(((x1+x2)/2, (y1+y2)/2))
            
            # Calculate gap equality between 6 lines (4 shelves + 2 frame borders)
            if len(horiz_600) == 6:
                horiz_600.sort(key=lambda p: p[1])
                gaps = [horiz_600[i][1] - horiz_600[i-1][1] for i in range(1, 6)]
                avg_gap = sum(gaps) / len(gaps)
                if 358 < avg_gap < 362 and all(abs(g - avg_gap) < 0.5 for g in gaps):
                    math_precise = True
                    score += 30
                    feedback_parts.append("DXF Mathematical precision perfect (horizontal)")
            elif len(vert_600) == 6:
                vert_600.sort(key=lambda p: p[0])
                gaps = [vert_600[i][0] - vert_600[i-1][0] for i in range(1, 6)]
                avg_gap = sum(gaps) / len(gaps)
                if 358 < avg_gap < 362 and all(abs(g - avg_gap) < 0.5 for g in gaps):
                    math_precise = True
                    score += 30
                    feedback_parts.append("DXF Mathematical precision perfect (vertical)")
            else:
                feedback_parts.append(f"DXF layout mismatch: expected 6 parallel 600mm lines, found {len(horiz_600)} horiz and {len(vert_600)} vert.")
    except Exception as e:
        logger.error(f"Error parsing DXF: {e}")
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # VLM Verification of trajectory to prevent purely scripting-based solutions
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Look at these screenshots of SolveSpace CAD software. "
            "Did the user draw an outer rectangle with 4 interior shelves/lines? "
            "Respond in JSON format with a single boolean: {\"bookcase_drawn\": true/false}"
        )
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and vlm_res.get('parsed', {}).get('bookcase_drawn', False):
                score += 20
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM visual verification failed (CAD layout not visible in GUI)")
        except Exception as e:
            logger.error(f"VLM error: {e}")

    # Pass condition requires both the correct method (Equal Length) and correct outcome (math_precise)
    passed = score >= 70 and math_precise and has_equal_length
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }