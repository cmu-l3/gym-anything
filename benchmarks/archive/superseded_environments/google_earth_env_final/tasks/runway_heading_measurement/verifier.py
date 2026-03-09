#!/usr/bin/env python3
"""
Verifier for runway_heading_measurement task.

Task: Measure the magnetic heading of Runway 34L at Denver International Airport
using Google Earth Pro's Ruler tool and create a placemark documenting the 
threshold location and measured heading.

VERIFICATION STRATEGY (Multi-signal):
1. KML file exists and was created during task (15 points)
2. Placemark name contains runway reference (15 points)  
3. Coordinates are accurate (within tolerance of threshold) (25 points)
4. Heading is documented in description (20 points)
5. Heading value is accurate (within tolerance) (15 points)
6. VLM: Trajectory shows Denver airport area (10 points)

Pass threshold: 70 points with coordinates accurate

CRITICAL: Uses copy_from_env, NOT exec_in_env
"""

import json
import tempfile
import os
import re
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_runway_heading_measurement(traj, env_info, task_info):
    """
    Verify that runway heading was measured and documented correctly.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('threshold_lat', 39.8279)
    expected_lon = metadata.get('threshold_lon', -104.6647)
    expected_heading = metadata.get('expected_heading', 345)
    heading_tolerance = metadata.get('heading_tolerance', 6)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.01)
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/runway_34L_heading.kml')
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and created during task (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += 15
        feedback_parts.append("✅ KML file created during task (+15)")
    elif output_exists:
        score += 5
        feedback_parts.append("⚠️ KML file exists but may be pre-existing (+5)")
    else:
        feedback_parts.append("❌ KML file not found (0)")
        # Early exit - nothing more to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: Placemark name contains runway reference (15 points)
    # ================================================================
    placemark_name = result.get('placemark_name', '')
    name_upper = placemark_name.upper() if placemark_name else ''
    
    name_valid = (
        '34L' in name_upper or 
        ('RUNWAY' in name_upper and '34' in name_upper) or
        ('DEN' in name_upper and ('RUNWAY' in name_upper or 'THRESHOLD' in name_upper)) or
        ('34' in name_upper and 'THRESHOLD' in name_upper)
    )
    
    if name_valid:
        score += 15
        feedback_parts.append(f"✅ Placemark name valid: '{placemark_name}' (+15)")
    elif placemark_name:
        score += 5
        feedback_parts.append(f"⚠️ Placemark name missing runway ref: '{placemark_name}' (+5)")
    else:
        feedback_parts.append("❌ No placemark name found (0)")
    
    # ================================================================
    # CRITERION 3: Coordinates accuracy (25 points)
    # ================================================================
    parsed_lat_str = result.get('parsed_latitude', '')
    parsed_lon_str = result.get('parsed_longitude', '')
    
    coords_valid = False
    try:
        if parsed_lat_str and parsed_lon_str:
            parsed_lat = float(parsed_lat_str)
            parsed_lon = float(parsed_lon_str)
            
            lat_diff = abs(parsed_lat - expected_lat)
            lon_diff = abs(parsed_lon - expected_lon)
            
            result_details['coordinate_check'] = {
                'parsed_lat': parsed_lat,
                'parsed_lon': parsed_lon,
                'expected_lat': expected_lat,
                'expected_lon': expected_lon,
                'lat_diff': lat_diff,
                'lon_diff': lon_diff,
                'tolerance': coord_tolerance
            }
            
            if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
                coords_valid = True
                score += 25
                feedback_parts.append(f"✅ Coordinates accurate: {parsed_lat:.4f}, {parsed_lon:.4f} (+25)")
            elif lat_diff <= coord_tolerance * 2 and lon_diff <= coord_tolerance * 2:
                # Close but not exact
                score += 15
                feedback_parts.append(f"⚠️ Coordinates close: {parsed_lat:.4f}, {parsed_lon:.4f} (+15)")
            else:
                feedback_parts.append(f"❌ Coordinates inaccurate: {parsed_lat:.4f}, {parsed_lon:.4f} (0)")
                feedback_parts.append(f"   Expected: {expected_lat:.4f}, {expected_lon:.4f}")
        else:
            feedback_parts.append("❌ No coordinates found in KML (0)")
    except (ValueError, TypeError) as e:
        feedback_parts.append(f"❌ Could not parse coordinates: {e} (0)")
    
    # ================================================================
    # CRITERION 4: Heading documented in description (20 points)
    # ================================================================
    placemark_desc = result.get('placemark_description', '')
    heading_value_str = result.get('heading_value', '')
    
    heading_documented = False
    heading_value = None
    
    if placemark_desc:
        # Look for heading patterns in description
        heading_patterns = [
            r'[Hh]eading[:\s]+(\d{2,3})',
            r'(\d{3})\s*°',
            r'(\d{3})\s*degrees',
            r'[Bb]earing[:\s]+(\d{2,3})',
            r'[Aa]zimuth[:\s]+(\d{2,3})',
            r'(\d{3})\s*deg'
        ]
        
        for pattern in heading_patterns:
            match = re.search(pattern, placemark_desc)
            if match:
                heading_value = int(match.group(1))
                heading_documented = True
                break
        
        # Also try the pre-extracted heading value
        if not heading_documented and heading_value_str:
            try:
                heading_value = int(heading_value_str)
                if 0 <= heading_value <= 360:
                    heading_documented = True
            except ValueError:
                pass
    
    if heading_documented and heading_value is not None:
        score += 20
        feedback_parts.append(f"✅ Heading documented: {heading_value}° (+20)")
        result_details['heading_value'] = heading_value
    elif placemark_desc:
        score += 5
        feedback_parts.append(f"⚠️ Description exists but no clear heading: '{placemark_desc[:50]}...' (+5)")
    else:
        feedback_parts.append("❌ No description with heading found (0)")
    
    # ================================================================
    # CRITERION 5: Heading accuracy (15 points)
    # ================================================================
    if heading_value is not None:
        # Handle 360° wraparound
        heading_diff = abs(heading_value - expected_heading)
        if heading_diff > 180:
            heading_diff = 360 - heading_diff
        
        result_details['heading_check'] = {
            'measured': heading_value,
            'expected': expected_heading,
            'difference': heading_diff,
            'tolerance': heading_tolerance
        }
        
        if heading_diff <= heading_tolerance:
            score += 15
            feedback_parts.append(f"✅ Heading accurate: {heading_value}° (expected ~{expected_heading}°) (+15)")
        elif heading_diff <= heading_tolerance * 2:
            score += 8
            feedback_parts.append(f"⚠️ Heading close: {heading_value}° (expected ~{expected_heading}°) (+8)")
        else:
            feedback_parts.append(f"❌ Heading inaccurate: {heading_value}° (expected ~{expected_heading}°) (0)")
    else:
        feedback_parts.append("❌ No heading value to verify accuracy (0)")
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (10 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across trajectory to verify workflow
            trajectory_frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            if trajectory_frames or final_frame:
                frames_to_check = trajectory_frames + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying a Google Earth task where the agent needed to navigate to Denver International Airport and measure a runway heading.

Look at these screenshots from the agent's work session and determine:
1. Is Google Earth visible (satellite imagery interface)?
2. Is Denver International Airport visible (distinctive runway pattern with 6 runways)?
3. Is there evidence of using the Ruler tool (measurement overlay visible)?
4. Is there a placemark or location pin visible?

Denver International Airport has a distinctive "pinwheel" runway layout that should be recognizable.

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "denver_airport_visible": true/false,
    "ruler_tool_evidence": true/false,
    "placemark_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames_to_check)
                result_details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    ge_visible = parsed.get('google_earth_visible', False)
                    den_visible = parsed.get('denver_airport_visible', False)
                    ruler_evidence = parsed.get('ruler_tool_evidence', False)
                    placemark_visible = parsed.get('placemark_visible', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    vlm_criteria = sum([ge_visible, den_visible, ruler_evidence, placemark_visible])
                    
                    if vlm_criteria >= 3 and confidence in ['medium', 'high']:
                        vlm_score = 10
                        feedback_parts.append(f"✅ VLM: Task workflow verified ({vlm_criteria}/4 criteria) (+10)")
                    elif vlm_criteria >= 2:
                        vlm_score = 6
                        feedback_parts.append(f"⚠️ VLM: Partial verification ({vlm_criteria}/4 criteria) (+6)")
                    elif ge_visible:
                        vlm_score = 3
                        feedback_parts.append(f"⚠️ VLM: Google Earth visible but limited evidence (+3)")
                    else:
                        feedback_parts.append("❌ VLM: Could not verify task workflow (0)")
                else:
                    feedback_parts.append(f"⚠️ VLM: Query failed - {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ VLM: No trajectory frames available")
        except ImportError as e:
            logger.warning(f"VLM utilities not available: {e}")
            feedback_parts.append("⚠️ VLM: Verification utilities not available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM: Verification error - {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM: Not available for verification")
    
    score += vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Pass requires 70+ points AND coordinates must be reasonably accurate
    key_criteria_met = (
        output_exists and 
        file_created_during_task and 
        (coords_valid or score >= 80)  # Either coords valid OR very high score
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Add summary
    feedback_parts.append(f"\n📊 Final Score: {score}/100")
    if passed:
        feedback_parts.append("✅ PASSED")
    else:
        if score >= 70 and not key_criteria_met:
            feedback_parts.append("❌ FAILED: Score >= 70 but key criteria not met")
        else:
            feedback_parts.append(f"❌ FAILED: Score below threshold or missing criteria")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }