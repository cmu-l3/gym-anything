#!/usr/bin/env python3
"""
Verifier for Create Organization Chart task.

Verification Strategy:
1. Parse the saved presentation (ODP or PPTX).
2. Check that the file was modified during the task.
3. Verify the presence of all 6 required names on Slide 3.
4. Verify sufficient shapes/connectors to constitute a chart.
5. VLM verification of the visual hierarchy using trajectory.
"""

import json
import tempfile
import os
import sys
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

# Import utils from environment
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from impress_verification_utils import (
        copy_and_parse_presentation,
        get_slide_count,
        verify_text_on_slide,
        count_shapes_on_slide,
        cleanup_verification_environment,
    )
except ImportError:
    # Fallback if running outside full environment context
    logging.warning("Could not import impress_verification_utils, using stubs or limited functionality")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_org_chart(traj, env_info, task_info):
    """
    Verify that the org chart was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_names = metadata.get('expected_names', [
        "Maria Chen", "David Park", "Lisa Thompson", 
        "Michael Brown", "Sarah Johnson", "Robert Garcia"
    ])
    
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

    # 2. Check File Existence & Modification (10 points)
    file_path = result.get('file_path')
    if not result.get('file_exists') or not file_path:
        return {"passed": False, "score": 0, "feedback": "No presentation file found"}
    
    if result.get('file_modified_during_task'):
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("Warning: File not modified (anti-gaming check)")

    # 3. Parse Presentation Content (60 points)
    # Determine format
    fmt = 'pptx' if file_path.endswith('.pptx') else 'odp'
    
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        file_path,
        copy_from_env,
        file_format=fmt
    )
    
    names_found_count = 0
    shape_count = 0
    slide_count = 0
    
    if success:
        # Check Slide Count (should remain 4)
        slide_count = get_slide_count(presentation)
        if slide_count == 4:
            score += 5
            feedback_parts.append("Structure preserved (4 slides)")
        else:
            feedback_parts.append(f"Slide count changed: {slide_count}")
            
        # Check Names on Slide 3 (Index 2)
        # Note: If slide count changed, try to find the "Leadership" slide
        target_slide_idx = 2
        
        # Verify names (45 points: 7.5 per name)
        for name in expected_names:
            if verify_text_on_slide(presentation, target_slide_idx, name, case_sensitive=False):
                names_found_count += 1
                score += 7.5
                
        feedback_parts.append(f"Names found: {names_found_count}/{len(expected_names)}")
        
        # Check Shapes (15 points)
        # We expect at least 6 shapes (boxes) + connectors
        shape_count = count_shapes_on_slide(presentation, target_slide_idx)
        # Note: Title is usually one shape.
        if shape_count >= 10:  # 6 boxes + connectors + title
            score += 15
            feedback_parts.append(f"Good shape density ({shape_count} objects)")
        elif shape_count >= 7: # Just the boxes + title
            score += 10
            feedback_parts.append(f"Basic shapes present ({shape_count} objects)")
        elif shape_count > 1:
            score += 5
            feedback_parts.append(f"Few shapes found ({shape_count})")
        
        cleanup_verification_environment(temp_dir)
    else:
        feedback_parts.append(f"Failed to parse file: {error}")

    # 4. VLM Verification (30 points)
    # Use trajectory frames to verify workflow and visual structure
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's work in LibreOffice Impress.
    The task was to create an Organizational Chart on Slide 3.
    
    Review the image sequence. 
    1. Did the agent use drawing tools (rectangles, lines/connectors)?
    2. Does the final slide show a hierarchical chart structure (boxes connected by lines)?
    3. Are there text labels inside the boxes?
    
    Respond in JSON:
    {
        "drawing_tools_used": boolean,
        "chart_structure_visible": boolean,
        "text_in_boxes": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(
        prompt=vlm_prompt,
        images=frames + [final_frame] if final_frame else frames
    )
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("drawing_tools_used"): vlm_score += 10
        if parsed.get("chart_structure_visible"): vlm_score += 10
        if parsed.get("text_in_boxes"): vlm_score += 10
        
        feedback_parts.append(f"VLM verification: {vlm_score}/30 pts")
    else:
        feedback_parts.append("VLM verification failed")
    
    score += vlm_score
    
    # Final cleanup
    score = min(100, int(score))
    # Pass if score >= 70 AND at least 4 names found (core requirement)
    passed = score >= 70 and names_found_count >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "names_found": names_found_count,
            "shape_count": shape_count,
            "file_modified": result.get('file_modified_during_task')
        }
    }