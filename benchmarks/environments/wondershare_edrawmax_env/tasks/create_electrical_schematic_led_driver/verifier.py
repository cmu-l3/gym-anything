#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_electrical_schematic(traj, env_info, task_info):
    """
    Verifies the electrical schematic task.
    
    Scoring Criteria:
    1. Files (EDDX + PNG) exist and created during task (20 pts)
    2. EDDX is valid and contains required text labels (40 pts)
    3. Visual verification (VLM) confirms schematic structure (40 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    required_labels = metadata.get('required_labels', ["9V", "1k", "330R", "2N2222", "LED", "GND"])
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: Load Export Result ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # --- Step 2: File Verification (20 pts) ---
    eddx_exists = result_data.get("eddx_exists", False)
    eddx_fresh = result_data.get("eddx_created_during_task", False)
    png_exists = result_data.get("png_exists", False)
    
    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but timestamp is suspicious.")
    else:
        feedback_parts.append("EDDX file missing.")

    if png_exists and result_data.get("png_created_during_task", False):
        score += 10
        feedback_parts.append("PNG export created.")
    else:
        feedback_parts.append("PNG export missing.")

    # --- Step 3: Content Verification via XML Parsing (40 pts) ---
    # We unzip the .eddx and check page XMLs for the text labels
    labels_found = 0
    valid_archive = False
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata['expected_eddx'], temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                valid_archive = True
                # Concatenate all XML content to search
                all_xml_content = ""
                for filename in zf.namelist():
                    if filename.endswith(".xml"):
                        try:
                            all_xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for labels
                found_list = []
                for label in required_labels:
                    # Simple substring search in the XML
                    if label in all_xml_content:
                        labels_found += 1
                        found_list.append(label)
                
                # Normalize score based on fraction of labels found
                if len(required_labels) > 0:
                    fraction = labels_found / len(required_labels)
                    score += int(40 * fraction)
                    feedback_parts.append(f"Found labels: {found_list}")
                else:
                    score += 40 # No labels required?
                    
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is corrupted or not a valid zip.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    # --- Step 4: Visual Verification via VLM (40 pts) ---
    # We verify the FINAL state looks like a schematic
    
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        You are evaluating a screenshot of Wondershare EdrawMax.
        The user is supposed to create an electrical schematic for an LED driver.
        
        Look for:
        1. Electrical symbols (Resistor zig-zags, Battery/Source lines, Ground symbol, Transistor circle).
        2. Connectivity (black lines connecting the symbols).
        3. Labels like "9V", "1k", "2N2222", "GND".
        
        Does this image contain a recognizable electrical circuit diagram?
        """
        
        vlm_result = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_result['success']:
            # We expect a positive assessment
            # A simple heuristic: if the model replies positively about seeing a circuit
            content = vlm_result.get('answer', '').lower()
            if "yes" in content or "circuit" in content or "schematic" in content:
                score += 40
                feedback_parts.append("VLM confirms circuit diagram is visible.")
            else:
                feedback_parts.append("VLM did not detect a clear circuit diagram.")
        else:
            feedback_parts.append("VLM check failed (technical error).")
            # Fallback: if we found all labels in XML, give partial credit for VLM
            if labels_found >= len(required_labels) - 1:
                score += 20
                feedback_parts.append("Fallback: High label match implies visual success.")

    # --- Final Scoring ---
    passed = (score >= 70) and valid_archive
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }