#!/bin/bash
# task_utils.sh — Shared utilities for MedinTux tasks
# MedinTux real schema: IndexNomPrenom + fchpat (NOT Personnes)

# ============================================================
# Screenshot function
# ============================================================
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || \
    DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

# ============================================================
# Database query function
# ============================================================
medintux_query() {
    local query="$1"
    mysql -u root DrTuxTest -N -e "$query" 2>/dev/null
}

# ============================================================
# Extract Qt4 DLLs from installer to Manager/bin if missing.
# CRITICAL: The NSIS installer contains all Qt4 DLLs but the
# wine installer does not always copy them to Manager/bin/.
# Without QtGui4.dll etc. in Manager/bin/, wine crashes.
# ============================================================
ensure_qt_dlls() {
    local MANAGER_BIN
    MANAGER_BIN=$(find /home/ga/.wine/drive_c -name "Manager.exe" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
    if [ -z "$MANAGER_BIN" ]; then
        echo "WARNING: Manager.exe not found, cannot ensure Qt DLLs"
        return 1
    fi
    # Check if QtGui4.dll already present (it's the critical one)
    if [ -f "$MANAGER_BIN/QtGui4.dll" ]; then
        echo "Qt DLLs already in Manager/bin, skipping extraction"
        return 0
    fi
    echo "Extracting Qt DLLs from installer via 7z (30-60s)..."
    local INSTALLER="/opt/medintux/medintux-2.16.012.exe"
    local EXTRACT_DIR="/tmp/qt4_task_dlls"
    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"
    if [ -f "$INSTALLER" ] && command -v 7z >/dev/null 2>&1; then
        7z e "$INSTALLER" -o"$EXTRACT_DIR" "*.dll" -r -y > /dev/null 2>&1 || true
        local COUNT
        COUNT=$(ls "$EXTRACT_DIR"/*.dll 2>/dev/null | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            cp "$EXTRACT_DIR"/*.dll "$MANAGER_BIN"/ 2>/dev/null || true
            chown -R ga:ga "$MANAGER_BIN"/ 2>/dev/null || true
            echo "Copied $COUNT DLLs to $MANAGER_BIN/"
        fi
    fi
    rm -rf "$EXTRACT_DIR"
    if [ -f "$MANAGER_BIN/QtGui4.dll" ]; then
        echo "Qt DLL extraction successful"
    else
        echo "WARNING: QtGui4.dll still missing — Manager may fail to start"
    fi
}

# ============================================================
# Create a correct MedinTux launcher script.
# ============================================================
create_medintux_launcher() {
    local MANAGER_BIN
    MANAGER_BIN=$(find /home/ga/.wine/drive_c -name "Manager.exe" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null)
    if [ -z "$MANAGER_BIN" ]; then
        echo "ERROR: Cannot create launcher — Manager.exe not found"
        return 1
    fi
    cat > /home/ga/launch_medintux.sh << LAUNCH_SCRIPT_EOF
#!/bin/bash
export DISPLAY=:1
export WINEDEBUG=-all
export WINEPREFIX=/home/ga/.wine
cd "${MANAGER_BIN}"
exec wine "${MANAGER_BIN}/Manager.exe"
LAUNCH_SCRIPT_EOF
    chmod +x /home/ga/launch_medintux.sh
    chown ga:ga /home/ga/launch_medintux.sh
    echo "Launcher created: /home/ga/launch_medintux.sh"
}

# ============================================================
# Full MedinTux launch sequence:
# 1. Ensure Qt DLLs are present
# 2. Create correct launcher
# 3. Launch Manager.exe in background
# 4. Wait for process to appear (up to 30s)
# 5. Wait for window to render (up to 90s)
# ============================================================
launch_medintux_manager() {
    ensure_qt_dlls
    create_medintux_launcher

    echo "Launching MedinTux Manager..."
    su - ga -c "setsid /home/ga/launch_medintux.sh > /tmp/medintux_task.log 2>&1 &"

    echo "Waiting for Manager.exe process (up to 30s)..."
    for i in $(seq 1 15); do
        sleep 2
        if pgrep -f "Manager.exe" > /dev/null 2>&1; then
            echo "Manager.exe process started (${i}x2s)"
            break
        fi
    done

    if ! pgrep -f "Manager.exe" > /dev/null 2>&1; then
        echo "ERROR: Manager.exe did not start. Log:"
        tail -20 /tmp/medintux_task.log 2>/dev/null || true
        return 1
    fi

    # Wine needs 75-90 seconds to render the Qt4 window after process start.
    # Poll for the window rather than a fixed sleep.
    echo "Waiting for MedinTux window to appear (up to 90s)..."
    for i in $(seq 1 90); do
        sleep 1
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "manager\|medintux\|drtux" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "MedinTux window appeared (${i}s)"
            break
        fi
    done

    # Maximize
    DISPLAY=:1 wmctrl -r "Manager" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1

    echo "Current windows:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
}

# ============================================================
# Ensure MedinTux is running (legacy compat wrapper)
# ============================================================
ensure_medintux_running() {
    if pgrep -f "Manager.exe" > /dev/null 2>&1; then
        echo "MedinTux Manager is already running."
        return 0
    fi
    launch_medintux_manager
}

# ============================================================
# Wait for MedinTux window to appear
# ============================================================
wait_for_medintux_window() {
    local timeout=30
    for i in $(seq 1 $timeout); do
        WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "medintux\|manager\|DrTux" | head -1 | awk '{print $1}')
        if [ -n "$WID" ]; then
            echo "MedinTux window found: $WID"
            return 0
        fi
        sleep 1
    done
    echo "WARNING: MedinTux window not found after ${timeout}s"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
    return 1
}

# ============================================================
# Count patients in real MedinTux schema
# Real table: IndexNomPrenom (not Personnes)
# ============================================================
count_patients() {
    medintux_query "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'"
}

# ============================================================
# Check if patient exists in IndexNomPrenom
# Usage: patient_exists "LASTNAME" "Firstname"
# ============================================================
patient_exists() {
    local nom="$1"
    local prenom="$2"
    local count
    count=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_NomDos='$nom' AND FchGnrl_Prenom='$prenom'" 2>/dev/null || echo 0)
    echo "$count"
}

# ============================================================
# Get patient GUID from IndexNomPrenom
# Usage: get_patient_guid "LASTNAME" "Firstname"
# ============================================================
get_patient_guid() {
    local nom="$1"
    local prenom="$2"
    mysql -u root DrTuxTest -N -e "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='$nom' AND FchGnrl_Prenom='$prenom' LIMIT 1" 2>/dev/null || echo ""
}

# ============================================================
# Insert patient into both IndexNomPrenom and fchpat
# Usage: insert_patient "GUID" "NOM" "Prenom" "YYYY-MM-DD" "H|F" "Titre" "Adresse" "CP" "Ville" "Tel" "NumSS"
# ============================================================
insert_patient() {
    local guid="$1"
    local nom="$2"
    local prenom="$3"
    local naissance="$4"
    local sexe="$5"
    local titre="$6"
    local adresse="$7"
    local cp="$8"
    local ville="$9"
    local tel="${10}"
    local numss="${11}"

    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$guid', '$nom', '$prenom', 'Dossier')" \
        2>/dev/null || true

    # Insert patient details
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$guid', '$nom', '$naissance', '$sexe', '$titre', '$adresse', $cp, '$ville', '$tel', '$numss')" \
        2>/dev/null || true
}

# ============================================================
# Delete patient from both tables
# Usage: delete_patient "LASTNAME" "Firstname"
# ============================================================
delete_patient() {
    local nom="$1"
    local prenom="$2"
    local guid
    guid=$(get_patient_guid "$nom" "$prenom")
    if [ -n "$guid" ]; then
        mysql -u root DrTuxTest -e \
            "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'; DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'" \
            2>/dev/null || true
    fi
}
