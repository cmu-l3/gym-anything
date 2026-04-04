#!/usr/bin/env python3
"""
Verifier for mobile_app_wireframe_prd task.
Verifies structure, content, and export of a draw.io wireframe.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mobile_app_wireframe_prd(traj, env_info, task_info):
    """
    Verify the mobile app wireframe task using:
    1. Programmatic checks on the exported draw.io XML structure (pages, shapes, text).
    2. Verification of PNG export.
    3. VLM verification of the process via trajectory frames.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', [])

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    analysis = result.get('analysis', {})
    
    # --- CRITERION 1: File Status (10 pts) ---
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("File created and modified (+10)")
    else:
        feedback.append("File not modified or missing (0)")
        return {"passed": False, "score": 0, "feedback": "Task failed: No work saved."}

    # --- CRITERION 2: Page Structure (15 pts) ---
    page_count = analysis.get('page_count', 0)
    expected_pages = 5
    if page_count >= expected_pages:
        score += 15
        feedback.append(f"Correct page count ({page_count}) (+15)")
    elif page_count >= 3:
        score += 8
        feedback.append(f"Partial page count ({page_count}/{expected_pages}) (+8)")
    else:
        feedback.append(f"Insufficient pages ({page_count}/{expected_pages})")

    # --- CRITERION 3: Page Naming (5 pts) ---
    # Check if page names match PRD (Home, Trip Planner, etc)
    page_names = [n.lower() for n in analysis.get('page_names', [])]
    expected_names = ["home", "trip", "result", "detail", "alert"]
    matched_names = sum(1 for exp in expected_names if any(exp in name for name in page_names))
    if matched_names >= 4:
        score += 5
        feedback.append("Page names match PRD (+5)")
    
    # --- CRITERION 4: Content/Shapes (20 pts) ---
    total_shapes = analysis.get('total_shapes', 0)
    # A full 5-screen wireframe should have many shapes (buttons, inputs, cards)
    # PRD implies ~10-15 shapes per screen. Expect at least 50 total.
    if total_shapes >= 50:
        score += 20
        feedback.append(f"Sufficient UI components ({total_shapes}) (+20)")
    elif total_shapes >= 25:
        score += 10
        feedback.append(f"Sparse UI components ({total_shapes}) (+10)")
    else:
        feedback.append(f"Too few shapes ({total_shapes})")

    # --- CRITERION 5: Text Content Accuracy (15 pts) ---
    all_text = analysis.get('all_text', "")
    found_labels = [lbl for lbl in required_labels if lbl.lower() in all_text]
    label_ratio = len(found_labels) / len(required_labels)
    
    if label_ratio >= 0.8:
        score += 15
        feedback.append("Content text matches PRD specs well (+15)")
    elif label_ratio >= 0.5:
        score += 7
        feedback.append("Some content text matches PRD (+7)")
    else:
        feedback.append("Missing many required text labels from PRD")

    # --- CRITERION 6: Navigation/Edges (10 pts) ---
    total_edges = analysis.get('total_edges', 0)
    if total_edges >= 4:
        score += 10
        feedback.append("Navigation flows added (+10)")
    else:
        feedback.append("Missing navigation flow arrows")

    # --- CRITERION 7: PNG Export (10 pts) ---
    if result.get('png_exists') and result.get('png_size', 0) > 5000:
        score += 10
        feedback.append("PNG export successful (+10)")
    else:
        feedback.append("PNG export missing or invalid")

    # --- CRITERION 8: VLM Process Verification (15 pts) ---
    # Use trajectory frames to confirm the agent actually built this in the UI
    # and didn't just paste XML or do nothing.
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of a user using Diagrams.net (draw.io).
    The user is tasked with creating a mobile app wireframe with 5 screens (Home, Trip Planner, etc).
    
    Look for:
    1. Multiple pages being created (tabs at bottom).
    2. Mobile-like wireframe shapes (rectangles, lists, buttons) being placed.
    3. Text labels matching a transit app (e.g. "Plan Trip", "Bus 42").
    4. Arrows connecting screens.
    
    Did the user perform meaningful wireframing work corresponding to these requirements?
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt,
        options=["Yes, work visible", "No/Unclear"]
    )
    
    if vlm_result == "Yes, work visible":
        score += 15
        feedback.append("Visual verification passed (+15)")
    else:
        feedback.append("Visual verification failed (work not clearly visible in screenshots)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }