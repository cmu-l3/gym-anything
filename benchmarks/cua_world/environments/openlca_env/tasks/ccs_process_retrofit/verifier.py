#!/usr/bin/env python3
"""
Verifier for CCS Process Retrofit task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# VLM Prompts
TRAJECTORY_PROMPT = """You are analyzing an agent modifying a Life Cycle Assessment process in openLCA.
Goal: Create a CCS (Carbon Capture) variant of a natural gas power plant process.
Workflow stages:
1. Import/Open database.
2. Search/Locate "Natural gas electricity" process.
3. Copy and Paste/Duplicate the process.
4. Rename new process to include "CCS" or "Carbon Capture".
5. Open process inputs/outputs (Exchanges).
6. Edit "Carbon dioxide" output flow amount (reduce it).
7. Save.

Assess:
- Did the agent copy/duplicate a process?
- Did they rename a process to "CCS" something?
- Did they edit the exchanges (numbers)?
- Did they create a report file?

Return JSON:
{
  "process_copied": true/false,
  "renamed_ccs": true/false,
  "exchanges_edited": true/false,
  "report_created": true/false,
  "confidence": "low/medium/high"
}"""

FINAL_STATE_PROMPT = """Analyze the final screenshot of openLCA.
Look for:
- A text file or report open showing comparison data.
- Or the openLCA interface showing a process named "CCS" or "Carbon Capture".
- Or the Exchanges tab of a process showing Carbon Dioxide values.

Return JSON:
{
  "ccs_process_visible": true/false,
  "report_visible": true/false,
  "observations": "string"
}"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_ccs_process_retrofit(traj, env_info, task_info):
    """
    Verify the CCS retrofit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database and Basic Setup (20 pts)
    if result.get('db_found'):
        score += 10
        feedback.append("Database found.")
    else:
        feedback.append("No database found.")

    if result.get('process_count', 0) > 10:
        score += 10
        feedback.append("Database populated.")
    
    # 2. CCS Process Existence (30 pts)
    if result.get('ccs_process_found'):
        score += 30
        feedback.append(f"CCS Process found (ID: {result.get('ccs_process_id')}).")
    else:
        feedback.append("CCS Process NOT found in database.")

    # 3. CO2 Reduction Verification (30 pts)
    ccs_co2 = result.get('ccs_co2_amount')
    orig_co2 = result.get('original_co2_amount')
    
    reduction_verified = False
    if ccs_co2:
        try:
            ccs_val = float(ccs_co2)
            # If we found an original value, compare
            if orig_co2:
                orig_val = float(orig_co2)
                ratio = ccs_val / orig_val if orig_val > 0 else 1.0
                if 0.05 <= ratio <= 0.20:
                    score += 30
                    reduction_verified = True
                    feedback.append(f"CO2 reduction verified: {ccs_val} is ~{ratio*100:.1f}% of {orig_val}.")
                elif ratio < 0.5:
                    score += 20 # Partial credit
                    feedback.append(f"CO2 reduced but not ~90% (ratio: {ratio:.2f}).")
                else:
                    feedback.append(f"CO2 not significantly reduced (ratio: {ratio:.2f}).")
            else:
                # Fallback: USLCI Nat Gas CO2 is typically ~0.4 - 0.6 kg. 
                # 90% capture => ~0.04 - 0.06.
                if ccs_val < 0.1:
                    score += 30
                    reduction_verified = True
                    feedback.append(f"CO2 value {ccs_val} looks correct (low enough for CCS).")
                else:
                    score += 10
                    feedback.append(f"CO2 value {ccs_val} found, but comparison baseline missing.")
        except ValueError:
            feedback.append("Invalid CO2 value data.")
    else:
        feedback.append("Could not verify CO2 flow values in database.")

    # 4. Report File (10 pts)
    if result.get('report_exists'):
        score += 10
        feedback.append("Report file created.")
        content = result.get('report_content_preview', '').lower()
        if 'ccs' in content and 'co2' in content:
            score += 5 # Bonus for content
            feedback.append("Report content looks relevant.")
    else:
        feedback.append("Report file missing.")

    # 5. VLM Verification (5 pts)
    # Only if we are missing points, use VLM to top up
    if score < 100:
        # Placeholder for VLM logic if needed
        pass

    passed = score >= 60 and result.get('ccs_process_found')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }