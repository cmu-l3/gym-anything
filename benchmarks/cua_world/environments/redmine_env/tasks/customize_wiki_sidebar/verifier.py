#!/usr/bin/env python3
"""
Verifier for customize_wiki_sidebar task.
Verifies that the Sidebar page exists, contains the correct links,
and that the linked pages were created.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_wiki_sidebar(traj, env_info, task_info):
    """
    Verify the wiki sidebar creation and linking.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract db state
    db_state = result.get('db_state', {})
    if db_state.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Database verification failed: {db_state['error']}"}

    sidebar_info = db_state.get('sidebar_page', {})
    target_pages = db_state.get('target_pages', {})
    task_start = result.get('task_start', 0)

    score = 0
    feedback = []

    # 2. Scoring Criteria

    # CRITERION 1: Sidebar Page Exists (20 pts)
    # The page must be named exactly "Sidebar" for Redmine to treat it as a sidebar.
    if sidebar_info.get('exists'):
        score += 20
        feedback.append("Sidebar page created")
        
        # Anti-gaming: Check timestamp
        updated_on = sidebar_info.get('updated_on', 0)
        if updated_on < task_start:
            feedback.append("(Warning: Sidebar page predates task start)")
            # We don't penalize heavily here because setup script clears it, 
            # but it's a good sanity check.
    else:
        feedback.append("Sidebar page NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # CRITERION 2: Sidebar Content (Header) (10 pts)
    content = sidebar_info.get('content', '')
    if "### Quick Links" in content:
        score += 10
        feedback.append("Header found")
    else:
        feedback.append("Header '### Quick Links' missing")

    # CRITERION 3: Links in Sidebar (30 pts)
    # We look for the wiki link syntax [[Page Name]]
    required_links = ["Coding Standards", "Deployment Procedures", "Onboarding Checklist"]
    links_found = 0
    for link in required_links:
        if f"[[{link}]]" in content:
            links_found += 1
    
    score += (links_found * 10)
    if links_found == 3:
        feedback.append("All links present in sidebar")
    else:
        feedback.append(f"Found {links_found}/3 links in sidebar")

    # CRITERION 4: Target Pages Exist (30 pts)
    # Redmine normalizes spaces to underscores in the DB lookup
    # The export script handles this map.
    db_keys = [
        "Coding_Standards",
        "Deployment_Procedures",
        "Onboarding_Checklist"
    ]
    
    pages_created = 0
    pages_have_content = 0
    
    for key in db_keys:
        page_data = target_pages.get(key, {})
        if page_data.get('exists'):
            pages_created += 1
            if page_data.get('has_content'):
                pages_have_content += 1
    
    score += (pages_created * 10)
    
    if pages_created == 3:
        feedback.append("All target pages created")
    else:
        feedback.append(f"Created {pages_created}/3 target pages")

    # CRITERION 5: Content Not Empty (10 pts)
    # Awarded if all created pages have some content (not just empty title)
    if pages_created > 0 and pages_created == pages_have_content:
        score += 10
        feedback.append("Target pages have content")
    elif pages_created > 0:
        feedback.append("Some target pages are empty")

    # 3. Final Assessment
    # Pass threshold: 70 points
    # Must have sidebar (20), links (30), and pages (20+) to pass reasonably.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }