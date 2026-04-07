#!/usr/bin/env python3
"""
Verifier for Review Immunization Records task in VistA.

Verification Strategy:
1. Check VistA/YDBGui infrastructure status (20 points)
2. Use VLM to verify trajectory frames/final state for:
   - Navigation to ^AUTNIMM (Immunization Types)
   - Visibility of vaccine names (e.g., INFLUENZA)
   - Navigation to ^AUPNVIMM (Vaccination Events)
   - Visibility of event data

Scoring (100 points):
- VistA container running: 10 points
- YDBGui accessible: 10 points
- Immunization Types (^AUTNIMM) navigated: 25 points
- Vaccine names visible: 20 points
- Vaccination Events (^AUPNVIMM) navigated: 20 points
- Event details visible: 15 points

Pass threshold: 55 points
"""

import json
import os
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_review_immunization_records(traj, env_info, task_info):
    """
    Verify that immunization globals were reviewed in YDBGui.
    """
    # Use copy_from_env to retrieve the result JSON
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/review_immunization_records_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # -------------------------------------------------------------------------
    # Infrastructure Checks (20 points)
    # -------------------------------------------------------------------------
    
    # Vista Running (10 pts)
    if result.get('vista_container_status') == 'running':
        score += 10
        subscores['vista_running'] = True
        feedback_parts.append("VistA container running")
    else:
        feedback_parts.append("VistA container NOT running")

    # YDBGui Accessible (10 pts)
    if result.get('ydbgui_accessible'):
        score += 10
        subscores['ydbgui_accessible'] = True
        feedback_parts.append("YDBGui accessible")
    else:
        feedback_parts.append("YDBGui NOT accessible")

    # -------------------------------------------------------------------------
    # VLM Visual Verification (80 points)
    # -------------------------------------------------------------------------
    
    # Collect frames for analysis (last 3 frames + final) to catch trajectory
    frames_to_analyze = []
    
    # Helper to get frames safely
    if hasattr(traj, 'get_images'): # If traj object
        frames_to_analyze = traj.get_images()[-3:]
    elif isinstance(traj, dict): # If dict
        # Try different common keys
        paths = traj.get('screenshots', []) or traj.get('images', [])
        frames_to_analyze = paths[-3:]
        
    final_screenshot = result.get('screenshot_path')
    # Note: final_screenshot path is inside container, we need the one from traj if possible
    # Usually the verifier runs on host, so we use traj images. 
    # If traj has no images, we can't do VLM.
    
    if not frames_to_analyze and query_vlm:
        feedback_parts.append("No screenshots available for visual verification")
    elif query_vlm:
        # Prompt checking for BOTH globals
        prompt = """Analyze this series of screenshots from the VistA YDBGui EHR interface.
        
        I need to verify that the user reviewed IMMUNIZATION data.
        
        Look for TWO specific things:
        
        1. IMMUNIZATION TYPES (Global: ^AUTNIMM):
           - Look for "^AUTNIMM" text in the Global viewer
           - Look for vaccine names like "INFLUENZA", "TETANUS", "PNEUMO", "COVID", "HEPATITIS"
           - Look for a list of vaccines
           
        2. VACCINATION EVENTS (Global: ^AUPNVIMM):
           - Look for "^AUPNVIMM" text in the Global viewer
           - Look for numerical data linking patients (DFN) to vaccines
           - Look for dates or "V IMMUNIZATION" header
           
        Also checking for SQL/Octo usage: "SELECT * FROM IMMUNIZATION" or similar.
        
        Return JSON:
        {
           "autnimm_navigated": boolean,
           "vaccine_names_visible": boolean,
           "aupnvimm_navigated": boolean,
           "event_data_visible": boolean,
           "evidence": "brief description of what you see"
        }
        """
        
        # We query the VLM with the sequence of images to capture the workflow
        # Assuming query_vlm handles a list of images or we loop
        # For simplicity in this template, we'll try the last frame first, 
        # but robust implementation might check max score across frames.
        
        best_vlm_score = 0
        best_vlm_result = {}
        
        # Analyze the frames (limit to last few to avoid API costs/time)
        for img in frames_to_analyze:
            try:
                vlm_resp = query_vlm(image=img, prompt=prompt)
                
                # Parse JSON from VLM
                # Note: query_vlm implementation details vary, assuming it returns dict or json string
                if isinstance(vlm_resp, str):
                    # Clean markdown code blocks if present
                    clean_resp = vlm_resp.replace("