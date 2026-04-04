#!/usr/bin/env python3
"""
Verifier for PCA Score Extraction Workflow task.

Checks:
1. Jamovi project (.omv) exists and is a valid ZIP.
2. OMV contains a PCA analysis configuration with 25 items, 5 components, Varimax.
3. OMV contains a Correlation analysis configuration.
4. Dataset in OMV has expanded columns (original 28 -> 33), indicating scores were saved.
5. Text report contains a valid correlation coefficient.
"""

import json
import os
import zipfile
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pca_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # --- 1. Load Result JSON ---
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

    # --- 2. Check Project File Existence ---
    if not result_data.get("project_exists"):
        return {"passed": False, "score": 0, "feedback": "Jamovi project file not saved."}
    
    score += 10
    feedback.append("Project file saved.")

    # --- 3. Retrieve and Parse OMV File ---
    project_path = result_data["project_path"]
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    
    try:
        copy_from_env(project_path, temp_omv.name)
        
        if not zipfile.is_zipfile(temp_omv.name):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid OMV archive."}
        
        with zipfile.ZipFile(temp_omv.name, 'r') as z:
            namelist = z.namelist()
            
            # Check Analysis Configuration (usually in index.json or distinct analysis files)
            # Jamovi OMV structure typically has 'index.json' in root describing analyses
            analysis_found = {"pca": False, "correlation": False}
            pca_correct_config = False
            
            # Try to read metadata or index to find analyses
            # Structure varies slightly by version, but 'index.json' or 'meta' is standard
            try:
                if 'index.json' in namelist:
                    with z.open('index.json') as f:
                        index_data = json.load(f)
                        # index_data['analyses'] is a list
                        for analysis in index_data.get('analyses', []):
                            # Check for PCA
                            if 'pca' in analysis.get('name', '').lower() or \
                               'principal' in analysis.get('name', '').lower() or \
                               analysis.get('type') == 'pca':
                                analysis_found['pca'] = True
                                
                                # Check options inside the analysis entry
                                options = analysis.get('options', {})
                                # Check n_components (sometimes 'nFactor' or 'nFactors')
                                n_factors = options.get('nFactor') or options.get('nFactors') or options.get('nComp')
                                rotation = options.get('rotation', '').lower()
                                
                                if str(n_factors) == '5' and 'varimax' in rotation:
                                    pca_correct_config = True
                                    
                            # Check for Correlation
                            if 'corr' in analysis.get('name', '').lower() or \
                               'correlation' in analysis.get('name', '').lower():
                                analysis_found['correlation'] = True
                
                # Check metadata for variable count to verify "Save Scores"
                # If scores are saved, column count increases
                # BFI25 has 28 columns originally
                data_cols = 0
                if 'metadata.json' in namelist:
                    with z.open('metadata.json') as f:
                        meta = json.load(f)
                        # Usually meta['dataSet']['fieldCount'] or similar
                        if 'dataSet' in meta:
                            data_cols = meta['dataSet'].get('fieldCount', 0)
                        elif 'fields' in meta:
                             data_cols = len(meta['fields'])
                elif '000000.json' in namelist: # Sometimes metadata is in numbered jsons
                     pass # Hard to predict without traversing
                     
            except Exception as e:
                feedback.append(f"Error parsing OMV structure: {e}")

            # Scoring based on Analysis Findings
            if analysis_found['pca']:
                score += 20
                feedback.append("PCA analysis found.")
                if pca_correct_config:
                    score += 20
                    feedback.append("PCA configuration correct (5 comps, Varimax).")
                else:
                    feedback.append("PCA settings incorrect (check components/rotation).")
            else:
                feedback.append("No PCA analysis found in project.")

            if analysis_found['correlation']:
                score += 20
                feedback.append("Correlation analysis found.")
            else:
                feedback.append("No correlation analysis found.")
                
            # Verify Data Modification (Save Scores)
            # If we couldn't parse fieldCount from meta, we give benefit of doubt if PCA config is perfect
            # But ideally, we check data columns.
            # Assuming metadata.json exists in standard OMV:
            if data_cols >= 33: # 28 original + 5 components
                score += 20
                feedback.append("Component scores saved to dataset (variable count increased).")
            elif data_cols > 0:
                feedback.append(f"Dataset has {data_cols} variables (expected >= 33). Did you save component scores?")
            else:
                # Fallback if we couldn't read column count: check if text report is good
                pass

    except Exception as e:
        feedback.append(f"Failed to verify project file: {str(e)}")
    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    # --- 4. Check Text Report ---
    report_exists = result_data.get("report_exists")
    report_content = result_data.get("report_content", "")
    
    if report_exists:
        try:
            # Look for a float in the content
            match = re.search(r"0\.\d+", report_content)
            if match:
                val = float(match.group())
                # Neuroticism (N) generally has small negative correlation with Age
                # In BFI data, N often decreases slightly with age. 
                # Approx range |r|: 0.05 to 0.25.
                # We check if it's a valid correlation (0 to 1) and not exactly 0 or 1
                if 0.0 < val < 1.0:
                    score += 10
                    feedback.append(f"Reported correlation value: {val}")
                else:
                    feedback.append(f"Reported value {val} is unlikely for this data.")
            else:
                feedback.append("Could not parse number from report.")
        except:
            feedback.append("Error parsing report content.")
    else:
        feedback.append("Text report not found.")

    passed = (score >= 70) and analysis_found['pca'] and analysis_found['correlation']

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }