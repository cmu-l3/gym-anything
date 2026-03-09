#!/usr/bin/env python3
import json
import os
import logging
import datetime
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_create_third_party_risk(traj, env_info, task_info):
    """
    Verifies the create_third_party_risk task.
    
    Scoring Criteria:
    1. Record Exists (20 pts): A third_party_risks record with the correct title exists.
    2. Description Content (15 pts): Contains 'TechCloud Solutions' AND 'HIPAA'.
    3. Threats Populated (10 pts): Non-empty and contains keywords.
    4. Vulnerabilities Populated (10 pts): Non-empty and contains keywords.
    5. Mitigation Strategy (15 pts): ID equals 3 (Mitigate).
    6. Review Date (10 pts): Equals '2025-07-15'.
    7. Anti-Gaming (10 pts): Record created after task start AND count increased.
    8. VLM Verification (10 pts): Visual confirmation of workflow.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load task metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get("expected_title", "Cloud Provider Data Breach - TechCloud Solutions")
    desc_keywords = metadata.get("description_keywords", ["TechCloud Solutions", "HIPAA"])
    mitigation_id_expected = str(metadata.get("expected_mitigation_id", 3))
    review_date_expected = metadata.get("expected_review_date", "2025-07-15")

    # Retrieve result file from environment
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # Initialize scoring
    score = 0
    feedback = []
    
    record_found = result_data.get("record_found", False)
    record_data = result_data.get("record_data", {})
    
    # --- Criterion 1: Record Existence (20 pts) ---
    if record_found and record_data.get("title") == expected_title:
        score += 20
        feedback.append("Success: Third Party Risk record found with correct title.")
    else:
        feedback.append("Failure: No active Third Party Risk record found with the exact required title.")
        # If record is missing, major fail, but continue to check other signals if possible (unlikely if record missing)
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # --- Criterion 2: Description Content (15 pts) ---
    description = record_data.get("description", "")
    if all(keyword.lower() in description.lower() for keyword in desc_keywords):
        score += 15
        feedback.append("Success: Description contains required keywords.")
    else:
        feedback.append(f"Partial: Description missing one or more keywords: {desc_keywords}")
        # Partial credit if at least non-empty
        if len(description) > 10:
            score += 5

    # --- Criterion 3: Threats Populated (10 pts) ---
    threats = record_data.get("threats", "")
    if len(threats) > 5 and ("unauthorized" in threats.lower() or "exfiltration" in threats.lower()):
        score += 10
        feedback.append("Success: Threats field populated correctly.")
    elif len(threats) > 5:
        score += 5
        feedback.append("Partial: Threats field populated but missing specific keywords.")
    else:
        feedback.append("Failure: Threats field empty or too short.")

    # --- Criterion 4: Vulnerabilities Populated (10 pts) ---
    vulns = record_data.get("vulnerabilities", "")
    if len(vulns) > 5 and ("shared" in vulns.lower() or "segmentation" in vulns.lower()):
        score += 10
        feedback.append("Success: Vulnerabilities field populated correctly.")
    elif len(vulns) > 5:
        score += 5
        feedback.append("Partial: Vulnerabilities field populated but missing keywords.")
    else:
        feedback.append("Failure: Vulnerabilities field empty or too short.")

    # --- Criterion 5: Mitigation Strategy (15 pts) ---
    # Database returns string, ensure comparison works
    actual_mitigation = str(record_data.get("mitigation_id", ""))
    if actual_mitigation == mitigation_id_expected:
        score += 15
        feedback.append("Success: Risk Mitigation Strategy set to 'Mitigate'.")
    else:
        feedback.append(f"Failure: Incorrect Mitigation Strategy ID. Expected {mitigation_id_expected}, got '{actual_mitigation}'.")

    # --- Criterion 6: Review Date (10 pts) ---
    # Expected format YYYY-MM-DD. Database returns YYYY-MM-DD HH:MM:SS or similar usually, need to check.
    # MySQL 'review' column usually date or datetime. The export script treats it as string.
    actual_review = record_data.get("review_date", "").split(" ")[0] # Take just the date part
    if actual_review == review_date_expected:
        score += 10
        feedback.append(f"Success: Review date is {review_date_expected}.")
    else:
        feedback.append(f"Failure: Incorrect Review Date. Expected {review_date_expected}, got '{actual_review}'.")

    # --- Criterion 7: Anti-Gaming (10 pts) ---
    # Check 1: Created timestamp > Task Start
    task_start = result_data.get("task_start_ts", 0)
    created_str = record_data.get("created", "")
    
    # Parse created string to timestamp
    is_created_during_task = False
    try:
        # Eramba/MySQL format usually "YYYY-MM-DD HH:MM:SS"
        if created_str:
            created_dt = datetime.datetime.strptime(created_str, "%Y-%m-%d %H:%M:%S")
            # Assume container time is roughly synced or check relative
            # If created_dt timestamp is greater than task_start - buffer (allow small clock skew)
            if created_dt.timestamp() > (task_start - 10):
                is_created_during_task = True
    except ValueError:
        # Fallback if parsing fails, rely on count check primarily
        pass

    # Check 2: Count increased
    initial_count = result_data.get("initial_count", 0)
    final_count = result_data.get("final_count", 0)
    count_increased = final_count > initial_count

    if is_created_during_task and count_increased:
        score += 10
        feedback.append("Success: Record verified as created during task session.")
    elif count_increased:
        score += 5
        feedback.append("Warning: Count increased but timestamp check inconclusive.")
    else:
        feedback.append("Failure: Database record count did not increase.")

    # --- Criterion 8: VLM Verification (10 pts) ---
    # We verify the visual state using the final screenshot
    from gym_anything.vlm import get_final_screenshot, query_vlm
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        prompt = (
            "Analyze this screenshot of the Eramba GRC application. "
            "1. Does it show a list of 'Third Party Risks' or a form with 'Risk Details'? "
            "2. Can you see the text 'TechCloud' or 'Cloud Provider' anywhere? "
            "3. Is there a success message visible (e.g., 'The item has been saved')? "
            "Return JSON: {\"is_third_party_risk_page\": bool, \"content_visible\": bool, \"success_visible\": bool}"
        )
        try:
            vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_third_party_risk_page") or parsed.get("content_visible"):
                    vlm_score = 10
                    feedback.append("Success: Visual verification confirmed Eramba usage.")
                else:
                    feedback.append("Warning: Visual verification could not confirm context.")
            else:
                feedback.append("Warning: VLM query failed.")
        except Exception as e:
            feedback.append(f"Warning: VLM error {str(e)}")
    
    score += vlm_score

    # Final Pass/Fail Determination
    # Threshold: 60 points mandatory
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }