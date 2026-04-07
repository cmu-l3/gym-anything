#!/usr/bin/env python3
"""Verifier for configure_regex_filter task."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring bcWebCam.

The goal was to enable the regex filter and set it to: ^\d{13}$

Check the frames to determine:
1. Did the agent open the settings/options dialog?
2. Did the agent locate the regex filter setting?
3. Did the agent type the correct pattern: ^\d{13}$  (or ^[0-9]{13}$)
4. Was the feature enabled (checkbox ticked)?
5. Were the settings applied (clicking OK/Save)?

Respond in JSON format:
{
    "settings_opened": true/false,
    "regex_field_visible": true/false,
    "pattern_typed_correctly": true/false,
    "filter_enabled": true/false,
    "settings_applied": true/false,
    "confidence": "low" | "medium" | "high",
    "reasoning": "Brief explanation"
}
"""

def verify_configure_regex_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract metadata expectations
    metadata = task_info.get('metadata', {})
    expected_pattern = metadata.get('expected_pattern', r'^\d{13}$')
    
    # 1. Programmatic Checking (Config state inside container)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        # Note: Docker API generally prefers forward slashes for cross-platform robustness
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load programmatic result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    config_found = result.get('config_found', False)
    regex_filter = result.get('regex_filter', '')
    regex_enabled = result.get('regex_enabled', False)
    
    programmatic_success = False
    
    if config_found:
        if regex_enabled:
            score += 20
            feedback_parts.append("Config shows filter enabled")
        
        # Check pattern exactly
        pattern_matches = False
        if regex_filter == r'^\d{13}$' or regex_filter == r'^[0-9]{13}$':
            pattern_matches = True
            
        if pattern_matches:
            score += 30
            feedback_parts.append("Config shows correct pattern string")
            
        if regex_enabled and pattern_matches:
            programmatic_success = True
            
    # Functional test against realistic EAN-13 barcodes
    if regex_filter:
        try:
            compiled = re.compile(regex_filter)
            if compiled.match("4006381333931") and not compiled.match("SHIP-2024-0891") and not compiled.match("12345"):
                score += 15
                feedback_parts.append("Pattern functionally valid")
        except:
            pass
            
    # 2. VLM Trajectory Verification
    # (Crucial fallback if bcWebCam requires application restart to flush config to disk)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    get_trajectory_frames = env_info.get('get_trajectory_frames')
    
    if query_vlm and get_trajectory_frames:
        try:
            frames = get_trajectory_frames(traj, n=8)
            if frames:
                vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_response and vlm_response.get("success"):
                    parsed = vlm_response.get("parsed", {})
                    
                    if parsed.get("settings_opened"): vlm_score += 5
                    if parsed.get("regex_field_visible"): vlm_score += 5
                    if parsed.get("pattern_typed_correctly"): vlm_score += 10
                    if parsed.get("filter_enabled"): vlm_score += 10
                    if parsed.get("settings_applied"): vlm_score += 5
                    
                    feedback_parts.append(f"VLM Score: {vlm_score}/35")
                else:
                    feedback_parts.append("VLM query failed")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification error")
            
    score += vlm_score
    
    # Cap maximum score at 100
    score = min(100, score)
    
    # Pass threshold demands either solid config proof or strong visual evidence of completion
    passed = score >= 60 and (programmatic_success or vlm_score >= 25)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No configuration or trajectory evidence found"
    }