#!/usr/bin/env python3
"""
Verifier for Remote SSH Development Setup task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_remote_ssh_setup(traj, env_info, task_info):
    """
    Verify that Remote SSH development environment was set up correctly.
    
    Checks:
    1. SSH config file exists with correct connection details
    2. Remote VSCode Server is installed
    3. ESLint extension is installed remotely
    4. Remote workspace folder exists
    5. Node.js application file created with correct content
    6. Process is running on remote (as developer user)
    7. No process running locally (as ga user)
    8. Overall integration check
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='remote_ssh_verify_')
    
    try:
        results = {
            "ssh_config_valid": False,
            "remote_vscode_server_installed": False,
            "eslint_installed_remotely": False,
            "remote_workspace_exists": False,
            "application_file_exists": False,
            "application_code_valid": False,
            "process_running_remotely": False,
            "process_not_local": False
        }
        
        feedback_parts = []
        
        # Criterion 1: Check SSH config
        ssh_config_local = os.path.join(temp_dir, "ssh_config.txt")
        try:
            copy_from_env("/tmp/ssh_config.txt", ssh_config_local)
            
            if os.path.exists(ssh_config_local) and os.path.getsize(ssh_config_local) > 0:
                ssh_config = read_file_content(ssh_config_local)
                
                # Check for required SSH config elements
                required_elements = [
                    "Host devserver",
                    "HostName 127.0.0.1",
                    "Port 2222", 
                    "User developer",
                    "IdentityFile"
                ]
                
                # Flexible matching (case insensitive, whitespace tolerant)
                ssh_config_lower = ssh_config.lower()
                config_score = 0
                for element in required_elements:
                    if element.lower() in ssh_config_lower:
                        config_score += 1
                
                if config_score >= 4:  # At least 4/5 elements present
                    results["ssh_config_valid"] = True
                    feedback_parts.append(f"✅ SSH config valid ({config_score}/5 elements)")
                else:
                    feedback_parts.append(f"❌ SSH config incomplete ({config_score}/5 elements)")
            else:
                feedback_parts.append("❌ SSH config file not found or empty")
        except Exception as e:
            logger.warning(f"Failed to check SSH config: {e}")
            feedback_parts.append(f"❌ SSH config check failed: {str(e)[:50]}")
        
        # Criterion 2: Check VSCode Server installation on remote
        vscode_server_status_local = os.path.join(temp_dir, "vscode_server_status.txt")
        try:
            copy_from_env("/tmp/vscode_server_status.txt", vscode_server_status_local)
            
            if os.path.exists(vscode_server_status_local):
                status = read_file_content(vscode_server_status_local)
                if "installed" in status.lower():
                    results["remote_vscode_server_installed"] = True
                    feedback_parts.append("✅ VSCode Server installed on remote")
                else:
                    feedback_parts.append("❌ VSCode Server not installed on remote")
        except Exception as e:
            logger.warning(f"Failed to check VSCode Server: {e}")
            feedback_parts.append("❌ VSCode Server check failed")
        
        # Criterion 3: Check for ESLint extension on remote
        remote_extensions_local = os.path.join(temp_dir, "remote_extensions.txt")
        try:
            copy_from_env("/tmp/remote_extensions.txt", remote_extensions_local)
            
            if os.path.exists(remote_extensions_local):
                extensions = read_file_content(remote_extensions_local)
                
                # Check for ESLint extension (various possible names)
                if any(x in extensions.lower() for x in ['eslint', 'dbaeumer.vscode-eslint']):
                    results["eslint_installed_remotely"] = True
                    feedback_parts.append("✅ ESLint extension installed remotely")
                else:
                    if "no remote extensions" not in extensions.lower():
                        feedback_parts.append(f"❌ ESLint not found in remote extensions")
                    else:
                        feedback_parts.append("❌ No remote extensions directory")
        except Exception as e:
            logger.warning(f"Failed to check remote extensions: {e}")
            feedback_parts.append("❌ Remote extensions check failed")
        
        # Criterion 4: Check remote workspace
        workspace_status_local = os.path.join(temp_dir, "remote_workspace_status.txt")
        try:
            copy_from_env("/tmp/remote_workspace_status.txt", workspace_status_local)
            
            if os.path.exists(workspace_status_local):
                status = read_file_content(workspace_status_local)
                if "exists" in status.lower():
                    results["remote_workspace_exists"] = True
                    feedback_parts.append("✅ Remote workspace /home/developer/projects/ exists")
                else:
                    feedback_parts.append("❌ Remote workspace not created")
        except Exception as e:
            logger.warning(f"Failed to check workspace: {e}")
            feedback_parts.append("❌ Workspace check failed")
        
        # Criterion 5 & 6: Check application file and code
        hello_server_local = os.path.join(temp_dir, "hello_server_code.js")
        try:
            copy_from_env("/tmp/hello_server_code.js", hello_server_local)
            
            if os.path.exists(hello_server_local) and os.path.getsize(hello_server_local) > 0:
                code = read_file_content(hello_server_local)
                
                if "file not created" not in code.lower():
                    results["application_file_exists"] = True
                    feedback_parts.append("✅ hello-server.js file created")
                    
                    # Check code content
                    required_patterns = [
                        "require('http')",  # HTTP module import
                        "3000",  # Port number
                        "Hello from remote!"  # Response text
                    ]
                    
                    code_score = sum(1 for pattern in required_patterns if pattern in code)
                    
                    if code_score >= 2:  # At least 2/3 elements
                        results["application_code_valid"] = True
                        feedback_parts.append(f"✅ Application code valid ({code_score}/3 elements)")
                    else:
                        feedback_parts.append(f"❌ Application code incomplete ({code_score}/3 elements)")
                else:
                    feedback_parts.append("❌ Application file not created")
        except Exception as e:
            logger.warning(f"Failed to check application file: {e}")
            feedback_parts.append("❌ Application file check failed")
        
        # Criterion 7: Check Node.js process running as developer (remotely)
        remote_processes_local = os.path.join(temp_dir, "remote_node_processes.txt")
        try:
            copy_from_env("/tmp/remote_node_processes.txt", remote_processes_local)
            
            if os.path.exists(remote_processes_local):
                processes = read_file_content(remote_processes_local)
                
                # Check if developer user has node process
                if "developer" in processes and "node" in processes and "no node" not in processes.lower():
                    results["process_running_remotely"] = True
                    feedback_parts.append("✅ Node.js process running as developer user (remote)")
                else:
                    feedback_parts.append("❌ Node.js process not running on remote")
        except Exception as e:
            logger.warning(f"Failed to check remote process: {e}")
            feedback_parts.append("❌ Remote process check failed")
        
        # Criterion 8: Verify NOT running locally
        local_processes_local = os.path.join(temp_dir, "local_node_processes.txt")
        try:
            copy_from_env("/tmp/local_node_processes.txt", local_processes_local)
            
            if os.path.exists(local_processes_local):
                processes = read_file_content(local_processes_local)
                
                # Should NOT have ga user running node
                if "no local" in processes.lower() or "ga" not in processes or processes.strip() == "":
                    results["process_not_local"] = True
                    feedback_parts.append("✅ Confirmed: Process NOT running locally")
                else:
                    if "node" in processes:
                        feedback_parts.append("⚠️ Warning: Node.js process detected locally (should be remote only)")
                    else:
                        results["process_not_local"] = True
        except Exception as e:
            logger.warning(f"Failed to check local process: {e}")
            # Give benefit of doubt if we can't check
            results["process_not_local"] = True
        
        # Calculate score with weighted criteria
        weights = {
            "ssh_config_valid": 0.15,
            "remote_vscode_server_installed": 0.15,
            "eslint_installed_remotely": 0.10,
            "remote_workspace_exists": 0.10,
            "application_file_exists": 0.15,
            "application_code_valid": 0.15,
            "process_running_remotely": 0.15,
            "process_not_local": 0.05
        }
        
        score = sum(weights[k] for k, v in results.items() if v) * 100
        passed = score >= 85
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        criteria_met = sum(1 for v in results.values() if v)
        summary = f"Criteria met: {criteria_met}/8"
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": f"{summary} | {feedback}",
            "details": results
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
