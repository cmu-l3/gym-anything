#!/usr/bin/env python3
"""
Verifier for FastAPI Debug Configuration task
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


def verify_fastapi_debug_config(traj, env_info, task_info):
    """
    Verify that FastAPI debug configuration was created correctly.

    Checks:
    1. .vscode/launch.json file exists
    2. JSON is valid and parseable
    3. Configuration named "FastAPI Debug" exists (case-insensitive)
    4. Environment variable DATABASE_URL is set correctly
    5. Arguments include --config config.yaml and --port 8080
    6. Python interpreter points to virtual environment (.venv)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='fastapi_debug_verify_')

    try:
        # Copy launch.json exported by export_result.sh
        launch_json_path = "/tmp/launch.json"
        local_launch_json = os.path.join(temp_dir, "launch.json")

        try:
            copy_from_env(launch_json_path, local_launch_json)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy launch.json: {str(e)}"
            }

        # Check if file exists and is not the "not_found" marker
        if not os.path.exists(local_launch_json):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ launch.json file not found at .vscode/launch.json"
            }

        # Check if it's the "not_found" marker
        with open(local_launch_json, 'r') as f:
            first_line = f.readline().strip()
            if first_line == "not_found":
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "❌ launch.json file not found at .vscode/launch.json"
                }

        # Parse JSON
        try:
            with open(local_launch_json, 'r', encoding='utf-8') as f:
                launch_config = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ launch.json is not valid JSON: {str(e)}"
            }

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Criterion 1: File exists and is valid JSON (already checked above)
        criteria_passed += 1
        feedback_parts.append("✅ launch.json exists and is valid JSON")

        # Criterion 2: Check configurations array exists
        if "configurations" not in launch_config:
            feedback_parts.append("❌ Missing 'configurations' array in launch.json")
            score = int((criteria_passed / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        configs = launch_config["configurations"]
        if not isinstance(configs, list) or len(configs) == 0:
            feedback_parts.append("❌ No debug configurations found in 'configurations' array")
            score = int((criteria_passed / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        criteria_passed += 1
        feedback_parts.append(f"✅ Found {len(configs)} configuration(s)")

        # Find "FastAPI Debug" configuration (case-insensitive)
        fastapi_config = None
        for config in configs:
            config_name = config.get("name", "")
            if config_name.lower() == "fastapi debug":
                fastapi_config = config
                break

        if not fastapi_config:
            feedback_parts.append("❌ No configuration named 'FastAPI Debug' found (case-insensitive)")
            # List available configs for debugging
            config_names = [c.get("name", "unnamed") for c in configs]
            feedback_parts.append(f"Available configs: {', '.join(config_names)}")
            score = int((criteria_passed / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        criteria_passed += 1
        feedback_parts.append(f"✅ Configuration 'FastAPI Debug' found")

        # Criterion 3: Check program/module points to app.py
        program = fastapi_config.get("program", "")
        module = fastapi_config.get("module", "")
        script = fastapi_config.get("script", "")
        
        has_correct_program = False
        if "app.py" in program or "app.py" in module or "app.py" in script:
            has_correct_program = True
        elif "app" in module:  # module can be just "app" without .py
            has_correct_program = True
        
        if has_correct_program:
            criteria_passed += 1
            feedback_parts.append("✅ Program/module set to app.py")
        else:
            feedback_parts.append(f"❌ Program/module not set to app.py (found: program='{program}', module='{module}')")

        # Criterion 4: Check environment variables
        env_vars = fastapi_config.get("env", {})
        has_db_url = False
        
        if "DATABASE_URL" in env_vars:
            db_value = env_vars["DATABASE_URL"]
            if "postgresql://localhost/testdb" in db_value:
                has_db_url = True
                criteria_passed += 1
                feedback_parts.append(f"✅ DATABASE_URL environment variable set correctly")
            else:
                feedback_parts.append(f"❌ DATABASE_URL has incorrect value: '{db_value}' (expected 'postgresql://localhost/testdb')")
        else:
            feedback_parts.append("❌ Missing DATABASE_URL environment variable")

        # Criterion 5: Check arguments
        args = fastapi_config.get("args", [])
        
        # Convert to string for easier checking
        if isinstance(args, list):
            args_str = " ".join(str(arg) for arg in args)
        elif isinstance(args, str):
            args_str = args
        else:
            args_str = ""

        has_config_arg = "--config" in args_str and "config.yaml" in args_str
        has_port_arg = "--port" in args_str and "8080" in args_str

        if has_config_arg and has_port_arg:
            criteria_passed += 1
            feedback_parts.append("✅ Arguments include --config config.yaml and --port 8080")
        else:
            missing = []
            if not has_config_arg:
                missing.append("--config config.yaml")
            if not has_port_arg:
                missing.append("--port 8080")
            feedback_parts.append(f"❌ Missing arguments: {', '.join(missing)} (found: '{args_str}')")

        # Criterion 6: Check Python interpreter path
        python_path = fastapi_config.get("python", "") or fastapi_config.get("pythonPath", "")
        
        # Also check if it's using default Python with cwd in venv
        cwd = fastapi_config.get("cwd", "")
        
        has_venv_python = False
        if ".venv" in python_path or "venv" in python_path:
            has_venv_python = True
        elif "${workspaceFolder}/.venv" in python_path:
            has_venv_python = True
        
        if has_venv_python:
            criteria_passed += 1
            feedback_parts.append(f"✅ Python interpreter points to virtual environment")
        else:
            feedback_parts.append(f"❌ Python interpreter doesn't point to .venv (found: '{python_path}')")

        # Calculate score and determine pass/fail
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # 5 out of 6 criteria

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": {
                "criteria_passed": criteria_passed,
                "total_criteria": total_criteria,
                "config_name": fastapi_config.get("name"),
                "has_env_vars": "DATABASE_URL" in env_vars,
                "has_correct_args": has_config_arg and has_port_arg,
                "uses_venv": has_venv_python
            }
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
