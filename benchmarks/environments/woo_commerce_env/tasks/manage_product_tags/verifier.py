#!/usr/bin/env python3
"""
Verifier for manage_product_tags task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points):
  1. Tags Created (30 pts): Premium (10), Eco-Friendly (10), Gift Idea (10)
  2. Assignments (30 pts): 5 points per correct assignment (6 assignments)
  3. Anti-gaming (10 pts): New tags were actually created during task

VLM checks (30 points):
  4. Process verification (15 pts): Trajectory shows interaction with Tags page or Product Edit sidebar
  5. Final state verification (15 pts): Screen shows tags applied or tag list

Pass threshold: 60 points AND all tags created
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent managing product tags in WooCommerce.

For successful tag management, the agent should EITHER:
A) Navigate to Products > Tags and create new tags there, OR
B) Edit individual products and type new tags into the 'Product tags' sidebar box.

Assess:
1. TAG_MANAGEMENT_VISIBLE: Is the 'Product tags' screen or the product edit sidebar visible?
2. TYPING_TAGS: Is there evidence of typing tag names (Premium, Eco-Friendly, Gift Idea)?
3. SAVING: Is there evidence of clicking 'Add New Tag' or 'Update' (on product page)?

Respond in JSON format:
{
    "tag_management_visible": true/false,
    "typing_tags": true/false,
    "saving_action": true/false,
    "method_used": "central_screen_or_product_edit",
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce task.

The goal was to create and assign tags.
Assess:
1. TAGS_VISIBLE: Are specific tags (Premium, Eco-Friendly, Gift Idea) visible on screen?
2. SUCCESS_INDICATORS: Is there a "Tag added" or "Product updated" message?

Respond in JSON format:
{
    "tags_visible": true/false,
    "success_indicators": true/false,
    "visible_tag_names": ["list names seen"],
    "confidence": "low"/"medium"/"high"
}
"""

def verify_manage_product_tags(traj, env_info, task_info):
    """
    Verify that 3 product tags were created and assigned correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Read Programmatic Result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}

    # 2. Programmatic Scoring (70 pts max)
    
    # Check Tags Existence (30 pts)
    tags = result.get("tags", {})
    tags_created = 0
    if tags.get("premium", {}).get("found"):
        score += 10
        tags_created += 1
        feedback_parts.append("Tag 'Premium' created")
    else:
        feedback_parts.append("Tag 'Premium' MISSING")

    if tags.get("eco", {}).get("found"):
        score += 10
        tags_created += 1
        feedback_parts.append("Tag 'Eco-Friendly' created")
    else:
        feedback_parts.append("Tag 'Eco-Friendly' MISSING")

    if tags.get("gift", {}).get("found"):
        score += 10
        tags_created += 1
        feedback_parts.append("Tag 'Gift Idea' created")
    else:
        feedback_parts.append("Tag 'Gift Idea' MISSING")

    # Check Assignments (30 pts - 5 pts each)
    assignments = result.get("assignments", {})
    assign_score = 0
    
    # T-Shirt
    if assignments.get("tshirt_premium"): assign_score += 5
    if assignments.get("tshirt_eco"): assign_score += 5
    
    # Headphones
    if assignments.get("headphones_premium"): assign_score += 5
    if assignments.get("headphones_gift"): assign_score += 5
    
    # Sweater
    if assignments.get("sweater_eco"): assign_score += 5
    if assignments.get("sweater_gift"): assign_score += 5

    score += assign_score
    feedback_parts.append(f"Assignments correct: {assign_score}/30 pts")

    # Anti-gaming (10 pts)
    initial_count = int(result.get("initial_tag_count", 0))
    current_count = int(result.get("current_tag_count", 0))
    if current_count >= initial_count + 3:
        score += 10
        feedback_parts.append("Anti-gaming passed (new tags detected)")
    elif current_count > initial_count:
        score += 5
        feedback_parts.append("Partial anti-gaming (some new tags)")

    # 3. VLM Verification (30 pts max)
    # Only run if programmatic checks show at least some progress to save tokens
    vlm_score = 0
    if score > 10:
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        # Trajectory Analysis (15 pts)
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            try:
                traj_res = query_vlm(prompt=TRAJECTORY_PROCESS_PROMPT, images=frames)
                if traj_res.get("success"):
                    parsed = traj_res.get("parsed", {})
                    if parsed.get("tag_management_visible") or parsed.get("typing_tags"):
                        vlm_score += 15
                        feedback_parts.append("VLM: Workflow confirmed")
            except Exception as e:
                logger.warning(f"VLM trajectory check failed: {e}")

        # Final State Analysis (15 pts)
        final_shot = get_final_screenshot(traj)
        if final_shot:
            try:
                final_res = query_vlm(prompt=FINAL_STATE_PROMPT, image=final_shot)
                if final_res.get("success"):
                    parsed = final_res.get("parsed", {})
                    if parsed.get("tags_visible") or parsed.get("success_indicators"):
                        vlm_score += 15
                        feedback_parts.append("VLM: Final state confirmed")
            except Exception as e:
                logger.warning(f"VLM final check failed: {e}")

    score += vlm_score
    
    # 4. Final Result
    passed = (score >= 60) and (tags_created == 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }