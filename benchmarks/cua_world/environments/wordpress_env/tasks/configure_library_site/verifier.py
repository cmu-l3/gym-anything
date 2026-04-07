#!/usr/bin/env python3
"""
Verifier for configure_library_site task.

Verifies:
1. 6 required pages exist with correct content states
2. Reading Settings (static front page mapping)
3. Navigation Menu creation and primary assignment
4. VLM validation of trajectory (to prevent API manipulation shortcuts)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

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

TRAJECTORY_PROMPT = """You are evaluating a sequence of screenshots from an agent setting up a WordPress library website.

The correct workflow involves:
1. Creating multiple Pages (Add New Page, using the WordPress editor)
2. Changing Reading Settings (Settings > Reading) to set a static front page
3. Creating a Navigation Menu (Appearance > Menus)

Assess:
1. WORKFLOW_PAGES: Is the WordPress page editor visible at least once?
2. WORKFLOW_SETTINGS: Is the WordPress "Reading Settings" screen visible?
3. WORKFLOW_MENUS: Is the WordPress "Menus" screen visible?
4. GENUINE_WORK: Does this look like a human/agent actively working in the browser (not just a script)?

Respond strictly in JSON:
{
    "workflow_pages": true/false,
    "workflow_settings": true/false,
    "workflow_menus": true/false,
    "genuine_work": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_configure_library_site(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load initial state
    initial_state = {}
    try:
        temp_init = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/initial_state.json", temp_init.name)
        with open(temp_init.name, 'r') as f:
            initial_state = json.load(f)
        os.unlink(temp_init.name)
    except Exception as e:
        logger.warning(f"Could not load initial state: {e}")

    # Load final state
    result = {}
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data safely
    pages = result.get('pages', [])
    show_on_front = result.get('show_on_front', '')
    page_on_front = result.get('page_on_front', '0')
    page_for_posts = result.get('page_for_posts', '0')
    menus = result.get('menus', [])
    locations = result.get('nav_menu_locations', {})

    # Match utility for pages
    def find_page(title_substring):
        sub = title_substring.lower()
        for p in pages:
            if sub in p.get('post_title', '').lower():
                return p
        return None

    # ==========================================
    # 1. PAGE CHECKS (33 points)
    # ==========================================
    expected_pages = [
        ("Welcome to Greenfield Library", 8, True),
        ("Library News", 5, False),
        ("Catalog", 5, True),
        ("Digital Collections", 5, True),
        ("Events & Programs", 5, True), # Accept Variations
        ("About Us", 5, True)
    ]

    pages_found = 0
    welcome_id = None
    news_id = None

    for title, points, needs_content in expected_pages:
        # Handle ampersand vs "and" variations safely
        search_title = title.replace("&", "").replace("and", "").strip()
        p = find_page(search_title)
        
        if p:
            if title == "Welcome to Greenfield Library":
                welcome_id = str(p['ID'])
            elif title == "Library News":
                news_id = str(p['ID'])

            content_len = len(p.get('post_content', '').strip())
            if needs_content and content_len < 10:
                score += (points // 2)
                feedback_parts.append(f"Page '{title}' created but lacks content")
                pages_found += 1
            else:
                score += points
                feedback_parts.append(f"Page '{title}' verified")
                pages_found += 1
        else:
            feedback_parts.append(f"Missing page: '{title}'")

    # Anti-gaming: Ensure pages were actually created during task
    initial_page_ids = {str(p['ID']) for p in initial_state.get('pages', [])}
    current_page_ids = {str(p['ID']) for p in pages}
    new_pages = current_page_ids - initial_page_ids
    if len(new_pages) == 0:
        return {"passed": False, "score": 0, "feedback": "No new pages were created during this task session (Gaming attempt detected)."}

    # ==========================================
    # 2. READING SETTINGS CHECKS (30 points)
    # ==========================================
    static_front_ok = False
    
    if show_on_front == 'page':
        score += 10
        static_front_ok = True
        feedback_parts.append("Static front page enabled")
    else:
        feedback_parts.append(f"Front page not static (is '{show_on_front}')")

    if welcome_id and str(page_on_front) == welcome_id:
        score += 10
        feedback_parts.append("Homepage set to Welcome page")
    else:
        feedback_parts.append("Homepage not set correctly")

    if news_id and str(page_for_posts) == news_id:
        score += 10
        feedback_parts.append("Posts page set to Library News")
    else:
        feedback_parts.append("Posts page not set correctly")

    # ==========================================
    # 3. MENU CHECKS (27 points)
    # ==========================================
    target_menu = None
    for m in menus:
        if "main navigation" in m.get('name', '').lower():
            target_menu = m
            break

    if target_menu:
        score += 7
        feedback_parts.append("Main Navigation menu exists")
        
        menu_items = target_menu.get('items', [])
        # We need at least 5 page items
        page_items = [i for i in menu_items if i.get('object') == 'page']
        
        if len(page_items) >= 5:
            score += 10
            feedback_parts.append(f"Menu has sufficient items ({len(page_items)})")
        elif len(page_items) >= 3:
            score += 5
            feedback_parts.append(f"Menu has partial items ({len(page_items)})")
        else:
            feedback_parts.append("Menu lacks required page items")

        # Location check
        primary_menu_id = str(locations.get('primary', ''))
        if primary_menu_id == str(target_menu.get('term_id')):
            score += 10
            feedback_parts.append("Menu assigned to Primary location")
        else:
            feedback_parts.append("Menu not assigned to Primary location")
    else:
        feedback_parts.append("Main Navigation menu not found")

    # ==========================================
    # 4. VLM TRAJECTORY CHECK (10 points)
    # ==========================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if vlm_res:
            active_workflows = 0
            if vlm_res.get('workflow_pages'): active_workflows += 1
            if vlm_res.get('workflow_settings'): active_workflows += 1
            if vlm_res.get('workflow_menus'): active_workflows += 1
            
            if active_workflows >= 2 and vlm_res.get('genuine_work'):
                score += 10
                feedback_parts.append("VLM verified genuine UI workflow")
            else:
                feedback_parts.append("VLM found insufficient workflow evidence")
        else:
            # Fallback if VLM fails but programmatic score is high
            if score >= 60:
                score += 10
                feedback_parts.append("VLM unavailable, auto-crediting trajectory based on high state score")
    else:
        if score >= 60:
            score += 10
            feedback_parts.append("VLM unavailable, auto-crediting trajectory")

    # Final pass logic
    passed = score >= 70 and static_front_ok and pages_found >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }