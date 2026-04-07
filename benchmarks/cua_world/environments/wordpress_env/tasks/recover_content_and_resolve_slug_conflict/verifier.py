#!/usr/bin/env python3
import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent restoring a trashed WordPress post and fixing a URL slug conflict.

The agent should progress through these stages:
1. WordPress admin dashboard or Posts list visible
2. Navigating to the Trash and restoring a post
3. Editing a post (to fix the slug or add categories/tags)
4. Editing another post to add a hyperlink

Assess:
1. WORKFLOW_COMPLETED: Did the agent restore a post from the Trash and edit posts?
2. PAGE_EDITOR_VISIBLE: Is the WordPress post editor visible at some point?
3. MEANINGFUL_PROGRESSION: Do the frames show real state changes across different admin pages?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "page_editor_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_recover_content(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_slug = metadata.get('expected_slug', 'global-climate-report-2024')
    expected_category = metadata.get('expected_category', 'Featured Research')
    expected_tag = metadata.get('expected_tag', 'Climate Data')

    score = 0
    feedback_parts = []

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    orig_status = result.get('orig_status', '')
    orig_name = result.get('orig_name', '')
    draft_status = result.get('draft_status', '')
    draft_name = result.get('draft_name', '')
    orig_categories = result.get('orig_categories', '')
    orig_tags = result.get('orig_tags', '')
    post_2023_tags = result.get('post_2023_tags', '')
    post_2023_content = result.get('post_2023_content', '')

    # 1. Original Post Restored (10 pts)
    if orig_status == 'publish':
        score += 10
        feedback_parts.append("Original post restored and published")
    else:
        feedback_parts.append(f"Original post status is '{orig_status}', expected 'publish'")

    # 2. Slug Conflict Resolved (20 pts)
    slug_resolved = False
    if orig_name == expected_slug:
        score += 20
        slug_resolved = True
        feedback_parts.append("Slug conflict resolved successfully")
    else:
        feedback_parts.append(f"Original post slug is '{orig_name}', expected '{expected_slug}'")

    # 3. Intern Draft Handled (10 pts)
    if draft_status in ['deleted', 'trash'] or draft_name != expected_slug:
        score += 10
        feedback_parts.append("Intern draft handled correctly")
    else:
        feedback_parts.append("Intern draft still occupies target slug")

    # 4. Category Assignment (10 pts)
    orig_cat_list = [c.strip().lower() for c in orig_categories.split(',')]
    if expected_category.lower() in orig_cat_list:
        score += 10
        feedback_parts.append("Category assigned")
    else:
        feedback_parts.append(f"Category '{expected_category}' not found on original post")

    # 5. Tagging (15 pts)
    orig_tag_list = [t.strip().lower() for t in orig_tags.split(',')]
    post_2023_tag_list = [t.strip().lower() for t in post_2023_tags.split(',')]
    
    if expected_tag.lower() in orig_tag_list and expected_tag.lower() in post_2023_tag_list:
        score += 15
        feedback_parts.append("Tag 'Climate Data' assigned to both posts")
    else:
        feedback_parts.append("Tag 'Climate Data' missing from one or both posts")

    # 6. SEO Cross-link (15 pts)
    has_link = bool(re.search(r'href=[\'"][^\'"]*global-climate-report-2024/?[\'"]', post_2023_content, re.IGNORECASE))
    if has_link:
        score += 15
        feedback_parts.append("SEO cross-link added to 2023 post")
    else:
        feedback_parts.append("SEO cross-link missing from 2023 post")

    # 7. VLM Trajectory (20 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        if vlm_result:
            if vlm_result.get('workflow_completed'): vlm_score += 10
            if vlm_result.get('page_editor_visible'): vlm_score += 5
            if vlm_result.get('meaningful_progression'): vlm_score += 5
            feedback_parts.append(f"VLM score: {vlm_score}/20")
        else:
            feedback_parts.append("VLM query failed")
            vlm_score = 20 # Auto-pass if VLM error
    else:
        vlm_score = 20 # Auto-pass if VLM unavailable
        
    score += vlm_score

    passed = (score >= 75) and slug_resolved and (orig_status == 'publish')
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }