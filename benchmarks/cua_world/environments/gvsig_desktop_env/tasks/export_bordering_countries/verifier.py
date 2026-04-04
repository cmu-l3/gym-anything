#!/usr/bin/env python3
"""
Verifier for export_bordering_countries task.

Verifies that the user exported a shapefile containing only the neighbors of Germany.
"""

import json
import os
import sys
import tempfile
import logging
import shutil

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def install_pyshp():
    """Try to install pyshp if not available."""
    try:
        import shapefile
        return True
    except ImportError:
        try:
            import subprocess
            logger.info("Installing pyshp...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
            return True
        except Exception as e:
            logger.error(f"Failed to install pyshp: {e}")
            return False

def verify_export_bordering_countries(traj, env_info, task_info):
    """
    Verify the exported shapefile of Germany's neighbors.
    """
    # ensure pyshp is available
    if not install_pyshp():
        return {"passed": False, "score": 0, "feedback": "Verifier failed to initialize dependencies"}
        
    import shapefile

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_neighbors = set(metadata.get('expected_neighbors', [
        "Austria", "Belgium", "Czechia", "Denmark", "France", 
        "Luxembourg", "Netherlands", "Poland", "Switzerland"
    ]))
    target_country = metadata.get('target_country', "Germany")
    
    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check existence
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found"}
    
    if not result.get('created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task session"}

    if not result.get('sidecars_exist', False):
        return {"passed": False, "score": 10, "feedback": "Shapefile is missing required sidecar files (.dbf/.shx)"}

    # Retrieve the shapefile components for analysis
    temp_dir = tempfile.mkdtemp()
    shp_path = os.path.join(temp_dir, "neighbors.shp")
    shx_path = os.path.join(temp_dir, "neighbors.shx")
    dbf_path = os.path.join(temp_dir, "neighbors.dbf")
    
    try:
        copy_from_env(result['output_path'], shp_path)
        copy_from_env(result['output_shx_path'], shx_path)
        copy_from_env(result['output_dbf_path'], dbf_path)
        
        # Analyze content
        sf = shapefile.Reader(shp_path)
        
        # Find the NAME field index
        fields = [f[0] for f in sf.fields[1:]] # Skip DeletionFlag
        name_idx = -1
        for i, field in enumerate(fields):
            if field.upper() == 'NAME' or field.upper() == 'ADMIN':
                name_idx = i
                break
        
        if name_idx == -1:
            return {"passed": False, "score": 20, "feedback": "Could not find 'NAME' field in exported shapefile"}
            
        records = sf.records()
        exported_countries = set()
        for r in records:
            # Handle potential encoding issues or padding
            val = r[name_idx]
            if isinstance(val, bytes):
                val = val.decode('utf-8', errors='ignore')
            exported_countries.add(str(val).strip())
            
        logger.info(f"Exported countries: {exported_countries}")
        
        # Scoring logic
        score = 0
        feedback = []
        
        # 1. Check if target (Germany) is excluded (Critical)
        if target_country in exported_countries:
            feedback.append(f"FAILED: Output contains {target_country}, which should be excluded.")
            target_excluded = False
        else:
            feedback.append(f"SUCCESS: {target_country} correctly excluded.")
            score += 20
            target_excluded = True
            
        # 2. Check overlap with expected neighbors
        found_neighbors = exported_countries.intersection(expected_neighbors)
        missing_neighbors = expected_neighbors - exported_countries
        extra_countries = exported_countries - expected_neighbors
        
        # Remove target from extra_countries if present (already penalized)
        extra_countries.discard(target_country)
        
        neighbor_count = len(found_neighbors)
        expected_count = len(expected_neighbors)
        
        # Score for finding neighbors (up to 40 pts)
        neighbor_score = (neighbor_count / expected_count) * 40
        score += neighbor_score
        
        feedback.append(f"Found {neighbor_count}/{expected_count} expected neighbors.")
        if missing_neighbors:
            feedback.append(f"Missing: {', '.join(missing_neighbors)}.")
            
        # 3. Penalty for false positives (non-neighbors)
        if extra_countries:
            penalty = len(extra_countries) * 5
            score = max(0, score - penalty)
            feedback.append(f"included {len(extra_countries)} non-neighbor countries (e.g., {list(extra_countries)[:3]}).")
        else:
            score += 20 # Bonus for clean result
            feedback.append("No incorrect countries included.")
            
        # 4. Basic file validity points
        score += 20 # For creating a valid, readable shapefile
        
        passed = (score >= 70) and target_excluded and (neighbor_count >= 5)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error analyzing shapefile: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)