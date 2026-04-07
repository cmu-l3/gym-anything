#!/usr/bin/env python3
"""
Verifier for packaging_packml_states task.

A Controls Engineer configures 3 PackML state-tracking tags using Crimson 3.0 Multi-State Formatting.
The Palletizer_Mode tag must be EXCLUDED based on judgment.

Scoring (100 points total):
  Subtask 1 — Tag Presence & Integer Type (10 pts): Main_State, Control_Mode, Fault_Type
  Subtask 2 — Format Selection (10 pts): FormatType == Multi-State
  Subtask 3 — Main_State Mapping (25 pts): 7 exact string states mapping 0-6.
  Subtask 4 — Control_Mode Mapping (20 pts): 4 exact string states mapping 0-3.
  Subtask 5 — Fault_Type Mapping (20 pts): 5 exact string states mapping 0-4.
  Subtask 6 — VLM Trajectory (15 pts): Verifies agent actively used the HMI software (anti-gaming).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/packaging_packml_result.json"

def build_vlm_prompt():
    return """Examine these screenshots from a remote desktop session.
The user was asked to configure "Data Tags" in an industrial HMI software called "Crimson 3.0".

Did the user actively navigate the software and edit Data Tags?
Look for:
1. The Crimson 3.0 application open.
2. The "Data Tags" section selected on the left navigation pane.
3. Forms/fields being edited in the middle/right pane (e.g., changing Data Type to 'Integer', Format Type to 'Multi-State', or typing state names like 'IDLE', 'EXECUTE').

Reply with JSON:
{
    "interacted_with_tags": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def get_tag(tags, tag_name):
    for t in tags:
        if str(t.get("Name", "")).strip().lower() == tag_name.lower():
            return t
    return None

def verify_packaging_packml_states(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_states = metadata.get("states", {})

    # Copy result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read exported result: {e}"}

    # GATE 1: Did they save a project?
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project not found. Ensure it was saved to the exact requested path."}
    
    # Anti-gaming: Ensure it was created DURING the session
    if not result.get("created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Project file exists but its timestamp indicates it wasn't modified during the task session."}

    if not result.get("export_success"):
        return {"passed": False, "score": 0, "feedback": "Project exists, but CSV export failed (project might be empty or UI automation failed)."}

    exported_tags = result.get("tags", [])
    if not exported_tags:
        return {"passed": False, "score": 0, "feedback": "No tags found in the project export."}

    # GATE 2: Wrong Scope (Palletizer excluded)
    if get_tag(exported_tags, "Palletizer_Mode"):
        return {"passed": False, "score": 0, "feedback": "FAIL: Configured 'Palletizer_Mode'. You were explicitly instructed to ONLY configure active Packer tags."}

    score = 0
    feedback_parts = []

    # Check Required Tags
    required_tags = ["Main_State", "Control_Mode", "Fault_Type"]
    
    # S1 & S2: Presence, Data Type, and Format Type
    s1_score = 0
    s2_score = 0
    for t_name in required_tags:
        tag = get_tag(exported_tags, t_name)
        if tag:
            # Check Data Type (TreatAs)
            treat_as = tag.get("TreatAs", "").strip().lower()
            if "integer" in treat_as or "uint" in treat_as or "sint" in treat_as:
                s1_score += (10 / len(required_tags))
            
            # Check Format Type
            fmt_type = tag.get("FormatType", "").strip().lower()
            if "multi-state" in fmt_type or "multistate" in fmt_type:
                s2_score += (10 / len(required_tags))

    score += s1_score
    score += s2_score
    feedback_parts.append(f"Presence&Type: {s1_score:.1f}/10")
    feedback_parts.append(f"Format: {s2_score:.1f}/10")

    # S3, S4, S5: State String Mapping checks
    mapping_scores = {
        "Main_State": {"max": 25, "earned": 0},
        "Control_Mode": {"max": 20, "earned": 0},
        "Fault_Type": {"max": 20, "earned": 0}
    }

    for t_name, state_dict in expected_states.items():
        tag = get_tag(exported_tags, t_name)
        if not tag:
            continue
        
        num_states = len(state_dict)
        pts_per_state = mapping_scores[t_name]["max"] / num_states
        
        for state_num, expected_str in state_dict.items():
            # Crimson CSV usually exports these as State0Name, State1Name, etc.
            key = f"State{state_num}Name"
            actual_str = tag.get(key, "").strip()
            
            if actual_str == expected_str: # Exact case match as required
                mapping_scores[t_name]["earned"] += pts_per_state

    for t_name, sc in mapping_scores.items():
        score += sc["earned"]
        feedback_parts.append(f"{t_name} Mapping: {sc['earned']:.1f}/{sc['max']}")

    # S6: VLM Trajectory Verification
    vlm_score = 0
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_response = query_vlm(images=frames, prompt=build_vlm_prompt())
            parsed = vlm_response.get("parsed", {})
            if parsed.get("interacted_with_tags"):
                vlm_score = 15
                feedback_parts.append("VLM: Crimson UI usage confirmed (15/15)")
            else:
                feedback_parts.append("VLM: Could not confirm Crimson UI interaction (0/15)")
        else:
            feedback_parts.append("VLM: No frames available (0/15)")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM: Skipped/Error")
        # Give benefit of the doubt if programmatic is perfect but VLM errors
        if score >= 85: 
            vlm_score = 15
            
    score += vlm_score

    # Determine success
    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback_parts)
    }