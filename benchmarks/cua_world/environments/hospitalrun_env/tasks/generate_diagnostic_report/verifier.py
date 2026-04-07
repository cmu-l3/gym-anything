#!/usr/bin/env python3
"""
Verifier for generate_diagnostic_report task.

Verification Strategy:
1.  VLM Analysis (Primary):
    - Analyze the final screenshot to confirm the Diagnostic Report is visible.
    - Check for specific keywords (report title, date range, diagnosis names).
    - Analyze trajectory frames to verify the workflow (navigation -> input -> generation).
2.  Anti-Gaming:
    - Ensure meaningful state change (initial != final).
    - Ensure timestamp validity.

Pass Threshold: 60 points (Requires report generation and correct content)
"""

import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_diagnostic_report(traj, env_info, task_info):
    """
    Verify that the Diagnostic Report was generated correctly.
    """
    # 1. Setup & Data Extraction
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_text = metadata.get('expected_text_visible', [])
    start_date = metadata.get('start_date', '01/01/2025')
    end_date = metadata.get('end_date', '01/31/2025')

    score = 0
    feedback_parts = []
    
    # 2. VLM Analysis of Final State
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available"}

    # Prompt for VLM to check final report state
    vlm_prompt_final = f"""
    Analyze this screenshot of the HospitalRun application.
    1. Is a "Diagnostic Report" or "Diagnosis Report" visible?
    2. Is there a table or list of diagnoses shown?
    3. Can you see the date range {start_date} to {end_date} (or "Jan 1st" to "Jan 31st")?
    4. Are any of these terms visible: "Pneumonia", "Diabetes", "Hypertension"?
    
    Output JSON:
    {{
        "is_report_page": true/false,
        "is_diagnostic_report": true/false,
        "data_table_visible": true/false,
        "date_range_correct": true/false,
        "diagnoses_visible": ["list found terms"],
        "is_empty_report": true/false
    }}
    """
    
    # We assume 'query_vlm' is available in the global scope or passed in some way.
    # In standard framework usage, we use the helper provided by the environment.
    # Since I cannot import the actual VLM client here, I will structure this 
    # assuming the framework executes this code with access to the VLM.
    
    # Note: In the provided examples, `query_vlm` is not passed to the verifier function directly,
    # but the verifier imports `query_vlm` from `gym_anything.vlm` or similar.
    # The instructions say "USE TRAJECTORY FRAMES... result = query_vlm(...)".
    # I will import a placeholder/helper for this.
    
    try:
        from gym_anything.vlm import query_vlm
        vlm_result_final = query_vlm(images=[final_screenshot], prompt=vlm_prompt_final)
        
        # Parse VLM output (handle potential JSON parsing errors safely)
        if isinstance(vlm_result_final, str):
            # Try to extract JSON from markdown block if needed
            if "