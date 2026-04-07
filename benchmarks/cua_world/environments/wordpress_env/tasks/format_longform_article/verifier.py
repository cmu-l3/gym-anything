#!/usr/bin/env python3
"""
Verifier for format_longform_article task.

Programmatic criteria (70 points):
1. Post exists and is published (10 pts)
2. Category "Educational" is assigned (10 pts)
3. H2 headings exist for the three specific sections (10 pts)
4. HTML anchors (IDs) are present on those headings (10 pts)
5. A Table of Contents exists with jump links pointing to the anchors (10 pts)
6. A Quote/Blockquote block exists with the target text (10 pts)
7. A video embed block exists and placeholders are removed (10 pts)

VLM Verification (30 points):
8. Trajectory shows interaction with Block Editor settings (15 pts)
9. Final state shows published post (10 pts)
10. Cross validation (5 pts)
"""

import json
import tempfile
import os
import re
import logging

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

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent formatting a WordPress post using the Block Editor.

Assess the agent's actions based on these frames:
1. WORKFLOW_COMPLETED: Did the agent copy text into the editor and interact with block settings?
2. SIDEBAR_INTERACTION: Is there evidence of the agent using the right-side settings panel (specifically the "Advanced" section to add HTML anchors)?
3. FORMATTING_APPLIED: Do you see the agent converting blocks into Headings, Quotes, or Lists?
4. EMBEDDING: Is there evidence of the agent pasting a YouTube URL into an embed block?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "sidebar_interaction": true/false,
    "formatting_applied": true/false,
    "embedding": true/false,
    "observations": "describe what you see",
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress post creation task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. POST_PUBLISHED: Are there success indicators that the post was published (e.g., "Post published" banner, or the button says "Update" instead of "Publish")?
3. POST_DATA_VISIBLE: Can you see the formatted content (Headings, quotes, links)?

Respond in JSON format:
{
    "admin_visible": true/false,
    "post_published": true/false,
    "post_data_visible": true/false,
    "observations": "describe what you see",
    "confidence": "low"/"medium"/"high"
}
"""

def verify_format_longform_article(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_headings = metadata.get('required_headings', [
        "Solar Energy Technologies",
        "Wind Power Developments",
        "Energy Storage Solutions"
    ])
    quote_start = metadata.get('quote_start', "The transition to 100% renewable energy systems")
    embed_url = metadata.get('embed_url', "https://www.youtube.com/watch?v=1kUE0BZtTRc")

    # Read the programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/format_longform_article_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Post Exists and Published (10 pts)
    if not result.get("post_found", False):
        return {"passed": False, "score": 0, "feedback": "Post with exact title not found"}
    
    status = result.get("post_status", "")
    if status == "publish":
        score += 10
        feedback.append("Post published")
    else:
        feedback.append(f"Post found but status is '{status}', not 'publish'")

    # 2. Category Assigned (10 pts)
    categories = result.get("post_categories", "")
    if "Educational" in categories:
        score += 10
        feedback.append("Category 'Educational' assigned")
    else:
        feedback.append(f"Missing 'Educational' category (Found: {categories})")

    content = result.get("post_content", "")
    content_lower = content.lower()

    # Placeholders removed
    placeholders_removed = True
    if "[Insert Table of Contents Here]".lower() in content_lower or "[Embed Video Here...]".lower() in content_lower:
        placeholders_removed = False

    # 3. Headings Exist (10 pts) & 4. Anchors exist (10 pts)
    headings_found = 0
    anchors_found = 0
    found_anchor_ids = []

    for heading in required_headings:
        # Check for HTML h2 tags with the text
        h2_pattern = rf'<h2[^>]*>(?:<[^>]+>)*\s*{re.escape(heading)}\s*(?:<[^>]+>)*</h2>'
        h2_match = re.search(h2_pattern, content, re.IGNORECASE)
        
        # Check for Gutenberg block comments
        block_pattern = rf'<!--\s*wp:heading.*?-->\s*<h2[^>]*>.*?{re.escape(heading)}.*?</h2>\s*<!--\s*/wp:heading\s*-->'
        block_match = re.search(block_pattern, content, re.IGNORECASE | re.DOTALL)
        
        if h2_match or block_match:
            headings_found += 1
            
            # Check for anchor/id
            match_str = block_match.group(0) if block_match else h2_match.group(0)
            
            # Extract id="something"
            id_match = re.search(r'id=["\']([^"\']+)["\']', match_str, re.IGNORECASE)
            # Or extract from block JSON: {"anchor":"something"}
            anchor_match = re.search(r'"anchor"\s*:\s*"([^"]+)"', match_str, re.IGNORECASE)
            
            if id_match or anchor_match:
                anchors_found += 1
                found_id = id_match.group(1) if id_match else anchor_match.group(1)
                found_anchor_ids.append(found_id)

    if headings_found == 3:
        score += 10
        feedback.append("All 3 H2 headings found")
    else:
        feedback.append(f"Found {headings_found}/3 required H2 headings")

    if anchors_found == 3:
        score += 10
        feedback.append("All 3 HTML anchors found on headings")
    elif anchors_found > 0:
        score += 5
        feedback.append(f"Found {anchors_found}/3 HTML anchors on headings")
    else:
        feedback.append("No HTML anchors found on the headings")

    # 5. Jump Links (Table of Contents) (10 pts)
    jump_links_found = 0
    for anchor_id in found_anchor_ids:
        # Look for <a href="#anchor_id">
        link_pattern = rf'<a[^>]+href=["\']#{re.escape(anchor_id)}["\'][^>]*>'
        if re.search(link_pattern, content, re.IGNORECASE):
            jump_links_found += 1

    if len(found_anchor_ids) > 0 and jump_links_found == len(found_anchor_ids):
        score += 10
        feedback.append("Valid jump links match all anchors")
    elif jump_links_found > 0:
        score += 5
        feedback.append(f"Found {jump_links_found} valid jump links to anchors")
    else:
        feedback.append("No valid jump links to anchors found")

    # 6. Blockquote (10 pts)
    quote_pattern = rf'<!--\s*wp:quote.*?-->.*?{re.escape(quote_start[:30])}.*?<!--\s*/wp:quote\s*-->'
    html_quote_pattern = rf'<blockquote[^>]*>.*?{re.escape(quote_start[:30])}.*?</blockquote>'
    
    if re.search(quote_pattern, content, re.IGNORECASE | re.DOTALL) or re.search(html_quote_pattern, content, re.IGNORECASE | re.DOTALL):
        score += 10
        feedback.append("Quote block found")
    else:
        feedback.append("Quote block not found")

    # 7. Embed & Placeholders removed (10 pts)
    embed_found = False
    if "youtube.com" in content_lower or "youtu.be" in content_lower:
        if "wp:embed" in content_lower or "<iframe" in content_lower or "wp-block-embed" in content_lower:
            embed_found = True
            
    if embed_found and placeholders_removed:
        score += 10
        feedback.append("Video embedded and placeholders removed")
    elif embed_found:
        score += 5
        feedback.append("Video embedded but placeholders remain")
    else:
        feedback.append("Video embed not found")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Check Trajectory (15 pts)
            frames = sample_trajectory_frames(traj, n=4)
            traj_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            
            if traj_result:
                if traj_result.get("sidebar_interaction", False) and traj_result.get("formatting_applied", False):
                    score += 15
                    feedback.append("VLM confirms editor interaction and formatting")
                elif traj_result.get("formatting_applied", False):
                    score += 8
                    feedback.append("VLM confirms basic formatting, missed sidebar anchors")
            
            # Check Final State (10 pts)
            final_img = get_final_screenshot(traj)
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
            
            if final_result and final_result.get("post_published", False):
                score += 10
                feedback.append("VLM confirms published state")
                
            # Cross-validation (5 pts)
            if status == "publish" and final_result and final_result.get("post_published", False):
                score += 5
                
        except Exception as e:
            logger.error(f"VLM processing failed: {e}")
            feedback.append("VLM processing failed, ignoring VLM score")

    # Calculate Pass/Fail
    # To pass, they must score >= 65, the post must exist and be published, and anchors/headings must be at least partially present.
    is_published = status == "publish"
    has_structure = (headings_found >= 2 and anchors_found >= 1)
    
    passed = score >= 65 and is_published and has_structure

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "headings_found": headings_found,
            "anchors_found": anchors_found,
            "jump_links_found": jump_links_found,
            "placeholders_removed": placeholders_removed
        }
    }