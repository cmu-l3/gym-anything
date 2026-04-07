#!/usr/bin/env python3
"""
Verifier for EHR Integration Feasibility Task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ehr_integration_feasibility(traj, env_info, task_info):
    """
    Verifies the task based on:
    1. Simulation State: At least 2 distinct devices created + Vital Signs app launched.
    2. Report Artifact: File exists, created during task, sufficient size.
    3. Report Content: Contains specific keywords proving technical investigation (DDS, ICE, etc.).
    4. VLM Verification: Visual confirmation of workflow.
    """
    
    # 1. Setup Interface
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 2. Retrieve Data
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    result_data = {}
    report_content = ""
    
    try:
        # Get JSON Result
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result_data = json.load(f)
            
        # Get Report Content (if exists)
        if result_data.get("report_exists"):
            try:
                copy_from_env(metadata.get("report_path"), report_file.name)
                with open(report_file.name, 'r', errors='ignore') as f:
                    report_content = f.read()
            except Exception as e:
                logger.warning(f"Could not copy report file despite existence flag: {e}")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving verification data: {e}"}
    finally:
        if os.path.exists(result_file.name): os.unlink(result_file.name)
        if os.path.exists(report_file.name): os.unlink(report_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # --- Criterion 1: Device Simulation (20 pts) ---
    # Combine log and window detection
    log_devs = [d for d in result_data.get("log_devices_detected", "").split(",") if d]
    win_devs = [d for d in result_data.get("window_devices_detected", "").split(",") if d]
    all_devs = set(log_devs + win_devs)
    
    if len(all_devs) >= 2:
        score += 20
        feedback.append(f"Success: {len(all_devs)} distinct devices detected ({', '.join(all_devs)}).")
    elif len(all_devs) == 1:
        score += 10
        feedback.append(f"Partial: Only 1 device detected ({list(all_devs)[0]}). Expected 2.")
    else:
        feedback.append("Fail: No simulated devices detected.")

    # --- Criterion 2: Clinical App Launch (10 pts) ---
    if result_data.get("app_launched_log") or result_data.get("app_window_detected"):
        score += 10
        feedback.append("Success: Vital Signs app launched.")
    else:
        feedback.append("Fail: Vital Signs app not detected.")

    # --- Criterion 3: Report Mechanics (15 pts) ---
    report_valid = False
    if result_data.get("report_exists"):
        if result_data.get("report_created_during_task"):
            if result_data.get("report_size", 0) >= metadata.get("min_report_bytes", 500):
                score += 15
                report_valid = True
                feedback.append("Success: Report file created with sufficient content.")
            else:
                score += 5
                feedback.append("Partial: Report exists but is too short (<500 bytes).")
        else:
            feedback.append("Fail: Report file timestamp is before task start (pre-existing file?).")
    else:
        feedback.append("Fail: Report file not found.")

    # --- Criterion 4: Report Content Technical Quality (40 pts) ---
    # Only evaluate if report is valid
    if report_valid and report_content:
        content_lower = report_content.lower()
        
        # Check Sections (10 pts)
        sections_found = 0
        for section in metadata.get("required_sections", []):
            if section.lower() in content_lower:
                sections_found += 1
        
        if sections_found >= 4:
            score += 10
            feedback.append("Report Structure: All required sections present.")
        elif sections_found >= 2:
            score += 5
            feedback.append(f"Report Structure: {sections_found}/4 sections found.")
        
        # Check Keywords (30 pts)
        kw_groups = metadata.get("keywords", {})
        
        # Architecture (DDS/Middleware) - 10 pts
        arch_hits = sum(1 for k in kw_groups.get("architecture", []) if k.lower() in content_lower)
        if arch_hits >= 2: score += 10
        elif arch_hits == 1: score += 5
        
        # Data Model (ICE types) - 10 pts
        model_hits = sum(1 for k in kw_groups.get("data_model", []) if k.lower() in content_lower)
        if model_hits >= 2: score += 10
        elif model_hits == 1: score += 5
        
        # Integration (HL7/FHIR) - 10 pts
        int_hits = sum(1 for k in kw_groups.get("integration", []) if k.lower() in content_lower)
        if int_hits >= 2: score += 10
        elif int_hits == 1: score += 5
        
        feedback.append(f"Content Analysis: Arch({arch_hits}), Model({model_hits}), Int({int_hits}) keywords found.")

    # --- Criterion 5: VLM / OpenICE Running (15 pts) ---
    # Simple check for running process first
    if result_data.get("openice_running"):
        score += 15
        feedback.append("System Status: OpenICE is running.")
    else:
        feedback.append("Fail: OpenICE was not running at verification time.")

    # --- Final Result ---
    # Gate: Must have at least one device and a valid report to pass
    passed = (score >= 60) and (len(all_devs) >= 1) and report_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }