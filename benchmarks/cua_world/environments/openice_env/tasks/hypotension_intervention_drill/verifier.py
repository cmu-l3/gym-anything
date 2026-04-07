#!/usr/bin/env python3
"""
Verifier for hypotension_intervention_drill task.

Scoring Criteria (100 points total):
1. Environment Health (10 pts): OpenICE is running.
2. Device Setup (30 pts): 
   - Multiparameter Monitor created (15 pts)
   - Infusion Pump created (15 pts)
3. Action Verification via Report (40 pts):
   - Report file exists & written during task (10 pts)
   - Report mentions BP context (10 pts)
   - Report mentions Pump/Rate context (10 pts)
   - Report contains target numeric values (BP < 90, Rate > 500) (10 pts)
4. Evidence (20 pts):
   - Agent created a screenshot as requested (10 pts)
   - VLM verification of final state (10 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for verifying the final screenshot
VLM_PROMPT = """You are verifying a clinical simulation task in OpenICE.
The user was asked to:
1. Create a Multiparameter Monitor and an Infusion Pump.
2. Set the Monitor's Blood Pressure LOW (< 90).
3. Set the Pump's Flow Rate HIGH (> 500).

Look at the screenshot and determine:
- Are there two distinct device windows or panels visible? (Monitor usually shows waveforms, Pump usually shows numbers/rates).
- Can you see any numeric values indicating hypotension (BP < 90, e.g., 80/50)?
- Can you see any numeric values indicating a high infusion rate (> 500)?

Respond in JSON:
{
  "devices_visible": true/false,
  "low_bp_visible": true/false,
  "high_rate_visible": true/false,
  "confidence": "low/medium/high"
}
"""

def verify_hypotension_intervention_drill(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: OpenICE Running (10 pts) ---
    if result.get('openice_running', False):
        score += 10
        feedback_parts.append("OpenICE running")
    else:
        feedback_parts.append("OpenICE NOT running")

    # --- Criterion 2: Device Setup (30 pts) ---
    monitor = result.get('monitor_detected', False)
    pump = result.get('pump_detected', False)
    
    if monitor:
        score += 15
        feedback_parts.append("Monitor created")
    else:
        feedback_parts.append("Monitor MISSING")
        
    if pump:
        score += 15
        feedback_parts.append("Pump created")
    else:
        feedback_parts.append("Pump MISSING")

    # Fallback: if specific detection failed but windows increased by >= 2
    if not (monitor and pump) and result.get('window_increase', 0) >= 2:
        score += 10
        feedback_parts.append("(Partial credit: Window count increased by >= 2)")

    # --- Criterion 3: Report Verification (40 pts) ---
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    task_start = result.get('task_start', 0)
    
    # Check timestamp integrity
    report_fresh = report_exists and (report_mtime > task_start)
    
    if report_fresh:
        score += 10
        feedback_parts.append("Log file created")
        
        if result.get('report_content_bp', False):
            score += 10
            feedback_parts.append("Log mentions BP")
        
        if result.get('report_content_rate', False):
            score += 10
            feedback_parts.append("Log mentions Rate")
            
        if result.get('report_values_valid', False):
            score += 10
            feedback_parts.append("Log contains valid target values")
    else:
        feedback_parts.append("Log file missing or stale")

    # --- Criterion 4: Evidence & VLM (20 pts) ---
    # A. Agent Screenshot (10 pts)
    if result.get('agent_screenshot_exists', False):
        score += 10
        feedback_parts.append("Agent screenshot found")
    else:
        feedback_parts.append("No agent screenshot")

    # B. VLM Check of System State (10 pts)
    # We use the framework's VLM utility on the final screenshot taken by export_result.sh
    # If not available, we give points if devices were detected via logs (benefit of doubt)
    vlm_score = 0
    try:
        from vlm_utils import query_vlm, get_final_screenshot
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_res = query_vlm(prompt=VLM_PROMPT, image=final_img)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('devices_visible'):
                    vlm_score += 5
                if parsed.get('low_bp_visible') or parsed.get('high_rate_visible'):
                    vlm_score += 5
                feedback_parts.append(f"VLM: Devices={parsed.get('devices_visible')}, Vals={parsed.get('low_bp_visible') or parsed.get('high_rate_visible')}")
            else:
                # VLM failed, fallback to log detection
                if monitor and pump: vlm_score += 10
        else:
            if monitor and pump: vlm_score += 10
    except ImportError:
        # If VLM utils not available in environment
        if monitor and pump: vlm_score += 10

    score += vlm_score

    # Final Pass Check
    # Must have created devices and produced the report
    passed = (score >= 60) and monitor and pump and report_fresh

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }