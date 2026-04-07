#!/usr/bin/env python3
"""
Verifier for fm_document_linking task.

Scoring rubric (100 points total, pass threshold = 65):
  - file_is_new           : 15 pts  (output IFC created/modified during this task)
  - documents_created     : 25 pts  (>= 4 document entities; partial at 1+)
  - relationships_created : 25 pts  (>= 3 IfcRelAssociatesDocument; partial at 1+)
  - elements_associated   : 35 pts  (>= 10 elements associated; partial at 1+)
"""

import json
import os
import tempfile


def verify_fm_document_linking(traj, env_info, task_info):
    score = 0
    feedback_lines = []

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info."}

    # ── Copy result JSON from VM ──────────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        tmp_path = f.name

    try:
        copy_from_env("/tmp/fm_document_result.json", tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run."}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # ── Critical gate: output file must exist ─────────────────────────────
    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "FAIL: Output IFC file /home/ga/BIMProjects/fzk_fm_handover.ifc "
                "was not created. Score: 0/100."
            ),
        }

    # ── Check 1: File is newly created during this task session ───────────
    file_mtime = result.get("file_mtime", 0.0)
    task_start = result.get("task_start", 0.0)
    if task_start > 0 and file_mtime > task_start:
        score += 15
        feedback_lines.append("PASS: Output IFC file was created/saved during this task session. (+15)")
    else:
        feedback_lines.append(
            "FAIL: Output file was not modified during the task "
            f"(file_mtime={file_mtime:.1f}, task_start={task_start:.1f}). (+0)"
        )

    # ── Check 2: Document Entities Created ────────────────────────────────
    n_docs = result.get("total_documents", 0)
    doc_names = result.get("document_names", [])
    
    if n_docs >= 4:
        score += 25
        feedback_lines.append(
            f"PASS: {n_docs} IfcDocument(Information/Reference) entities found. "
            f"Names: {doc_names[:4]}. (+25)"
        )
    elif n_docs == 3:
        score += 18
        feedback_lines.append(f"PARTIAL: {n_docs}/4 document entities found. (+18)")
    elif n_docs == 2:
        score += 12
        feedback_lines.append(f"PARTIAL: {n_docs}/4 document entities found. (+12)")
    elif n_docs == 1:
        score += 5
        feedback_lines.append(f"PARTIAL: {n_docs}/4 document entities found. (+5)")
    else:
        feedback_lines.append("FAIL: No document entities found in output IFC. (+0)")

    # ── Check 3: Relationships (IfcRelAssociatesDocument) ─────────────────
    n_rels = result.get("num_relationships", 0)
    if n_rels >= 3:
        score += 25
        feedback_lines.append(f"PASS: {n_rels} IfcRelAssociatesDocument relationships found. (+25)")
    elif n_rels == 2:
        score += 15
        feedback_lines.append(f"PARTIAL: {n_rels} document relationships found. (+15)")
    elif n_rels == 1:
        score += 8
        feedback_lines.append(f"PARTIAL: {n_rels} document relationships found. (+8)")
    else:
        feedback_lines.append("FAIL: No IfcRelAssociatesDocument relationships found. (+0)")

    # ── Check 4: Elements Associated ──────────────────────────────────────
    n_elems = result.get("num_associated_elements", 0)
    if n_elems >= 20:
        score += 35
        feedback_lines.append(f"PASS: {n_elems} building elements associated with documents. (+35)")
    elif n_elems >= 10:
        score += 25
        feedback_lines.append(f"PASS: {n_elems} building elements associated with documents. (+25)")
    elif n_elems >= 5:
        score += 15
        feedback_lines.append(f"PARTIAL: {n_elems} building elements associated with documents. (+15)")
    elif n_elems >= 1:
        score += 5
        feedback_lines.append(f"PARTIAL: {n_elems} building elements associated with documents. (+5)")
    else:
        feedback_lines.append("FAIL: No building elements were associated with documents. (+0)")

    passed = score >= 65
    feedback_lines.append(
        f"\nTotal score: {score}/100. {'PASSED' if passed else 'FAILED'} (threshold: 65)."
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines),
    }