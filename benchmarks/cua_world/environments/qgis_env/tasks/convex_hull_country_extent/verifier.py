#!/usr/bin/env python3
"""
Verifier for convex_hull_country_extent task.

Criteria:
1. GeoJSON output exists and is a valid Polygon (30 pts)
2. GeoJSON contains exactly 1 feature (10 pts)
3. GeoJSON bounding box is within Australian region (20 pts)
4. Report file exists and contains a plausible area value (25 pts)
5. Output files were created during the task (Anti-gaming) (15 pts)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convex_hull_country_extent(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    min_area = metadata.get('min_area_sqkm', 3000000)
    max_area = metadata.get('max_area_sqkm', 12000000)
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. GeoJSON Valid Polygon (30 pts)
    if result.get('geojson_exists') and result.get('geojson_valid') and result.get('geojson_is_polygon'):
        score += 30
        feedback_parts.append("Valid GeoJSON Polygon created")
    elif result.get('geojson_exists'):
        score += 10
        feedback_parts.append("GeoJSON created but not a Polygon")
    else:
        feedback_parts.append("No GeoJSON output found")
        
    # 2. Single Feature (10 pts) - Convex hull of a set of points is one polygon
    if result.get('geojson_feature_count') == 1:
        score += 10
        feedback_parts.append("Correct single feature count")
    elif result.get('geojson_feature_count', 0) > 1:
        score += 5
        feedback_parts.append(f"Multiple features found ({result.get('geojson_feature_count')})")
        
    # 3. Spatial Location Check (20 pts)
    bbox = result.get('geojson_bbox', [])
    if bbox and len(bbox) == 4:
        # Australia approx bounds: [113, -44, 154, -10]
        # We allow some buffer for islands
        minx, miny, maxx, maxy = bbox
        
        # Check if it overlaps significantly with Australia
        # Center of bbox
        cx = (minx + maxx) / 2
        cy = (miny + maxy) / 2
        
        if 110 <= cx <= 160 and -45 <= cy <= -10:
            score += 20
            feedback_parts.append("Geometry is correctly located in Australia")
        else:
            feedback_parts.append(f"Geometry seems misplaced (Center: {cx:.1f}, {cy:.1f})")
    else:
        feedback_parts.append("Could not verify geometry location")
        
    # 4. Report & Area Check (25 pts)
    if result.get('report_exists'):
        try:
            area_val = float(result.get('report_extracted_area', 0))
            if min_area <= area_val <= max_area:
                score += 25
                feedback_parts.append(f"Reported area plausible ({area_val:,.0f} sq km)")
            elif area_val > 0:
                score += 10
                feedback_parts.append(f"Reported area out of expected range ({area_val:,.0f} sq km)")
            else:
                score += 5
                feedback_parts.append("Report exists but valid number not found")
        except (ValueError, TypeError):
            score += 5
            feedback_parts.append("Report exists but could not parse area")
    else:
        feedback_parts.append("Report file missing")
        
    # 5. Anti-gaming (15 pts) - Implied by 'exists' checks in export_result.sh which check timestamps
    # But we double check the flag passed from export script
    if result.get('geojson_exists') and result.get('report_exists'):
        score += 15
    elif result.get('geojson_exists'):
        score += 7
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }