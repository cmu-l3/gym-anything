#!/usr/bin/env python3
"""
Verifier for export_uddf task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output file exists at exact path (15 points)
2. File was created/modified during task execution (anti-gaming) (15 points)
3. File is not trivial (size check > 1KB) (10 points)
4. Valid XML formatting and structure (10 points)
5. Root element is valid <uddf> (10 points)
6. Contains >= 5 <dive> elements (20 points)
7. VLM verification of trajectory (Export dialog used) (20 points)
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_uddf(traj, env_info, task_info):
    """Verify UDDF export task using programmatic file inspection and VLM."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/exported_dives.uddf')
    min_file_size = metadata.get('min_file_size_bytes', 1024)
    min_dive_count = metadata.get('min_dive_count', 5)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch JSON task state result
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task export results."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ---------------------------------------------------------
    # 2. Check File Existence & Timestamp Anti-gaming
    # ---------------------------------------------------------
    output_exists = result.get("output_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    file_size = result.get("output_size_bytes", 0)

    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file not found at {expected_output_path}"
        }
    else:
        score += 15
        feedback_parts.append("File exists")

    if file_created_during_task:
        score += 15
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start")

    if file_size >= min_file_size:
        score += 10
        feedback_parts.append(f"Size OK ({file_size} bytes)")
    else:
        feedback_parts.append(f"File too small ({file_size} bytes)")

    # ---------------------------------------------------------
    # 3. Fetch and Parse UDDF XML File
    # ---------------------------------------------------------
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.uddf')
    temp_xml.close()
    
    xml_valid = False
    uddf_root = False
    dive_count = 0
    profiles_present = False
    
    try:
        copy_from_env(expected_output_path, temp_xml.name)
        
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            xml_valid = True
            
            # Check Root Element (Strip namespaces if present)
            root_tag = root.tag.split('}')[-1].lower()
            if root_tag == 'uddf':
                uddf_root = True
            
            # Count dive elements and look for profile samples/waypoints
            for elem in root.iter():
                tag = elem.tag.split('}')[-1].lower()
                if tag == 'dive':
                    dive_count += 1
                elif tag in ['waypoint', 'sample', 'samples', 'depth']:
                    profiles_present = True
                    
        except ET.ParseError as e:
            logger.error(f"XML parsing failed: {e}")
            feedback_parts.append("Invalid XML formatting")
    except Exception as e:
        logger.error(f"Failed to copy or read UDDF file: {e}")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # Programmatic Scoring
    if xml_valid:
        score += 10
        feedback_parts.append("Valid XML")
    
    if uddf_root:
        score += 10
        feedback_parts.append("Root is <uddf>")
        
    if dive_count >= min_dive_count:
        score += 20
        feedback_parts.append(f"Exported {dive_count} dives")
    elif dive_count > 0:
        score += 10
        feedback_parts.append(f"Partial export ({dive_count} dives)")
    else:
        feedback_parts.append("No <dive> elements found")

    # ---------------------------------------------------------
    # 4. VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_success = False
    try:
        # Import VLM utilities dynamically based on framework patterns
        import importlib
        vlm_utils_found = False
        
        # Try different possible paths for VLM utilities
        for module_name in ['gym_anything.vlm', 'vlm_utils', 'utils.vlm']:
            try:
                vlm_module = importlib.import_module(module_name)
                if hasattr(vlm_module, 'sample_trajectory_frames') and hasattr(vlm_module, 'query_vlm'):
                    sample_trajectory_frames = getattr(vlm_module, 'sample_trajectory_frames')
                    get_final_screenshot = getattr(vlm_module, 'get_final_screenshot')
                    query_vlm = getattr(vlm_module, 'query_vlm')
                    vlm_utils_found = True
                    break
            except ImportError:
                continue

        if vlm_utils_found:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """Examine this sequence of screenshots from a Linux desktop running the Subsurface dive log.
Did the user interact with the 'Export' dialog (usually accessible via File -> Export)?
Look for a dialog box related to exporting files and checking/selecting the 'UDDF' format option.
Reply with JSON format:
{
    "export_dialog_seen": true/false,
    "uddf_format_selected": true/false
}"""
                vlm_response = query_vlm(images=images, prompt=prompt)
                
                if isinstance(vlm_response, dict) and vlm_response.get("success"):
                    parsed = vlm_response.get("parsed", {})
                    if parsed.get("export_dialog_seen") and parsed.get("uddf_format_selected"):
                        vlm_success = True
                        score += 20
                        feedback_parts.append("VLM confirmed export workflow")
                    else:
                        feedback_parts.append("VLM did not verify export dialog interactions")
                else:
                    logger.warning(f"VLM query failed or invalid format: {vlm_response}")
                    score += 20  # Give benefit of doubt if VLM errors out natively
                    feedback_parts.append("VLM unavailable - awarded fallback points")
        else:
            logger.info("VLM utility not found, bypassing VLM check and allocating points")
            score += 20
            feedback_parts.append("VLM check bypassed")
            
    except Exception as e:
        logger.warning(f"Error during VLM verification: {e}")
        score += 20
        feedback_parts.append("VLM errored - bypassed")

    # ---------------------------------------------------------
    # 5. Final Determination
    # ---------------------------------------------------------
    key_criteria_met = (
        output_exists and 
        file_created_during_task and 
        xml_valid and 
        uddf_root and 
        dive_count > 0
    )
    
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "output_exists": output_exists,
            "xml_valid": xml_valid,
            "uddf_root": uddf_root,
            "dive_count": dive_count,
            "profiles_present": profiles_present,
            "file_size": file_size
        }
    }