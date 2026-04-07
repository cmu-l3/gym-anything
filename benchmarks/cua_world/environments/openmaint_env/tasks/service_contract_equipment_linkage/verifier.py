#!/usr/bin/env python3
"""
Verifier for service_contract_equipment_linkage task.

Scoring:
- C1 (20pts): 3 Equipment CIs created
- C2 (15pts): CI details (Serial numbers) correct
- C3 (20pts): 3 Contracts created
- C4 (15pts): Contract details correct
- C5 (15pts): Correct CI-Contract linkages
- C6 (15pts): Contamination (Boiler) NOT linked

Pass Threshold: 55/100
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_service_contract_equipment_linkage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    
    score = 0
    feedback_parts = []
    
    # Retrieve result
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/sce_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export failed: {e}"}

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    cis = result.get("cis", {})
    contracts = result.get("contracts", {})
    linkages = result.get("linkages", {})
    contam = result.get("contamination", {})

    # C1: Equipment Created (20 pts)
    # ------------------------------
    created_count = sum(1 for c in cis.values() if c["exists"])
    score_c1 = min(created_count, 3) * (20/3)
    score += score_c1
    feedback_parts.append(f"CIs Created: {created_count}/3")

    # C2: Equipment Details (15 pts)
    # ------------------------------
    # Check Serials
    expected_serials = {
        "EQ-CHILLER-010": "CR-8842-XA",
        "EQ-AHU-015": "TM-5521-MS",
        "EQ-ELEV-007": "OG-3317-G2"
    }
    details_correct = 0
    for code, expected_sn in expected_serials.items():
        if cis.get(code, {}).get("exists"):
            actual_sn = cis[code].get("serial", "")
            if expected_sn in actual_sn:
                details_correct += 1
    
    score_c2 = details_correct * 5
    score += score_c2
    if details_correct < 3:
        feedback_parts.append(f"CI Details Correct: {details_correct}/3")

    # C3: Contracts Created (20 pts)
    # ------------------------------
    contract_count = sum(1 for c in contracts.values() if c["exists"])
    score_c3 = min(contract_count, 3) * (20/3)
    score += score_c3
    feedback_parts.append(f"Contracts Created: {contract_count}/3")

    # C4: Contract Details (15 pts)
    # -----------------------------
    # Loose check on dates or description
    valid_details = 0
    for code, data in contracts.items():
        if data["exists"]:
            desc = data.get("description", "").lower()
            # Simple keyword check
            if "hvac" in code.lower() and "hvac" in desc: valid_details += 1
            elif "elev" in code.lower() and "elev" in desc: valid_details += 1
            elif "fire" in code.lower() and "fire" in desc: valid_details += 1
    
    score_c4 = valid_details * 5
    score += score_c4
    
    # C5: Linkages (15 pts)
    # ---------------------
    # HVAC -> Chiller AND AHU
    # Elev -> Elevator
    # Fire -> None
    links_score = 0
    
    hvac_links = linkages.get("SVC-2025-HVAC-001", [])
    if "EQ-CHILLER-010" in hvac_links and "EQ-AHU-015" in hvac_links:
        links_score += 7
    elif "EQ-CHILLER-010" in hvac_links or "EQ-AHU-015" in hvac_links:
        links_score += 3 # Partial

    elev_links = linkages.get("SVC-2025-ELEV-001", [])
    if "EQ-ELEV-007" in elev_links:
        links_score += 5

    fire_links = linkages.get("SVC-2025-FIRE-001", [])
    if len(fire_links) == 0:
        links_score += 3
        
    score += links_score
    feedback_parts.append(f"Linkage Score: {links_score}/15")

    # C6: Contamination (15 pts)
    # --------------------------
    if not contam.get("exists"):
        feedback_parts.append("Contamination CI deleted!")
        # 0 points for C6
    elif contam.get("linked_to_contract"):
        feedback_parts.append(f"Contamination linked to {contam.get('linked_to')}")
        # 0 points for C6
    else:
        score += 15
        feedback_parts.append("Contamination avoided")

    # Final tally
    score = min(100, round(score))
    
    # Cap score if contamination failed
    if contam.get("linked_to_contract") or not contam.get("exists"):
        score = min(score, 55)

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }