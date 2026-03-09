#!/usr/bin/env python3
"""
Verifier for Conduct Architecture Spike task
Checks that architecture spike workspace is properly set up
"""

import os
import sys
import json
import ast
import logging
import tempfile
import shutil
from pathlib import Path

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_architecture_spike(traj, env_info, task_info):
    """
    Verify that architecture spike workspace is properly configured.
    
    Checks 9 criteria (need 7/9 to pass):
    1. Directory structure (all 5 files exist)
    2. Redis implementation valid
    3. Memory implementation valid
    4. Benchmark exists and imports both
    5. VSCode settings.json configured
    6. VSCode launch.json configured
    7. FINDINGS.md documented
    8. Git has 2+ commits
    9. requirements.txt has redis
    
    Returns:
        dict with passed, score, feedback, metadata
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "metadata": {}
        }
    
    workspace_path = "/home/ga/workspace"
    spike_dir = f"{workspace_path}/session_spike"
    vscode_dir = f"{workspace_path}/.vscode"
    
    temp_dir = tempfile.mkdtemp(prefix='spike_verify_')
    
    try:
        issues = []
        success_criteria = {
            "directory_structure": False,
            "redis_implementation": False,
            "memory_implementation": False,
            "benchmark_exists": False,
            "vscode_settings": False,
            "vscode_launch": False,
            "findings_documented": False,
            "git_tracking": False,
            "requirements_file": False
        }
        
        # Define required files
        required_files = {
            "redis_approach": f"{spike_dir}/redis_approach.py",
            "memory_approach": f"{spike_dir}/memory_approach.py",
            "benchmark": f"{spike_dir}/benchmark.py",
            "requirements": f"{spike_dir}/requirements.txt",
            "findings": f"{spike_dir}/FINDINGS.md",
            "settings": f"{vscode_dir}/settings.json",
            "launch": f"{vscode_dir}/launch.json"
        }
        
        # Copy all files to temp directory
        copied_files = {}
        for key, container_path in required_files.items():
            local_path = os.path.join(temp_dir, f"{key}.file")
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    copied_files[key] = local_path
                else:
                    logger.debug(f"File not found or empty: {container_path}")
            except Exception as e:
                logger.debug(f"Failed to copy {container_path}: {e}")
        
        # Check 1: Directory structure (all 5 spike files exist)
        spike_files = ["redis_approach", "memory_approach", "benchmark", "requirements", "findings"]
        if all(f in copied_files for f in spike_files):
            success_criteria["directory_structure"] = True
        else:
            missing = [f for f in spike_files if f not in copied_files]
            issues.append(f"Missing spike files: {', '.join(missing)}")
        
        # Check 2: Redis implementation quality
        if "redis_approach" in copied_files:
            redis_code = read_file_content(copied_files["redis_approach"])
            if redis_code:
                try:
                    ast.parse(redis_code)  # Valid Python syntax
                    code_lower = redis_code.lower()
                    
                    has_redis = "redis" in code_lower or "import redis" in code_lower
                    has_class_or_def = "class " in redis_code or "def " in redis_code
                    has_set = "def set" in redis_code or "def put" in redis_code
                    has_get = "def get" in redis_code
                    
                    if has_redis and has_class_or_def and (has_set or has_get):
                        success_criteria["redis_implementation"] = True
                    else:
                        missing_parts = []
                        if not has_redis:
                            missing_parts.append("redis reference")
                        if not (has_set and has_get):
                            missing_parts.append("set/get methods")
                        issues.append(f"redis_approach.py incomplete: missing {', '.join(missing_parts)}")
                except SyntaxError as e:
                    issues.append(f"redis_approach.py syntax error: {str(e)[:50]}")
        
        # Check 3: Memory implementation quality
        if "memory_approach" in copied_files:
            memory_code = read_file_content(copied_files["memory_approach"])
            if memory_code:
                try:
                    ast.parse(memory_code)  # Valid Python syntax
                    
                    has_class_or_def = "class " in memory_code or "def " in memory_code
                    has_set = "def set" in memory_code or "def put" in memory_code
                    has_get = "def get" in memory_code
                    
                    if has_class_or_def and (has_set or has_get):
                        success_criteria["memory_implementation"] = True
                    else:
                        issues.append("memory_approach.py missing class/methods")
                except SyntaxError as e:
                    issues.append(f"memory_approach.py syntax error: {str(e)[:50]}")
        
        # Check 4: Benchmark exists and imports both approaches
        if "benchmark" in copied_files:
            benchmark_code = read_file_content(copied_files["benchmark"])
            if benchmark_code:
                has_redis_import = (
                    "redis_approach" in benchmark_code or 
                    "from redis_approach" in benchmark_code or
                    "import redis_approach" in benchmark_code
                )
                has_memory_import = (
                    "memory_approach" in benchmark_code or 
                    "from memory_approach" in benchmark_code or
                    "import memory_approach" in benchmark_code
                )
                has_timing = (
                    "time" in benchmark_code.lower() or 
                    "perf_counter" in benchmark_code or
                    "timeit" in benchmark_code.lower()
                )
                
                if has_redis_import and has_memory_import:
                    success_criteria["benchmark_exists"] = True
                    if not has_timing:
                        issues.append("benchmark.py missing timing logic (minor)")
                else:
                    missing = []
                    if not has_redis_import:
                        missing.append("redis_approach import")
                    if not has_memory_import:
                        missing.append("memory_approach import")
                    issues.append(f"benchmark.py missing: {', '.join(missing)}")
        
        # Check 5: VSCode settings configured
        if "settings" in copied_files:
            try:
                with open(copied_files["settings"], 'r', encoding='utf-8') as f:
                    settings = json.load(f)
                
                # Check for Python interpreter configuration
                python_keys = [k for k in settings.keys() if k.startswith("python.")]
                interpreter_keys = [
                    k for k in python_keys 
                    if "interpreter" in k.lower() or "pythonpath" in k.lower()
                ]
                
                if python_keys:  # Any Python configuration is acceptable
                    success_criteria["vscode_settings"] = True
                else:
                    issues.append("settings.json has no Python configuration")
            except json.JSONDecodeError:
                issues.append("settings.json is not valid JSON")
            except Exception as e:
                issues.append(f"settings.json error: {str(e)[:50]}")
        
        # Check 6: Launch configuration exists
        if "launch" in copied_files:
            try:
                with open(copied_files["launch"], 'r', encoding='utf-8') as f:
                    launch_config = json.load(f)
                
                if "configurations" in launch_config:
                    configs = launch_config["configurations"]
                    
                    # Look for benchmark-related configuration
                    benchmark_configs = [
                        c for c in configs 
                        if (
                            "benchmark" in c.get("name", "").lower() or
                            "benchmark.py" in c.get("program", "") or
                            "benchmark" in c.get("program", "").lower()
                        )
                    ]
                    
                    if benchmark_configs:
                        success_criteria["vscode_launch"] = True
                    else:
                        # Accept any Python debug configuration as partial credit
                        python_configs = [c for c in configs if c.get("type") == "python"]
                        if python_configs:
                            success_criteria["vscode_launch"] = True
                            issues.append("launch.json has Python config but not specifically for benchmark (acceptable)")
                        else:
                            issues.append("launch.json has no benchmark debug configuration")
                else:
                    issues.append("launch.json missing 'configurations' key")
            except json.JSONDecodeError:
                issues.append("launch.json is not valid JSON")
            except Exception as e:
                issues.append(f"launch.json error: {str(e)[:50]}")
        
        # Check 7: Findings documented
        if "findings" in copied_files:
            findings = read_file_content(copied_files["findings"])
            if findings:
                findings_lower = findings.lower()
                
                # Check for required sections (flexible matching)
                required_sections = {
                    "problem": ["problem", "background", "context", "motivation"],
                    "approach": ["approach", "solution", "method", "implementation"],
                    "result": ["result", "finding", "measurement", "benchmark", "outcome"],
                    "trade": ["trade", "pros", "cons", "comparison", "versus"]
                }
                
                sections_found = 0
                for section_name, keywords in required_sections.items():
                    if any(keyword in findings_lower for keyword in keywords):
                        sections_found += 1
                
                if sections_found >= 3:  # At least 3 of 4 sections
                    success_criteria["findings_documented"] = True
                else:
                    issues.append(f"FINDINGS.md missing sections (found {sections_found}/4)")
            else:
                issues.append("FINDINGS.md is empty")
        
        # Check 8: Git tracking (copy and parse git log)
        git_log_path = os.path.join(temp_dir, "git_log.txt")
        try:
            copy_from_env("/tmp/spike_export/git_log.txt", git_log_path)
        except:
            # Fallback: try to get git log directly
            try:
                copy_from_env(f"{workspace_path}/.git/logs/HEAD", git_log_path)
            except:
                pass
        
        commits = []
        if os.path.exists(git_log_path):
            with open(git_log_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and line != "No commits" and line != "No git repository":
                        parts = line.split('|', 3)
                        if len(parts) >= 2:
                            commits.append({
                                'hash': parts[0] if len(parts) > 0 else '',
                                'message': parts[1] if len(parts) > 1 else line
                            })
        
        if len(commits) >= 2:
            # Check if commits mention spike-related keywords
            spike_keywords = ["spike", "session", "redis", "memory", "benchmark", "approach", "storage"]
            spike_commits = [
                c for c in commits 
                if any(kw in c['message'].lower() for kw in spike_keywords)
            ]
            
            if len(spike_commits) >= 2:
                success_criteria["git_tracking"] = True
            else:
                issues.append(f"Git has {len(commits)} commits but only {len(spike_commits)} mention spike work")
        else:
            issues.append(f"Insufficient Git commits (found {len(commits)}, need 2+)")
        
        # Check 9: Requirements file
        if "requirements" in copied_files:
            requirements = read_file_content(copied_files["requirements"])
            if requirements and "redis" in requirements.lower():
                success_criteria["requirements_file"] = True
            else:
                if requirements:
                    issues.append("requirements.txt exists but doesn't list redis")
                else:
                    issues.append("requirements.txt is empty")
        
        # Calculate score
        criteria_met = sum(success_criteria.values())
        total_criteria = len(success_criteria)
        
        success = criteria_met >= 7  # Need 7/9 criteria
        score = int((criteria_met / total_criteria) * 100)
        
        # Generate feedback
        if success:
            feedback = f"✅ Architecture spike workspace successfully configured ({criteria_met}/{total_criteria} criteria met)"
            if issues:
                feedback += "\n\nMinor issues:\n" + "\n".join(f"  • {issue}" for issue in issues[:3])
        else:
            feedback = f"❌ Architecture spike incomplete ({criteria_met}/{total_criteria} criteria met, need 7)\n\n"
            feedback += "Issues:\n" + "\n".join(f"  • {issue}" for issue in issues[:5])
            
            # Add helpful hints
            if not success_criteria["directory_structure"]:
                feedback += "\n\nHint: Create session_spike/ directory with all 5 required files"
            if not success_criteria["git_tracking"]:
                feedback += "\n\nHint: Make at least 2 Git commits tracking your spike work"
        
        metadata = {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "success_criteria": success_criteria,
            "issues_count": len(issues),
            "commits_found": len(commits),
            "files_found": list(copied_files.keys())
        }
        
        return {
            "passed": success,
            "score": score,
            "feedback": feedback,
            "metadata": metadata
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "metadata": {"error": str(e)}
        }
    finally:
        cleanup_verification_temp(temp_dir)
