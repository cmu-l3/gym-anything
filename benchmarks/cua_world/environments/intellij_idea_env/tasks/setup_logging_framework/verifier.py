#!/usr/bin/env python3
"""Verifier for setup_logging_framework task."""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_setup_logging_framework(traj, env_info, task_info):
    """
    Verify that the user has correctly set up SLF4J/Logback and refactored the code.
    
    Scoring:
    - SLF4J dependency in pom.xml (10 pts)
    - Logback dependency in pom.xml (10 pts)
    - logback.xml exists and valid (15 pts)
    - No System.out.println remaining (20 pts)
    - No System.err.println remaining (5 pts)
    - Logger declared in modified classes (15 pts)
    - Log levels appropriately used (10 pts)
    - Project compiles successfully (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check POM Dependencies (20 pts)
    pom_content = result.get('pom_content', '')
    has_slf4j = 'slf4j-api' in pom_content
    has_logback = 'logback-classic' in pom_content
    
    if has_slf4j:
        score += 10
        feedback.append("SLF4J dependency found.")
    else:
        feedback.append("Missing 'slf4j-api' dependency.")
        
    if has_logback:
        score += 10
        feedback.append("Logback dependency found.")
    else:
        feedback.append("Missing 'logback-classic' dependency.")

    # 2. Check Logback Configuration (15 pts)
    logback_exists = result.get('logback_exists', False)
    logback_content = result.get('logback_content', '')
    
    if logback_exists:
        # Simple validity check
        if '<configuration>' in logback_content and '<appender' in logback_content and '<root' in logback_content:
            score += 15
            feedback.append("Valid logback.xml configuration found.")
        else:
            score += 5
            feedback.append("logback.xml exists but content seems incomplete.")
    else:
        feedback.append("logback.xml not found in src/main/resources.")

    # 3. Check Java Files Refactoring
    java_files = result.get('java_files', {})
    total_sys_out = 0
    total_sys_err = 0
    files_with_logger = 0
    correct_levels = 0
    
    expected_files = ["LibraryApp.java", "BookService.java", "BookRepository.java", "SearchEngine.java"]
    
    for fname, content in java_files.items():
        if fname not in expected_files: 
            continue
            
        # Count remaining prints
        sys_out = content.count("System.out.println")
        sys_err = content.count("System.err.println")
        total_sys_out += sys_out
        total_sys_err += sys_err
        
        # Check Logger declaration
        # Look for: Logger logger = LoggerFactory.getLogger(...)
        has_logger_decl = bool(re.search(r'Logger\s+\w+\s*=\s*LoggerFactory\.getLogger', content))
        if has_logger_decl:
            files_with_logger += 1
            
        # Check usage of levels
        has_info = 'logger.info(' in content
        has_debug = 'logger.debug(' in content
        has_error = 'logger.error(' in content
        has_warn = 'logger.warn(' in content
        
        # Heuristic for correct level usage
        if fname == 'BookRepository.java':
            if has_error: correct_levels += 1 # It has a catch block
        if fname == 'BookService.java':
            if has_warn: correct_levels += 1 # It has a warn condition
            
    # Score: No System.out remaining (20 pts)
    if total_sys_out == 0:
        score += 20
        feedback.append("All System.out.println calls removed.")
    else:
        feedback.append(f"{total_sys_out} System.out.println calls remaining.")

    # Score: No System.err remaining (5 pts)
    if total_sys_err == 0:
        score += 5
        feedback.append("All System.err.println calls removed.")
    else:
        feedback.append(f"{total_sys_err} System.err.println calls remaining.")
        
    # Score: Logger declared (15 pts) - roughly 3.75 pts per file
    if files_with_logger == 4:
        score += 15
        feedback.append("Logger declared in all required files.")
    else:
        points = int(files_with_logger * (15/4))
        score += points
        feedback.append(f"Logger declared in {files_with_logger}/4 files.")
        
    # Score: Log levels (10 pts)
    # If we see mix of info/debug/error/warn usage across files, give points
    level_score = 0
    all_content = "".join(java_files.values())
    if 'logger.info' in all_content: level_score += 2
    if 'logger.debug' in all_content: level_score += 2
    if 'logger.error' in all_content: level_score += 3
    if 'logger.warn' in all_content: level_score += 3
    score += level_score
    if level_score < 10:
        feedback.append("Some log levels (info/debug/warn/error) appear unused.")

    # 4. Check Compilation (15 pts)
    compile_success = result.get('compile_success', False)
    if compile_success:
        score += 15
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("Project compilation FAILED.")
        
    # Final Pass/Fail
    passed = score >= 60 and compile_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }