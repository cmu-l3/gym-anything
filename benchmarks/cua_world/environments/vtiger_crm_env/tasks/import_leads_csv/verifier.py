#!/usr/bin/env python3
"""
Verifier for import_leads_csv task.

Evaluates the imported leads against the CSV ground truth.
Verifies multi-step import via VLM trajectory.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_leads_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/import_leads_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    task_start = result.get('task_start_time', 0)
    recent_leads = result.get('recent_leads', [])

    expected_leads = {
        "Dominguez": "Greenfield Landscaping LLC",
        "Oyelaran": "BrightPath Solar Inc",
        "Kowalski": "Apex Property Management",
        "Nwosu": "Harbor Freight Logistics",
        "Chakraborty": "Sunrise Home Health Services",
        "Whitfield": "Summit Roofing Contractors",
        "Ferreira": "Coastal Realty Group",
        "Al-Rashidi": "Pinnacle IT Solutions"
    }

    score = 0
    feedback = []

    # 1. Check database lead count (20 points)
    count_diff = current_count - initial_count
    if count_diff >= 8:
        score += 20
        feedback.append(f"Lead count increased by {count_diff} (expected >= 8)")
    elif count_diff > 0:
        score += int((count_diff / 8) * 20)
        feedback.append(f"Lead count increased by {count_diff} (expected 8)")
    else:
        feedback.append("Lead count did not increase")

    # Evaluate individual leads
    matches = 0
    fully_populated = 0
    correct_source = 0
    created_after = 0

    for lead in recent_leads:
        lname = lead.get('lastname', '')
        comp = lead.get('company', '')
        
        if lname in expected_leads and expected_leads[lname] == comp:
            matches += 1

            # 2. Check mapped fields (Email, Phone, City)
            if lead.get('email') and lead.get('phone') and lead.get('city'):
                fully_populated += 1

            # 3. Check specific field mapping matching "Trade Show"
            if lead.get('leadsource') == 'Trade Show':
                correct_source += 1

            # 4. Anti-gaming check (Created during task timeline)
            if lead.get('createdtime_ts', 0) >= task_start:
                created_after += 1

    # Apply scoring for matches (25 points)
    if matches >= 8:
        score += 25
        feedback.append("All 8 leads matched by Name and Company")
    elif matches > 0:
        score += int((matches / 8) * 25)
        feedback.append(f"{matches}/8 leads matched by Name and Company")
    else:
        feedback.append("No leads matched expected names/companies")

    # Apply scoring for populated fields (15 points)
    if fully_populated >= 8:
        score += 15
        feedback.append("All fields successfully mapped and populated")
    elif fully_populated > 0:
        score += int((fully_populated / 8) * 15)
        feedback.append(f"{fully_populated}/8 leads had mapped fields populated")

    # Apply scoring for lead source (10 points)
    if correct_source >= 8:
        score += 10
        feedback.append("Lead Source correctly mapped to 'Trade Show'")
    elif correct_source > 0:
        score += int((correct_source / 8) * 10)
        feedback.append(f"{correct_source}/8 leads had correct Lead Source")

    # Apply scoring for creation time (10 points)
    if created_after >= 8:
        score += 10
        feedback.append("Leads created during task timeframe (anti-gaming passed)")
    elif created_after > 0:
        score += int((created_after / 8) * 10)
        feedback.append(f"{created_after}/8 leads created during task timeframe")

    # 5. VLM Verification for Import Process usage (20 points)
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = []
            if frames: images.extend(frames)
            if final: images.append(final)

            if images:
                prompt = """Analyze these screenshots from a trajectory of a user importing leads into a CRM.
Did the user open and use the CRM's CSV Import Wizard? Look for screens with titles like "Import Leads", steps indicating "Step 1" or "Step 2", file upload buttons, or field mapping tables where CSV columns are mapped to CRM fields.

Respond in JSON format exactly like this:
{"used_import_wizard": true, "reasoning": "I can see the step 2 mapping fields..."}"""
                vlm_res = query_vlm(prompt=prompt, images=images)
                
                # Check parsed JSON if available, otherwise check raw text
                used_wizard = False
                if isinstance(vlm_res, dict) and "parsed" in vlm_res:
                    used_wizard = vlm_res["parsed"].get("used_import_wizard", False)
                else:
                    text = vlm_res.get('text', '').lower()
                    if '"used_import_wizard": true' in text or 'true' in text:
                        used_wizard = True

                if used_wizard:
                    vlm_score = 20
                    feedback.append("VLM confirmed interaction with the Import Wizard (+20)")
                else:
                    feedback.append("VLM did not detect interaction with the Import Wizard")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback.append(f"VLM verification skipped due to error")
    
    score += vlm_score

    # Determine passing state
    passed = score >= 75 and count_diff > 0 and matches >= 4

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": {
            "initial_count": initial_count,
            "current_count": current_count,
            "matched_leads": matches,
            "fully_populated": fully_populated,
            "vlm_confirmed": vlm_score > 0
        }
    }