#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_archimate_diagram(traj, env_info, task_info):
    """
    Verifies the ArchiMate diagram task.
    Checks for:
    1. Valid .drawio file creation.
    2. Usage of ArchiMate 3.0 shape library (crucial).
    3. Presence of required elements in correct layers.
    4. Connectivity.
    5. PDF Export.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = data.get("diagram_analysis", {})
    export_data = data.get("export", {})
    
    score = 0
    feedback = []
    
    # 2. Verification Criteria
    
    # A. File Existence & Validity (10 pts)
    if analysis.get("file_exists") and analysis.get("file_valid"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Diagram file not saved or invalid."}

    # B. Modification Check (Anti-Gaming)
    if not analysis.get("modified_during_task"):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task session."}

    # C. ArchiMate Library Usage (15 pts) - CRITICAL
    # We check if 'archimate3' style tags were found in the XML
    if analysis.get("archimate_library_used"):
        score += 15
        feedback.append("Correct ArchiMate 3.0 shape library used.")
    else:
        feedback.append("❌ Standard ArchiMate shapes not used (generic shapes detected).")
        
    # D. Element Checking (45 pts total)
    # Helper to fuzzy match names
    def check_layer(layer_name, expected_names, layer_data):
        found_count = 0
        local_feedback = []
        for expected in expected_names:
            found = False
            for item in layer_data:
                if expected.lower() in item["name"].lower():
                    found = True
                    break
            if found:
                found_count += 1
            else:
                local_feedback.append(f"Missing '{expected}'")
        
        return found_count, local_feedback

    # Business Layer (15 pts)
    biz_expected = ["Customer", "Submit Claim", "Claims Administration"]
    biz_count, biz_missing = check_layer("Business", biz_expected, analysis["elements"]["business"])
    score += (biz_count * 5)
    if biz_missing:
        feedback.append(f"Business Layer missing: {', '.join(biz_missing)}")

    # Application Layer (15 pts)
    app_expected = ["Claims Management Service", "Home & Away", "Customer Data"]
    app_count, app_missing = check_layer("Application", app_expected, analysis["elements"]["application"])
    score += (app_count * 5)
    if app_missing:
        feedback.append(f"App Layer missing: {', '.join(app_missing)}")

    # Technology Layer (10 pts)
    tech_expected = ["Mainframe", "Policy Database"]
    tech_count, tech_missing = check_layer("Technology", tech_expected, analysis["elements"]["technology"])
    score += (tech_count * 5)
    if tech_missing:
        feedback.append(f"Tech Layer missing: {', '.join(tech_missing)}")

    # E. Connections (10 pts)
    conn_count = analysis.get("connections_count", 0)
    if conn_count >= 5:
        score += 10
        feedback.append(f"Connections sufficient ({conn_count}).")
    elif conn_count > 0:
        score += 5
        feedback.append(f"Partial connections ({conn_count}/5).")
    else:
        feedback.append("❌ No connections between elements.")

    # F. Export (10 pts)
    if export_data.get("pdf_exists") and export_data.get("pdf_size_bytes", 0) > 100:
        score += 10
        feedback.append("PDF export successful.")
    else:
        feedback.append("❌ PDF export missing or empty.")

    # 3. Final Evaluation
    passed = score >= 60 and analysis.get("archimate_library_used")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }