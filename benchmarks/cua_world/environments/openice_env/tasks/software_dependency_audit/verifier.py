#!/usr/bin/env python3
"""
Verifier for OpenICE Software Dependency Audit task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_software_dependency_audit(traj, env_info, task_info):
    """
    Verifies the software audit report based on:
    1. File existence and creation time.
    2. Presence of required 5 sections.
    3. Accuracy of technical details compared to ground truth extracted from the repo.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Metadata (13 pts)
    report_exists = result.get('report_exists', False)
    file_created = result.get('file_created_during_task', False)
    report_size = int(result.get('report_size', 0))
    report_content = result.get('report_content_raw', "")
    ground_truth = result.get('ground_truth', {})

    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if report_size < 100:
        return {"passed": False, "score": 0, "feedback": "Report file is empty or too small."}

    score += 8  # Exists and has content
    feedback_parts.append("Report file exists")

    if file_created:
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp verification failed (pre-existing?)")

    # 2. Section Headers Check (10 pts)
    # Flexible matching for headers
    required_keywords = ["Module Structure", "Dependencies", "DDS", "Build System", "Risk"]
    sections_found = 0
    lower_content = report_content.lower()
    
    for kw in required_keywords:
        if kw.lower() in lower_content:
            sections_found += 1
    
    if sections_found == 5:
        score += 5
        score += 5 # Bonus for full structure
        feedback_parts.append("All report sections present")
    elif sections_found >= 3:
        score += 5
        feedback_parts.append(f"Most report sections present ({sections_found}/5)")
    else:
        feedback_parts.append(f"Missing report sections (found {sections_found}/5)")

    # 3. Content Verification vs Ground Truth
    
    # A. Modules (20 pts)
    # Ground truth is a comma-separated string of module paths (e.g. :interop-lab:demo-apps)
    gt_modules = [m.strip().replace(':', '') for m in ground_truth.get('modules', '').split(',') if m.strip()]
    # If parsing failed, fallback to some known OpenICE modules
    if not gt_modules:
        gt_modules = ["demo-apps", "demo-devices", "openice", "interop-lab"]
    
    modules_found_count = 0
    for mod in gt_modules:
        # Check if module name appears in report
        # Use word boundaries to avoid partial matches inside other words
        if re.search(r'\b' + re.escape(mod) + r'\b', lower_content):
            modules_found_count += 1
            
    if modules_found_count >= 5:
        score += 20
        feedback_parts.append(f"Excellent module enumeration ({modules_found_count} found)")
    elif modules_found_count >= 3:
        score += 15
        feedback_parts.append(f"Good module enumeration ({modules_found_count} found)")
    elif modules_found_count >= 1:
        score += 5
        feedback_parts.append("Some modules identified")
    else:
        feedback_parts.append("No correct module names found")

    # B. Dependencies (22 pts)
    gt_deps = [d.strip() for d in ground_truth.get('dependencies', '').split(',') if d.strip()]
    # Filter to just the artifact names (e.g., 'spring-core' from 'org.springframework:spring-core:5.0')
    gt_artifacts = []
    for dep in gt_deps:
        parts = dep.split(':')
        if len(parts) >= 2:
            gt_artifacts.append(parts[1])
        else:
            gt_artifacts.append(dep)
            
    # Also add some known OpenICE deps in case grep failed
    known_deps = ["javafx", "log4j", "slf4j", "junit", "spring", "rti", "jackson"]
    gt_artifacts.extend(known_deps)
    gt_artifacts = list(set(gt_artifacts)) # Unique
    
    deps_found_count = 0
    for art in gt_artifacts:
        if len(art) > 3 and re.search(r'\b' + re.escape(art.lower()) + r'\b', lower_content):
            deps_found_count += 1
            
    if deps_found_count >= 6:
        score += 22
        feedback_parts.append(f"Comprehensive dependency list ({deps_found_count} found)")
    elif deps_found_count >= 3:
        score += 15
        feedback_parts.append(f"Adequate dependency list ({deps_found_count} found)")
    elif deps_found_count >= 1:
        score += 5
        feedback_parts.append("Few dependencies identified")
    else:
        feedback_parts.append("No recognized dependencies found")

    # C. DDS Identification (15 pts)
    gt_dds = ground_truth.get('dds_vendor', 'RTI').lower()
    report_dds_correct = False
    
    if "rti" in gt_dds and ("rti" in lower_content or "connext" in lower_content):
        report_dds_correct = True
    elif "opendds" in gt_dds and "opendds" in lower_content:
        report_dds_correct = True
    elif "dds" in lower_content and ("middleware" in lower_content or "transport" in lower_content):
        # Partial credit if they mention DDS generally but miss the specific vendor
        score += 5
        feedback_parts.append("DDS mentioned but vendor unclear")
        
    if report_dds_correct:
        score += 15
        feedback_parts.append("DDS middleware correctly identified")

    # D. Build System/Gradle (12 pts)
    gt_gradle = ground_truth.get('gradle_version', '').lower()
    # Extract version numbers from ground truth (e.g. 7.6)
    gt_ver_match = re.search(r'(\d+\.\d+)', gt_gradle)
    gt_ver = gt_ver_match.group(1) if gt_ver_match else "unknown"
    
    if gt_ver != "unknown" and gt_ver in lower_content:
        score += 8
        feedback_parts.append(f"Gradle version {gt_ver} correct")
    elif "gradle" in lower_content:
        score += 4
        feedback_parts.append("Gradle mentioned but version missing/wrong")
        
    if "java" in lower_content and re.search(r'version \d+|java \d+|jdk', lower_content):
        score += 4
        feedback_parts.append("Java requirement mentioned")

    # E. Risk Classification (8 pts)
    # Check for "High", "Medium", "Low" keywords in close proximity to dependency-like names
    # Simple check: Does the report contain these classification words?
    if "high" in lower_content and "medium" in lower_content and "low" in lower_content:
        score += 8
        feedback_parts.append("Risk classification present")
    elif "risk" in lower_content and ("high" in lower_content or "low" in lower_content):
        score += 4
        feedback_parts.append("Partial risk classification")

    # Final pass/fail
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "modules_found": modules_found_count,
            "deps_found": deps_found_count,
            "dds_correct": report_dds_correct,
            "file_size": report_size
        }
    }