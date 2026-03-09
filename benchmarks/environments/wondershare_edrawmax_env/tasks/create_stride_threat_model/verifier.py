#!/usr/bin/env python3
"""
Verifier for create_stride_threat_model task.

Verification Strategy:
1. Programmatic (Primary):
   - Check if .eddx file exists and is a valid ZIP archive.
   - Search internal XML content for specific text labels (Components and Threats).
2. VLM (Secondary):
   - Verify visual elements that are hard to parse programmatically:
     - Dashed line (Trust Boundary).
     - Spatial arrangement (Cloud in center, boundary enclosing cloud).
     - Connections between components.
"""

import os
import json
import zipfile
import tempfile
import logging
import sys
from pathlib import Path

# Import VLM utils from framework
sys.path.insert(0, str(Path(__file__).parents[2]))
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_stride_threat_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [
        "Mobile App", "IoT Cloud Platform", "Smart Thermostat", "Spoofing", "Tampering"
    ])
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # PART 1: File Existence & Metadata (20 points)
    # ---------------------------------------------------------
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    eddx_exists = result_data.get('eddx_exists', False)
    eddx_valid_time = result_data.get('eddx_valid_time', False)
    png_exists = result_data.get('png_exists', False)
    
    if eddx_exists and eddx_valid_time:
        score += 10
        feedback_parts.append("EDDX file created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but timestamp is suspicious.")
    else:
        feedback_parts.append("EDDX file missing.")

    if png_exists:
        score += 10
        feedback_parts.append("PNG export created.")
    else:
        feedback_parts.append("PNG export missing.")

    # ---------------------------------------------------------
    # PART 2: Programmatic Content Verification (40 points)
    # ---------------------------------------------------------
    # Extract text from the .eddx file (which is a ZIP of XMLs)
    found_terms = []
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/threat_model.eddx", temp_eddx.name)
            
            # EdrawMax files are ZIPs. Text is usually in page XML files.
            with zipfile.ZipFile(temp_eddx.name, 'r') as z:
                # Read all XML files in the zip
                all_text_content = ""
                for filename in z.namelist():
                    if filename.endswith('.xml'):
                        try:
                            with z.open(filename) as f_xml:
                                all_text_content += f_xml.read().decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for required terms
                for term in required_text:
                    if term.lower() in all_text_content.lower():
                        found_terms.append(term)
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is not a valid ZIP archive.")
        except Exception as e:
            feedback_parts.append(f"Error parsing EDDX file: {str(e)}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    
    # Score based on found terms
    term_score = 0
    if len(found_terms) == len(required_text):
        term_score = 40
        feedback_parts.append("All required text labels found in file.")
    elif len(found_terms) > 0:
        term_score = int((len(found_terms) / len(required_text)) * 40)
        feedback_parts.append(f"Found {len(found_terms)}/{len(required_text)} text labels: {', '.join(found_terms)}.")
    else:
        feedback_parts.append("No required text labels found in diagram.")
    
    score += term_score

    # ---------------------------------------------------------
    # PART 3: VLM Verification (40 points)
    # ---------------------------------------------------------
    # We need to verify:
    # 1. Trust Boundary (dashed line) is present and encloses the Cloud Platform.
    # 2. Arrows/Data flows exist between components.
    # 3. Threat labels are spatially near their respective targets (optional, hard for VLM, but generally presence is key).
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Use final screenshot if available, otherwise last frame
    image_to_check = final_screen if final_screen else (frames[-1] if frames else None)
    
    vlm_score = 0
    if image_to_check:
        prompt = """
        You are verifying a 'STRIDE Threat Model' diagram created in EdrawMax.
        
        The diagram should contain:
        1. Three main boxes/shapes labeled roughly 'Mobile App', 'IoT Cloud Platform', 'Smart Thermostat'.
        2. Arrows connecting them.
        3. A DASHED LINE (Trust Boundary) drawing a box or circle specifically around the 'IoT Cloud Platform'.
        4. Text labels 'Spoofing' and 'Tampering'.

        Please analyze the image and return JSON:
        {
            "components_present": boolean,
            "trust_boundary_visible": boolean,
            "boundary_is_dashed": boolean,
            "boundary_encloses_cloud": boolean,
            "connections_visible": boolean,
            "threat_labels_visible": boolean
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, image=image_to_check)
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            
            # Trust boundary check (Critical for this task)
            if parsed.get('trust_boundary_visible') and (parsed.get('boundary_is_dashed') or parsed.get('boundary_encloses_cloud')):
                vlm_score += 20
                feedback_parts.append("VLM confirmed Trust Boundary.")
            else:
                feedback_parts.append("VLM could not clearly identify the Trust Boundary (dashed line around cloud).")

            # Diagram structure check
            if parsed.get('components_present') and parsed.get('connections_visible'):
                vlm_score += 10
                feedback_parts.append("VLM confirmed diagram structure (components + arrows).")

            # Visual text confirmation (backup to programmatic)
            if parsed.get('threat_labels_visible'):
                vlm_score += 10
                feedback_parts.append("VLM confirmed threat labels visibility.")
                
        else:
            feedback_parts.append("VLM analysis failed.")
    else:
        feedback_parts.append("No screenshots available for VLM verification.")

    score += vlm_score
    
    # ---------------------------------------------------------
    # FINAL ASSESSMENT
    # ---------------------------------------------------------
    passed = score >= 70  # Requires decent file content + some visual verification
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }