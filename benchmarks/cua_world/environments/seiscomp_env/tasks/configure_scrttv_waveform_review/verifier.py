#!/usr/bin/env python3
"""
Verifier for configure_scrttv_waveform_review task.
"""

import os
import json
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for verifying the progression and correct tool usage
VLM_PROMPT = """You are evaluating an AI agent's performance on a SeisComP task.
The agent was asked to configure and launch 'scrttv' (Real-Time Trace View) to display seismic waveforms.

Review the sequence of trajectory screenshots from the agent's session and evaluate:
1. WORKFLOW_PROGRESSION: Does the agent show progression from the desktop, to configuring files (terminal or scconfig UI), and finally launching a graphical trace viewing application?
2. TRACE_VIEW_VISIBLE: In the final frames, is a SeisComP application window (scrttv) clearly visible showing multiple horizontal trace tracks/channels?
3. NO_CRASHES: Did the application launch successfully without blocking error/crash popups?

Return your assessment in the following JSON format ONLY:
{
    "workflow_progression": true/false,
    "trace_view_visible": true/false,
    "no_crashes": true/false,
    "observations": "brief explanation of what you see"
}
"""

def verify_configure_scrttv(traj, env_info, task_info):
    """
    Verify the scrttv configuration and launch.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy and load the exported result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    scrttv_cfg = result.get('scrttv_cfg', '')
    global_cfg = result.get('global_cfg', '')
    combined_cfg = scrttv_cfg + "\n" + global_cfg

    # 1. Check SDS Recordstream (15 pts)
    # Can be defined in either global or scrttv configuration
    sds_service_match = re.search(r'recordstream\.service\s*=\s*[\"\']?sdsarchive[\"\']?', combined_cfg)
    sds_source_match = re.search(r'recordstream\.source\s*=\s*[\"\']?/home/ga/seiscomp/var/lib/archive/?[\"\']?', combined_cfg)
    
    if sds_service_match and sds_source_match:
        score += 15
        feedback_parts.append("SDS Recordstream configured")
    else:
        feedback_parts.append("SDS Recordstream NOT fully configured")

    # 2. Check Bandpass Filter (20 pts)
    # Must be in scrttv.cfg
    filter_match = re.search(r'BW\(\s*2\s*,\s*0\.5\s*,\s*8\.0\s*\)', scrttv_cfg)
    if filter_match:
        score += 20
        feedback_parts.append("Bandpass filter correctly configured")
    else:
        feedback_parts.append("Bandpass filter NOT configured correctly")

    # 3. Check Buffer Size (10 pts)
    # Must be in scrttv.cfg and >= 1800
    buffer_match = re.search(r'bufferSize\s*=\s*(\d+)', scrttv_cfg)
    buffer_configured = False
    if buffer_match:
        try:
            buffer_val = int(buffer_match.group(1))
            if buffer_val >= 1800:
                score += 10
                buffer_configured = True
                feedback_parts.append(f"Buffer size configured ({buffer_val}s)")
        except ValueError:
            pass
    if not buffer_configured:
        feedback_parts.append("Buffer size NOT configured or < 1800s")

    # 4. Check Stream Configuration (10 pts)
    # Looking for GE and BHZ in streams config
    stream_match = re.search(r'GE', scrttv_cfg) and re.search(r'BHZ', scrttv_cfg)
    if stream_match:
        score += 10
        feedback_parts.append("Streams configured for GE/BHZ")
    else:
        feedback_parts.append("Streams configuration missing GE/BHZ")

    # 5. Check scrttv Process Running (15 pts)
    scrttv_running = result.get('scrttv_running', False)
    if scrttv_running:
        score += 15
        feedback_parts.append("scrttv process is running")
    else:
        feedback_parts.append("scrttv process is NOT running")

    # 6. Check Screenshot Saved (10 pts)
    screenshot_valid = result.get('screenshot_valid', False)
    if screenshot_valid:
        score += 10
        feedback_parts.append("Manual screenshot captured and valid")
    else:
        feedback_parts.append("Manual screenshot missing or invalid")

    # 7. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("workflow_progression"):
                    vlm_score += 10
                if parsed.get("trace_view_visible") and parsed.get("no_crashes"):
                    vlm_score += 10
                    
                score += vlm_score
                feedback_parts.append(f"VLM verification scored {vlm_score}/20")
            else:
                feedback_parts.append("VLM query failed or format error")
        else:
            feedback_parts.append("No trajectory frames for VLM")
    except Exception as e:
        logger.warning(f"VLM evaluation failed: {e}")
        feedback_parts.append("VLM evaluation error")

    # Final Evaluation
    # Mandatory criteria: filter must be configured AND scrttv must be running
    key_criteria_met = bool(filter_match) and scrttv_running
    passed = score >= 60 and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS")
    else:
        if not key_criteria_met:
            feedback_parts.insert(0, "FAILED (Mandatory criteria not met: requires filter configured AND scrttv running)")
        else:
            feedback_parts.insert(0, f"FAILED (Score {score}/100 below 60 threshold)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }