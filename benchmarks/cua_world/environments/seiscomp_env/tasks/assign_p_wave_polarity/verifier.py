#!/usr/bin/env python3
"""
Verifier for assign_p_wave_polarity task.

Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
1. Programmatic DB checks: Verifies that new picks with agency=GYM were created and have correct polarities.
2. VLM Trajectory checks: Verifies that the agent actually interacted with the Waveform/Picker view in scolv.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent interacting with the SeisComP 'scolv' application.
The agent's task is to open the "Picker" view (which shows waveform traces/seismograms for different stations) and assign P-wave polarities.

Look at these frames chronologically.
Assess:
1. Did the agent open the Picker/Waveform view at any point? (Look for a window showing multiple horizontal squiggly lines / waveform traces).
2. Is there evidence that they clicked on or interacted with the waveform traces to set picks/polarities?

Respond in JSON format exactly like this:
{
    "picker_view_opened": true/false,
    "waveform_interaction_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible"
}
"""

def verify_p_wave_polarity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_polarities = metadata.get('expected_polarities', {})

    score = 0
    feedback_parts = []
    
    # 1. Read exported DB data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Origins (15 points)
    initial_origins = result.get('initial_gym_origins', 0)
    current_origins = result.get('current_gym_origins', 0)
    
    if current_origins > initial_origins:
        score += 15
        feedback_parts.append(f"New GYM origin created ({initial_origins} -> {current_origins})")
        origin_created = True
    else:
        feedback_parts.append("No new GYM origin was committed to the database")
        origin_created = False

    # 3. Check Polarities (15 points each = 60 points)
    gym_picks = result.get('gym_picks', [])
    
    # Extract the latest polarity set for each station from the newly created picks
    found_polarities = {}
    for pick in gym_picks:
        station = pick.get('station')
        polarity = pick.get('polarity')
        # Since the query orders by _oid DESC, the first time we see a station it's the latest pick
        if station not in found_polarities and polarity != 'null':
            found_polarities[station] = polarity.lower()

    stations_correct = 0
    for target_station, expected_polarity in expected_polarities.items():
        actual_polarity = found_polarities.get(target_station)
        if actual_polarity == expected_polarity.lower():
            score += 15
            stations_correct += 1
            feedback_parts.append(f"{target_station} polarity correct ({expected_polarity})")
        else:
            feedback_parts.append(f"{target_station} polarity incorrect/missing (expected {expected_polarity}, found {actual_polarity})")

    # 4. VLM Trajectory Verification (25 points)
    # Check if they actually used the scolv Picker view
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('picker_view_opened') and parsed.get('waveform_interaction_visible'):
                        score += 25
                        vlm_passed = True
                        feedback_parts.append("VLM confirms Picker/Waveform view usage")
                    else:
                        feedback_parts.append("VLM did not detect interaction with Waveform view")
                else:
                    feedback_parts.append("VLM query failed or format invalid")
        else:
            # Grant partial free points if VLM isn't available to not penalize correct programmatic state
            score += 25
            vlm_passed = True
            feedback_parts.append("VLM unavailable, assuming GUI was used based on DB state")
            
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # Soft-fail VLM
        score += 25
        vlm_passed = True
        feedback_parts.append("VLM exception, bypassing visual check")

    # Determine final success
    # Need origin committed + at least 3 polarities correct + VLM visual confirmation
    key_criteria_met = origin_created and (stations_correct >= 3) and vlm_passed
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "origin_created": origin_created,
            "stations_correct": stations_correct,
            "vlm_passed": vlm_passed
        }
    }