#!/usr/bin/env python3
import json
import os
import re
import tempfile
import zipfile
import shutil

def verify_correlation_matrix_exam_anxiety(traj, env_info, task_info):
    """
    Verifies that the agent performed a Pearson correlation analysis in Jamovi.
    
    Checks:
    1. .omv file creation (Jamovi project file)
    2. .omv internal structure (contains correlation analysis definition)
    3. Text report content (contains correct r and p values)
    4. Anti-gaming (files created during task)
    """
    
    # 1. Setup and Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_corrs = metadata.get('expected_correlations', {})

    score = 0
    max_score = 100
    feedback = []
    
    # Load basic result info
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check OMV File (30 points)
    omv_passed = False
    if task_result.get('omv_exists') and task_result.get('omv_created_during_task'):
        score += 10
        feedback.append("Jamovi file (.omv) created.")
        
        # Analyze OMV content
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(task_result['omv_path'], temp_omv.name)
            
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    # Check for analysis definition
                    # Jamovi stores analyses in the 'analysis' folder usually
                    # We look for index.html or analysis definitions
                    file_list = z.namelist()
                    if 'index.html' in file_list or any(f.startswith('analysis') for f in file_list):
                        score += 10
                        feedback.append("OMV file is a valid Jamovi archive.")
                        omv_passed = True
                    else:
                        feedback.append("OMV file structure invalid.")
                        
                    # Advanced: Try to find "corrMatrix" in the metadata/analysis json if possible
                    # This is a heuristic check
                    found_correlation = False
                    for filename in file_list:
                        if filename.endswith('.json') or filename.endswith('.js'):
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                if 'corrMatrix' in content or 'Correlation Matrix' in content:
                                    found_correlation = True
                                    break
                            except:
                                continue
                    
                    if found_correlation:
                        score += 10
                        feedback.append("Confirmed correlation analysis inside OMV file.")
                    else:
                        feedback.append("Could not explicitly confirm correlation analysis in OMV metadata (might still be valid).")
                        # We give partial credit here if the zip was valid
                        score += 5
            else:
                feedback.append("OMV file is not a valid zip archive.")
        except Exception as e:
            feedback.append(f"Error analyzing OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    else:
        feedback.append("Jamovi file (.omv) not found or not created during task.")

    # 3. Check Text Report (70 points)
    report_passed = False
    if task_result.get('report_exists') and task_result.get('report_created_during_task'):
        score += 5
        feedback.append("Report file created.")
        
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(task_result['report_path'], temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read()
            
            # Normalize content for search
            content_lower = report_content.lower()
            
            # Extract numbers for verification
            # We look for numbers close to expected values
            # Exam-Anxiety: ~ -0.44
            # Exam-Revise: ~ 0.40
            # Revise-Anxiety: ~ -0.71
            
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", report_content)
            floats = []
            for n in numbers:
                try:
                    floats.append(float(n))
                except:
                    pass
            
            # Check for values in range
            ea_found = False
            er_found = False
            ra_found = False
            
            ea_target = expected_corrs.get('exam_anxiety', {})
            er_target = expected_corrs.get('exam_revise', {})
            ra_target = expected_corrs.get('revise_anxiety', {})
            
            for val in floats:
                if ea_target.get('r_min') <= val <= ea_target.get('r_max'):
                    ea_found = True
                if er_target.get('r_min') <= val <= er_target.get('r_max'):
                    er_found = True
                if ra_target.get('r_min') <= val <= ra_target.get('r_max'):
                    ra_found = True
            
            # Scoring logic for values
            val_score = 0
            if ea_found: 
                val_score += 15
                feedback.append("Found correct Exam-Anxiety correlation.")
            else:
                feedback.append("Missing or incorrect Exam-Anxiety correlation (expected ~ -0.44).")
                
            if er_found: 
                val_score += 15
                feedback.append("Found correct Exam-Revise correlation.")
            else:
                feedback.append("Missing or incorrect Exam-Revise correlation (expected ~ 0.40).")
                
            if ra_found: 
                val_score += 15
                feedback.append("Found correct Revise-Anxiety correlation.")
            else:
                feedback.append("Missing or incorrect Revise-Anxiety correlation (expected ~ -0.71).")
            
            score += val_score
            
            # Check for significance/p-value mentions
            # "significant", "p <", "0.001", "0.05", "yes"
            sig_terms = ["significant", "p <", "0.001", "< .001", "p-value", "yes"]
            if any(term in content_lower for term in sig_terms):
                score += 10
                feedback.append("Report mentions significance/p-values.")
            else:
                feedback.append("Report missing significance details.")
            
            # Check for N (sample size) mention if requested? 
            # Description asked to enable N in Jamovi, not explicitly to write it in report, 
            # but checking for it in OMV is hard. We'll skip strict N checking in text.

            if val_score >= 30: # At least 2 correlations correct
                report_passed = True

        except Exception as e:
            feedback.append(f"Error reading report file: {str(e)}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Report file not found or not created during task.")

    # 4. Final Success Determination
    passed = (score >= 60) and omv_passed and report_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }