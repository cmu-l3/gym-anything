#!/usr/bin/env python3
"""
Verifier for create_warehouse_layout task.
Checks for valid .eddx file, correct text content (Zones, Docks, Rows), and visual layout.
"""

import json
import os
import tempfile
import zipfile
import logging
from typing import Dict, Any, List

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Mock for testing if framework not available
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_xml_content(eddx_path: str, required_terms: List[str]) -> Dict[str, Any]:
    """Unzip .eddx and check if required terms exist in the XML content."""
    found_terms = []
    missing_terms = []
    
    try:
        with zipfile.ZipFile(eddx_path, 'r') as zf:
            # EdrawMax files store page content in XML files (often under pages/)
            # We'll search all xml files to be safe.
            xml_content = ""
            for filename in zf.namelist():
                if filename.endswith('.xml'):
                    try:
                        xml_content += zf.read(filename).decode('utf-8', errors='ignore')
                    except Exception:
                        pass
            
            # Normalize for search
            xml_content_lower = xml_content.lower()
            
            for term in required_terms:
                if term.lower() in xml_content_lower:
                    found_terms.append(term)
                else:
                    missing_terms.append(term)
                    
            return {
                "success": True,
                "found": found_terms,
                "missing": missing_terms,
                "all_content": xml_content
            }
    except zipfile.BadZipFile:
        return {"success": False, "error": "Invalid ZIP/EDDX file"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def verify_create_warehouse_layout(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Load exported result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check EDDX File
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_created = result_data.get('eddx_created_during_task', False)
    eddx_size = result_data.get('eddx_size', 0)

    if eddx_exists and eddx_created and eddx_size > 2000:
        score += 20
        feedback_parts.append("Valid .eddx file created.")
        
        # 3. Check Content (Strings in XML)
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env(metadata['expected_eddx_path'], temp_eddx.name)
            xml_check = check_xml_content(temp_eddx.name, required_text)
            
            if xml_check['success']:
                found = xml_check['found']
                missing = xml_check['missing']
                
                # Scoring based on percentage of required terms found
                term_score = 0
                if len(required_text) > 0:
                    term_score = int((len(found) / len(required_text)) * 40) # Max 40 points for content
                
                score += term_score
                feedback_parts.append(f"Found {len(found)}/{len(required_text)} required labels.")
                if missing:
                    feedback_parts.append(f"Missing labels: {', '.join(missing[:3])}...")
            else:
                feedback_parts.append(f"Content check failed: {xml_check.get('error')}")
        except Exception as e:
            feedback_parts.append(f"Failed to inspect .eddx content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("No valid .eddx file found created during task.")

    # 4. Check PNG Export (10 points)
    png_exists = result_data.get('png_exists', False)
    png_created = result_data.get('png_created_during_task', False)
    png_size = result_data.get('png_size', 0)
    
    if png_exists and png_created and png_size > 5000:
        score += 10
        feedback_parts.append("PNG export created successfully.")
    else:
        feedback_parts.append("PNG export missing or invalid.")

    # 5. VLM Visual Verification (30 points)
    # We verify if the visual layout looks like a warehouse
    final_screenshot = get_final_screenshot(traj)
    
    # If the user exported a PNG, we could prefer that, but 'traj' usually only has screenshots.
    # We'll use the final screenshot of the desktop, which should show EdrawMax open with the diagram,
    # OR if that's ambiguous, we rely on the programmatic check primarily.
    
    if final_screenshot:
        prompt = """
        You are verifying a "Warehouse Layout" diagram task in EdrawMax.
        Look at the screenshot. Does it show a diagram containing:
        1. A top-down floor plan view?
        2. Parallel rectangular rows (representing storage racks)?
        3. A "Loading Dock" area (usually openings on a wall)?
        4. Specific labels like "Zone 1", "Zone 2", "Receiving", or "Rows"?
        
        Respond with JSON: {"is_warehouse_layout": boolean, "elements_visible": list of strings, "confidence": float}
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('is_warehouse_layout', False):
                score += 30
                feedback_parts.append("Visual verification passed: Looks like a warehouse layout.")
            else:
                feedback_parts.append("Visual verification failed: Does not look like a warehouse layout.")
        else:
            # Fallback if VLM fails: give partial points if Programmatic check was very strong
            if score >= 50: 
                score += 10 
                feedback_parts.append("VLM check skipped, added fallback points.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }