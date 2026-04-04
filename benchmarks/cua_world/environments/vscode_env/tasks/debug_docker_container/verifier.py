#!/usr/bin/env python3
"""
Verifier for Debug Docker Container task
"""

import sys
import os
import logging
import tempfile
import json
import re
import subprocess

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_docker_container(traj, env_info, task_info):
    """
    Verify that VSCode is configured to debug Flask app in Docker container.
    
    Checks:
    1. debugpy installed in container
    2. Port 5678 exposed from container
    3. main.py contains debugpy import and listen call
    4. .vscode/launch.json exists with correct attach configuration
    5. Container is running
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    checks = {
        "container_running": False,
        "debugpy_installed": False,
        "port_exposed": False,
        "main_py_has_import": False,
        "main_py_has_listen": False,
        "launch_json_exists": False,
        "launch_config_valid": False,
        "attach_type_correct": False,
        "port_correct": False,
        "path_mappings_correct": False,
    }
    
    feedback_parts = []
    temp_dir = tempfile.mkdtemp(prefix='docker_debug_verify_')
    
    try:
        # Copy exported data
        docker_status_local = os.path.join(temp_dir, "docker_status.txt")
        docker_ports_local = os.path.join(temp_dir, "docker_ports.txt")
        debugpy_status_local = os.path.join(temp_dir, "debugpy_status.txt")
        main_py_local = os.path.join(temp_dir, "main.py")
        launch_json_local = os.path.join(temp_dir, "launch.json")
        
        try:
            copy_from_env("/tmp/docker_status.txt", docker_status_local)
            copy_from_env("/tmp/docker_ports.txt", docker_ports_local)
            copy_from_env("/tmp/debugpy_status.txt", debugpy_status_local)
            copy_from_env("/tmp/main_py_container.py", main_py_local)
            copy_from_env("/tmp/launch_json_export.json", launch_json_local)
        except Exception as e:
            logger.warning(f"Failed to copy some files: {e}")
        
        # Check 1: Container is running
        if os.path.exists(docker_status_local):
            with open(docker_status_local, 'r') as f:
                status_content = f.read()
                if 'flask_debug_app' in status_content and ('Up' in status_content or 'running' in status_content.lower()):
                    checks["container_running"] = True
                    feedback_parts.append("✅ Container 'flask_debug_app' is running")
                else:
                    feedback_parts.append(f"❌ Container not running properly: {status_content[:100]}")
        
        # Check 2: debugpy installed in container
        if os.path.exists(debugpy_status_local):
            with open(debugpy_status_local, 'r') as f:
                debugpy_content = f.read()
                if 'Name: debugpy' in debugpy_content or 'debugpy' in debugpy_content.lower():
                    if 'not installed' not in debugpy_content.lower():
                        checks["debugpy_installed"] = True
                        feedback_parts.append("✅ debugpy installed in container")
                    else:
                        feedback_parts.append("❌ debugpy not installed (run: docker exec flask_debug_app pip install debugpy)")
                else:
                    feedback_parts.append("❌ debugpy not installed in container")
        
        # Check 3: Port 5678 exposed
        if os.path.exists(docker_ports_local):
            with open(docker_ports_local, 'r') as f:
                ports_content = f.read()
                if '5678' in ports_content:
                    checks["port_exposed"] = True
                    feedback_parts.append("✅ Port 5678 exposed from container")
                else:
                    feedback_parts.append("❌ Port 5678 not exposed (update docker-compose.yml and restart)")
        
        # Check 4: main.py has debugpy setup
        if os.path.exists(main_py_local) and os.path.getsize(main_py_local) > 0:
            with open(main_py_local, 'r') as f:
                main_py_content = f.read()
            
            # Check for import
            if 'import debugpy' in main_py_content or 'from debugpy' in main_py_content:
                checks["main_py_has_import"] = True
                feedback_parts.append("✅ debugpy imported in main.py")
            else:
                feedback_parts.append("❌ debugpy not imported in main.py")
            
            # Check for listen call
            if re.search(r'debugpy\.listen\s*\(', main_py_content):
                # Also check if it's listening on correct port
                if '5678' in main_py_content:
                    checks["main_py_has_listen"] = True
                    feedback_parts.append("✅ debugpy.listen() called on port 5678")
                else:
                    feedback_parts.append("⚠️ debugpy.listen() found but port may be incorrect")
            else:
                feedback_parts.append("❌ debugpy.listen() not called in main.py")
        else:
            feedback_parts.append("❌ Could not read main.py")
        
        # Check 5: launch.json exists and is valid
        if os.path.exists(launch_json_local) and os.path.getsize(launch_json_local) > 2:
            checks["launch_json_exists"] = True
            
            try:
                with open(launch_json_local, 'r') as f:
                    launch_config = json.load(f)
                
                checks["launch_config_valid"] = True
                
                # Find attach configuration
                configs = launch_config.get('configurations', [])
                attach_config = None
                
                for config in configs:
                    if config.get('request') == 'attach' and config.get('type') == 'python':
                        attach_config = config
                        checks["attach_type_correct"] = True
                        break
                
                if attach_config:
                    feedback_parts.append("✅ Python attach configuration found")
                    
                    # Check port
                    connect = attach_config.get('connect', {})
                    port = connect.get('port')
                    
                    if port == 5678:
                        checks["port_correct"] = True
                        feedback_parts.append("✅ Debug port correctly set to 5678")
                    else:
                        feedback_parts.append(f"❌ Debug port incorrect (expected 5678, found {port})")
                    
                    # Check path mappings
                    path_mappings = attach_config.get('pathMappings', [])
                    
                    correct_mapping = False
                    for mapping in path_mappings:
                        local_root = mapping.get('localRoot', '').lower()
                        remote_root = mapping.get('remoteRoot', '')
                        
                        # Accept variations
                        if ('app' in local_root or '/app' in local_root) and remote_root == '/app':
                            correct_mapping = True
                            checks["path_mappings_correct"] = True
                            feedback_parts.append("✅ Path mappings correct (app/ -> /app)")
                            break
                    
                    if not correct_mapping:
                        feedback_parts.append("❌ Path mappings incorrect (should map local app/ to remote /app)")
                else:
                    feedback_parts.append("❌ No Python attach configuration found in launch.json")
            
            except json.JSONDecodeError as e:
                feedback_parts.append(f"❌ Invalid JSON in launch.json: {str(e)[:50]}")
            except Exception as e:
                feedback_parts.append(f"❌ Error parsing launch.json: {str(e)[:50]}")
        else:
            feedback_parts.append("❌ .vscode/launch.json not found or empty")
        
        # Calculate score
        total_checks = len(checks)
        passed_checks = sum(checks.values())
        score = int((passed_checks / total_checks) * 100)
        
        # Critical checks that must pass for success
        critical_checks = [
            checks["debugpy_installed"],
            checks["port_exposed"],
            checks["main_py_has_import"],
            checks["main_py_has_listen"],
            checks["launch_json_exists"],
            checks["attach_type_correct"],
            checks["port_correct"],
            checks["path_mappings_correct"]
        ]
        
        critical_passed = sum(critical_checks)
        critical_total = len(critical_checks)
        
        # Pass if at least 80% of critical checks pass
        passed = (critical_passed / critical_total) >= 0.8
        
        if passed:
            feedback = "✅ Docker debug configuration complete! " + " | ".join(feedback_parts[:3])
        else:
            feedback = " | ".join(feedback_parts[:5])  # Show first 5 feedback items
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "checks": checks,
                "critical_passed": f"{critical_passed}/{critical_total}",
                "all_feedback": feedback_parts
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
        # Cleanup temp directory
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
