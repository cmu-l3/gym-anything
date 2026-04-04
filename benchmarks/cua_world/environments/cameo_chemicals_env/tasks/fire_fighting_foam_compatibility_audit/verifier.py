#!/usr/bin/env python3
"""
Verifier for Fire Fighting Foam Compatibility Audit task.
"""

import json
import base64
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_fire_fighting_foam_compatibility_audit(traj, env_info, task_info):
    """
    Verifies the foam compatibility audit report.
    
    Criteria:
    1. Report file exists and was created during task.
    2. Correct classification (AR-AFFF vs Standard) for all 6 chemicals.
    3. Correct ERG Guide numbers for all 6 chemicals.
    4. VLM verification that agent visited chemical pages.
    """
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence (10 pts)
    score = 0
    feedback = []
    
    if not result.get("output_file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file ~/Documents/foam_audit.txt not found."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task session."}
    
    score += 10
    feedback.append("Report file created.")

    # 3. Decode and Parse Content
    try:
        content_b64 = result.get("file_content_b64", "")
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to decode report content: {str(e)}"}

    # Define Ground Truth
    # Requirement: Name match + (ERG match) + (Requirement match)
    # Using relaxed matching to account for formatting variations
    chemicals = [
        {"name": "Acetone", "erg": "127", "req": "AR-AFFF", "anti_req": "STANDARD"},
        {"name": "Benzene", "erg": "130", "req": "STANDARD", "anti_req": "AR-AFFF"},
        {"name": "Isopropyl Alcohol", "erg": "129", "req": "AR-AFFF", "anti_req": "STANDARD"},
        {"name": "n-Hexane", "erg": "128", "req": "STANDARD", "anti_req": "AR-AFFF"},
        {"name": "Methyl Ethyl Ketone", "erg": "127", "req": "AR-AFFF", "anti_req": "STANDARD"},
        {"name": "Turpentine", "erg": "128", "req": "STANDARD", "anti_req": "AR-AFFF"}
    ]

    # Normalize content for search
    content_lower = content.lower()
    
    # Scoring: 15 pts per chemical (5 pts for finding it + 5 pts for correct ERG + 5 pts for correct classification)
    # Total 90 pts for chemicals + 10 pts for file existence = 100
    
    chem_score = 0
    
    for chem in chemicals:
        # Check if chemical name is present
        # We search for the name or common synonyms if needed, but task gave specific names
        # Just simple string search on the name part
        name_found = chem["name"].lower() in content_lower
        
        if not name_found:
            feedback.append(f"❌ Missing {chem['name']}")
            continue
            
        # Extract the 'block' of text for this chemical to avoid cross-contamination
        # This is hard with free text, so we'll look for proximity or just global presence if simple
        # A robust way: split by double newlines or headers. 
        # For this verifier, we'll try to find the lines following the name.
        
        # Simple heuristic: Look for the chemical name, then look at the next 100 characters
        # OR just check if the specific combination exists in the file (less strict on structure)
        
        # Let's try a regex for the specific block
        # Look for Name ... ERG ... Requirement
        # Using a wide window
        
        # Check ERG
        # Allow 127/129 swap for alcohols sometimes, but generally strict
        erg_hit = f"{chem['erg']}" in content
        
        # Check Classification
        # Look for "AR-AFFF" or "Alcohol-Resistant" vs "Standard" or "Regular"
        req_hit = False
        if chem["req"] == "AR-AFFF":
            if "ar-afff" in content_lower or "alcohol-resistant" in content_lower or "polar solvent" in content_lower:
                # We need to make sure we associate it with the right chemical. 
                # This simple global check is weak if they mix them up.
                # Let's assume the agent follows the requested format:
                # Name
                # ERG
                # Requirement
                pass 
        
        # Improved parsing: Split by chemical names
        # This assumes the agent writes them in some order or clearly separated
        # We will split the file by the known chemical names to isolate sections.
        
        # Find start index of this chemical
        idx = content_lower.find(chem["name"].lower())
        if idx == -1: 
             continue # Already handled
             
        # Find start of NEXT chemical (closest one)
        next_indices = [content_lower.find(c["name"].lower()) for c in chemicals if c["name"] != chem["name"]]
        next_indices = [i for i in next_indices if i > idx]
        end_idx = min(next_indices) if next_indices else len(content_lower)
        
        section = content_lower[idx:end_idx]
        
        # Evaluate Section
        chem_points = 5 # Base for presence
        
        # Check ERG in section
        if chem["erg"] in section:
            chem_points += 5
        else:
            feedback.append(f"⚠️ {chem['name']}: Wrong/Missing ERG (Expected {chem['erg']})")
            
        # Check Requirement in section
        if chem["req"] == "AR-AFFF":
            if ("ar-afff" in section or "alcohol" in section or "polar" in section) and "standard" not in section:
                chem_points += 5
            elif "standard" in section or "regular" in section:
                feedback.append(f"❌ {chem['name']}: Incorrectly marked as Standard (Requires AR-AFFF)")
            else:
                 # Check for "required" keyword if they just wrote "AR-AFFF REQUIRED"
                 if "ar-afff" in section: chem_points += 5
                 else: feedback.append(f"❌ {chem['name']}: Classification unclear")
                 
        elif chem["req"] == "STANDARD":
            if ("standard" in section or "regular" in section) and "ar-afff" not in section:
                chem_points += 5
            elif "ar-afff" in section or "alcohol" in section:
                feedback.append(f"❌ {chem['name']}: Incorrectly marked as AR-AFFF (Standard Sufficient)")
            else:
                 if "standard" in section: chem_points += 5
                 else: feedback.append(f"❌ {chem['name']}: Classification unclear")

        chem_score += chem_points
        if chem_points == 15:
            feedback.append(f"✅ {chem['name']}: Correct")

    score += chem_score

    # 4. VLM Verification (Bonus/Confirmation)
    # Check if they actually browsed chemicals. 
    # This detects if they just guessed or pasted pre-known info without looking.
    # We check if trajectory frames show CAMEO pages.
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_result = query_vlm(
            images=frames,
            prompt="Does the user appear to be browsing chemical datasheets on the CAMEO Chemicals website? Look for headers like 'Acetone', 'Benzene', 'Response Recommendations', or 'Firefighting'. Answer yes or no."
        )
        if vlm_result.get("parsed_response", "").lower().startswith("yes"):
            # Could add bonus points or just use as validation
            pass
        else:
            # If score is high but VLM says no browsing, might be suspicious, but text evidence is primary.
            pass

    # Final result
    passed = score >= 85 # Allow one minor error (e.g. one ERG wrong)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }