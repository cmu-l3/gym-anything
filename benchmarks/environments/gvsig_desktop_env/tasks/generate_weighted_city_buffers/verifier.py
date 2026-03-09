#!/usr/bin/env python3
"""
Verifier for generate_weighted_city_buffers task.

Checks:
1. Shapefile creation and validity.
2. Geometry type (Polygon).
3. Number of features (should match input cities, implying no dissolve).
4. Geometry area variance (implies variable buffer sizes).
5. Correlation between buffer area and population attribute.
"""

import json
import os
import sys
import tempfile
import math
import logging
import statistics

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import pyshp, install if missing
try:
    import shapefile
except ImportError:
    import subprocess
    logger.info("Installing pyshp...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
    import shapefile

def calculate_polygon_area(points):
    """
    Calculate area of a polygon using shoelace formula.
    Points is a list of (x, y) tuples.
    """
    if len(points) < 3:
        return 0.0
    
    area = 0.0
    for i in range(len(points)):
        j = (i + 1) % len(points)
        area += points[i][0] * points[j][1]
        area -= points[j][0] * points[i][1]
    
    return abs(area) / 2.0

def verify_weighted_buffers(traj, env_info, task_info):
    """
    Verify the weighted buffers task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count_min = metadata.get('expected_feature_count_min', 200)

    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found at expected location"}
    
    score += 20
    feedback_parts.append("Output file exists")

    if result_data.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates pre-existence (gaming?)")

    # 2. Analyze Shapefile Content
    # We need .shp and .dbf and .shx
    temp_dir = tempfile.mkdtemp()
    try:
        # Copy shapefile components
        for ext in ['.shp', '.shx', '.dbf']:
            local_path = os.path.join(temp_dir, f"verify_output{ext}")
            try:
                copy_from_env(f"/tmp/verify_output{ext}", local_path)
            except Exception:
                pass # .shx might be missing, handled by pyshp usually or we fail later

        shp_path = os.path.join(temp_dir, "verify_output.shp")
        
        try:
            sf = shapefile.Reader(shp_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid shapefile: {e}"}

        # Check Geometry Type (5 = Polygon)
        if sf.shapeType not in [5, 15, 25]: # Polygon, PolygonZ, PolygonM
            feedback_parts.append(f"Wrong geometry type: {sf.shapeType} (expected Polygon)")
        else:
            score += 10
            feedback_parts.append("Correct geometry type (Polygon)")

        # Check Feature Count
        num_features = len(sf.shapes())
        if num_features >= expected_count_min:
            score += 20
            feedback_parts.append(f"Feature count ok ({num_features})")
        else:
            feedback_parts.append(f"Feature count low ({num_features}), expected > {expected_count_min}. Did you dissolve?")

        # Check Variable Sizes and Correlation
        # We need to map shapes to attributes.
        # Find POP_MAX field index
        fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag
        pop_idx = -1
        for i, field_name in enumerate(fields):
            if "POP" in field_name.upper():
                pop_idx = i
                break
        
        areas = []
        populations = []
        
        records = sf.records()
        shapes = sf.shapes()

        for i in range(min(len(records), len(shapes))):
            # Calculate area
            # Handle multi-polygons (pyshp returns list of parts)
            # Simple approx: sum of areas of parts
            # pyshp parts are indices in points list
            shape = shapes[i]
            total_area = 0
            
            if not shape.parts:
                continue
                
            parts = list(shape.parts) + [len(shape.points)]
            for j in range(len(parts) - 1):
                pts = shape.points[parts[j]:parts[j+1]]
                total_area += calculate_polygon_area(pts)
            
            areas.append(total_area)
            
            # Get population
            if pop_idx >= 0:
                try:
                    pop = float(records[i][pop_idx])
                    populations.append(pop)
                except (ValueError, TypeError):
                    populations.append(0)

        # Variance Check
        if len(areas) > 1:
            stdev_area = statistics.stdev(areas)
            if stdev_area > 0.0001: # Threshold for "not all same size"
                score += 25
                feedback_parts.append("Buffers have variable sizes")
            else:
                feedback_parts.append("All buffers are identical size (did not use field for distance?)")
        
        # Correlation Check
        correlation = 0
        if len(areas) > 10 and len(populations) == len(areas) and pop_idx >= 0:
            # Buffer Area ~ r^2 ~ (Pop)^2
            # So sqrt(Area) should correlate with Pop
            sqrt_areas = [math.sqrt(a) for a in areas]
            
            # Simple correlation coeff
            def mean(data): return sum(data) / len(data)
            mu_x = mean(populations)
            mu_y = mean(sqrt_areas)
            
            numerator = sum((x - mu_x) * (y - mu_y) for x, y in zip(populations, sqrt_areas))
            denom = math.sqrt(sum((x - mu_x)**2 for x in populations) * sum((y - mu_y)**2 for y in sqrt_areas))
            
            if denom != 0:
                correlation = numerator / denom
            
            if correlation > 0.8:
                score += 25
                feedback_parts.append(f"Size correlates with population (r={correlation:.2f})")
            else:
                feedback_parts.append(f"Low correlation between size and population (r={correlation:.2f})")
        elif pop_idx == -1:
            feedback_parts.append("Could not find POP attribute in output to verify correlation")

    except Exception as e:
        feedback_parts.append(f"Error analyzing shapefile: {e}")
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }