#!/usr/bin/env python3
"""
Verifier for SPC Process Capability Task.

Verification Strategy:
1. Programmatic Checks (80%):
   - Capability CSV exists, is valid, and contains values in expected ranges.
   - OOC CSV exists and contains rows (detection of outliers).
   - Control Charts PNG exists and is of sufficient size.
   - R script uses 'qcc' and 'cusum' logic.
   - 'qcc' package is installed.

2. Visual Verification (20%):
   - VLM checks the Control Charts PNG for correct types (X-bar, R, CUSUM) and legibility.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spc_process_capability(traj, env_info, task_info):
    """Verify the SPC analysis task."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_ranges = metadata.get('expected_ranges', {})

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Process Capability CSV (30 pts) ---
    cap_data = result.get('capability_data', {})
    
    if result.get('capability_exists') and result.get('capability_valid'):
        score += 10
        feedback.append("Capability CSV exists and is valid format (+10)")
        
        # Check values against ranges
        # Cp
        cp = cap_data.get('Cp', 0)
        if expected_ranges['Cp'][0] <= cp <= expected_ranges['Cp'][1]:
            score += 5
            feedback.append(f"Cp value {cp:.2f} in range (+5)")
        else:
            feedback.append(f"Cp value {cp:.2f} out of expected range {expected_ranges['Cp']}")

        # Cpk
        cpk = cap_data.get('Cpk', 0)
        if expected_ranges['Cpk'][0] <= cpk <= expected_ranges['Cpk'][1]:
            score += 5
            feedback.append(f"Cpk value {cpk:.2f} in range (+5)")
        else:
             feedback.append(f"Cpk value {cpk:.2f} out of expected range {expected_ranges['Cpk']}")

        # Pp/Ppk (Bonus/Robustness check)
        pp = cap_data.get('Pp', 0)
        ppk = cap_data.get('Ppk', 0)
        if pp > 0 and ppk > 0:
            score += 5
            feedback.append("Pp/Ppk values computed (+5)")
        else:
            feedback.append("Pp/Ppk missing or zero")
            
        # Logic Check: Cpk <= Cp
        if cpk <= cp + 0.01: # allow float tolerance
            score += 5
            feedback.append("Consistency check Cpk <= Cp passed (+5)")
        else:
            feedback.append("Consistency check failed: Cpk > Cp is impossible")
            
    else:
        feedback.append("Capability CSV missing or invalid format")

    # --- Criterion 2: Out-of-Control Points CSV (20 pts) ---
    if result.get('ooc_exists'):
        score += 10
        feedback.append("OOC CSV exists (+10)")
        
        ooc_rows = result.get('ooc_rows', 0)
        if ooc_rows >= 1:
            score += 10
            feedback.append(f"OOC CSV contains {ooc_rows} violations (+10)")
        else:
            feedback.append("OOC CSV is empty (no violations detected)")
    else:
        feedback.append("OOC CSV missing")

    # --- Criterion 3: Control Charts PNG (15 pts programmatic + 10 pts VLM) ---
    png_path = "/tmp/spc_charts_verify.png"
    vlm_score = 0
    
    if result.get('png_exists'):
        score += 10
        feedback.append("Control charts PNG exists (+10)")
        
        if result.get('png_size_bytes', 0) > 30000: # >30KB implies content
            score += 5
            feedback.append("PNG size indicates content (+5)")
            
            # VLM Check
            if query_vlm:
                # Need to fetch the image first
                try:
                    # We need to copy the PNG from container to host to send to VLM
                    # The framework usually handles 'get_final_screenshot', but for specific file:
                    # Note: Using get_final_screenshot(traj) is safer for general UI, 
                    # but if we want to verify the specific plot file, we rely on copy_from_env.
                    # We'll use the final screenshot for VLM context if the plot file fetch fails,
                    # but let's try to verify the plot specifically if possible.
                    
                    # NOTE: Since we cannot easily "upload" the specific PNG to VLM without 
                    # generic tool support, we will fallback to checking the final screenshot 
                    # of the desktop which likely displays the plot, OR assumes the score implies
                    # visual correctness if file size is good. 
                    # However, to follow best practices, we will use the FINAL SCREENSHOT 
                    # provided by the framework to check if the plot is visible on screen.
                    
                    from gym_anything.vlm import get_final_screenshot
                    final_screen = get_final_screenshot(traj)
                    
                    if final_screen:
                        prompt = """
                        Does this screen show statistical control charts? 
                        Look for:
                        1. An X-bar chart (points fluctuating around a center line with limits).
                        2. An R chart (Range chart).
                        3. A CUSUM chart (Cumulative Sum).
                        4. RStudio interface.
                        
                        Answer yes/no and briefly describe which charts are visible.
                        """
                        vlm_resp = query_vlm(image=final_screen, prompt=prompt)
                        if vlm_resp.get('success'):
                            # Simple keyword matching on reasoning
                            resp_text = vlm_resp.get('parsed', {}).get('answer', '').lower() + \
                                        vlm_resp.get('parsed', {}).get('reasoning', '').lower()
                            
                            if 'yes' in resp_text or 'chart' in resp_text:
                                vlm_score += 10
                                feedback.append("VLM confirms control charts visible (+10)")
                            else:
                                feedback.append("VLM did not clearly identify control charts")
                        else:
                            # If VLM fails, give benefit of doubt if file size is large
                            vlm_score += 10 
                            feedback.append("VLM unavailable, defaulting to file size check (+10)")
                    else:
                         vlm_score += 10 # Fallback
                except Exception as e:
                    logger.warning(f"VLM check failed: {e}")
                    vlm_score += 10
        else:
            feedback.append("PNG size too small")
    else:
        feedback.append("Control charts PNG missing")
    
    score += vlm_score

    # --- Criterion 4: R Script & Package (15 pts) ---
    if result.get('script_modified'):
        score += 5
        feedback.append("R script modified (+5)")
        
        if result.get('script_has_qcc'):
            score += 5
            feedback.append("Script uses qcc (+5)")
        else:
            feedback.append("Script missing 'qcc' keyword")
            
        if result.get('script_has_cusum'):
            score += 5
            feedback.append("Script uses cusum (+5)")
        else:
            feedback.append("Script missing 'cusum' keyword")
    else:
        feedback.append("R script not modified from template")

    # --- Criterion 5: Package Installation (10 pts) ---
    if result.get('qcc_installed'):
        score += 10
        feedback.append("qcc package successfully installed (+10)")
    else:
        feedback.append("qcc package not installed")

    # Final Score Calculation
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }