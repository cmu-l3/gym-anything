#!/usr/bin/env python3
"""
Verifier for create_printable_model task.

VERIFICATION CRITERIA:
1. STL File Verification (40 pts):
   - File must exist at expected path
   - File must be created/modified during task
   - File size must be significant (>5MB) indicating a real dental mesh

2. VLM Trajectory Verification (60 pts):
   - Verify surface generation (mesh appearing)
   - Verify base addition (solid block shape)
   - Verify text embossing ("CASE-992")
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_printable_model(traj, env_info, task_info):
    """
    Verify creation of a printable mandible model with embedded text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', 'CASE-992')
    min_size_mb = metadata.get('min_size_mb', 5)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. FILE-BASED VERIFICATION
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        feedback_parts.append("Failed to retrieve task result data")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    output_exists = result_data.get('output_exists', False)
    created_during_task = result_data.get('file_created_during_task', False)
    size_bytes = result_data.get('output_size_bytes', 0)
    size_mb = size_bytes / (1024 * 1024)

    if output_exists:
        if created_during_task:
            score += 20
            feedback_parts.append("✅ New STL file created")
            
            # Check complexity/validity via size
            if size_mb >= min_size_mb:
                score += 20
                feedback_parts.append(f"✅ File size valid ({size_mb:.1f} MB)")
            else:
                feedback_parts.append(f"⚠️ File too small ({size_mb:.1f} MB) - likely empty or incomplete")
        else:
            feedback_parts.append("❌ Output file exists but was not modified during task")
    else:
        feedback_parts.append("❌ No output STL file found")

    # ================================================================
    # 2. VLM VISUAL VERIFICATION
    # ================================================================
    # We check the final state and key trajectory moments
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # If no file was created, we can still give partial points for workflow if visible
    
    prompt = f"""
    You are verifying a dental 3D modeling task in Blue Sky Plan.
    The user was asked to:
    1. Generate a 3D surface of a mandible.
    2. Add a base to make it a solid block.
    3. Emboss the text "{required_text}" onto the model.
    
    Review the provided screenshots (trajectory and final state).
    
    Check for:
    1. [SURFACE] Is a 3D jaw/mandible surface visible? (Not just 2D slices)
    2. [BASE] Does the model have a flat base added to the bottom (making it a solid block)?
    3. [TEXT] Is the text "{required_text}" visible anywhere on the 3D model?
    
    Return JSON:
    {{
        "surface_visible": true/false,
        "base_added": true/false,
        "text_visible": true/false,
        "text_content_correct": true/false,
        "confidence": "high/medium/low"
    }}
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('surface_visible'):
            score += 20
            feedback_parts.append("✅ 3D Surface generation verified visually")
        else:
            feedback_parts.append("❌ No 3D surface seen")
            
        if parsed.get('base_added'):
            score += 20
            feedback_parts.append("✅ Base addition verified visually")
        else:
            feedback_parts.append("❌ No model base seen")
            
        if parsed.get('text_visible') and parsed.get('text_content_correct'):
            score += 20
            feedback_parts.append(f"✅ Text '{required_text}' verified visually")
        elif parsed.get('text_visible'):
            score += 10
            feedback_parts.append("⚠️ Text visible but content unclear")
        else:
            feedback_parts.append(f"❌ Text '{required_text}' not visible")
    else:
        feedback_parts.append("⚠️ VLM verification failed/unavailable")

    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Max Score: 40 (File) + 60 (Visual) = 100
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }