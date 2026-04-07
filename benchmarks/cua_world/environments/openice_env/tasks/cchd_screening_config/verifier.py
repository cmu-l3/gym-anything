#!/usr/bin/env python3
"""
Verifier for CCHD Screening Configuration Task

Logic:
1. Verify OpenICE is running.
2. Verify two "Pulse Oximeter" device simulators are active (via window count/titles).
3. Verify report file exists and maps UDIs to "Pre-ductal"/"Post-ductal" or values 98/90.
4. Verify the report's claims against log data or screen evidence.
   - Since extracting exact UDI-value pairs from unstructured logs is brittle,
     we primarily check:
     a) The report contains two distinct UDI-like strings.
     b) The logs contain evidence of '98' and '90' values being published.
     c) VLM verification of the agent's screenshot to confirm values 98 and 90 are visible
        on the device simulators.

Scoring:
- 20 pts: Setup (OpenICE running, 2+ new windows)
- 20 pts: Configuration (Values 98 and 90 detected in logs)
- 20 pts: Report Existence & Formatting (Two UDIs listed)
- 40 pts: VLM Evidence (Screenshot shows correct setup: 2 devices, values 98 & 90)
"""

import json
import os
import tempfile
import re
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if needed (mocked here if not available)
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from vlm_utils import query_vlm, get_final_screenshot
except ImportError:
    # Fallback if running outside framework
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cchd_screening(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Environment & Window State (20 pts)
    openice_running = result.get("openice_running", False)
    final_windows = result.get("final_window_count", 0)
    initial_windows = result.get("initial_window_count", 0)
    window_increase = final_windows - initial_windows
    window_list = result.get("window_list", "")
    
    # Check for 2+ new windows (likely the two simulators)
    if openice_running and window_increase >= 2:
        score += 20
        feedback.append("OpenICE running with new device windows.")
    elif openice_running:
        score += 10
        feedback.append("OpenICE running but fewer than 2 new windows detected.")
    else:
        feedback.append("OpenICE not running.")

    # 2. Log-based Configuration Check (20 pts)
    # Check if we see 98 and 90 in the logs/hints
    hints = result.get("log_hints", {})
    found_98 = hints.get("found_98", 0) > 0
    found_90 = hints.get("found_90", 0) > 0
    found_pulse = hints.get("found_pulse_ox", 0) > 0
    
    if found_98 and found_90:
        score += 20
        feedback.append("Logs confirm values 98 and 90 were generated.")
    elif found_98 or found_90:
        score += 10
        feedback.append("Logs confirm only one of the target values (98 or 90).")
    else:
        feedback.append("Logs do NOT show evidence of 98 or 90 values.")

    # 3. Report Verification (20 pts)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "")
    
    # Simple regex to find UDI-like strings (uuid or long alnum)
    # OpenICE UDIs often look like UUIDs
    udi_pattern = r'[0-9a-fA-F-]{20,}'
    udis_found = re.findall(udi_pattern, report_content)
    
    if report_exists and len(udis_found) >= 2:
        score += 20
        feedback.append(f"Report exists and lists {len(udis_found)} potential UDIs.")
    elif report_exists:
        score += 10
        feedback.append("Report exists but valid UDIs not clearly detected.")
    else:
        feedback.append("Report file not found.")

    # 4. VLM Verification of Agent's Screenshot (40 pts)
    # The agent was supposed to take a screenshot at /home/ga/Desktop/cchd_screen_evidence.png
    # We should verify THAT screenshot if it exists, otherwise the system final screenshot
    
    # We can't access the specific agent-saved file easily from here without `copy_from_env`ing it,
    # but the framework passes `traj` which has screenshots.
    # However, to be precise, let's use the system final screenshot for VLM as a proxy
    # OR we rely on the framework to allow us to copy the specific evidence image.
    
    # Let's try to copy the evidence image if it exists
    evidence_exists = result.get("evidence_screenshot_exists", False)
    vlm_score = 0
    
    if evidence_exists:
        # Use a temporary path for the evidence image
        evidence_local_path = tempfile.mktemp(suffix='.png')
        try:
            copy_from_env("/home/ga/Desktop/cchd_screen_evidence.png", evidence_local_path)
            
            prompt = """
            Analyze this screenshot of the OpenICE medical simulator.
            I am looking for:
            1. Two distinct 'Pulse Oximeter' or 'Device' windows.
            2. One device showing the value '98' (SpO2).
            3. One device showing the value '90' (SpO2).
            
            Return JSON:
            {
                "two_devices_visible": true/false,
                "value_98_visible": true/false,
                "value_90_visible": true/false
            }
            """
            vlm_res = query_vlm(prompt, image=evidence_local_path)
            
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("two_devices_visible"): vlm_score += 15
                if parsed.get("value_98_visible"): vlm_score += 12
                if parsed.get("value_90_visible"): vlm_score += 13
                feedback.append(f"VLM Analysis: {parsed}")
            else:
                feedback.append("VLM query failed on evidence screenshot.")
                # Fallback points if file exists
                vlm_score += 10 
        except Exception as e:
            feedback.append(f"Could not process evidence screenshot: {e}")
            if evidence_exists: vlm_score += 5
        finally:
            if os.path.exists(evidence_local_path):
                os.unlink(evidence_local_path)
    else:
        feedback.append("Agent evidence screenshot not found.")
    
    score += vlm_score

    # Final tally
    passed = score >= 60 and openice_running
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }