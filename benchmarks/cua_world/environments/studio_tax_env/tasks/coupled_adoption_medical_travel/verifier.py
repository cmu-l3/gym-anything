#!/usr/bin/env python3
"""
Verifier for coupled_adoption_medical_travel task.

Evaluates a linked spousal return in StudioTax 2024 for Chloe and Marc Gagnon.
Validates the presence of correct T4 income amounts, adoption limits, calculated 
medical travel expenses, and child care allocation. Uses VLM to confirm workflow.
"""

import json
import os
import tempfile
import logging

def verify_coupled_adoption_medical_travel(traj, env_info, task_info):
    score = 0
    feedback = []
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: No copy_from_env helper"}

    # 1. Retrieve programmatic results from Windows environment
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        copy_from_env("C:/Users/Docker/Desktop/gagnon_result.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read programmatic result: {e}"}

    # 2. Programmatic Scoring
    file_ok = result.get('file_exists', False) and result.get('file_size_bytes', 0) > 1000
    if file_ok:
        score += 5
        feedback.append("File 'gagnon_family.24t' saved with valid size.")
    else:
        feedback.append("FAIL: Return file not found or suspiciously small.")

    if result.get('file_is_new', False):
        score += 5
        feedback.append("File created/modified during task (Valid timestamp).")
    else:
        feedback.append("FAIL: File timestamp predates task.")

    # Taxpayer Names
    names_ok = result.get('contains_chloe') and result.get('contains_marc') and result.get('contains_gagnon')
    if names_ok:
        score += 10
        feedback.append("Chloe and Marc Gagnon found (Linked Spousal).")
    elif result.get('contains_chloe') or result.get('contains_marc'):
        score += 5
        feedback.append("Only one taxpayer name found.")

    if result.get('contains_leo'):
        score += 5
        feedback.append("Dependent Leo Gagnon found.")

    # Incomes
    t4_chloe_ok = result.get('contains_85000', False)
    t4_marc_ok = result.get('contains_62000', False)
    if t4_chloe_ok:
        score += 10
        feedback.append("Chloe's T4 ($85,000) found.")
    if t4_marc_ok:
        score += 10
        feedback.append("Marc's T4 ($62,000) found.")

    # Deductions
    if result.get('contains_adoption', False):
        score += 10
        feedback.append("Adoption expenses ($18,210 limit / $19,500) found.")
    
    if result.get('contains_14672', False):
        score += 10
        feedback.append("Total Medical + Travel expenses ($14,672) calculated & found.")
        
    if result.get('contains_3200', False):
        score += 5
        feedback.append("Child care expenses ($3,200) found.")

    # 3. VLM Trajectory Verification (30 points)
    # Checking for visual evidence that the agent actually interacted with a coupled return.
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        all_images = frames + [final_screen] if final_screen else frames
        
        if all_images:
            prompt = """
            You are verifying a computer agent's workflow completing a Canadian tax return in StudioTax.
            Task: Complete a 'linked' (spousal) tax return, entering medical expenses and adoption expenses.
            
            Look at these trajectory screenshots and respond in JSON format with these boolean fields:
            - "used_linked_return": True if the UI shows tabs/evidence of multiple taxpayers (e.g., 'Taxpayer' and 'Spouse' tabs or Chloe/Marc simultaneously).
            - "navigated_medical_or_adoption": True if any screenshot shows the Medical Expenses schedule, Adoption Expenses form, or Child Care form.
            - "entered_data": True if the agent is visibly typing or interacting with forms, rather than just staring at the home screen.
            """
            
            vlm_response = query_vlm(images=all_images, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("used_linked_return"):
                    vlm_score += 15
                    feedback.append("VLM confirmed usage of linked spousal return.")
                if parsed.get("navigated_medical_or_adoption"):
                    vlm_score += 10
                    feedback.append("VLM confirmed navigation to specialized medical/adoption forms.")
                if parsed.get("entered_data"):
                    vlm_score += 5
            else:
                feedback.append("VLM query failed or returned no valid data.")

    score += vlm_score

    # 4. Critical Score Caps
    # If core T4 incomes are missing, the agent likely just typed random deduction numbers.
    if not (t4_chloe_ok and t4_marc_ok) and score > 40:
        score = 40
        feedback.append("SCORE CAPPED AT 40: Both core T4 employment incomes must be present to pass.")

    passed = score >= 70 and (t4_chloe_ok and t4_marc_ok)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }