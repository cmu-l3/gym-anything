#!/usr/bin/env python3
"""
Verifier for Audit Patient Eligibility task.

Verifies that the agent has identified and displayed the correct text names
for the patient's Period of Service and Primary Eligibility Code.

Verification Logic:
1. Checks if infrastructure (VistA, YDBGui) was running.
2. Uses Ground Truth data extracted during export to know what text to look for.
3. Uses VLM to check if that specific text is visible in the final screenshot.
"""

import json
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_patient_eligibility(traj, env_info, task_info):
    """
    Verify the agent displayed the resolved service and eligibility names.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Copy result JSON from container
    import tempfile
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_json.close()
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Basic Infrastructure Checks (25 points)
    score = 0
    feedback_parts = []
    
    # VistA Running (10 pts)
    if result.get("vista_container_status") == "running":
        score += 10
        feedback_parts.append("VistA running")
    else:
        feedback_parts.append("VistA stopped")

    # YDBGui Accessible (10 pts)
    if result.get("ydbgui_accessible"):
        score += 10
        feedback_parts.append("YDBGui accessible")
    
    # Browser Open (5 pts)
    if result.get("browser_window_open"):
        score += 5
        feedback_parts.append("Browser open")

    # 3. Ground Truth Verification using VLM (75 points)
    ground_truth = result.get("ground_truth", {})
    svc_name = ground_truth.get("service_name", "").strip()
    elig_name = ground_truth.get("eligibility_name", "").strip()
    
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')

    if not svc_name or not elig_name:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Setup Error: Ground truth data could not be retrieved from VistA."
        }

    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        # VLM Query
        prompt = f"""
        Analyze this screenshot of a medical database interface.
        
        I am looking for two specific pieces of information about a patient's history:
        1. Period of Service: "{svc_name}"
        2. Eligibility Code: "{elig_name}"
        
        Task:
        - Look for the text "{svc_name}" (case-insensitive).
        - Look for the text "{elig_name}" (case-insensitive).
        - Look for context like "Period of Service", "Eligibility", "^DIC(21)", "^DIC(8)", or SQL query results.
        
        Return JSON:
        {{
            "service_name_visible": true/false,
            "eligibility_name_visible": true/false,
            "context_visible": "what kind of data is shown (global viewer, sql result, etc)",
            "explanation": "brief reasoning"
        }}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            
            # Simple fallback parsing if VLM doesn't return dict
            if isinstance(vlm_resp, dict):
                parsed = vlm_resp
            else:
                # Try to parse JSON from string
                try:
                    # Clean markdown code blocks if present
                    clean_resp = vlm_resp.replace("