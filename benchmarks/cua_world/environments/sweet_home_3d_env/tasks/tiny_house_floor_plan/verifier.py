#!/usr/bin/env python3
"""
Verifier for tiny_house_floor_plan task.

Evaluates an agent's ability to create a floor plan from scratch.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tiny_house_floor_plan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/tiny_house_floor_plan_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    # --- Anti-Gaming & Basic File Checks ---
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file not found. Ensure the file is saved properly."
        }
    
    file_mtime = result.get("file_mtime", 0)
    task_start_time = result.get("task_start_time", 0)
    if task_start_time > 0 and file_mtime < task_start_time:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming check failed: File predates task start time."
        }

    # --- Wrong-Target Gate ---
    total_furniture = result.get("total_furniture", 0)
    if total_furniture < 5:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong-target gate: Only {total_furniture} furniture items found. At least 5 required."
        }

    # C1: Walls (20 pts) -> >=6 total walls (partial >=4)
    walls = result.get("wall_count", 0)
    if walls >= 6:
        score += 20
        feedback_parts.append(f"C1: PASS — {walls} walls drawn [+20]")
    elif walls >= 4:
        score += 10
        feedback_parts.append(f"C1: PARTIAL — {walls} walls drawn (need >=6) [+10]")
    else:
        feedback_parts.append(f"C1: FAIL — only {walls} walls drawn (need >=6)")

    # C2: Doors + Windows (15 pts) -> >=1 door + >=3 windows (partial >=1 door + >=1 window)
    doors = result.get("doors", 0)
    windows = result.get("windows", 0)
    dw_total = result.get("door_window_count", 0)
    
    if doors >= 1 and windows >= 3:
        score += 15
        feedback_parts.append(f"C2: PASS — {doors} door(s) and {windows} window(s) placed [+15]")
    elif doors >= 1 and windows >= 1:
        score += 7
        feedback_parts.append(f"C2: PARTIAL — {doors} door(s) and {windows} window(s) (need >=3 windows) [+7]")
    elif dw_total >= 2:
        # Fallback if categorization fails
        score += 7
        feedback_parts.append(f"C2: PARTIAL — {dw_total} total doors/windows placed [+7]")
    else:
        feedback_parts.append(f"C2: FAIL — {doors} doors, {windows} windows placed")

    # C3: Room Definitions (15 pts) -> >=4 named rooms (partial >=2)
    rooms = result.get("room_count", 0)
    room_names = result.get("room_names", [])
    valid_names = [n for n in room_names if len(n.strip()) > 0]
    
    if rooms >= 4 and len(valid_names) >= 3:
        score += 15
        feedback_parts.append(f"C3: PASS — {rooms} rooms defined, {len(valid_names)} named [+15]")
    elif rooms >= 2:
        score += 7
        feedback_parts.append(f"C3: PARTIAL — {rooms} rooms defined (need >=4) [+7]")
    else:
        feedback_parts.append(f"C3: FAIL — only {rooms} rooms defined")

    # C4: Living + Kitchen Furniture (20 pts)
    sofas = result.get("sofas", 0)
    tables = result.get("tables", 0)
    chairs = result.get("chairs", 0)
    appliances = result.get("appliances", 0)
    
    if sofas >= 1 and tables >= 1 and chairs >= 2 and appliances >= 2:
        score += 20
        feedback_parts.append(f"C4: PASS — Living/Kitchen complete ({sofas} sofas, {tables} tables, {chairs} chairs, {appliances} apps) [+20]")
    elif (sofas >= 1 or chairs >= 1) and tables >= 1 and appliances >= 1:
        score += 10
        feedback_parts.append(f"C4: PARTIAL — Living/Kitchen incomplete ({sofas} sofas, {tables} tables, {chairs} chairs, {appliances} apps) [+10]")
    else:
        feedback_parts.append(f"C4: FAIL — Living/Kitchen missing core items")

    # C5: Bedroom + Bathroom Fixtures (15 pts)
    beds = result.get("beds", 0)
    shelves = result.get("shelves_wardrobes", 0)
    toilets = result.get("toilets", 0)
    sinks = result.get("sinks", 0)
    
    if beds >= 1 and shelves >= 1 and toilets >= 1 and sinks >= 1:
        score += 15
        feedback_parts.append(f"C5: PASS — Bed/Bath complete ({beds} beds, {shelves} shelves, {toilets} toilets, {sinks} sinks) [+15]")
    elif beds >= 1 and toilets >= 1:
        score += 7
        feedback_parts.append(f"C5: PARTIAL — Bed/Bath incomplete ({beds} beds, {toilets} toilets) [+7]")
    else:
        feedback_parts.append(f"C5: FAIL — Bed/Bath missing core fixtures")

    # C6: Dimensions + Total Items + Save Size (15 pts total)
    c6_score = 0
    c6_notes = []
    
    dims = result.get("valid_dimension_count", 0)
    if dims >= 2:
        c6_score += 5
        c6_notes.append(f"{dims} dims")
    elif dims == 1:
        c6_score += 2
        c6_notes.append(f"{dims} dim")
        
    if total_furniture >= 20:
        c6_score += 5
        c6_notes.append(f"{total_furniture} items")
    elif total_furniture >= 10:
        c6_score += 2
        c6_notes.append(f"{total_furniture} items")
        
    file_size = result.get("file_size", 0)
    if file_size > 1000:
        c6_score += 5
        c6_notes.append("saved properly")
        
    score += c6_score
    if c6_score == 15:
        feedback_parts.append(f"C6: PASS — Dimensions & Volumes ({', '.join(c6_notes)}) [+15]")
    elif c6_score > 0:
        feedback_parts.append(f"C6: PARTIAL — ({', '.join(c6_notes)}) [+{c6_score}]")
    else:
        feedback_parts.append("C6: FAIL — Missing dimensions, low items, or empty file")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }