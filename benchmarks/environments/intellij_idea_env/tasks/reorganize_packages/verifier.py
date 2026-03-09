#!/usr/bin/env python3
"""Verifier for reorganize_packages task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorganize_packages(traj, env_info, task_info):
    """
    Verify that the project was correctly refactored into packages.
    
    Scoring Criteria (100 pts):
    1. Build Success (30 pts): 'mvn compile' passes.
    2. File Location (40 pts): 
       - Model classes (Book, Member, Loan) in com/library/model (15 pts)
       - Service classes in com/library/service (10 pts)
       - Util classes in com/library/util (10 pts)
       - App class in com/library/app (5 pts)
    3. Code Correctness (30 pts):
       - Correct 'package' statements in moved files (15 pts)
       - Correct 'import' statements (checking explicit imports between packages) (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/library-system')
    
    score = 0
    feedback_parts = []
    
    # --- Load Result JSON ---
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # --- Criterion 1: Build Success (30 pts) ---
    if result.get('build_success', False):
        score += 30
        feedback_parts.append("Build Success (+30)")
    else:
        feedback_parts.append("Build Failed (0/30)")
        # If build failed, we still check structure but cap score later potentially

    # --- Helper to read file content ---
    def get_file_content(rel_path):
        full_path = f"{project_dir}/{rel_path}"
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.java')
            tmp.close()
            copy_from_env(full_path, tmp.name)
            if not os.path.exists(tmp.name) or os.path.getsize(tmp.name) == 0:
                os.unlink(tmp.name)
                return None
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception:
            if os.path.exists(tmp.name): os.unlink(tmp.name)
            return None

    # --- Criterion 2: File Locations (40 pts) ---
    structure_score = 0
    
    expected_locations = {
        "model": ["Book", "Member", "Loan"],
        "service": ["LibraryService", "SearchService"],
        "util": ["DateUtils", "ValidationUtils"],
        "app": ["LibraryApp"]
    }
    
    file_contents = {} # Cache content for next step
    
    for pkg, files in expected_locations.items():
        pkg_path = f"src/main/java/com/library/{pkg}"
        for cls in files:
            rel_path = f"{pkg_path}/{cls}.java"
            content = get_file_content(rel_path)
            
            if content:
                file_contents[cls] = content
                # Points distribution
                if pkg == "model": structure_score += 5   # 3 * 5 = 15
                if pkg == "service": structure_score += 5 # 2 * 5 = 10
                if pkg == "util": structure_score += 5    # 2 * 5 = 10
                if pkg == "app": structure_score += 5     # 1 * 5 = 5
            else:
                feedback_parts.append(f"Missing {cls}.java in {pkg}")

    score += structure_score
    feedback_parts.append(f"Structure Score: {structure_score}/40")

    # --- Criterion 3: Code Correctness (30 pts) ---
    syntax_score = 0
    
    # Check Package Declarations (15 pts)
    # 8 files total. ~2 pts each.
    pkg_correct_count = 0
    for cls, content in file_contents.items():
        # Determine expected package
        expected_pkg = ""
        for p, fs in expected_locations.items():
            if cls in fs: expected_pkg = f"com.library.{p}"
        
        if f"package {expected_pkg};" in content:
            pkg_correct_count += 1
            
    # Normalize to 15 pts
    if len(file_contents) > 0:
        syntax_score += int((pkg_correct_count / 8) * 15)
    
    if pkg_correct_count == 8:
        feedback_parts.append("All package declarations correct (+15)")
    else:
        feedback_parts.append(f"Package declarations: {pkg_correct_count}/8 correct")

    # Check Imports (15 pts)
    # Key check: Services must import Model and Util classes now
    # Previous state: No imports (same package)
    # New state: LibraryService needs 'import com.library.model.Book;' etc.
    
    import_checks = 0
    import_checks_passed = 0
    
    if "LibraryService" in file_contents:
        ls_content = file_contents["LibraryService"]
        import_checks += 1
        if "import com.library.model.Book;" in ls_content or "import com.library.model.*;" in ls_content:
            import_checks_passed += 1
        else:
            feedback_parts.append("LibraryService missing Book import")
            
        import_checks += 1
        if "import com.library.util.DateUtils;" in ls_content or "import com.library.util.*;" in ls_content:
             import_checks_passed += 1

    if "Loan" in file_contents:
        loan_content = file_contents["Loan"]
        import_checks += 1
        # Loan needs Member and Book. Since Loan/Member/Book are all in model, they DON'T need imports for each other.
        # But Loan needs to NOT have wrong imports.
        # Actually, let's check ValidationUtils which needs Member
        pass

    if "ValidationUtils" in file_contents:
        vu_content = file_contents["ValidationUtils"]
        import_checks += 1
        # ValidationUtils (util) uses Member (model)
        if "import com.library.model.Member;" in vu_content:
             import_checks_passed += 1
    
    if import_checks > 0:
        import_score = int((import_checks_passed / import_checks) * 15)
        syntax_score += import_score
        feedback_parts.append(f"Import checks: {import_checks_passed}/{import_checks} passed")
    else:
        # Fallback if files missing
        feedback_parts.append("Skipping import checks (files missing)")

    score += syntax_score
    
    # --- Final Score Calculation ---
    passed = score >= 70 and result.get('build_success', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }