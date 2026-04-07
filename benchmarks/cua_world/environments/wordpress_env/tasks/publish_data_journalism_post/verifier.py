#!/usr/bin/env python3
"""
Verifier for publish_data_journalism_post task.

Programmatic checks (70 points):
  1. Post exists & published (10 pts)
  2. Taxonomy applied: Category "Data Journalism" & Tag "earthquakes" (10 pts)
  3. Table block used (10 pts)
  4. Table header configured (10 pts)
  5. Table data accuracy: contains all 5 CSV locations (10 pts)
  6. Anchor links: ToC contains correct hrefs (10 pts)
  7. Headings anchored: Headings have matching ids/anchors (10 pts)

VLM checks (30 points):
  8. Trajectory shows Gutenberg block interactions (15 pts)
  9. Final state shows published post / success (10 pts)
  10. Cross-validation (5 pts)

Pass threshold: score >= 70 AND post found AND table block utilized.
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots of an agent creating a data journalism post in WordPress.

For successful creation, the agent should:
1. Open the Gutenberg block editor (Add New Post).
2. Enter the post title.
3. Insert block elements (like Table, Headings, Paragraphs).
4. Configure Block settings (e.g., adding HTML Anchors in the Advanced panel, enabling Table Header Section).
5. Apply Categories and Tags in the Post settings sidebar.

Assess:
1. WORKFLOW_COMPLETED: Did the agent interact with the block editor and enter data?
2. TABLE_BLOCK_USED: Is there evidence of the agent specifically using the WordPress Table block UI?
3. ANCHOR_CONFIGURED: Is there evidence of the agent configuring HTML Anchors (Advanced panel)?
4. MEANINGFUL_PROGRESSION: Do the frames show sequential progress?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "table_block_used": true/false,
    "anchor_configured": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress post creation task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress interface visible?
2. SUCCESS_INDICATORS: Are there success indicators like "Post published" or viewing the published post?
3. POST_DATA_VISIBLE: Can you see the data table or the anchored headings?
4. ERROR_INDICATORS: Any errors visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "post_data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_publish_data_journalism_post(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # Load programmatic result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/publish_data_journalism_post_result.json", temp_result.name)
            with open(temp_result.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    post_found = result.get('post_found', False)
    if not post_found:
        return {"passed": False, "score": 0, "feedback": "Post with exact title not found"}

    score += 5
    feedback_parts.append("Post found")

    # 1. Post Status (5 pts)
    status = result.get('post_status', '')
    if status == 'publish':
        score += 5
        feedback_parts.append("Post published")
    else:
        feedback_parts.append(f"Post NOT published (status: {status})")

    # 2. Taxonomy (10 pts)
    categories = result.get('categories', '').lower()
    tags = result.get('tags', '').lower()
    
    if 'data journalism' in categories and 'earthquakes' in tags:
        score += 10
        feedback_parts.append("Taxonomy correct")
    else:
        feedback_parts.append(f"Taxonomy missing (Cats: {categories}, Tags: {tags})")

    content = result.get('post_content', '')
    content_lower = content.lower()

    # 3. Table Block Used (10 pts)
    # Check for WordPress table block syntax or standard HTML table
    has_table_block = 'wp:table' in content_lower or '<table' in content_lower
    if has_table_block:
        score += 10
        feedback_parts.append("Table block used")
    else:
        feedback_parts.append("No table block found")

    # 4. Table Header (10 pts)
    has_header = '<thead>' in content_lower or '"hasheadersection":true' in content_lower or '<th' in content_lower
    if has_header:
        score += 10
        feedback_parts.append("Table header configured")
    else:
        feedback_parts.append("Table header missing")

    # 5. Table Data Accuracy (10 pts)
    expected_locations = ["kahramanmaras", "al haouz", "herat", "jajarkot", "jishishan"]
    data_accurate = all(loc in content_lower for loc in expected_locations)
    if data_accurate:
        score += 10
        feedback_parts.append("Table data accurate")
    else:
        feedback_parts.append("Missing CSV data in post content")

    # 6. Anchor Links in ToC (10 pts)
    hrefs_found = all(f'href="#{anchor}"' in content_lower for anchor in ["data-summary", "methodology", "impact"])
    if hrefs_found:
        score += 10
        feedback_parts.append("ToC Anchor links present")
    else:
        feedback_parts.append("ToC Anchor hrefs missing")

    # 7. Headings Anchored (10 pts)
    # Check for id="anchor" or Gutenberg comment "anchor":"anchor"
    anchors_configured = True
    for anchor in ["data-summary", "methodology", "impact"]:
        if f'id="{anchor}"' not in content_lower and f'"anchor":"{anchor}"' not in content_lower:
            anchors_configured = False
            break
            
    if anchors_configured:
        score += 10
        feedback_parts.append("Headings correctly anchored")
    else:
        feedback_parts.append("Heading HTML anchors missing")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)

        # Process verification (15 pts)
        process_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        vlm_workflow = False
        if process_res:
            vlm_workflow = process_res.get('workflow_completed', False)
            if vlm_workflow:
                score += 8
                feedback_parts.append("VLM confirms workflow")
            if process_res.get('table_block_used', False):
                score += 7
                feedback_parts.append("VLM confirms table UI interaction")
                
        # Final state verification (10 pts)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        if final_res and final_res.get('success_indicators', False):
            score += 10
            feedback_parts.append("VLM confirms final success state")
            
        # Cross-validation (5 pts)
        if post_found and vlm_workflow:
            score += 5
    else:
        # Scale score if VLM not available
        logger.warning("VLM not available, scaling programmatic score to 100")
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("Score scaled (no VLM)")

    # Final logic
    key_criteria_met = post_found and status == 'publish' and has_table_block
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }