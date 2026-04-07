#!/usr/bin/env python3
"""
Verifier for packaging_hmi_localization task.
Requires the agent to configure tags in Crimson 3.0 for dual-language (English/Spanish).

Checks:
1. Anti-gaming check (file created during task)
2. Distractor trap (no French translations used)
3. Correct tags present
4. Correct translations populated
5. VLM visual verification for display page UI and language toggle
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_tag_by_name(tags, target_name):
    target = target_name.lower()
    for t in tags:
        # Check all values in the dict just in case the export column name varies
        for k, v in t.items():
            if str(v).strip().lower() == target:
                return t
    return None

def verify_packaging_localization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    distractor_words = metadata.get('distractor_words', [
        "arrêté", "panne", "niveau", "remplissage", "vitesse", 
        "convoyeur", "arrêt", "urgence", "nombre", "produits"
    ])

    feedback_parts = []
    score = 0

    # 1. Retrieve Result JSON from Environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\CrimsonTasks\\packaging_hmi_mexico_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    project_found = result.get('project_found', False)
    if not project_found:
        return {"passed": False, "score": 0, "feedback": "Project packaging_hmi_mexico.c3 not found. Did not save."}
    
    score += 10
    feedback_parts.append("Project file found")

    # Anti-gaming: Check if project was saved during task session
    try:
        tmp_start = tempfile.NamedTemporaryFile(delete=False)
        copy_from_env("C:\\Users\\Docker\\Desktop\\CrimsonTasks\\task_start_time.txt", tmp_start.name)
        with open(tmp_start.name, 'r') as f:
            start_time = int(f.read().strip())
        os.unlink(tmp_start.name)
        
        file_mtime = result.get('file_mtime', 0)
        if file_mtime < start_time:
            return {"passed": False, "score": 0, "feedback": "Project file was not created/modified during this session (Anti-gaming filter)."}
    except Exception:
        logger.warning("Could not verify timestamps - proceeding.")

    tags = result.get('tags', [])
    export_success = result.get('export_success', False)
    found_count = 0

    if not export_success or not tags:
        feedback_parts.append("Tags not successfully exported or project empty")
    else:
        # 2. Distractor Trap evaluation
        tags_str = json.dumps(tags).lower()
        trap_triggered = any(dw in tags_str for dw in distractor_words)
        
        if trap_triggered:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "DISTRACTOR TRAP FAILED: French translations found in exported tags. Agent must follow location context (Mexico)."
            }
        
        feedback_parts.append("No French distractors found")
        score += 10

        # 3. Verify Tags and localization strings
        expected_tags = ["MachineState", "FillerLevel", "ConveyorSpeed", "EmergencyStop", "ProductCount"]
        expected_english = ["stopped", "faulted", "filler level", "conveyor speed", "e-stop", "product count"]
        expected_spanish = ["detenido", "falla", "nivel de llenado", "velocidad del transportador", "paro de emergencia", "conteo de producto"]

        english_match = 0
        spanish_match = 0

        for et in expected_tags:
            tag_data = get_tag_by_name(tags, et)
            if tag_data:
                found_count += 1
                tag_row_str = json.dumps(tag_data).lower()
                
                if any(en_str in tag_row_str for en_str in expected_english):
                    english_match += 1
                
                if any(es_str in tag_row_str for es_str in expected_spanish):
                    spanish_match += 1

        # Calculate tag presence score (Max 20)
        score += min(20, found_count * 4)
        feedback_parts.append(f"Found {found_count}/5 required tags")

        # Calculate localization population scores
        en_score = min(15, english_match * 3)
        es_score = min(15, spanish_match * 3)
        score += en_score
        score += es_score

        feedback_parts.append(f"L1 (English) matches: {english_match}")
        feedback_parts.append(f"L2 (Spanish) matches: {spanish_match}")

    # 4. VLM Verification (Trajectory & Final UI)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Examine these trajectory frames and the final screenshot of an HMI software (Red Lion Crimson 3.0).
The user was asked to create a Display Page containing 5 tags (MachineState, FillerLevel, ConveyorSpeed, EmergencyStop, ProductCount) and a language toggle button.

Check for:
1. Are there visual elements on a Display Page corresponding to the 5 tags (e.g., data boxes, text primitives)?
2. Is there a button, flag, or menu element designed to toggle or select the language (e.g., "Language", "English/Español", "Toggle Lang", or a flag icon)?

Respond with JSON:
{
    "tags_on_display": true/false,
    "language_toggle_present": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly explain what you see"
}
"""
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get('parsed'):
                parsed = vlm_response['parsed']
                if parsed.get('tags_on_display'):
                    vlm_score += 15
                    feedback_parts.append("VLM: Tags visible on display")
                if parsed.get('language_toggle_present'):
                    vlm_score += 15
                    feedback_parts.append("VLM: Language toggle visible")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped/failed")
    
    score += vlm_score

    passed = score >= 70 and project_found and (found_count >= 3)
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }