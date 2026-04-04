#!/usr/bin/env python3
"""
Verifier for One-Sample T-Test in Jamovi.
Checks the saved .omv file for correct analysis configuration and VLM for visual confirmation.
"""

import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_one_sample_ttest_toothgrowth(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error: copy_from_env missing"}

    # 1. Load basic result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    score = 0
    feedback_lines = []
    
    # Check 1: File Existence & Creation (20 pts)
    if task_result.get("file_exists") and task_result.get("file_created_during_task"):
        score += 20
        feedback_lines.append("✓ Output .omv file created successfully.")
    elif task_result.get("file_exists"):
        score += 10
        feedback_lines.append("⚠ Output file exists but timestamp is old (re-used?).")
    else:
        feedback_lines.append("✗ Output .omv file not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_lines)}

    # Check 2: OMV File Content Verification (50 pts)
    # The .omv file is a zip. We need to extract the analysis definition.
    # Usually located in index.json or similar manifest inside the zip.
    omv_verified = False
    omv_details = []
    
    with tempfile.NamedTemporaryFile(suffix=".omv") as omv_tmp:
        try:
            copy_from_env(task_result["file_path"], omv_tmp.name)
            
            if not zipfile.is_zipfile(omv_tmp.name):
                feedback_lines.append("✗ Output file is not a valid Jamovi (.omv) archive.")
            else:
                with zipfile.ZipFile(omv_tmp.name, 'r') as z:
                    # Jamovi OMV structure usually has an 'index.json' or 'meta' folder
                    # We look for the analysis options in index.json (manifest) or individual analysis files
                    file_list = z.namelist()
                    
                    # Try to find index.json
                    if "index.json" in file_list:
                        with z.open("index.json") as meta_f:
                            meta_data = json.load(meta_f)
                            # Parse analyses
                            analyses = meta_data.get("analyses", [])
                            target_analysis = None
                            
                            for analysis in analyses:
                                # Look for One Sample T-Test
                                # The type identifier for One Sample T-Test in Jamovi is usually 'ttestOneS'
                                if "ttestOneS" in analysis.get("name", "") or "One Sample T-Test" in analysis.get("title", ""):
                                    target_analysis = analysis
                                    break
                            
                            if target_analysis:
                                score += 10 # Found the right analysis type
                                feedback_lines.append("✓ One Sample T-Test analysis found in file.")
                                
                                options = target_analysis.get("options", {})
                                
                                # Verify Parameters
                                
                                # 1. Variable (len)
                                vars_ = options.get("vars", [])
                                if "len" in vars_:
                                    score += 5
                                    feedback_lines.append("✓ Correct variable 'len' selected.")
                                else:
                                    feedback_lines.append(f"✗ Incorrect variable. Expected 'len', found {vars_}")

                                # 2. Test Value (20)
                                if str(options.get("testValue", "")) == "20" or options.get("testValue") == 20:
                                    score += 5
                                    feedback_lines.append("✓ Test value set to 20.")
                                else:
                                    feedback_lines.append(f"✗ Incorrect test value. Found {options.get('testValue')}")

                                # 3. Student + Wilcoxon
                                if options.get("student", False):
                                    score += 5
                                    feedback_lines.append("✓ Student's t enabled.")
                                else:
                                    feedback_lines.append("✗ Student's t NOT enabled.")
                                
                                if options.get("wilcoxon", False):
                                    score += 5
                                    feedback_lines.append("✓ Wilcoxon rank enabled.")
                                else:
                                    feedback_lines.append("✗ Wilcoxon rank NOT enabled.")

                                # 4. Additional Stats (Mean Diff, Effect Size, CI, Desc)
                                if options.get("meanDiff", False):
                                    score += 2.5
                                if options.get("effectSize", False):
                                    score += 2.5
                                if options.get("ci", False):
                                    score += 2.5
                                if options.get("desc", False):
                                    score += 2.5
                                feedback_lines.append("✓ Statistics options checked.")

                                # 5. Assumptions (Norm, QQ)
                                if options.get("norm", False): # Shapiro-Wilk
                                    score += 5
                                    feedback_lines.append("✓ Shapiro-Wilk enabled.")
                                if options.get("qq", False):
                                    score += 5
                                    feedback_lines.append("✓ Q-Q Plot enabled.")
                                
                                omv_verified = True
                            else:
                                feedback_lines.append("✗ No One Sample T-Test analysis found in OMV file.")
                    else:
                        feedback_lines.append("✗ Could not parse OMV structure (index.json missing).")

        except Exception as e:
            feedback_lines.append(f"✗ Error analyzing OMV file: {str(e)}")

    # Check 3: VLM Verification (30 pts)
    # We use trajectory to confirm the user actually interacted with the UI
    # and to catch cases where the OMV might be valid but process was weird (or backup if OMV parse fails)
    
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    # Add final frame to analysis if unique
    if final_frame:
        frames.append(final_frame)

    if not frames:
         feedback_lines.append("⚠ No screenshots available for VLM verification.")
    else:
        vlm_prompt = """
        You are verifying a Jamovi statistics task. 
        Goal: Check if the user performed a One Sample T-Test on the 'len' variable with Test Value = 20.
        
        Look for these specific elements in the screenshots:
        1. A 'One Sample T-Test' configuration panel.
        2. The variable 'len' in the Dependent Variables box.
        3. A 'Test value' field showing '20'.
        4. Results table showing 'Student's t' AND 'Wilcoxon W'.
        5. 'Assumption Checks' like Shapiro-Wilk or Q-Q Plot visible.
        
        Answer JSON:
        {
            "analysis_panel_visible": true/false,
            "correct_variable_visible": true/false,
            "test_value_20_visible": true/false,
            "results_table_visible": true/false,
            "wilcoxon_visible": true/false,
            "plots_visible": true/false
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            if parsed.get("analysis_panel_visible"): vlm_score += 5
            if parsed.get("results_table_visible"): vlm_score += 5
            if parsed.get("wilcoxon_visible"): vlm_score += 5
            if parsed.get("test_value_20_visible"): vlm_score += 10
            if parsed.get("plots_visible"): vlm_score += 5
            
            # Cap VLM score at 30
            score += min(vlm_score, 30)
            feedback_lines.append(f"✓ Visual verification score: {min(vlm_score, 30)}/30")
        else:
            feedback_lines.append("⚠ VLM verification failed or inconclusive.")

    # Final Pass Decision
    # Need at least 70 points AND the file must exist
    passed = (score >= 70) and task_result.get("file_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }