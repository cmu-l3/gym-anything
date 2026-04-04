#!/usr/bin/env python3
"""
Verifier for Debug Background Worker task
"""

import sys
import os
import logging
import tempfile
import shutil
import json

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import copy_and_parse_json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_worker_debug(traj, env_info, task_info):
    """
    Verify background worker debugging task completion.
    
    Checks:
    1. Launch configuration created (25 points)
    2. Config bug fixed (30 points)
    3. Test job present (15 points)
    4. Job completed (20 points)
    5. Output artifacts created (10 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0.0
    max_score = 100.0
    feedback_parts = []
    
    # Criterion 1: Check launch configuration (25 points)
    launch_json_path = "/home/ga/workspace/thumbnail_service/.vscode/launch.json"
    try:
        success, launch_config, error = copy_and_parse_json(launch_json_path, copy_from_env)
        
        if success and launch_config:
            configs = launch_config.get("configurations", [])
            python_configs = [c for c in configs if c.get("type") == "python" or c.get("type") == "debugpy"]
            
            if python_configs:
                score += 20
                feedback_parts.append("✅ Python debug configuration created")
                
                # Check if targets worker.py
                worker_config = None
                for c in python_configs:
                    program = c.get("program", "").lower()
                    if "worker" in program or "worker.py" in program:
                        worker_config = c
                        break
                
                if worker_config:
                    score += 3
                    feedback_parts.append("✅ Configuration targets worker.py")
                    
                    # Bonus: check if named appropriately
                    name = worker_config.get("name", "").lower()
                    if "worker" in name:
                        score += 2
                        feedback_parts.append(f"✅ Configuration well-named: '{worker_config.get('name')}'")
                else:
                    feedback_parts.append("⚠️ Configuration doesn't explicitly target worker.py")
            else:
                feedback_parts.append("❌ No Python debug configuration found")
        else:
            feedback_parts.append(f"❌ Launch configuration not found or invalid")
    except Exception as e:
        logger.warning(f"Error checking launch configuration: {e}")
        feedback_parts.append(f"❌ Error checking launch.json: {str(e)[:50]}")
    
    # Criterion 2: Check config.yaml fix (30 points)
    config_yaml_path = "/home/ga/workspace/thumbnail_service/config.yaml"
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.yaml')
    
    try:
        copy_from_env(config_yaml_path, temp_config.name)
        
        if os.path.exists(temp_config.name) and os.path.getsize(temp_config.name) > 0:
            import yaml
            with open(temp_config.name, 'r') as f:
                config = yaml.safe_load(f)
            
            thumbnail_width = config.get('thumbnail_width')
            
            if thumbnail_width and isinstance(thumbnail_width, int) and 0 < thumbnail_width <= 1000:
                score += 30
                feedback_parts.append(f"✅ thumbnail_width fixed to {thumbnail_width}")
            elif thumbnail_width == 0:
                feedback_parts.append("❌ thumbnail_width still set to 0 (must be positive)")
            else:
                feedback_parts.append(f"❌ thumbnail_width invalid: {thumbnail_width} (must be 1-1000)")
        else:
            feedback_parts.append("❌ config.yaml not found or empty")
    except Exception as e:
        logger.warning(f"Error checking config.yaml: {e}")
        feedback_parts.append(f"❌ Error reading config.yaml: {str(e)[:50]}")
    finally:
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
    
    # Criterion 3: Check test job added (15 points)
    queue_json_path = "/home/ga/workspace/thumbnail_service/queue.json"
    jobs = []
    
    try:
        success, queue_data, error = copy_and_parse_json(queue_json_path, copy_from_env)
        
        if success and queue_data:
            jobs = queue_data if isinstance(queue_data, list) else queue_data.get('jobs', [])
            
            if jobs and len(jobs) > 0:
                # Check if jobs have required fields
                valid_jobs = [
                    j for j in jobs 
                    if all(k in j for k in ['id', 'image_path', 'status'])
                ]
                
                if valid_jobs:
                    score += 15
                    feedback_parts.append(f"✅ Test job(s) present ({len(valid_jobs)} valid jobs)")
                else:
                    feedback_parts.append("❌ Jobs missing required fields (id, image_path, status)")
            else:
                feedback_parts.append("❌ No jobs found in queue.json")
        else:
            feedback_parts.append(f"❌ queue.json not found or invalid")
    except Exception as e:
        logger.warning(f"Error checking queue.json: {e}")
        feedback_parts.append(f"❌ Error reading queue.json: {str(e)[:50]}")
    
    # Criterion 4: Check job completion (20 points)
    try:
        if jobs:
            completed_jobs = [
                j for j in jobs 
                if j.get('status', '').lower() in ['completed', 'success', 'done', 'processed']
            ]
            
            if completed_jobs:
                score += 20
                feedback_parts.append(f"✅ Job processing verified ({len(completed_jobs)} completed)")
            else:
                # Check if any failed jobs
                failed_jobs = [j for j in jobs if j.get('status', '').lower() == 'failed']
                if failed_jobs:
                    error_msg = failed_jobs[0].get('error', 'Unknown error')
                    feedback_parts.append(f"❌ Jobs failed: {error_msg[:60]}")
                else:
                    pending_jobs = [j for j in jobs if j.get('status', '').lower() == 'pending']
                    if pending_jobs:
                        feedback_parts.append(f"❌ {len(pending_jobs)} jobs still pending (worker not run?)")
                    else:
                        feedback_parts.append("❌ No completed jobs found")
        else:
            feedback_parts.append("❌ Cannot verify job completion (no jobs)")
    except Exception as e:
        logger.warning(f"Error verifying job completion: {e}")
        feedback_parts.append(f"❌ Error checking completion: {str(e)[:50]}")
    
    # Criterion 5: Check output artifacts (10 points)
    output_dir_path = "/home/ga/workspace/thumbnail_service/output"
    temp_output_dir = tempfile.mkdtemp(prefix='verify_output_')
    
    try:
        # Try to copy entire output directory
        try:
            copy_from_env(output_dir_path, temp_output_dir)
        except:
            # If directory copy fails, try individual file listing
            pass
        
        # Check for files in temp directory
        output_files = []
        if os.path.exists(temp_output_dir):
            for item in os.listdir(temp_output_dir):
                item_path = os.path.join(temp_output_dir, item)
                if os.path.isfile(item_path):
                    file_size = os.path.getsize(item_path)
                    if file_size > 1024:  # At least 1KB
                        output_files.append((item, file_size))
        
        if output_files:
            score += 10
            feedback_parts.append(f"✅ Output artifacts created ({len(output_files)} files)")
        else:
            feedback_parts.append("❌ No valid output files found (expected thumbnails in output/)")
    except Exception as e:
        logger.warning(f"Error checking output: {e}")
        feedback_parts.append(f"⚠️ Could not verify output directory")
    finally:
        if os.path.exists(temp_output_dir):
            shutil.rmtree(temp_output_dir, ignore_errors=True)
    
    # Calculate final result
    percentage = (score / max_score) * 100
    passed = percentage >= 75.0
    
    feedback_message = " | ".join(feedback_parts)
    feedback_message += f"\n\nFinal Score: {score:.0f}/{max_score:.0f} ({percentage:.1f}%)"
    
    if passed:
        feedback_message += "\n✅ PASSED: Worker debugging setup complete"
    else:
        feedback_message += "\n❌ FAILED: Task incomplete (need 75%)"
        
        # Add helpful hints
        hints = []
        if score < 25:
            hints.append("Create .vscode/launch.json with Python debug config")
        if 25 <= score < 55:
            hints.append("Fix thumbnail_width in config.yaml (change 0 to positive number)")
        if 55 <= score < 70:
            hints.append("Ensure queue.json has jobs with id, image_path, status fields")
        if 70 <= score < 75:
            hints.append("Run the worker (python worker.py) to process jobs")
        
        if hints:
            feedback_message += "\n💡 Hints: " + "; ".join(hints)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_message
    }
