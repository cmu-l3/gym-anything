#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anova_residual_normality_check(traj, env_info, task_info):
    """
    Verifies that the agent performed an ANOVA, saved residuals, and ran a Shapiro-Wilk test on them.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load export result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'ToothGrowth_Residuals.omv' not found."}
    
    if not result_data.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task session."}

    output_path = result_data.get("output_path")
    
    # Download and inspect the OMV file
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    try:
        copy_from_env(output_path, temp_omv.name)
        
        # OMV is a ZIP archive. We need to inspect the analysis JSONs inside.
        with zipfile.ZipFile(temp_omv.name, 'r') as z:
            file_list = z.namelist()
            
            # 1. Analyze Metadata to check variable types and residuals existence
            # Usually found in 'metadata.json' or 'xdata.json' depending on version
            metadata_files = [f for f in file_list if 'metadata.json' in f]
            has_residuals_var = False
            dose_is_factor = False
            
            for mf in metadata_files:
                try:
                    meta_content = json.loads(z.read(mf).decode('utf-8'))
                    # Check fields/variables
                    if 'fields' in meta_content:
                        for field in meta_content['fields']:
                            name = field.get('name', '')
                            ftype = field.get('measureType', '')
                            
                            # Check dose type (should be nominal or ordinal)
                            if name == 'dose':
                                if ftype in ['nominal', 'ordinal']:
                                    dose_is_factor = True
                            
                            # Check for residuals variable
                            # Jamovi typically names it 'Residuals' or 'Residuals - [DepVar]'
                            if 'Residuals' in name:
                                has_residuals_var = True
                except Exception as e:
                    logger.warning(f"Error parsing metadata {mf}: {e}")

            # 2. Analyze Analysis JSONs to check configuration
            # Look for numbered json files in root or analysis folder
            analysis_files = [f for f in file_list if re.match(r'.*\d+\s+.*\.json$', f) and 'metadata' not in f]
            
            anova_found = False
            anova_save_resid = False
            descriptives_found = False
            shapiro_checked = False
            
            for af in analysis_files:
                try:
                    content = json.loads(z.read(af).decode('utf-8'))
                    options = content.get('options', {})
                    name = content.get('name', '')
                    
                    # Check for ANOVA
                    if name == 'ANOVA' or content.get('type') == 'jmv::ANOVA':
                        anova_found = True
                        # Check dependent and fixed factors
                        if options.get('dep') == 'len' and 'dose' in options.get('fixed', []):
                            # Check save residuals option
                            # Key might be 'saveResid' or similar
                            if options.get('saveResid') is True:
                                anova_save_resid = True
                                
                    # Check for Descriptives
                    if name == 'descriptives' or content.get('type') == 'jmv::descriptives':
                        vars_list = options.get('vars', [])
                        # Check if analyzing a residual variable
                        if any('Residuals' in v for v in vars_list):
                            descriptives_found = True
                            # Check Shapiro-Wilk
                            # Key usually 'sw' or 'shapiro'
                            if options.get('sw') is True or options.get('shapiro') is True:
                                shapiro_checked = True
                                
                except Exception as e:
                    logger.warning(f"Error parsing analysis {af}: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to analyze OMV file: {str(e)}"}
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    # Calculate Score
    score = 0
    feedback = []

    # Criteria 1: File created (10 pts) - Already verified above
    score += 10
    feedback.append("File created.")

    # Criteria 2: Dose variable type correct (20 pts)
    if dose_is_factor:
        score += 20
        feedback.append("Variable 'dose' correctly set to Factor.")
    else:
        feedback.append("Variable 'dose' not set to Nominal/Ordinal (failed Factor requirement).")

    # Criteria 3: Correct ANOVA Module (20 pts)
    if anova_found:
        score += 20
        feedback.append("General ANOVA module used.")
    else:
        feedback.append("General ANOVA analysis not found.")

    # Criteria 4: Residuals Saved (25 pts)
    # Requires both the option enabled AND the variable existing in data
    if anova_save_resid and has_residuals_var:
        score += 25
        feedback.append("Residuals successfully saved to dataset.")
    elif anova_save_resid:
        score += 15
        feedback.append("Save Residuals option enabled, but variable not found in metadata.")
    elif has_residuals_var:
        score += 15
        feedback.append("Residuals variable found, but Analysis options unclear.")
    else:
        feedback.append("Residuals not saved.")

    # Criteria 5: Normality Test Run (25 pts)
    if descriptives_found and shapiro_checked:
        score += 25
        feedback.append("Shapiro-Wilk test performed on residuals.")
    elif descriptives_found:
        score += 10
        feedback.append("Descriptives run on residuals, but Shapiro-Wilk not enabled.")
    else:
        feedback.append("Descriptives analysis on residuals not found.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }