#!/usr/bin/env python3
"""
Verifier for build_dynamic_landing_page task in WordPress.

Verification Strategy:
1. Programmatic database checks (70 pts):
   - Page exists and published (10 pts)
   - Media uploaded to site (10 pts)
   - Page content contains Cover block (10 pts)
   - Cover block contains "Explore the Wild" text (10 pts)
   - Page content contains Query Loop block (10 pts)
   - Query Loop filters by the "Travel" category ID (10 pts)
   - Settings configured to use this page as static front page (10 pts)
2. VLM Trajectory & Workflow checks (30 pts):
   - Frames show Block Editor active (15 pts)
   - Meaningful work was done manually (15 pts)

Pass Threshold: 80 points (Must get filter and static front page correct)
"""

import json
import tempfile
import os
import logging
import base64
import re

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


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


TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent building a landing page in WordPress.

The correct workflow involves:
1. Uploading an image to the Media Library.
2. Opening the Page Editor to create a new page.
3. Using the Block Editor (Gutenberg) to insert a Cover Block with an image and text overlay.
4. Inserting and configuring a Query Loop block to filter posts.
5. Setting the homepage in Settings > Reading or Site Editor.

Assess:
1. BLOCK_EDITOR_USED: Is the WordPress Block Editor (Gutenberg) visible being used in any frame?
2. MEDIA_INTERACTION: Is there evidence of the agent interacting with the Media Library or uploading an image?
3. SETTINGS_INTERACTION: Did the agent visit a settings menu (like Settings > Reading) or the Site Editor?
4. MEANINGFUL_PROGRESSION: Do the frames show a logical progression of completing these steps manually?

Respond in JSON format:
{
    "block_editor_used": true/false,
    "media_interaction": true/false,
    "settings_interaction": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_build_dynamic_landing_page(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load programmatic result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/build_dynamic_landing_page_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file missing/invalid: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Parse core data
    page_found = result.get('page_found', False)
    page_status = result.get('page_status', '')
    media_uploaded = result.get('media_uploaded', False)
    content_b64 = result.get('page_content_b64', '')
    show_on_front = result.get('show_on_front', '')
    page_on_front = str(result.get('page_on_front', '0'))
    page_id = str(result.get('page_id', '0'))
    travel_id = str(result.get('travel_category_id', 'X'))
    
    # Decode content
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore') if content_b64 else ''
    except Exception:
        content = ''

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================
    
    if page_found and page_status == 'publish':
        score += 10
        feedback_parts.append("Page created and published")
    else:
        feedback_parts.append("Page missing or not published")

    if media_uploaded:
        score += 10
        feedback_parts.append("Media uploaded")
    else:
        feedback_parts.append("Media missing")

    # Content block checks
    has_cover = False
    has_query = False
    has_hero_text = False
    has_filter = False

    if content:
        # Check Cover block
        if "wp:cover" in content:
            score += 10
            has_cover = True
            feedback_parts.append("Cover block found")
        else:
            feedback_parts.append("Cover block missing")

        # Check Hero Text
        if "Explore the Wild" in content and has_cover:
            score += 10
            has_hero_text = True
            feedback_parts.append("Hero text found")
        else:
            feedback_parts.append("Hero text missing")

        # Check Query Loop block
        if "wp:query" in content:
            score += 10
            has_query = True
            feedback_parts.append("Query block found")
        else:
            feedback_parts.append("Query block missing")

        # Check Taxonomy filter (Gutenberg stores query args in JSON inside the block comment)
        # We look for "category":[ID] anywhere in the content JSON payload
        cat_filter_pattern = rf'"category"\s*:\s*\[\s*{travel_id}\s*\]'
        if has_query and (re.search(cat_filter_pattern, content) or f"category={travel_id}" in content):
            score += 10
            has_filter = True
            feedback_parts.append(f"Query filtered by Travel category ({travel_id})")
        else:
            feedback_parts.append(f"Query filter for Travel ({travel_id}) missing")

    # Front page checks
    has_static_homepage = False
    if show_on_front == 'page' and page_on_front == page_id and page_id != '0':
        score += 10
        has_static_homepage = True
        feedback_parts.append("Static homepage configured correctly")
    else:
        feedback_parts.append(f"Homepage routing incorrect (show: {show_on_front}, page: {page_on_front} != expected: {page_id})")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        final_img = get_final_screenshot(traj)
        if frames and final_img:
            vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames + [final_img])
            if vlm_res:
                if vlm_res.get("block_editor_used"):
                    vlm_score += 15
                    feedback_parts.append("VLM confirmed block editor usage")
                if vlm_res.get("meaningful_progression"):
                    vlm_score += 15
                    feedback_parts.append("VLM confirmed meaningful workflow")
            else:
                feedback_parts.append("VLM analysis failed to parse")
        else:
            feedback_parts.append("Insufficient frames for VLM")
    else:
        # Grace points if VLM disabled
        vlm_score = 30
        feedback_parts.append("VLM disabled (grace points awarded)")
        
    score += vlm_score

    # Final pass logic
    # Must get >= 80 pts AND strictly required to have configured the filter and static homepage
    key_criteria_met = page_found and has_filter and has_static_homepage
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "page_id": page_id,
            "has_filter": has_filter,
            "has_static_homepage": has_static_homepage
        }
    }