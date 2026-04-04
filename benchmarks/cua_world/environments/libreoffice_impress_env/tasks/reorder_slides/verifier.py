#!/usr/bin/env python3
"""
Verifier for reorder_slides task.
Parses the presentation file to verify slide order.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, List

# Import environment verification utils
# We assume the utils are in the python path or relative
try:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
    from impress_verification_utils import parse_pptx_file, parse_odp_file, get_slide_title
except ImportError:
    # Fallback for local testing or different path structure
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorder_slides(traj, env_info, task_info):
    """
    Verify that the slides have been reordered correctly.
    
    Criteria:
    1. File exists and was modified (anti-gaming).
    2. File has exactly 6 slides.
    3. Slides are in the correct logical order based on titles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_titles = metadata.get('expected_titles', [])
    
    # 1. Retrieve Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file existence and modification
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found."}
    
    if not result_data.get('was_modified'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File was not saved/modified. You must save the changes (Ctrl+S)."
        }

    # 2. Retrieve the Presentation File
    file_path_in_env = result_data.get('file_path', '')
    ext = os.path.splitext(file_path_in_env)[1].lower()
    
    # We copied it to a standard location in export_result.sh to simplify
    # But let's check extension to decide parsing method
    temp_pres = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
    temp_pres.close() # Close so we can write to it via copy_from_env
    
    try:
        # Try copying from the temp location set in export script
        # Note: export script tries to copy to /tmp/verification_target.*
        target_name = "/tmp/verification_target" + ext
        copy_from_env(target_name, temp_pres.name)
        
        # Parse the file
        if ext == '.odp':
            parsed_data = parse_odp_file(temp_pres.name)
        else:
            # Default to PPTX
            parsed_data = parse_pptx_file(temp_pres.name)
            
        if 'error' in parsed_data:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse presentation: {parsed_data['error']}"}
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving presentation file: {str(e)}"}
    finally:
        if os.path.exists(temp_pres.name):
            os.unlink(temp_pres.name)

    # 3. Verify Content
    slides = parsed_data.get('slides', [])
    slide_count = len(slides)
    
    feedback_parts = []
    score = 0
    
    # Check Slide Count (10 pts)
    if slide_count == 6:
        score += 10
        feedback_parts.append("✅ Correct slide count (6)")
    else:
        feedback_parts.append(f"❌ Incorrect slide count: {slide_count} (expected 6)")
    
    # Check Modification (15 pts) - already checked boolean, awarding points
    score += 15
    feedback_parts.append("✅ File saved successfully")

    # Check Order (75 pts total, 12.5 per slide)
    correct_slides = 0
    
    for i, expected_title in enumerate(expected_titles):
        if i >= len(slides):
            break
            
        # Get actual title
        # parsed_data['slides'][i]['text_elements'][0] is usually title
        # We can also use 'text_elements' list generally
        text_elements = slides[i].get('text_elements', [])
        actual_title_text = text_elements[0] if text_elements else ""
        
        # Fuzzy match for title (ignore case and whitespace)
        # Using a keyword approach since extraction might vary
        keywords = expected_title.lower().split()
        # Filter small words
        keywords = [k for k in keywords if len(k) > 3]
        
        actual_lower = actual_title_text.lower()
        match = all(k in actual_lower for k in keywords)
        
        if match:
            score += 12.5
            correct_slides += 1
        else:
            # Try looking at the second element if first is empty
            if len(text_elements) > 1:
                actual_lower_2 = text_elements[1].lower()
                if all(k in actual_lower_2 for k in keywords):
                    score += 12.5
                    correct_slides += 1
                    continue
            
            # Debug feedback
            short_actual = (actual_title_text[:20] + '..') if len(actual_title_text) > 20 else actual_title_text
            # feedback_parts.append(f"Slide {i+1} mismatch") 
            # (Keeping feedback concise)

    feedback_parts.append(f"✅ Slides in correct position: {correct_slides}/6")

    final_score = min(100, int(score)) # Cap at 100 just in case
    
    # Pass threshold: 60 (Requires saving + correct count + at least 3 correct slides)
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "correct_positions": correct_slides,
            "slide_count": slide_count
        }
    }