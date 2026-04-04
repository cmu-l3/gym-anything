#!/usr/bin/env python3
"""
Verifier for lowest_elevation_badwater task.

Task: Navigate to Badwater Basin in Death Valley and create a documented 
placemark with elevation information, then export to KML.

VERIFICATION STRATEGY:
1. KML file exists and was created during task (anti-gaming)
2. Valid KML format with placemark
3. Placemark name contains relevant keywords
4. Coordinates within tolerance of Badwater Basin
5. Description contains elevation documentation
6. VLM trajectory verification (shows navigation + placemark creation)

Uses copy_from_env (NOT exec_in_env) and trajectory frames.
"""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_lowest_elevation_badwater(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that agent navigated to Badwater Basin and created documented placemark.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    # Get metadata with expected values
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/badwater_basin.kml')
    target_lat = metadata.get('target_latitude', 36.2291)
    target_lon = metadata.get('target_longitude', -116.7677)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.02)
    expected_elev_m = metadata.get('elevation_meters', -86)
    elev_tolerance = metadata.get('elevation_tolerance_m', 15)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_json'] = result
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"❌ Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ KML file exists (+15)")
    else:
        feedback_parts.append("❌ KML file not found at expected path")
        # Early exit - can't verify anything else without file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (15 points)
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    
    if file_created:
        score += 15
        feedback_parts.append("✅ File created during task (+15)")
    else:
        feedback_parts.append("⚠️ File may predate task (+0)")
        # Don't fail completely, but this is suspicious
    
    # ================================================================
    # CRITERION 3: Valid KML format (10 points)
    # ================================================================
    valid_kml = result.get('valid_kml', False)
    
    if valid_kml:
        score += 10
        feedback_parts.append("✅ Valid KML format (+10)")
    else:
        feedback_parts.append("❌ Invalid KML format (+0)")
    
    # ================================================================
    # STEP 2: Copy and parse the actual KML file for detailed checks
    # ================================================================
    kml_data = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output_path, temp_kml.name)
        kml_data = parse_kml_file(temp_kml.name)
        details['kml_parsed'] = kml_data
    except Exception as e:
        logger.warning(f"Could not parse KML file: {e}")
        details['kml_parse_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 4: Placemark name contains relevant keywords (10 points)
    # ================================================================
    placemark_name = result.get('placemark_name', '') or ''
    if kml_data and kml_data.get('name'):
        placemark_name = kml_data['name']
    
    name_lower = placemark_name.lower()
    name_keywords = ['badwater', 'lowest', 'death valley', 'low point', 'below sea']
    name_match = any(kw in name_lower for kw in name_keywords)
    
    if name_match:
        score += 10
        feedback_parts.append(f"✅ Relevant placemark name: '{placemark_name[:40]}' (+10)")
    elif placemark_name:
        score += 3
        feedback_parts.append(f"⚠️ Placemark name not descriptive: '{placemark_name[:30]}' (+3)")
    else:
        feedback_parts.append("❌ No placemark name found (+0)")
    
    # ================================================================
    # CRITERION 5: Coordinates within tolerance (20 points)
    # ================================================================
    lat, lon = None, None
    
    # Try to get coordinates from parsed KML
    if kml_data and kml_data.get('latitude') is not None:
        lat = kml_data['latitude']
        lon = kml_data['longitude']
    else:
        # Fallback: parse from result JSON
        coords_str = result.get('coordinates', '')
        if coords_str:
            lat, lon = parse_coordinates_string(coords_str)
    
    coord_score, coord_msg = check_coordinates(lat, lon, target_lat, target_lon, coord_tolerance)
    score += coord_score
    feedback_parts.append(coord_msg)
    details['parsed_lat'] = lat
    details['parsed_lon'] = lon
    
    # ================================================================
    # CRITERION 6: Description contains elevation (15 points)
    # ================================================================
    description = result.get('description', '') or ''
    if kml_data and kml_data.get('description'):
        description = kml_data['description']
    
    elev_found, elev_score, elev_msg = check_elevation_in_description(description, expected_elev_m, elev_tolerance)
    score += elev_score
    feedback_parts.append(elev_msg)
    details['description_excerpt'] = description[:200] if description else ''
    
    # ================================================================
    # CRITERION 7: Below sea level indication (10 points)
    # ================================================================
    below_sea_indicators = ['below sea level', 'below sea', 'negative', 'under sea', '-8', '-28', '-27']
    desc_lower = description.lower()
    
    below_sea_mentioned = any(ind in desc_lower for ind in below_sea_indicators)
    if below_sea_mentioned or (elev_found and '-' in description):
        score += 10
        feedback_parts.append("✅ Below sea level indicated (+10)")
    elif elev_found:
        score += 5
        feedback_parts.append("⚠️ Elevation found but sea level not explicitly mentioned (+5)")
    else:
        feedback_parts.append("❌ Below sea level not documented (+0)")
    
    # ================================================================
    # CRITERION 8: VLM trajectory verification (5 points)
    # ================================================================
    vlm_score, vlm_msg = verify_via_vlm_trajectory(traj, query_vlm)
    score += vlm_score
    feedback_parts.append(vlm_msg)
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria: coordinates must be reasonably correct AND some documentation
    key_criteria_met = (coord_score >= 12) and (elev_score > 0 or below_sea_mentioned)
    passed = score >= 70 and key_criteria_met
    
    # Additional details
    details['total_score'] = score
    details['key_criteria_met'] = key_criteria_met
    details['coord_score'] = coord_score
    details['elev_score'] = elev_score
    
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"✅ PASSED (Score: {score}/100) | " + feedback
    else:
        reasons = []
        if coord_score < 12:
            reasons.append("coordinates not accurate enough")
        if elev_score == 0 and not below_sea_mentioned:
            reasons.append("elevation not documented")
        feedback = f"❌ FAILED (Score: {score}/100) - {', '.join(reasons)} | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def parse_kml_file(filepath: str) -> Optional[Dict[str, Any]]:
    """Parse KML file and extract placemark data."""
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace first, then without
        placemarks = root.findall('.//kml:Placemark', ns)
        if not placemarks:
            placemarks = root.findall('.//Placemark')
        
        if not placemarks:
            return None
        
        pm = placemarks[0]
        
        # Extract name
        name_elem = pm.find('kml:name', ns) or pm.find('name')
        name = name_elem.text if name_elem is not None else ""
        
        # Extract description
        desc_elem = pm.find('kml:description', ns) or pm.find('description')
        description = desc_elem.text if desc_elem is not None else ""
        
        # Extract coordinates
        coords_elem = pm.find('.//kml:coordinates', ns) or pm.find('.//coordinates')
        coords = coords_elem.text.strip() if coords_elem is not None else ""
        
        # Parse coordinates (lon,lat,alt format in KML)
        lon, lat, alt = None, None, None
        if coords:
            parts = coords.replace('\n', '').replace('\t', '').strip().split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0].strip())
                    lat = float(parts[1].strip())
                except ValueError:
                    pass
            if len(parts) >= 3:
                try:
                    alt = float(parts[2].strip())
                except ValueError:
                    pass
        
        return {
            "name": name,
            "description": description,
            "latitude": lat,
            "longitude": lon,
            "altitude": alt,
            "raw_coordinates": coords
        }
        
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
        return None
    except Exception as e:
        logger.warning(f"Error parsing KML: {e}")
        return None


def parse_coordinates_string(coords_str: str) -> Tuple[Optional[float], Optional[float]]:
    """Parse coordinate string in various formats."""
    try:
        # KML format: lon,lat,alt
        parts = coords_str.replace('\n', '').replace('\t', '').strip().split(',')
        if len(parts) >= 2:
            lon = float(parts[0].strip())
            lat = float(parts[1].strip())
            return lat, lon
    except ValueError:
        pass
    return None, None


def check_coordinates(lat: Optional[float], lon: Optional[float], 
                     target_lat: float, target_lon: float, 
                     tolerance: float) -> Tuple[int, str]:
    """Check if coordinates are within tolerance of target."""
    if lat is None or lon is None:
        return 0, "❌ Coordinates not found in placemark (+0)"
    
    lat_diff = abs(lat - target_lat)
    
    # Handle longitude sign (KML uses negative for West)
    # Target is -116.7677, so lon should be negative
    if lon > 0:
        lon = -lon  # Convert if stored as positive
    lon_diff = abs(lon - target_lon)
    
    if lat_diff <= tolerance and lon_diff <= tolerance:
        return 20, f"✅ Coordinates accurate ({lat:.4f}, {lon:.4f}) (+20)"
    elif lat_diff <= tolerance * 2 and lon_diff <= tolerance * 2:
        return 12, f"⚠️ Coordinates close ({lat:.4f}, {lon:.4f}) (+12)"
    elif lat_diff <= tolerance * 5 and lon_diff <= tolerance * 5:
        return 5, f"⚠️ Coordinates in general area ({lat:.4f}, {lon:.4f}) (+5)"
    else:
        return 0, f"❌ Coordinates incorrect ({lat:.4f}, {lon:.4f}) - expected near ({target_lat}, {target_lon}) (+0)"


def check_elevation_in_description(description: str, expected_elev: float, 
                                   tolerance: float) -> Tuple[bool, int, str]:
    """Check if description contains elevation information."""
    if not description:
        return False, 0, "❌ No description in placemark (+0)"
    
    desc_lower = description.lower()
    
    # Look for elevation/altitude keywords
    elev_keywords = ['elevation', 'altitude', 'height', 'meters', 'feet', 'ft', 'm ']
    has_elev_word = any(kw in desc_lower for kw in elev_keywords)
    
    # Extract numeric values
    numbers = re.findall(r'-?\d+\.?\d*', description)
    
    elev_in_range = False
    for num_str in numbers:
        try:
            num = float(num_str)
            # Check meters range (-100 to -50)
            if -100 <= num <= -50:
                elev_in_range = True
                break
            # Check feet range (-330 to -230)
            if -330 <= num <= -230:
                elev_in_range = True
                break
        except ValueError:
            continue
    
    if has_elev_word and elev_in_range:
        return True, 15, "✅ Elevation correctly documented (+15)"
    elif elev_in_range:
        return True, 12, "✅ Elevation value present (+12)"
    elif has_elev_word:
        return True, 8, "⚠️ Elevation mentioned but value unclear (+8)"
    else:
        return False, 0, "❌ No elevation information found (+0)"


def verify_via_vlm_trajectory(traj: Dict[str, Any], query_vlm) -> Tuple[int, str]:
    """Use VLM on trajectory frames to verify workflow."""
    if not query_vlm:
        return 0, "⚠️ VLM not available for trajectory verification (+0)"
    
    # Import trajectory sampling functions
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        # Fallback if import fails
        return 0, "⚠️ VLM trajectory functions not available (+0)"
    
    # Sample frames across the trajectory
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
    except Exception as e:
        logger.warning(f"Failed to sample trajectory frames: {e}")
        return 0, "⚠️ Could not sample trajectory frames (+0)"
    
    if not frames:
        return 0, "⚠️ No trajectory frames available (+0)"
    
    # VLM prompt for trajectory verification
    vlm_prompt = """You are verifying that an agent completed a Google Earth task to navigate to Badwater Basin (Death Valley) and create a placemark.

These screenshots are from the agent's interaction (earliest to latest).

For successful completion, the agent should have:
1. Used Google Earth (satellite/aerial imagery visible)
2. Navigated to Death Valley area (tan/brown desert terrain, distinctive white salt flats)
3. Created a placemark (Add Placemark dialog, or placemark pin visible)
4. Exported or saved the placemark (Save dialog, file browser)

Assess:
1. GOOGLE_EARTH_USED: Is this clearly Google Earth Pro interface?
2. DEATH_VALLEY_VISIBLE: Is desert terrain with white salt flat patterns visible?
3. PLACEMARK_CREATED: Is there evidence of placemark creation (dialog, pin, or My Places entry)?
4. MEANINGFUL_WORK: Do the frames show real navigation/interaction (not just idle)?

Respond in JSON:
{
    "google_earth_used": true/false,
    "death_valley_visible": true/false,
    "placemark_created": true/false,
    "meaningful_work": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
    
    try:
        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        
        if not vlm_result.get("success"):
            return 0, f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')} (+0)"
        
        parsed = vlm_result.get("parsed", {})
        
        criteria_met = sum([
            parsed.get("google_earth_used", False),
            parsed.get("death_valley_visible", False),
            parsed.get("placemark_created", False),
            parsed.get("meaningful_work", False)
        ])
        
        confidence = parsed.get("confidence", "low")
        conf_mult = {"high": 1.0, "medium": 0.8, "low": 0.6}.get(confidence, 0.6)
        
        # Max 5 points for VLM verification
        vlm_score = min(5, int((criteria_met / 4) * 5 * conf_mult))
        
        if vlm_score >= 4:
            return vlm_score, f"✅ VLM trajectory verified (confidence: {confidence}) (+{vlm_score})"
        elif vlm_score >= 2:
            return vlm_score, f"⚠️ VLM partial verification (confidence: {confidence}) (+{vlm_score})"
        else:
            return vlm_score, f"⚠️ VLM low confidence ({confidence}) (+{vlm_score})"
            
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return 0, f"⚠️ VLM verification error: {str(e)[:50]} (+0)"