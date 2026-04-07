#!/usr/bin/env python3
"""
Verifier for import_audio_column task.

Checks if an OpenToonz scene was saved containing a reference to the audio file,
validating that the user successfully imported audio into the Xsheet.
"""

import json
import os
import tempfile
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_audio_column(traj, env_info, task_info):
    """
    Verifies that the audio import task was completed successfully.
    
    Scoring Criteria:
    1. Scene file exists (15 pts)
    2. Scene file created during task (anti-gaming) (15 pts)
    3. Scene file is not empty (10 pts)
    4. Audio file is referenced inside the scene file (Evidence of import) (20 pts)
    5. Sound column tags present in scene file (Evidence of correct column type) (15 pts)
    6. VLM Visual Verification (Waveform visible) (15 pts)
    7. Application clean state/running (10 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback = []

    # Criterion 1: Scene Exists (15 pts)
    if result.get('scene_exists', False):
        score += 15
        feedback.append("Scene file created successfully.")
    else:
        feedback.append("Scene file not found.")

    # Criterion 2: Timestamp Check (15 pts)
    if result.get('scene_newer_than_start', False):
        score += 15
    elif result.get('scene_exists', False):
        feedback.append("Scene file is old (pre-existing?).")

    # Criterion 3: File Size (10 pts)
    if result.get('scene_size_bytes', 0) > 100: # minimal valid XML size
        score += 10
    else:
        feedback.append("Scene file is empty or too small.")

    # Criterion 4: Audio Reference in Scene (20 pts)
    # This is critical - proves the specific file was imported
    if result.get('has_audio_reference', False):
        score += 20
        feedback.append("Audio file correctly referenced in scene.")
    else:
        feedback.append("Scene does not contain reference to 'reference_dialogue.wav'.")

    # Criterion 5: Sound Column Structure (15 pts)
    # Proves it was imported as a sound column, not just a generic level
    if result.get('has_sound_column_tag', False):
        score += 15
        feedback.append("Sound column structure detected in scene.")
    else:
        feedback.append("No sound column tags found in scene XML.")

    # Criterion 6: VLM/Visual Verification (15 pts)
    # We check if the VLM can see the waveform (Green waveform usually in OpenToonz Xsheet)
    # Since we don't have a live VLM in this verifier stub, we simulate based on strong file evidence
    # or use a placeholder if the framework supports it.
    # Logic: If file evidence is strong (Criteria 4 & 5 met), we infer visual success for this programmatic verifier.
    # In a real VLM integration, we would call query_vlm here.
    if result.get('has_audio_reference', False) and result.get('has_sound_column_tag', False):
        score += 15
        feedback.append("Visual verification inferred from valid scene structure.")
    elif result.get('scene_exists', False):
        feedback.append("Visual verification failed: Scene structure incomplete.")

    # Criterion 7: App State (10 pts)
    if result.get('app_running', False):
        score += 10
    
    # 3. Final Scoring
    # Pass threshold: 60
    # Must have created scene and referenced audio
    critical_success = result.get('scene_exists', False) and result.get('has_audio_reference', False)
    
    passed = (score >= 60) and critical_success

    if not critical_success:
        feedback.insert(0, "FAILED: Critical criteria missing (Scene file with audio reference).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }