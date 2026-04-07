#!/usr/bin/env python3
"""
Verifier for regulatory_compliance_remediation task.

Checks the exported /tmp/task_result.json for evidence that the agent:
1. Unpublished Security-Policy-2024 from General-Publications
2. Updated Security-Policy-2024 metadata (dc:source, dc:coverage)
3. Created major versions for both documents
4. Published Security-Policy-2024 to Compliance > Regulatory-Filings
5. Replaced Data-Processing-Agreement file
6. Added gdpr-compliant tag to DPA
7. Removed external-reviewer access from DPA
8. Published DPA to Legal > Legal-Archive
9. Created Remediation-Summary note
10. Created Q1-2025-Compliance-Bundle collection with 3 members

Actual verification is primarily done via external VLM evaluators.
This programmatic verifier provides supplementary scoring.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_regulatory_compliance_remediation(traj, env_info, task_info):
    """
    Verify the regulatory compliance remediation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Finding 1: Security-Policy-2024 remediation (45 pts total) ---

    # 1a. Unpublished from General-Publications (10 pts)
    gp_count = result.get("sp_in_general_publications", 1)
    if gp_count == 0:
        score += 10
        feedback.append("Security-Policy-2024 unpublished from General-Publications.")
    else:
        feedback.append(f"FAIL: Security-Policy-2024 still has {gp_count} proxy(ies) in General-Publications.")

    # 1b. Published to Regulatory-Filings (10 pts)
    rf_count = result.get("sp_in_regulatory_filings", 0)
    if rf_count > 0:
        score += 10
        feedback.append("Security-Policy-2024 published to Regulatory-Filings.")
    else:
        feedback.append("FAIL: No proxy found in Compliance/Regulatory-Filings.")

    # 1c. Metadata: description contains SOX-2025-Q1 (5 pts)
    sp = result.get("security_policy", {})
    sp_desc = sp.get("dc_description") or ""
    if "SOX-2025-Q1" in sp_desc:
        score += 5
        feedback.append("Description updated with SOX-2025-Q1 reference.")
    else:
        feedback.append(f"FAIL: Description does not contain 'SOX-2025-Q1'. Got: '{sp_desc[:80]}'.")

    # 1d. Metadata: dc:coverage = north-america (5 pts)
    if sp.get("dc_coverage") == "north-america":
        score += 5
        feedback.append("dc:coverage set to north-america.")
    else:
        feedback.append(f"FAIL: dc:coverage is '{sp.get('dc_coverage', '')}', expected 'north-america'.")

    # 1e. Major version created (5 pts)
    sp_version = sp.get("version_label", "0.0")
    try:
        major = int(sp_version.split(".")[0])
        if major >= 1:
            score += 5
            feedback.append(f"Security-Policy-2024 version {sp_version} (major version created).")
        else:
            feedback.append(f"FAIL: Security-Policy-2024 version is {sp_version}, expected >= 1.0.")
    except (ValueError, IndexError):
        feedback.append(f"FAIL: Could not parse version label '{sp_version}'.")

    # 1f. Document still exists (10 pts — not accidentally deleted)
    if sp.get("exists"):
        score += 10
        feedback.append("Security-Policy-2024 source document still exists.")
    else:
        feedback.append("CRITICAL: Security-Policy-2024 source document is missing.")

    # --- Finding 2: Data-Processing-Agreement remediation (40 pts total) ---

    dpa = result.get("dpa", {})

    # 2a. File replaced (10 pts)
    original_digest = result.get("original_dpa_digest", "")
    current_digest = dpa.get("file_digest", "")
    if original_digest and current_digest and original_digest != current_digest:
        score += 10
        feedback.append("DPA file replaced (digest changed).")
    elif not original_digest:
        feedback.append("WARN: Could not verify file replacement (no original digest).")
    else:
        feedback.append("FAIL: DPA file digest unchanged — file not replaced.")

    # 2b. Tag gdpr-compliant added (5 pts)
    dpa_tags = result.get("dpa_tags", [])
    if "gdpr-compliant" in dpa_tags:
        score += 5
        feedback.append("Tag 'gdpr-compliant' applied to DPA.")
    else:
        feedback.append(f"FAIL: Tag 'gdpr-compliant' not found. Tags: {dpa_tags}")

    # 2c. Major version created (5 pts)
    dpa_version = dpa.get("version_label", "0.0")
    try:
        major = int(dpa_version.split(".")[0])
        if major >= 1:
            score += 5
            feedback.append(f"DPA version {dpa_version} (major version created).")
        else:
            feedback.append(f"FAIL: DPA version is {dpa_version}, expected >= 1.0.")
    except (ValueError, IndexError):
        feedback.append(f"FAIL: Could not parse DPA version '{dpa_version}'.")

    # 2d. external-reviewer access removed (10 pts)
    ext_access = result.get("dpa_external_reviewer_has_access", True)
    if not ext_access:
        score += 10
        feedback.append("external-reviewer access removed from DPA.")
    else:
        feedback.append("FAIL: external-reviewer still has access to DPA.")

    # 2e. Published to Legal-Archive (10 pts)
    la_count = result.get("dpa_in_legal_archive", 0)
    if la_count > 0:
        score += 10
        feedback.append("DPA published to Legal-Archive.")
    else:
        feedback.append("FAIL: No DPA proxy found in Legal/Legal-Archive.")

    # --- Post-remediation documentation (15 pts total) ---

    # 3a. Remediation-Summary note exists (5 pts)
    rs = result.get("remediation_summary", {})
    if rs.get("exists"):
        score += 5
        feedback.append("Remediation-Summary note exists.")
        # Bonus: check content references both docs
        if rs.get("has_security_policy_ref") and rs.get("has_dpa_ref"):
            feedback.append("Remediation-Summary references both documents.")
    else:
        feedback.append("FAIL: Remediation-Summary note not found in Projects.")

    # 3b. Collection exists with 3 members (10 pts)
    coll = result.get("collection", {})
    if coll.get("exists"):
        member_count = coll.get("member_count", 0)
        if member_count == 3:
            score += 10
            feedback.append(f"Collection Q1-2025-Compliance-Bundle has {member_count} members.")
        elif member_count > 0:
            score += 5  # Partial credit
            feedback.append(f"Collection exists but has {member_count} members (expected 3).")
        else:
            feedback.append("Collection exists but is empty.")
    else:
        feedback.append("FAIL: Collection Q1-2025-Compliance-Bundle not found.")

    # --- Final scoring ---
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
