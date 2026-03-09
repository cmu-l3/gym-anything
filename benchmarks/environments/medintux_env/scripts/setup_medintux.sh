#!/bin/bash
set -euo pipefail

echo "=== Setting up MedinTux environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Start MySQL and configure it
# ============================================================
echo "Starting MySQL server..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 5

# Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."
for i in $(seq 1 30); do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready (attempt $i)"
        break
    fi
    sleep 2
done

# Configure MySQL root with empty password (no auth plugin issues)
echo "Configuring MySQL..."
mysql -u root << 'MYSQL_EOF'
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';
FLUSH PRIVILEGES;
MYSQL_EOF
echo "MySQL configured."

# ============================================================
# Initialize Wine prefix for ga user
# ============================================================
echo "Initializing Wine prefix for ga user..."
su - ga -c "WINEDEBUG=-all DISPLAY=:1 wineboot --init" 2>&1 | tail -5 || true
sleep 8

# ============================================================
# Install MedinTux via Wine
# IMPORTANT: The installer shows a GUI dialog (NOT truly silent
# with /S flag). We must use xdotool to click "Next".
# After installation, Manager.exe is at:
#   /home/ga/.wine/drive_c/MedinTux-2.16/Programmes/Manager/bin/Manager.exe
# ============================================================
echo "Installing MedinTux via Wine..."

# Copy installer to ga home (accessible without root path issues)
cp /opt/medintux/medintux-2.16.012.exe /home/ga/medintux-installer.exe
chown ga:ga /home/ga/medintux-installer.exe

# Launch the installer in background as ga user with display
# NOTE: /S alone doesn't suppress the first dialog page
su - ga -c "DISPLAY=:1 WINEDEBUG=-all wine /home/ga/medintux-installer.exe > /tmp/medintux_install.log 2>&1" &
INSTALL_PID=$!

echo "Waiting for installer dialog to appear (20 seconds)..."
sleep 20

# Click the "Next" button using xdotool Enter key.
# NSIS installer's default button (Next/Install/Finish) is activated by Enter.
echo "Sending Enter to proceed past installer dialog..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || \
    DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
sleep 3

# Second Enter in case there are two dialog pages
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || \
    DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
sleep 2

# Wait for installation to FULLY complete.
# CRITICAL: Do NOT break early on Manager.exe appearance alone!
# The NSIS installer extracts Manager.exe first, then continues copying
# Qt DLLs (QtCore4.dll, QtSql4.dll, etc.) and other files.
# Breaking early and killing the installer leaves Qt DLLs missing,
# causing "Library QtCore4.dll not found" errors at runtime.
# We wait for the installer PROCESS to end naturally (not just Manager.exe).
echo "Waiting for installation to FULLY complete (up to 10 minutes)..."
for i in $(seq 1 120); do
    sleep 5
    if ! kill -0 $INSTALL_PID 2>/dev/null; then
        echo "Installer process completed naturally at attempt $i ($((i*5))s)"
        break
    fi
    # Show progress every 30s
    if [ $((i % 6)) -eq 0 ]; then
        echo "Still installing... ($((i*5))s elapsed)"
        # Check Qt DLL presence as progress indicator
        QT_PRESENT=$(find /home/ga/.wine/drive_c -name "QtCore4.dll" 2>/dev/null | head -1)
        if [ -n "$QT_PRESENT" ]; then
            echo "  QtCore4.dll found at: $QT_PRESENT"
        fi
    fi
done

# Wait a bit more after installer exits for wine cleanup
sleep 5

# Verify Manager.exe AND Qt DLLs are both present
MANAGER_CHECK=$(find /home/ga/.wine/drive_c -name "Manager.exe" 2>/dev/null | head -1)
QTCORE_CHECK=$(find /home/ga/.wine/drive_c -name "QtCore4.dll" 2>/dev/null | head -1)
echo "Post-install check:"
echo "  Manager.exe: ${MANAGER_CHECK:-MISSING}"
echo "  QtCore4.dll: ${QTCORE_CHECK:-MISSING}"

if [ -z "$MANAGER_CHECK" ]; then
    echo "ERROR: Manager.exe not found after installation!"
    echo "Install log tail:"
    tail -30 /tmp/medintux_install.log 2>/dev/null || true
    exit 1
fi

if [ -z "$QTCORE_CHECK" ]; then
    echo "WARNING: QtCore4.dll not found — installer may not have fully completed"
    echo "Checking all DLLs in MedinTux directory..."
    find /home/ga/.wine/drive_c -name "*.dll" 2>/dev/null | head -20 || true
    echo "Install log tail:"
    tail -50 /tmp/medintux_install.log 2>/dev/null || true
    # Not fatal — we'll try to run anyway; wine may find DLLs elsewhere
fi

# Kill any lingering install wine processes (should already be done)
pkill -f "medintux-installer" 2>/dev/null || true
pkill -f "wine.*medintux" 2>/dev/null || true
sleep 3

# ============================================================
# Find installed MedinTux paths
# ============================================================
MANAGER=$(find /home/ga/.wine/drive_c -name "Manager.exe" 2>/dev/null | head -1)
if [ -z "$MANAGER" ]; then
    echo "ERROR: Manager.exe not found after installation!"
    echo "Wine drive_c contents:"
    ls /home/ga/.wine/drive_c/ 2>/dev/null || true
    echo "Install log tail:"
    tail -30 /tmp/medintux_install.log 2>/dev/null || true
    exit 1
fi

MANAGER_DIR=$(dirname "$MANAGER")
# Path structure: .../MedinTux-2.16/Programmes/Manager/bin
# Remove /Manager/bin to get Programmes directory
PROGRAMMES_DIR=$(echo "$MANAGER_DIR" | sed 's|/Manager/bin$||')
MEDINTUX_ROOT=$(echo "$MANAGER_DIR" | sed 's|/Programmes/Manager/bin$||')

echo "MedinTux root: $MEDINTUX_ROOT"
echo "Programmes dir: $PROGRAMMES_DIR"
echo "Manager: $MANAGER"

# ============================================================
# Extract Qt4 DLLs from the MedinTux NSIS installer.
#
# CRITICAL DISCOVERY: The NSIS installer contains ALL Qt4 DLLs in
# Programmes/QtW/ (including QtGui4.dll, QtNetwork4.dll, QtSql4.dll,
# QtXml4.dll, QtWebKit4.dll), but the wine-run installer installs
# them in a different order. Some DLLs end up in QtW/ on disk, but
# QtGui4.dll, QtNetwork4.dll, QtSql4.dll, QtXml4.dll may be missing
# because the installer was slow or completed in an unexpected order.
#
# Fix: Use 7z to extract ALL DLLs directly from the installer, then
# copy them to Manager/bin/ where wine looks for them (exe directory).
# ============================================================
INSTALLER_FILE="/opt/medintux/medintux-2.16.012.exe"
QT_EXTRACT_DIR="/tmp/qt4_extract"
echo "Extracting Qt4 DLLs from installer with 7z..."
mkdir -p "$QT_EXTRACT_DIR"

if [ -f "$INSTALLER_FILE" ] && command -v 7z >/dev/null 2>&1; then
    7z e "$INSTALLER_FILE" -o"$QT_EXTRACT_DIR" "*.dll" -r -y > /dev/null 2>&1 || true
    DLL_COUNT=$(ls "$QT_EXTRACT_DIR"/*.dll 2>/dev/null | wc -l)
    echo "  Extracted $DLL_COUNT DLLs from installer"

    if [ "$DLL_COUNT" -gt 0 ]; then
        cp "$QT_EXTRACT_DIR"/*.dll "$MANAGER_DIR"/ 2>/dev/null && \
            echo "  Copied all DLLs to Manager/bin/" || \
            echo "  WARNING: DLL copy had errors"
        chown -R ga:ga "$MANAGER_DIR"/ 2>/dev/null || true
    fi
    rm -rf "$QT_EXTRACT_DIR"
else
    echo "  7z or installer not available, trying QtW/ copy fallback..."
    QTW_DIR="$PROGRAMMES_DIR/QtW"
    if [ -d "$QTW_DIR" ]; then
        cp "$QTW_DIR"/*.dll "$MANAGER_DIR"/ 2>/dev/null || true
        chown -R ga:ga "$MANAGER_DIR"/ 2>/dev/null || true
    fi
fi

# Verify key Qt DLLs are now in Manager/bin
echo "Qt DLL check:"
for dll in QtCore4.dll QtGui4.dll QtNetwork4.dll QtSql4.dll Qt3Support4.dll; do
    if [ -f "$MANAGER_DIR/$dll" ]; then
        echo "  $dll: OK ($(du -h "$MANAGER_DIR/$dll" | cut -f1))"
    else
        echo "  $dll: MISSING"
    fi
done

# ============================================================
# Create MedinTux databases
# ============================================================
echo "Creating MedinTux databases..."
mysql -u root << 'MYSQL_EOF'
CREATE DATABASE IF NOT EXISTS DrTuxTest CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS MedicaTuxTest CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS CIM10Test CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE IF NOT EXISTS CCAMTest CHARACTER SET utf8 COLLATE utf8_general_ci;
MYSQL_EOF
echo "Databases created."

# ============================================================
# Load official SQL dumps bundled with MedinTux installer
# These are in the installed application under set_bases/bin/SqlCreateTable/
# They contain the real MedinTux schema + demo patient data
# ============================================================
SQL_DIR="$PROGRAMMES_DIR/set_bases/bin/SqlCreateTable"
echo "Looking for SQL dumps in: $SQL_DIR"
ls "$SQL_DIR" 2>/dev/null | head -20 || echo "SQL directory not found"

if [ -f "$SQL_DIR/Dump_DrTuxTest.sql" ]; then
    echo "Loading official DrTuxTest schema and demo data..."
    mysql -u root DrTuxTest < "$SQL_DIR/Dump_DrTuxTest.sql" 2>/dev/null || true
    echo "DrTuxTest loaded."
else
    echo "WARNING: Dump_DrTuxTest.sql not found at $SQL_DIR"
    find "$MEDINTUX_ROOT" -name "Dump_DrTuxTest.sql" 2>/dev/null | head -5 || true
fi

if [ -f "$SQL_DIR/Dump_MedicaTuxTest.sql" ]; then
    echo "Loading MedicaTuxTest..."
    mysql -u root MedicaTuxTest < "$SQL_DIR/Dump_MedicaTuxTest.sql" 2>/dev/null || true
    echo "MedicaTuxTest loaded."
fi

if [ -f "$SQL_DIR/Dump_CIM10Test.sql" ]; then
    echo "Loading CIM10Test (ICD-10 codes)..."
    mysql -u root CIM10Test < "$SQL_DIR/Dump_CIM10Test.sql" 2>/dev/null || true
    echo "CIM10Test loaded."
fi

if [ -f "$SQL_DIR/Dump_CCAMTest.sql" ]; then
    echo "Loading CCAMTest (medical procedure codes)..."
    mysql -u root CCAMTest < "$SQL_DIR/Dump_CCAMTest.sql" 2>/dev/null || true
    echo "CCAMTest loaded."
fi

# ============================================================
# Verify schema and fix fchpat AUTO_INCREMENT
# ============================================================
echo "Verifying DrTuxTest schema..."
mysql -u root DrTuxTest -N -e "SHOW TABLES" 2>/dev/null | head -30 || true

FCHPAT_EXISTS=$(mysql -u root DrTuxTest -N -e "SHOW TABLES LIKE 'fchpat'" 2>/dev/null | wc -l || echo 0)
INP_EXISTS=$(mysql -u root DrTuxTest -N -e "SHOW TABLES LIKE 'IndexNomPrenom'" 2>/dev/null | wc -l || echo 0)
echo "fchpat: $FCHPAT_EXISTS, IndexNomPrenom: $INP_EXISTS"

if [ "$FCHPAT_EXISTS" -gt 0 ]; then
    # Add AUTO_INCREMENT to FchPat_RefPk if missing (needed for patient inserts)
    HAS_AI=$(mysql -u root DrTuxTest -N -e \
        "SELECT EXTRA FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='DrTuxTest' AND TABLE_NAME='fchpat' AND COLUMN_NAME='FchPat_RefPk'" \
        2>/dev/null || echo "")
    if ! echo "$HAS_AI" | grep -q "auto_increment"; then
        echo "Adding AUTO_INCREMENT to fchpat.FchPat_RefPk..."
        mysql -u root DrTuxTest -e \
            "ALTER TABLE fchpat MODIFY FchPat_RefPk bigint unsigned NOT NULL AUTO_INCREMENT" \
            2>/dev/null || true
    fi

    PATIENT_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null || echo 0)
    echo "Patients in fchpat after SQL load: $PATIENT_COUNT"
fi

# ============================================================
# Insert task-specific test patients
# Real schema: IndexNomPrenom (search index) + fchpat (details)
# Both rows linked by the same GUID in FchGnrl_IDDos / FchPat_GUID_Doss
# ============================================================
echo "Inserting task-specific test patients..."

if [ "$FCHPAT_EXISTS" -gt 0 ] && [ "$INP_EXISTS" -gt 0 ]; then

    insert_test_patient() {
        local NOM="$1" PRENOM="$2" NEE="$3" SEXE="$4" TITRE="$5"
        local ADRESSE="$6" CP="$7" VILLE="$8" TEL="$9" NUMSS="${10}"
        local GUID
        # Check if already present
        local EXISTING
        EXISTING=$(mysql -u root DrTuxTest -N -e \
            "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='$NOM' AND FchGnrl_Prenom='$PRENOM'" \
            2>/dev/null || echo 0)
        if [ "$EXISTING" -gt 0 ]; then
            echo "Patient $NOM $PRENOM already exists, skipping."
            return
        fi
        # Generate a UUID-style GUID (uppercase, matching MedinTux format)
        GUID=$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')
        echo "Inserting $NOM $PRENOM (GUID: $GUID)..."
        # Insert into search index
        mysql -u root DrTuxTest -e \
            "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
             VALUES ('$GUID', '$NOM', '$PRENOM', 'Dossier')" 2>/dev/null || true
        # Insert patient details (fchpat uses FchPat_* column names)
        mysql -u root DrTuxTest -e \
            "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
             FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
             VALUES ('$GUID', '$NOM', '$NEE', '$SEXE', '$TITRE', '$ADRESSE', $CP, '$VILLE', '$TEL', '$NUMSS')" \
            2>/dev/null || true
    }

    # Patients needed for tasks (10 arguments each):
    # NOM PRENOM DOB SEXE TITRE ADRESSE CP VILLE TEL NUMSS
    insert_test_patient "ROUSSEAU" "Laurent"    "1975-08-14" "M" "M."   "3 Rue de la Liberté"    75001 "Paris"      "01.42.33.44.55" "1750875001001"
    insert_test_patient "SIMON"    "Valérie"    "1970-10-19" "F" "Mme"  "11 Rue de la Paix"      06000 "Nice"       "04.93.22.33.44" "2701006000011"
    insert_test_patient "MARTIN"   "Sophie"     "1985-03-22" "F" "Mme"  "45 Avenue des Fleurs"   69001 "Lyon"       "04.72.11.22.33" "2850369001022"
    insert_test_patient "DUBOIS"   "Marie-Claire" "1962-07-08" "F" "Mme" "7 Impasse du Moulin"   13001 "Marseille"  "04.91.55.66.77" "2620613001045"
    insert_test_patient "BERNARD"  "Pierre"     "1968-11-30" "M" "M."   "22 Chemin des Pins"     33000 "Bordeaux"   "05.56.44.55.66" "1681133000088"
    insert_test_patient "LEROY"    "Isabelle"   "1979-04-15" "F" "Mme"  "8 Rue Voltaire"         67000 "Strasbourg" "03.88.11.22.33" "2790467000033"
    insert_test_patient "MOREAU"   "François"   "1955-12-01" "M" "M."   "14 Boulevard de la Mer" 06300 "Nice"       "04.93.77.88.99" "1551206300022"
    insert_test_patient "PETIT"    "Nathalie"   "1990-06-25" "F" "Mme"  "5 Allée des Roses"      31000 "Toulouse"   "05.61.33.44.55" "2900631000011"
    insert_test_patient "DURAND"   "Christophe" "1972-09-03" "M" "M."   "33 Rue de la Fontaine"  44000 "Nantes"     "02.40.22.33.44" "1720944000066"
    insert_test_patient "LAMBERT"  "Anne"       "1983-01-17" "F" "Mme"  "19 Rue du Château"      59000 "Lille"      "03.20.44.55.66" "2830159000099"
    insert_test_patient "GIRARD"   "Michel"     "1960-05-29" "M" "M."   "6 Place de la Mairie"   37000 "Tours"      "02.47.55.66.77" "1600537000044"
    insert_test_patient "ROUX"     "Céline"     "1977-08-11" "F" "Mme"  "27 Avenue Foch"         06000 "Nice"       "04.93.88.99.00" "2770806000055"
    insert_test_patient "FOURNIER" "Jacques"    "1950-03-08" "M" "M."   "11 Rue Pasteur"         75015 "Paris"      "01.45.33.44.55" "1500375015033"
    insert_test_patient "MOREL"    "Sylvie"     "1966-11-22" "F" "Mme"  "3 Chemin du Bois"       38000 "Grenoble"   "04.76.22.33.44" "2661138000077"
    insert_test_patient "HENRY"    "Emmanuel"   "1981-07-14" "M" "M."   "88 Rue de Lyon"         69007 "Lyon"       "04.72.66.77.88" "1810769007011"
    insert_test_patient "PERRIN"   "Martine"    "1958-02-28" "F" "Mme"  "14 Avenue du Parc"      13008 "Marseille"  "04.91.44.55.66" "2580813008099"
    insert_test_patient "BLANC"    "David"      "1993-10-05" "M" "M."   "56 Rue de la Gare"      67100 "Strasbourg" "03.88.22.33.44" "1931067100044"
    insert_test_patient "GAUTHIER" "Hélène"     "1974-06-18" "F" "Mme"  "9 Impasse des Lilas"    75018 "Paris"      "01.46.77.88.99" "2740675018011"
    insert_test_patient "ROBIN"    "Philippe"   "1963-09-14" "M" "M."   "25 Boulevard Clemenceau" 33000 "Bordeaux"  "05.56.55.66.77" "1630933000022"
    insert_test_patient "NICOLAS"  "Sandrine"   "1987-12-03" "F" "Mme"  "7 Rue de l'Eglise"      44200 "Nantes"     "02.40.33.44.55" "2871244200033"

    FINAL_COUNT=$(mysql -u root DrTuxTest -N -e \
        "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo "?")
    echo "Total patients after insertion: $FINAL_COUNT"
fi

# ============================================================
# Configure MedinTux database connection (BasesTest.conf)
# Format: QMYSQL3 , DatabaseName , User , Password , Host , Port
# ============================================================
echo "Configuring MedinTux database connection..."

BASES_CONF="$PROGRAMMES_DIR/set_bases/bin/BasesTest.conf"
echo "Looking for Bases config at: $BASES_CONF"

if [ -f "$BASES_CONF" ]; then
    echo "Found BasesTest.conf:"
    cat "$BASES_CONF"
else
    echo "BasesTest.conf not found — creating it..."
    CONF_DIR="$PROGRAMMES_DIR/set_bases/bin"
    if [ -d "$CONF_DIR" ]; then
        cat > "$CONF_DIR/BasesTest.conf" << 'CONF_EOF'
Master = QMYSQL3 , DrTuxTest , root ,  , localhost , 3306
Medica = QMYSQL3 , MedicaTuxTest , root ,  , localhost , 3306
CIM10 = QMYSQL3 , CIM10Test , root ,  , localhost , 3306
CCAM = QMYSQL3 , CCAMTest , root ,  , localhost , 3306
CONF_EOF
        chown ga:ga "$CONF_DIR/BasesTest.conf"
        echo "BasesTest.conf created."
    else
        echo "WARNING: Config directory not found: $CONF_DIR"
        find "$MEDINTUX_ROOT" -name "set_bases" -type d 2>/dev/null | head -5 || true
    fi
fi

# ============================================================
# Create a reliable launcher script for MedinTux Manager.
# Wine must be launched from the Manager.exe directory so it
# can find sibling DLLs (QtSql4.dll, QtCore4.dll, etc.).
# We use setsid so the process survives the su subshell exit.
# ============================================================
echo "Creating MedinTux launcher script..."
# Note: Use single-quoted LAUNCH_EOF so variables are NOT expanded here.
# The launcher uses the hardcoded MANAGER_DIR path expanded during this script run.
cat > /home/ga/launch_medintux.sh << LAUNCH_EOF
#!/bin/bash
export DISPLAY=:1
export WINEDEBUG=-all
export WINEPREFIX=/home/ga/.wine
cd "${MANAGER_DIR}"
exec wine "${MANAGER_DIR}/Manager.exe"
LAUNCH_EOF

chmod +x /home/ga/launch_medintux.sh
chown ga:ga /home/ga/launch_medintux.sh

# ============================================================
# Warm-up launch of MedinTux Manager
# ============================================================
echo "Performing warm-up launch of MedinTux..."

# Kill any stale wine processes first
pkill -f "Manager.exe" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 2

# Use setsid so the process survives the su subshell
su - ga -c "setsid /home/ga/launch_medintux.sh > /tmp/medintux_warmup.log 2>&1 &"

echo "Waiting 45 seconds for MedinTux to start..."
sleep 45

if pgrep -f "Manager.exe" > /dev/null 2>&1; then
    echo "MedinTux Manager is running — warm-up successful"
    # Take a screenshot to capture startup state
    DISPLAY=:1 import -window root /tmp/medintux_warmup_screenshot.png 2>/dev/null || \
        DISPLAY=:1 scrot /tmp/medintux_warmup_screenshot.png 2>/dev/null || true
    # Kill after warm-up
    pkill -f "Manager.exe" 2>/dev/null || true
    pkill -x wine 2>/dev/null || true
    sleep 5
else
    echo "MedinTux Manager did not start after 45s — checking log..."
    tail -50 /tmp/medintux_warmup.log 2>/dev/null || true
    # Not fatal: task scripts launch MedinTux themselves
fi

echo "=== MedinTux setup complete ==="
