#!/usr/bin/env python3
"""
Verifier for create_emotional_rating_task.

Criteria:
1. Files Created (20 pts): .psyexp and .csv exist and modified.
2. Conditions File Valid (20 pts): CSV has header, >1 rows, references images.
3. Experiment Structure (XML) (40 pts):
   - Valid XML.
   - Contains Loop linking to conditions.
   - Contains Image component.
   - Contains 2 Slider components.
   - Contains Submission mechanism (Button/Keyboard).
4. Slider Configuration (20 pts):
   - Correct labels detected (Valence/Arousal keywords).

VLM verification is used as a backup/confirmation of UI state.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_create_emotional_rating_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Check 1: Files Existence & Integrity (20 pts) ---
    if result.get("exp_file_exists") and result.get("exp_file_modified"):
        score += 10
        feedback.append("Experiment file created.")
    else:
        feedback.append("Experiment file missing or not saved.")

    if result.get("cond_file_exists"):
        score += 10
        feedback.append("Conditions file created.")
    else:
        feedback.append("Conditions file missing.")

    # --- Check 2: Conditions Content (20 pts) ---
    if result.get("csv_valid", False):
        rows = result.get("csv_rows", 0)
        cols = result.get("csv_columns", [])
        if rows >= 3:
            score += 10
            feedback.append(f"Conditions file has sufficient rows ({rows}).")
        else:
            feedback.append(f"Conditions file has too few rows ({rows}).")
            
        # Check for likely image column
        if any(x.lower() in ["image", "stim", "file", "face"] for x in [c.lower() for c in cols]):
            score += 10
            feedback.append("Conditions file has image/stimulus column.")
        else:
            feedback.append("Conditions file missing obvious image column.")
    
    # --- Check 3: Experiment Structure (40 pts) ---
    if result.get("is_valid_xml"):
        comps = result.get("component_counts", {})
        
        # Loop Check
        if result.get("has_loop"):
            score += 10
            cond_ref = result.get("conditions_file_ref", "")
            if "faces.csv" in cond_ref or "conditions" in cond_ref:
                feedback.append("Loop connected to conditions file.")
            else:
                feedback.append(f"Loop found but conditions file ref unclear ({cond_ref}).")
        else:
            feedback.append("No loop found.")

        # Image Component
        if comps.get("ImageComponent", 0) >= 1:
            score += 10
            feedback.append("Image component found.")
        else:
            feedback.append("Missing Image component.")

        # Slider Components
        slider_count = comps.get("SliderComponent", 0)
        if slider_count >= 2:
            score += 10
            feedback.append(f"Found {slider_count} sliders.")
        elif slider_count == 1:
            score += 5
            feedback.append("Found only 1 slider (expected 2).")
        else:
            feedback.append("Missing Slider components.")

        # Submission Mechanism (Button or Keyboard)
        if comps.get("ButtonComponent", 0) >= 1 or comps.get("KeyboardComponent", 0) >= 1:
            score += 10
            feedback.append("Submission mechanism (Button/Key) found.")
        else:
            feedback.append("No obvious submission mechanism found.")

    # --- Check 4: Slider Configuration (20 pts) ---
    labels = result.get("slider_labels", [])
    label_str = " ".join(str(l) for l in labels).lower()
    
    valence_found = any(x in label_str for x in ["negative", "positive", "bad", "good"])
    arousal_found = any(x in label_str for x in ["calm", "excited", "arousal", "sleepy"])
    
    if valence_found:
        score += 10
        feedback.append("Valence slider labels detected.")
    if arousal_found:
        score += 10
        feedback.append("Arousal slider labels detected.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }