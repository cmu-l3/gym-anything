"""
Verifier for compliance_audit_system task.

Occupation: Database Security Administrator / Compliance Officer (SOC 15-1299.08)
Context: Build a compliant PII storage system in a new ComplianceDB database using
         SQL Server symmetric key encryption (AES_256), AFTER INSERT triggers for
         audit logging, and a stored procedure for safe encrypted data insertion.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_compliance_audit_system(traj, env_info, task_info):
    """
    Score the compliance_audit_system task.

    Expected objects in ComplianceDB:
    - audit schema
    - DATABASE MASTER KEY
    - AuditDataCert certificate
    - SSNEncryptionKey symmetric key (AES_256)
    - audit.SensitiveEmployeeData table (7 columns)
    - audit.AuditLog table (7 columns)
    - audit.usp_InsertSensitiveRecord stored procedure
    - AFTER INSERT trigger on audit.SensitiveEmployeeData
    - 3 encrypted records in audit.SensitiveEmployeeData
    - 3 audit log entries in audit.AuditLog
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ───────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/compliance_result.json", tmp.name)
    except Exception as e:
        os.unlink(tmp.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No result file found. export_result.sh may not have run. Error: {e}",
            "subscores": {},
        }

    try:
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        os.unlink(tmp.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result JSON: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    # ── GATE: Wrong-target detection ──────────────────────────────────────────
    db_exists = result.get("db_exists", False)
    sensitive_table_exists = result.get("sensitive_table_exists", False)
    audit_log_exists = result.get("audit_log_exists", False)
    proc_exists = result.get("proc_exists", False)

    if not db_exists and not sensitive_table_exists and not proc_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: The ComplianceDB database does not exist and none of the required "
                "objects were found. The agent may have created objects in the wrong database "
                "or created no objects at all. All objects must be created in 'ComplianceDB'."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: ComplianceDB database exists (10 pts) ────────────────────
    if db_exists:
        score += 10
        subscores["db_exists"] = 10
        feedback_parts.append("PASS: ComplianceDB database exists.")
    else:
        subscores["db_exists"] = 0
        feedback_parts.append(
            "FAIL: ComplianceDB database not found. Use: CREATE DATABASE ComplianceDB."
        )

    # ── Criterion 2: audit schema exists (5 pts) ──────────────────────────────
    audit_schema_exists = result.get("audit_schema_exists", False)

    if audit_schema_exists:
        score += 5
        subscores["audit_schema"] = 5
        feedback_parts.append("PASS: audit schema exists in ComplianceDB.")
    elif db_exists:
        subscores["audit_schema"] = 0
        feedback_parts.append(
            "FAIL: audit schema not found in ComplianceDB. "
            "Use: USE ComplianceDB; CREATE SCHEMA audit."
        )
    else:
        subscores["audit_schema"] = 0
        feedback_parts.append("FAIL: audit schema check skipped (ComplianceDB does not exist).")

    # ── Criterion 3: Encryption infrastructure (15 pts) ───────────────────────
    master_key_exists = result.get("master_key_exists", False)
    certificate_exists = result.get("certificate_exists", False)
    symmetric_key_exists = result.get("symmetric_key_exists", False)

    enc_pts = 0
    if master_key_exists:
        enc_pts += 5
        feedback_parts.append("PASS: DATABASE MASTER KEY exists in ComplianceDB.")
    else:
        feedback_parts.append(
            "FAIL: DATABASE MASTER KEY not found. "
            "Use: CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Compliance@Secure2024'."
        )

    if certificate_exists:
        enc_pts += 5
        feedback_parts.append("PASS: Certificate AuditDataCert exists.")
    else:
        feedback_parts.append(
            "FAIL: Certificate AuditDataCert not found. "
            "Use: CREATE CERTIFICATE AuditDataCert WITH SUBJECT = 'PII Encryption Certificate'."
        )

    if symmetric_key_exists:
        enc_pts += 5
        feedback_parts.append("PASS: Symmetric key SSNEncryptionKey (AES_256) exists.")
    else:
        feedback_parts.append(
            "FAIL: Symmetric key SSNEncryptionKey not found. "
            "Use: CREATE SYMMETRIC KEY SSNEncryptionKey WITH ALGORITHM = AES_256 "
            "ENCRYPTION BY CERTIFICATE AuditDataCert."
        )

    score += enc_pts
    subscores["encryption_infra"] = enc_pts

    # ── Criterion 4: audit.SensitiveEmployeeData table exists with columns (15 pts) ──
    has_sensitive_columns = result.get("has_sensitive_columns", False)
    sensitive_columns_found = result.get("sensitive_columns_found", "")

    if sensitive_table_exists and has_sensitive_columns:
        score += 15
        subscores["sensitive_table"] = 15
        feedback_parts.append(
            "PASS: audit.SensitiveEmployeeData exists with required columns "
            "(RecordID, SSN_Encrypted, FirstName, LastName, DateOfBirth)."
        )
    elif sensitive_table_exists:
        score += 8
        subscores["sensitive_table"] = 8
        feedback_parts.append(
            f"PARTIAL: audit.SensitiveEmployeeData exists but missing some required columns. "
            f"Columns found: {sensitive_columns_found}"
        )
    elif db_exists:
        subscores["sensitive_table"] = 0
        feedback_parts.append("FAIL: audit.SensitiveEmployeeData table not found in ComplianceDB.")
    else:
        subscores["sensitive_table"] = 0
        feedback_parts.append("FAIL: Sensitive table check skipped (ComplianceDB does not exist).")

    # ── Criterion 5: audit.AuditLog table exists with columns (10 pts) ────────
    has_audit_log_columns = result.get("has_audit_log_columns", False)
    audit_log_columns_found = result.get("audit_log_columns_found", "")

    if audit_log_exists and has_audit_log_columns:
        score += 10
        subscores["audit_log_table"] = 10
        feedback_parts.append(
            "PASS: audit.AuditLog exists with required columns "
            "(LogID, EventType, TableName, AffectedRecordID, EventTimestamp)."
        )
    elif audit_log_exists:
        score += 5
        subscores["audit_log_table"] = 5
        feedback_parts.append(
            f"PARTIAL: audit.AuditLog exists but missing some required columns. "
            f"Columns found: {audit_log_columns_found}"
        )
    elif db_exists:
        subscores["audit_log_table"] = 0
        feedback_parts.append("FAIL: audit.AuditLog table not found in ComplianceDB.")
    else:
        subscores["audit_log_table"] = 0
        feedback_parts.append("FAIL: AuditLog check skipped (ComplianceDB does not exist).")

    # ── Criterion 6: Stored procedure exists (10 pts) ─────────────────────────
    if proc_exists:
        score += 10
        subscores["stored_proc"] = 10
        feedback_parts.append("PASS: Stored procedure audit.usp_InsertSensitiveRecord exists.")
    elif db_exists:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: Stored procedure audit.usp_InsertSensitiveRecord not found.")
    else:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: Procedure check skipped (ComplianceDB does not exist).")

    # ── Criterion 7: Trigger exists (10 pts) ──────────────────────────────────
    trigger_exists = result.get("trigger_exists", False)

    if trigger_exists:
        score += 10
        subscores["trigger"] = 10
        feedback_parts.append(
            "PASS: AFTER INSERT trigger on audit.SensitiveEmployeeData exists."
        )
    elif sensitive_table_exists:
        subscores["trigger"] = 0
        feedback_parts.append(
            "FAIL: No INSERT trigger found on audit.SensitiveEmployeeData. "
            "Create an AFTER INSERT trigger that logs to audit.AuditLog."
        )
    else:
        subscores["trigger"] = 0
        feedback_parts.append("FAIL: Trigger check skipped (SensitiveEmployeeData does not exist).")

    # ── Criterion 8: 3 encrypted records exist (10 pts) ───────────────────────
    sensitive_row_count = result.get("sensitive_row_count", 0)
    encryption_working = result.get("encryption_working", False)

    if sensitive_table_exists and encryption_working and sensitive_row_count >= 3:
        score += 10
        subscores["encrypted_records"] = 10
        feedback_parts.append(
            f"PASS: audit.SensitiveEmployeeData has {sensitive_row_count} rows with "
            f"non-NULL encrypted SSN data (ENCRYPTBYKEY is working correctly)."
        )
    elif sensitive_table_exists and sensitive_row_count >= 3:
        score += 5
        subscores["encrypted_records"] = 5
        feedback_parts.append(
            f"PARTIAL: Table has {sensitive_row_count} rows but SSN_Encrypted is NULL. "
            f"Ensure the procedure opens the key with OPEN SYMMETRIC KEY SSNEncryptionKey "
            f"DECRYPTION BY CERTIFICATE AuditDataCert before calling ENCRYPTBYKEY."
        )
    elif sensitive_table_exists and sensitive_row_count > 0:
        score += 3
        subscores["encrypted_records"] = 3
        feedback_parts.append(
            f"PARTIAL: Only {sensitive_row_count} row(s) found (expected 3). "
            f"Execute the stored procedure 3 times with the test SSN values."
        )
    else:
        subscores["encrypted_records"] = 0
        feedback_parts.append(
            "FAIL: No records in audit.SensitiveEmployeeData. "
            "Execute: EXEC audit.usp_InsertSensitiveRecord '123-45-6789', 'Alice', 'Johnson', '1985-03-15'"
        )

    # ── Criterion 9: AuditLog has 3 rows (trigger fired 3 times) (5 pts) ──────
    audit_log_row_count = result.get("audit_log_row_count", 0)

    if audit_log_exists and audit_log_row_count >= 3:
        score += 5
        subscores["audit_log_data"] = 5
        feedback_parts.append(
            f"PASS: audit.AuditLog has {audit_log_row_count} entries "
            f"(trigger fired correctly for each INSERT)."
        )
    elif audit_log_exists and audit_log_row_count > 0:
        score += 2
        subscores["audit_log_data"] = 2
        feedback_parts.append(
            f"PARTIAL: audit.AuditLog has {audit_log_row_count} entries (expected 3, one per insert). "
            f"Check your trigger definition and that all 3 EXEC calls were made."
        )
    elif audit_log_exists:
        subscores["audit_log_data"] = 0
        feedback_parts.append(
            "FAIL: audit.AuditLog is empty. "
            "Verify the trigger is correctly logging INSERT events to audit.AuditLog."
        )
    else:
        subscores["audit_log_data"] = 0
        feedback_parts.append("FAIL: AuditLog data check skipped (table does not exist).")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= PASS_THRESHOLD
    feedback = " | ".join(feedback_parts)

    if passed:
        feedback = f"PASSED ({score}/100): " + feedback
    else:
        feedback = f"FAILED ({score}/100, need {PASS_THRESHOLD}): " + feedback

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
    }
