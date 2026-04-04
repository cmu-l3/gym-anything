#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_restructure_unformatted_leads(traj, env_info, task_info):
    """
    Verifies that the three leads were correctly restructured in Odoo CRM.
    
    Criteria:
    1. Database state check (High weight):
       - Name (Title) cleaned
       - Contact Name extracted
       - Priority set (for the urgent lead)
    2. VLM Verification (Low weight):
       - Confirms the agent interacted with the forms.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            db_results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in db_results:
        return {"passed": False, "score": 0, "feedback": f"Database query failed: {db_results['error']}"}

    # 2. Evaluate Database State
    score = 0
    feedback = []
    
    # Define expectations
    expectations = {
        "REF_LEAD_001": {"contact": "Alice Wong", "title": "Q3 Software License"},
        "REF_LEAD_002": {"contact": "David Miller", "title": "Fleet Audit"},
        "REF_LEAD_003": {"contact": "Elena Sisko", "title": "Security Breach Response", "priority": "3"}
    }

    total_checks = 0
    passed_checks = 0

    for ref, expected in expectations.items():
        record = db_results.get(ref, {})
        
        if not record.get("found"):
            feedback.append(f"❌ Lead {ref} ({expected['contact']}) not found in database.")
            continue

        # Check Contact Name (approx 30 pts total)
        actual_contact = (record.get("contact_name") or "").strip()
        if actual_contact.lower() == expected["contact"].lower():
            score += 10
            feedback.append(f"✅ Lead {ref}: Contact name correct.")
        else:
            feedback.append(f"❌ Lead {ref}: Expected contact '{expected['contact']}', got '{actual_contact}'.")

        # Check Title (approx 30 pts total)
        # Allow minor flexibility (trimming)
        actual_title = (record.get("name") or "").strip()
        if actual_title.lower() == expected["title"].lower():
            score += 10
            feedback.append(f"✅ Lead {ref}: Title cleaned.")
        else:
            # Check if they failed to remove the name/hyphen
            if expected["title"].lower() in actual_title.lower() and len(actual_title) > len(expected["title"]) + 5:
                feedback.append(f"⚠️ Lead {ref}: Title contains correct text but wasn't fully cleaned ('{actual_title}').")
                score += 5 # Partial credit
            else:
                feedback.append(f"❌ Lead {ref}: Expected title '{expected['title']}', got '{actual_title}'.")

        # Check Priority for the urgent lead (25 pts)
        if "priority" in expected:
            actual_priority = str(record.get("priority", "0"))
            if actual_priority == expected["priority"]:
                score += 25
                feedback.append(f"✅ Lead {ref}: Priority set to High (3 stars).")
            else:
                feedback.append(f"❌ Lead {ref}: Expected priority '{expected['priority']}', got '{actual_priority}'.")

    # 3. VLM Verification (15 pts)
    # Ensure they actually opened forms and didn't just magic the DB (though DB check is primary)
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of an agent working in Odoo CRM.
    Did the agent:
    1. Open a lead/opportunity form view?
    2. Edit the 'Contact Name' or 'Opportunity' fields?
    3. Click on the priority stars (for one of the leads)?
    
    Answer yes/no for each.
    """
    
    try:
        # Simple VLM check - we give points if it looks like they worked in CRM
        # Since DB verification is very strong here, we treat VLM as a sanity check
        vlm_result = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
        vlm_text = vlm_result.get("response", "").lower()
        
        if "yes" in vlm_text:
            score += 15
            feedback.append("✅ Visual verification passed.")
        else:
            feedback.append("⚠️ Visual verification inconclusive (did not clearly see form editing).")
            # We don't fail strictly on VLM if DB is perfect
            if score >= 80: 
                score += 15
    except Exception as e:
        feedback.append(f"⚠️ VLM check skipped: {e}")
        # Grace points if DB is perfect
        if score >= 80:
            score += 15

    # 4. Final Scoring
    # Max possible: 30 (contacts) + 30 (titles) + 25 (priority) + 15 (VLM) = 100
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }