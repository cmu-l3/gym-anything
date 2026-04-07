#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_properties_currency(traj, env_info, task_info):
    """
    Verifies that the project properties and currency were updated correctly.
    
    Criteria:
    1. Output XML file exists and is valid (10 pts)
    2. Project Title is "European Operations Rollout" (25 pts)
    3. Currency is EUR/€ (40 pts)
    4. Project Manager rate is 90.00 (25 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Projects/euro_project.xml')
    
    # Weights
    score_file_valid = 10
    score_title = 25
    score_currency = 40
    score_rate = 25
    
    total_score = 0
    feedback = []

    # 1. Retrieve Result Metadata
    # ---------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metadata."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output XML file was not created."}

    # 2. Retrieve and Parse XML
    # -------------------------
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_output_path, temp_xml.name)
        
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            total_score += score_file_valid
            feedback.append("Valid XML file generated.")
        except ET.ParseError:
            return {"passed": False, "score": 0, "feedback": "Output file exists but is not valid XML."}

        # XML Namespace handling (ProjectLibre MSPDI usually has a default namespace)
        # We'll try to detect it or search without it if possible.
        ns = {}
        if root.tag.startswith("{"):
            uri = root.tag.split("}")[0].strip("{")
            ns = {"p": uri}
        
        # Helper to find text safely
        def find_text(xpath):
            if ns:
                elem = root.find(xpath, ns)
            else:
                elem = root.find(xpath)
            return elem.text if elem is not None else None

        # 3. Verify Project Title
        # -----------------------
        # XPath: /Project/Title
        title = find_text("p:Title" if ns else "Title")
        if title and "European Operations Rollout" in title:
            total_score += score_title
            feedback.append(f"Project Title updated correctly to '{title}'.")
        else:
            feedback.append(f"Incorrect Project Title. Found: '{title}', Expected: 'European Operations Rollout'.")

        # 4. Verify Currency
        # ------------------
        # XPath: /Project/CurrencySymbol or /Project/CurrencyCode
        symbol = find_text("p:CurrencySymbol" if ns else "CurrencySymbol")
        code = find_text("p:CurrencyCode" if ns else "CurrencyCode")
        
        currency_correct = False
        if symbol and "€" in symbol:
            currency_correct = True
        elif code and "EUR" in code:
            currency_correct = True
            
        if currency_correct:
            total_score += score_currency
            feedback.append(f"Currency settings correct (Symbol: {symbol}, Code: {code}).")
        else:
            feedback.append(f"Incorrect Currency. Found Symbol: '{symbol}', Code: '{code}'. Expected € or EUR.")

        # 5. Verify Resource Rate
        # -----------------------
        # Needs to find Resource with Name "Project Manager" then check StandardRate
        resources = root.findall("p:Resources/p:Resource" if ns else "Resources/Resource", ns)
        target_resource = None
        
        for res in resources:
            res_name = res.find("p:Name" if ns else "Name", ns)
            if res_name is not None and res_name.text == "Project Manager":
                target_resource = res
                break
        
        rate_correct = False
        actual_rate = "Not Found"
        
        if target_resource is not None:
            rate_elem = target_resource.find("p:StandardRate" if ns else "StandardRate", ns)
            if rate_elem is not None:
                actual_rate = rate_elem.text
                # Format might be "90" or "90.00" or "PT90H..." depending on schema version
                # Usually ProjectLibre XML exports rate as simple number
                try:
                    rate_val = float(actual_rate)
                    if 89.9 <= rate_val <= 90.1:
                        rate_correct = True
                except ValueError:
                    pass

        if rate_correct:
            total_score += score_rate
            feedback.append("Project Manager rate updated to 90.00.")
        else:
            feedback.append(f"Incorrect Project Manager rate. Found: '{actual_rate}', Expected: 90.00.")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": total_score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 6. VLM Verification (Trajectory Check)
    # --------------------------------------
    # Only perform if score is high but not perfect, or as a sanity check
    # But for this task, XML proof is definitive. We'll use VLM just to confirm
    # they didn't just edit the XML file directly (unlikely in desktop env without text editor task)
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = "Does the sequence of images show a user interacting with a 'Project Information' dialog box or editing a 'Resource Sheet' in ProjectLibre?"
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            # We don't deduct points based on VLM here because XML is truth, 
            # but we can add positive feedback.
            if vlm_res and "yes" in str(vlm_res).lower():
                feedback.append("Visual confirmation: Project Information/Resource dialogs detected.")
        except Exception:
            pass # VLM failure shouldn't fail the task if XML is perfect

    passed = total_score >= 60 and "Currency settings correct" in str(feedback)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback)
    }