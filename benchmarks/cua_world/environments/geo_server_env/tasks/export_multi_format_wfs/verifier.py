#!/usr/bin/env python3
"""
Verifier for export_multi_format_wfs task.
Validates GeoJSON, KML, GML, and CSV exports for correct format and content (South America filter).
"""

import json
import os
import tempfile
import logging
import csv
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_multi_format_wfs(traj, env_info, task_info):
    """
    Verify that the agent exported the 4 required files with correct content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    export_dir = metadata.get('export_dir', '/home/ga/exports')
    
    # Target countries to check for (sampling)
    target_countries = set(metadata.get('target_countries', ["Argentina", "Brazil", "Chile", "Colombia", "Peru"]))
    
    # Score components
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Load Task Result JSON (Metadata about files)
    # ------------------------------------------------------------------
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files_info = task_result.get('files', {})

    # Helper to copy a file from env to temp for analysis
    def get_file_content(filename):
        if not files_info.get(filename.split('.')[-1].lower(), {}).get('exists'):
            return None
        
        t = tempfile.NamedTemporaryFile(delete=False, suffix=f"_{filename}")
        try:
            copy_from_env(f"{export_dir}/{filename}", t.name)
            return t.name
        except Exception:
            if os.path.exists(t.name):
                os.unlink(t.name)
            return None

    # ------------------------------------------------------------------
    # 2. Verify GeoJSON (15 pts existence + 8 pts content + 5 pts filter)
    # ------------------------------------------------------------------
    geojson_score = 0
    geojson_count = 0
    geojson_path = get_file_content("south_america.geojson")
    
    if geojson_path:
        f_info = files_info.get('geojson', {})
        if f_info.get('size', 0) > 100 and f_info.get('created_during_task'):
            geojson_score += 15 # Exists and valid size
            
            try:
                with open(geojson_path, 'r') as f:
                    data = json.load(f)
                
                if data.get('type') == 'FeatureCollection' and 'features' in data:
                    features = data['features']
                    geojson_count = len(features)
                    
                    # Check for South American countries
                    sa_countries_found = 0
                    non_sa_found = False
                    
                    for feat in features:
                        props = feat.get('properties', {})
                        # Continent check (some datasets use CONTINENT, some continent)
                        cont = props.get('continent', props.get('CONTINENT', ''))
                        name = props.get('name', props.get('NAME', props.get('ADMIN', '')))
                        
                        if cont == 'South America':
                            pass # Good
                        elif cont:
                            non_sa_found = True # Found a different continent!
                        
                        if name in target_countries:
                            sa_countries_found += 1

                    if geojson_count >= 10:
                        geojson_score += 5
                    
                    if sa_countries_found >= 3:
                        geojson_score += 3
                        
                    if not non_sa_found and geojson_count > 0:
                        geojson_score += 5
                        feedback_parts.append("GeoJSON: Valid content (South America only)")
                    elif non_sa_found:
                         feedback_parts.append("GeoJSON: Contains non-South American data")
                    
                else:
                    feedback_parts.append("GeoJSON: Invalid structure")
            except Exception as e:
                feedback_parts.append(f"GeoJSON: Parsing error {str(e)}")
        else:
             feedback_parts.append("GeoJSON: File too small or not created during task")
        
        os.unlink(geojson_path)
    else:
        feedback_parts.append("GeoJSON: File not found")

    score += geojson_score

    # ------------------------------------------------------------------
    # 3. Verify KML (15 pts existence + 8 pts content)
    # ------------------------------------------------------------------
    kml_score = 0
    kml_count = 0
    kml_path = get_file_content("south_america.kml")
    
    if kml_path:
        f_info = files_info.get('kml', {})
        if f_info.get('size', 0) > 100 and f_info.get('created_during_task'):
            kml_score += 15
            try:
                tree = ET.parse(kml_path)
                root = tree.getroot()
                # KML namespace usually {http://www.opengis.net/kml/2.2}
                # Find all Placemarks regardless of namespace
                placemarks = []
                for elem in root.iter():
                    if 'Placemark' in elem.tag:
                        placemarks.append(elem)
                
                kml_count = len(placemarks)
                if kml_count >= 10:
                    kml_score += 8
                    feedback_parts.append(f"KML: Valid ({kml_count} placemarks)")
                else:
                    feedback_parts.append(f"KML: Valid but low count ({kml_count})")
            except Exception:
                feedback_parts.append("KML: Parsing error")
        else:
            feedback_parts.append("KML: Invalid file")
            
        os.unlink(kml_path)
    else:
        feedback_parts.append("KML: Not found")
        
    score += kml_score

    # ------------------------------------------------------------------
    # 4. Verify GML (15 pts existence + 7 pts content)
    # ------------------------------------------------------------------
    gml_score = 0
    gml_count = 0
    gml_path = get_file_content("south_america.gml")
    
    if gml_path:
        f_info = files_info.get('gml', {})
        if f_info.get('size', 0) > 100 and f_info.get('created_during_task'):
            gml_score += 15
            try:
                tree = ET.parse(gml_path)
                root = tree.getroot()
                # Count feature members. GML structure varies, usually wfs:member or gml:featureMember
                members = 0
                for elem in root.iter():
                    if 'featureMember' in elem.tag or 'member' in elem.tag:
                        # Ensure it's not the root container
                        if elem is not root: 
                            members += 1
                
                # If 0 members found via tags, try counting children of collection
                if members == 0 and len(list(root)) > 0:
                    members = len(list(root))

                gml_count = members
                if gml_count >= 10:
                    gml_score += 7
                    feedback_parts.append(f"GML: Valid ({gml_count} features)")
                else:
                    feedback_parts.append(f"GML: Low feature count ({gml_count})")
            except Exception:
                feedback_parts.append("GML: Parsing error")
        else:
             feedback_parts.append("GML: Invalid file")
        os.unlink(gml_path)
    else:
        feedback_parts.append("GML: Not found")
        
    score += gml_score

    # ------------------------------------------------------------------
    # 5. Verify CSV (15 pts existence + 7 pts content)
    # ------------------------------------------------------------------
    csv_score = 0
    csv_count = 0
    csv_path = get_file_content("south_america.csv")
    
    if csv_path:
        f_info = files_info.get('csv', {})
        if f_info.get('size', 0) > 50 and f_info.get('created_during_task'):
            csv_score += 15
            try:
                with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
                    reader = csv.reader(f)
                    header = next(reader, [])
                    rows = list(reader)
                    csv_count = len(rows)
                    
                    # Check header for 'continent' or 'name'
                    header_str = "".join(header).lower()
                    if 'name' in header_str or 'continent' in header_str:
                        if csv_count >= 10:
                            csv_score += 7
                            feedback_parts.append(f"CSV: Valid ({csv_count} rows)")
                        else:
                            feedback_parts.append(f"CSV: Low row count ({csv_count})")
                    else:
                        feedback_parts.append("CSV: Header missing expected columns")
            except Exception:
                 feedback_parts.append("CSV: Parsing error")
        else:
             feedback_parts.append("CSV: Invalid file")
        os.unlink(csv_path)
    else:
        feedback_parts.append("CSV: Not found")
    
    score += csv_score

    # ------------------------------------------------------------------
    # 6. Consistency Check (5 pts)
    # ------------------------------------------------------------------
    # We expect counts to be roughly equal (CSV might include/exclude header, 
    # GML might structure differently, but they should be close)
    counts = [c for c in [geojson_count, kml_count, gml_count, csv_count] if c > 0]
    if len(counts) >= 3:
        # Check if max difference is small
        if max(counts) - min(counts) <= 2:
            score += 5
            feedback_parts.append("Consistency: Counts match across formats")
        else:
            feedback_parts.append(f"Consistency: Counts vary {counts}")
    elif len(counts) > 0:
        feedback_parts.append("Consistency: Not enough valid files to compare")

    # ------------------------------------------------------------------
    # 7. No Extraneous Data (5 pts)
    # ------------------------------------------------------------------
    # Already checked in GeoJSON section mostly, award if GeoJSON score was high
    if geojson_score >= 25: # Full geojson points implies filter was correct
        score += 5
        feedback_parts.append("Filter: Correctly filtered to South America")

    # Final tally
    passed = score >= 60 and geojson_count >= 10
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }