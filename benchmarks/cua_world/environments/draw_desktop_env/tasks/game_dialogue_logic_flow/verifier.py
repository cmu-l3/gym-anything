#!/usr/bin/env python3
import json
import os
import sys
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_game_dialogue_logic_flow(traj, env_info, task_info):
    """
    Verifies the Game Dialogue Logic Flow task.
    
    Criteria:
    1. Files (.drawio, .png) created during task.
    2. Logic Nodes: At least 3 diamond/rhombus shapes for logic checks.
    3. Complexity: At least 12 nodes total.
    4. Content: Text matches script keywords (Streetwise, 2000 Credits, etc).
    5. VLM: Confirms visual flowchart structure.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result load failed: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    score = 0
    feedback = []
    
    # 2. Programmatic Verification (60 points)
    
    # File Checks (10 pts)
    if result.get('file_created_during_task'):
        score += 10
        feedback.append("Draw.io file created.")
    else:
        feedback.append("No new .drawio file found.")
        
    if result.get('png_exists'):
        score += 5  # Bonus 5 for export
        feedback.append("PNG export found.")

    # Complexity Checks (15 pts)
    node_count = analysis.get('node_count', 0)
    edge_count = analysis.get('edge_count', 0)
    
    if node_count >= 12:
        score += 10
        feedback.append(f"Node count good ({node_count}).")
    elif node_count >= 5:
        score += 5
        feedback.append(f"Node count low ({node_count}/12).")
        
    if edge_count >= 8:
        score += 5
        feedback.append(f"Edge count good ({edge_count}).")

    # Shape Semantics (20 pts)
    # Looking for Diamonds (Logic) and Ellipses (Endings)
    diamond_count = analysis.get('diamond_count', 0)
    if diamond_count >= 3:
        score += 15
        feedback.append("Logic checks (diamonds) correctly used.")
    elif diamond_count >= 1:
        score += 5
        feedback.append("Some logic checks found, but fewer than expected (need 3).")
    else:
        feedback.append("No logic check (diamond) shapes detected.")
        
    ellipse_count = analysis.get('ellipse_count', 0)
    if ellipse_count >= 3:
        score += 5
        feedback.append("Ending nodes (ellipses) found.")

    # Content Matching (15 pts)
    required_phrases = ["streetwise", "2000", "neural", "police", "arrested", "combat", "fixer"]
    found_text = " ".join(analysis.get('text_content', [])).lower()
    
    matches = sum(1 for p in required_phrases if p in found_text)
    if matches >= 5:
        score += 15
        feedback.append(f"Text content matches script ({matches} keywords).")
    elif matches >= 2:
        score += 8
        feedback.append(f"Some text content missing ({matches} keywords).")
    else:
        feedback.append("Diagram text does not match script.")

    # 3. VLM Verification (40 points)
    # Use VLM to confirm it actually looks like a flowchart and handles the layout logic
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this agent's work in draw.io. They were supposed to create a flowchart for a game quest.
    1. Does the final image show a connected flowchart structure (boxes connected by arrows)?
    2. Are there branching paths (decisions splitting into multiple lines)?
    3. Are different shapes used (e.g., diamonds for decisions, rectangles for text)?
    
    Respond in JSON: {"is_flowchart": bool, "has_branching": bool, "visual_differentiation": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
        # Clean markdown
        if "