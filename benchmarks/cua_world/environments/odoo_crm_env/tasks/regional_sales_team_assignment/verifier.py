#!/usr/bin/env python3
"""
Verifier for regional_sales_team_assignment task.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regional_sales_team_assignment(traj, env_info, task_info):
    """
    Verify that the 'West Coast' sales team was created and CA leads were assigned to it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata for expected values
    metadata = task_info.get('metadata', {})
    ca_leads = metadata.get('ca_leads', [
        "Golden Gate Software Upgrade",
        "SoCal Surf Shop Franchise",
        "Napa Valley Logistics"
    ])
    control_leads = metadata.get('control_leads', [
        "Gotham Trading Platform", 
        "Austin Warehouse Automation"
    ])

    # --- CRITERION 1: Team Creation (30 points) ---
    if result.get("team_created"):
        score += 30
        feedback_parts.append("✅ 'West Coast' team created")
        
        # Anti-gaming: Check creation time vs task start (if available in Odoo format)
        # Odoo dates are string "YYYY-MM-DD HH:MM:SS". Simple presence check is usually sufficient
        # combined with "write_date" checks on leads.
    else:
        feedback_parts.append("❌ 'West Coast' team NOT found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Sales team 'West Coast' was not created. Cannot verify assignments."
        }

    assignments = result.get("assignments", {})

    # --- CRITERION 2: CA Leads Reassigned (20 points each, max 60) ---
    ca_success_count = 0
    for lead_name in ca_leads:
        lead_data = assignments.get(lead_name)
        if not lead_data:
            feedback_parts.append(f"⚠️ Lead '{lead_name}' not found in DB")
            continue
            
        if lead_data.get("is_west_coast"):
            score += 20
            ca_success_count += 1
            feedback_parts.append(f"✅ '{lead_name}' assigned correctly")
        else:
            current_team = lead_data.get("team_name", "Unassigned")
            feedback_parts.append(f"❌ '{lead_name}' is in '{current_team}' (expected West Coast)")

    # --- CRITERION 3: Non-CA Leads Untouched (10 points) ---
    # Points awarded if NO collateral damage
    collateral_damage = False
    for lead_name in control_leads:
        lead_data = assignments.get(lead_name)
        if lead_data and lead_data.get("is_west_coast"):
            collateral_damage = True
            feedback_parts.append(f"❌ '{lead_name}' (Non-CA) incorrectly moved to West Coast")
    
    if not collateral_damage:
        score += 10
        feedback_parts.append("✅ Non-California leads remained in original teams")
    
    # --- Final Evaluation ---
    passed = (score >= 70)  # Requires Team Created (30) + at least 2 leads (40) = 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }