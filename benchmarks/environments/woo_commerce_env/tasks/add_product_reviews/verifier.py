#!/usr/bin/env python3
"""
Verifier for Add Product Reviews task in WooCommerce.

Verification Strategy:
1. Programmatic (80 pts):
   - Settings correctly configured (30 pts)
   - Headphones review found with correct rating and text (25 pts)
   - T-Shirt review found with correct rating and text (25 pts)
2. VLM (20 pts):
   - Trajectory verification: Did the agent visit the frontend product pages?
   - The reviews can be verified purely via DB, so VLM is supplementary for workflow adherence.
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
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception:
        pass
    return None

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent performing a task in WooCommerce.
The task involves enabling product reviews in settings and then posting reviews on two specific products from the storefront.

Look for:
1. SETTINGS_CHANGE: Visiting WooCommerce > Settings > Products and enabling reviews/ratings.
2. FRONTEND_VISIT: Visiting the public-facing product pages (storefront), not just the admin edit pages.
3. REVIEW_SUBMISSION: Scrolling down to the "Reviews" tab on a product page, selecting stars, and typing text.

Respond in JSON:
{
    "visited_settings": true/false,
    "visited_storefront": true/false,
    "submitted_review_ui": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_add_product_reviews(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    
    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. Verify Settings (30 pts)
    settings = result.get("settings", {})
    s_score = 0
    if settings.get("enable_reviews") == "yes": s_score += 10
    if settings.get("enable_ratings") == "yes": s_score += 10
    if settings.get("ratings_required") == "yes": s_score += 10
    
    score += s_score
    feedback.append(f"Settings configuration: {s_score}/30 points")
    if s_score < 30:
        feedback.append(f"  Got: Reviews={settings.get('enable_reviews')}, Ratings={settings.get('enable_ratings')}, Required={settings.get('ratings_required')}")

    # 2. Verify Headphones Review (25 pts)
    hp_rev = result.get("headphones_review", {})
    hp_score = 0
    if hp_rev.get("found"):
        hp_score += 10
        if str(hp_rev.get("rating")) == str(metadata.get("headphones_rating", 5)):
            hp_score += 10
        else:
            feedback.append(f"  Headphones rating incorrect: {hp_rev.get('rating')}")
        
        # Keyword check usually handled by SQL, but verify content length
        if len(hp_rev.get("content", "")) > 10:
            hp_score += 5
    else:
        feedback.append("  Headphones review not found")
    
    score += hp_score
    feedback.append(f"Headphones review: {hp_score}/25 points")

    # 3. Verify T-Shirt Review (25 pts)
    ts_rev = result.get("tshirt_review", {})
    ts_score = 0
    if ts_rev.get("found"):
        ts_score += 10
        if str(ts_rev.get("rating")) == str(metadata.get("tshirt_rating", 4)):
            ts_score += 10
        else:
            feedback.append(f"  T-Shirt rating incorrect: {ts_rev.get('rating')}")
            
        if len(ts_rev.get("content", "")) > 10:
            ts_score += 5
    else:
        feedback.append("  T-Shirt review not found")
        
    score += ts_score
    feedback.append(f"T-Shirt review: {ts_score}/25 points")

    # 4. VLM / Workflow Verification (20 pts)
    # Check if they actually went to the storefront (trajectory analysis)
    # If reviews are found, we assume workflow was likely followed, but VLM confirms it wasn't hacked via SQL
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        # Sample frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, 5)
        
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get("visited_settings"): vlm_score += 5
            if vlm_res.get("visited_storefront"): vlm_score += 10
            if vlm_res.get("submitted_review_ui"): vlm_score += 5
    else:
        # Fallback if VLM not available but reviews exist
        if hp_score > 0 and ts_score > 0:
            vlm_score = 20
    
    score += vlm_score
    feedback.append(f"Workflow verification: {vlm_score}/20 points")

    # Pass logic: Must have correct settings and at least one review correct
    passed = (s_score == 30) and (hp_score >= 20 or ts_score >= 20) and (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }