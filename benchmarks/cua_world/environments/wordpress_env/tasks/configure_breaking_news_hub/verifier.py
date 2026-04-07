#!/usr/bin/env python3
"""
Verifier for configure_breaking_news_hub task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) - from export script JSON inside container:
  1. Tagline updated exactly (7 pts)
  2. Category renamed and slug updated (10 pts)
  3. Post published (10 pts)
  4. Post made Sticky (18 pts)
  5. Post added to primary menu (10 pts)
  6. Menu item assigned 'breaking-pulse' CSS class (15 pts)

VLM checks (30 points) - using TRAJECTORY frames:
  7. Process verification (20 pts): Frames show agent navigating WP, opening Screen Options,
     creating menu item, making post sticky.
  8. Final state verification (10 pts): Visual confirmation of success.

Pass threshold: 70 points AND (Menu item added OR Post Sticky)
"""

import json
import tempfile
import os
import logging
import re

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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring a WordPress site for a breaking news event.

The agent should progress through these stages:
1. Updating Settings > General (Site Tagline)
2. Renaming a category in Posts > Categories
3. Editing a post to publish it and checking the "Stick to the top of the blog" box.
4. Editing Appearance > Menus, adding the post to the menu.
5. Crucially: Opening the "Screen Options" drawer at the top right of the Menus screen, checking "CSS Classes", and typing a class into the menu item field.

Assess:
1. MENU_AND_SCREEN_OPTIONS: Did the agent navigate to Appearance > Menus AND open Screen Options to enable CSS classes?
2. STICKY_POST_CHECKED: Is there evidence of the agent publishing the post and clicking the "Stick to the top" setting?
3. MULTI_SYSTEM_COORDINATION: Do the frames show the agent moving between at least 3 distinct WP systems (Settings, Categories, Posts, Menus)?

Respond in JSON format:
{
    "menu_and_screen_options": true/false,
    "sticky_post_checked": true/false,
    "multi_system_coordination": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress breaking news configuration task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. MENU_CONFIGURED: Are we looking at the Menus page with a new item added, OR another settings page showing success?
3. ERROR_INDICATORS: Are there any error messages or warnings visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "menu_configured": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""

def verify_configure_breaking_news_hub(traj, env_info, task_info):
    """
    Verify that the breaking news hub was correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tagline = metadata.get('expected_tagline', "Live Election Coverage 2026")
    expected_category_name = metadata.get('expected_category_name', "Breaking News")
    expected_category_slug = metadata.get('expected_category_slug', "breaking-news")
    expected_menu_class = metadata.get('expected_menu_class', "breaking-pulse")

    feedback_parts = []
    score = 0
    
    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_breaking_news_hub_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. Tagline (7 pts)
    tagline = result.get('tagline', '')
    if tagline == expected_tagline:
        score += 7
        feedback_parts.append("Tagline correct")
    else:
        feedback_parts.append(f"Tagline incorrect (expected '{expected_tagline}', got '{tagline}')")

    # 2. Category renamed (10 pts)
    cat_name = result.get('cat_name', '')
    cat_slug = result.get('cat_slug', '')
    if cat_name.lower() == expected_category_name.lower() and cat_slug.lower() == expected_category_slug.lower():
        score += 10
        feedback_parts.append("Category renamed correctly")
    elif cat_name.lower() == expected_category_name.lower():
        score += 5
        feedback_parts.append("Category name correct, but slug missing/wrong")
    else:
        feedback_parts.append("Category not renamed correctly")

    # 3. Post published (10 pts)
    post_id = result.get('post_id', '')
    post_status = result.get('post_status', '')
    post_published = (post_status == 'publish')
    
    if post_published:
        score += 10
        feedback_parts.append("Post published")
    else:
        feedback_parts.append("Post not published")

    # 4. Post made Sticky (18 pts)
    sticky_posts_raw = result.get('sticky_posts', '')
    is_sticky = False
    
    if post_id and str(post_id) in sticky_posts_raw:
        # Check if the ID string strictly exists as an array value in the serialized PHP array
        # e.g., i:42;
        if re.search(r'i:' + str(post_id) + r';', sticky_posts_raw):
            is_sticky = True
            
    if is_sticky:
        score += 18
        feedback_parts.append("Post is sticky")
    else:
        feedback_parts.append("Post is NOT sticky")

    # 5. Post added to menu (10 pts)
    menu_item_id = result.get('menu_item_id', '')
    menu_item_added = bool(menu_item_id)
    
    if menu_item_added:
        score += 10
        feedback_parts.append("Menu item added")
    else:
        feedback_parts.append("Post not added to menu")

    # 6. CSS Class applied to menu item (15 pts)
    menu_classes_raw = result.get('menu_classes', '')
    css_class_applied = expected_menu_class in menu_classes_raw
    
    if css_class_applied:
        score += 15
        feedback_parts.append("Menu item CSS class applied")
    elif menu_item_added:
        feedback_parts.append(f"Menu item missing CSS class '{expected_menu_class}'")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm and hasattr(traj, 'get_frames'):
        try:
            frames = traj.get_frames()
            if len(frames) > 0:
                sampled_frames = [frames[i] for i in range(0, len(frames), max(1, len(frames) // 5))][:5]
                
                # Check 1: Trajectory Process (20 pts)
                process_data = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames)
                if process_data:
                    vlm_score = 0
                    if process_data.get('menu_and_screen_options'): vlm_score += 10
                    if process_data.get('sticky_post_checked'): vlm_score += 5
                    if process_data.get('multi_system_coordination'): vlm_score += 5
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM process score: {vlm_score}/20")
                
                # Check 2: Final State (10 pts)
                final_frame = frames[-1]
                final_data = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
                if final_data and not final_data.get('error_indicators', False):
                    if final_data.get('admin_visible', False):
                        score += 10
                        feedback_parts.append("VLM final state verified")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification failed (skipped)")
    else:
        # Scale if VLM is completely unavailable to not penalize
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("Score scaled (VLM unavailable)")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    
    key_criteria_met = menu_item_added and is_sticky
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }