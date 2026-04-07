#!/usr/bin/env python3
import json
import os
import base64
import csv
import io
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_world_geodetic_audit(traj, env_info, task_info):
    """
    Verify the world geodetic audit task.
    
    Score Breakdown (100 pts):
    - CSV Catalog (60 pts):
        - File exists & header correct (10)
        - Row count matches world count (10)
        - Data accuracy (40) - 10 per category (Coords, Dims, Area, Res)
    - Audit Report (40 pts):
        - File exists & length > 50 lines (10)
        - Key terminology used (10)
        - Training recommendations present (10)
        - Specific world names referenced (10)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    try:
        import tempfile
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        
        copy_from_env("/tmp/task_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Extract ground truth from the file path referenced in result
        copy_from_env("/tmp/ground_truth_worlds.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result files: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    score = 0
    feedback = []
    
    # --- PART 1: CSV Verification (60 pts) ---
    csv_data = result.get('csv', {})
    if csv_data.get('exists') and csv_data.get('modified'):
        score += 10
        feedback.append("CSV file created successfully.")
        
        try:
            content = base64.b64decode(csv_data.get('content_base64', '')).decode('utf-8')
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
            
            # Check row count
            if len(rows) == len(ground_truth):
                score += 10
                feedback.append(f"Row count matches ground truth ({len(rows)} worlds).")
            else:
                feedback.append(f"Row count mismatch: Found {len(rows)}, expected {len(ground_truth)}.")
                # Give partial credit if close
                if abs(len(rows) - len(ground_truth)) <= 1:
                    score += 5

            # Verify Data Accuracy
            matches_coords = 0
            matches_dims = 0
            matches_area = 0
            matches_res = 0
            
            total_worlds = len(ground_truth)
            if total_worlds > 0:
                for gt_world in ground_truth:
                    # Find matching row in agent CSV (fuzzy match on name)
                    agent_row = None
                    for row in rows:
                        # Normalize names for comparison
                        if gt_world['WorldName'].lower() in row.get('WorldName', '').lower() or \
                           row.get('WorldName', '').lower() in gt_world['WorldName'].lower():
                            agent_row = row
                            break
                    
                    if agent_row:
                        try:
                            # 1. Coordinates (Lat, Long, Extents) - Tol: 0.05
                            t_lat = float(agent_row['TerrainLat'])
                            t_long = float(agent_row['TerrainLong'])
                            t_ext_lat = float(agent_row['LatExtent'])
                            t_ext_long = float(agent_row['LongExtent'])
                            
                            if (abs(t_lat - gt_world['TerrainLat']) < 0.05 and
                                abs(t_long - gt_world['TerrainLong']) < 0.05 and
                                abs(t_ext_lat - gt_world['LatExtent']) < 0.05 and
                                abs(t_ext_long - gt_world['LongExtent']) < 0.05):
                                matches_coords += 1
                                
                            # 2. Dimensions (Width, Height, Depth) - Tol: Exact for dim, 1.0 for depth
                            if (int(float(agent_row['MapWidth'])) == gt_world['MapWidth'] and
                                int(float(agent_row['MapHeight'])) == gt_world['MapHeight'] and
                                abs(float(agent_row['SeaMaxDepth']) - gt_world['SeaMaxDepth']) <= 1.0):
                                matches_dims += 1
                                
                            # 3. Area - Tol: 20%
                            area = float(agent_row['AreaSqNm'])
                            if gt_world['AreaSqNm'] > 0:
                                diff_pct = abs(area - gt_world['AreaSqNm']) / gt_world['AreaSqNm']
                                if diff_pct < 0.20:
                                    matches_area += 1
                            elif area == 0:
                                matches_area += 1 # Both zero
                                
                            # 4. Resolution - Tol: 20%
                            res = float(agent_row['ResolutionMetersPerPixel'])
                            if gt_world['ResolutionMetersPerPixel'] > 0:
                                diff_pct = abs(res - gt_world['ResolutionMetersPerPixel']) / gt_world['ResolutionMetersPerPixel']
                                if diff_pct < 0.20:
                                    matches_res += 1
                            elif res == 0:
                                matches_res += 1
                                
                        except (ValueError, KeyError) as e:
                            pass # Formatting error in row

                # Scale scores based on % matched
                score += int((matches_coords / total_worlds) * 10)
                score += int((matches_dims / total_worlds) * 10)
                score += int((matches_area / total_worlds) * 10)
                score += int((matches_res / total_worlds) * 10)
                
                feedback.append(f"Data Accuracy: Coords {matches_coords}/{total_worlds}, Dims {matches_dims}/{total_worlds}, Area {matches_area}/{total_worlds}, Res {matches_res}/{total_worlds}")

        except Exception as e:
            feedback.append(f"Error parsing CSV content: {str(e)}")
    else:
        feedback.append("CSV file not found or not created during task.")

    # --- PART 2: Report Verification (40 pts) ---
    report_data = result.get('report', {})
    if report_data.get('exists') and report_data.get('modified'):
        
        # Length check
        if report_data.get('line_count', 0) >= 50:
            score += 10
            feedback.append("Report length requirement met (>= 50 lines).")
        else:
            score += 5
            feedback.append(f"Report too short ({report_data.get('line_count')} lines).")

        try:
            content = base64.b64decode(report_data.get('content_base64', '')).decode('utf-8').lower()
            
            # Key terminology
            terms = ['latitude', 'longitude', 'resolution', 'nautical', 'extent', 'wgs84', 'bathymetry']
            found_terms = sum(1 for term in terms if term in content)
            if found_terms >= 4:
                score += 10
                feedback.append(f"Technical terminology used ({found_terms} terms found).")
            else:
                feedback.append(f"Missing technical terminology (only {found_terms} found).")

            # Training recommendations
            rec_keywords = ['open ocean', 'confined', 'coastal', 'training', 'suitability']
            found_recs = sum(1 for kw in rec_keywords if kw in content)
            if found_recs >= 3:
                score += 10
                feedback.append("Training recommendations section detected.")
            else:
                feedback.append("Missing clear training recommendations.")

            # World names check
            found_worlds = 0
            for w in ground_truth:
                if w['WorldName'].lower() in content:
                    found_worlds += 1
            
            if found_worlds >= 1:
                score += 10
                feedback.append(f"Report references specific worlds ({found_worlds} found).")
            else:
                feedback.append("Report does not reference installed world names.")
                
        except Exception as e:
            feedback.append(f"Error reading report content: {str(e)}")
    else:
        feedback.append("Report file not found or not created during task.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }