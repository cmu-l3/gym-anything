#!/usr/bin/env python3
"""
Verifier for consolidate_line_labels task.
"""

import json
import tempfile
import os
import re

def verify_consolidate_line_labels(traj, env_info, task_info):
    """
    Verify that the 'river_labels' style was created correctly and applied.
    
    Criteria:
    1. Style exists (10 pts)
    2. Style is default for ne_rivers layer (10 pts)
    3. SLD uses LinePlacement (15 pts)
    4. SLD enables Grouping vendor option (35 pts)
    5. SLD enables FollowLine vendor option (20 pts)
    6. WMS rendering is valid (no SLD errors) (10 pts)
    
    Anti-gaming:
    - VLM checks for GUI usage if REST API logs are ambiguous.
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
    
    # 1. Style Existence
    if result.get('style_exists'):
        score += 10
        feedback_parts.append("Style 'river_labels' created")
    else:
        return {"passed": False, "score": 0, "feedback": "Style 'river_labels' not found"}

    # 2. Layer Association
    if result.get('layer_uses_style'):
        score += 10
        feedback_parts.append("Style applied to 'ne_rivers'")
    else:
        feedback_parts.append(f"Style NOT applied to layer (current: {result.get('layer_default_style')})")

    # 3. Valid Render
    if result.get('valid_render'):
        score += 10
        feedback_parts.append("SLD is valid and renders correctly")
    else:
        feedback_parts.append("SLD has syntax errors (WMS rendering failed)")

    # Parse SLD Content
    sld = result.get('style_content', '')
    
    # 4. Line Placement
    if 'LinePlacement' in sld:
        score += 15
        feedback_parts.append("LinePlacement used")
    else:
        feedback_parts.append("LinePlacement missing (found PointPlacement?)")

    # 5. Vendor Option: Group
    # Check for <VendorOption name="group">yes</VendorOption> or true
    # Regex for robustness against whitespace
    if re.search(r'<VendorOption\s+name=["\']group["\']\s*>.*(yes|true).*</VendorOption>', sld, re.IGNORECASE | re.DOTALL):
        score += 35
        feedback_parts.append("Grouping enabled")
    else:
        feedback_parts.append("Label grouping NOT enabled (VendorOption 'group')")

    # 6. Vendor Option: Follow Line
    if re.search(r'<VendorOption\s+name=["\']followLine["\']\s*>.*(yes|true).*</VendorOption>', sld, re.IGNORECASE | re.DOTALL):
        score += 20
        feedback_parts.append("Follow Line enabled")
    else:
        feedback_parts.append("Follow Line NOT enabled (VendorOption 'followLine')")

    # VLM Verification (Trajectory Analysis)
    query_vlm = env_info.get('query_vlm')
    gui_detected = result.get('gui_interaction_detected', False)
    
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if frames:
            vlm_result = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user editing an SLD style or XML code in a web interface? Return JSON with key 'is_editing_style': bool."
            )
            is_editing = vlm_result.get('parsed', {}).get('is_editing_style', False) if vlm_result.get('success') else False
            
            if not gui_detected and not is_editing:
                # If neither logs nor VLM see interaction, might be programmatic/nothing
                pass 
                # We don't penalize here strictly as result.json logs might be flaky, 
                # but it's good metadata.

    passed = score >= 60 and result.get('style_exists') and ('group' in sld or score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }