#!/usr/bin/env python3
"""
Verifier for configure_region_site task.

Verifies:
1. Region "Asia Pacific" exists (Database)
2. Site "Singapore Hub" exists (Database)
3. Site is correctly linked to the Region (Database Foreign Key check)
4. Site address details match specifications (Database)
5. Evidence of work (Screenshots/Logs)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_region_site(traj, env_info, task_info):
    """
    Verify the agent configured the Region and Site correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_region = metadata.get('expected_region', 'Asia Pacific')
    expected_site = metadata.get('expected_site', 'Singapore Hub')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_data = result.get('db_data', {})
    score = 0
    feedback = []
    
    # 1. Verify Region (25 pts)
    if db_data.get('region_found'):
        score += 25
        feedback.append(f"Region '{expected_region}' created successfully.")
        region_id = db_data.get('region_id')
    else:
        feedback.append(f"Region '{expected_region}' NOT found.")
        region_id = None

    # 2. Verify Site Existence (25 pts)
    site_details = db_data.get('site_details', {})
    if db_data.get('site_found'):
        score += 25
        feedback.append(f"Site '{expected_site}' created successfully.")
    else:
        feedback.append(f"Site '{expected_site}' NOT found.")

    # 3. Verify Hierarchy (30 pts)
    # The site's regionid must match the created region's id
    linked_region_id = site_details.get('linked_region_id')
    
    if region_id and linked_region_id and str(region_id) == str(linked_region_id):
        score += 30
        feedback.append("Site is correctly linked to the new Region.")
    elif db_data.get('site_found'):
        feedback.append(f"Site linked to wrong region (ID: {linked_region_id} vs {region_id}).")
    
    # 4. Verify Address Details (20 pts)
    address_score = 0
    # Address (5)
    if metadata.get('expected_address') in site_details.get('address', ''):
        address_score += 5
    # City (5)
    if metadata.get('expected_city').lower() == site_details.get('city', '').lower():
        address_score += 5
    # Zip (5)
    if metadata.get('expected_zip') in site_details.get('zip', ''):
        address_score += 5
    # Country (5)
    if metadata.get('expected_country').lower() == site_details.get('country', '').lower():
        address_score += 5
    
    if address_score > 0:
        score += address_score
        feedback.append(f"Address details verification: {address_score}/20 points.")
    else:
        feedback.append("Address details missing or incorrect.")

    # 5. VLM Verification (sanity check / bonus / tie-breaker)
    # We use VLM to verify if the UI actually shows the hierarchy if the DB check is ambiguous
    # or just to confirm the agent was interacting with the right screens.
    # Since DB check is robust here, we use VLM mainly for trajectory validation.
    
    final_img = get_final_screenshot(traj)
    if final_img:
        vlm_res = query_vlm(
            images=[final_img], 
            prompt=f"Does this screen show a list of Sites or Regions, specifically '{expected_site}' or '{expected_region}'? Answer yes/no."
        )
        if vlm_res and "yes" in vlm_res.get("result", "").lower():
            feedback.append("VLM confirms site visible in UI.")
        
    passed = (score >= 80) and db_data.get('region_found') and db_data.get('site_found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }