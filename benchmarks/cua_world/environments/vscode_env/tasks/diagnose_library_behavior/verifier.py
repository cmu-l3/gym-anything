#!/usr/bin/env python3
"""
Verifier for Diagnose Library Behavior task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_library_diagnosis(traj, env_info, task_info):
    """
    Verify that the user correctly diagnosed the library behavior and created the config.
    
    Checks:
    1. Config file .datamorph.config exists in project root
    2. Config file is valid JSON
    3. Config contains "parallel_enabled": true
    4. Config contains valid "workers" setting (positive integer)
    5. Script execution output confirms parallel processing is enabled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='datamorph_verify_')
    
    try:
        # Copy config file and execution output from /tmp
        config_local = os.path.join(temp_dir, "config.json")
        output_local = os.path.join(temp_dir, "output.txt")
        
        try:
            copy_from_env("/tmp/datamorph_config.json", config_local)
            copy_from_env("/tmp/datamorph_output.txt", output_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy verification files: {str(e)}"
            }
        
        feedback_parts = []
        
        # Check 1: Config file exists and is not empty
        if not os.path.exists(config_local) or os.path.getsize(config_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Configuration file .datamorph.config not found in project root (/home/ga/workspace/data_pipeline/)"
            }
        
        # Check if file is just empty JSON
        with open(config_local, 'r') as f:
            content = f.read().strip()
        
        if content == '{}':
            return {
                "passed": False,
                "score": 20,
                "feedback": "❌ Configuration file exists but is empty. Need to add parallel_enabled and workers settings"
            }
        
        feedback_parts.append("✅ Config file exists")
        
        # Check 2: Config is valid JSON
        try:
            with open(config_local, 'r') as f:
                config = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 20,
                "feedback": f"❌ Config file is not valid JSON: {str(e)}"
            }
        
        feedback_parts.append("✅ Config is valid JSON")
        
        # Check 3: parallel_enabled is set to true
        parallel_enabled = config.get('parallel_enabled', False)
        if not parallel_enabled:
            return {
                "passed": False,
                "score": 40,
                "feedback": f"❌ Config file exists but 'parallel_enabled' is not set to true. Current value: {parallel_enabled}"
            }
        
        feedback_parts.append("✅ parallel_enabled is true")
        
        # Check 4: workers setting is present and valid
        workers = config.get('workers')
        if workers is None:
            return {
                "passed": False,
                "score": 60,
                "feedback": "❌ Config file needs a 'workers' setting (positive integer)"
            }
        
        if not isinstance(workers, int) or workers < 1:
            return {
                "passed": False,
                "score": 60,
                "feedback": f"❌ 'workers' must be a positive integer, got: {workers} (type: {type(workers).__name__})"
            }
        
        feedback_parts.append(f"✅ workers configured ({workers})")
        
        # Check 5: Execution output confirms parallel processing
        if os.path.exists(output_local):
            with open(output_local, 'r') as f:
                output = f.read()
            
            # Look for the parallel processing confirmation message
            if 'Using parallel processing' in output:
                feedback_parts.append("✅ Script execution confirms parallel processing enabled")
            elif 'Using serial processing' in output:
                return {
                    "passed": False,
                    "score": 80,
                    "feedback": "❌ Config appears correct but script still reports serial processing. " + 
                               "Check that config file is in /home/ga/workspace/data_pipeline/"
                }
            elif 'Script execution failed' in output or 'timed out' in output:
                return {
                    "passed": False,
                    "score": 80,
                    "feedback": f"❌ Config appears correct but script failed to execute: {output[:200]}"
                }
            else:
                # Ambiguous output
                return {
                    "passed": False,
                    "score": 80,
                    "feedback": f"❌ Cannot confirm parallel processing from output. Output: {output[:200]}"
                }
        else:
            return {
                "passed": False,
                "score": 80,
                "feedback": "❌ Script output file not found - cannot verify execution"
            }
        
        # All checks passed!
        return {
            "passed": True,
            "score": 100,
            "feedback": " | ".join(feedback_parts) + " | 🎉 Successfully diagnosed and fixed library configuration!"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)
