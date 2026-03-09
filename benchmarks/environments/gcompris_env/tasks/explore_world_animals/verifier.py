#!/usr/bin/env python3
"""
Verifier for explore_world_animals task.

Evaluates:
1. Report file existence and creation time (Anti-gaming).
2. Report content formatting and validity (Real data check).
3. VLM verification of trajectory (Workflow check).
"""

import json
import os
import re
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_explore_world_animals(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    known_animals = set(a.lower() for a in metadata.get('known_animals', []))
    min_entries = metadata.get('min_entries', 5)

    # --- Criterion 1: Report File Existence & Timestamp (15 pts) ---
    if result.get('report_exists'):
        if result.get('file_created_during_task'):
            score += 15
            feedback_parts.append("Report file created successfully.")
        else:
            score += 5
            feedback_parts.append("Report file exists but has old timestamp (pre-task?).")
    else:
        feedback_parts.append("Report file not found.")

    # --- Criterion 2: Report Content Analysis (40 pts) ---
    content = result.get('report_content', '')
    lines = [l.strip() for l in content.split('\n') if l.strip()]
    
    valid_entries = 0
    has_header = False
    has_footer = False
    
    if lines:
        # Check Header
        if "GCompris World Animals Report" in lines[0]:
            score += 5
            has_header = True
            feedback_parts.append("Header valid.")
        
        # Check Entries
        # Regex for "Region: [Name] - Animal: [Name]"
        entry_pattern = re.compile(r"Region:\s*(.+?)\s*-\s*Animal:\s*(.+)", re.IGNORECASE)
        
        found_animals = []
        for line in lines:
            match = entry_pattern.match(line)
            if match:
                region, animal = match.groups()
                # Check if animal is likely real/valid
                # We check if the extracted animal name contains any of our known keywords
                animal_lower = animal.lower()
                is_valid_animal = any(k in animal_lower for k in known_animals)
                
                if is_valid_animal:
                    valid_entries += 1
                    found_animals.append(animal)
        
        # Check Footer
        if any("Total animals explored:" in l for l in lines):
            score += 5
            has_footer = True
            feedback_parts.append("Footer valid.")

    # Score entries
    # 5 pts per valid entry up to min_entries (5 * 6 = 30 pts max for content body)
    entry_score = min(valid_entries, min_entries) * 6
    score += entry_score
    feedback_parts.append(f"Found {valid_entries} valid animal entries.")

    if valid_entries < min_entries:
        feedback_parts.append(f"Expected at least {min_entries} entries.")

    # --- Criterion 3: Agent Screenshot (10 pts) ---
    if result.get('agent_screenshot_exists'):
        score += 10
        feedback_parts.append("Agent screenshot saved.")
    else:
        feedback_parts.append("Agent failed to save screenshot.")

    # --- Criterion 4: VLM Trajectory Verification (35 pts) ---
    # We check if the agent actually visited the World Animals activity
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        frames = [final_screen] if final_screen else []

    vlm_prompt = """
    Analyze these screenshots of a user using GCompris educational software.
    I need to verify if the user navigated to and used the 'Explore World Animals' activity.
    
    Look for:
    1. A world map view with continent highlights.
    2. Popups or text showing information about animals (e.g., photos of animals, text descriptions).
    3. Navigation through the GCompris menu (icons like a cat, penguin, globe).
    
    Did the user successfully access the World Animals map/activity?
    """

    vlm_result = query_vlm(
        images=frames,
        prompt=vlm_prompt
    )
    
    vlm_passed = False
    if vlm_result and vlm_result.get('success'):
        # Simple heuristic on VLM response
        text = vlm_result.get('parsed', {}).get('response', '').lower()
        # Or if the framework returns a direct boolean in 'parsed'
        # Assuming standard text response for now, looking for positive confirmation
        # Ideally, use a structured VLM query if supported, but here we assume the VLM wrapper handles it.
        # Let's try a structured check pattern if the VLM output is just text.
        
        # Re-query with structured prompt if needed, or parse text.
        # Let's assume the VLM returns a boolean 'yes'/'no' or we parse the explanation.
        # Better approach:
        check_prompt = "Respond with JSON: {\"activity_visible\": boolean, \"animal_info_seen\": boolean}"
        vlm_check = query_vlm(images=frames, prompt=vlm_prompt + "\n" + check_prompt)
        
        parsed = vlm_check.get('parsed', {})
        if parsed.get('activity_visible') or parsed.get('animal_info_seen'):
            vlm_passed = True
            score += 35
            feedback_parts.append("VLM verified activity usage.")
        else:
            feedback_parts.append("VLM could not verify activity usage from screenshots.")
    else:
        # Fallback if VLM fails (give benefit of doubt if text report is perfect?)
        # No, strict verification requires evidence.
        feedback_parts.append("VLM verification failed to run.")

    # Final Pass/Fail
    # Pass if score >= 70 AND valid entries >= 3 AND VLM confirmed
    passed = (score >= 70) and (valid_entries >= 3) and vlm_passed

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }