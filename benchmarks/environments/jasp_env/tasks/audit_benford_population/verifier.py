#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_benford_population(traj, env_info, task_info):
    """
    Verify the JASP Benford's Law analysis.
    
    Scoring:
    - 10 pts: File exists
    - 30 pts: Analysis uses the 'Audit' module (Benford's Law)
    - 40 pts: Correct variable 'Value' selected
    - 20 pts: 'Observed vs expected' plot enabled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 1. Retrieve metadata result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    try:
        copy_from_env("/tmp/task_result.json", temp_json)
        with open(temp_json) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {str(e)}"}
    finally:
        if os.path.exists(temp_json):
            os.remove(temp_json)

    # 2. Check basic file existence
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "JASP output file not found."}
    
    if not result_data.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task session."}

    score += 10
    feedback.append("Output file created.")

    # 3. Retrieve and Analyze the .jasp file
    jasp_path = result_data["output_path"]
    local_jasp = tempfile.NamedTemporaryFile(delete=False, suffix=".jasp").name
    
    try:
        copy_from_env(jasp_path, local_jasp)
        
        # JASP files are ZIPs. We need to look inside.
        if not zipfile.is_zipfile(local_jasp):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP archive."}

        with zipfile.ZipFile(local_jasp, 'r') as z:
            # List files to find the analysis definition
            # Structure usually includes 'embedded/...' or root JSONs.
            # We look for any JSON that contains analysis info.
            filenames = z.namelist()
            json_content = ""
            
            # Common JASP structure: the state is often in 'index.html' embedded data or specific json files
            # But simpler: search all .json files or read 'index.html' looking for config
            # Actually, JASP saves the analysis state in the .jasp zip. 
            # Often it is in a folder like `analysis/` or similar.
            
            # Robust verification: Search text content of relevant files for keys
            found_benford = False
            found_variable = False
            found_plot = False
            
            for fname in filenames:
                if fname.endswith('.json') or fname.endswith('.qml') or "results" in fname:
                    try:
                        content = z.read(fname).decode('utf-8', errors='ignore')
                        
                        # Check module/analysis type
                        # "jfaBenfordsLaw" is the internal name, or "Benford" title
                        if "jfaBenfordsLaw" in content or ("Benford" in content and "analysis" in content.lower()):
                            found_benford = True
                        
                        # Check variable "Value"
                        # Representation might be "Value" in a variables list
                        if '"Value"' in content or "'Value'" in content:
                            found_variable = True
                            
                        # Check plot "Observed vs. expected"
                        # Internal key might be "plotObservedExpected" or boolean flags
                        # We look for the specific plot setting being true
                        if "plotObservedExpected" in content and "true" in content.lower():
                            found_plot = True
                        elif "observed vs. expected" in content.lower():
                             # If the UI label is stored
                            found_plot = True
                            
                    except:
                        continue

            if found_benford:
                score += 30
                feedback.append("Audit/Benford analysis found.")
            else:
                feedback.append("Could not confirm Benford's Law analysis type.")

            if found_variable:
                score += 40
                feedback.append("Correct variable 'Value' used.")
            else:
                feedback.append("Variable 'Value' not detected in analysis.")

            if found_plot:
                score += 20
                feedback.append("Observed vs. Expected plot enabled.")
            else:
                feedback.append("Required plot not detected.")

    except Exception as e:
        feedback.append(f"Error analyzing JASP file: {str(e)}")
    finally:
        if os.path.exists(local_jasp):
            os.remove(local_jasp)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }