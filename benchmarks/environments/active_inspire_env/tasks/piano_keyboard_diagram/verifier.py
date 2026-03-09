#!/usr/bin/env python3
"""Verifier for Piano Keyboard Diagram task.

Hybrid verification strategy:
1. Programmatic: Check file existence, valid XML structure, shape counts, and text content.
2. VLM: Visual check for correct spatial arrangement (2 black keys, gap, 3 black keys) and labeling alignment.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_piano_prompt():
    return """
    Examine this screenshot of an ActivInspire flipchart.
    The user was tasked with drawing a one-octave piano keyboard diagram.
    
    Please verify the following strictly:
    1. **Structure**: Are there white keys and black keys visible?
    2. **Pattern**: Do the black keys follow the correct piano pattern?
       - Look for a group of **2 black keys**, then a gap, then a group of **3 black keys**.
       - This is the most critical visual check.
    3. **Alignment**: Are the black keys shorter and placed "between" or on top of the white keys?
    4. **Labels**: Are there letters C, D, E, F, G, A, B visible on the white keys?
       - "C" should be to the left of the 2-black-key group.
    
    Respond in JSON:
    {
        "is_piano_diagram": true/false,
        "black_key_pattern_correct": true/false,
        "labels_visible": true/false,
        "labels_aligned_correctly": true/false,
        "confidence": "low/medium/high",
        "reasoning": "..."
    }
    """

def verify_piano_keyboard_diagram(traj, env_info, task_info):
    """
    Verify the piano keyboard diagram task.
    
    Scoring Breakdown (100 pts):
    - File Valid & Created: 20 pts
    - Rectangle Count >= 12: 25 pts
    - Text Labels (XML check): 20 pts (2.5 per label)
    - VLM Visual Pattern Check: 35 pts (Pattern=20, Alignment=15)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}
        
    # Load JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result read failed: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (65 pts total)
    
    # Criterion A: File Existence & Validity (20 pts)
    if result.get("file_found") and result.get("file_valid") and result.get("created_during_task"):
        score += 20
        feedback.append("Valid flipchart created.")
    else:
        feedback.append("Flipchart file missing, invalid, or pre-existing.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion B: Shape Count (25 pts)
    # 7 white + 5 black = 12 rectangles minimum.
    rect_count = result.get("rectangle_count", 0)
    if rect_count >= 12:
        score += 25
        feedback.append(f"Sufficient rectangles found ({rect_count}).")
    elif rect_count >= 7:
        score += 10
        feedback.append(f"Partial rectangles found ({rect_count}/12).")
    else:
        feedback.append(f"Not enough rectangles for a keyboard ({rect_count}).")

    # Criterion C: Text Content (20 pts)
    # Expected flags: Title, C, D, E, F, G, A, B
    text_flags = result.get("text_flags", "0,0,0,0,0,0,0,0").split(',')
    # We ignore the title index for the 'note' count, check it separately if desired, 
    # but the task spec grouped them. Let's count total flags matching '1'.
    found_text_count = sum(1 for f in text_flags if f == '1')
    
    # 8 items total (Title + 7 notes). 
    # 20 points / 8 items = 2.5 pts each.
    text_score = found_text_count * 2.5
    score += text_score
    if found_text_count == 8:
        feedback.append("All text labels found.")
    else:
        feedback.append(f"Found {found_text_count}/8 text labels.")

    # 3. VLM Verification (35 pts total)
    if query_vlm:
        screenshot = get_final_screenshot(traj)
        if screenshot and os.path.exists(screenshot):
            vlm_res = query_vlm(prompt=build_piano_prompt(), image=screenshot)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                # Visual Pattern (20 pts)
                if parsed.get("black_key_pattern_correct"):
                    score += 20
                    feedback.append("Visual check: Black key pattern correct.")
                else:
                    feedback.append("Visual check: Black key pattern incorrect or unclear.")
                
                # Alignment/Labels (15 pts)
                if parsed.get("labels_aligned_correctly") or parsed.get("labels_visible"):
                    score += 15
                    feedback.append("Visual check: Labels aligned.")
                else:
                    feedback.append("Visual check: Labels missing or misaligned.")
            else:
                feedback.append("VLM analysis failed.")
        else:
            feedback.append("No screenshot available for visual verification.")
    else:
        feedback.append("VLM not available; skipping visual scoring.")
        # Fallback: Scale current score to 100 if VLM is strictly unavailable? 
        # Usually better to penalize or accept partial score in strict verification modes.
        # Here we leave score as is to encourage VLM availability.

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " ".join(feedback)
    }