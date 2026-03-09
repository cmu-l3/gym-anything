#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stage_plot(traj, env_info, task_info):
    """
    Verifies the Concert Stage Plot & Input List task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Scoring Criteria ---

    # 1. Files Created (20 pts)
    if result.get("drawio_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("Draw.io file created.")
    else:
        feedback.append("Draw.io file missing or not created during task.")

    if result.get("pdf_exists"):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # 2. Text Content Analysis (Keywords) (30 pts)
    # Check for essential items from the Input List and Plot
    required_keywords = [
        "Neon Velvet", # Title
        "Kick", "Snare", # Input List
        "SVT", "Ampeg", # Bass Gear
        "Twin", "Fender", # Guitar Gear
        "Nord", # Keys Gear
        "Monitor", # Wedges
        "Beta 52", "SM57" # Mics
    ]
    
    all_text = " ".join(result.get("text_content", [])).lower()
    found_keywords = 0
    for kw in required_keywords:
        if kw.lower() in all_text:
            found_keywords += 1
    
    # Scale score based on keywords found
    keyword_score = min(30, int((found_keywords / len(required_keywords)) * 30))
    score += keyword_score
    feedback.append(f"Content Check: Found {found_keywords}/{len(required_keywords)} keywords ({keyword_score} pts).")

    # 3. Spatial Logic (30 pts)
    # Retrieve identified shapes from export analysis
    shapes = result.get("shapes", [])
    
    # Helper to find shape by type
    def get_shape(stype):
        return next((s for s in shapes if s["type"] == stype), None)

    drums = get_shape("Drums")
    vocals = get_shape("Vocals")
    keys = get_shape("Keys")
    guitar = get_shape("Guitar")

    # Check: Drums Upstage of Vocals (Upstage = Lower Y value in diagram usually, OR smaller Y? 
    # Actually in computer graphics, Y increases downwards.
    # Upstage (back of stage) is visually 'higher' on the screen, so SMALLER Y value.
    # Downstage (front of stage/audience) is visually 'lower', so LARGER Y value.
    if drums and vocals:
        if drums["y"] < vocals["y"]:
            score += 15
            feedback.append("Spatial: Drums correctly placed Upstage (behind) Vocals.")
        else:
            feedback.append(f"Spatial: Drums ({drums['y']}) seem Downstage/Below Vocals ({vocals['y']}) - Incorrect.")
    else:
        feedback.append("Spatial: Could not find Drums or Vocals shapes to compare.")

    # Check: Keys (Stage Right/Audience Left) vs Guitar (Stage Left/Audience Right)
    # Audience Left = LEFT side of screen = SMALLER X value.
    if keys and guitar:
        if keys["x"] < guitar["x"]:
            score += 15
            feedback.append("Spatial: Keys correctly placed Stage Right (Left side).")
        else:
            feedback.append("Spatial: Keys seem to be Stage Left (Right side) of Guitar - Incorrect.")
    else:
        feedback.append("Spatial: Could not find Keys or Guitar shapes to compare.")

    # 4. Input List Table Structure (20 pts)
    # Hard to verify exact table structure from XML text dump, but we verify identifying marks
    # Look for sequential numbers which suggest a list
    if "01" in all_text and "16" in all_text and "channel" in all_text:
        score += 20
        feedback.append("Input List: structure detected (channel numbers and header).")
    elif "kick" in all_text and "vocal" in all_text:
        # Partial credit if data is there but numbering/header missing
        score += 10
        feedback.append("Input List: Content found but table structure unclear.")
    else:
        feedback.append("Input List: Missing key input list data.")

    # Final tally
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }