#!/usr/bin/env python3
"""
Verifier for Create Hierarchical Research Guide Pages task.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (80 points) - via export script JSON:
  1. Parent Page (15 pts): Found/Published (10), correct content phrase (5)
  2. Child Page 1 (15 pts): Found (5), parent ID matches (3), order=1 (3), content (4)
  3. Child Page 2 (15 pts): Found (5), parent ID matches (3), order=2 (3), content (4)
  4. Child Page 3 (15 pts): Found (5), parent ID matches (3), order=3 (3), content (4)
  5. Child Page 4 (15 pts): Found (5), parent ID matches (3), order=4 (3), content (4)
  6. Net New Pages Created >= 5 (5 pts): Anti-gaming check

VLM checks (20 points) - using TRAJECTORY frames:
  7. Process verification (15 pts): Agent seen setting Page Attributes (parent/order)
  8. Final state (5 pts): Admin pages list visible

Pass threshold: 70 points AND Parent found AND at least 3 children fully configured.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots of an agent creating a hierarchical set of WordPress pages.

The agent should:
1. Create a parent page ("Digital Humanities Research Guide")
2. Create multiple child pages
3. For child pages, use the "Page Attributes" panel (usually on the right sidebar) to set the "Parent" dropdown to the guide.
4. For child pages, set the "Order" number in the same attributes panel.

Assess:
1. HIERARCHY_CONFIGURED: Did the agent open the Page Attributes / Summary panel and set a Parent page?
2. ORDER_CONFIGURED: Did the agent explicitly type a number into the Order field?
3. MULTIPLE_PAGES: Is there evidence of the agent creating and publishing multiple distinct pages?

Respond in JSON format:
{
    "hierarchy_configured": true/false,
    "order_configured": true/false,
    "multiple_pages": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see regarding page attributes"
}
"""


def verify_create_research_guide(traj, env_info, task_info):
    """Verify research guide creation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_research_guide_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    # ================================================================
    # PROGRAMMATIC CHECKS (80 points)
    # ================================================================
    
    parent = result.get('parent', {})
    children = result.get('children', {})
    
    # Check 1: Parent Page (15 pts)
    parent_id = parent.get('id', 0)
    if parent.get('found', False):
        score += 10
        feedback_parts.append("Parent page found")
        if parent.get('has_phrase', False):
            score += 5
            feedback_parts.append("Parent content correct")
        else:
            feedback_parts.append("Parent missing expected content")
    else:
        feedback_parts.append("Parent page NOT found")
    
    # Check 2-5: Child Pages (15 pts each x 4 = 60 pts)
    child_configs = [
        ("child1", 1, "Getting Started"),
        ("child2", 2, "Primary Source"),
        ("child3", 3, "Digital Tools"),
        ("child4", 4, "Citation Guide")
    ]
    
    children_fully_configured = 0
    
    for key, expected_order, name_hint in child_configs:
        child = children.get(key, {})
        child_score = 0
        
        if child.get('found', False):
            child_score += 5
            
            # Parent check
            actual_parent = child.get('parent_id', 0)
            parent_correct = (actual_parent == parent_id and parent_id > 0)
            if parent_correct:
                child_score += 3
                
            # Order check
            actual_order = child.get('menu_order', 0)
            order_correct = (actual_order == expected_order)
            if order_correct:
                child_score += 3
                
            # Content check
            content_correct = child.get('has_phrase', False)
            if content_correct:
                child_score += 4
                
            if parent_correct and order_correct and content_correct:
                children_fully_configured += 1
                feedback_parts.append(f"{name_hint} fully configured")
            else:
                feedback_parts.append(f"{name_hint} partially configured (score: {child_score}/15)")
                
            score += child_score
        else:
            feedback_parts.append(f"{name_hint} NOT found")

    # Check 6: Net New Pages (5 pts)
    initial_count = result.get('initial_page_count', 0)
    current_count = result.get('current_page_count', 0)
    new_pages = current_count - initial_count
    
    if new_pages >= 5:
        score += 5
        feedback_parts.append(f"Created {new_pages} new pages")
    elif new_pages > 0:
        feedback_parts.append(f"Created only {new_pages} new pages (expected 5)")
    else:
        feedback_parts.append("No new pages created")

    # ================================================================
    # VLM CHECKS (20 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and len(traj) > 0:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            
            # Process check (15 pts)
            vlm_process = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
            if vlm_process:
                if vlm_process.get("hierarchy_configured", False):
                    vlm_score += 8
                if vlm_process.get("order_configured", False):
                    vlm_score += 7
            
            # Final state (5 pts) implicitly verified by DB checks above, but we can award
            # points if they just made it through the workflow properly.
            if vlm_process and vlm_process.get("multiple_pages", False):
                vlm_score += 5
                
            score += vlm_score
            feedback_parts.append(f"VLM Score: {vlm_score}/20")
        except Exception as e:
            logger.error(f"VLM evaluation failed: {e}")
            feedback_parts.append("VLM evaluation skipped/failed")
    else:
        # If VLM is not available, scale programmatic score up
        score = int(score * (100.0 / 80.0))
        feedback_parts.append("VLM skipped (scaled programmatic score)")

    # ================================================================
    # FINAL EVALUATION
    # ================================================================
    # Require 70 total points, parent exists, and at least 3 children fully right
    passed = (score >= 70) and parent.get('found', False) and (children_fully_configured >= 3)
    
    # Cap score at 100
    score = min(100, score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "parent_found": parent.get('found', False),
            "children_fully_configured": children_fully_configured,
            "new_pages_created": new_pages,
            "vlm_score": vlm_score
        }
    }