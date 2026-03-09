#!/usr/bin/env python3
"""
Verifier for Trace Cryptic Error task
"""

import sys
import os
import logging
import tempfile
import json
import difflib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_investigation(traj, env_info, task_info):
    """
    Verify that debugging investigation was completed correctly.
    
    Checks:
    1. Launch configuration exists and is valid (30 points)
    2. Diagnostic instrumentation added (35 points)
    3. Findings documented correctly (35 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='debug_verify_')
    
    try:
        # Copy exported files
        launch_json_local = os.path.join(temp_dir, "launch.json")
        data_processor_local = os.path.join(temp_dir, "data_processor.py")
        findings_local = os.path.join(temp_dir, "findings.txt")
        original_script_local = os.path.join(temp_dir, "data_processor_original.py")
        
        try:
            copy_from_env("/tmp/launch.json", launch_json_local)
            copy_from_env("/tmp/data_processor.py", data_processor_local)
            copy_from_env("/tmp/findings.txt", findings_local)
            copy_from_env("/tmp/data_processor_original.py", original_script_local)
        except Exception as e:
            logger.warning(f"Failed to copy some files: {e}")

        total_score = 0
        feedback_parts = []
        
        # ===== CRITERION 1: Launch Configuration (30 points) =====
        launch_score = 0
        launch_feedback = []
        
        if os.path.exists(launch_json_local) and os.path.getsize(launch_json_local) > 2:
            try:
                with open(launch_json_local, 'r') as f:
                    launch_config = json.load(f)
                
                # Check if it's a valid VSCode launch config
                if 'configurations' in launch_config or 'version' in launch_config:
                    launch_score += 10
                    launch_feedback.append("✅ Valid launch.json structure")
                    
                    configs = launch_config.get('configurations', [])
                    if not configs and 'type' in launch_config:
                        # Single config format
                        configs = [launch_config]
                    
                    # Check for Python debug configuration
                    python_config_found = False
                    targets_correct_file = False
                    
                    for config in configs:
                        config_type = config.get('type', '').lower()
                        if 'python' in config_type or 'debugpy' in config_type:
                            python_config_found = True
                            launch_score += 10
                            launch_feedback.append("✅ Python debug configuration present")
                            
                            # Check if it targets data_processor.py
                            program = config.get('program', '')
                            if 'data_processor.py' in program:
                                targets_correct_file = True
                                launch_score += 10
                                launch_feedback.append("✅ Targets data_processor.py")
                            break
                    
                    if not python_config_found:
                        launch_feedback.append("❌ No Python debug configuration found")
                    elif not targets_correct_file:
                        launch_feedback.append("⚠️ Debug config doesn't target data_processor.py")
                else:
                    launch_feedback.append("⚠️ launch.json exists but has unexpected structure")
                    launch_score += 5
                    
            except json.JSONDecodeError:
                launch_feedback.append("❌ launch.json is not valid JSON")
        else:
            launch_feedback.append("❌ launch.json not found or empty")
        
        total_score += launch_score
        feedback_parts.extend(launch_feedback)
        
        # ===== CRITERION 2: Diagnostic Instrumentation (35 points) =====
        instrumentation_score = 0
        instrumentation_feedback = []
        
        if os.path.exists(data_processor_local) and os.path.exists(original_script_local):
            original_content = read_file_content(original_script_local)
            modified_content = read_file_content(data_processor_local)
            
            if original_content and modified_content:
                # Check if file was modified
                if original_content != modified_content:
                    instrumentation_score += 5
                    instrumentation_feedback.append("✅ data_processor.py was modified")
                    
                    # Count diagnostic statements added
                    original_lines = original_content.split('\n')
                    modified_lines = modified_content.split('\n')
                    
                    # Look for print, logging, or debug statements
                    diagnostic_patterns = [
                        'print(',
                        'logging.',
                        'logger.',
                        'print (',
                        'debug(',
                        'console.log'
                    ]
                    
                    # Count new diagnostic statements
                    new_diagnostics = 0
                    for line in modified_lines:
                        line_lower = line.strip().lower()
                        if any(pattern in line_lower for pattern in diagnostic_patterns):
                            # Check if this line wasn't in original
                            if line.strip() not in [l.strip() for l in original_lines]:
                                new_diagnostics += 1
                    
                    if new_diagnostics >= 3:
                        instrumentation_score += 20
                        instrumentation_feedback.append(f"✅ Added {new_diagnostics} diagnostic statements")
                    elif new_diagnostics > 0:
                        instrumentation_score += int((new_diagnostics / 3) * 20)
                        instrumentation_feedback.append(f"⚠️ Added {new_diagnostics} diagnostic statements (expected 3+)")
                    else:
                        instrumentation_feedback.append("❌ No diagnostic statements detected")
                    
                    # Check if diagnostics are near the error location (validate_nested function)
                    strategic_placement = False
                    in_validate_nested = False
                    for i, line in enumerate(modified_lines):
                        if 'def validate_nested' in line:
                            in_validate_nested = True
                        elif in_validate_nested and ('def ' in line or (i > 0 and modified_lines[i-1].startswith('def '))):
                            in_validate_nested = False
                        
                        if in_validate_nested:
                            if any(pattern in line.lower() for pattern in diagnostic_patterns):
                                if line.strip() not in [l.strip() for l in original_lines]:
                                    strategic_placement = True
                                    break
                    
                    if strategic_placement:
                        instrumentation_score += 10
                        instrumentation_feedback.append("✅ Strategic placement near error location")
                    else:
                        instrumentation_feedback.append("⚠️ No diagnostics near validate_nested function")
                        
                else:
                    instrumentation_feedback.append("❌ data_processor.py was not modified")
            else:
                instrumentation_feedback.append("❌ Could not read script files")
        else:
            instrumentation_feedback.append("❌ Script files not found")
        
        total_score += instrumentation_score
        feedback_parts.extend(instrumentation_feedback)
        
        # ===== CRITERION 3: Findings Documentation (35 points) =====
        findings_score = 0
        findings_feedback = []
        
        if os.path.exists(findings_local) and os.path.getsize(findings_local) > 10:
            findings_content = read_file_content(findings_local).lower()
            
            if findings_content:
                findings_feedback.append("✅ findings.txt exists with content")
                findings_score += 5
                
                # Check for line number (should be around 47, ±3)
                has_line_number = False
                for num in range(44, 51):  # Lines 44-50
                    if str(num) in findings_content or f'line {num}' in findings_content:
                        has_line_number = True
                        findings_score += 10
                        findings_feedback.append(f"✅ Correct line number identified (~line {num})")
                        break
                
                if not has_line_number:
                    # Check if any line number is mentioned
                    if 'line' in findings_content or any(str(i) in findings_content for i in range(1, 100)):
                        findings_feedback.append("⚠️ Line number mentioned but incorrect")
                        findings_score += 5
                    else:
                        findings_feedback.append("❌ No line number identified")
                
                # Check for problematic variable identification
                variable_keywords = ['schema_version', 'metadata', 'version']
                has_variable = any(keyword in findings_content for keyword in variable_keywords)
                if has_variable:
                    findings_score += 10
                    findings_feedback.append("✅ Problematic variable identified")
                else:
                    findings_feedback.append("❌ Problematic variable not identified")
                
                # Check for root cause explanation
                cause_keywords = [
                    'type', 'string', 'int', 'integer', 
                    'str', 'mismatch', 'expect', 'format',
                    'convert', 'cast'
                ]
                has_cause_explanation = sum(1 for keyword in cause_keywords if keyword in findings_content) >= 2
                if has_cause_explanation:
                    findings_score += 10
                    findings_feedback.append("✅ Root cause explanation present")
                else:
                    findings_feedback.append("❌ Root cause explanation insufficient")
                    
            else:
                findings_feedback.append("❌ findings.txt is empty")
        else:
            findings_feedback.append("❌ findings.txt not found or too short")
        
        total_score += findings_score
        feedback_parts.extend(findings_feedback)
        
        # ===== FINAL SCORING =====
        passed = total_score >= 65
        
        # Add summary
        summary = f"Launch: {launch_score}/30 | Instrumentation: {instrumentation_score}/35 | Findings: {findings_score}/35"
        feedback_parts.insert(0, summary)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
