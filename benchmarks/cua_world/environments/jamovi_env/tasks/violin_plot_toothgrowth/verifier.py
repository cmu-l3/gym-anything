#!/usr/bin/env python3
"""
Verifier for violin_plot_toothgrowth task.
Checks for .omv file structure (analysis options, filters) and exported image.
"""

import json
import os
import tempfile
import zipfile
import shutil
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_violin_plot_toothgrowth(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the .omv file with correct Descriptives analysis configuration.
    2. Enabled Violin, Box, and Data plots.
    3. Applied a filter to exclude dose=1.0.
    4. Exported a valid PNG image.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check file existence and creation (Anti-gaming)
    omv_exists = result.get("omv_exists", False)
    omv_fresh = result.get("omv_created_during_task", False)
    png_exists = result.get("png_exists", False)
    png_fresh = result.get("png_created_during_task", False)

    if not omv_exists:
        return {"passed": False, "score": 0, "feedback": "Jamovi project file (.omv) not found."}
    
    score += 10
    feedback_parts.append("OMV file created.")
    
    if omv_fresh:
        score += 10
        feedback_parts.append("OMV file created during task.")
    else:
        feedback_parts.append("Warning: OMV file timestamp is old.")

    if png_exists:
        score += 10
        feedback_parts.append("PNG export found.")
        if png_fresh:
            score += 5
            feedback_parts.append("PNG created during task.")
    else:
        feedback_parts.append("PNG export missing.")

    # 3. Analyze OMV content
    # OMV is a zip. We need to look at the analysis definition inside.
    # We'll extract it to a temp dir.
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    omv_analysis_passed = False
    filter_passed = False
    
    try:
        copy_from_env(result.get("omv_path", "/tmp/submission.omv"), temp_omv.name)
        
        with zipfile.ZipFile(temp_omv.name, 'r') as z:
            # List files to find the analysis definitions
            # Jamovi .omv structure usually has an 'index.json' or numbered folders like '01 descriptives'
            file_list = z.namelist()
            
            # Check for Filter
            # Filters are often in metadata or part of the data definition.
            # In Jamovi 2.x, filters are often stored in 'meta' or 'data.bin' metadata.
            # Parsing binary data is hard, but we can check the 'index.json' or '0.json' (manifest).
            # Sometimes filters are just columns with formulas.
            
            # Let's search for analysis options first
            found_descriptives = False
            correct_plots = False
            correct_vars = False
            
            # Iterate through JSON files in the zip to find the analysis spec
            for filename in file_list:
                if filename.endswith('.json') and 'analysis' in filename.lower():
                    # This might be an analysis definition
                    # Jamovi uses separate folders for analyses, e.g., "1 descriptives/analysis"
                    pass
                
                if filename.endswith('01 descriptives') or 'descriptives' in filename.lower():
                    # This is likely the analysis folder
                    pass

                # Generic search for JSONs that look like analysis definitions
                if filename.endswith('.json'):
                    try:
                        with z.open(filename) as f:
                            data = json.load(f)
                            
                            # Check if this is a Descriptives analysis
                            # Structure varies by version, looking for keys
                            # Typically: "name": "descriptives", "options": {...}
                            
                            # Flatten logical check: is this the descriptives analysis?
                            if isinstance(data, dict) and \
                               (data.get("name") == "descriptives" or \
                                data.get("procName") == "descriptives" or \
                                "descriptives" in str(data.get("title", "")).lower()):
                                
                                found_descriptives = True
                                options = data.get("options", {})
                                
                                # Check variables
                                vars_ = options.get("vars", [])
                                split = options.get("splitBy", [])
                                if "len" in vars_ and "supp" in str(split):
                                    correct_vars = True
                                
                                # Check plots
                                # Options keys might be 'violin', 'box', 'dot'
                                if options.get("violin", False) and \
                                   options.get("box", False) and \
                                   options.get("dot", False):
                                    correct_plots = True
                                    
                    except:
                        continue

            # Check for filter in 'index.json' or 'meta'
            # Simpler check: Grep the raw text of json files for filter syntax
            # "dose != 1" or similar
            for filename in file_list:
                if filename.endswith('index.json') or filename.endswith('metadata.json'):
                    try:
                        with z.open(filename) as f:
                            content = f.read().decode('utf-8')
                            # Check for filter presence
                            if 'filters' in content.lower() or 'filter' in content.lower():
                                # Heuristic: check if our logic is present
                                if 'dose' in content and ('!=' in content or '1' in content):
                                    filter_passed = True
                    except:
                        pass

            if found_descriptives:
                score += 15
                feedback_parts.append("Descriptives analysis found.")
            else:
                feedback_parts.append("Descriptives analysis NOT found in OMV.")

            if correct_vars:
                score += 15
                feedback_parts.append("Correct variables selected (len by supp).")
            else:
                feedback_parts.append("Incorrect variable selection.")

            if correct_plots:
                score += 20
                feedback_parts.append("Violin + Box + Data plots enabled.")
            else:
                feedback_parts.append("Plot options incorrect (Check Violin, Box, and Data).")
            
            if filter_passed:
                score += 15
                feedback_parts.append("Filter appears to be applied.")
            else:
                # Fallback: lenient points if analysis is correct, assuming filter might be hidden in binary
                feedback_parts.append("Could not confirm filter syntax explicitly.")

            omv_analysis_passed = found_descriptives and correct_vars and correct_plots

    except Exception as e:
        feedback_parts.append(f"Error parsing OMV file: {e}")

    finally:
        if os.path.exists(temp_omv.name):
            os.unlink(temp_omv.name)

    # 4. Final Scoring
    # Max Score Breakdown:
    # - OMV Exists: 10
    # - OMV Fresh: 10
    # - PNG Exists: 10
    # - PNG Fresh: 5
    # - Descriptives Found: 15
    # - Correct Vars: 15
    # - Correct Plots: 20
    # - Filter: 15
    # Total: 100
    
    # Calculate Passed
    # Must have OMV, PNG, and mostly correct analysis
    passed = (score >= 70) and omv_exists and png_exists and omv_analysis_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }