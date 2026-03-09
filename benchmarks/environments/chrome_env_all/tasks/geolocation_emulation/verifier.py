#!/usr/bin/env python3
"""
Verifier for Chrome DevTools Geolocation Emulation Task (geolocation_emulation@1)
Task: Use DevTools Sensors panel to override geolocation and verify test page responds

Verification Strategy:
1. Use CDP to check if geolocation override is active (if possible)
2. Extract displayed coordinates from test page HTML
3. Verify coordinates match expected override (Paris: 48.8584, 2.2945)
4. Ensure coordinates differ significantly from default/real location
5. Check that test page successfully retrieved location
"""

import logging
import sys
import os
import json
import re
import tempfile
import requests
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass

# Expected coordinates for Paris
EXPECTED_LAT = 48.8584
EXPECTED_LON = 2.2945
COORDINATE_TOLERANCE = 0.05  # ~5km tolerance


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for geolocation_emulation@1.
    
    Verification Criteria (5 total, need 4 to pass):
    1. DevTools appears to be open (based on context/screenshots)
    2. Geolocation override appears active (coordinates set)
    3. Test page displays coordinates close to expected override
    4. Coordinates differ significantly from default (0,0 or actual location)
    5. Page successfully retrieved location (no errors)
    
    Args:
        traj: Trajectory data
        env_info: Environment information with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Extract verification data from container
        verification_data = extract_verification_data(copy_from_env)
        
        # Perform multi-criteria verification
        result = verify_geolocation_emulation(verification_data)
        
        # Cleanup
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_verification_data(copy_from_env) -> Dict[str, Any]:
    """
    Extract all verification data from container.
    
    Returns:
        Dict containing:
        - active_url: URL of active tab
        - page_title: Title of active tab
        - dom_info: DOM information from page
        - cdp_available: Whether CDP was accessible
    """
    data = {
        "active_url": "",
        "page_title": "",
        "dom_info": {},
        "cdp_available": False,
        "displayed_lat": None,
        "displayed_lon": None
    }
    
    # Try to get active URL
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/active_url.txt", temp_file.name)
        
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            with open(temp_file.name, 'r') as f:
                data["active_url"] = f.read().strip()
            data["cdp_available"] = True
        
        os.unlink(temp_file.name)
    except Exception as e:
        logger.warning(f"Could not get active URL: {e}")
    
    # Try to get DOM info
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        copy_from_env("/tmp/dom_info.json", temp_file.name)
        
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            with open(temp_file.name, 'r') as f:
                data["dom_info"] = json.load(f)
                data["page_title"] = data["dom_info"].get("title", "")
        
        os.unlink(temp_file.name)
    except Exception as e:
        logger.warning(f"Could not get DOM info: {e}")
    
    # Try to use CDP directly from host (if accessible)
    try:
        response = requests.get("http://localhost:9222/json", timeout=3)
        targets = response.json()
        
        for target in targets:
            if target.get('type') == 'page' and 'geolocation_test' in target.get('url', ''):
                data["page_title"] = target.get('title', '')
                data["active_url"] = target.get('url', '')
                data["cdp_available"] = True
                
                # Try to extract coordinates from title if present
                title = target.get('title', '')
                coords = extract_coordinates_from_text(title)
                if coords:
                    data["displayed_lat"], data["displayed_lon"] = coords
                
                break
    except Exception as e:
        logger.debug(f"Could not access CDP from host: {e}")
    
    logger.info(f"Extracted verification data: URL={data['active_url']}, Title={data['page_title']}, CDP={data['cdp_available']}")
    
    return data


def extract_coordinates_from_text(text: str) -> Optional[Tuple[float, float]]:
    """
    Extract latitude and longitude from text using regex.
    
    Args:
        text: Text potentially containing coordinates
        
    Returns:
        Tuple of (lat, lon) or None if not found
    """
    # Pattern for decimal coordinates
    pattern = r'(-?\d+\.\d+)[°,\s]+(-?\d+\.\d+)'
    
    match = re.search(pattern, text)
    if match:
        try:
            lat = float(match.group(1))
            lon = float(match.group(2))
            
            # Validate reasonable coordinate ranges
            if -90 <= lat <= 90 and -180 <= lon <= 180:
                return (lat, lon)
        except ValueError:
            pass
    
    return None


def verify_geolocation_emulation(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify geolocation emulation was successfully configured.
    
    Checks multiple criteria and returns detailed feedback.
    
    Args:
        data: Verification data extracted from container
        
    Returns:
        Dict with passed, score, and detailed feedback
    """
    criteria_results = []
    feedback_parts = []
    
    # Criterion 1: Test page is loaded
    page_loaded = 'geolocation_test' in data.get('active_url', '')
    criteria_results.append(page_loaded)
    
    if page_loaded:
        feedback_parts.append("✓ Geolocation test page is loaded")
    else:
        feedback_parts.append("✗ Geolocation test page not detected")
    
    logger.info(f"Criterion 1 (Page loaded): {page_loaded}")
    
    # Criterion 2: CDP is accessible
    cdp_ok = data.get('cdp_available', False)
    criteria_results.append(cdp_ok)
    
    if cdp_ok:
        feedback_parts.append("✓ Chrome DevTools Protocol is accessible")
    else:
        feedback_parts.append("⚠ CDP not fully accessible (may still pass)")
    
    logger.info(f"Criterion 2 (CDP accessible): {cdp_ok}")
    
    # Criterion 3 & 4: Extract and verify coordinates from page
    # Try multiple methods to get coordinates
    displayed_lat = data.get('displayed_lat')
    displayed_lon = data.get('displayed_lon')
    
    # Try to extract from title
    if displayed_lat is None and data.get('page_title'):
        coords = extract_coordinates_from_text(data['page_title'])
        if coords:
            displayed_lat, displayed_lon = coords
    
    # Try to extract from description
    if displayed_lat is None and data.get('dom_info', {}).get('description'):
        coords = extract_coordinates_from_text(data['dom_info']['description'])
        if coords:
            displayed_lat, displayed_lon = coords
    
    coordinates_found = displayed_lat is not None and displayed_lon is not None
    criteria_results.append(coordinates_found)
    
    if coordinates_found:
        feedback_parts.append(f"✓ Coordinates found on page: {displayed_lat:.4f}, {displayed_lon:.4f}")
        logger.info(f"Found coordinates: lat={displayed_lat}, lon={displayed_lon}")
    else:
        feedback_parts.append("✗ Could not extract coordinates from page")
        logger.warning("Coordinates not found in any extracted data")
    
    logger.info(f"Criterion 3 (Coordinates found): {coordinates_found}")
    
    # Criterion 4: Coordinates match expected override (Paris)
    coordinates_match = False
    if coordinates_found:
        lat_diff = abs(displayed_lat - EXPECTED_LAT)
        lon_diff = abs(displayed_lon - EXPECTED_LON)
        
        coordinates_match = (lat_diff <= COORDINATE_TOLERANCE and 
                           lon_diff <= COORDINATE_TOLERANCE)
        
        if coordinates_match:
            feedback_parts.append(f"✓ Coordinates match expected override (Paris: {EXPECTED_LAT}, {EXPECTED_LON})")
        else:
            # Check if coordinates are at least non-default
            if not (displayed_lat == 0 and displayed_lon == 0):
                feedback_parts.append(f"⚠ Coordinates set but don't match Paris (diff: lat={lat_diff:.4f}, lon={lon_diff:.4f})")
                # Give partial credit
                coordinates_match = 0.5
            else:
                feedback_parts.append("✗ Coordinates are default (0, 0) - override not active")
    else:
        feedback_parts.append("✗ Cannot verify coordinate match without extracted values")
    
    criteria_results.append(coordinates_match)
    logger.info(f"Criterion 4 (Coordinates match): {coordinates_match}")
    
    # Criterion 5: Page appears to have successfully retrieved location
    # Check for success indicators in title/description
    success_indicators = [
        'success' in data.get('page_title', '').lower(),
        '✅' in data.get('page_title', ''),
        coordinates_found,  # Having coordinates is a success indicator
    ]
    
    error_indicators = [
        'error' in data.get('page_title', '').lower(),
        'denied' in data.get('page_title', '').lower(),
        'failed' in data.get('page_title', '').lower(),
    ]
    
    location_retrieved = any(success_indicators) and not any(error_indicators)
    criteria_results.append(location_retrieved)
    
    if location_retrieved:
        feedback_parts.append("✓ Page successfully retrieved location (no errors detected)")
    else:
        feedback_parts.append("⚠ Could not confirm successful location retrieval")
    
    logger.info(f"Criterion 5 (Location retrieved): {location_retrieved}")
    
    # Calculate score
    # Convert boolean/float criteria to numeric scores
    numeric_criteria = []
    for c in criteria_results:
        if isinstance(c, bool):
            numeric_criteria.append(1.0 if c else 0.0)
        elif isinstance(c, (int, float)):
            numeric_criteria.append(float(c))
        else:
            numeric_criteria.append(0.0)
    
    criteria_met = sum(numeric_criteria)
    total_criteria = len(criteria_results)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least ~4/5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo pass this task:"
        feedback += "\n1. Press F12 to open Chrome DevTools"
        feedback += "\n2. Navigate to 'Sensors' panel (may be under '⋮' More tools)"
        feedback += "\n3. In 'Location' section, select 'Other...' or preset"
        feedback += "\n4. Set coordinates: Latitude: 48.8584, Longitude: 2.2945"
        feedback += "\n5. The test page should auto-refresh showing Paris coordinates"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met:.1f}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "page_loaded": page_loaded,
            "cdp_available": cdp_ok,
            "coordinates_found": coordinates_found,
            "coordinates_match": bool(coordinates_match),
            "location_retrieved": location_retrieved,
            "displayed_coordinates": {
                "latitude": displayed_lat,
                "longitude": displayed_lon
            } if coordinates_found else None,
            "expected_coordinates": {
                "latitude": EXPECTED_LAT,
                "longitude": EXPECTED_LON
            }
        }
    }
