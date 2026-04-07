#!/usr/bin/env python3
import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_drift_detection(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Identified drift (Report)
    2. Preserved config (Extraction)
    3. Stopped bad containers
    4. Started clean containers (from base image, no unauthorized packages)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # ---------------------------------------------------------
    # 1. Report Verification (25 points)
    # ---------------------------------------------------------
    report = result.get("report", {})
    if report.get("exists") and report.get("size", 0) > 100:
        score += 10
        feedback.append("Report file exists.")
        
        # Check content keywords
        content = ""
        try:
            content = base64.b64decode(report.get("content_b64", "")).decode('utf-8', errors='ignore').lower()
        except:
            pass
            
        keywords_met = 0
        if "webserver" in content and ("curl" in content or "default.conf" in content):
            keywords_met += 1
        if "appserver" in content and ("debugpy" in content or "config.json" in content):
            keywords_met += 1
        if "taskrunner" in content and ("backup" in content or "crontab" in content):
            keywords_met += 1
            
        score += (keywords_met * 5) # Max 15
        if keywords_met > 0:
            feedback.append(f"Report covers {keywords_met}/3 containers.")
    else:
        feedback.append("Report missing or too short.")

    # ---------------------------------------------------------
    # 2. Config Extraction Verification (15 points)
    # ---------------------------------------------------------
    configs = result.get("configs", {})
    extracted_count = 0
    if configs.get("webserver_extracted"): extracted_count += 1
    if configs.get("appserver_extracted"): extracted_count += 1
    if configs.get("taskrunner_extracted"): extracted_count += 1
    
    score += (extracted_count * 5)
    feedback.append(f"Configs extracted for {extracted_count}/3 containers.")

    # ---------------------------------------------------------
    # 3. Original Containers Stopped (15 points)
    # ---------------------------------------------------------
    orig = result.get("originals", {})
    stopped_count = 0
    if orig.get("webserver_status") != "running": stopped_count += 1
    if orig.get("appserver_status") != "running": stopped_count += 1
    if orig.get("taskrunner_status") != "running": stopped_count += 1
    
    score += (stopped_count * 5)
    feedback.append(f"Originals stopped: {stopped_count}/3.")

    # ---------------------------------------------------------
    # 4. Clean Containers Running (45 points)
    # ---------------------------------------------------------
    clean = result.get("clean_containers", {})
    
    # Webserver (15 pts)
    ws = clean.get("webserver", {})
    if ws.get("status") == "running" and "nginx" in ws.get("image", "") and ws.get("is_clean"):
        score += 15
        feedback.append("Webserver restored clean.")
    elif ws.get("status") == "running":
        feedback.append("Webserver running but dirty or wrong image.")
    
    # Appserver (15 pts)
    as_ = clean.get("appserver", {})
    if as_.get("status") == "running" and "python" in as_.get("image", "") and as_.get("is_clean"):
        score += 15
        feedback.append("Appserver restored clean.")
    elif as_.get("status") == "running":
        feedback.append("Appserver running but dirty (debugpy found).")

    # Taskrunner (15 pts)
    tr = clean.get("taskrunner", {})
    if tr.get("status") == "running" and "alpine" in tr.get("image", ""):
        score += 15
        feedback.append("Taskrunner restored clean.")
    
    # Final Tally
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }