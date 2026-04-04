#!/usr/bin/env python3
"""
Verifier for Meteor Crater Geological Annotation task.

Hybrid verification using:
1. KML file analysis (programmatic)
2. VLM trajectory verification (visual)

Scoring:
- KML file exists: 10 points
- Valid KML structure with polygon: 10 points
- Correct polygon name: 10 points
- Description with geological content: 10 points
- Location accuracy (centroid near crater): 20 points
- Shape accuracy (roughly circular): 15 points
- Size accuracy (area within tolerance): 10 points
- Proper vertex count: 5 points
- VLM trajectory verification: 10 points

Pass threshold: 70 points with location criterion met
"""

import json
import tempfile
import os
import math
import base64
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371  # Earth radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1-a))


def polygon_area_km2(coords):
    """Calculate approximate polygon area in km² using shoelace formula."""
    if len(coords) < 3:
        return 0
    
    # Convert to approximate km using center point
    center_lat = sum(c[1] for c in coords) / len(coords)
    lat_to_km = 111.0  # km per degree latitude
    lon_to_km = 111.0 * math.cos(math.radians(center_lat))
    
    # Shoelace formula
    n = len(coords)
    area = 0
    for i in range(n):
        j = (i + 1) % n
        x1 = coords[i][0] * lon_to_km
        y1 = coords[i][1] * lat_to_km
        x2 = coords[j][0] * lon_to_km
        y2 = coords[j][1] * lat_to_km
        area += x1 * y2 - x2 * y1
    
    return abs(area) / 2


def parse_kml_content(kml_text):
    """Parse KML content and extract polygon data."""
    try:
        root = ET.fromstring(kml_text)
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace first, then without
        placemark = root.find('.//kml:Placemark', ns)
        if placemark is None:
            placemark = root.find('.//Placemark')
        
        if placemark is None:
            return None, "No Placemark found in KML"
        
        # Get name
        name_elem = placemark.find('kml:name', ns)
        if name_elem is None:
            name_elem = placemark.find('name')
        name = name_elem.text if name_elem is not None and name_elem.text else ""
        
        # Get description
        desc_elem = placemark.find('kml:description', ns)
        if desc_elem is None:
            desc_elem = placemark.find('description')
        description = desc_elem.text if desc_elem is not None and desc_elem.text else ""
        
        # Get polygon coordinates - check multiple paths
        coords_elem = None
        for path in ['.//kml:Polygon//kml:coordinates', './/Polygon//coordinates', 
                     './/kml:coordinates', './/coordinates']:
            coords_elem = root.find(path, ns) if 'kml:' in path else root.find(path)
            if coords_elem is not None:
                break
        
        if coords_elem is None or not coords_elem.text:
            return None, "No coordinates found in polygon"
        
        # Parse coordinates (lon,lat,alt format)
        coords_text = coords_elem.text.strip()
        coords = []
        for point in coords_text.split():
            point = point.strip()
            if not point:
                continue
            parts = point.split(',')
            if len(parts) >= 2:
                try:
                    lon, lat = float(parts[0]), float(parts[1])
                    coords.append((lon, lat))
                except ValueError:
                    continue
        
        if len(coords) < 3:
            return None, f"Not enough valid coordinates ({len(coords)})"
        
        return {
            'name': name,
            'description': description,
            'coordinates': coords
        }, None
        
    except ET.ParseError as e:
        return None, f"XML parse error: {e}"
    except Exception as e:
        return None, f"Error parsing KML: {e}"


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing screenshots from a Google Earth task where the user should:
1. Navigate to Meteor Crater in Arizona (a distinctive circular impact crater)
2. Draw a polygon tracing the crater rim
3. Add a name and description to the polygon
4. Export/save the polygon as a KML file

Examine these trajectory screenshots and determine:

1. CRATER_VISIBLE: Is Meteor Crater visible? (A large circular bowl-shaped depression in a desert landscape)
2. POLYGON_DRAWN: Is there a polygon being drawn or visible on the crater?
3. DIALOG_SHOWN: Was a polygon properties dialog shown (for naming/description)?
4. EXPORT_ATTEMPTED: Was a save/export dialog visible at any point?
5. WORKFLOW_PROGRESS: Did the user appear to make progress through the task steps?

Respond in JSON format:
{
    "crater_visible": true/false,
    "polygon_drawn": true/false,
    "dialog_shown": true/false,
    "export_attempted": true/false,
    "workflow_progress": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observe"
}
"""


def verify_meteor_crater_annotation(traj, env_info, task_info):
    """
    Verify the Meteor Crater annotation task.
    
    Uses:
    1. copy_from_env to get task results
    2. KML file parsing for programmatic verification
    3. VLM trajectory analysis for visual verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_polygon_name', 'Barringer Crater Rim')
    crater_lat = metadata.get('crater_center_lat', 35.028)
    crater_lon = metadata.get('crater_center_lon', -111.022)
    crater_area = metadata.get('crater_area_km2', 1.13)
    max_distance = metadata.get('acceptable_centroid_radius_km', 5.0)
    area_tolerance = metadata.get('acceptable_area_tolerance', 0.30)
    min_vertices = metadata.get('min_vertices', 15)
    max_vertices = metadata.get('max_vertices', 100)
    description_keywords = metadata.get('description_keywords', 
        ['impact', 'crater', 'meteor', 'asteroid', '50000', '50,000', 'years', 'diameter', 'km'])
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result'] = result
    
    # ================================================================
    # CRITERION 1: Output file exists (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ KML file not found")
        details['file_exists'] = False
        # Try to still do VLM verification even without file
    
    # ================================================================
    # CRITERION 2: Anti-gaming - file created during task (implied in score)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if not file_created_during_task and output_exists:
        feedback_parts.append("⚠️ File may not have been created during this task")
        score -= 5  # Penalty
        details['file_timestamp_valid'] = False
    else:
        details['file_timestamp_valid'] = file_created_during_task
    
    # ================================================================
    # Parse KML content if available
    # ================================================================
    polygon_data = None
    kml_content_b64 = result.get('kml_content_base64', '')
    
    if kml_content_b64:
        try:
            kml_text = base64.b64decode(kml_content_b64).decode('utf-8', errors='ignore')
            polygon_data, parse_error = parse_kml_content(kml_text)
            if parse_error:
                details['kml_parse_error'] = parse_error
        except Exception as e:
            details['kml_decode_error'] = str(e)
    
    # ================================================================
    # CRITERION 3: Valid KML structure with polygon (10 points)
    # ================================================================
    if polygon_data:
        score += 10
        feedback_parts.append("✅ Valid KML with polygon")
        details['valid_kml'] = True
    elif output_exists:
        feedback_parts.append("⚠️ KML exists but could not parse polygon")
        details['valid_kml'] = False
    
    # ================================================================
    # CRITERION 4: Correct polygon name (10 points)
    # ================================================================
    if polygon_data:
        name = polygon_data.get('name', '').lower()
        expected_lower = expected_name.lower()
        
        # Check for partial matches
        if 'barringer' in name or (('crater' in name or 'meteor' in name) and 'rim' in name):
            score += 10
            feedback_parts.append(f"✅ Correct name: '{polygon_data.get('name')}'")
            details['name_correct'] = True
        elif 'crater' in name or 'meteor' in name:
            score += 5
            feedback_parts.append(f"⚠️ Partial name match: '{polygon_data.get('name')}'")
            details['name_correct'] = False
        else:
            feedback_parts.append(f"❌ Incorrect name: '{polygon_data.get('name')}'")
            details['name_correct'] = False
    
    # ================================================================
    # CRITERION 5: Description with geological content (10 points)
    # ================================================================
    if polygon_data:
        desc = (polygon_data.get('description') or '').lower()
        keywords_found = sum(1 for kw in description_keywords if kw.lower() in desc)
        
        if keywords_found >= 3 and len(desc) > 30:
            score += 10
            feedback_parts.append(f"✅ Good geological description ({keywords_found} keywords)")
            details['description_quality'] = 'good'
        elif keywords_found >= 1 and len(desc) > 10:
            score += 5
            feedback_parts.append(f"⚠️ Partial description ({keywords_found} keywords)")
            details['description_quality'] = 'partial'
        elif len(desc) > 5:
            score += 2
            feedback_parts.append("⚠️ Description present but lacks geological content")
            details['description_quality'] = 'minimal'
        else:
            feedback_parts.append("❌ No meaningful description")
            details['description_quality'] = 'none'
    
    # ================================================================
    # CRITERION 6: Location accuracy (20 points)
    # ================================================================
    location_accurate = False
    
    if polygon_data and polygon_data.get('coordinates'):
        coords = polygon_data['coordinates']
        
        # Calculate centroid
        centroid_lon = sum(c[0] for c in coords) / len(coords)
        centroid_lat = sum(c[1] for c in coords) / len(coords)
        
        distance = haversine_distance(centroid_lat, centroid_lon, crater_lat, crater_lon)
        details['centroid_distance_km'] = round(distance, 2)
        
        if distance <= 2.0:
            score += 20
            feedback_parts.append(f"✅ Excellent location ({distance:.1f}km from crater center)")
            location_accurate = True
        elif distance <= max_distance:
            score += 10
            feedback_parts.append(f"⚠️ Approximate location ({distance:.1f}km from crater center)")
            location_accurate = True
        else:
            feedback_parts.append(f"❌ Wrong location ({distance:.1f}km from crater center)")
            location_accurate = False
    
    # ================================================================
    # CRITERION 7: Shape accuracy - circularity (15 points)
    # ================================================================
    if polygon_data and polygon_data.get('coordinates') and len(polygon_data['coordinates']) >= 3:
        coords = polygon_data['coordinates']
        centroid_lon = sum(c[0] for c in coords) / len(coords)
        centroid_lat = sum(c[1] for c in coords) / len(coords)
        
        # Calculate distances from centroid
        distances = [haversine_distance(c[1], c[0], centroid_lat, centroid_lon) for c in coords]
        avg_dist = sum(distances) / len(distances)
        
        if avg_dist > 0:
            variance = sum((d - avg_dist)**2 for d in distances) / len(distances)
            std_dev = math.sqrt(variance)
            circularity = std_dev / avg_dist
            details['circularity'] = round(circularity, 3)
            
            if circularity < 0.25:
                score += 15
                feedback_parts.append(f"✅ Excellent circular shape (circularity={circularity:.2f})")
            elif circularity < 0.4:
                score += 10
                feedback_parts.append(f"✅ Good circular shape (circularity={circularity:.2f})")
            elif circularity < 0.6:
                score += 5
                feedback_parts.append(f"⚠️ Rough circular shape (circularity={circularity:.2f})")
            else:
                feedback_parts.append(f"❌ Poor shape (circularity={circularity:.2f})")
    
    # ================================================================
    # CRITERION 8: Size accuracy (10 points)
    # ================================================================
    if polygon_data and polygon_data.get('coordinates') and len(polygon_data['coordinates']) >= 3:
        coords = polygon_data['coordinates']
        area = polygon_area_km2(coords)
        details['polygon_area_km2'] = round(area, 2)
        
        area_error = abs(area - crater_area) / crater_area if crater_area > 0 else 1
        
        if area_error <= 0.20:
            score += 10
            feedback_parts.append(f"✅ Accurate size ({area:.2f} km²)")
        elif area_error <= area_tolerance:
            score += 5
            feedback_parts.append(f"⚠️ Approximate size ({area:.2f} km², expected ~{crater_area})")
        else:
            feedback_parts.append(f"❌ Wrong size ({area:.2f} km², expected ~{crater_area})")
    
    # ================================================================
    # CRITERION 9: Vertex count (5 points)
    # ================================================================
    if polygon_data and polygon_data.get('coordinates'):
        vertex_count = len(polygon_data['coordinates'])
        details['vertex_count'] = vertex_count
        
        if min_vertices <= vertex_count <= max_vertices:
            score += 5
            feedback_parts.append(f"✅ Good vertex count ({vertex_count})")
        else:
            feedback_parts.append(f"⚠️ Unusual vertex count ({vertex_count}, expected {min_vertices}-{max_vertices})")
    
    # ================================================================
    # CRITERION 10: VLM trajectory verification (10 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Sample trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            all_frames = frames + ([final_frame] if final_frame else [])
            
            if all_frames:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=all_frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    vlm_checks = 0
                    if parsed.get('crater_visible'):
                        vlm_checks += 1
                    if parsed.get('polygon_drawn'):
                        vlm_checks += 1
                    if parsed.get('dialog_shown'):
                        vlm_checks += 1
                    if parsed.get('export_attempted'):
                        vlm_checks += 1
                    if parsed.get('workflow_progress'):
                        vlm_checks += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    conf_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.6)
                    
                    vlm_score = int((vlm_checks / 5) * 10 * conf_mult)
                    score += vlm_score
                    
                    if vlm_checks >= 4:
                        feedback_parts.append(f"✅ VLM verified workflow ({vlm_checks}/5 checks)")
                    elif vlm_checks >= 2:
                        feedback_parts.append(f"⚠️ VLM partial verification ({vlm_checks}/5 checks)")
                    else:
                        feedback_parts.append(f"❌ VLM could not verify workflow ({vlm_checks}/5 checks)")
                else:
                    feedback_parts.append("⚠️ VLM verification failed")
                    details['vlm_error'] = vlm_result.get('error', 'Unknown')
            else:
                feedback_parts.append("⚠️ No trajectory frames for VLM")
        except ImportError:
            feedback_parts.append("⚠️ VLM utilities not available")
        except Exception as e:
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
            details['vlm_exception'] = str(e)
    else:
        feedback_parts.append("⚠️ VLM not available")
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    
    # Key criteria: file exists AND location is correct
    key_criteria_met = output_exists and location_accurate
    
    # Ensure score doesn't go negative
    score = max(0, min(100, score))
    
    passed = score >= 70 and key_criteria_met
    
    details['score_breakdown'] = {
        'file_exists': 10 if output_exists else 0,
        'valid_kml': 10 if polygon_data else 0,
        'location': details.get('centroid_distance_km', 999),
        'vlm_score': vlm_score,
        'total': score
    }
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }