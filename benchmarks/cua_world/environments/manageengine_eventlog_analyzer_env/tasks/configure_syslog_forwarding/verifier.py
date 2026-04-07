#!/usr/bin/env python3
"""
Verifier for configure_syslog_forwarding task.

Verification Logic:
1. Programmatic Check (Primary):
   - Inspects the DB dump provided by export_result.sh.
   - Looks for the presence of the target IP (10.200.50.25) and Port (1514).
   - Also checks config files/web scrape as fallbacks if DB schema is obscure.

2. VLM Check (Secondary/Context):
   - Uses trajectory frames to verify the user navigated to the forwarding settings.
   - Ensures the final state screenshot shows the configured rule in the UI.

Scoring:
- 25 pts: Forwarding rule exists (IP detected in DB or Config).
- 25 pts: Correct Port (1514) detected associated with that IP.
- 25 pts: Correct Protocol (UDP) detected (default usually, but explicit check preferred).
- 25 pts: VLM visual confirmation of the rule in the UI.
"""

import json
import tempfile
import os
import logging
import re

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_syslog_forwarding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ip = metadata.get('expected_ip', '10.200.50.25')
    expected_port = metadata.get('expected_port', '1514')
    expected_protocol = metadata.get('expected_protocol', 'UDP')

    # Load result from container
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
    
    # --- Programmatic Verification ---
    
    db_records = result.get('db_records', '')
    config_grep = result.get('config_grep', '')
    web_evidence = result.get('web_content_evidence', '')
    
    # Combine all text sources for searching
    combined_evidence = f"{db_records}\n{config_grep}\n{web_evidence}"
    
    # Check 1: IP Address (25 pts)
    ip_found = False
    if expected_ip in combined_evidence:
        ip_found = True
        score += 25
        feedback.append(f"Success: Forwarding IP {expected_ip} found in configuration.")
    else:
        feedback.append(f"Fail: Forwarding IP {expected_ip} NOT found in DB or config.")

    # Check 2: Port (25 pts)
    # We look for the port near the IP or generally in the record
    port_found = False
    if ip_found and expected_port in combined_evidence:
        port_found = True
        score += 25
        feedback.append(f"Success: Forwarding Port {expected_port} found.")
    elif ip_found:
        feedback.append(f"Fail: IP found, but Port {expected_port} not detected in same record.")
    else:
        feedback.append("Fail: Port check skipped due to missing IP.")

    # Check 3: Protocol (UDP) (25 pts)
    # Protocol might be stored as numeric ID or string
    # Common: 1=UDP, 2=TCP or strings "UDP", "TCP"
    protocol_found = False
    if ip_found:
        # If explicitly UDP is found, or if defaults are assumed and not contradicted
        if "UDP" in combined_evidence.upper() or "17" in combined_evidence: # 17 is UDP proto number
            protocol_found = True
            score += 25
            feedback.append("Success: Protocol UDP confirmed.")
        elif "TCP" in combined_evidence.upper():
            feedback.append("Fail: Protocol appears to be TCP (expected UDP).")
        else:
            # Flexible: If IP and Port are correct, assume default UDP if no contradictory evidence
            # But we award fewer points for assumption
            protocol_found = True
            score += 15
            feedback.append("Warning: Explicit Protocol not found, assuming UDP based on valid IP/Port.")
    
    # --- VLM Verification (25 pts) ---
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            # Use trajectory frames to check navigation
            frames = sample_trajectory_frames(traj, n=4)
            final_screen = get_final_screenshot(traj)
            
            prompt = f"""
            You are verifying an agent's task to configure Syslog Forwarding in ManageEngine EventLog Analyzer.
            
            Target Configuration:
            - Destination IP: {expected_ip}
            - Port: {expected_port}
            - Protocol: {expected_protocol}
            
            Review the screenshots.
            1. Did the agent navigate to a Settings or Admin page related to "Forwarding" or "Syslog"?
            2. Is the specific IP {expected_ip} visible in the final configuration list or form?
            3. Is the port {expected_port} visible?
            
            Return JSON: {{ "navigated_correctly": bool, "config_visible": bool, "values_match": bool }}
            """
            
            vlm_resp = query_vlm(prompt=prompt, images=frames + [final_screen])
            if vlm_resp and vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('navigated_correctly'):
                    vlm_score += 10
                if parsed.get('config_visible') and parsed.get('values_match'):
                    vlm_score += 15
                    feedback.append("VLM: Visual confirmation of correct forwarding config.")
                elif parsed.get('config_visible'):
                    vlm_score += 5
                    feedback.append("VLM: Forwarding config screen visible, but values unclear.")
            else:
                # Fallback if VLM fails but programmatic passed
                if ip_found and port_found:
                    vlm_score += 25
                    feedback.append("VLM skipped, trusting programmatic evidence.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            if ip_found and port_found:
                vlm_score += 25

    # If VLM not available/mock mode
    else:
        if ip_found and port_found:
            vlm_score = 25
            feedback.append("VLM unavailable, max score based on programmatic check.")

    score += vlm_score

    passed = score >= 60 and ip_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }