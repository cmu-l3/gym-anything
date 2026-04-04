#!/usr/bin/env python3
"""
Verifier for weather_stations_csv_import task.

VERIFICATION STRATEGY:
This task requires importing a CSV file with 25 NOAA weather station records
into Google Earth Pro. We verify through multiple independent signals:

1. Programmatic checks (from export_result.json):
   - myplaces.kml modified during task (not before)
   - New placemarks added (count comparison)
   - Known station names found in myplaces.kml
   - CSV file was accessed during task
   - Google Earth was running

2. VLM trajectory verification:
   - Import dialog workflow visible in trajectory frames
   - Column mapping configuration visible
   - Placemarks visible on map (western US region)
   - My Places panel shows entries

ANTI-GAMING:
- Timestamp checks ensure file modifications happened during task
- Placemark count comparison (before vs after)
- Station name matching (specific expected values)
- Trajectory frames prove actual workflow execution
"""

import json
import tempfile
import os
import logging
import re
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected station names from the CSV
EXPECTED_STATIONS = [
    "LOS ANGELES INTL AP",
    "SAN FRANCISCO INTL AP", 
    "SEATTLE TACOMA INTL AP",
    "SAN DIEGO LINDBERGH FLD",
    "PORTLAND INTL JETPORT",
    "PHOENIX SKY HARBOR INTL AP",
    "DENVER INTL AP",
    "SALT LAKE CITY INTL AP",
    "ALBUQUERQUE INTL AP",
    "BOISE AIR TERMINAL",
    "RENO TAHOE INTL AP",
    "TUCSON INTL AP",
    "FLAGSTAFF PULLIAM AP",
    "GRAND JUNCTION WALKER FLD",
    "BILLINGS LOGAN INTL AP",
    "SPOKANE INTL AP",
    "MEDFORD ROGUE VALLEY INTL",
    "EL PASO INTL AP",
    "LAS VEGAS MCCARRAN INTL AP",
    "FRESNO YOSEMITE INTL AP",
    "COLORADO SPRINGS MUNI AP",
    "MISSOULA INTL AP",
    "GREAT FALLS INTL AP",
    "HELENA REGIONAL AP",
    "SACRAMENTO EXECUTIVE AP"
]


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_IMPORT_WORKFLOW_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a CSV import task in Google Earth Pro.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful CSV import in Google Earth Pro, the agent should progress through:
1. Google Earth Pro open - the main interface with globe/satellite view visible
2. File menu or Import dialog - accessing File > Import
3. File browser - navigating to select a CSV file
4. Import wizard/dialog - column mapping screen where user assigns latitude, longitude, and name fields
5. Placemarks visible - either in My Places panel or as markers on the map

Analyze the trajectory and determine:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro's interface visible in the frames?
2. IMPORT_DIALOG_SHOWN: Is there evidence of an import dialog, file browser, or column mapping interface?
3. FILE_SELECTION_VISIBLE: Can you see a file browser or file path being selected?
4. COLUMN_MAPPING_VISIBLE: Is there a dialog showing column name assignments (latitude, longitude, name)?
5. PLACEMARKS_RESULT: Are there placemarks visible on the map or in the My Places panel?
6. MEANINGFUL_PROGRESSION: Do the frames show state changes indicating actual work (not same screen)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "import_dialog_shown": true/false,
    "file_selection_visible": true/false,
    "column_mapping_visible": true/false,
    "placemarks_result": true/false,
    "meaningful_progression": true/false,
    "workflow_stages_observed": ["list what stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the trajectory"
}
"""

FINAL_STATE_VERIFICATION_PROMPT = """You are verifying the final state of a CSV import task in Google Earth Pro.

TASK: Import 25 NOAA weather station locations from a CSV file. Stations are across the western United States including airports in CA, WA, OR, AZ, CO, UT, NV, MT, ID, NM.

Examine this screenshot and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite/aerial imagery application)?
2. WESTERN_US_VISIBLE: Does the map view show the western United States region?
3. PLACEMARKS_ON_MAP: Are there multiple placemark icons/markers visible on the map?
4. MY_PLACES_ENTRIES: Is the My Places panel visible and does it show entries/placemarks?
5. IMPORT_SUCCESS_INDICATION: Is there any indication of successful import (multiple markers, populated list)?

Note: After CSV import, you should see:
- Multiple placemark markers across western US (CA, WA, OR, AZ, CO, etc.)
- Entries in the My Places sidebar panel
- The map may be zoomed to show all imported locations

Respond in JSON format:
{
    "is_google_earth": true/false,
    "western_us_visible": true/false,
    "placemarks_on_map": true/false,
    "estimated_placemark_count": "none"/"few (1-5)"/"some (6-15)"/"many (16+)",
    "my_places_entries_visible": true/false,
    "import_success_indication": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def parse_myplaces_kml(kml_content: str) -> Dict[str, Any]:
    """Parse myplaces.kml to extract placemark information."""
    result = {
        "total_placemarks": 0,
        "station_names_found": [],
        "has_coordinates": False
    }
    
    try:
        # Count placemarks
        placemark_count = kml_content.count("<Placemark")
        result["total_placemarks"] = placemark_count
        
        # Search for known station names
        for station in EXPECTED_STATIONS:
            if station in kml_content:
                result["station_names_found"].append(station)
        
        # Check for coordinate data
        if "<coordinates>" in kml_content:
            result["has_coordinates"] = True
            
    except Exception as e:
        logger.warning(f"Error parsing KML: {e}")
    
    return result


def _vlm_query(query_vlm, prompt: str, image=None, images=None) -> Dict:
    """Execute VLM query with error handling."""
    if not query_vlm:
        return {}
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return {}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_weather_stations_csv_import(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent successfully imported CSV weather station data.
    
    Uses multiple independent verification signals:
    - Programmatic: File timestamps, placemark counts, station name matching
    - VLM: Trajectory workflow verification, final state verification
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'details'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_placemark_count', 25)
    
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ================================================================
    # PROGRAMMATIC VERIFICATION: Read export results
    # ================================================================
    
    # Copy task_result.json from container
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["export_result"] = result_data
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        feedback_parts.append("⚠️ Could not read export results")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Copy myplaces.kml for deeper analysis
    kml_content = ""
    kml_analysis = {}
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        kml_analysis = parse_myplaces_kml(kml_content)
        details["kml_analysis"] = kml_analysis
    except Exception as e:
        logger.warning(f"Could not read myplaces.kml: {e}")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: CSV file was accessed (10 points)
    # ================================================================
    csv_accessed = result_data.get('csv_file_accessed', False)
    if csv_accessed:
        score += 10
        feedback_parts.append("✅ CSV file was accessed")
    else:
        feedback_parts.append("❌ CSV file not accessed")
    details["csv_accessed"] = csv_accessed
    
    # ================================================================
    # CRITERION 2: myplaces.kml was modified during task (15 points)
    # ================================================================
    myplaces_modified = result_data.get('myplaces_modified', False)
    task_start = result_data.get('task_start', 0)
    myplaces_mtime = result_data.get('myplaces_mtime', 0)
    
    if myplaces_modified and myplaces_mtime > task_start:
        score += 15
        feedback_parts.append("✅ myplaces.kml modified during task")
    elif result_data.get('myplaces_exists', False):
        score += 5
        feedback_parts.append("⚠️ myplaces.kml exists but may not be modified during task")
    else:
        feedback_parts.append("❌ myplaces.kml not modified")
    details["myplaces_modified"] = myplaces_modified
    
    # ================================================================
    # CRITERION 3: New placemarks were added (20 points)
    # ================================================================
    new_placemarks = result_data.get('new_placemarks_added', 0)
    initial_count = result_data.get('initial_placemark_count', 0)
    current_count = result_data.get('current_placemark_count', 0)
    
    if new_placemarks >= 23:  # Allow 2 missing
        score += 20
        feedback_parts.append(f"✅ {new_placemarks} new placemarks added (expected ~25)")
    elif new_placemarks >= 20:
        score += 17
        feedback_parts.append(f"✓ {new_placemarks} new placemarks added (expected ~25)")
    elif new_placemarks >= 15:
        score += 12
        feedback_parts.append(f"⚠️ {new_placemarks} new placemarks added (expected ~25)")
    elif new_placemarks >= 10:
        score += 8
        feedback_parts.append(f"⚠️ Only {new_placemarks} new placemarks added (expected ~25)")
    elif new_placemarks >= 5:
        score += 5
        feedback_parts.append(f"⚠️ Only {new_placemarks} new placemarks added (expected ~25)")
    elif new_placemarks > 0:
        score += 2
        feedback_parts.append(f"❌ Only {new_placemarks} new placemarks added (expected ~25)")
    else:
        feedback_parts.append("❌ No new placemarks added")
    
    details["new_placemarks"] = new_placemarks
    details["placemark_counts"] = {"initial": initial_count, "current": current_count}
    
    # ================================================================
    # CRITERION 4: Station names found in myplaces.kml (15 points)
    # ================================================================
    matching_count = result_data.get('matching_station_count', 0)
    stations_found = kml_analysis.get('station_names_found', [])
    
    # Use KML analysis if available, otherwise use export result
    if stations_found:
        matching_count = len(stations_found)
    
    if matching_count >= 20:
        score += 15
        feedback_parts.append(f"✅ {matching_count} known station names found in data")
    elif matching_count >= 15:
        score += 12
        feedback_parts.append(f"✓ {matching_count} known station names found in data")
    elif matching_count >= 10:
        score += 8
        feedback_parts.append(f"⚠️ {matching_count} known station names found in data")
    elif matching_count >= 5:
        score += 5
        feedback_parts.append(f"⚠️ Only {matching_count} known station names found")
    elif matching_count > 0:
        score += 2
        feedback_parts.append(f"❌ Only {matching_count} known station names found")
    else:
        feedback_parts.append("❌ No known station names found in placemarks")
    
    details["matching_stations"] = matching_count
    details["stations_found_sample"] = stations_found[:5] if stations_found else []
    
    # ================================================================
    # CRITERION 5: Google Earth was running (5 points)
    # ================================================================
    ge_running = result_data.get('google_earth_running', False)
    if ge_running:
        score += 5
        feedback_parts.append("✅ Google Earth was running")
    else:
        feedback_parts.append("❌ Google Earth not running")
    details["google_earth_running"] = ge_running
    
    # ================================================================
    # VLM VERIFICATION: Trajectory analysis (20 points)
    # ================================================================
    vlm_trajectory_score = 0
    vlm_trajectory_details = {}
    
    if query_vlm and traj:
        # Get trajectory frames
        try:
            from gym_anything.vlm import sample_trajectory_frames
            traj_frames = sample_trajectory_frames(traj, n=5)
        except ImportError:
            # Fallback: extract frames manually
            traj_frames = []
            frames = traj.get('frames', [])
            if frames:
                indices = [0, len(frames)//4, len(frames)//2, 3*len(frames)//4, -1]
                traj_frames = [frames[min(i, len(frames)-1)] for i in indices if i < len(frames)]
        
        if traj_frames:
            vlm_result = _vlm_query(query_vlm, TRAJECTORY_IMPORT_WORKFLOW_PROMPT, images=traj_frames)
            vlm_trajectory_details = vlm_result
            
            if vlm_result:
                # Score trajectory verification
                traj_criteria = 0
                if vlm_result.get('google_earth_visible', False):
                    traj_criteria += 1
                if vlm_result.get('import_dialog_shown', False):
                    traj_criteria += 2
                if vlm_result.get('column_mapping_visible', False):
                    traj_criteria += 2
                if vlm_result.get('placemarks_result', False):
                    traj_criteria += 1
                if vlm_result.get('meaningful_progression', False):
                    traj_criteria += 1
                
                confidence = vlm_result.get('confidence', 'low')
                confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                
                vlm_trajectory_score = int((traj_criteria / 7) * 20 * confidence_mult)
                
                if traj_criteria >= 5:
                    feedback_parts.append(f"✅ VLM trajectory: Import workflow detected ({vlm_result.get('observations', '')[:50]}...)")
                elif traj_criteria >= 3:
                    feedback_parts.append(f"✓ VLM trajectory: Partial workflow detected")
                else:
                    feedback_parts.append(f"⚠️ VLM trajectory: Limited workflow evidence")
            else:
                feedback_parts.append("⚠️ VLM trajectory analysis failed")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM")
    
    score += vlm_trajectory_score
    details["vlm_trajectory"] = vlm_trajectory_details
    details["vlm_trajectory_score"] = vlm_trajectory_score
    
    # ================================================================
    # VLM VERIFICATION: Final state (15 points)
    # ================================================================
    vlm_final_score = 0
    vlm_final_details = {}
    
    if query_vlm:
        # Get final screenshot
        final_screenshot = None
        try:
            from gym_anything.vlm import get_final_screenshot
            final_screenshot = get_final_screenshot(traj)
        except ImportError:
            # Fallback
            frames = traj.get('frames', [])
            if frames:
                final_screenshot = frames[-1]
        
        if final_screenshot:
            vlm_result = _vlm_query(query_vlm, FINAL_STATE_VERIFICATION_PROMPT, image=final_screenshot)
            vlm_final_details = vlm_result
            
            if vlm_result:
                final_criteria = 0
                if vlm_result.get('is_google_earth', False):
                    final_criteria += 1
                if vlm_result.get('western_us_visible', False):
                    final_criteria += 1
                if vlm_result.get('placemarks_on_map', False):
                    final_criteria += 2
                if vlm_result.get('my_places_entries_visible', False):
                    final_criteria += 1
                if vlm_result.get('import_success_indication', False):
                    final_criteria += 2
                
                # Bonus for estimated placemark count
                est_count = vlm_result.get('estimated_placemark_count', 'none')
                if est_count == 'many (16+)':
                    final_criteria += 1
                elif est_count == 'some (6-15)':
                    final_criteria += 0.5
                
                confidence = vlm_result.get('confidence', 'low')
                confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                
                vlm_final_score = int((final_criteria / 8) * 15 * confidence_mult)
                
                if final_criteria >= 6:
                    feedback_parts.append(f"✅ VLM final: Import results visible")
                elif final_criteria >= 4:
                    feedback_parts.append(f"✓ VLM final: Partial results visible")
                else:
                    feedback_parts.append(f"⚠️ VLM final: Limited evidence of import")
            else:
                feedback_parts.append("⚠️ VLM final state analysis failed")
        else:
            feedback_parts.append("⚠️ No final screenshot available")
    
    score += vlm_final_score
    details["vlm_final"] = vlm_final_details
    details["vlm_final_score"] = vlm_final_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    
    # Key criteria: Must have at least some placemarks AND either file modified or stations found
    key_criteria_met = (
        new_placemarks >= 5 and 
        (myplaces_modified or matching_count >= 5)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Final score cap
    score = min(score, 100)
    
    details["score_breakdown"] = {
        "csv_accessed": 10 if csv_accessed else 0,
        "myplaces_modified": 15 if myplaces_modified else (5 if result_data.get('myplaces_exists') else 0),
        "new_placemarks": min(20, new_placemarks) if new_placemarks > 0 else 0,
        "station_names": min(15, matching_count) if matching_count > 0 else 0,
        "ge_running": 5 if ge_running else 0,
        "vlm_trajectory": vlm_trajectory_score,
        "vlm_final": vlm_final_score
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }