#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import struct
import zipfile
import re
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_stl_bbox_and_volume(stl_path):
    """
    Parses a binary STL file to calculate bounding box and approximate volume.
    Returns (min_x, max_x, min_y, max_y, min_z, max_z, volume).
    """
    try:
        with open(stl_path, "rb") as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) < 4:
                return None
            count = struct.unpack('<I', count_bytes)[0]
            
            # Sanity check for huge files
            if count > 1000000: 
                return None
                
            min_x, max_x = float('inf'), float('-inf')
            min_y, max_y = float('inf'), float('-inf')
            min_z, max_z = float('inf'), float('-inf')
            
            signed_volume = 0.0
            
            # Read triangles (50 bytes each: normal(12) + v1(12) + v2(12) + v3(12) + attr(2))
            for _ in range(count):
                data = f.read(50)
                if len(data) < 50:
                    break
                
                # Unpack vertices (floats)
                # Normal (0-11), V1 (12-23), V2 (24-35), V3 (36-47)
                parts = struct.unpack('<12fH', data)
                v1 = (parts[3], parts[4], parts[5])
                v2 = (parts[6], parts[7], parts[8])
                v3 = (parts[9], parts[10], parts[11])
                
                for v in [v1, v2, v3]:
                    if v[0] < min_x: min_x = v[0]
                    if v[0] > max_x: max_x = v[0]
                    if v[1] < min_y: min_y = v[1]
                    if v[1] > max_y: max_y = v[1]
                    if v[2] < min_z: min_z = v[2]
                    if v[2] > max_z: max_z = v[2]

                # Signed tetrahedron volume for this triangle with respect to origin
                # vol = (v1 . (v2 x v3)) / 6
                # Cross product v2 x v3
                cp_x = v2[1]*v3[2] - v2[2]*v3[1]
                cp_y = v2[2]*v3[0] - v2[0]*v3[2]
                cp_z = v2[0]*v3[1] - v2[1]*v3[0]
                # Dot product v1 . cp
                dp = v1[0]*cp_x + v1[1]*cp_y + v1[2]*cp_z
                signed_volume += dp

            volume = abs(signed_volume) / 6.0
            return (min_x, max_x, min_y, max_y, min_z, max_z, volume)
    except Exception as e:
        logger.error(f"STL parse error: {e}")
        return None

def verify_fcstd_content(fcstd_path):
    """
    Checks FCStd (zip) for specific keywords in Document.xml.
    """
    try:
        with zipfile.ZipFile(fcstd_path, 'r') as z:
            # Document.xml contains the object tree
            if 'Document.xml' in z.namelist():
                xml_content = z.read('Document.xml').decode('utf-8', errors='ignore')
                
                has_shapestring = 'ShapeString' in xml_content or 'Draft::ShapeString' in xml_content
                has_robot_text = 'ROBOT-01' in xml_content or 'ROBOT' in xml_content
                has_extrude = 'Part::Extrusion' in xml_content or 'PartDesign::Pad' in xml_content
                
                return {
                    "has_shapestring": has_shapestring,
                    "has_text": has_robot_text,
                    "has_extrude": has_extrude,
                    "valid_zip": True
                }
    except Exception as e:
        logger.error(f"FCStd parse error: {e}")
        return {"valid_zip": False}
    return {"valid_zip": False}

def verify_create_3d_nameplate(traj, env_info, task_info):
    """
    Verifies the creation of a 3D nameplate with extruded text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define verification criteria points
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Creation (30 points)
    fcstd_ok = result_data.get('fcstd_exists') and result_data.get('fcstd_created_during_task')
    stl_ok = result_data.get('stl_exists') and result_data.get('stl_created_during_task')
    
    if fcstd_ok:
        score += 15
        feedback_parts.append("FCStd file created.")
    else:
        feedback_parts.append("FCStd file missing or not created during task.")
        
    if stl_ok:
        score += 15
        feedback_parts.append("STL file created.")
    else:
        feedback_parts.append("STL file missing or not created during task.")

    # 3. Verify STL Geometry (30 points)
    # We copy the STL out to verify dimensions
    stl_valid = False
    if stl_ok:
        temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
        try:
            copy_from_env(metadata['expected_stl_path'], temp_stl.name)
            bbox_vol = parse_stl_bbox_and_volume(temp_stl.name)
            
            if bbox_vol:
                min_x, max_x, min_y, max_y, min_z, max_z, volume = bbox_vol
                dx = max_x - min_x
                dy = max_y - min_y
                dz = max_z - min_z
                
                # Check dimensions (Broad tolerance because of potential origin shifts)
                # Expected: 100 x 30 x 5 (3 base + 2 text)
                x_ok = metadata['bbox_min_x'] <= dx <= metadata['bbox_max_x']
                y_ok = metadata['bbox_min_y'] <= dy <= metadata['bbox_max_y']
                z_ok = metadata['bbox_min_z'] <= dz <= metadata['bbox_max_z']
                
                if x_ok and y_ok and z_ok:
                    score += 20
                    stl_valid = True
                    feedback_parts.append(f"STL dimensions correct ({dx:.1f}x{dy:.1f}x{dz:.1f}mm).")
                else:
                    feedback_parts.append(f"STL dimensions incorrect: {dx:.1f}x{dy:.1f}x{dz:.1f}mm (Expected ~100x30x5).")
                
                # Check volume (Base is 9000, text adds some)
                if metadata['min_volume_mm3'] <= volume <= metadata['max_volume_mm3']:
                    score += 10
                    feedback_parts.append(f"Volume correct ({int(volume)} mm^3).")
                else:
                    feedback_parts.append(f"Volume out of range ({int(volume)} mm^3).")
            else:
                feedback_parts.append("STL file is invalid or empty.")
        except Exception as e:
            feedback_parts.append(f"Error verifying STL: {e}")
        finally:
            if os.path.exists(temp_stl.name):
                os.unlink(temp_stl.name)

    # 4. Verify FCStd Internal Structure (20 points)
    if fcstd_ok:
        temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd')
        try:
            copy_from_env(metadata['expected_fcstd_path'], temp_fcstd.name)
            fcstd_content = verify_fcstd_content(temp_fcstd.name)
            
            if fcstd_content.get('valid_zip'):
                if fcstd_content.get('has_shapestring'):
                    score += 10
                    feedback_parts.append("Found ShapeString object in project.")
                else:
                    feedback_parts.append("No ShapeString object found in project.")
                    
                if fcstd_content.get('has_text'):
                    score += 10
                    feedback_parts.append("Found 'ROBOT-01' text in project.")
                else:
                    feedback_parts.append("Text 'ROBOT-01' not found in project.")
            else:
                feedback_parts.append("FCStd is not a valid zip archive.")
        except Exception as e:
            feedback_parts.append(f"Error verifying FCStd: {e}")
        finally:
            if os.path.exists(temp_fcstd.name):
                os.unlink(temp_fcstd.name)

    # 5. VLM Verification (20 points)
    # Check for visual evidence of the nameplate and text
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + [final_screenshot] if final_screenshot else frames
    
    if all_images and query_vlm:
        prompt = """
        Review these screenshots of a FreeCAD session.
        The user is supposed to create a 3D nameplate with the text 'ROBOT-01' extruded on it.
        
        1. Do you see a 3D object that looks like a rectangular plate?
        2. Do you see the text 'ROBOT-01' or similar on the object?
        3. Does the text appear to be 3D (extruded/raised)?
        
        Return JSON: {"plate_visible": bool, "text_visible": bool, "text_is_3d": bool}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, images=all_images)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('plate_visible'):
                    score += 5
                if parsed.get('text_visible'):
                    score += 10
                    feedback_parts.append("VLM confirms text visibility.")
                if parsed.get('text_is_3d'):
                    score += 5
                    feedback_parts.append("VLM confirms text is 3D.")
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {e}")
    else:
        feedback_parts.append("Skipping VLM check (no images or query function).")

    passed = score >= 60 and fcstd_ok and stl_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }