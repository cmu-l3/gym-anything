#!/usr/bin/env python3
"""
Verifier for Register Custom Post Type via Code task.

This evaluates both system administration skills (editing PHP without crashing)
and WordPress content management skills (using the block editor).

Scoring (100 points total):
Programmatic (70 pts):
  - 10 pts: Site operational (HTTP 200, no PHP syntax errors)
  - 10 pts: CPT properly registered (`public` and `has_archive`)
  -  5 pts: REST API enabled (`show_in_rest` for Gutenberg)
  -  5 pts: Features configured (`supports` array)
  - 15 pts: Post created successfully in new CPT
  - 10 pts: Content & Excerpt correctly entered
  - 15 pts: Featured image attached
VLM (30 pts):
  - 15 pts: Trajectory shows file editing / code entry
  - 10 pts: Final state / Editor usage
  -  5 pts: Cross-validation

Pass threshold: 75 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing screenshots from an agent completing a WordPress development task.
The agent must edit `functions.php` to register a Custom Post Type, then use the WordPress admin to publish a post.

Assess the sequence:
1. CODE_EDITING_VISIBLE: Is a code editor or terminal (like nano, vim, or the WP Theme File Editor) visible editing `functions.php`?
2. WP_ADMIN_VISIBLE: Does the agent navigate the WordPress admin (specifically the new 'Portfolio Projects' menu)?
3. BLOCK_EDITOR_USED: Is the WordPress Block Editor (Gutenberg) visible being used to write the post or add a featured image?
4. NO_PLUGINS_USED: Verify the agent did NOT just use a plugin screen like "CPT UI" to make the post type (should use code).

Respond in JSON format:
{
    "code_editing_visible": true/false,
    "wp_admin_visible": true/false,
    "block_editor_used": true/false,
    "no_plugins_used": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of the WordPress task.

Assess:
1. SUCCESS_INDICATORS: Is there a "Post published" message, or is the new post visible in the list of Portfolio Projects?
2. ERROR_INDICATORS: Are there any PHP fatal errors, white screens of death, or warnings visible?

Respond in JSON format:
{
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_cpt_registration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'NASA Graphics Standards Manual Restoration')
    expected_excerpt = metadata.get('expected_excerpt', 'A comprehensive restoration of the 1975 NASA Graphics Standards Manual.')

    feedback_parts = []
    score = 0

    # 1. Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/cpt_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result read error: {e}"}

    # Anti-Gaming: Check if plugins were used
    active_plugins = result.get('active_plugins', '')
    if 'custom-post-type' in active_plugins.lower() or 'cpt' in active_plugins.lower():
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Prohibited plugin usage detected. CPT must be registered via code."
        }

    # 2. Evaluate Programmatic Criteria (70 points max)
    
    # 2a. HTTP Status (10 pts)
    http_status = result.get('http_status', '0')
    if http_status == "200":
        score += 10
        feedback_parts.append("Site operational (HTTP 200)")
    else:
        feedback_parts.append(f"Site CRASHED (HTTP {http_status}) - Check PHP syntax")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)} # Early exit if crashed

    # 2b. CPT Registered (10 pts) + REST (5 pts) + Features (5 pts)
    cpt = result.get('cpt_config', {})
    if cpt.get('exists'):
        if cpt.get('public') and cpt.get('has_archive'):
            score += 10
            feedback_parts.append("CPT registered correctly")
        else:
            feedback_parts.append("CPT exists but public/has_archive missing")

        if cpt.get('show_in_rest'):
            score += 5
            feedback_parts.append("REST API enabled")
        else:
            feedback_parts.append("REST API disabled (show_in_rest missing)")

        supports = cpt.get('supports', {})
        # check if it's a dict/object containing the keys
        if all(k in supports for k in ['title', 'editor', 'thumbnail', 'excerpt']):
            score += 5
            feedback_parts.append("All CPT features supported")
        else:
            feedback_parts.append("Missing required CPT features in 'supports'")
    else:
        feedback_parts.append("CPT 'portfolio' not found")

    # 2c. Post Created (15 pts) + Content (10 pts) + Image (15 pts)
    post = result.get('post_data', {})
    if post.get('found'):
        score += 15
        feedback_parts.append("Portfolio post found")
        
        # Check Title/Excerpt/Content
        actual_title = post.get('title', '')
        actual_excerpt = post.get('excerpt', '')
        content_len = post.get('content_length', 0)
        
        content_ok = False
        if expected_title.lower() in actual_title.lower():
            if expected_excerpt.lower() in actual_excerpt.lower() and content_len > 100:
                score += 10
                content_ok = True
                feedback_parts.append("Content & Excerpt correct")
            else:
                feedback_parts.append("Excerpt or Content incorrect")
        else:
            feedback_parts.append("Post title mismatch")

        # Check Thumbnail
        thumb_id = post.get('thumbnail_id', '0')
        try:
            if int(thumb_id) > 0:
                score += 15
                feedback_parts.append("Featured image attached")
            else:
                feedback_parts.append("Featured image missing")
        except ValueError:
            feedback_parts.append("Featured image missing")
            
    else:
        feedback_parts.append("No published portfolio post found")

    # 3. Evaluate VLM Criteria (30 points max)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Sample trajectory frames
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        if frames:
            proc_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            if proc_res:
                if proc_res.get('code_editing_visible'):
                    score += 7
                if proc_res.get('wp_admin_visible') and proc_res.get('block_editor_used'):
                    score += 8
                if not proc_res.get('no_plugins_used'):
                    score -= 20 # Penalty if VLM suspects they used a plugin UI
                    feedback_parts.append("VLM flagged potential plugin UI usage for CPT")
                else:
                    feedback_parts.append("VLM verified code editor workflow")
                    
        if final_frame:
            fin_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            if fin_res:
                if fin_res.get('success_indicators'):
                    score += 10
                    feedback_parts.append("VLM verified final success state")
                if fin_res.get('error_indicators'):
                    score -= 10
                    feedback_parts.append("VLM spotted visible errors")
    else:
        # If VLM is not available, we prorate or just grant the VLM points if programmatic is perfect
        # Since this relies heavily on VLM to verify the "how" (code vs plugin), 
        # but we did programmatic plugin checks, we can award proportional points.
        logger.info("VLM not available, scaling programmatic score.")
        score = int((score / 70.0) * 100)

    # 4. Final Assessment
    # Must get >= 75 points
    passed = score >= 75

    return {
        "passed": passed,
        "score": min(100, max(0, score)),
        "feedback": " | ".join(feedback_parts)
    }