#!/usr/bin/env python3
"""
Verifier for Publish Real Estate Listings task.

Programmatic Verification (70 Points):
- Category 'Properties' created (5 pts)
- Listing 1 created correctly & Meta complete (15 pts)
- Listing 2 created correctly & Meta complete (20 pts)
- Listing 3 created correctly & Meta complete (25 pts)
- Anti-gaming Check: Posts must be created after task start (5 pts)

VLM Verification (30 Points):
- Process verification on trajectory frames (shows editor usage) (15 pts)
- Final state shows posts (10 pts)
- Cross validation (5 pts)
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
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROMPT = """You are analyzing trajectory screenshots from an agent adding real estate listings to a WordPress site.

The agent should progress through:
1. Navigating to Posts > Add New
2. Filling in the title and content
3. Assigning the 'Properties' category
4. Using the Custom Fields panel (which might need to be enabled in Preferences) OR using the terminal/WP-CLI to add metadata like 'property_price', 'property_beds', etc.
5. Setting the Discussion/Comment status

Assess:
1. WORKFLOW_COMPLETED: Did the agent create posts and assign custom metadata (either via UI or CLI)?
2. CUSTOM_FIELDS_VISIBLE: Is the Custom Fields panel visible, or is the terminal visible processing wp-cli commands?
3. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "custom_fields_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress post creation task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin or terminal interface visible?
2. SUCCESS_INDICATORS: Are there success messages ("Post published") or is the All Posts list showing the new property listings?
3. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_publish_real_estate_listings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_listings = metadata.get('listings', [])

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/real_estate_task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Category Check (5 pts)
    if result.get("category_exists", False):
        score += 5
        feedback_parts.append("Category 'Properties' exists")
    else:
        feedback_parts.append("Category 'Properties' NOT found")

    # 2. Check Listings
    listings_data = result.get("listings", {})
    all_found = True
    all_meta_perfect = True
    
    listing_points = [15, 20, 25]  # Weights for Listing 1, 2, 3
    
    for idx, expected in enumerate(expected_listings):
        title = expected["title"]
        max_pts = listing_points[idx]
        actual = listings_data.get(title, {})
        
        if not actual.get("found", False):
            feedback_parts.append(f"Listing {idx+1} ({title[:15]}...) NOT found")
            all_found = False
            all_meta_perfect = False
            continue
            
        pts = max_pts * 0.4  # Base points for finding it published
        
        # Check category
        if "Properties" in actual.get("categories", []):
            pts += max_pts * 0.1
        else:
            feedback_parts.append(f"Listing {idx+1} missing 'Properties' category")
            all_meta_perfect = False
            
        # Check comment status
        if actual.get("comment_status", "") == expected["comment_status"]:
            pts += max_pts * 0.1
        else:
            feedback_parts.append(f"Listing {idx+1} comment status wrong (Expected {expected['comment_status']})")
            all_meta_perfect = False
            
        # Check Custom Fields
        meta_ok = True
        for m_key, m_val in expected["meta"].items():
            actual_meta = actual.get("meta", {}).get(m_key, "")
            if actual_meta != m_val:
                meta_ok = False
                all_meta_perfect = False
                feedback_parts.append(f"Listing {idx+1} {m_key} wrong (Expected '{m_val}', got '{actual_meta}')")
        
        if meta_ok:
            pts += max_pts * 0.4  # Full points if meta perfectly matches
            
        score += pts
        
    # 3. Anti-gaming check (5 pts)
    # Check if the result was exported recently after task start
    task_start = result.get("task_start_timestamp", 0)
    export_time = result.get("timestamp", 0)
    if export_time > task_start and task_start > 0:
        score += 5
    else:
        feedback_parts.append("Warning: Timestamps invalid or pre-existing state suspected")

    # VLM Evaluation (30 pts)
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_img = get_final_screenshot(traj)
            
            traj_result = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
            if traj_result:
                if traj_result.get("workflow_completed", False): score += 10
                if traj_result.get("custom_fields_visible", False): score += 5
                
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
            if final_result:
                if final_result.get("admin_visible", False): score += 5
                if final_result.get("success_indicators", False): score += 5
                
            # Cross validation
            if all_found and traj_result and traj_result.get("workflow_completed", False):
                score += 5
        except Exception as e:
            logger.warning(f"VLM evaluation skipped or failed: {e}")
            # Grant average VLM points if VLM fails but programmatically perfect to prevent unfair failure
            if all_found and all_meta_perfect:
                score += 25

    score = int(min(100, score))
    passed = score >= 75 and all_found

    if passed:
        feedback_parts.insert(0, "Task completed successfully!")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }