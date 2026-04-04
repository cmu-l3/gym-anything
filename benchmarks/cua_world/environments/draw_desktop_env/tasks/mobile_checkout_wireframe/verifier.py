#!/usr/bin/env python3
"""
Verifier for mobile_checkout_wireframe task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_mobile_checkout_wireframe(traj, env_info, task_info):
    """
    Verify the creation of a mobile checkout wireframe.
    
    Criteria:
    1. .drawio file created and modified (10 pts)
    2. PNG export exists and is not empty (10 pts)
    3. Structural Complexity: >15 shapes, >2 edges (15 pts)
    4. Mobile Context: At least 3 phone/mobile frame shapes detected (25 pts)
    5. Content Accuracy: Keywords for Cart, Payment, and Success screens (40 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result
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
    
    # 1. File Check (10 pts)
    if result.get('drawio_exists') and result.get('drawio_modified'):
        score += 10
        feedback_parts.append("Drawio file saved")
    else:
        feedback_parts.append("Drawio file missing or unchanged")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. PNG Check (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback_parts.append("PNG exported")
    else:
        feedback_parts.append("PNG missing or empty")

    # 3. Structure Check (15 pts)
    shape_count = result.get('shape_count', 0)
    edge_count = result.get('edge_count', 0)
    
    if shape_count >= 10:
        score += 10
        feedback_parts.append(f"Structure OK ({shape_count} shapes)")
    else:
        feedback_parts.append(f"Too simple ({shape_count} shapes)")
        
    if edge_count >= 2:
        score += 5
        feedback_parts.append("Flow arrows found")
    else:
        feedback_parts.append("No flow arrows found")

    # 4. Mobile Context (25 pts)
    # The agent should use phone frames.
    phone_frames = result.get('phone_frames_found', 0)
    if phone_frames >= 3:
        score += 25
        feedback_parts.append(f"3+ Phone frames found ({phone_frames})")
    elif phone_frames >= 1:
        score += 10
        feedback_parts.append(f"Partial phone frames ({phone_frames})")
    else:
        # Fallback: if structure is very high, maybe they drew manual rectangles?
        if shape_count > 30:
            score += 5
            feedback_parts.append("No specific phone shapes found, but complex diagram")
        else:
            feedback_parts.append("No phone frame shapes detected (use Mockups/Mobile library)")

    # 5. Content Verification (40 pts)
    all_text = result.get('all_text', '').lower()
    
    # Screen 1 Keywords
    s1_keys = metadata.get('keywords_screen1', [])
    s1_hits = sum(1 for k in s1_keys if k in all_text)
    
    # Screen 2 Keywords
    s2_keys = metadata.get('keywords_screen2', [])
    s2_hits = sum(1 for k in s2_keys if k in all_text)
    
    # Screen 3 Keywords
    s3_keys = metadata.get('keywords_screen3', [])
    s3_hits = sum(1 for k in s3_keys if k in all_text)
    
    # Scoring content
    # We want roughly half keywords to get points
    if s1_hits >= 3: score += 10
    elif s1_hits >= 1: score += 5
    
    if s2_hits >= 3: score += 10
    elif s2_hits >= 1: score += 5
    
    if s3_hits >= 2: score += 10
    elif s3_hits >= 1: score += 5
    
    # Bonus for specific accuracy
    total_hits = s1_hits + s2_hits + s3_hits
    if total_hits >= 10:
        score += 10
        feedback_parts.append(f"High content accuracy ({total_hits} matches)")
    else:
        feedback_parts.append(f"Content accuracy: {total_hits} keyword matches")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }