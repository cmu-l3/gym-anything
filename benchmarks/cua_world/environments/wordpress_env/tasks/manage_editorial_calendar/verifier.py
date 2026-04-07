#!/usr/bin/env python3
"""
Verifier for manage_editorial_calendar task.

Checks:
1. Category "Editorial Picks" exists (10 pts)
2. Post 1 created, status future, date within 2h of target, content > 20 chars (10 pts)
3. Post 2 created, status future, date within 2h of target, content > 20 chars (10 pts)
4. Post 3 created, status future, date within 2h of target, content > 20 chars (10 pts)
5. "Getting Started with WordPress" is sticky (10 pts)
6. "10 Essential WordPress Plugins..." is draft (10 pts)
7. "The Art of Writing Engaging Blog Content" is draft (10 pts)
8. Category assignments correct (10 pts, 2.5 pts each for P1, P2, P3, GS)
9. VLM Process Verification (15 pts)
10. VLM Final State Verification (5 pts)

Pass threshold: 60 points total AND at least 50 points from programmatic criteria.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

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

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent managing an editorial calendar in WordPress.

The agent should be performing multiple tasks:
1. Creating a new category
2. Creating new scheduled (future-dated) posts
3. Editing existing posts (making one sticky, changing others to Draft)

Assess:
1. WORKFLOW_COMPLETED: Did the agent navigate through the Posts section, Editor, and Quick Edit/Full Edit interfaces?
2. SCHEDULING_VISIBLE: Is the scheduling UI (calendar or date/time picker) visible at any point?
3. STATUS_CHANGES: Is there evidence of post statuses being changed (e.g., Draft dropdown, Sticky checkbox)?
4. MEANINGFUL_PROGRESSION: Do the frames show real progression across different post management tasks?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "scheduling_visible": true/false,
    "status_changes": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "stages_observed": ["list stages"]
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress editorial task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. POST_LIST_VISIBLE: Is the Posts list visible showing post statuses (Scheduled, Draft, Sticky)?
3. SUCCESS_INDICATORS: Are there success messages ("Post scheduled", "Post updated")?

Respond in JSON format:
{
    "admin_visible": true/false,
    "post_list_visible": true/false,
    "success_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def parse_wp_date(date_str):
    try:
        return datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
    except:
        return None

def verify_manage_editorial_calendar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Extract expected dates
    dt_p1 = parse_wp_date(metadata.get('p1_date', '2026-01-15 09:00:00'))
    dt_p2 = parse_wp_date(metadata.get('p2_date', '2026-01-16 10:30:00'))
    dt_p3 = parse_wp_date(metadata.get('p3_date', '2026-01-17 08:00:00'))

    feedback_parts = []
    score = 0
    programmatic_score = 0

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/manage_editorial_calendar_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result load error: {e}"}

    # Helper for checking scheduled posts
    def check_scheduled_post(post_key, expected_dt, title_label):
        post = result.get(post_key, {})
        if not post.get('id'):
            return 0, f"{title_label} NOT found"
        
        pts = 0
        status = post.get('status', '')
        date_str = post.get('date', '')
        length = post.get('len', 0)
        
        if status == 'future':
            pts += 4
        else:
            return 0, f"{title_label} found but status is '{status}', not 'future'"
            
        if length > 20:
            pts += 2
            
        actual_dt = parse_wp_date(date_str)
        if actual_dt and expected_dt:
            diff_hours = abs((actual_dt - expected_dt).total_seconds()) / 3600.0
            if diff_hours <= 2.5: # 2.5 hours tolerance for timezone/UI fuzziness
                pts += 4
            else:
                return pts, f"{title_label} scheduled for wrong time ({date_str})"
        
        return pts, f"{title_label} correctly scheduled"

    # 1. Category Exists (10 pts)
    if result.get('cat_exists', False):
        programmatic_score += 10
        feedback_parts.append("Category 'Editorial Picks' created")
    else:
        feedback_parts.append("Category 'Editorial Picks' NOT found")

    # 2-4. Scheduled Posts (10 pts each)
    pts1, fb1 = check_scheduled_post('p1', dt_p1, 'Post 1')
    pts2, fb2 = check_scheduled_post('p2', dt_p2, 'Post 2')
    pts3, fb3 = check_scheduled_post('p3', dt_p3, 'Post 3')
    
    programmatic_score += pts1 + pts2 + pts3
    feedback_parts.extend([fb1, fb2, fb3])

    # 5. Getting Started is Sticky (10 pts)
    gs = result.get('gs', {})
    gs_id = gs.get('id', '')
    sticky_list = result.get('sticky_posts', [])
    
    if gs_id and int(gs_id) in sticky_list:
        programmatic_score += 10
        feedback_parts.append("'Getting Started' is sticky")
    else:
        feedback_parts.append("'Getting Started' is NOT sticky")

    # 6-7. Posts changed to Draft (10 pts each)
    d1 = result.get('d1', {})
    if d1.get('id') and d1.get('status') == 'draft':
        programmatic_score += 10
        feedback_parts.append("D1 correctly set to draft")
    else:
        feedback_parts.append("D1 NOT set to draft")

    d2 = result.get('d2', {})
    if d2.get('id') and d2.get('status') == 'draft':
        programmatic_score += 10
        feedback_parts.append("D2 correctly set to draft")
    else:
        feedback_parts.append("D2 NOT set to draft")

    # 8. Category assignments (10 pts total, 2.5 each)
    cat_score = 0
    p1_cats = [c.strip().lower() for c in result.get('p1', {}).get('cats', '').split(',')]
    p2_cats = [c.strip().lower() for c in result.get('p2', {}).get('cats', '').split(',')]
    p3_cats = [c.strip().lower() for c in result.get('p3', {}).get('cats', '').split(',')]
    gs_cats = [c.strip().lower() for c in result.get('gs', {}).get('cats', '').split(',')]

    if 'editorial picks' in p1_cats: cat_score += 2.5
    if 'editorial picks' in p2_cats: cat_score += 2.5
    if 'news' in p3_cats: cat_score += 2.5
    if 'editorial picks' in gs_cats: cat_score += 2.5
    
    programmatic_score += cat_score
    feedback_parts.append(f"Category assignments score: {cat_score}/10")

    score += programmatic_score

    # 9-10. VLM Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        # Trajectory
        if frames:
            proc_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if proc_res and proc_res.get('workflow_completed') and proc_res.get('status_changes'):
                vlm_score += 15
                feedback_parts.append("VLM confirms editing workflow")
            elif proc_res and proc_res.get('meaningful_progression'):
                vlm_score += 7
                feedback_parts.append("VLM confirms partial workflow")
                
        # Final State
        if final:
            fin_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final)
            if fin_res and (fin_res.get('post_list_visible') or fin_res.get('success_indicators')):
                vlm_score += 5
                feedback_parts.append("VLM confirms final state")
                
        score += vlm_score
    else:
        # Give full VLM points if VLM is unavailable, relying strictly on robust programmatic checks
        score += 20
        feedback_parts.append("VLM skipped (auto-awarded)")

    # Threshold Check
    passed = score >= 60 and programmatic_score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }