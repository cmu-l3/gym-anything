#!/usr/bin/env python3
"""
Verifier for gold_mine_cyanide_storage task.

Evaluation Strategy:
1. Programmatic DB Verification: Copies the parsed JSON export of the Tier2 Submit SQLite database.
2. VLM Trajectory Verification: Examines screenshots to confirm agent interacted with UI properly.
3. Scoring logic validates file existence, chemical identity, physical states, hazards, and multi-location storage.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure the agent physically manipulated the Tier2 Submit UI
VLM_PROMPT = """You are verifying if an agent successfully configured a complex chemical entry in EPA Tier2 Submit.
Review these sequential screenshots taken during the agent's workflow.

Look for the following evidence:
1. Did the agent open or create a chemical entry for "Sodium Cyanide"?
2. Did the agent check BOTH the "Solid" and "Liquid" checkboxes under Physical State?
3. Did the agent navigate to the "Storage Locations" tab/section and add multiple distinct locations?
4. Are there indications of manual data entry (e.g., typing in text fields, clicking dropdowns)?

Respond in JSON format:
{
    "ui_interaction_observed": true/false,
    "solid_and_liquid_checked": true/false,
    "multiple_storage_locations_added": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly explain what you see in the frames to support your boolean answers."
}
"""

def verify_gold_mine_cyanide_storage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\gold_mine_cyanide_result.json")
    
    # 1. Retrieve the parsed Tier2 Submit database
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # Criterion 1: File Export (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("PASS: Submission file silverstrike_cyanide_t2.t2s was exported successfully (+10).")
    else:
        feedback.append("FAIL: Submission file was not exported to the expected path.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Find Sodium Cyanide chemical entry
    chemicals = result.get("chemicals", [])
    cyanide_entry = None
    for chem in chemicals:
        # Flatten dictionary to easily search for CAS or Name regardless of exact column casing
        flat_vals = " ".join([str(v).lower() for v in chem.values()])
        if "143-33-9" in flat_vals or "cyanide" in flat_vals:
            cyanide_entry = chem
            break

    # Criterion 2: Chemical Identity & EHS (15 pts)
    if cyanide_entry:
        score += 15
        feedback.append("PASS: Sodium Cyanide chemical entry found (+15).")
    else:
        feedback.append("FAIL: Sodium Cyanide (CAS 143-33-9) not found in the exported database.")
        
    if cyanide_entry:
        flat_chem_vals = " ".join([str(v).lower() for v in cyanide_entry.values()])
        
        # Criterion 3: Physical States - Solid & Liquid (15 pts)
        # Often mapped as boolean fields like StateSolid=1 and StateLiquid=1
        solid_found = "solid" in flat_chem_vals or "1" in [str(cyanide_entry.get(k)) for k in cyanide_entry.keys() if "solid" in k.lower()]
        liquid_found = "liquid" in flat_chem_vals or "1" in [str(cyanide_entry.get(k)) for k in cyanide_entry.keys() if "liquid" in k.lower()]
        
        if solid_found and liquid_found:
            score += 15
            feedback.append("PASS: Both Solid and Liquid physical states are recorded (+15).")
        else:
            feedback.append("FAIL: Did not find both Solid and Liquid physical states in the database.")

        # Criterion 4: Quantities (10 pts)
        # Checking for amounts or range codes (45000/30000 or range 05/04)
        if "45000" in flat_chem_vals and "30000" in flat_chem_vals:
            score += 10
            feedback.append("PASS: Maximum and Average quantities correctly recorded (+10).")
        elif "05" in flat_chem_vals and "04" in flat_chem_vals:
            score += 10
            feedback.append("PASS: Maximum and Average quantity range codes correctly recorded (+10).")
        else:
            feedback.append("FAIL: Maximum/Average quantities are missing or incorrect.")

        # Criterion 5 & 6: Storage Locations (30 pts)
        storage_locations = cyanide_entry.get("storage_locations", [])
        if len(storage_locations) >= 2:
            bag_warehouse_found = False
            tank_outdoor_found = False
            
            for loc in storage_locations:
                flat_loc = " ".join([str(v).lower() for v in loc.values()])
                if ("bag" in flat_loc or "sack" in flat_loc) and "warehouse" in flat_loc:
                    bag_warehouse_found = True
                if ("tank" in flat_loc) and ("cyanide mixing" in flat_loc or "outdoor" in flat_loc):
                    tank_outdoor_found = True
                    
            if bag_warehouse_found:
                score += 15
                feedback.append("PASS: Solid Reagent storage location (Bag/Warehouse) found (+15).")
            else:
                feedback.append("FAIL: Solid Reagent storage location (Bag/Warehouse) missing or incorrect.")
                
            if tank_outdoor_found:
                score += 15
                feedback.append("PASS: Liquid Solution storage location (Tank/Outdoor) found (+15).")
            else:
                feedback.append("FAIL: Liquid Solution storage location (Tank/Outdoor) missing or incorrect.")
        else:
            feedback.append(f"FAIL: Expected 2+ storage locations, found {len(storage_locations)}.")

    # Criterion 7: VLM Process Verification (20 pts)
    # This acts as an anti-gaming check to ensure the agent didn't just write a python script to forge a .t2s file
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("ui_interaction_observed"):
                score += 10
                feedback.append("PASS: VLM confirmed UI interaction (+10).")
            
            if parsed.get("multiple_storage_locations_added") or parsed.get("solid_and_liquid_checked"):
                score += 10
                feedback.append("PASS: VLM confirmed proper data entry workflow (+10).")
    except Exception as e:
        logger.warning(f"VLM Verification skipped or failed: {e}")
        # If VLM fails but DB programmatic checks are perfect, we can still pass them on programmatic alone.

    # Final tally
    passed = score >= 70
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }