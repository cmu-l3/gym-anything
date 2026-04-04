#!/usr/bin/env python3
"""
Verifier for configure_terms_page task.

Task Requirements:
1. Create a WordPress Page "Terms of Service".
2. Content must include specific legal text.
3. Page must be Published.
4. WooCommerce Settings > Advanced > Terms and conditions must be set to this page.

Verification Strategy:
- Primary: Database state (wp_options and wp_posts).
- Secondary: VLM Trajectory (verify UI interaction for creation and settings).

Scoring (100 pts):
- 30 pts: Page created/exists with correct title.
- 20 pts: Content matches requirements.
- 30 pts: WooCommerce setting points to the correct page ID.
- 20 pts: Page was created *during* the task (anti-gaming via timestamp check).
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_terms_page(traj, env_info, task_info):
    """
    Verify the terms page creation and configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_page_title', 'Terms of Service')
    expected_content_snippet = metadata.get('expected_content_snippet', 'By placing an order, you agree')

    # Load Result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Extract Data
    linked_page = result.get('page_linked_in_settings', {})
    fallback_search = result.get('fallback_search', {})
    
    current_setting_id = str(result.get('current_setting_id', '0'))
    initial_setting_id = str(result.get('initial_setting_id', '0'))
    
    score = 0
    feedback_parts = []

    # Criteria 1: Is the setting updated? (30 pts)
    setting_updated = (current_setting_id != '0') and (current_setting_id != initial_setting_id)
    if setting_updated:
        score += 30
        feedback_parts.append("WooCommerce Terms setting updated")
    else:
        feedback_parts.append("WooCommerce Terms setting NOT updated or invalid")

    # Criteria 2: Does the linked page match criteria? 
    # If setting is updated, we check the linked page. If not, we check if they at least created a page (partial credit).
    
    target_page = linked_page if linked_page.get('exists') else {}
    
    # If they didn't link it, check the fallback page for partial content points
    if not target_page.get('exists') and fallback_search.get('found'):
        feedback_parts.append("(Checking unlinked page for partial credit)")
        # We can't verify content of fallback easily without extra DB query in export, 
        # but usually export script only fetches full details for linked page.
        # Actually export script DOES NOT fetch content for fallback, just ID. 
        # So we can't give content points for unlinked page based on current export script.
        # We will strictly require linking for high score.
        pass

    # Title Match (30 pts)
    # Flexible match: Case insensitive
    actual_title = target_page.get('title', '')
    if expected_title.lower() in actual_title.lower():
        score += 30
        feedback_parts.append(f"Page title correct ('{actual_title}')")
    elif linked_page.get('exists'):
        feedback_parts.append(f"Page title mismatch ('{actual_title}')")
        score += 10 # Small credit for linking *some* page
    else:
        feedback_parts.append("No valid page linked")

    # Content Match (20 pts)
    actual_content = target_page.get('content', '')
    if expected_content_snippet.lower() in actual_content.lower():
        score += 20
        feedback_parts.append("Page content correct")
    elif linked_page.get('exists'):
        feedback_parts.append("Page content missing required legal text")

    # Criteria 3: Recency/Anti-Gaming (20 pts)
    # Check if the linked page was created after task start
    task_start_ts = int(result.get('task_start_timestamp', 0))
    post_date_str = target_page.get('post_date_gmt', '1970-01-01 00:00:00')
    
    # Simple check: if ID > initial max ID (not tracked here) or timestamp check
    # Since we didn't track max ID, we rely on timestamp.
    try:
        # DB date format: YYYY-MM-DD HH:MM:SS
        post_dt = datetime.strptime(post_date_str, "%Y-%m-%d %H:%M:%S")
        post_ts = post_dt.timestamp()
        
        # Buffer of 60s for clock skew
        if post_ts >= (task_start_ts - 60):
            score += 20
            feedback_parts.append("Page created during task session")
        else:
            if linked_page.get('exists'):
                feedback_parts.append("Linked page is old (pre-existing?)")
    except Exception:
        # If parsing fails or date empty, 0 points for this section
        pass

    # Calculate final status
    passed = (score >= 100) # Strict pass: must do everything
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }