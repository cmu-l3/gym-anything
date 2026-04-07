#!/usr/bin/env python3
"""
Verifier for Schedule Content Series task in WordPress.

Verification Strategy:
1. Programmatic Checks (90 points):
    - Post 1: Found (5), Scheduled (8), Correct Date (7), Category (5) = 25 pts
    - Post 2: Found (5), Scheduled (8), Correct Date (7), Category (5) = 25 pts
    - Post 3: Found (5), Scheduled (8), Correct Date (7), Category (5) = 25 pts
    - Tags correctly applied across all 3 posts (10 pts)
    - Substantive content length for all 3 posts (5 pts)
2. VLM Trajectory (10 points):
    - Verify visual evidence of navigating the editor and scheduling panel

Pass threshold: Score >= 60 AND at least 2 posts successfully scheduled (status='future')
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_date(date_str, target_date_str):
    """Check if the scheduled date matches the target date within a 1-hour tolerance."""
    if not date_str:
        return False
    try:
        dt = datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
        target = datetime.strptime(target_date_str, "%Y-%m-%d %H:%M:%S")
        diff = abs((dt - target).total_seconds())
        return diff <= 3600  # 1 hour tolerance
    except Exception as e:
        logger.warning(f"Date parsing error: {e}")
        return False

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent scheduling blog posts in WordPress.

Assess:
1. EDITOR_USED: Did the agent open the WordPress post editor (Gutenberg or Classic)?
2. SCHEDULE_PANEL_USED: Is there evidence of the agent interacting with the date/time picker to schedule a post for a future date (e.g., clicking on the 'Publish: Immediately' link to change it, or adjusting the calendar)?
3. POSTS_LIST_VISIBLE: Did the agent view the 'All Posts' list showing 'Scheduled' indicators?

Respond in JSON format:
{
    "editor_used": true/false,
    "schedule_panel_used": true/false,
    "posts_list_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_schedule_content_series(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/schedule_content_series_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    score = 0
    feedback_parts = []
    scheduled_count = 0

    # Evaluate Post 1
    p1 = metadata.get('post1', {})
    if result.get('p1_found', False):
        score += 5
        feedback_parts.append("Post 1 found")
        if result.get('p1_status') == 'future':
            score += 8
            scheduled_count += 1
            feedback_parts.append("Post 1 is 'future'")
        else:
            feedback_parts.append(f"Post 1 status wrong: {result.get('p1_status')}")
            
        if check_date(result.get('p1_date'), p1.get('date')):
            score += 7
            feedback_parts.append("Post 1 date correct")
        else:
            feedback_parts.append(f"Post 1 date wrong: {result.get('p1_date')}")
            
        if p1.get('category') in result.get('p1_cats', ''):
            score += 5
            feedback_parts.append("Post 1 category correct")
        else:
            feedback_parts.append(f"Post 1 category wrong: {result.get('p1_cats')}")
    else:
        feedback_parts.append("Post 1 NOT found")

    # Evaluate Post 2
    p2 = metadata.get('post2', {})
    if result.get('p2_found', False):
        score += 5
        feedback_parts.append("Post 2 found")
        if result.get('p2_status') == 'future':
            score += 8
            scheduled_count += 1
            feedback_parts.append("Post 2 is 'future'")
        else:
            feedback_parts.append(f"Post 2 status wrong: {result.get('p2_status')}")
            
        if check_date(result.get('p2_date'), p2.get('date')):
            score += 7
            feedback_parts.append("Post 2 date correct")
        else:
            feedback_parts.append(f"Post 2 date wrong: {result.get('p2_date')}")
            
        if p2.get('category') in result.get('p2_cats', ''):
            score += 5
            feedback_parts.append("Post 2 category correct")
        else:
            feedback_parts.append(f"Post 2 category wrong: {result.get('p2_cats')}")
    else:
        feedback_parts.append("Post 2 NOT found")

    # Evaluate Post 3
    p3 = metadata.get('post3', {})
    if result.get('p3_found', False):
        score += 5
        feedback_parts.append("Post 3 found")
        if result.get('p3_status') == 'future':
            score += 8
            scheduled_count += 1
            feedback_parts.append("Post 3 is 'future'")
        else:
            feedback_parts.append(f"Post 3 status wrong: {result.get('p3_status')}")
            
        if check_date(result.get('p3_date'), p3.get('date')):
            score += 7
            feedback_parts.append("Post 3 date correct")
        else:
            feedback_parts.append(f"Post 3 date wrong: {result.get('p3_date')}")
            
        if p3.get('category') in result.get('p3_cats', ''):
            score += 5
            feedback_parts.append("Post 3 category correct")
        else:
            feedback_parts.append(f"Post 3 category wrong: {result.get('p3_cats')}")
    else:
        feedback_parts.append("Post 3 NOT found")

    # Check tags across all posts (10 pts)
    tags_correct = True
    if result.get('p1_found'):
        tags_correct &= all(t in result.get('p1_tags', '') for t in p1.get('tags', []))
    if result.get('p2_found'):
        tags_correct &= all(t in result.get('p2_tags', '') for t in p2.get('tags', []))
    if result.get('p3_found'):
        tags_correct &= all(t in result.get('p3_tags', '') for t in p3.get('tags', []))
        
    if tags_correct and scheduled_count > 0:
        score += 10
        feedback_parts.append("Tags correct across posts")
    else:
        feedback_parts.append("Tags missing or incorrect")

    # Check content lengths (5 pts)
    lengths_ok = True
    for p in ['p1', 'p2', 'p3']:
        if result.get(f'{p}_found', False) and result.get(f'{p}_len', 0) < 100:
            lengths_ok = False
            
    if lengths_ok and scheduled_count > 0:
        score += 5
        feedback_parts.append("Content length OK")
    else:
        feedback_parts.append("Content length insufficient")

    # VLM Evaluation (10 pts)
    query_vlm = env_info.get("query_vlm")
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if vlm_res:
            if vlm_res.get('editor_used', False):
                score += 5
            if vlm_res.get('schedule_panel_used', False):
                score += 5
                feedback_parts.append("VLM confirmed schedule panel use")
            elif vlm_res.get('posts_list_visible', False):
                score += 5
                feedback_parts.append("VLM confirmed posts list interaction")
    else:
        # Give grace points if VLM is unavailable
        score += 10

    # Ensure score doesn't exceed 100
    score = min(100, score)

    # Pass logic
    passed = score >= 60 and scheduled_count >= 2
    if passed:
        feedback_parts.insert(0, f"SUCCESS (Score: {score})")
    else:
        feedback_parts.insert(0, f"FAILED (Score: {score})")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }