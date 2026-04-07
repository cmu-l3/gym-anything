#!/usr/bin/env python3
"""
Verifier for Apply Digital Collimation (Shutter) task.

Verification Strategy:
1. Validates that the expected JPEG file exists and was created during the task.
2. Programmatic Pixel Variance Analysis:
   - Evaluates the outer 10% edge boundaries of the exported image.
   - If a shutter was correctly applied, the outer edges become a solid color (usually black), resulting in near-zero variance.
   - Evaluates the center 40% of the image to confirm anatomy is still visible (high variance).
3. VLM Trajectory Verification: Confirms the agent's workflow using the UI tools.
"""

import os
import json
import logging
import tempfile
import numpy as np

# Import VLM utilities
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    pass # Handled gracefully if not in test environment

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_digital_collimation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    export_path = metadata.get('expected_output_path', '/home/ga/DICOM/exports/collimated_view.jpg')
    max_edge_variance = metadata.get('max_edge_variance', 50)
    min_center_variance = metadata.get('min_center_variance', 500)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
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

    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('file_size_bytes', 0)

    if file_exists and file_size > 1024:
        score += 15
        feedback_parts.append("Export file exists")
    else:
        feedback_parts.append("Export file missing or empty")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if file_created:
        score += 10
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("File timestamp invalid (pre-existed)")

    # 2. Analyze Pixel Variance
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    edge_masked = False
    center_visible = False
    try:
        copy_from_env(export_path, temp_img.name)
        
        # Load image via PIL to calculate variance
        from PIL import Image
        img = Image.open(temp_img.name).convert('L')
        img_array = np.array(img)
        h, w = img_array.shape
        
        # Outer 10% bounds
        h10, w10 = int(h * 0.10), int(w * 0.10)
        
        # Extract edges
        top_edge = img_array[0:h10, :]
        bottom_edge = img_array[h-h10:h, :]
        left_edge = img_array[:, 0:w10]
        right_edge = img_array[:, w-w10:w]
        
        edge_pixels = np.concatenate([top_edge.flatten(), bottom_edge.flatten(), left_edge.flatten(), right_edge.flatten()])
        edge_variance = np.var(edge_pixels)
        
        # Center 40% (From 30% to 70%)
        center_region = img_array[int(h*0.3):int(h*0.7), int(w*0.3):int(w*0.7)]
        center_variance = np.var(center_region)

        logger.info(f"Edge Variance: {edge_variance:.2f}, Center Variance: {center_variance:.2f}")

        if edge_variance < max_edge_variance:
            score += 30
            edge_masked = True
            feedback_parts.append(f"Edges masked (Var: {edge_variance:.1f})")
        else:
            feedback_parts.append(f"Edges NOT masked (Var: {edge_variance:.1f})")

        if center_variance > min_center_variance:
            score += 25
            center_visible = True
            feedback_parts.append(f"Center anatomy visible (Var: {center_variance:.1f})")
        else:
            feedback_parts.append(f"Center anatomy obscured (Var: {center_variance:.1f})")

    except Exception as e:
        logger.error(f"Image analysis failed: {e}")
        feedback_parts.append(f"Image analysis error")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # 3. VLM Verification
    vlm_passed = False
    try:
        if 'sample_trajectory_frames' in globals() and 'query_vlm' in globals():
            frames = sample_trajectory_frames(traj, n=5)
            prompt = """Look at this sequence of screenshots of a user interacting with Weasis DICOM viewer. 
            Did the user select and apply a 'Shutter' or 'Collimator' tool (often rectangular)?
            Respond ONLY with a JSON object: {"shutter_used": true/false}"""
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('shutter_used', False):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("VLM: Shutter workflow confirmed")
                else:
                    feedback_parts.append("VLM: Shutter workflow NOT detected")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")

    # To pass, they must hit at least 80 points AND successfully have low variance on the edges (indicating shutter)
    passed = score >= 80 and edge_masked

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }