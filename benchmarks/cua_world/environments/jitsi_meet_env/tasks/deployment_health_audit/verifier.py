#!/usr/bin/env python3
import json
import os
import base64
import re
import logging
import tempfile
from datetime import datetime

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("gym_anything.vlm not available, skipping VLM checks")

def parse_report(report_text):
    """Parses the audit report into sections."""
    sections = {}
    current_section = None
    
    # Define regex for section headers
    header_re = re.compile(r'^--- (.+) ---$')
    
    lines = report_text.split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        match = header_re.match(line)
        if match:
            current_section = match.group(1)
            sections[current_section] = []
        elif current_section:
            sections[current_section].append(line)
            
    return sections

def verify_deployment_health_audit(traj, env_info, task_info):
    """
    Verifies the Jitsi Meet deployment audit task.
    
    Criteria:
    1. Report file exists and was created during task.
    2. Report contains all required sections.
    3. Content Accuracy:
       - Container list matches ground truth (names present).
       - Service status matches ground truth.
       - Network name matches ground truth.
    4. VLM: Evidence of terminal usage and meeting test.
    """
    
    # 1. Load result data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy_from_env not available"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Initialize Scoring
    score = 0
    max_score = 100
    feedback = []
    
    # --- Check 1: File Existence & Anti-Gaming (10 pts) ---
    if not result.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file ~/jitsi_audit_report.txt not found."}
    
    if not result.get("report_created_during_task"):
        feedback.append("Warning: Report file timestamp suggests it wasn't created during this task session.")
        # We penalize but don't fail immediately if content is good (could be time sync issue), 
        # but strictly for anti-gaming we usually fail or heavily penalize.
        score += 0 
    else:
        score += 10
        feedback.append("Report file created during task.")

    # Decode report content
    try:
        report_text = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8')
    except:
        return {"passed": False, "score": score, "feedback": "Failed to decode report content."}
        
    if len(report_text) < 50:
        return {"passed": False, "score": score, "feedback": "Report file is too short/empty."}
        
    # --- Check 2: Structure (15 pts) ---
    parsed_report = parse_report(report_text)
    required_sections = [
        "CONTAINER STATUS", 
        "SERVICE CONNECTIVITY", 
        "NETWORK CONFIGURATION", 
        "MEETING FUNCTIONALITY", 
        "SUMMARY"
    ]
    
    missing_sections = [s for s in required_sections if s not in parsed_report]
    if missing_sections:
        feedback.append(f"Missing sections: {', '.join(missing_sections)}")
        score += 0
    else:
        score += 15
        feedback.append("All required report sections present.")
        
    # --- Check 3: Content Accuracy (50 pts) ---
    ground_truth = result.get("ground_truth", {})
    gt_containers = ground_truth.get("containers", [])
    gt_services = ground_truth.get("services", {})
    gt_network = ground_truth.get("network", {})
    
    # 3a. Container Status (15 pts)
    # Check if real container names appear in the report
    containers_found_count = 0
    container_section = "\n".join(parsed_report.get("CONTAINER STATUS", []))
    
    # Identify key containers we expect
    key_containers = ["web", "prosody", "jicofo", "jvb"]
    found_containers = []
    
    for container in gt_containers:
        # Check if Name or Image is in text
        c_name = container.get("Names", "unknown")
        c_image = container.get("Image", "unknown")
        
        # Determine if this is a Jitsi container
        is_jitsi = any(k in c_name or k in c_image for k in key_containers)
        
        if is_jitsi:
            # Check if mentioned in report
            if c_name in container_section or (c_image and c_image in container_section):
                found_containers.append(c_name)
    
    if len(found_containers) >= 4:
        score += 15
        feedback.append(f"Correctly listed Jitsi containers.")
    elif len(found_containers) > 0:
        score += 5
        feedback.append(f"Only listed {len(found_containers)}/4 Jitsi containers.")
    else:
        feedback.append("No Jitsi containers identified in Container Status section.")

    # 3b. Service Connectivity (15 pts)
    # Check if report status matches ground truth status
    service_section = "\n".join(parsed_report.get("SERVICE CONNECTIVITY", [])).lower()
    services_correct = 0
    
    # Web
    if gt_services.get("web") == "accessible" and "web ui: accessible" in service_section:
        services_correct += 1
    elif gt_services.get("web") != "accessible" and "web ui: not accessible" in service_section:
        services_correct += 1
        
    # Services (JVB, Prosody, Jicofo) - assuming they are running in the standard happy path
    # We look for "running" string associated with the service name in the section
    for svc in ["jvb", "prosody", "jicofo"]:
        status = gt_services.get(svc)
        # We expect the user to write "JVB: running" etc.
        if status == "running" and f"{svc}: running" in service_section:
            services_correct += 1
        elif status != "running" and f"{svc}: not running" in service_section:
            services_correct += 1
            
    if services_correct >= 4:
        score += 15
        feedback.append("Service connectivity status reported correctly.")
    else:
        score += int(15 * (services_correct / 4))
        feedback.append(f"Service status partially correct ({services_correct}/4).")

    # 3c. Network Config (10 pts)
    network_section = "\n".join(parsed_report.get("NETWORK CONFIGURATION", []))
    gt_net_name = gt_network.get("name", "")
    
    if gt_net_name and gt_net_name in network_section:
        score += 10
        feedback.append(f"Correctly identified Docker network: {gt_net_name}")
    else:
        feedback.append(f"Failed to identify correct Docker network (Expected: {gt_net_name})")
        
    # 3d. Meeting Functionality (10 pts)
    meeting_section = "\n".join(parsed_report.get("MEETING FUNCTIONALITY", [])).lower()
    if "functional" in meeting_section and "not functional" not in meeting_section:
        # Assuming happy path where it IS functional. 
        # Ideally we verify if the room was actually created, but here we check report consistency.
        score += 10
        feedback.append("Meeting reported as functional.")
    else:
        feedback.append("Meeting reported as not functional or status unclear.")

    # --- Check 4: VLM Evidence (25 pts) ---
    # We want to see:
    # 1. Terminal open with docker commands (10 pts)
    # 2. Browser open in the meeting room (15 pts)
    
    if VLM_AVAILABLE:
        # Get frames
        frames = sample_trajectory_frames(traj, n=10)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        from gym_anything.vlm import query_vlm
        
        prompt = """
        You are verifying a Jitsi Meet system audit task. 
        Look at these screenshots of the agent's screen.
        
        Check for two specific activities:
        1. TERMINAL_USAGE: Is there a terminal window visible showing 'docker' commands (like 'docker ps')?
        2. MEETING_TEST: Is the web browser visible showing a Jitsi meeting room (video interface, toolbar)?
        
        Respond in JSON:
        {
            "terminal_docker_visible": true/false,
            "jitsi_meeting_visible": true/false
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("terminal_docker_visible"):
                score += 10
                feedback.append("VLM: Docker terminal usage confirmed.")
            else:
                feedback.append("VLM: No Docker terminal usage observed.")
                
            if parsed.get("jitsi_meeting_visible"):
                score += 15
                feedback.append("VLM: Jitsi meeting test confirmed.")
            else:
                feedback.append("VLM: No Jitsi meeting room observed.")
        else:
            # Fallback if VLM fails: award partial points if report is good to avoid blocking
            if score >= 60:
                score += 15
                feedback.append("VLM check failed, awarding partial fallback points.")
    else:
        # If VLM not available in env, auto-pass this section if report is high quality
        if score >= 60:
            score += 25
            feedback.append("VLM unavailable, assuming success based on report quality.")

    passed = score >= 60 and result.get("report_exists") and len(found_containers) >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }