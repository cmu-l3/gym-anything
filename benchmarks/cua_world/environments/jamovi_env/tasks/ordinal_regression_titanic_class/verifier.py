#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import re
from gym_anything.vlm import get_final_screenshot, query_vlm

def verify_ordinal_regression_titanic_class(traj, env_info, task_info):
    """
    Verifies the Ordinal Logistic Regression task.
    
    Criteria:
    1. Files (.omv and .txt) created during task.
    2. OMV Analysis:
       - passengerClass is Ordinal.
       - Levels are ordered [3rd, 2nd, 1st] (CRITICAL).
       - Ordinal Regression analysis exists.
    3. Report Content:
       - Correct Odds Ratio (~1.04).
       - Correct Interpretation ("Increase").
    4. VLM:
       - Final screen shows Jamovi with results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Task Result JSON
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    try:
        copy_from_env("/tmp/task_result.json", temp_json)
        with open(temp_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_json): os.unlink(temp_json)

    # Check File Existence & Timestamp (Anti-gaming)
    omv_exists = result_data.get("omv_exists", False)
    omv_fresh = result_data.get("omv_created_during_task", False)
    report_exists = result_data.get("report_exists", False)
    
    if omv_exists and omv_fresh:
        score += 10
        feedback.append("Project file created.")
    else:
        feedback.append("Project file missing or not saved.")
        
    if report_exists:
        score += 10
        feedback.append("Report file created.")

    # ---------------------------------------------------------
    # 2. Analyze OMV File Structure
    # ---------------------------------------------------------
    if omv_exists:
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix=".zip").name
        try:
            copy_from_env("/home/ga/Documents/Jamovi/Titanic_Ordinal.omv", temp_omv)
            
            # Open OMV (it's a zip)
            with zipfile.ZipFile(temp_omv, 'r') as z:
                # Jamovi stores metadata in metadata.json or similar
                # We need to find variable definitions.
                # Usually in metadata.json under "dataSet" -> "fields"
                
                # List files to debug if needed
                files = z.namelist()
                
                metadata_content = None
                if "metadata.json" in files:
                    with z.open("metadata.json") as f:
                        metadata_content = json.load(f)
                
                # Check Variable Configuration (Levels Order)
                levels_correct = False
                var_found = False
                
                if metadata_content:
                    fields = metadata_content.get("dataSet", {}).get("fields", [])
                    for field in fields:
                        if field.get("name") == "passengerClass":
                            var_found = True
                            # Check type
                            if field.get("measureType") == "ordinal":
                                score += 10
                                feedback.append("Variable type set to Ordinal.")
                            else:
                                feedback.append(f"Variable type incorrect: {field.get('measureType')}")

                            # Check levels order
                            # Jamovi saves levels in the 'levels' list.
                            # We expect ["3rd", "2nd", "1st"]
                            # Default is often ["1st", "2nd", "3rd"] (Alpha)
                            levels = [l.get("label", l.get("value")) for l in field.get("levels", [])]
                            
                            # Clean levels (remove non-string artifacts if any)
                            clean_levels = [str(l) for l in levels]
                            
                            # We look for the subsequence of interest
                            if clean_levels == ["3rd", "2nd", "1st"]:
                                levels_correct = True
                                score += 30
                                feedback.append("Variable levels correctly reordered (Status: Low->High).")
                            elif clean_levels == ["1st", "2nd", "3rd"]:
                                feedback.append("Variable levels in WRONG order (1st is lowest). Results will be inverted.")
                            else:
                                feedback.append(f"Variable levels weird: {clean_levels}")
                            break
                    
                    if not var_found:
                        feedback.append("Variable 'passengerClass' not found in metadata.")
                
                # Check Analysis Existence
                # Analyses are usually in 01 title / analysis
                analysis_found = False
                for fname in files:
                    if fname.endswith("analysis"):
                        # It's a text/json file describing the analysis
                        try:
                            with z.open(fname) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                if "ordinal" in content.lower() or "polr" in content.lower():
                                    analysis_found = True
                        except:
                            pass
                
                if analysis_found:
                    score += 15
                    feedback.append("Ordinal Regression analysis found.")
                else:
                    feedback.append("No Ordinal Regression analysis detected in project.")

        except Exception as e:
            feedback.append(f"Error analyzing OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv): os.unlink(temp_omv)

    # ---------------------------------------------------------
    # 3. Verify Report Content
    # ---------------------------------------------------------
    if report_exists:
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt").name
        try:
            copy_from_env("/home/ga/Documents/Jamovi/ordinal_results.txt", temp_txt)
            with open(temp_txt, 'r') as f:
                content = f.read()
                lower_content = content.lower()
                
                # Check for Odds Ratio ~ 1.04
                # If levels were wrong (1st, 2nd, 3rd), OR would be ~0.95
                if "1.04" in content or "1.05" in content or "1.03" in content:
                    score += 15
                    feedback.append("Odds Ratio correct (~1.04).")
                elif "0.96" in content or "0.95" in content:
                    feedback.append("Odds Ratio indicates inverted variable order (~0.96).")
                else:
                    feedback.append("Correct Odds Ratio not found.")
                
                # Check Interpretation
                if "increase" in lower_content:
                    score += 10
                    feedback.append("Interpretation 'Increase' correct.")
                elif "decrease" in lower_content:
                    feedback.append("Interpretation 'Decrease' incorrect.")
        except Exception as e:
            feedback.append(f"Error reading report: {e}")
        finally:
            if os.path.exists(temp_txt): os.unlink(temp_txt)

    # ---------------------------------------------------------
    # 4. VLM Verification (Final Check)
    # ---------------------------------------------------------
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        response = query_vlm(
            prompt="Is this a screenshot of Jamovi statistical software showing a regression analysis results table? Look for 'Ordinal Logistic Regression' or 'Model Coefficients'. Answer yes/no and briefly explain.",
            image=final_screenshot
        )
        if response.get("success"):
            parsed = response.get("parsed", {})
            # Simple heuristic check on VLM output text if parsed isn't structured
            # Assuming standard gym_anything VLM returns text
            if "yes" in str(response).lower():
                vlm_score = 10
                feedback.append("VLM confirms Jamovi analysis visible.")
            else:
                feedback.append("VLM did not recognize Jamovi analysis.")
        else:
            feedback.append("VLM query failed.")
    
    score += vlm_score

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = (score >= 70)  # Threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }