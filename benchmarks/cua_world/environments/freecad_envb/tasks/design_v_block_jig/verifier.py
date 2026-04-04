#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_v_block_jig(traj, env_info, task_info):
    """
    Verifies the V-Block Design task.
    
    Criteria:
    1. File exists and valid FCStd (10 pts)
    2. Correct Bounding Box (60x60x40) (20 pts)
    3. Correct Volume (~129600 mm3) (30 pts)
    4. Geometric Features (V-faces detected) (10 pts)
    5. VLM Visual Confirmation (30 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Extract metrics
    analysis = result.get('analysis', {})
    bbox = analysis.get('bbox', [0, 0, 0])
    volume = analysis.get('volume', 0)
    
    feedback_parts = []
    score = 0
    
    # 2. File Verification (10 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File saved successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "File not saved or not created during task"}

    # 3. Geometric Verification
    
    # Bounding Box Check (20 pts)
    # Expected: 60x60x40. Order might vary depending on rotation, so we sort dimensions.
    expected_dims = sorted([60.0, 60.0, 40.0])
    actual_dims = sorted(bbox)
    
    # Tolerance 1mm
    dims_match = all(abs(e - a) < 1.0 for e, a in zip(expected_dims, actual_dims))
    
    if dims_match:
        score += 20
        feedback_parts.append("Dimensions correct (60x60x40)")
    else:
        feedback_parts.append(f"Dimensions incorrect: {actual_dims}")

    # Volume Check (30 pts)
    # Expected: 129,600 mm3
    # Tolerance: 2% (allow for minor meshing/segmentation diffs if any)
    target_vol = 129600
    tolerance = target_vol * 0.02
    
    if abs(volume - target_vol) < tolerance:
        score += 30
        feedback_parts.append("Volume correct (features properly subtracted)")
    elif volume > 140000:
        # Likely raw block without cuts
        score += 5
        feedback_parts.append("Volume too high - features likely missing")
    else:
        feedback_parts.append(f"Volume incorrect: {int(volume)} mm3 (Target: {target_vol})")

    # Feature Flag Check (10 pts)
    if analysis.get('has_v_groove_faces'):
        score += 10
        feedback_parts.append("V-groove geometry detected")
        
    # 4. VLM Verification (30 pts)
    # Check visual appearance
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Review this FreeCAD screenshot of a V-Block Jig design.
        I am looking for:
        1. A rectangular block.
        2. A V-shaped groove on the top face.
        3. Rectangular cutouts/slots on the sides.
        4. The object looks 3D and solid.
        
        Does the image show these features?
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_res.get('success'):
                # Simple keyword matching in reasoning or 'yes' check
                # Assuming vlm_res returns a structured 'parsed' or 'response'
                response_text = vlm_res.get('response', '').lower()
                
                # Check for positive confirmation
                if 'yes' in response_text or ('v-shaped' in response_text and 'slot' in response_text):
                    score += 30
                    feedback_parts.append("Visual verification passed")
                else:
                    score += 10 # Partial credit if image exists but VLM is unsure
                    feedback_parts.append("Visual verification inconclusive")
        except Exception:
            feedback_parts.append("VLM check failed")
    
    # Final Pass Logic
    # Strict pass: Dimensions correct AND Volume reasonably close
    passed = (dims_match and abs(volume - target_vol) < tolerance)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }