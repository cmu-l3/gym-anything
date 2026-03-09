#!/usr/bin/env python3
"""
Verifier for convert_java_to_kotlin task.

Scoring System (100 points):
- Files Converted (30 pts):
  - Word.kt exists (10)
  - WordDao.kt exists (10)
  - WordViewModel.kt exists (10)
- Source Validity (24 pts):
  - Word.kt has proper content/annotations (8)
  - WordDao.kt has proper content/annotations (8)
  - WordViewModel.kt has proper content (8)
- Clean State (6 pts):
  - Original Java files removed (3)
  - Untouched files remain Java (3)
- Build Success (40 pts):
  - Project compiles successfully (40)
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_convert_java_to_kotlin(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy unavailable"}

    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    if not result:
        return {"passed": False, "score": 0, "feedback": "No result file generated"}

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence (30 pts)
    files_ok = 0
    if result.get("word_kt_exists"):
        score += 10
        files_ok += 1
    if result.get("word_dao_kt_exists"):
        score += 10
        files_ok += 1
    if result.get("word_vm_kt_exists"):
        score += 10
        files_ok += 1
    
    feedback_parts.append(f"Converted files existence: {files_ok}/3")

    # 2. Check Content Validity (24 pts)
    # Word.kt
    word_content = result.get("word_kt_content", "")
    if "class Word" in word_content and "@Entity" in word_content and "val" in word_content:
        score += 8
    elif result.get("word_kt_exists"):
        feedback_parts.append("Word.kt exists but missing Kotlin constructs or annotations")

    # WordDao.kt
    dao_content = result.get("word_dao_kt_content", "")
    if "interface WordDao" in dao_content and "@Dao" in dao_content and "fun" in dao_content:
        score += 8
    elif result.get("word_dao_kt_exists"):
        feedback_parts.append("WordDao.kt exists but missing Kotlin constructs")

    # WordViewModel.kt
    vm_content = result.get("word_vm_kt_content", "")
    if "class WordViewModel" in vm_content and "AndroidViewModel" in vm_content:
        score += 8
    elif result.get("word_vm_kt_exists"):
        feedback_parts.append("WordViewModel.kt exists but missing Kotlin constructs")

    # 3. Clean State (6 pts)
    java_gone = not (result.get("word_java_exists") or result.get("word_dao_java_exists") or result.get("word_vm_java_exists"))
    repo_remains = result.get("repo_java_exists")
    
    if java_gone:
        score += 3
    else:
        feedback_parts.append("Original Java files still present")
        
    if repo_remains:
        score += 3
    else:
        feedback_parts.append("WordRepository.java missing (over-converted?)")

    # 4. Build Success (40 pts)
    if result.get("build_success"):
        score += 40
        feedback_parts.append("Project builds successfully")
    else:
        feedback_parts.append("Build failed")

    # Anti-gaming check
    if not result.get("created_during_task", False) and files_ok > 0:
        score = 0
        feedback_parts = ["Files modified before task start - potential gaming"]

    passed = score >= 60 and result.get("build_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }