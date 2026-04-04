#!/usr/bin/env python3
"""
Verifier for Game AI Behavior Tree Task.
Scoring depends on:
1. File creation/modification (10%)
2. PNG export (10%)
3. Logic Structure (Keywords/Nodes present) (50%)
4. Styling Compliance (Colors) (30%)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_game_ai_behavior_tree_npc(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. File checks (20 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback_parts.append("File created/modified (+10)")
    else:
        feedback_parts.append("File not modified/created")
        
    if result.get("png_exists"):
        score += 10
        feedback_parts.append("PNG export found (+10)")
    else:
        feedback_parts.append("PNG export missing")

    # 2. Structure & Node Counts (30 pts)
    node_count = result.get("node_count", 0)
    if node_count >= 15:
        score += 10
        feedback_parts.append(f"Sufficient node count ({node_count}) (+10)")
    elif node_count >= 8:
        score += 5
        feedback_parts.append(f"Low node count ({node_count}) (+5)")
    else:
        feedback_parts.append(f"Too few nodes ({node_count})")

    # Check specific node types exist
    if result.get("selector_count", 0) >= 2: # Main + Combat + Idle selectors
        score += 5
        feedback_parts.append("Selectors present (+5)")
    if result.get("sequence_count", 0) >= 4: # 4 main branches
        score += 5
        feedback_parts.append("Sequences present (+5)")
    if result.get("condition_count", 0) >= 3:
        score += 5
        feedback_parts.append("Conditions present (+5)")
    if result.get("action_count", 0) >= 4:
        score += 5
        feedback_parts.append("Actions present (+5)")

    # 3. Logic Implementation (30 pts)
    if result.get("has_health_check"):
        score += 10
        feedback_parts.append("Self-Preservation logic found (+10)")
    else:
        feedback_parts.append("Missing Health/Cover logic")

    if result.get("has_combat_branch"):
        score += 10
        feedback_parts.append("Combat logic found (+10)")
    else:
        feedback_parts.append("Missing Combat/Attack logic")
        
    if result.get("has_idle_branch"):
        score += 10
        feedback_parts.append("Idle logic found (+10)")
    else:
        feedback_parts.append("Missing Idle logic")

    # 4. Styling (20 pts)
    style_score = result.get("styling_score", 0)
    # Map 0-100% to 0-20 points
    points_style = int(style_score / 5) 
    score += points_style
    if points_style > 0:
        feedback_parts.append(f"Styling compliance: {int(style_score)}% (+{points_style})")
    else:
        feedback_parts.append("No correct color coding detected")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }