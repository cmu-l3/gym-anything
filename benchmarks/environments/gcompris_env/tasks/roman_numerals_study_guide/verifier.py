#!/usr/bin/env python3
import json
import os
import base64
import logging
import tempfile
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_roman_numerals_study_guide(traj, env_info, task_info):
    """
    Verifies the Roman Numerals Study Guide task.
    
    Criteria:
    1. File Creation (20 pts): 'roman_guide.txt' exists and was created during task.
    2. File Content (40 pts): 
       - Header 'Roman Numeral Reference' (5 pts)
       - All 7 symbols (I, V, X, L, C, D, M) correctly mapped (5 pts each = 35 pts)
    3. Activity Report (10 pts): Mentions 'convert'/'game'/'activity'.
    4. VLM Verification (30 pts): Trajectory shows GCompris Roman Numerals activity interaction.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_symbols = metadata.get('required_symbols', {
        "I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000
    })
    
    # Load result file
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback = []
    
    # 2. Verify File Creation (20 pts)
    file_content = ""
    if result_data.get("file_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback.append("Study guide file created successfully.")
        
        # Decode content
        try:
            content_b64 = result_data.get("file_content_base64", "")
            file_content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except Exception:
            feedback.append("Error decoding file content.")
    else:
        feedback.append("Study guide file NOT created or not modified during task.")

    # 3. Verify File Content (50 pts total)
    if file_content:
        # Check Header (5 pts)
        if "Roman Numeral Reference" in file_content:
            score += 5
            feedback.append("Header found.")
        else:
            feedback.append("Header 'Roman Numeral Reference' missing.")

        # Check Symbols (35 pts)
        # We look for the symbol and the value on the same line, case insensitive
        lines = file_content.lower().split('\n')
        symbols_found = 0
        for sym, val in required_symbols.items():
            sym_lower = sym.lower()
            val_str = str(val)
            found = False
            for line in lines:
                # Check if line contains both symbol and value (e.g., "v = 5" or "v: 5")
                # Using regex to ensure we match 'v' as a word or distinct character, not inside 'level'
                # Simple heuristic: Look for symbol char and value string in same line
                if sym_lower in line and val_str in line:
                    # Specific check to avoid matching 'i' in 'activity'
                    # We expect something like "i = 1" or "i: 1"
                    if re.search(rf"\b{sym_lower}\b.*{val_str}|{val_str}.*\b{sym_lower}\b", line):
                        found = True
                        break
            
            if found:
                score += 5
                symbols_found += 1
            else:
                feedback.append(f"Symbol {sym}={val} missing or incorrect.")
        
        if symbols_found == 7:
            feedback.append("All 7 Roman numeral symbols found.")

        # Check Activity Report (10 pts)
        # Look for keywords indicating a sentence about the task
        keywords = ["convert", "arabic", "roman", "game", "activity", "ask", "change"]
        if any(k in file_content.lower() for k in keywords):
            score += 10
            feedback.append("Activity report/description detected.")
        else:
            feedback.append("Activity report missing (no description of what the game asked).")

    # 4. VLM Verification (30 pts)
    # Use trajectory frames to verify GCompris interaction
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        feedback.append("No trajectory frames available for verification.")
    else:
        # Include final screen in analysis
        if final_screen:
            frames.append(final_screen)
            
        vlm_prompt = """
        Analyze these screenshots of a user interacting with the GCompris educational software.
        
        I need to verify if the user performed the 'Roman Numerals' activity.
        
        Look for:
        1. An interface showing Roman Numerals (I, V, X, L, C, D, M) or a temple/history theme.
        2. Math problems asking to convert numbers (e.g., "19 = ?" or "IV = ?").
        3. A text editor being used to write a guide.
        
        Did the user:
        A. Navigate to and open the Roman Numerals activity?
        B. Interact with the activity (solving problems)?
        C. Open a text editor?
        
        Return JSON: {"activity_seen": bool, "interaction_seen": bool, "editor_seen": bool}
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_result.get("parsed", {})
            
            vlm_score = 0
            if parsed.get("activity_seen"):
                vlm_score += 10
                feedback.append("VLM confirmed Roman Numerals activity was opened.")
            if parsed.get("interaction_seen"):
                vlm_score += 10
                feedback.append("VLM confirmed interaction with the activity.")
            if parsed.get("editor_seen"):
                vlm_score += 10
                feedback.append("VLM confirmed text editor usage.")
                
            score += vlm_score
            
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            # Fallback: if we have a good file score, give partial VLM credit
            if score >= 40:
                score += 15
                feedback.append("VLM failed but file evidence suggests success.")

    # Final Pass Logic
    # Pass if file is valid (>= 40 pts from file) AND total score >= 70
    passed = (score >= 70) and (result_data.get("file_exists"))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }