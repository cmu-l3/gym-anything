#!/usr/bin/env python3
"""
Verifier for orthographic_vblock task.
Verifies DXF structure (layers, entities) and uses VLM for visual correctness.
"""

import json
import tempfile
import os
import logging
import sys

# Add ezdxf path if needed, though env should have it
try:
    import ezdxf
except ImportError:
    pass

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_orthographic_vblock(traj, env_info, task_info):
    """
    Verify the V-Block drawing task.
    
    Criteria:
    1. DXF file exists and is valid (20 pts)
    2. File created during task (10 pts)
    3. Required layers exist (VISIBLE, HIDDEN, DIMENSIONS) (20 pts)
    4. Entities exist on HIDDEN layer (indicating hidden lines used) (15 pts)
    5. VLM: Confirms 3 views and general shape (35 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/vblock_projection.dxf')
    
    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)

    # Criterion 1 & 2: File Basics
    if output_exists and file_size > 500: # Empty DXF is usually very small, but headers take space. >500B implies some content
        score += 20
        feedback_parts.append("DXF file exists")
        if created_during:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp invalid")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing or empty"}

    # 3. DXF Structural Analysis via ezdxf
    dxf_score = 0
    dxf_feedback = []
    
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(expected_path, temp_dxf.name)
        
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            
            # Check Layers
            layers = [layer.dxf.name.upper() for layer in doc.layers]
            req_layers = ['VISIBLE', 'HIDDEN', 'DIMENSIONS']
            missing_layers = [l for l in req_layers if l not in layers]
            
            if not missing_layers:
                dxf_score += 20
                dxf_feedback.append("All required layers found")
            else:
                dxf_feedback.append(f"Missing layers: {', '.join(missing_layers)}")
                # Partial credit
                if 'VISIBLE' in layers: dxf_score += 5
                if 'HIDDEN' in layers: dxf_score += 5

            # Check Entities on HIDDEN layer
            hidden_entities = [e for e in msp if e.dxf.layer.upper() == 'HIDDEN']
            if len(hidden_entities) > 0:
                dxf_score += 15
                dxf_feedback.append(f"Found {len(hidden_entities)} hidden line entities")
            else:
                dxf_feedback.append("No entities found on HIDDEN layer")

        except Exception as e:
            dxf_feedback.append(f"DXF Parsing Error: {str(e)}")
            
    except Exception as e:
        dxf_feedback.append(f"Failed to retrieve DXF: {str(e)}")
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    score += dxf_score
    feedback_parts.extend(dxf_feedback)

    # 4. VLM Verification
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if final_screenshot:
        prompt = """
        You are verifying a technical drawing task in LibreCAD.
        The task is to draw a 3-view orthographic projection of a V-Block.
        
        Look for:
        1. Three distinct geometric views (Front, Top, Side).
        2. A "V" shape visible in one of the views.
        3. Dashed lines representing hidden features (usually blue or different style).
        4. Dimension lines with text.
        
        Answer with JSON:
        {
            "three_views_visible": boolean,
            "v_shape_visible": boolean,
            "dashed_lines_visible": boolean,
            "dimensions_visible": boolean,
            "overall_quality": "low"|"medium"|"high"
        }
        """
        
        # We use the frames + final to catch it if they closed the window or zoomed out too much at the end
        vlm_res = query_vlm(images=frames + [final_screenshot], prompt=prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('three_views_visible'): vlm_score += 10
            if parsed.get('v_shape_visible'): vlm_score += 10
            if parsed.get('dashed_lines_visible'): vlm_score += 10
            if parsed.get('dimensions_visible'): vlm_score += 5
            
            feedback_parts.append(f"Visual check: {vlm_score}/35 points")
        else:
            feedback_parts.append("VLM verification failed")
            
    score += vlm_score

    # Final Pass/Fail
    # Pass threshold: 70
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }