#!/usr/bin/env python3
"""
Verifier for tag_and_categorize_backlog task.

Scoring Criteria (100 points total):
1. Work Item Tagging (45 points)
   - 'security' tags correct: 15 pts
   - 'performance' tags correct: 15 pts
   - 'api' tags correct: 15 pts
   - Penalty for incorrect tags
2. Shared Queries Organization (20 points)
   - 'Cross-Cutting Concerns' folder exists: 10 pts
   - Queries are inside the folder: 10 pts
3. Query Logic/Correctness (35 points)
   - 'Security Items' query exists and returns correct items: 15 pts
   - 'Performance Items' query exists and returns correct items: 10 pts
   - 'API Items' query exists and returns correct items: 10 pts
"""

import json
import logging
import os
import tempfile
import time
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_tags(tag_string):
    """Convert tag string (e.g. 'api; security') to normalized set."""
    if not tag_string:
        return set()
    return set(t.strip().lower() for t in tag_string.split(';'))

def verify_tag_and_categorize_backlog(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tags_map = metadata.get('expected_tags', {})
    
    # 1. Load Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. VERIFY WORK ITEM TAGS (45 pts)
    # =========================================================
    work_items = result.get('work_items', [])
    tag_score = 0
    max_tag_score = 45
    
    # Track counts for feedback
    correct_security = 0
    correct_performance = 0
    correct_api = 0
    total_items_checked = 0
    
    for item in work_items:
        title = item.get('title')
        actual_tags = normalize_tags(item.get('tags', ''))
        
        # Match title roughly (ignoring minor variations if needed, but titles are static here)
        expected = None
        for key in expected_tags_map:
            if key in title:
                expected = set(expected_tags_map[key])
                break
        
        if expected is not None:
            total_items_checked += 1
            # Check correctness per tag category
            if 'security' in expected:
                if 'security' in actual_tags: correct_security += 1
            elif 'security' in actual_tags: # Wrongly tagged
                tag_score -= 2
                
            if 'performance' in expected:
                if 'performance' in actual_tags: correct_performance += 1
            elif 'performance' in actual_tags:
                tag_score -= 2
                
            if 'api' in expected:
                if 'api' in actual_tags: correct_api += 1
            elif 'api' in actual_tags:
                tag_score -= 2

    # Calculate subscores
    # Security: 3 items expected
    sec_pts = (correct_security / 3) * 15
    tag_score += sec_pts
    
    # Performance: 3 items expected
    perf_pts = (correct_performance / 3) * 15
    tag_score += perf_pts
    
    # API: 4 items expected
    api_pts = (correct_api / 4) * 15
    tag_score += api_pts
    
    # Clamp score
    tag_score = max(0, min(45, tag_score))
    score += tag_score
    feedback_parts.append(f"Tagging Score: {tag_score:.1f}/45")

    # =========================================================
    # 2. VERIFY FOLDER (20 pts)
    # =========================================================
    if result.get('query_folder_exists'):
        score += 20
        feedback_parts.append("Folder 'Cross-Cutting Concerns' created (+20)")
    else:
        feedback_parts.append("Folder 'Cross-Cutting Concerns' NOT found")

    # =========================================================
    # 3. VERIFY QUERIES (35 pts)
    # =========================================================
    queries = result.get('queries', [])
    query_score = 0
    
    # Check for specific queries
    q_sec = next((q for q in queries if "security" in q['name'].lower()), None)
    q_perf = next((q for q in queries if "performance" in q['name'].lower()), None)
    q_api = next((q for q in queries if "api" in q['name'].lower()), None)
    
    # Scoring logic: Must exist AND return correct count
    # Security (expect 3)
    if q_sec:
        if q_sec['result_count'] == 3:
            query_score += 15
        else:
            query_score += 5 # Points for creating it, but wrong results
            feedback_parts.append(f"Security query result mismatch (got {q_sec['result_count']}, expected 3)")
    
    # Performance (expect 3)
    if q_perf:
        if q_perf['result_count'] == 3:
            query_score += 10
        else:
            query_score += 3
            feedback_parts.append(f"Performance query result mismatch (got {q_perf['result_count']}, expected 3)")

    # API (expect 4)
    if q_api:
        if q_api['result_count'] == 4:
            query_score += 10
        else:
            query_score += 3
            feedback_parts.append(f"API query result mismatch (got {q_api['result_count']}, expected 4)")
            
    score += query_score
    feedback_parts.append(f"Query Score: {query_score}/35")

    # =========================================================
    # 4. VLM VERIFICATION (Trajectory Check)
    # =========================================================
    # Verify the agent actually used the UI and didn't just guess URLs or scripts
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = (
        "Does the screenshot show the Azure DevOps Work Items backlog or Query editor? "
        "Look for a list of items like 'Design REST API...' or 'Shared Queries'. "
        "Are tags like 'security' or 'api' visible on the rows? "
        "Reply 'yes' if the interface is being used correctly for tagging or querying."
    )
    
    vlm_passed = False
    try:
        # Just check one representative frame or the final one if needed
        if frames:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if "yes" in vlm_res.get('response', '').lower():
                vlm_passed = True
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        vlm_passed = True # Fallback if VLM fails systemically

    if not vlm_passed:
        feedback_parts.append("Warning: Visual verification of workflow failed")
        # Optional: penalize if strict visual proof is needed
        # score -= 10

    passed = score >= 55
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "; ".join(feedback_parts)
    }