# compliance_audit_system

## Domain Context

**Occupation**: Database Security Administrator / Compliance Officer (SOC 15-1299.08)
**Industry**: Healthcare Services / Financial Services
**Application**: Azure Data Studio + Microsoft SQL Server 2022

Following a regulatory audit, a healthcare services company has been required to implement compliant storage of personally identifiable information (PII). The compliance requirement mandates: (1) sensitive fields must be encrypted at rest using industry-standard encryption, (2) every data modification must be automatically logged to an immutable audit trail, and (3) the system must be isolated in its own database with a dedicated schema.

This is a from-scratch implementation in a **new database** (`ComplianceDB`) — it does not use any AdventureWorks data.

---

## Task Goal

Build a compliant PII storage and audit system in a new SQL Server database named `ComplianceDB`. The deliverables are:

1. A new database `ComplianceDB` with an `audit` schema
2. SQL Server certificate-based symmetric key encryption infrastructure: a DATABASE MASTER KEY, a CERTIFICATE (`AuditDataCert`), and a SYMMETRIC KEY (`SSNEncryptionKey`) using AES_256 algorithm
3. A table (`audit.SensitiveEmployeeData`) that stores encrypted SSNs as VARBINARY alongside plaintext demographic fields
4. A table (`audit.AuditLog`) that records every DML event on the sensitive data table
5. A stored procedure (`audit.usp_InsertSensitiveRecord`) that opens the symmetric key, encrypts the SSN using `ENCRYPTBYKEY`, inserts the record, and closes the key
6. An AFTER INSERT trigger (`audit.trg_SensitiveEmployeeData_Insert`) on `audit.SensitiveEmployeeData` that automatically logs each insert to `audit.AuditLog`
7. Three test records inserted via the stored procedure using the provided test SSNs and demographics

---

## Expected End State

- `ComplianceDB` database exists
- `audit` schema exists within `ComplianceDB`
- DATABASE MASTER KEY exists in `ComplianceDB`
- `AuditDataCert` certificate exists in `ComplianceDB`
- `SSNEncryptionKey` symmetric key (AES_256) exists, encrypted by `AuditDataCert`
- `audit.SensitiveEmployeeData` table exists with 7 columns including `SSN_Encrypted` (VARBINARY)
- `audit.AuditLog` table exists with 7 columns including `EventType`, `TableName`, `AffectedRecordID`
- `audit.usp_InsertSensitiveRecord` stored procedure exists
- AFTER INSERT trigger exists on `audit.SensitiveEmployeeData`
- `audit.SensitiveEmployeeData` has exactly 3 rows
- `SSN_Encrypted` column contains non-NULL VARBINARY data (encryption is working)
- `audit.AuditLog` has 3 rows (trigger fired once per insert)

---

## Test Records to Insert

After building the system, execute the stored procedure for these three individuals:

| SSN | FirstName | LastName | DateOfBirth |
|-----|-----------|----------|-------------|
| 123-45-6789 | Alice | Johnson | 1985-03-15 |
| 987-65-4321 | Robert | Martinez | 1979-11-28 |
| 456-78-9012 | Carol | Thompson | 1992-07-04 |

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| ComplianceDB database exists | 10 |
| audit schema exists | 5 |
| Encryption infrastructure (Master Key + Certificate + Symmetric Key) | 15 (5 each) |
| audit.SensitiveEmployeeData table with required columns | 15 |
| audit.AuditLog table with required columns | 10 |
| audit.usp_InsertSensitiveRecord stored procedure exists | 10 |
| AFTER INSERT trigger exists on SensitiveEmployeeData | 10 |
| 3 encrypted records in SensitiveEmployeeData (SSN_Encrypted is non-NULL) | 10 |
| 3 entries in AuditLog (trigger fired) | 5 |
| **Pass threshold** | **70/100** |

---

## Verification Strategy

`export_result.sh` queries (all in `ComplianceDB` context):
- `sys.databases` — ComplianceDB existence
- `sys.schemas` — audit schema
- `sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##'` — master key
- `sys.certificates WHERE name = 'AuditDataCert'` — certificate
- `sys.symmetric_keys WHERE name = 'SSNEncryptionKey'` — symmetric key
- `sys.objects` (type='U') — both tables
- `INFORMATION_SCHEMA.COLUMNS` — column counts and names
- `COUNT(*) WHERE SSN_Encrypted IS NOT NULL AND LEN(SSN_Encrypted) > 0` — encryption working
- `sys.procedures JOIN sys.schemas` — stored procedure
- `sys.triggers` — trigger on SensitiveEmployeeData
- `COUNT(*)` from both tables — data populated

All results written to `/tmp/compliance_result.json`.

---

## Required Table: audit.SensitiveEmployeeData

| Column | Type | Notes |
|--------|------|-------|
| RecordID | INT IDENTITY PK | Auto-generated |
| SSN_Encrypted | VARBINARY(256) NOT NULL | AES-256 encrypted via ENCRYPTBYKEY |
| FirstName | NVARCHAR(100) NOT NULL | Plaintext |
| LastName | NVARCHAR(100) NOT NULL | Plaintext |
| DateOfBirth | DATE NOT NULL | Plaintext |
| RecordCreatedAt | DATETIME2 | DEFAULT SYSUTCDATETIME() |
| CreatedByUser | NVARCHAR(128) | DEFAULT SYSTEM_USER |

## Required Table: audit.AuditLog

| Column | Type | Notes |
|--------|------|-------|
| LogID | INT IDENTITY PK | Auto-generated |
| EventType | NVARCHAR(20) NOT NULL | e.g., 'INSERT' |
| TableName | NVARCHAR(128) NOT NULL | e.g., 'audit.SensitiveEmployeeData' |
| AffectedRecordID | INT | From inserted.RecordID in trigger |
| PerformedBy | NVARCHAR(128) | DEFAULT SYSTEM_USER |
| EventTimestamp | DATETIME2 | DEFAULT SYSUTCDATETIME() |
| AdditionalInfo | NVARCHAR(500) | e.g., 'New PII record added' |

---

## Key Implementation Details

### Encryption Object Creation Order
Objects must be created in dependency order:
1. `CREATE MASTER KEY ENCRYPTION BY PASSWORD = '...'`
2. `CREATE CERTIFICATE AuditDataCert ...`
3. `CREATE SYMMETRIC KEY SSNEncryptionKey WITH ALGORITHM = AES_256 ENCRYPTION BY CERTIFICATE AuditDataCert`

### Stored Procedure Pattern
The procedure must open/close the key around each insert:
```sql
OPEN SYMMETRIC KEY SSNEncryptionKey DECRYPTION BY CERTIFICATE AuditDataCert;
INSERT INTO audit.SensitiveEmployeeData (SSN_Encrypted, FirstName, LastName, DateOfBirth)
VALUES (ENCRYPTBYKEY(KEY_GUID('SSNEncryptionKey'), @SSN), @FirstName, @LastName, @DateOfBirth);
CLOSE SYMMETRIC KEY SSNEncryptionKey;
```

### Trigger Pattern
```sql
CREATE TRIGGER audit.trg_SensitiveEmployeeData_Insert
ON audit.SensitiveEmployeeData
AFTER INSERT
AS
    INSERT INTO audit.AuditLog (EventType, TableName, AffectedRecordID, AdditionalInfo)
    SELECT 'INSERT', 'audit.SensitiveEmployeeData', RecordID, 'New PII record added'
    FROM inserted;
```

---

## Edge Cases

- All objects must be in `ComplianceDB`, not `master` or `AdventureWorks2022`
- The trigger must use the `inserted` pseudo-table to capture the new RecordID
- `ENCRYPTBYKEY` returns NULL if the key is not open; the procedure must open the key first
- All three `EXEC` calls must succeed; if the key or cert is misconfigured, all three will have NULL in SSN_Encrypted

---

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, hooks |
| `setup_task.sh` | Drops ComplianceDB entirely (clean slate), opens ADS |
| `export_result.sh` | Queries all verification criteria in ComplianceDB context, writes `/tmp/compliance_result.json` |
| `verifier.py` | Reads JSON, applies multi-criterion scoring, returns pass/fail |
