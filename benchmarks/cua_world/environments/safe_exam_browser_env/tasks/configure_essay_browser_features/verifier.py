#!/usr/bin/env python3
import json
import os
import tempfile
import logging

# Standard framework VLM imports
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    logging.warning("gym_anything.vlm not available. Using fallback stubs.")
    def query_vlm(*args, **kwargs): return {"success": True, "parsed": {}}
    def sample_trajectory_frames(*args, **kwargs): return []
    def get_final_screenshot(*args, **kwargs): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's trajectory to see if it correctly configured a Safe Exam Browser profile in the web UI.

Task requirements:
1. Create config named 'ENGL101_Creative_Writing_2026'
2. Enable Spell Check
3. Enable Text Zoom
4. Disable Printing

Look at these screenshots from the agent's session. Did the agent successfully find and modify the settings for Spell Check, Text Zoom, and Printing according to the instructions?

Respond in JSON format with these boolean fields:
{
    "created_config_correct_name": true/false,
    "enabled_spell_check": true/false,
    "enabled_text_zoom": true/false,
    "disabled_printing": true/false,
    "saved_changes": true/false,
    "reasoning": "brief explanation of what you see"
}
"""

def verify_configure_essay_browser_features(traj, env_info, task_info):
    """
    Verifies that the agent created the configuration and set the correct parameters.
    Uses Database checks for primary existence, and VLM Trajectory checks for granular settings 
    (as nested database properties can be schema-volatile).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result exported from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read DB results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------
    # CRITERION 1: Database Baseline Checks (Anti-Gaming)
    # ----------------------------------------------------
    config_exists = result.get('config_exists', False)
    new_configs = result.get('new_configs_created', 0)
    
    if config_exists:
        score += 20
        feedback_parts.append("Config 'ENGL101_Creative_Writing_2026' found in DB")
    else:
        feedback_parts.append("Config NOT found in DB")
        
    if new_configs > 0:
        score += 10
        feedback_parts.append(f"Newly created configs confirmed (+{new_configs})")
    elif config_exists:
        # Pre-existing config gaming check
        feedback_parts.append("Config existed but no NEW config was created")
        
    # ----------------------------------------------------
    # CRITERION 2: VLM Trajectory Verification
    # ----------------------------------------------------
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    
    all_frames = frames
    if final_frame:
        all_frames.append(final_frame)
        
    if not all_frames:
        feedback_parts.append("No frames available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    vlm_result = query_vlm(images=all_frames, prompt=VLM_PROMPT)
    
    if vlm_result.get("success") and "parsed" in vlm_result:
        parsed = vlm_result["parsed"]
        
        if parsed.get("created_config_correct_name"):
            score += 10
            feedback_parts.append("VLM confirms correct config UI")
            
        if parsed.get("enabled_spell_check"):
            score += 20
            feedback_parts.append("VLM: Spell Check verified")
            
        if parsed.get("enabled_text_zoom"):
            score += 20
            feedback_parts.append("VLM: Text Zoom verified")
            
        if parsed.get("disabled_printing"):
            score += 20
            feedback_parts.append("VLM: Printing disable verified")
    else:
        feedback_parts.append("VLM query failed or returned invalid format")

    # Agent must actually create the config in DB AND score well visually to pass
    key_criteria_met = config_exists and new_configs > 0 and score >= 70
    passed = key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }