#!/bin/bash
set -e
echo "=== Setting up patient_data_audit task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Remove any previous audit report
rm -f /home/ga/audit_report.csv

# ============================================================
# Ensure MySQL is running
# ============================================================
echo "Ensuring MySQL is running..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3
for i in $(seq 1 20); do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready."
        break
    fi
    sleep 2
done

# ============================================================
# Clean up any previous test audit patients
# ============================================================
echo "Cleaning up previous audit test patients..."
for NAME in AUDIT_COMPLET AUDIT_NODOB AUDIT_NOSS AUDIT_NOADDR AUDIT_MULTI; do
    GUID=$(mysql -u root DrTuxTest -N -e \
        "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='$NAME' LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$GUID" ]; then
        mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$GUID'" 2>/dev/null || true
        mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID'" 2>/dev/null || true
    fi
done

# ============================================================
# Insert 5 test patients with known data completeness
# ============================================================
echo "Inserting audit test patients..."

# Patient 1: COMPLETE — all fields filled (should NOT appear in report)
GUID1="AUDIT-TEST-$(date +%s)-001"
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID1', 'AUDIT_COMPLET', 'Marie', 'Dossier')" 2>/dev/null
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_NumSS, FchPat_Adresse, FchPat_Tel1, FchPat_Sexe, FchPat_Titre) VALUES ('$GUID1', 'AUDIT_COMPLET', '1985-06-15', '2850675012345', '10 Rue de la Paix, Marseille', '0491234567', 'F', 'Mme')" 2>/dev/null

# Patient 2: Missing DOB
GUID2="AUDIT-TEST-$(date +%s)-002"
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID2', 'AUDIT_NODOB', 'Pierre', 'Dossier')" 2>/dev/null
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_NumSS, FchPat_Adresse, FchPat_Tel1, FchPat_Sexe, FchPat_Titre) VALUES ('$GUID2', 'AUDIT_NODOB', '', '1780213054321', '25 Avenue Foch, Lyon', '0472345678', 'H', 'M.')" 2>/dev/null

# Patient 3: Missing SSN
GUID3="AUDIT-TEST-$(date +%s)-003"
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID3', 'AUDIT_NOSS', 'Sophie', 'Dossier')" 2>/dev/null
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_NumSS, FchPat_Adresse, FchPat_Tel1, FchPat_Sexe, FchPat_Titre) VALUES ('$GUID3', 'AUDIT_NOSS', '1990-03-22', '', '8 Rue Victor Hugo, Paris', '0156789012', 'F', 'Mme')" 2>/dev/null

# Patient 4: Missing Address
GUID4="AUDIT-TEST-$(date +%s)-004"
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID4', 'AUDIT_NOADDR', 'Jean', 'Dossier')" 2>/dev/null
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_NumSS, FchPat_Adresse, FchPat_Tel1, FchPat_Sexe, FchPat_Titre) VALUES ('$GUID4', 'AUDIT_NOADDR', '1975-11-08', '1751108098765', '', '0561234567', 'H', 'M.')" 2>/dev/null

# Patient 5: Multiple missing (DOB, Address, Phone)
GUID5="AUDIT-TEST-$(date +%s)-005"
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID5', 'AUDIT_MULTI', 'Claire', 'Dossier')" 2>/dev/null
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_NumSS, FchPat_Adresse, FchPat_Tel1, FchPat_Sexe, FchPat_Titre) VALUES ('$GUID5', 'AUDIT_MULTI', '', '2920499012345', '', '', 'F', 'Mme')" 2>/dev/null

echo "Test patients inserted."

# ============================================================
# Generate ground truth: all incomplete patients in the DB
# ============================================================
echo "Generating ground truth..."
mkdir -p /tmp/ground_truth
chmod 700 /tmp/ground_truth

# Ground truth CSV with same format expected from agent
# Note: Using TR to replace tabs with commas
mysql -u root DrTuxTest -N -e "
SELECT
    inp.FchGnrl_NomDos,
    inp.FchGnrl_Prenom,
    CASE WHEN (fp.FchPat_Nee IS NULL OR fp.FchPat_Nee = '' OR fp.FchPat_Nee = '0000-00-00') THEN 1 ELSE 0 END,
    CASE WHEN (fp.FchPat_NumSS IS NULL OR fp.FchPat_NumSS = '') THEN 1 ELSE 0 END,
    CASE WHEN (fp.FchPat_Adresse IS NULL OR fp.FchPat_Adresse = '') THEN 1 ELSE 0 END,
    CASE WHEN (fp.FchPat_Tel1 IS NULL OR fp.FchPat_Tel1 = '') THEN 1 ELSE 0 END
FROM fchpat fp
JOIN IndexNomPrenom inp ON fp.FchPat_GUID_Doss = inp.FchGnrl_IDDos
WHERE inp.FchGnrl_Type = 'Dossier'
HAVING (
    CASE WHEN (fp.FchPat_Nee IS NULL OR fp.FchPat_Nee = '' OR fp.FchPat_Nee = '0000-00-00') THEN 1 ELSE 0 END +
    CASE WHEN (fp.FchPat_NumSS IS NULL OR fp.FchPat_NumSS = '') THEN 1 ELSE 0 END +
    CASE WHEN (fp.FchPat_Adresse IS NULL OR fp.FchPat_Adresse = '') THEN 1 ELSE 0 END +
    CASE WHEN (fp.FchPat_Tel1 IS NULL OR fp.FchPat_Tel1 = '') THEN 1 ELSE 0 END
) > 0
ORDER BY inp.FchGnrl_NomDos, inp.FchGnrl_Prenom
" 2>/dev/null | tr '\t' ',' > /tmp/ground_truth/incomplete_patients.csv

# Add header
sed -i '1i last_name,first_name,dob_missing,ssn_missing,address_missing,phone_missing' /tmp/ground_truth/incomplete_patients.csv

GROUND_TRUTH_COUNT=$(tail -n +2 /tmp/ground_truth/incomplete_patients.csv | wc -l)
echo "Ground truth: $GROUND_TRUTH_COUNT incomplete patients found"

# Ensure MedinTux Manager is running (for initial state visual)
launch_medintux_manager || true
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="