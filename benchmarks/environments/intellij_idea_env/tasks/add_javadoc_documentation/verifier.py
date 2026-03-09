#!/usr/bin/env python3
"""
Verifier for add_javadoc_documentation task.

Checks:
1. Source files modified (checksum verification)
2. Compilation success
3. Javadoc presence (Class and Method level regex checks)
4. Meaningful content heuristic
5. HTML documentation generation
6. VLM trajectory verification
"""

import json
import tempfile
import os
import re
import hashlib
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SOURCE_FILES = [
    "Pair.java",
    "ImmutablePair.java",
    "MutablePair.java",
    "Triple.java",
    "ImmutableTriple.java",
]
SRC_REL_PATH = "src/main/java/org/apache/commons/lang3/tuple"

def check_class_javadoc(content):
    """Check if public class declarations are preceded by Javadoc."""
    # Find public class/abstract class
    # Pattern: match Javadoc block followed optionally by annotations/whitespace, then class decl
    # Note: simple regex approach, may miss edge cases but sufficient for verification
    
    # We look for the class definition line
    class_pattern = r'public\s+(?:abstract\s+)?class\s+(\w+)'
    matches = list(re.finditer(class_pattern, content))
    
    documented_count = 0
    total_count = len(matches)
    
    for match in matches:
        start_idx = match.start()
        # Look backwards from class definition
        preceding_text = content[:start_idx]
        
        # Should find '*/' of javadoc
        javadoc_end = preceding_text.rfind('*/')
        
        if javadoc_end != -1:
            # Check distance - shouldn't be too far (ignoring imports/package)
            # Typically directly above or above annotations
            segment_between = preceding_text[javadoc_end+2:]
            
            # If segment only contains whitespace, annotations, or newlines, it's valid
            # remove annotations like @Deprecated
            segment_clean = re.sub(r'@\w+(\(.*\))?', '', segment_between).strip()
            
            if not segment_clean:
                # Find start of javadoc
                javadoc_start = preceding_text.rfind('/**', 0, javadoc_end)
                if javadoc_start != -1:
                    doc_block = preceding_text[javadoc_start:javadoc_end+2]
                    # check content length (meaningfulness)
                    if len(re.sub(r'[\s\*\/@]', '', doc_block)) > 10:
                        documented_count += 1
                        
    return documented_count, total_count

def check_method_javadoc(content):
    """Check if public methods have Javadoc."""
    # Pattern for methods: public [static] [final] [Type] [name](
    # Excluding constructors for simplicity in regex
    method_pattern = r'public\s+(?:static\s+)?(?:final\s+)?(?:[\w<>[\]]+\s+)(\w+)\s*\('
    
    matches = list(re.finditer(method_pattern, content))
    documented_count = 0
    total_count = 0
    
    for match in matches:
        method_name = match.group(1)
        # Skip constructors (heuristic: method name matches filename/class usually)
        if method_name in ["Pair", "ImmutablePair", "MutablePair", "Triple", "ImmutableTriple"]:
            continue
            
        total_count += 1
        
        start_idx = match.start()
        preceding_text = content[:start_idx]
        javadoc_end = preceding_text.rfind('*/')
        
        if javadoc_end != -1:
            segment_between = preceding_text[javadoc_end+2:]
            segment_clean = re.sub(r'@\w+(\(.*\))?', '', segment_between).strip()
            
            if not segment_clean:
                javadoc_start = preceding_text.rfind('/**', 0, javadoc_end)
                if javadoc_start != -1:
                    doc_block = preceding_text[javadoc_start:javadoc_end+2]
                    # Check for tags
                    has_param = '@param' in doc_block
                    has_return = '@return' in doc_block
                    # Check text length
                    if len(re.sub(r'[\s\*\/@]', '', doc_block)) > 10:
                        documented_count += 1

    return documented_count, total_count

def verify_add_javadoc_documentation(traj, env_info, task_info):
    """
    Verify the add_javadoc_documentation task.
    
    Scoring Breakdown:
    1. Code Modification (Modified files check) - 10 pts (Gatekeeper)
    2. Compilation Success - 10 pts
    3. Class-level Javadoc - 20 pts
    4. Method-level Javadoc & Tags - 30 pts
    5. HTML Generation - 10 pts
    6. Doc Report File - 5 pts
    7. VLM Verification - 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/tuple-utils')
    src_pkg_path = f"{project_dir}/{SRC_REL_PATH}"
    
    score = 0
    feedback_parts = []
    
    # Load result JSON
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result_data = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # Load stripped checksums
    stripped_checksums = {}
    try:
        tmp_chk = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        tmp_chk.close()
        copy_from_env(metadata.get('stripped_checksums_file', '/tmp/ground_truth/stripped_checksums.txt'), tmp_chk.name)
        with open(tmp_chk.name, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    fname = os.path.basename(parts[1])
                    stripped_checksums[fname] = parts[0]
        os.unlink(tmp_chk.name)
    except Exception:
        pass

    # --- Criterion 1: Files Modified (10 pts) ---
    files_modified = 0
    total_classes_found = 0
    documented_classes = 0
    total_methods_found = 0
    documented_methods = 0
    
    # iterate files
    for fname in SOURCE_FILES:
        try:
            tmp_src = tempfile.NamedTemporaryFile(delete=False, suffix='.java')
            tmp_src.close()
            copy_from_env(f"{src_pkg_path}/{fname}", tmp_src.name)
            
            with open(tmp_src.name, 'r', encoding='utf-8') as f:
                content = f.read()
            os.unlink(tmp_src.name)
            
            # Check modification
            curr_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()
            if fname in stripped_checksums and stripped_checksums[fname] != curr_hash:
                files_modified += 1
            
            # Check Class Javadoc
            c_doc, c_tot = check_class_javadoc(content)
            documented_classes += c_doc
            total_classes_found += c_tot
            
            # Check Method Javadoc
            m_doc, m_tot = check_method_javadoc(content)
            documented_methods += m_doc
            total_methods_found += m_tot
            
        except Exception as e:
            logger.warning(f"Error processing {fname}: {e}")

    if files_modified >= 3:
        score += 10
        feedback_parts.append(f"Source files modified ({files_modified}/5)")
    else:
        feedback_parts.append(f"Few source files modified ({files_modified}/5)")
        # Critical failure if no work done
        if files_modified == 0:
            return {"passed": False, "score": 0, "feedback": "No source files were modified."}

    # --- Criterion 2: Compilation (10 pts) ---
    if result_data.get('compile_success'):
        score += 10
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation failed")

    # --- Criterion 3: Class Javadoc (20 pts) ---
    if total_classes_found > 0:
        class_coverage = documented_classes / total_classes_found
        c_score = int(20 * class_coverage)
        score += c_score
        feedback_parts.append(f"Class Javadoc coverage: {documented_classes}/{total_classes_found}")
    
    # --- Criterion 4: Method Javadoc (30 pts) ---
    if total_methods_found > 0:
        method_coverage = documented_methods / total_methods_found
        m_score = int(30 * method_coverage)
        score += m_score
        feedback_parts.append(f"Method Javadoc coverage: {documented_methods}/{total_methods_found}")

    # --- Criterion 5: HTML Generation (10 pts) ---
    html_status = result_data.get('html_generated', 'false')
    if html_status == 'true':
        score += 10
        feedback_parts.append("Javadoc HTML generated")
    elif html_status == 'false_stale':
        feedback_parts.append("Javadoc HTML found but old (stale)")
    else:
        feedback_parts.append("Javadoc HTML not found")

    # --- Criterion 6: Doc Report (5 pts) ---
    if result_data.get('doc_report_exists'):
        score += 5
        feedback_parts.append("Documentation report created")
    
    # --- Criterion 7: VLM Verification (15 pts) ---
    from gym_anything.vlm import vlm_verify_intellij_task
    
    vlm_result = vlm_verify_intellij_task(
        traj, env_info,
        task_description="Add Javadoc documentation to Java files and generate HTML docs",
        checklist_items=[
            "Agent opened Java source files in editor",
            "Agent typed Javadoc comments (/** ... */)",
            "Agent used Maven tool window or terminal to run javadoc"
        ]
    )
    
    if vlm_result and vlm_result.get('vlm_passed'):
        score += 15
        feedback_parts.append("VLM: Workflow verified")
    elif vlm_result:
        # Partial credit if some items passed
        pass_rate = vlm_result.get('vlm_score', 0) / 100.0
        p_score = int(15 * pass_rate)
        score += p_score
        feedback_parts.append(f"VLM: Partial verification ({p_score}/15)")
    else:
        # Fallback if VLM fails/not avail
        score += 5
        feedback_parts.append("VLM: Not available (partial credit)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }