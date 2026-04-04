#!/usr/bin/env python3
"""
Verifier for Mariana Trench Documentation task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (10 points)
2. KML was created DURING task - anti-gaming (15 points)
3. Placemark named 'Challenger Deep' (15 points)
4. Coordinates in Mariana Trench region (20 points)
5. Depth value in description (15 points)
6. 'Mariana' reference in description (10 points)
7. VLM: Trajectory shows ocean exploration workflow (15 points)

Pass threshold: 65 points with KML exists AND coordinates valid
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Score configuration
MAX_SCORES = {
    "kml_exists": 10,
    "kml_created_during_task": 15,
    "placemark_name": 15,
    "coordinates_valid": 20,
    "depth_recorded": 15,
    "mariana_reference": 10,
    "vlm_trajectory": 15
}

# Mariana Trench bounding box (generous for Challenger Deep region)
COORD_BOUNDS = {
    "lat_min": 10.5,
    "lat_max": 12.5,
    "lon_min": 141.0,
    "lon_max": 144.0
}

# Valid depth range for Challenger Deep (in meters, negative values)
DEPTH_RANGE = {
    "min": -12000,
    "max": -10000
}


def parse_kml_content(kml_path: str) -> dict:
    """Parse KML file and extract placemark data."""
    result = {
        "valid": False,
        "name": "",
        "description": "",
        "coordinates": "",
        "latitude": None,
        "longitude": None,
        "error": None
    }
    
    try:
        tree = ET.parse(kml_path)
        root = tree.getroot()
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace first, then without
        placemarks = root.findall('.//kml:Placemark', ns)
        if not placemarks:
            placemarks = root.findall('.//Placemark')
        
        if not placemarks:
            result["error"] = "No Placemark element found"
            return result
        
        placemark = placemarks[0]
        
        # Extract name
        name_elem = placemark.find('kml:name', ns) or placemark.find('name')
        result["name"] = name_elem.text.strip() if name_elem is not None and name_elem.text else ""
        
        # Extract description (may be in CDATA)
        desc_elem = placemark.find('kml:description', ns) or placemark.find('description')
        if desc_elem is not None and desc_elem.text:
            result["description"] = desc_elem.text.strip()
        
        # Extract coordinates
        coords_elem = placemark.find('.//kml:coordinates', ns) or placemark.find('.//coordinates')
        if coords_elem is not None and coords_elem.text:
            result["coordinates"] = coords_elem.text.strip()
            
            # Parse lon,lat,alt format
            coord_parts = result["coordinates"].split(",")
            if len(coord_parts) >= 2:
                try:
                    result["longitude"] = float(coord_parts[0].strip())
                    result["latitude"] = float(coord_parts[1].strip())
                except ValueError:
                    pass
        
        result["valid"] = True
        return result
        
    except ET.ParseError as e:
        result["error"] = f"XML parse error: {e}"
        return result
    except Exception as e:
        result["error"] = f"Error reading KML: {e}"
        return result


def check_depth_in_description(description: str) -> tuple:
    """Check if description contains a valid depth value."""
    if not description:
        return False, None
    
    # Patterns for depth values
    patterns = [
        r'-\s*1[01],?\d{3}',      # -10,000 to -11,999
        r'-\s*1[01]\d{3}',        # -10000 to -11999
        r'1[01],?\d{3}\s*m',      # 10,000m to 11,999m
        r'1[01]\d{3}\s*m',        # 10000m to 11999m
        r'depth[:\s]+[-]?\d+',    # depth: -XXXXX
        r'[-]?\d{4,5}\s*(?:m|meter|meters|metre|metres)'
    ]
    
    for pattern in patterns:
        match = re.search(pattern, description, re.IGNORECASE)
        if match:
            # Extract numeric value
            numbers = re.findall(r'-?\d+[,.]?\d*', match.group())
            for num_str in numbers:
                try:
                    num = float(num_str.replace(',', ''))
                    # Check if in valid range (absolute value)
                    if DEPTH_RANGE["min"] <= num <= DEPTH_RANGE["max"]:
                        return True, num
                    if DEPTH_RANGE["min"] <= -abs(num) <= DEPTH_RANGE["max"]:
                        return True, -abs(num)
                except ValueError:
                    continue
    
    return False, None


def check_mariana_reference(description: str) -> bool:
    """Check if description mentions Mariana Trench."""
    if not description:
        return False
    return "mariana" in description.lower()


def check_coordinates_valid(lat: float, lon: float) -> bool:
    """Check if coordinates are in the Mariana Trench region."""
    if lat is None or lon is None:
        return False
    
    lat_ok = COORD_BOUNDS["lat_min"] <= lat <= COORD_BOUNDS["lat_max"]
    lon_ok = COORD_BOUNDS["lon_min"] <= lon <= COORD_BOUNDS["lon_max"]
    
    return lat_ok and lon_ok


def verify_mariana_trench_documentation(traj, env_info, task_info):
    """
    Verify that the Mariana Trench documentation task was completed.
    
    Uses multiple verification signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/challenger_deep.kml')
    
    scores = {key: 0 for key in MAX_SCORES}
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details["export_result"] = result
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_info = result.get("output_file", {})
    kml_exists = output_info.get("exists", False)
    
    if kml_exists:
        scores["kml_exists"] = MAX_SCORES["kml_exists"]
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file not found")
        # Early exit if no file
        total_score = sum(scores.values())
        return {
            "passed": False,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (15 points) - ANTI-GAMING
    # ================================================================
    created_during_task = output_info.get("created_during_task", False)
    
    if created_during_task:
        scores["kml_created_during_task"] = MAX_SCORES["kml_created_during_task"]
        feedback_parts.append("✅ KML created during task")
    else:
        feedback_parts.append("⚠️ KML may have existed before task")
    
    # ================================================================
    # Copy and parse the actual KML file
    # ================================================================
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_data = None
    try:
        copy_from_env(expected_output_path, temp_kml.name)
        kml_data = parse_kml_content(temp_kml.name)
        details["kml_parsed"] = kml_data
    except Exception as e:
        logger.warning(f"Could not copy/parse KML: {e}")
        kml_data = {"valid": False, "error": str(e)}
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    if not kml_data.get("valid"):
        # Fall back to export script's parsing
        kml_content = result.get("kml_content", {})
        kml_data = {
            "valid": kml_content.get("valid_structure", False),
            "name": kml_content.get("placemark_name", ""),
            "description": kml_content.get("description", ""),
            "coordinates": kml_content.get("coordinates", ""),
            "latitude": None,
            "longitude": None
        }
        # Try to parse coordinates from export
        coords_str = kml_content.get("coordinates", "")
        if coords_str:
            parts = coords_str.split(",")
            if len(parts) >= 2:
                try:
                    kml_data["longitude"] = float(parts[0].strip())
                    kml_data["latitude"] = float(parts[1].strip())
                except ValueError:
                    pass
    
    # ================================================================
    # CRITERION 3: Placemark named 'Challenger Deep' (15 points)
    # ================================================================
    placemark_name = kml_data.get("name", "")
    name_lower = placemark_name.lower().strip()
    
    if "challenger" in name_lower and "deep" in name_lower:
        scores["placemark_name"] = MAX_SCORES["placemark_name"]
        feedback_parts.append(f"✅ Placemark name correct: '{placemark_name}'")
    elif "challenger" in name_lower or "deep" in name_lower:
        scores["placemark_name"] = MAX_SCORES["placemark_name"] // 2
        feedback_parts.append(f"⚠️ Partial name match: '{placemark_name}'")
    else:
        feedback_parts.append(f"❌ Wrong placemark name: '{placemark_name}'")
    
    # ================================================================
    # CRITERION 4: Coordinates in Mariana Trench region (20 points)
    # ================================================================
    lat = kml_data.get("latitude")
    lon = kml_data.get("longitude")
    
    if check_coordinates_valid(lat, lon):
        scores["coordinates_valid"] = MAX_SCORES["coordinates_valid"]
        feedback_parts.append(f"✅ Coordinates valid: ({lat:.4f}°N, {lon:.4f}°E)")
    elif lat is not None and lon is not None:
        feedback_parts.append(f"❌ Coordinates outside Mariana Trench: ({lat:.4f}, {lon:.4f})")
    else:
        feedback_parts.append("❌ Could not parse coordinates")
    
    details["coordinates"] = {"latitude": lat, "longitude": lon}
    
    # ================================================================
    # CRITERION 5: Depth value in description (15 points)
    # ================================================================
    description = kml_data.get("description", "")
    has_depth, depth_value = check_depth_in_description(description)
    
    if has_depth:
        scores["depth_recorded"] = MAX_SCORES["depth_recorded"]
        feedback_parts.append(f"✅ Depth recorded: {depth_value}m")
    else:
        # Check export script's analysis as fallback
        if result.get("kml_content", {}).get("has_depth_value", False):
            scores["depth_recorded"] = MAX_SCORES["depth_recorded"]
            feedback_parts.append("✅ Depth value found")
        else:
            feedback_parts.append("❌ No valid depth in description")
    
    details["depth_info"] = {"found": has_depth, "value": depth_value}
    
    # ================================================================
    # CRITERION 6: 'Mariana' reference in description (10 points)
    # ================================================================
    has_mariana = check_mariana_reference(description)
    
    if has_mariana:
        scores["mariana_reference"] = MAX_SCORES["mariana_reference"]
        feedback_parts.append("✅ 'Mariana' reference found")
    else:
        # Check export script's analysis as fallback
        if result.get("kml_content", {}).get("has_mariana_reference", False):
            scores["mariana_reference"] = MAX_SCORES["mariana_reference"]
            feedback_parts.append("✅ 'Mariana' reference found")
        else:
            feedback_parts.append("❌ No 'Mariana' reference in description")
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (15 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across trajectory (not just final!)
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """Analyze these screenshots from a Google Earth session documenting the Mariana Trench.

Look for evidence of the following workflow:
1. OCEAN_LAYER_ENABLED: Ocean floor/bathymetric terrain visible (underwater topography, not surface ocean)
2. TRENCH_NAVIGATION: View showing deep ocean trench structure (canyon-like depression in ocean floor)
3. PACIFIC_REGION: Location appears to be in the Pacific Ocean area
4. PLACEMARK_CREATION: Any placemark creation dialog or properties window visible
5. MEANINGFUL_WORKFLOW: Screenshots show progression through exploration/documentation steps

Respond in JSON format:
{
    "ocean_layer_enabled": true/false,
    "trench_visible": true/false,
    "pacific_region": true/false,
    "placemark_dialog_seen": true/false,
    "meaningful_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                details["vlm_result"] = vlm_result
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    vlm_criteria = 0
                    if parsed.get("ocean_layer_enabled"):
                        vlm_criteria += 1
                    if parsed.get("trench_visible"):
                        vlm_criteria += 1
                    if parsed.get("pacific_region"):
                        vlm_criteria += 1
                    if parsed.get("placemark_dialog_seen"):
                        vlm_criteria += 1
                    if parsed.get("meaningful_workflow"):
                        vlm_criteria += 1
                    
                    # Score based on criteria met (out of 5)
                    confidence = parsed.get("confidence", "low")
                    confidence_mult = {"high": 1.0, "medium": 0.85, "low": 0.7}.get(confidence, 0.7)
                    
                    vlm_score = int((vlm_criteria / 5) * MAX_SCORES["vlm_trajectory"] * confidence_mult)
                    scores["vlm_trajectory"] = vlm_score
                    
                    if vlm_criteria >= 3:
                        feedback_parts.append(f"✅ VLM: Ocean exploration workflow confirmed ({vlm_criteria}/5 criteria)")
                    elif vlm_criteria >= 1:
                        feedback_parts.append(f"⚠️ VLM: Partial workflow evidence ({vlm_criteria}/5 criteria)")
                    else:
                        feedback_parts.append("❌ VLM: Workflow not confirmed")
                else:
                    feedback_parts.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
        except ImportError:
            # VLM utilities not available - give partial credit based on other evidence
            if scores["coordinates_valid"] > 0 and scores["kml_created_during_task"] > 0:
                scores["vlm_trajectory"] = MAX_SCORES["vlm_trajectory"] // 2
                feedback_parts.append("⚠️ VLM unavailable, partial credit from other evidence")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM error: {e}")
    else:
        # No VLM available - give partial credit if programmatic checks passed
        if scores["coordinates_valid"] > 0 and scores["kml_created_during_task"] > 0:
            scores["vlm_trajectory"] = MAX_SCORES["vlm_trajectory"] // 2
            feedback_parts.append("⚠️ VLM unavailable, partial credit awarded")
    
    # ================================================================
    # Calculate final score and pass/fail
    # ================================================================
    total_score = sum(scores.values())
    max_total = sum(MAX_SCORES.values())
    
    # Critical requirements: KML exists AND coordinates valid
    critical_pass = scores["kml_exists"] > 0 and scores["coordinates_valid"] > 0
    score_pass = total_score >= 65
    
    passed = critical_pass and score_pass
    
    # Build detailed feedback
    feedback_parts.append(f"\n📊 Score: {total_score}/{max_total}")
    
    details["scores"] = scores
    details["max_scores"] = MAX_SCORES
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }