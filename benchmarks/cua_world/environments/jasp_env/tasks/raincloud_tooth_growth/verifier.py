#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import zipfile
import logging
import shutil

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_raincloud_tooth_growth(traj, env_info, task_info):
    """
    Verify the JASP Raincloud plot task.
    
    Criteria:
    1. JASP file created during task.
    2. Analysis type is 'Descriptives'.
    3. Variables: 'len' (dependent), split by 'supp' AND 'dose'.
    4. 'dose' variable type explicitly set to 'ordinal'.
    5. Plots: Raincloud config (violin + box + jitter) enabled.
    6. Stats: Mean, StdDev, CI enabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    score = 0
    max_score = 100
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Get Task Result Metadata (File existence, timestamp)
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file ToothGrowth_Raincloud.jasp not found."}

    if not task_result.get("file_created_during_task", False):
        feedback.append("Warning: File timestamp indicates it wasn't modified during this session.")
    else:
        score += 10
        feedback.append("File created/saved successfully (10/10).")

    # ------------------------------------------------------------------
    # 2. Retrieve and Analyze the .jasp File
    # ------------------------------------------------------------------
    jasp_file_path = task_result.get("output_path")
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .jasp is a zip
    
    try:
        copy_from_env(jasp_file_path, temp_jasp.name)
        
        # JASP files are ZIP archives containing JSON analysis definitions
        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            # Look for JSON files in the archive that might contain analysis settings
            # Typically in "analysis/1/analysis.json" or similar structure
            json_files = [f for f in z.namelist() if f.endswith('.json')]
            
            analysis_found = False
            correct_vars = False
            correct_split = False
            correct_type = False
            correct_plots = False
            correct_stats = False
            
            for jf in json_files:
                try:
                    with z.open(jf) as f:
                        data = json.load(f)
                        
                        # Recursive search helper for complex JSON structures
                        def find_key(obj, key):
                            if key in obj: return obj[key]
                            if isinstance(obj, dict):
                                for k, v in obj.items():
                                    if isinstance(v, (dict, list)):
                                        res = find_key(v, key)
                                        if res is not None: return res
                            elif isinstance(obj, list):
                                for v in obj:
                                    res = find_key(v, key)
                                    if res is not None: return res
                            return None

                        # Check if this is a Descriptive Statistics analysis
                        # JASP internal name for Descriptives is often "Descriptives"
                        title = find_key(data, "title")
                        name = find_key(data, "name")
                        
                        if title == "Descriptive Statistics" or name == "Descriptives":
                            analysis_found = True
                            
                            # Extract settings usually found in "options"
                            options = find_key(data, "options")
                            if not options:
                                continue

                            # Check Variables: 'variables' list should contain 'len'
                            # 'splitBy' list should contain 'supp' and 'dose'
                            vars_list = options.get("variables", [])
                            split_list = options.get("splitBy", [])
                            
                            if "len" in str(vars_list):
                                correct_vars = True
                            
                            if "supp" in str(split_list) and "dose" in str(split_list):
                                correct_split = True

                            # Check Plots: Raincloud or (Violin + Box + Jitter)
                            # Keys might be "raincloudPlots", "violinPlots", "boxPlots", "dataDisplay"
                            raincloud = options.get("raincloudPlots", False)
                            violin = options.get("violinPlots", False)
                            box = options.get("boxPlots", False)
                            jitter = options.get("dataDisplay") == "jitter" or options.get("jitterElement", False)
                            
                            if raincloud or (violin and box and jitter):
                                correct_plots = True
                            
                            # Check Stats: Mean, StdDev, CI
                            # JASP option keys: "mean", "stdDev", "meanCI"
                            if options.get("mean", False) and options.get("stdDev", False) and options.get("meanCI", False):
                                correct_stats = True
                                
                            # Check Variable Type: 'dose' should be ordinal
                            # This might be in the analysis settings or separate metadata
                            # Often JASP saves user-defined types in the analysis options or data state
                            # We search for the specific definition or look at how 'dose' is treated
                            # A strong signal is if "dose" is associated with "ordinal" in the JSON
                            
                            # Rough check in the whole file content for safety
                            json_str = json.dumps(data).lower()
                            if '"dose"' in json_str and '"ordinal"' in json_str:
                                correct_type = True
                                
                except Exception as e:
                    logger.warning(f"Error parsing {jf}: {e}")
                    continue

            # Scoring based on findings
            if analysis_found:
                score += 20
                feedback.append("Descriptive statistics analysis found (20/20).")
            else:
                feedback.append("No Descriptive Statistics analysis found in file.")

            if correct_vars:
                score += 10
                feedback.append("Correct dependent variable 'len' selected (10/10).")
            else:
                feedback.append("Dependent variable 'len' not found in analysis.")

            if correct_split:
                score += 20
                feedback.append("Analysis correctly split by 'supp' and 'dose' (20/20).")
            else:
                feedback.append("Split variables 'supp' and 'dose' not correctly configured.")

            if correct_type:
                score += 10
                feedback.append("Variable 'dose' identified as Ordinal (10/10).")
            else:
                feedback.append("Variable 'dose' does not appear to be set to Ordinal type.")

            if correct_plots:
                score += 20
                feedback.append("Raincloud plot configuration (Violin+Box+Jitter) verified (20/20).")
            else:
                feedback.append("Plot configuration incorrect. missing Raincloud or Violin/Box/Jitter combo.")

            if correct_stats:
                score += 10
                feedback.append("Statistics (Mean, SD, 95% CI) correctly enabled (10/10).")
            else:
                feedback.append("Missing required statistics (Mean, SD, or CI).")

    except zipfile.BadZipFile:
        return {"passed": False, "score": 10, "feedback": "Output file is not a valid JASP/Zip archive."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }