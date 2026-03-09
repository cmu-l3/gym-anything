#!/usr/bin/env python3
"""
Verifier for concert_stage_plot_input_list task.

Criteria:
1. File Existence: .drawio and .png files created.
2. Anti-Gaming: Files modified after task start.
3. Content (XML Analysis):
   - Instrument keywords found (Drums, Bass, Guitar, Keys).
   - Spatial Layout: 
     - Drums (Rear) should have smaller Y than Vocals (Front).
     - Bass (Stage Right/House Left) should have smaller X than Guitar (Stage Left/House Right).
   - Input List:
     - Specific mic models found (Beta 91A, SM57, e906, etc).
     - Channel numbers (1-10) found.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_concert_stage_plot_input_list(traj, env_info, task_info):
    # Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. File Existence & modification (10 pts)
    if result.get("file_exists") and result.get("file_modified_during_task"):
        score += 5
        feedback.append("Draw.io file created and modified.")
    else:
        feedback.append("Draw.io file missing or not modified.")
    
    if result.get("png_exists"):
        score += 5
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    # 2. Content Analysis
    analysis = result.get("analysis", {})
    if not analysis.get("parsed"):
        return {"passed": False, "score": score, "feedback": "Could not parse draw.io file XML. " + " ".join(feedback)}

    shapes = analysis.get("shapes", [])
    all_text = " ".join([s["text"] for s in shapes])

    # 3. Instrument Presence (15 pts)
    required_instruments = ["drum", "bass", "guitar", "key"]
    found_instruments = [inst for inst in required_instruments if inst in all_text]
    
    if len(found_instruments) == 4:
        score += 15
        feedback.append("All instruments found.")
    elif len(found_instruments) >= 2:
        score += 8
        feedback.append(f"Some instruments found: {found_instruments}")
    else:
        feedback.append("Missing instruments.")

    # 4. Spatial Logic (30 pts)
    # Identify shapes by keywords to compare coords
    # Note: In screen coords, (0,0) is Top-Left. 
    # Rear/Upstage = Top = Smaller Y. Front/Downstage = Bottom = Larger Y.
    # Stage Right (House Left) = Left = Smaller X. Stage Left (House Right) = Right = Larger X.
    
    drum_shape = next((s for s in shapes if "drum" in s["text"]), None)
    vocal_shape = next((s for s in shapes if "vocal" in s["text"] and "lead" in s["text"]), None)
    bass_shape = next((s for s in shapes if "bass" in s["text"]), None)
    guitar_shape = next((s for s in shapes if "guitar" in s["text"]), None)

    # Check Depth (Drums behind Vocals)
    if drum_shape and vocal_shape:
        if drum_shape["y"] < vocal_shape["y"]:
            score += 15
            feedback.append("Spatial: Drums correctly placed behind Lead Vocals.")
        else:
            feedback.append("Spatial: Drums appear to be in front of Lead Vocals.")
    else:
        feedback.append("Spatial: Could not find Drums or Lead Vocals to compare depth.")

    # Check Width (Bass Left of Guitar)
    if bass_shape and guitar_shape:
        if bass_shape["x"] < guitar_shape["x"]:
            score += 15
            feedback.append("Spatial: Bass correctly placed Stage Right (House Left).")
        else:
            feedback.append("Spatial: Bass appears to be Stage Left (House Right).")
    else:
        feedback.append("Spatial: Could not find Bass or Guitar to compare width.")

    # 5. Input List Content (20 pts)
    # Check for specific mic models mentioned in requirements
    mic_models = ["beta 91", "beta 52", "sm57", "e604", "sm81", "j48", "re20", "e906", "prod2", "beta 58"]
    found_mics = [m for m in mic_models if m in all_text]
    
    if len(found_mics) >= 8:
        score += 20
        feedback.append(f"Input List: detailed mic models found ({len(found_mics)}).")
    elif len(found_mics) >= 4:
        score += 10
        feedback.append(f"Input List: some mic models found ({len(found_mics)}).")
    else:
        feedback.append("Input List: specific microphone models missing.")

    # 6. Channel Numbers (15 pts)
    # Check if numbers 1-10 appear in text
    # We look for "1", "2", etc as distinct words or starts of lines
    channels_found = 0
    for i in range(1, 11):
        if str(i) in all_text: # Simple check, might be noisy but okay for this context
            channels_found += 1
            
    if channels_found >= 8:
        score += 15
        feedback.append("Input List: Channel numbers 1-10 present.")
    elif channels_found >= 4:
        score += 7
        feedback.append("Input List: Partial channel numbering.")
    else:
        feedback.append("Input List: Channel numbers missing.")

    # 7. Accessories (10 pts)
    accessories = ["power", "110v", "wedge", "monitor"]
    found_acc = [a for a in accessories if a in all_text]
    if len(found_acc) >= 1:
        score += 10
        feedback.append("Accessories (Power/Monitors) noted.")
    else:
        feedback.append("Accessories missing.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }