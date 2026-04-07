#!/usr/bin/env python3
import json
import base64
import re
import os
import tempfile

def verify_ecdis_nmea_integration(traj, env_info, task_info):
    """
    Verifies the ECDIS NMEA Integration task.
    
    Scoring Breakdown (100 pts):
    1. Configuration (30 pts): bc5.ini has correct IP (127.0.0.1) and Port (10110).
    2. Data Capture (30 pts): Log file exists, has content, and contains NMEA sentences.
    3. Live Execution (20 pts): Log file was modified during the task window.
    4. Report (20 pts): Report identifies correct Talker IDs.
    """
    
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # Criterion 1: Configuration (30 pts)
    # ------------------------------------------------------------------
    config = result.get('config', {})
    ip = config.get('ip', '')
    port = config.get('port', '')
    
    # Verify IP
    if ip == '127.0.0.1' or ip == 'localhost':
        score += 15
        feedback.append("Config: Correct UDP Address.")
    else:
        feedback.append(f"Config: Incorrect UDP Address. Expected 127.0.0.1, found '{ip}'.")
        
    # Verify Port
    if port == '10110':
        score += 15
        feedback.append("Config: Correct UDP Port.")
    else:
        feedback.append(f"Config: Incorrect UDP Port. Expected 10110, found '{port}'.")

    # ------------------------------------------------------------------
    # Criterion 2: Data Capture Logic (30 pts)
    # ------------------------------------------------------------------
    log_data = result.get('log', {})
    log_exists = log_data.get('exists', False)
    log_sample_b64 = log_data.get('sample_b64', '')
    
    valid_nmea = False
    captured_talkers = set()
    
    if log_exists and log_sample_b64:
        try:
            log_content = base64.b64decode(log_sample_b64).decode('utf-8', errors='ignore')
            
            # Check for generic NMEA structure: $.....*CS
            # Regex for standard sentences like $GPGGA, $GPZDA, $HEHDT
            nmea_matches = re.findall(r'\$([A-Z]{5}),', log_content)
            
            if len(nmea_matches) > 0:
                valid_nmea = True
                score += 30
                feedback.append(f"Data Capture: Valid NMEA sentences found ({len(nmea_matches)} in sample).")
                
                # Extract talkers (first 2 chars) for later verification
                for match in nmea_matches:
                    captured_talkers.add(match[:2]) # e.g., 'GP' from 'GPGGA'
            else:
                feedback.append("Data Capture: Log file exists but contains no valid NMEA sentences.")
        except Exception:
            feedback.append("Data Capture: Failed to decode log file content.")
    else:
        feedback.append("Data Capture: Log file not found or empty.")

    # ------------------------------------------------------------------
    # Criterion 3: Live Execution (20 pts)
    # ------------------------------------------------------------------
    # Anti-gaming: Ensure file was created/modified *during* the task
    created_during_task = log_data.get('created_during_task', False)
    
    if created_during_task and valid_nmea:
        score += 20
        feedback.append("Live Execution: Verified log was generated during task session.")
    elif valid_nmea:
        feedback.append("Live Execution: Fail - Log file timestamp indicates it might be stale or pre-existing.")
    else:
        feedback.append("Live Execution: Skipped (no valid data captured).")

    # ------------------------------------------------------------------
    # Criterion 4: Report Analysis (20 pts)
    # ------------------------------------------------------------------
    report_data = result.get('report', {})
    report_exists = report_data.get('exists', False)
    
    if report_exists:
        try:
            report_content = base64.b64decode(report_data.get('content_b64', '')).decode('utf-8', errors='ignore')
            
            # Verify the agent identified the correct talkers
            # We compare against what we actually found in the log sample
            identified_correctly = False
            
            if captured_talkers:
                # Naive check: does the report contain the talker string?
                # e.g. if log has GP and HE, report should mention GP and HE
                matches = 0
                for talker in captured_talkers:
                    if talker in report_content:
                        matches += 1
                
                if matches >= 1: # Give credit if they identified at least one correctly
                    score += 20
                    feedback.append(f"Report: Successfully identified Talker IDs ({captured_talkers}).")
                else:
                    feedback.append(f"Report: Failed to identify actual Talker IDs {captured_talkers} in text.")
            else:
                # If we couldn't parse the log, we can't verify the report against truth,
                # but we give partial credit if the report looks somewhat valid
                if "GP" in report_content or "HE" in report_content:
                    score += 10
                    feedback.append("Report: Found plausible Talker IDs, but could not cross-reference with log.")
        except Exception:
            feedback.append("Report: Error parsing report content.")
    else:
        feedback.append("Report: Report file not found.")

    # ------------------------------------------------------------------
    # Script Existence (Bonus/Sanity Check - incorporated into total)
    # ------------------------------------------------------------------
    # We don't explicitly score the script existence separate from its output (the log),
    # but we can add feedback.
    script_exists = result.get('script', {}).get('exists', False)
    if not script_exists:
        feedback.append("Warning: Python capture script not found on Desktop.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }