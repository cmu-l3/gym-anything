#!/usr/bin/env python3
"""
Verifier for create_it_ceiling_plan task.

Verification Strategy:
1. File Checks: Confirm .eddx and .png exist and were created during the task.
2. Content Analysis (XML): Unzip .eddx and search for specific text labels ("WAP-01", "OCC-01")
   and shape types (Lights, Projector, etc.).
3. VLM Verification: Analyze the exported PNG to visually confirm the ceiling grid and layout.
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil

# Import VLM utils from framework
try:
    from vlm_utils import query_vlm
except ImportError:
    # Fallback for local testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_it_ceiling_plan(traj, env_info, task_info):
    """
    Verify the Reflected Ceiling Plan creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_eddx = metadata.get('expected_eddx_path', '/home/ga/Documents/conference_room_rcp.eddx')
    expected_png = metadata.get('expected_png_path', '/home/ga/Documents/conference_room_rcp.png')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Temporary directory for file analysis
    temp_dir = tempfile.mkdtemp()
    local_eddx = os.path.join(temp_dir, "diagram.eddx")
    local_png = os.path.join(temp_dir, "export.png")
    local_result_json = os.path.join(temp_dir, "task_result.json")

    try:
        # 1. Get Setup/Export Metadata
        try:
            copy_from_env("/tmp/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {e}"}

        # 2. Check File Existence & Timestamp (Anti-Gaming)
        if task_result.get("eddx_exists") and task_result.get("eddx_created_during_task"):
            score += 10
            feedback_parts.append("EDDX file created successfully.")
            
            # Copy EDDX for content analysis
            try:
                copy_from_env(expected_eddx, local_eddx)
            except Exception:
                feedback_parts.append("Could not retrieve EDDX file for analysis.")
        elif task_result.get("eddx_exists"):
            feedback_parts.append("EDDX file exists but was not created during this task session.")
        else:
            feedback_parts.append("EDDX file not found.")

        if task_result.get("png_exists") and task_result.get("png_created_during_task"):
            score += 10
            feedback_parts.append("PNG export created successfully.")
            
            # Copy PNG for VLM analysis
            try:
                copy_from_env(expected_png, local_png)
            except Exception:
                feedback_parts.append("Could not retrieve PNG file for analysis.")
        else:
            feedback_parts.append("PNG export not found or stale.")

        # 3. Content Analysis (XML Parsing of .eddx)
        # EdrawMax files are zip archives containing XMLs
        xml_content = ""
        found_labels = []
        found_shapes = []
        
        if os.path.exists(local_eddx) and zipfile.is_zipfile(local_eddx):
            try:
                with zipfile.ZipFile(local_eddx, 'r') as z:
                    # Search all XML files in the archive (usually in model/pages/)
                    for filename in z.namelist():
                        if filename.endswith('.xml'):
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                xml_content += content
                            except Exception:
                                pass
                
                # Check for specific labels
                for label in ["WAP-01", "OCC-01"]:
                    if label in xml_content:
                        score += 15
                        found_labels.append(label)
                
                if found_labels:
                    feedback_parts.append(f"Found required labels: {', '.join(found_labels)}.")
                else:
                    feedback_parts.append("Missing required labels (WAP-01, OCC-01).")

                # Check for shape keywords (heuristic based on common XML attributes)
                # We check case-insensitive keywords that likely appear in shape Names or IDs
                required_keywords = {
                    "Projector": 10,
                    "Screen": 10,
                    "Speaker": 10,
                    "Grid": 5  # Ceiling Grid
                }
                
                for keyword, pts in required_keywords.items():
                    if keyword.lower() in xml_content.lower():
                        score += pts
                        found_shapes.append(keyword)
                
                if found_shapes:
                    feedback_parts.append(f"Identified shape types: {', '.join(found_shapes)}.")
            
            except Exception as e:
                feedback_parts.append(f"Error parsing EDDX file: {e}")
        
        # 4. VLM Verification on Exported PNG
        # If the PNG exists, we ask a VLM to verify it looks like a ceiling plan
        vlm_passed = False
        if os.path.exists(local_png) and os.path.getsize(local_png) > 1024:
            prompt = """
            Analyze this image. It should be a 'Reflected Ceiling Plan' for a conference room created in EdrawMax.
            
            Check for the following visual elements:
            1. A rectangular room layout.
            2. A grid pattern covering the room (ceiling grid).
            3. Rectangular light fixtures (troffers) arranged in a pattern.
            4. Specific symbols: A projector (center), a screen (wall), and small circular devices (sensors/speakers).
            5. Text labels reading "WAP-01" or "OCC-01".
            
            Does this image appear to be a valid Reflected Ceiling Plan with these elements?
            Answer JSON: {"is_valid_rcp": boolean, "elements_found": [list of strings], "confidence": float}
            """
            
            vlm_res = query_vlm(prompt, image=local_png)
            
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_valid_rcp", False):
                    score += 15 # VLM Bonus for visual confirmation
                    vlm_passed = True
                    feedback_parts.append("Visual verification passed: Looks like a valid RCP.")
                else:
                    feedback_parts.append(f"Visual verification failed: {parsed.get('elements_found', [])}")
            else:
                feedback_parts.append("Visual verification skipped (service unavailable).")

    finally:
        shutil.rmtree(temp_dir)

    # Final Pass Logic
    # Must have created the EDDX file, found at least one specific label, AND one AV shape
    key_requirements_met = (
        task_result.get("eddx_created_during_task") and 
        len(found_labels) > 0 and 
        len(found_shapes) > 0
    )
    
    passed = (score >= 70) and key_requirements_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }