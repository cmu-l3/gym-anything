#!/usr/bin/env python3
"""
Verifier for add_hospital_resource task in CAMEO Data Manager.

Verification Strategy:
1. Programmatic (Primary): 
   - Check if CAMEO database files were modified.
   - grep the raw database files for the specific hospital string ("Memorial Hermann Southeast").
2. Visual (Secondary): 
   - Use VLM to inspect the final screenshot for the correct record details.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_hospital_resource(traj, env_info, task_info):
    """
    Verify that the hospital was added to CAMEO Data Manager.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Database Verification (40 points)
    # Check if database file contains the hospital name (strong evidence of save)
    if result.get('record_string_found', False):
        score += 30
        feedback_parts.append("Database record found (Name match)")
    else:
        feedback_parts.append("Hospital name NOT found in database files")

    if result.get('details_string_found', False):
        score += 10
        feedback_parts.append("Address details found in database")
    
    # Check if files were modified (Anti-gaming)
    if result.get('db_modified', False):
        score += 10
        feedback_parts.append("Database files modified during task")
    else:
        feedback_parts.append("Warning: No database modification detected")

    # 3. VLM Verification (50 points)
    # Check final screenshot for visual confirmation
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of CAMEO Data Manager.
        
        Goal: Verify a new hospital record was added.
        
        Look for:
        1. A record named "Memorial Hermann Southeast Hospital".
        2. Address: "11800 Astoria Blvd".
        3. Phone: "(713) 222-2323".
        4. Section: "Resources" or "Hospitals" (not Facilities).
        
        Return JSON:
        {
            "hospital_name_visible": boolean,
            "address_visible": boolean,
            "phone_visible": boolean,
            "is_resources_section": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_out = query_vlm(
            prompt=prompt,
            images=frames + [final_screenshot]
        )
        
        if vlm_out.get('success'):
            parsed = vlm_out.get('parsed', {})
            
            if parsed.get('hospital_name_visible'):
                score += 20
                feedback_parts.append("VLM: Hospital name visible")
            
            if parsed.get('address_visible'):
                score += 10
                feedback_parts.append("VLM: Address visible")
                
            if parsed.get('phone_visible'):
                score += 10
                feedback_parts.append("VLM: Phone visible")
                
            if parsed.get('is_resources_section'):
                score += 10
                feedback_parts.append("VLM: Correct section (Resources)")
    else:
        feedback_parts.append("No screenshots available for VLM verification")

    # Passing logic
    # Must have either DB confirmation OR strong Visual confirmation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }