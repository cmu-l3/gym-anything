#!/usr/bin/env python3
"""
Verifier for location_disambiguation@1 task.

TASK: Search for 'Cambridge', disambiguate to Cambridge MA, navigate to Harvard Yard,
create a placemark with coordinate documentation, and export as KML.

VERIFICATION STRATEGY:
1. KML file exists at correct path (10 points)
2. Valid KML structure with Placemark (10 points)
3. Placemark within Cambridge, MA bounds (25 points) - KEY CRITERION
4. Placemark near Harvard Yard (15 points)
5. Correct placemark name (10 points)
6. Coordinates documented in description (15 points)
7. File created during task window (anti-gaming) (5 points)
8. VLM trajectory verification - search disambiguation evidence (10 points)

Pass threshold: 70 points with Cambridge MA criterion met
"""

import json
import tempfile
import os
import re
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_location_disambiguation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the location disambiguation task was completed correctly.
    
    Uses multiple independent signals:
    1. Programmatic KML file analysis
    2. Coordinate bounds checking
    3. VLM trajectory verification for process evidence
    """
    
    # Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available from environment"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/cambridge_research.kml')
    lat_min = metadata.get('latitude_min', 42.350)
    lat_max = metadata.get('latitude_max', 42.400)
    lon_min = metadata.get('longitude_min', -71.150)
    lon_max = metadata.get('longitude_max', -71.080)
    harvard_lat_min = metadata.get('harvard_lat_min', 42.370)
    harvard_lat_max = metadata.get('harvard_lat_max', 42.380)
    harvard_lon_min = metadata.get('harvard_lon_min', -71.125)
    harvard_lon_max = metadata.get('harvard_lon_max', -71.110)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    result_data = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load task result: {e}")
        details['result_loaded'] = False
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Try to copy and parse KML file directly
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output_path, temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        details['kml_copied'] = True
    except Exception as e:
        logger.warning(f"Could not copy KML file: {e}")
        details['kml_copied'] = False
        details['kml_copy_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    kml_exists = False
    if result_data and result_data.get('kml_file', {}).get('exists', False):
        kml_exists = True
    elif kml_content:
        kml_exists = True
    
    if kml_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['kml_exists'] = True
    else:
        feedback_parts.append("❌ KML file NOT found")
        details['kml_exists'] = False
        # Early exit if no KML file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Valid KML structure with Placemark (10 points)
    # ================================================================
    placemark_found = False
    placemark_name = ""
    placemark_lat = 0.0
    placemark_lon = 0.0
    placemark_description = ""
    
    # Try to get from result_data first
    if result_data and result_data.get('placemark'):
        pm = result_data['placemark']
        placemark_name = pm.get('name', '')
        placemark_lat = pm.get('latitude', 0)
        placemark_lon = pm.get('longitude', 0)
        placemark_description = pm.get('description', '')
        if placemark_lat != 0 or placemark_lon != 0:
            placemark_found = True
    
    # Parse KML directly if we have content and didn't get coords from result
    if kml_content and not placemark_found:
        try:
            import xml.etree.ElementTree as ET
            root = ET.fromstring(kml_content)
            
            # Handle KML namespace
            ns = {'kml': 'http://www.opengis.net/kml/2.2'}
            
            placemark = root.find('.//{http://www.opengis.net/kml/2.2}Placemark')
            if placemark is None:
                placemark = root.find('.//Placemark')
            
            if placemark is not None:
                placemark_found = True
                
                # Get name
                name_elem = placemark.find('{http://www.opengis.net/kml/2.2}name')
                if name_elem is None:
                    name_elem = placemark.find('name')
                if name_elem is not None and name_elem.text:
                    placemark_name = name_elem.text
                
                # Get description
                desc_elem = placemark.find('{http://www.opengis.net/kml/2.2}description')
                if desc_elem is None:
                    desc_elem = placemark.find('description')
                if desc_elem is not None and desc_elem.text:
                    placemark_description = desc_elem.text
                
                # Get coordinates
                coords_elem = placemark.find('.//{http://www.opengis.net/kml/2.2}coordinates')
                if coords_elem is None:
                    coords_elem = placemark.find('.//coordinates')
                if coords_elem is not None and coords_elem.text:
                    parts = coords_elem.text.strip().split(',')
                    if len(parts) >= 2:
                        placemark_lon = float(parts[0])
                        placemark_lat = float(parts[1])
        except Exception as e:
            logger.warning(f"KML parsing error: {e}")
            details['kml_parse_error'] = str(e)
    
    if placemark_found:
        score += 10
        feedback_parts.append("✅ Valid KML with Placemark")
        details['placemark_found'] = True
    else:
        feedback_parts.append("❌ No valid Placemark in KML")
        details['placemark_found'] = False
    
    details['placemark_name'] = placemark_name
    details['placemark_lat'] = placemark_lat
    details['placemark_lon'] = placemark_lon
    
    # ================================================================
    # CRITERION 3: Coordinates within Cambridge, MA bounds (25 points)
    # THIS IS THE KEY CRITERION
    # ================================================================
    in_cambridge_ma = False
    if placemark_lat != 0 and placemark_lon != 0:
        in_cambridge_ma = (
            lat_min <= placemark_lat <= lat_max and
            lon_min <= placemark_lon <= lon_max
        )
    
    if in_cambridge_ma:
        score += 25
        feedback_parts.append(f"✅ Location in Cambridge, MA ({placemark_lat:.4f}, {placemark_lon:.4f})")
        details['in_cambridge_ma'] = True
    else:
        feedback_parts.append(f"❌ Location NOT in Cambridge, MA bounds ({placemark_lat:.4f}, {placemark_lon:.4f})")
        details['in_cambridge_ma'] = False
    
    # ================================================================
    # CRITERION 4: Near Harvard Yard (15 points)
    # ================================================================
    near_harvard = False
    if placemark_lat != 0 and placemark_lon != 0:
        near_harvard = (
            harvard_lat_min <= placemark_lat <= harvard_lat_max and
            harvard_lon_min <= placemark_lon <= harvard_lon_max
        )
    
    if near_harvard:
        score += 15
        feedback_parts.append("✅ Near Harvard Yard target area")
        details['near_harvard'] = True
    elif in_cambridge_ma:
        # Partial credit for being in Cambridge but not near Harvard
        score += 5
        feedback_parts.append("⚠️ In Cambridge but not near Harvard Yard")
        details['near_harvard'] = False
    else:
        feedback_parts.append("❌ Not near Harvard Yard")
        details['near_harvard'] = False
    
    # ================================================================
    # CRITERION 5: Correct placemark name (10 points)
    # ================================================================
    name_correct = False
    if placemark_name:
        name_lower = placemark_name.lower()
        # Check for key components
        has_cambridge = 'cambridge' in name_lower
        has_ma = 'ma' in name_lower or 'massachusetts' in name_lower
        has_research = 'research' in name_lower
        
        if has_cambridge and (has_ma or has_research):
            name_correct = True
            score += 10
            feedback_parts.append(f"✅ Correct placemark name: '{placemark_name}'")
        else:
            score += 3  # Partial credit for any name
            feedback_parts.append(f"⚠️ Placemark name incomplete: '{placemark_name}'")
    else:
        feedback_parts.append("❌ No placemark name")
    
    details['name_correct'] = name_correct
    
    # ================================================================
    # CRITERION 6: Coordinates documented in description (15 points)
    # ================================================================
    coords_documented = False
    coords_match = False
    
    if placemark_description:
        # Look for coordinate pattern in description
        coord_pattern = r'[Cc]oordinates?\s*:?\s*(-?\d+\.?\d*)\s*[,\s]\s*(-?\d+\.?\d*)'
        match = re.search(coord_pattern, placemark_description)
        
        if match:
            coords_documented = True
            score += 10
            
            # Check if documented coords match actual coords
            try:
                doc_val1 = float(match.group(1))
                doc_val2 = float(match.group(2))
                
                tolerance = 0.01
                # Could be lat,lon or lon,lat format
                if ((abs(doc_val1 - placemark_lat) < tolerance and abs(doc_val2 - placemark_lon) < tolerance) or
                    (abs(doc_val1 - placemark_lon) < tolerance and abs(doc_val2 - placemark_lat) < tolerance)):
                    coords_match = True
                    score += 5
                    feedback_parts.append("✅ Coordinates documented and match placemark")
                else:
                    feedback_parts.append("⚠️ Coordinates documented but don't match")
            except:
                feedback_parts.append("⚠️ Coordinates documented (parse issue)")
        else:
            feedback_parts.append("❌ Coordinates not documented in description")
    else:
        feedback_parts.append("❌ No description in placemark")
    
    details['coords_documented'] = coords_documented
    details['coords_match'] = coords_match
    
    # ================================================================
    # CRITERION 7: File created during task (anti-gaming) (5 points)
    # ================================================================
    created_during_task = False
    if result_data:
        created_during_task = result_data.get('kml_file', {}).get('created_during_task', False)
    
    if created_during_task:
        score += 5
        feedback_parts.append("✅ File created during task window")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠️ File creation time unverified")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 8: VLM trajectory verification (10 points)
    # Check for search disambiguation evidence in trajectory
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample multiple frames from trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if trajectory_frames or final_frame:
                frames_to_check = trajectory_frames if trajectory_frames else []
                if final_frame and final_frame not in frames_to_check:
                    frames_to_check.append(final_frame)
                
                if frames_to_check:
                    vlm_prompt = """Analyze these screenshots from a Google Earth Pro session.

The task was to:
1. Search for "Cambridge" and select Cambridge, Massachusetts (not UK or other)
2. Navigate to Harvard Yard area
3. Create and save a placemark

Look at the sequence and determine:
1. SEARCH_VISIBLE: Is a search box or search results panel visible in any frame?
2. DISAMBIGUATION_EVIDENCE: Are there multiple search results visible (indicating disambiguation)?
3. CAMBRIDGE_MA_VIEW: Does any frame show Cambridge, MA area (urban, university buildings, Charles River)?
4. PLACEMARK_CREATED: Is there evidence of placemark creation dialog or placemark icon?
5. KML_EXPORT: Is there evidence of save/export dialog?

Respond in JSON:
{
    "search_visible": true/false,
    "disambiguation_evidence": true/false,
    "cambridge_ma_view": true/false,
    "placemark_created": true/false,
    "kml_export": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the sequence"
}"""
                    
                    vlm_result = query_vlm(
                        prompt=vlm_prompt,
                        images=frames_to_check
                    )
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_result'] = parsed
                        
                        # Score based on VLM findings
                        vlm_criteria = 0
                        if parsed.get('search_visible'):
                            vlm_criteria += 1
                        if parsed.get('disambiguation_evidence'):
                            vlm_criteria += 1
                        if parsed.get('cambridge_ma_view'):
                            vlm_criteria += 1
                        if parsed.get('placemark_created'):
                            vlm_criteria += 1
                        if parsed.get('kml_export'):
                            vlm_criteria += 1
                        
                        # Award points based on criteria met
                        if vlm_criteria >= 3:
                            vlm_score = 10
                            feedback_parts.append("✅ VLM: Workflow evidence confirmed")
                        elif vlm_criteria >= 2:
                            vlm_score = 6
                            feedback_parts.append("⚠️ VLM: Partial workflow evidence")
                        elif vlm_criteria >= 1:
                            vlm_score = 3
                            feedback_parts.append("⚠️ VLM: Minimal workflow evidence")
                        else:
                            feedback_parts.append("❌ VLM: No workflow evidence")
                    else:
                        feedback_parts.append("⚠️ VLM verification inconclusive")
                        details['vlm_error'] = vlm_result.get('error', 'Unknown')
        except ImportError:
            logger.warning("VLM utilities not available")
            feedback_parts.append("⚠️ VLM verification skipped (utilities unavailable)")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
            details['vlm_exception'] = str(e)
    else:
        feedback_parts.append("⚠️ VLM verification skipped (no VLM or trajectory)")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    total_score = min(score, 100)  # Cap at 100
    
    # Key criterion: Must have location in Cambridge, MA to pass
    key_criteria_met = in_cambridge_ma and kml_exists
    passed = total_score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": details
    }