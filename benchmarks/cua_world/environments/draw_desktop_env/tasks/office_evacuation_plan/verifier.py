#!/usr/bin/env python3
"""
Verifier for office_evacuation_plan task.
"""

import json
import tempfile
import os

def verify_office_evacuation_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Read error: {e}"}
    finally:
        if os.path.exists(temp_file.name): os.unlink(temp_file.name)

    score = 0
    feedback = []
    analysis = result.get("analysis", {})
    
    # 1. File Saved (10 pts)
    if result.get("file_exists") and result.get("file_modified_after_start"):
        score += 10
        feedback.append("File saved")
    else:
        feedback.append("File not saved")

    # 2. Rooms Found (20 pts)
    # Required: Reception, Workspace, Conference, Kitchen, Server
    rooms_found = analysis.get("rooms_found", [])
    required_rooms = ["reception", "workspace", "conference", "kitchen", "server"]
    found_count = len([r for r in required_rooms if r in rooms_found])
    
    if found_count >= 5:
        score += 20
        feedback.append(f"All {found_count} rooms labeled")
    elif found_count >= 3:
        score += 10
        feedback.append(f"Partial rooms labeled ({found_count}/5)")
    else:
        feedback.append(f"Missing room labels (found {found_count}/5)")

    # 3. Safety Symbols (25 pts)
    # Required: Extinguisher, Alarm, Exit
    symbols_found = analysis.get("symbols_found", [])
    has_extinguisher = "extinguisher" in symbols_found or "fire" in symbols_found
    has_alarm = "alarm" in symbols_found
    has_exit = "exit" in symbols_found
    
    symbol_score = 0
    if has_extinguisher: symbol_score += 10
    if has_alarm: symbol_score += 10
    if has_exit: symbol_score += 5
    score += symbol_score
    
    if symbol_score == 25:
        feedback.append("All safety symbols found")
    else:
        feedback.append(f"Missing symbols (Score: {symbol_score}/25)")

    # 4. Egress Paths (Green + Dashed) (35 pts total)
    green_edges = analysis.get("green_edges", 0)
    dashed_edges = analysis.get("dashed_edges", 0)
    
    if green_edges >= 2:
        score += 20
        feedback.append(f"Green egress paths found ({green_edges})")
    elif green_edges >= 1:
        score += 10
        feedback.append("Only 1 green path found")
    else:
        feedback.append("No green paths found")
        
    if dashed_edges >= 1:
        score += 15
        feedback.append("Dashed secondary route found")
    else:
        feedback.append("No dashed edges found")

    # 5. Extras (Assembly Point + Legend) (10 pts)
    extras = 0
    if analysis.get("assembly_point"): extras += 5
    if analysis.get("legend_found"): extras += 5
    score += extras
    if extras > 0: feedback.append("Assembly/Legend details found")

    # PNG Check (Bonus/Validation check - no extra points but good for logging)
    if result.get("png_exists") and result.get("png_size", 0) > 1000:
        feedback.append("PNG export valid")
    else:
        feedback.append("PNG export missing/empty")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }