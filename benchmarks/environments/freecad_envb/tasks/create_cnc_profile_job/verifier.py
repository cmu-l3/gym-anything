#!/usr/bin/env python3
"""
Verifier for create_cnc_profile_job task.

Criteria:
1. T8_housing_cnc.FCStd exists and is a valid FreeCAD file.
2. The FCStd file contains a Path::FeaturePython object (The Job).
3. The FCStd file contains a Profile/Contour operation.
4. T8_housing.nc (G-code) exists and contains valid G-code commands.
5. G-code coordinates match the approximate dimensions of the T8 bracket.
"""

import json
import os
import tempfile
import zipfile
import re
import logging
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cnc_profile_job(traj, env_info, task_info):
    """
    Verify CNC Job creation and G-code export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fcstd = metadata.get('expected_fcstd', '/home/ga/Documents/FreeCAD/T8_housing_cnc.FCStd')
    expected_gcode = metadata.get('expected_gcode', '/home/ga/Documents/FreeCAD/T8_housing.nc')

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify FCStd File Structure (Job and Profile existence)
    if result.get('fcstd_exists') and result.get('fcstd_created_during_task'):
        score += 10
        feedback_parts.append("Project file saved")
        
        # Analyze FCStd content (it's a zip file containing Document.xml)
        temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd')
        try:
            copy_from_env(expected_fcstd, temp_fcstd.name)
            
            if zipfile.is_zipfile(temp_fcstd.name):
                with zipfile.ZipFile(temp_fcstd.name, 'r') as z:
                    if 'Document.xml' in z.namelist():
                        with z.open('Document.xml') as xml_file:
                            tree = ElementTree.parse(xml_file)
                            root = tree.getroot()
                            
                            # Search for objects
                            # Path Job is usually Type="Path::FeaturePython" and has properties like "Job"
                            # Profile is usually Type="Path::FeaturePython" and name often contains "Profile" or "Contour"
                            
                            objects = root.findall(".//Object")
                            has_job = False
                            has_profile = False
                            
                            for obj in objects:
                                obj_type = obj.get('Type', '')
                                obj_name = obj.get('Name', '')
                                
                                # Check for Path objects
                                if 'Path::Feature' in obj_type:
                                    # Very naive check for Job - usually the container or has specific properties
                                    # But simply finding Path objects is a good sign
                                    
                                    # In FreeCAD Path, the Job object usually has a Label "Job" by default
                                    if "Job" in obj_name or "Job" in obj.get('Label', ''):
                                        has_job = True
                                    
                                    # Check for Profile
                                    if "Profile" in obj_name or "Contour" in obj_name or "Profile" in obj.get('Label', ''):
                                        has_profile = True
                            
                            if has_job:
                                score += 25
                                feedback_parts.append("Path Job found in project")
                            else:
                                feedback_parts.append("No Path Job object identified in project")

                            if has_profile:
                                score += 25
                                feedback_parts.append("Profile operation found in project")
                            else:
                                feedback_parts.append("No Profile operation identified")
                    else:
                        feedback_parts.append("Invalid FCStd: missing Document.xml")
            else:
                feedback_parts.append("Saved file is not a valid ZIP/FCStd")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing FCStd: {e}")
        finally:
            if os.path.exists(temp_fcstd.name):
                os.unlink(temp_fcstd.name)
    else:
        feedback_parts.append("Project file not saved or not created during task")

    # 3. Verify G-code Content
    if result.get('gcode_exists') and result.get('gcode_created_during_task'):
        score += 10
        feedback_parts.append("G-code file exported")
        
        temp_gcode = tempfile.NamedTemporaryFile(delete=False, suffix='.nc')
        try:
            copy_from_env(expected_gcode, temp_gcode.name)
            
            with open(temp_gcode.name, 'r', errors='ignore') as f:
                content = f.read()
                
            # Check length
            if len(content.splitlines()) > 20:
                score += 10
                feedback_parts.append("G-code length OK")
                
                # Check for coordinates
                x_coords = [float(x) for x in re.findall(r'[X]([\-0-9\.]+)', content)]
                y_coords = [float(y) for y in re.findall(r'[Y]([\-0-9\.]+)', content)]
                
                if x_coords and y_coords:
                    x_range = max(x_coords) - min(x_coords)
                    y_range = max(y_coords) - min(y_coords)
                    
                    # T8 bracket is roughly 40-50mm wide
                    # If ranges are tiny (< 5mm), it likely machined nothing
                    if x_range > 20 and y_range > 20:
                        score += 20
                        feedback_parts.append(f"Toolpath dimensions valid ({x_range:.1f}x{y_range:.1f}mm)")
                    else:
                        feedback_parts.append(f"Toolpath too small ({x_range:.1f}x{y_range:.1f}mm) - likely empty")
                else:
                    feedback_parts.append("No X/Y coordinates found in G-code")
            else:
                feedback_parts.append("G-code file too short")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing G-code: {e}")
        finally:
            if os.path.exists(temp_gcode.name):
                os.unlink(temp_gcode.name)
    else:
        feedback_parts.append("G-code file not exported or not created during task")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }