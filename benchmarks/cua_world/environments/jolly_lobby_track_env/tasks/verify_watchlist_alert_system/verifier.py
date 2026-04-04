#!/usr/bin/env python3
"""
Verifier for verify_watchlist_alert_system task.

This verifier checks:
1. Did the agent create the watchlist entry? (Database string check)
2. Did the agent capture the alert screenshot? (File existence + Timestamp)
3. Does the screenshot actually show a security alert? (VLM)
4. Did the agent abort the check-in? (VLM on final state/trajectory)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_watchlist_alert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    feedback = []
    
    # ------------------------------------------------------------------
    # Criteria 1: Watchlist Entry (30 pts)
    # ------------------------------------------------------------------
    if result.get("name_found_in_db"):
        score += 30
        feedback.append("✅ 'Audit RedTeam' found in database.")
    else:
        feedback.append("❌ 'Audit RedTeam' NOT found in database. Did you add them to the list?")

    # ------------------------------------------------------------------
    # Criteria 2: Proof Screenshot Existence (20 pts)
    # ------------------------------------------------------------------
    proof_exists = result.get("proof_screenshot_exists")
    proof_fresh = result.get("proof_created_during_task")
    
    proof_image_path = None
    
    if proof_exists and proof_fresh:
        score += 20
        feedback.append("✅ Proof screenshot created.")
        
        # Retrieve the screenshot for VLM analysis
        proof_remote_path = result.get("proof_path")
        if proof_remote_path:
            local_proof_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            local_proof_path = local_proof_tmp.name
            local_proof_tmp.close()
            try:
                copy_from_env(proof_remote_path, local_proof_path)
                proof_image_path = local_proof_path
            except Exception as e:
                logger.error(f"Failed to copy proof screenshot: {e}")
                feedback.append("⚠️ Could not retrieve proof screenshot for content verification.")
    elif proof_exists:
        feedback.append("❌ Proof screenshot is stale (existed before task).")
    else:
        feedback.append("❌ Proof screenshot not found at expected path.")

    # ------------------------------------------------------------------
    # Criteria 3: VLM Content Verification (Alert) (30 pts)
    # ------------------------------------------------------------------
    vlm_alert_confirmed = False
    if proof_image_path:
        prompt = (
            "Analyze this screenshot from visitor management software. "
            "1. Is there a popup dialog visible? "
            "2. Does it contain text like 'Watchlist', 'Denied', 'Alert', 'Match Found', or 'Security'? "
            "3. Is the name 'Audit RedTeam' visible on screen? "
            "Return JSON: { 'is_alert': bool, 'keywords_found': bool, 'name_visible': bool }"
        )
        try:
            vlm_resp = query_vlm(image=proof_image_path, prompt=prompt)
            if vlm_resp.get("success"):
                analysis = vlm_resp.get("parsed", {})
                if analysis.get("is_alert") and analysis.get("keywords_found"):
                    score += 30
                    vlm_alert_confirmed = True
                    feedback.append("✅ Screenshot confirms security alert dialog.")
                else:
                    feedback.append("❌ Screenshot does not appear to show a valid security alert.")
            else:
                feedback.append("⚠️ VLM analysis failed.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
        finally:
            if os.path.exists(proof_image_path):
                os.unlink(proof_image_path)
    else:
        feedback.append("Skipping content verification (no image).")

    # ------------------------------------------------------------------
    # Criteria 4: Check-in Aborted (20 pts)
    # ------------------------------------------------------------------
    # We check the final screenshot to ensure we aren't at a "Badge Print" or "Success" screen.
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = (
            "Analyze the final state of the application. "
            "Does it look like the visitor was successfully checked in (e.g., Badge printing, Success message)? "
            "Or does it look like the check-in was cancelled/aborted (e.g., back to list, main menu, or cleared form)? "
            "Return JSON: { 'check_in_successful': bool, 'check_in_aborted': bool }"
        )
        try:
            vlm_resp = query_vlm(image=final_screenshot, prompt=prompt)
            if vlm_resp.get("success"):
                analysis = vlm_resp.get("parsed", {})
                if analysis.get("check_in_aborted") and not analysis.get("check_in_successful"):
                    score += 20
                    feedback.append("✅ Check-in appears correctly aborted.")
                elif analysis.get("check_in_successful"):
                    feedback.append("❌ Final screen indicates visitor was checked in (Should have been Denied).")
                else:
                    # Ambiguous state, give partial credit if alert was confirmed (assuming they stopped there)
                    if vlm_alert_confirmed:
                        score += 10
                        feedback.append("⚠️ Final state ambiguous, but alert was found.")
        except Exception as e:
            logger.error(f"VLM error: {e}")

    # ------------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------------
    passed = score >= 80  # Requires entry + screenshot + alert verification + clean finish
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }