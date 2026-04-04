#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_techdraw_section_view(traj, env_info, task_info):
    """
    Verifies that the agent created a TechDraw section view.
    
    Strategy:
    1. Check if output file exists and was modified during task.
    2. Download and unzip the .FCStd file (it is a zip archive).
    3. Parse Document.xml to find TechDraw objects.
    4. Confirm existence of a Page, a Base View, and a Section View.
    5. Use VLM to visually confirm the drawing looks correct.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result metadata from container
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timing Checks (20 pts)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file housing_drawing.FCStd not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp suggests it wasn't modified during task.")
    else:
        score += 20
        feedback_parts.append("File created during task.")

    # 2. Content Verification via XML Parsing (50 pts)
    # FCStd files are standard ZIP archives containing Document.xml
    temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        copy_from_env("/home/ga/Documents/FreeCAD/housing_drawing.FCStd", temp_fcstd.name)
        
        has_page = False
        has_base_view = False
        has_section_view = False
        
        if zipfile.is_zipfile(temp_fcstd.name):
            with zipfile.ZipFile(temp_fcstd.name, 'r') as z:
                if 'Document.xml' in z.namelist():
                    with z.open('Document.xml') as f:
                        tree = ET.parse(f)
                        root = tree.getroot()
                        
                        # Namespace handling usually requires care, but we can search by attribute
                        # Structure is usually <Object type="TechDraw::DrawViewSection" ...>
                        
                        for obj in root.findall(".//Object"):
                            obj_type = obj.get("type", "")
                            
                            if "TechDraw::DrawPage" in obj_type:
                                has_page = True
                            elif "TechDraw::DrawViewPart" in obj_type:
                                has_base_view = True
                            elif "TechDraw::DrawViewSection" in obj_type:
                                has_section_view = True
                            # Fallback for some versions/arch
                            elif "DrawViewSection" in obj_type:
                                has_section_view = True

        if has_page:
            score += 10
            feedback_parts.append("TechDraw page found.")
        else:
            feedback_parts.append("No TechDraw page found in document.")

        if has_base_view:
            score += 15
            feedback_parts.append("Base view found.")
        else:
            feedback_parts.append("No standard view found.")

        if has_section_view:
            score += 25
            feedback_parts.append("Section view found.")
        else:
            feedback_parts.append("No Section view found.")

    except Exception as e:
        feedback_parts.append(f"Error inspecting file content: {str(e)}")
    finally:
        if os.path.exists(temp_fcstd.name):
            os.unlink(temp_fcstd.name)

    # 3. VLM Verification (30 pts)
    # Visual check to ensure it's not just empty objects
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of FreeCAD. The user should have created a technical drawing "
        "of a mechanical part. Look for: \n"
        "1. A white drawing page/sheet (TechDraw workbench).\n"
        "2. At least two distinct views of the part on the sheet.\n"
        "3. One view should look like a cross-section (often has hatched lines or looks cut).\n"
        "Do you see a valid technical drawing with a section view?"
    )
    
    # We use the frames to check for the workflow
    vlm_score = 0
    try:
        vlm_result = query_vlm(
            images=frames + [final_shot],
            prompt=vlm_prompt
        )
        
        if vlm_result.get("success", False):
            # Simple keyword heuristic on VLM reasoning if available, 
            # or rely on the implicit "True" from a 'yes' answer structure if the VLM wrapper supports it.
            # Assuming standard wrapper returns a boolean or we parse reasoning.
            # Here we assign points if VLM output is positive.
            response_text = vlm_result.get("text", "").lower()
            if "yes" in response_text and "drawing" in response_text:
                vlm_score = 30
                feedback_parts.append("Visual verification passed.")
            elif "section" in response_text or "hatched" in response_text:
                vlm_score = 20
                feedback_parts.append("Visual verification partial (section detected).")
            else:
                feedback_parts.append(f"Visual verification unclear: {response_text[:50]}...")
        else:
            feedback_parts.append("VLM verification failed to run.")
            
    except Exception as e:
        feedback_parts.append(f"VLM error: {str(e)}")

    score += vlm_score

    # Final Pass Determination
    # Must have the file, the specific section object, and some visual confirmation
    passed = (has_section_view and score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }