#!/bin/bash
echo "=== Exporting task results ==="

# Define Source and Target
SOURCE="DrTuxTest"
TARGET="DrTuxResearch"

# 1. Check if Target DB exists
DB_EXISTS=$(mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TARGET'")

if [ "$DB_EXISTS" -eq 0 ]; then
    echo "ERROR: Database $TARGET does not exist."
    cat > /tmp/task_result.json <<EOF
{
    "db_exists": false,
    "tables_exist": false,
    "row_count_match": false,
    "masking_correct": false,
    "data_preserved": false,
    "source_integrity": false
}
EOF
    exit 0
fi

# 2. Check Tables Existence
TABLES_COUNT=$(mysql -u root $TARGET -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$TARGET' AND TABLE_NAME IN ('IndexNomPrenom', 'fchpat')")
TABLES_EXIST="false"
if [ "$TABLES_COUNT" -ge 2 ]; then
    TABLES_EXIST="true"
fi

# 3. Check Row Counts (Should match Source)
SOURCE_COUNT_IDX=$(mysql -u root $SOURCE -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'")
TARGET_COUNT_IDX=$(mysql -u root $TARGET -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo -1)
SOURCE_COUNT_PAT=$(mysql -u root $SOURCE -N -e "SELECT COUNT(*) FROM fchpat")
TARGET_COUNT_PAT=$(mysql -u root $TARGET -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null || echo -1)

ROW_MATCH="false"
if [ "$SOURCE_COUNT_IDX" -eq "$TARGET_COUNT_IDX" ] && [ "$SOURCE_COUNT_PAT" -eq "$TARGET_COUNT_PAT" ] && [ "$SOURCE_COUNT_IDX" -gt 0 ]; then
    ROW_MATCH="true"
fi

# 4. Check Masking (Target DB)
# Count rows that fail masking criteria
# IndexNomPrenom: Nom should be 'ANONYMOUS', Prenom should be 'Subject'
FAIL_MASK_IDX=$(mysql -u root $TARGET -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos != 'ANONYMOUS' OR FchGnrl_Prenom != 'Subject'" 2>/dev/null || echo 999)

# fchpat: NomFille='ANONYMOUS', Adresse/Tel/SSN should be empty/null
# Note: Checking length < 2 or NULL for cleared fields
FAIL_MASK_PAT=$(mysql -u root $TARGET -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_NomFille != 'ANONYMOUS' OR LENGTH(COALESCE(FchPat_Adresse,'')) > 1 OR LENGTH(COALESCE(FchPat_Tel1,'')) > 1 OR LENGTH(COALESCE(FchPat_NumSS,'')) > 1" 2>/dev/null || echo 999)

MASKING_CORRECT="false"
if [ "$FAIL_MASK_IDX" -eq 0 ] && [ "$FAIL_MASK_PAT" -eq 0 ]; then
    MASKING_CORRECT="true"
fi

# 5. Check Preservation (Join Source & Target)
# Compare DOB, Sexe, Zip, Ville for matching GUIDs
# We want 0 rows where these fields differ
FAIL_PRESERVE=$(mysql -u root -N -e "
    SELECT COUNT(*) 
    FROM $SOURCE.fchpat s 
    JOIN $TARGET.fchpat t ON s.FchPat_GUID_Doss = t.FchPat_GUID_Doss 
    WHERE s.FchPat_Nee != t.FchPat_Nee 
       OR s.FchPat_Sexe != t.FchPat_Sexe 
       OR s.FchPat_CP != t.FchPat_CP 
       OR s.FchPat_Ville != t.FchPat_Ville
" 2>/dev/null || echo 999)

DATA_PRESERVED="false"
if [ "$FAIL_PRESERVE" -eq 0 ]; then
    DATA_PRESERVED="true"
fi

# 6. Check Source Integrity (Compare with initial checksum)
INITIAL_CHECKSUM=$(cat /tmp/source_db_checksum.txt 2>/dev/null || echo "initial")
CURRENT_CHECKSUM=$(mysql -u root $SOURCE -N -e "SELECT MD5(GROUP_CONCAT(FchGnrl_NomDos ORDER BY FchGnrl_IDDos)) FROM IndexNomPrenom;" 2>/dev/null || echo "current")

SOURCE_INTEGRITY="false"
if [ "$INITIAL_CHECKSUM" == "$CURRENT_CHECKSUM" ]; then
    SOURCE_INTEGRITY="true"
fi

# Debug output
echo "DB Exists: true"
echo "Tables Exist: $TABLES_EXIST ($TABLES_COUNT)"
echo "Rows Match: $ROW_MATCH (Src: $SOURCE_COUNT_IDX, Tgt: $TARGET_COUNT_IDX)"
echo "Masking Failures: Idx=$FAIL_MASK_IDX, Pat=$FAIL_MASK_PAT"
echo "Preservation Failures: $FAIL_PRESERVE"
echo "Source Integrity: $SOURCE_INTEGRITY"

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "db_exists": true,
    "tables_exist": $TABLES_EXIST,
    "row_count_match": $ROW_MATCH,
    "masking_correct": $MASKING_CORRECT,
    "data_preserved": $DATA_PRESERVED,
    "source_integrity": $SOURCE_INTEGRITY,
    "metrics": {
        "source_rows": $SOURCE_COUNT_IDX,
        "target_rows": $TARGET_COUNT_IDX,
        "mask_failures_index": $FAIL_MASK_IDX,
        "mask_failures_pat": $FAIL_MASK_PAT,
        "preservation_failures": $FAIL_PRESERVE
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="