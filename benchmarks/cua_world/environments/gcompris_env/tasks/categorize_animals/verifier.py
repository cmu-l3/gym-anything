#!/usr/bin/env python3
"""
Verifier for GCompris Categorize Animals task.
Uses VLM trajectory analysis as primary signal, supported by programmatic checks.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_categorize_animals(traj, env_info, task_info):
    """
    Verify the agent categorized animals correctly in GCompris.
    
    Scoring Breakdown (100 pts total):
    - Programmatic (10 pts):
        - App still running: 5 pts
        - Data/Progress modified: 5 pts
    - VLM Trajectory (90 pts):
        - Left Main Menu: 10 pts
        - Accessed Discovery Section: 15 pts
        - Opened Categorization Activity: 25 pts
        - Visible Sorting Interaction (Items moved): 20 pts
        - Success/Bonus Screen Visible: 20 pts
    """
    
    # 1. Setup & Programmatic Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # Load JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Score Programmatic Signals
    if result.get("app_running", False):
        score += 5
        feedback.append("GCompris application is active (+5)")
    else:
        feedback.append("GCompris was closed (0)")

    if result.get("data_modified", False):
        score += 5
        feedback.append("Activity progress data detected (+5)")
    
    # 2. VLM Trajectory Analysis
    # We use trajectory frames to verify the workflow steps
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    Analyze these screenshots of an agent using GCompris educational software.
    The agent's goal is to:
    1. Navigate from the Main Menu to the 'Discovery' section.
    2. Open the 'Categorization' activity (sorting items).
    3. Complete an 'Animals' sorting level (drag animals to boxes).
    4. See the congratulations/bonus animation (e.g., flower, penguin, stars).

    Evaluate the following milestones based on the visual evidence:
    
    1. LEFT_MAIN_MENU: Did the agent leave the starting grid/menu?
    2. DISCOVERY_SECTION: Did the agent enter the Discovery section (often has lightbulb/magnifying glass icon, or different set of activities)?
    3. CATEGORIZATION_OPEN: Is the categorization interface visible (showing items to sort and category boxes)?
    4. INTERACTION: Is there evidence of items being moved/sorted (items in boxes, mouse dragging)?
    5. SUCCESS: Is a success animation or "Great!" message visible?

    Respond in JSON format:
    {
        "left_main_menu": boolean,
        "discovery_section": boolean,
        "categorization_open": boolean,
        "interaction_visible": boolean,
        "success_screen": boolean,
        "reasoning": "string explaining what you see"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        analysis = vlm_result.get("parsed", {})
        logger.info(f"VLM Analysis: {analysis}")
        
        # Apply Scoring
        if analysis.get("left_main_menu"):
            score += 10
            feedback.append("Navigated from menu (+10)")
            
        if analysis.get("discovery_section"):
            score += 15
            feedback.append("Found Discovery section (+15)")
            
        if analysis.get("categorization_open"):
            score += 25
            feedback.append("Opened Categorization activity (+25)")
            
        if analysis.get("interaction_visible"):
            score += 20
            feedback.append("Performed sorting actions (+20)")
            
        if analysis.get("success_screen"):
            score += 20
            feedback.append("Level completed successfully (+20)")
    else:
        feedback.append("VLM verification failed (visual evidence check skipped)")

    # 3. Final Determination
    passed = score >= 60  # Threshold allows passing if they did the work but maybe missed one minor visual cue
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": vlm_result.get("parsed", {}) if vlm_result.get("success") else {}
    }