#!/usr/bin/env python3
"""
Verifier for Historical Marker Documentation task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists (10 points)
2. File created during task - anti-gaming (10 points)
3. Valid KML structure with Placemark (10 points)
4. Correct placemark name (10 points)
5. Coordinates in correct range (20 points)
6. Bold header present in description (15 points)
7. At least 3 bullet points (15 points)
8. Valid hyperlink to NPS (10 points)

VLM verification using TRAJECTORY frames:
- Verify agent navigated to Gettysburg
- Verify placemark dialog was used
- Verify file save operation occurred

Pass threshold: 70 points AND coordinates criterion met
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_historical_marker_documentation(traj, env_info, task_info):
    """
    Verify that the historical marker placemark was created correctly.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    - Programmatic KML file analysis
    - Timestamp verification
    - VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    # Get metadata from task_info
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/gettysburg_marker.kml')
    expected_name = metadata.get('expected_placemark_name', 'Gettysburg Battlefield Visitor Center')
    expected_lat = metadata.get('expected_latitude', 39.8133)
    expected_lon = metadata.get('expected_longitude', -77.2308)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.02)
    min_bullets = metadata.get('min_bullet_points', 3)
    min_file_size = metadata.get('min_file_size_bytes', 500)
    
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info(f"Loaded task result: {result}")
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
        # Continue with empty result - will verify via KML file directly
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Copy and analyze KML file directly
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output_path, temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8') as f:
            kml_content = f.read()
        details['kml_file_copied'] = True
        details['kml_size'] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        details['kml_file_copied'] = False
        details['kml_copy_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False) or (kml_content is not None)
    details['output_exists'] = output_exists
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file not found")
        # Cannot continue without file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - anti-gaming
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    details['file_created_during_task'] = file_created_during_task
    details['task_start'] = task_start
    details['output_mtime'] = output_mtime
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
    elif output_mtime > 0 and task_start > 0:
        # Double-check timing
        if output_mtime >= task_start:
            score += 10
            feedback_parts.append("✅ File timestamp valid")
        else:
            score += 3
            feedback_parts.append("⚠️ File may predate task")
    else:
        score += 5  # Partial credit if timing unclear
        feedback_parts.append("⚠️ Could not verify file timing")
    
    # ================================================================
    # Parse KML content if we have it
    # ================================================================
    placemark_name = None
    latitude = None
    longitude = None
    description = None
    has_bold = False
    bullet_count = 0
    has_link = False
    
    if kml_content:
        try:
            import xml.etree.ElementTree as ET
            root = ET.fromstring(kml_content)
            
            # Define namespaces
            ns = {'kml': 'http://www.opengis.net/kml/2.2'}
            
            # Find Placemark
            placemark = root.find('.//kml:Placemark', ns)
            if placemark is None:
                placemark = root.find('.//Placemark')
            
            if placemark is not None:
                # Get name
                name_elem = placemark.find('kml:name', ns)
                if name_elem is None:
                    name_elem = placemark.find('name')
                if name_elem is not None and name_elem.text:
                    placemark_name = name_elem.text.strip()
                
                # Get coordinates
                coord_elem = placemark.find('.//kml:coordinates', ns)
                if coord_elem is None:
                    coord_elem = placemark.find('.//coordinates')
                if coord_elem is not None and coord_elem.text:
                    coords = coord_elem.text.strip()
                    parts = coords.split(',')
                    if len(parts) >= 2:
                        try:
                            longitude = float(parts[0].strip())
                            latitude = float(parts[1].strip())
                        except ValueError:
                            pass
                
                # Get description
                desc_elem = placemark.find('kml:description', ns)
                if desc_elem is None:
                    desc_elem = placemark.find('description')
                if desc_elem is not None and desc_elem.text:
                    description = desc_elem.text
                    
                    # Check for bold
                    if re.search(r'<b[^>]*>|<strong[^>]*>', description, re.IGNORECASE):
                        has_bold = True
                    
                    # Count bullets
                    li_count = len(re.findall(r'<li[^>]*>', description, re.IGNORECASE))
                    if li_count > 0:
                        bullet_count = li_count
                    else:
                        # Count bullet characters and list markers
                        bullet_chars = ['•', '◦', '▪', '▸', '●', '○']
                        bullet_count = sum(description.count(char) for char in bullet_chars)
                        bullet_count += len(re.findall(r'^\s*[-*]\s+', description, re.MULTILINE))
                    
                    # Check for hyperlink
                    if re.search(r'<a[^>]+href=["\'][^"\']*nps\.gov[^"\']*["\']', description, re.IGNORECASE):
                        has_link = True
                    elif 'nps.gov/gett' in description.lower():
                        has_link = True
                        
        except Exception as e:
            logger.warning(f"Error parsing KML: {e}")
    
    # Use result JSON values if direct parsing failed
    if placemark_name is None:
        placemark_name = result.get('placemark_name', '')
    if latitude is None:
        latitude = result.get('latitude')
    if longitude is None:
        longitude = result.get('longitude')
    if not has_bold:
        has_bold = result.get('has_bold_header', False)
    if bullet_count == 0:
        bullet_count = result.get('bullet_count', 0)
    if not has_link:
        has_link = result.get('has_hyperlink', False)
    
    details['placemark_name'] = placemark_name
    details['latitude'] = latitude
    details['longitude'] = longitude
    details['has_bold'] = has_bold
    details['bullet_count'] = bullet_count
    details['has_link'] = has_link
    
    # ================================================================
    # CRITERION 3: Valid KML with Placemark (10 points)
    # ================================================================
    kml_valid = result.get('kml_valid', False) or (kml_content is not None)
    has_placemark = result.get('has_placemark', False) or (placemark_name is not None)
    
    if kml_valid and has_placemark:
        score += 10
        feedback_parts.append("✅ Valid KML with Placemark")
    elif kml_valid:
        score += 5
        feedback_parts.append("⚠️ Valid KML but no Placemark found")
    else:
        feedback_parts.append("❌ Invalid KML structure")
    
    # ================================================================
    # CRITERION 4: Correct placemark name (10 points)
    # ================================================================
    name_correct = False
    if placemark_name:
        # Check if name contains key parts
        name_lower = placemark_name.lower()
        expected_lower = expected_name.lower()
        if expected_lower in name_lower or name_lower in expected_lower:
            name_correct = True
        elif 'gettysburg' in name_lower and ('visitor' in name_lower or 'battlefield' in name_lower):
            name_correct = True
    
    details['name_correct'] = name_correct
    
    if name_correct:
        score += 10
        feedback_parts.append(f"✅ Correct placemark name: '{placemark_name}'")
    elif placemark_name:
        score += 3
        feedback_parts.append(f"⚠️ Name mismatch: '{placemark_name}' (expected: '{expected_name}')")
    else:
        feedback_parts.append("❌ No placemark name found")
    
    # ================================================================
    # CRITERION 5: Coordinates in correct range (20 points)
    # ================================================================
    coords_correct = False
    if latitude is not None and longitude is not None:
        lat_diff = abs(latitude - expected_lat)
        lon_diff = abs(longitude - expected_lon)
        
        details['lat_diff'] = lat_diff
        details['lon_diff'] = lon_diff
        
        if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
            coords_correct = True
            score += 20
            feedback_parts.append(f"✅ Coordinates correct ({latitude:.4f}, {longitude:.4f})")
        elif lat_diff <= coord_tolerance * 2 and lon_diff <= coord_tolerance * 2:
            score += 12
            feedback_parts.append(f"⚠️ Coordinates close ({latitude:.4f}, {longitude:.4f})")
        else:
            feedback_parts.append(f"❌ Coordinates incorrect ({latitude:.4f}, {longitude:.4f})")
    else:
        feedback_parts.append("❌ Could not extract coordinates")
    
    details['coords_correct'] = coords_correct
    
    # ================================================================
    # CRITERION 6: Bold header present (15 points)
    # ================================================================
    if has_bold:
        score += 15
        feedback_parts.append("✅ Bold header present")
    else:
        feedback_parts.append("❌ No bold header found")
    
    # ================================================================
    # CRITERION 7: At least 3 bullet points (15 points)
    # ================================================================
    if bullet_count >= min_bullets:
        score += 15
        feedback_parts.append(f"✅ {bullet_count} bullet points found")
    elif bullet_count > 0:
        partial_score = int(15 * bullet_count / min_bullets)
        score += partial_score
        feedback_parts.append(f"⚠️ Only {bullet_count}/{min_bullets} bullet points")
    else:
        feedback_parts.append(f"❌ No bullet points found (need {min_bullets})")
    
    # ================================================================
    # CRITERION 8: Valid hyperlink to NPS (10 points)
    # ================================================================
    if has_link:
        score += 10
        feedback_parts.append("✅ Hyperlink to NPS present")
    else:
        feedback_parts.append("❌ No hyperlink to nps.gov found")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation)
    # ================================================================
    vlm_verified = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import trajectory frame sampling
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying if an agent completed a task in Google Earth Pro.

TASK: Create a placemark at Gettysburg National Military Park and export it as KML.

Analyze these screenshots from the agent's session and determine:
1. Did the agent navigate to the Gettysburg, Pennsylvania area (or search for it)?
2. Did the agent open a placemark creation dialog?
3. Did the agent appear to enter placemark details (name, description)?
4. Did the agent save/export a file?

Look for:
- Google Earth showing Pennsylvania/Gettysburg area
- Add Placemark dialog or similar interface
- File save dialog
- Gettysburg landmarks visible

Respond in JSON:
{
    "navigated_to_gettysburg": true/false,
    "placemark_dialog_used": true/false,
    "entered_details": true/false,
    "file_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you observe in the screenshots"
}"""
                
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_frames[:6]  # Limit to 6 frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Count VLM criteria met
                    vlm_criteria = sum([
                        parsed.get('navigated_to_gettysburg', False),
                        parsed.get('placemark_dialog_used', False),
                        parsed.get('entered_details', False),
                        parsed.get('file_saved', False)
                    ])
                    
                    if vlm_criteria >= 3:
                        vlm_verified = True
                        feedback_parts.append(f"✅ VLM: Workflow verified ({vlm_criteria}/4 steps)")
                    elif vlm_criteria >= 2:
                        feedback_parts.append(f"⚠️ VLM: Partial workflow ({vlm_criteria}/4 steps)")
                    else:
                        feedback_parts.append(f"⚠️ VLM: Limited workflow evidence ({vlm_criteria}/4)")
                else:
                    details['vlm_error'] = vlm_result.get('error', 'Unknown error')
                    feedback_parts.append("⚠️ VLM verification unavailable")
        except ImportError:
            feedback_parts.append("⚠️ VLM module not available")
        except Exception as e:
            details['vlm_exception'] = str(e)
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    
    details['vlm_verified'] = vlm_verified
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Must have at least 70 points AND coordinates must be correct
    passed = score >= 70 and coords_correct
    
    details['final_score'] = score
    details['max_score'] = max_score
    details['passed'] = passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }