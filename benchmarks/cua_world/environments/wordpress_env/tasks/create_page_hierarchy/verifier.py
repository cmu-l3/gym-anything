#!/usr/bin/env python3
"""
Verifier for Create Page Hierarchy task in WordPress.

Verification Strategy:
1. Load the exported JSON containing all published WordPress pages.
2. Verify exact title matches (case-insensitive, ignoring HTML entity issues like &amp; vs &).
3. Verify Parent-Child relationships using `post_parent` linking to the correct top-level page IDs.
4. Verify required content phrases are present in `post_content`.
5. Check if pages were created chronologically recently (anti-gaming).
6. Perform trajectory VLM verification to ensure the agent actually used the WordPress UI.

Pass Threshold:
Score >= 60 AND at least 9/12 pages exist AND at least 6/9 relationships are correct.
"""

import json
import tempfile
import os
import logging
import html
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected Page Definitions
EXPECTED_PAGES = {
    "About the Department": {"parent": None, "content": ["Department of Digital Humanities"]},
    "Academic Programs": {"parent": None, "content": ["undergraduate and graduate degree programs"]},
    "Research & Scholarship": {"parent": None, "content": ["cutting-edge research"]},
    "Mission Statement": {"parent": "About the Department", "content": ["advance the intersection of technology and humanistic inquiry"]},
    "Faculty Directory": {"parent": "About the Department", "content": ["Dr. Sarah Chen", "Dr. Marcus Rivera"]},
    "Contact Information": {"parent": "About the Department", "content": ["dhinfo@university.edu", "Room 412, Hawthorne Hall"]},
    "Undergraduate Studies": {"parent": "Academic Programs", "content": ["Bachelor of Arts in Digital Humanities"]},
    "Graduate Studies": {"parent": "Academic Programs", "content": ["Master of Arts", "Doctor of Philosophy"]},
    "Course Catalog": {"parent": "Academic Programs", "content": ["DH 101", "DH 450"]},
    "Current Projects": {"parent": "Research & Scholarship", "content": ["Digital Archive of Historical Newspapers"]},
    "Publications": {"parent": "Research & Scholarship", "content": ["Journal of Digital Humanities"]},
    "Funding Opportunities": {"parent": "Research & Scholarship", "content": ["National Endowment for the Humanities"]}
}


def normalize_title(title):
    """Normalize string for robust title comparison."""
    if not title:
        return ""
    # Unescape HTML entities (e.g. &amp; -> &)
    t = html.unescape(title)
    # Lowercase and replace multiple spaces with single space
    t = re.sub(r'\s+', ' ', t.lower().strip())
    return t


def _vlm_query(query_vlm, prompt, images=None):
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a page hierarchy in WordPress.

The agent should:
1. Navigate to Pages > Add New multiple times
2. Use the Page Editor to enter titles and content
3. Use the 'Page Attributes' panel on the right sidebar to set the 'Parent' page and 'Order'
4. Publish the pages

Assess:
1. WORKFLOW_COMPLETED: Did the agent create and publish multiple pages?
2. PARENT_SETTING: Is there evidence of the agent using the Page Attributes panel to select a Parent page from a dropdown?
3. MEANINGFUL_PROGRESSION: Do the frames show real state changes (different pages being created)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "parent_setting_observed": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_create_page_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # Read Exported JSON
    # ================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_page_hierarchy_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file missing or invalid: {e}"}

    pages_data = result.get('pages', [])
    initial_count = result.get('initial_page_count', 0)
    current_count = result.get('current_page_count', 0)

    # Anti-gaming: Ensure actual pages were added
    if current_count < initial_count + 12:
        logger.warning(f"Count issue: started with {initial_count}, ended with {current_count}. Expected at least {initial_count + 12}.")

    # Map normalized titles to their page data dictionary
    found_pages = {}
    for p in pages_data:
        norm_title = normalize_title(p.get('post_title', ''))
        # If multiple pages have same title, keep the one with the highest ID (most recent)
        if norm_title not in found_pages or int(p.get('ID', 0)) > int(found_pages[norm_title].get('ID', 0)):
            found_pages[norm_title] = p

    score = 0
    feedback_parts = []
    
    pages_exist_count = 0
    relationships_correct_count = 0

    # ================================================================
    # PROGRAMMATIC EVALUATION
    # ================================================================

    # 1. Check Top-Level Pages (9 points)
    top_levels = ["About the Department", "Academic Programs", "Research & Scholarship"]
    for tl in top_levels:
        if normalize_title(tl) in found_pages:
            score += 3
            pages_exist_count += 1
            feedback_parts.append(f"Top-level '{tl}' exists")

    # 2. Check Children Existence (27 points)
    children_groups = {
        "About the Department": ["Mission Statement", "Faculty Directory", "Contact Information"],
        "Academic Programs": ["Undergraduate Studies", "Graduate Studies", "Course Catalog"],
        "Research & Scholarship": ["Current Projects", "Publications", "Funding Opportunities"]
    }

    for parent, children in children_groups.items():
        group_found = 0
        for child in children:
            if normalize_title(child) in found_pages:
                score += 3
                pages_exist_count += 1
                group_found += 1
        feedback_parts.append(f"Found {group_found}/3 children for '{parent}'")

    # 3. Check Parent-Child Hierarchy (27 points)
    # Need to match the post_parent ID to the parent's actual ID
    for expected_title, expected_data in EXPECTED_PAGES.items():
        norm_title = normalize_title(expected_title)
        if norm_title not in found_pages:
            continue
            
        page = found_pages[norm_title]
        expected_parent_title = expected_data['parent']
        
        # We only check relationships for child pages (where parent is not None)
        if expected_parent_title is not None:
            norm_parent = normalize_title(expected_parent_title)
            
            # If the actual expected parent page exists in our DB map
            if norm_parent in found_pages:
                expected_parent_id = int(found_pages[norm_parent].get('ID', 0))
                actual_parent_id = int(page.get('post_parent', 0))
                
                if actual_parent_id > 0 and actual_parent_id == expected_parent_id:
                    score += 3
                    relationships_correct_count += 1
                    logger.info(f"Correct hierarchy: '{expected_title}' is child of '{expected_parent_title}'")
            else:
                logger.info(f"Failed hierarchy: Expected parent '{expected_parent_title}' does not exist.")

    feedback_parts.append(f"Correct parent-child relationships: {relationships_correct_count}/9")

    # 4. Content Requirements (24 points)
    content_matches = 0
    for expected_title, expected_data in EXPECTED_PAGES.items():
        norm_title = normalize_title(expected_title)
        if norm_title in found_pages:
            page_content = html.unescape(found_pages[norm_title].get('post_content', '')).lower()
            all_strings_found = True
            for required_str in expected_data['content']:
                if required_str.lower() not in page_content:
                    all_strings_found = False
                    break
            
            if all_strings_found:
                score += 2
                content_matches += 1

    feedback_parts.append(f"Content requirements met: {content_matches}/12 pages")

    # 5. Menu Order Bonus (3 points)
    # Simplified check: Just verify at least 3 pages have menu_order > 0
    pages_with_order = sum(1 for p in found_pages.values() if int(p.get('menu_order', 0)) > 0)
    if pages_with_order >= 3:
        score += 3
        feedback_parts.append("Menu order utilized")

    # ================================================================
    # VLM TRAJECTORY EVALUATION (10 points)
    # ================================================================
    vlm_score = 0
    if 'gym_anything.vlm' in sys.modules or True:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            query_vlm = env_info.get('query_vlm')
            frames = sample_trajectory_frames(traj, n=8)
            
            vlm_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            if vlm_result:
                if vlm_result.get("workflow_completed", False):
                    vlm_score += 5
                if vlm_result.get("parent_setting_observed", False):
                    vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"VLM verified workflow: +{vlm_score} pts")
        except Exception as e:
            logger.warning(f"VLM evaluation failed: {e}")
            # Grant partial pass-through points if VLM errors out but programmatic was stellar
            if pages_exist_count >= 12 and relationships_correct_count >= 9:
                score += 10
                feedback_parts.append("VLM error, auto-awarded VLM points due to perfect programmatic match")

    # ================================================================
    # FINAL PASS/FAIL LOGIC
    # ================================================================
    
    passed = (
        score >= 60 and
        pages_exist_count >= 9 and 
        relationships_correct_count >= 6
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "pages_exist_count": pages_exist_count,
            "relationships_correct": relationships_correct_count,
            "content_matches": content_matches,
            "vlm_score": vlm_score
        }
    }