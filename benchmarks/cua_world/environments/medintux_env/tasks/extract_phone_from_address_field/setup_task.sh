#!/bin/bash
echo "=== Setting up extract_phone_from_address_field task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
wait_for_mysql() {
    for i in {1..30}; do
        if mysqladmin ping -h localhost --silent; then
            return 0
        fi
        sleep 1
    done
    return 1
}
wait_for_mysql || echo "WARNING: MySQL start timed out"

# Clean up any previous test artifacts
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss LIKE 'TEST-%';" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos LIKE 'TEST-%';" 2>/dev/null || true

echo "Injecting dirty data records..."

# 1. Pattern A: Address SPACE Phone (Dots)
# Address: 10 Rue de la Paix 01.45.67.89.00
# Expected: Phone=0145678900
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Adresse, FchPat_Tel1) VALUES ('TEST-DIRTY-001', 'TEST_A', '10 Rue de la Paix 01.45.67.89.00', '');" 
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Type) VALUES ('TEST-DIRTY-001', 'TEST_A', 'Dossier');"

# 2. Pattern B: Address (Tel: Phone)
# Address: 5 Ave Foch (Tel: 06 12 34 56 78)
# Expected: Phone=0612345678
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Adresse, FchPat_Tel1) VALUES ('TEST-DIRTY-002', 'TEST_B', '5 Ave Foch (Tel: 06 12 34 56 78)', NULL);"
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Type) VALUES ('TEST-DIRTY-002', 'TEST_B', 'Dossier');"

# 3. Pattern C: Address - Phone (Plain)
# Address: Route 66 - 0987654321
# Expected: Phone=0987654321
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Adresse, FchPat_Tel1) VALUES ('TEST-DIRTY-003', 'TEST_C', 'Route 66 - 0987654321', '');"
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Type) VALUES ('TEST-DIRTY-003', 'TEST_C', 'Dossier');"

# 4. Control: Clean record
# Should NOT be modified
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Adresse, FchPat_Tel1) VALUES ('TEST-CLEAN-001', 'TEST_D', '88 Blvd Saint Germain', '0199887766');"
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Type) VALUES ('TEST-CLEAN-001', 'TEST_D', 'Dossier');"

# Verify injection
COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat WHERE FchPat_GUID_Doss LIKE 'TEST-%'")
echo "Injected $COUNT test records."

# Record initial counts for verifier (anti-gaming)
echo "$COUNT" > /tmp/initial_test_count.txt

# Start MedinTux Manager (optional, but good for realism if agent wants to check UI)
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="