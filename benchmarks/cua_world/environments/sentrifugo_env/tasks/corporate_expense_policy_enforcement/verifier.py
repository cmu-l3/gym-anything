#!/usr/bin/env python3
"""
Verifier for corporate_expense_policy_enforcement task.

Uses a HYBRID verification strategy:
1. Programmatic DB Check: Parses the exported database tables to see if 
   the exact category updates and claim adjudications occurred.
2. VLM Trajectory Check: Reviews the agent's screen history to verify 
   UI interaction, awarding points if the DB schema drifted but the agent 
   successfully performed the work in the application.

Total: 100 points. Pass threshold: 70.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_expense_policy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Copy the exported result files from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_cat_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_claim_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    result = {}
    cat_dump = ""
    claim_dump = ""
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        copy_from_env("/tmp/expense_categories_dump.txt", temp_cat_dump.name)
        with open(temp_cat_dump.name, 'r') as f:
            cat_dump = f.read().lower()
            
        copy_from_env("/tmp/expense_claims_dump.txt", temp_claim_dump.name)
        with open(temp_claim_dump.name, 'r') as f:
            claim_dump = f.read().lower()
    except Exception as e:
        logger.warning(f"Failed to read DB dumps: {e}")
    finally:
        for tmp_file in [temp_json.name, temp_cat_dump.name, temp_claim_dump.name]:
            if os.path.exists(tmp_file):
                os.unlink(tmp_file)

    score = 0
    feedback = []

    # =======================================================
    # PROGRAMMATIC DATABASE CHECKS
    # =======================================================
    db_telecom_deactivated = False
    db_client_updated = False
    db_claims_adjudicated = False
    
    # Check Telecom deactivated (look for telecom and a 0/inactive flag)
    if "telecom" in cat_dump:
        # Standard format is often tab separated: id \t name \t desc \t isactive
        for line in cat_dump.split('\n'):
            if "telecom" in line and ("\t0" in line or " 0 " in line or line.endswith("0")):
                db_telecom_deactivated = True
                break

    # Check Client Entertainment updated to 100
    if "client entertainment" in cat_dump and "100" in cat_dump:
        db_client_updated = True

    # Check claims adjudication (85=Approved, 120=Rejected, 45=Rejected)
    if "85" in claim_dump and ("approv" in claim_dump or "accept" in claim_dump):
        if "120" in claim_dump and "reject" in claim_dump:
            if "45" in claim_dump and "reject" in claim_dump:
                db_claims_adjudicated = True

    # =======================================================
    # VLM TRAJECTORY VERIFICATION (Hybrid Fallback/Anti-Gaming)
    # =======================================================
    vlm_telecom_deactivated = False
    vlm_client_updated = False
    vlm_claims_adjudicated = False
    
    # We only use VLM if we are missing DB evidence (schema mismatch fallback) 
    # OR to verify the agent actually did the work via UI
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=6)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            Review these trajectory screenshots of an HRMS application (Sentrifugo).
            The agent was tasked to:
            1. Deactivate the 'Telecom & Internet' expense category.
            2. Update the 'Client Entertainment' category limit to $100.
            3. Adjudicate pending expense claims: Approve an $85 claim, and Reject $120 and $45 claims.
            
            Based ONLY on visual evidence in the UI workflow, did the agent perform these actions?
            Provide a JSON response:
            {
              "telecom_deactivated_in_ui": true/false,
              "client_entertainment_updated_in_ui": true/false,
              "claims_properly_adjudicated": true/false
            }
            """
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                vlm_telecom_deactivated = parsed.get("telecom_deactivated_in_ui", False)
                vlm_client_updated = parsed.get("client_entertainment_updated_in_ui", False)
                vlm_claims_adjudicated = parsed.get("claims_properly_adjudicated", False)
    except Exception as e:
        logger.error(f"VLM Verification failed: {e}")

    # =======================================================
    # SCORING (Take best of DB or VLM to prevent schema-related false negatives)
    # =======================================================
    
    # 1. Telecom Deactivated (30 pts)
    if db_telecom_deactivated:
        score += 30
        feedback.append("DB Verified: Telecom category deactivated (+30)")
    elif vlm_telecom_deactivated:
        score += 30
        feedback.append("VLM Verified: Telecom category deactivated in UI (+30)")
    else:
        feedback.append("Failed: Telecom category not deactivated")

    # 2. Client Entertainment Updated (30 pts)
    if db_client_updated:
        score += 30
        feedback.append("DB Verified: Client Entertainment limit updated (+30)")
    elif vlm_client_updated:
        score += 30
        feedback.append("VLM Verified: Client Entertainment limit updated in UI (+30)")
    else:
        feedback.append("Failed: Client Entertainment limit not updated")

    # 3. Claims Adjudicated Correctly (40 pts)
    if db_claims_adjudicated:
        score += 40
        feedback.append("DB Verified: All claims correctly approved/rejected (+40)")
    elif vlm_claims_adjudicated:
        score += 40
        feedback.append("VLM Verified: Claims accurately adjudicated in UI (+40)")
    else:
        feedback.append("Failed: Claims not fully/correctly adjudicated")

    # Pass condition
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "db_evidence": {
                "telecom_deactivated": db_telecom_deactivated,
                "client_updated": db_client_updated,
                "claims_adjudicated": db_claims_adjudicated
            },
            "vlm_evidence": {
                "telecom_deactivated": vlm_telecom_deactivated,
                "client_updated": vlm_client_updated,
                "claims_adjudicated": vlm_claims_adjudicated
            }
        }
    }