#!/usr/bin/env python3
"""
Verifier for create_map_layout task.
Evaluates the exported PNG map layout for required cartographic elements.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_map_layout(traj, env_info, task_info):
    """
    Verifies the map layout creation task.
    
    Scoring Breakdown (100 pts total):
    - 20 pts: Output file exists and is a valid image > 50KB
    - 5 pts: File created during task (anti-gaming timestamp)
    - 10 pts: Image dimensions reasonable (>= 800x600)
    - 65 pts: VLM Content Verification
        - 15 pts: Map view visible (countries/shapes)
        - 15 pts: Title "World Countries Map" visible
        - 15 pts: Legend visible
        - 10 pts: Scale Bar visible
        - 10 pts: North Arrow visible
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title_text', "World Countries Map")
    min_size_kb = metadata.get('min_file_size_kb', 50)

    score = 0
    feedback_parts = []
    
    # 1. RETRIEVE METADATA
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    # 2. CHECK FILE EXISTENCE & SPECS (35 pts total)
    file_exists = result_data.get("file_exists", False)
    valid_image = result_data.get("is_valid_image", False)
    file_size = result_data.get("file_size_bytes", 0)
    created_during = result_data.get("file_created_during_task", False)
    width = result_data.get("image_width", 0)
    height = result_data.get("image_height", 0)

    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Exported PNG file not found at expected path."}

    # Size check (20 pts)
    if valid_image and file_size > (min_size_kb * 1024):
        score += 20
        feedback_parts.append("Valid output file found.")
    else:
        feedback_parts.append(f"File exists but seems invalid or empty ({file_size} bytes).")

    # Timestamp check (5 pts)
    if created_during:
        score += 5
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this task.")

    # Dimension check (10 pts)
    if width >= 800 and height >= 600:
        score += 10
        feedback_parts.append(f"Resolution sufficient ({width}x{height}).")
    else:
        feedback_parts.append(f"Resolution too low ({width}x{height}).")

    # 3. VLM CONTENT VERIFICATION (65 pts)
    # We prioritize checking the actual exported image artifact
    
    # Retrieve the exported image
    exported_img_path = None
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as img_f:
        exported_img_path = img_f.name
    
    try:
        copy_from_env("/tmp/exported_map.png", exported_img_path)
        
        # Construct VLM prompt
        prompt = f"""
        Analyze this exported map image. I need to verify if it contains specific cartographic elements.
        
        Please check for:
        1. MAP CONTENT: Are there geographic shapes/countries visible?
        2. TITLE: Is the text "{expected_title}" visible?
        3. LEGEND: Is there a legend box explaining the map symbols?
        4. SCALE BAR: Is there a scale bar (ruler showing distance)?
        5. NORTH ARROW: Is there a compass or north arrow?
        
        Return a JSON object with boolean keys:
        {{
            "has_map_content": true/false,
            "has_correct_title": true/false,
            "has_legend": true/false,
            "has_scale_bar": true/false,
            "has_north_arrow": true/false
        }}
        """
        
        # Query VLM with the exported image
        vlm_response = query_vlm(
            images=[exported_img_path], 
            prompt=prompt,
            return_json=True
        )
        
        # Parse VLM Response
        if vlm_response:
            if vlm_response.get("has_map_content"):
                score += 15
                feedback_parts.append("Map content visible.")
            else:
                feedback_parts.append("Map content missing or unclear.")
                
            if vlm_response.get("has_correct_title"):
                score += 15
                feedback_parts.append(f"Title '{expected_title}' verified.")
            else:
                feedback_parts.append("Title missing or incorrect.")
                
            if vlm_response.get("has_legend"):
                score += 15
                feedback_parts.append("Legend found.")
            else:
                feedback_parts.append("Legend missing.")
                
            if vlm_response.get("has_scale_bar"):
                score += 10
                feedback_parts.append("Scale bar found.")
            else:
                feedback_parts.append("Scale bar missing.")
                
            if vlm_response.get("has_north_arrow"):
                score += 10
                feedback_parts.append("North arrow found.")
            else:
                feedback_parts.append("North arrow missing.")
        else:
            feedback_parts.append("Visual verification failed (no response).")
            
    except Exception as e:
        feedback_parts.append(f"Visual verification error: {str(e)}")
    finally:
        if exported_img_path and os.path.exists(exported_img_path):
            os.unlink(exported_img_path)

    # 4. TRAJECTORY CHECK (Backup if file check ambiguous, or just to confirm effort)
    # If the file verification failed completely (e.g., black image), we could check frames,
    # but for "Create Output" tasks, the output is the primary truth. 
    # We will assume if score > 50, the agent made a serious attempt.
    
    passed = score >= 60 and created_during
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }