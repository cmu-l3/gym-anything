#!/usr/bin/env python3
"""
Verifier for rpg_dungeon_level_design task.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rpg_dungeon_level_design(traj, env_info, task_info):
    """
    Verifies the RPG Dungeon Level Design task.
    
    Criteria:
    1. Files Created (10 pts): .drawio and .png exist and modified.
    2. Room Labels (25 pts): Checks for presence of 6 specific room names.
    3. Logic Items (25 pts): Checks for 5 specific logic items (Key, Start, Boss, etc.).
    4. Topology/Edges (20 pts): Checks if diagram has connections (edges).
    5. Export Validity (20 pts): PNG exists and has size > 0.
    """
    
    # Setup copy mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function unavailable"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    required_rooms = metadata.get('required_rooms', ["Entry", "Grand Hall", "Armory", "Shrine", "Treasure Vault", "Boss Chamber"])
    required_items = metadata.get('required_items', ["Start", "Rusty Key", "Trap", "Loot", "Boss"])
    min_edges = metadata.get('min_edges', 5)

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Task result file not found. Did the task script run?"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Task result file is corrupt."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    analysis = result.get('analysis', {})
    text_labels = analysis.get('text_labels', [])
    # Normalize text labels for fuzzy matching
    text_blob = " ".join(text_labels).lower()

    # --- Criterion 1: Files Created (10 pts) ---
    if result.get('drawio_modified', False):
        score += 10
        feedback.append("Draw.io file saved.")
    else:
        feedback.append("Draw.io file missing or not saved.")

    # --- Criterion 2: Room Labels (25 pts) ---
    # We look for room names in the text labels
    rooms_found = 0
    missing_rooms = []
    for room in required_rooms:
        # Simple containment check
        if room.lower() in text_blob:
            rooms_found += 1
        else:
            missing_rooms.append(room)
    
    room_score = (rooms_found / len(required_rooms)) * 25
    score += room_score
    if rooms_found == len(required_rooms):
        feedback.append(f"All {len(required_rooms)} rooms found.")
    else:
        feedback.append(f"Found {rooms_found}/{len(required_rooms)} rooms. Missing: {', '.join(missing_rooms)}.")

    # --- Criterion 3: Logic Items (25 pts) ---
    items_found = 0
    missing_items = []
    for item in required_items:
        if item.lower() in text_blob:
            items_found += 1
        else:
            missing_items.append(item)
            
    item_score = (items_found / len(required_items)) * 25
    score += item_score
    if items_found == len(required_items):
        feedback.append(f"All {len(required_items)} logic items found.")
    else:
        feedback.append(f"Found {items_found}/{len(required_items)} logic items. Missing: {', '.join(missing_items)}.")

    # --- Criterion 4: Topology/Edges (20 pts) ---
    edge_count = analysis.get('edge_count', 0)
    if edge_count >= min_edges:
        score += 20
        feedback.append(f"Topology OK: {edge_count} connections found.")
    elif edge_count > 0:
        score += 10
        feedback.append(f"Topology Weak: Only {edge_count} connections found (expected > {min_edges}).")
    else:
        feedback.append("Topology Fail: No connections (edges) detected.")

    # --- Criterion 5: Export Validity (20 pts) ---
    if result.get('png_modified', False):
        score += 20
        feedback.append("PNG export successful.")
    else:
        feedback.append("PNG export missing.")

    # Calculate final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": round(score),
        "feedback": " ".join(feedback)
    }