#!/usr/bin/env python3
"""
Verifier for add_progress_note task.

Uses `copy_from_env` to extract database states, checks for timestamps and patient
associations to prevent gaming, and uses trajectory frames for VLM verification.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_progress_note(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error"}

    metadata = task_info.get('metadata', {})
    subj_keywords = metadata.get('subjective_keywords', ["dizziness", "dizzy", "compliant", "lisinopril", "morning"])
    obj_keywords = metadata.get('objective_keywords', ["138", "88", "72", "165", "regular", "clear"])
    assess_keywords = metadata.get('assessment_keywords', ["hypertension", "improving", "goal", "orthostatic", "adequate"])
    plan_keywords = metadata.get('plan_keywords', ["continue", "follow up", "follow-up", "sodium", "increase", "20mg", "monitoring"])

    # 1. Fetch JSON result from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read database export."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Database Validations (Anti-gaming & Association)
    new_notes_count = result_data.get('new_notes_count', 0)
    notes_for_maria = result_data.get('notes_for_maria', 0)
    combined_text = result_data.get('combined_note_text', "").lower()
    
    if new_notes_count > 0:
        score += 15
        feedback_parts.append(f"New note record created (+15)")
    else:
        feedback_parts.append("No new notes were created in the database")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    if notes_for_maria > 0:
        score += 15
        feedback_parts.append(f"Note successfully linked to Maria Santos (+15)")
    else:
        feedback_parts.append("WARNING: New note exists, but not linked to Maria Santos")

    # 3. Check Clinical Keywords
    def count_hits(keywords, text):
        return sum(1 for kw in keywords if kw.lower() in text)

    s_hits = count_hits(subj_keywords, combined_text)
    o_hits = count_hits(obj_keywords, combined_text)
    a_hits = count_hits(assess_keywords, combined_text)
    p_hits = count_hits(plan_keywords, combined_text)

    # Max 40 points for content
    content_score = 0
    if s_hits >= 2: content_score += 10
    if o_hits >= 2: content_score += 10
    if a_hits >= 2: content_score += 10
    if p_hits >= 2: content_score += 10
    
    score += content_score
    feedback_parts.append(f"Content score: {content_score}/40 (S:{s_hits}, O:{o_hits}, A:{a_hits}, P:{p_hits})")

    # 4. VLM Verification (Trajectory checking)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        if all_frames:
            vlm_prompt = (
                "You are auditing an EMR task. Look at these sequential screenshots from the agent's workflow.\n"
                "1. Did the agent navigate to the patient chart for 'Maria Santos'?\n"
                "2. Did the agent open the 'Progress Notes' or 'Patient Notes' module?\n"
                "3. Did the agent type a SOAP note containing details about hypertension, lisinopril, or blood pressure?\n"
                "Reply exclusively in JSON format:\n"
                "{\"workflow_valid\": true/false, \"reason\": \"brief explanation\"}"
            )
            
            # Use query_vlm from environment if available, or fallback gracefully
            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                vlm_res = query_vlm(images=all_frames, prompt=vlm_prompt)
                
                try:
                    # Clean up json output from markdown backticks
                    text_resp = vlm_res.strip()
                    if text_resp.startswith("