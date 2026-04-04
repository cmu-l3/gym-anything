#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_saas_roadmap_timeline(traj, env_info, task_info):
    """
    Verifies the SaaS Roadmap Timeline task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # 1. Load results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    analysis = data.get("analysis", {})
    
    # 2. Verify Files (20 pts)
    if data.get("drawio_created"):
        score += 10
        feedback.append("Draw.io file saved.")
    else:
        feedback.append("Missing .drawio file.")

    if data.get("png_created"):
        score += 10
        feedback.append("PNG export saved.")
    else:
        feedback.append("Missing .png file.")

    # 3. Verify Structure (20 pts)
    teams_found = len(analysis.get("teams_found", []))
    if teams_found >= 3:
        score += 20
        feedback.append("All 3 team swimlanes found.")
    elif teams_found > 0:
        score += 10
        feedback.append(f"Found {teams_found}/3 team swimlanes.")
    else:
        feedback.append("No team swimlanes detected.")

    if analysis.get("swimlane_structure"):
        feedback.append("(Swimlane shapes used).")
    
    # 4. Verify Timeline (10 pts)
    quarters_found = len(analysis.get("quarters_found", []))
    if quarters_found >= 4:
        score += 10
        feedback.append("Full Q1-Q4 timeline detected.")
    else:
        feedback.append(f"Timeline incomplete: found {quarters_found}/4 quarters.")

    # 5. Verify Content/Tasks (30 pts)
    tasks_found = len(analysis.get("tasks_found", []))
    # Expecting 6 tasks + 1 milestone
    if tasks_found >= 6:
        score += 30
        feedback.append("All roadmap initiatives found.")
    elif tasks_found >= 3:
        score += 15
        feedback.append(f"Found {tasks_found}/6 initiatives.")
    else:
        feedback.append("Most initiatives missing.")

    if analysis.get("milestone_found"):
        score += 5  # Bonus within this category
        feedback.append("Milestone diamond found.")

    # 6. Verify Styling/Colors (20 pts)
    # Check for Green, Blue, Red usage
    # Hex codes vary by palette, usually:
    # Green: #d5e8d4, #82b366
    # Blue: #dae8fc, #6c8ebf
    # Red: #f8cecc, #b85450
    colors = [c.lower() for c in analysis.get("colors_used", []) if c and c != "none"]
    has_green = any("d5e8" in c or "82b3" in c or "green" in c for c in colors)
    has_blue = any("dae8" in c or "6c8e" in c or "blue" in c for c in colors)
    has_red = any("f8ce" in c or "b854" in c or "red" in c for c in colors)
    
    color_score = 0
    if has_green: color_score += 7
    if has_blue: color_score += 7
    if has_red: color_score += 6
    
    # Cap color score at 20
    score += min(20, color_score)
    if color_score > 0:
        feedback.append("Color coding applied.")
    else:
        feedback.append("No color coding detected.")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }