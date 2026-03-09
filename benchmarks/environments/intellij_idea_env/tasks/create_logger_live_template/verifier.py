#!/usr/bin/env python3
"""Verifier for create_logger_live_template task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_logger_live_template(traj, env_info, task_info):
    """
    Verify the creation and usage of a Live Template.
    
    Criteria:
    1. Custom.xml file created in templates config (10 pts)
    2. Template 'logger' exists with correct abbreviation (10 pts)
    3. Template text contains correct SLF4J pattern (20 pts)
    4. Variable $CLASS$ is bound to expression 'className()' (30 pts)
    5. Context is set to Java (10 pts)
    6. PaymentService.java contains the expanded logger line (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: Template File Exists (10 pts) ---
    if result.get('template_file_exists'):
        score += 10
        feedback_parts.append("Custom template group created")
        
        # Anti-gaming check: modified during task?
        if result.get('file_modified_during_task'):
            feedback_parts.append("(Created during task)")
        else:
            feedback_parts.append("(WARNING: File timestamp predates task start)")
    else:
        feedback_parts.append("Custom.xml template file not found")
        return {"passed": False, "score": 0, "feedback": "Template file not found"}

    # --- Parse XML Content ---
    xml_content = result.get('template_file_content', '')
    try:
        root = ET.fromstring(xml_content)
        
        # Find the 'logger' template
        template_node = None
        for tmpl in root.findall(".//template"):
            if tmpl.get("name") == "logger":
                template_node = tmpl
                break
        
        if template_node is not None:
            # --- Check 2: Abbreviation (10 pts) ---
            # Implicitly true if we found it by name="logger"
            score += 10
            feedback_parts.append("Template 'logger' found")
            
            # --- Check 3: Template Text (20 pts) ---
            value = template_node.get("value", "")
            expected_fragments = ["private static final", "org.slf4j.Logger", "LoggerFactory.getLogger"]
            if all(frag in value for frag in expected_fragments):
                score += 20
                feedback_parts.append("Template text correct")
            else:
                feedback_parts.append(f"Template text missing required parts. Found: '{value}'")

            # --- Check 4: Variable Logic (30 pts) ---
            # Looking for <variable name="CLASS" expression="className()" ... />
            variable_correct = False
            for var in template_node.findall("variable"):
                expression = var.get("expression", "")
                if "className()" in expression:
                    variable_correct = True
                    break
            
            if variable_correct:
                score += 30
                feedback_parts.append("Variable correctly bound to className()")
            else:
                feedback_parts.append("Variable expression incorrect (must use className())")

            # --- Check 5: Context (10 pts) ---
            context_node = template_node.find("context")
            if context_node is not None:
                # Check for Java context option
                options = context_node.findall("option")
                is_java = any(opt.get("name", "").startswith("JAVA") and opt.get("value") == "true" for opt in options)
                if is_java:
                    score += 10
                    feedback_parts.append("Context set to Java")
                else:
                    feedback_parts.append("Context defined but Java not enabled")
            else:
                feedback_parts.append("No context defined")
                
        else:
            feedback_parts.append("Template 'logger' not found in Custom.xml")

    except ET.ParseError:
        feedback_parts.append("Failed to parse Custom.xml")

    # --- Check 6: File Application (20 pts) ---
    java_content = result.get('java_file_content', '')
    # Expected: private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(PaymentService.class);
    # Be flexible with whitespace
    expected_pattern = r'private\s+static\s+final\s+org\.slf4j\.Logger\s+log\s*=\s*org\.slf4j\.LoggerFactory\.getLogger\s*\(\s*PaymentService\.class\s*\)\s*;'
    
    if re.search(expected_pattern, java_content):
        score += 20
        feedback_parts.append("Template successfully applied to PaymentService.java")
    else:
        # Check partial match (maybe they didn't use fully qualified names if imports were added manually)
        if "LoggerFactory.getLogger(PaymentService.class)" in java_content:
            score += 15
            feedback_parts.append("Logger present but format differs slightly (check fully qualified names)")
        else:
            feedback_parts.append("PaymentService.java does not contain expected logger line")

    # VLM Verification (Optional but good for robust check)
    # We could add VLM here to check if they opened the Settings dialog,
    # but the XML verification is very strong evidence for this specific task.

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }