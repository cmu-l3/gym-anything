#!/bin/bash
# VistA Setup Script (post_start hook)
# Starts VistA VEHU server via Docker and configures web interface
#
# VistA Credentials:
# - System Manager: 01vehu / vehu01
# - YDBGui: No authentication required (disabled for tasks)

echo "=== Setting up VistA Environment ==="

# Configuration
VEHU_IMAGE="worldvista/vehu:latest"
VISTA_CONTAINER="vista-vehu"
VISTA_ACCESS_CODE="01vehu"
VISTA_VERIFY_CODE="vehu01"

# Function to wait for VistA to be ready
wait_for_vista() {
    local timeout=${1:-180}
    local elapsed=0

    echo "Waiting for VistA VEHU server to be ready..."

    while [ $elapsed -lt $timeout ]; do
        # Check if the XWB port is accessible
        if nc -z localhost 9430 2>/dev/null; then
            echo "VistA XWB port 9430 is accessible after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s"
    done

    echo "WARNING: VistA readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for YDBGui web interface
wait_for_ydbgui() {
    local timeout=${1:-60}
    local elapsed=0
    local container_ip="$1"

    echo "Waiting for YDBGui web interface..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${container_ip}:8089/" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            echo "YDBGui ready at http://${container_ip}:8089/ after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "WARNING: YDBGui readiness check timed out"
    return 1
}

# Install required packages
apt-get update && apt-get install -y netcat-openbsd curl firefox wmctrl xdotool 2>/dev/null || true

# Stop and remove any existing VistA container
echo "Cleaning up any existing VistA container..."
docker stop "$VISTA_CONTAINER" 2>/dev/null || true
docker rm "$VISTA_CONTAINER" 2>/dev/null || true

# Pull VistA VEHU image
echo "Pulling VistA VEHU Docker image..."
docker pull "$VEHU_IMAGE"

# Start VistA VEHU container
# Ports:
#   9430 - XWB protocol (CPRS connection)
#   8001 - VistALink
#   8080 - Web UI (unused in VEHU)
#   8089 - YDBGui web interface (via container IP)
#   2222 - SSH (mapped to 2223 to avoid conflict)
#   1338 - SQL (Octo)
echo "Starting VistA VEHU container..."
docker run -d \
    --name "$VISTA_CONTAINER" \
    --restart unless-stopped \
    -p 9430:9430 \
    -p 8001:8001 \
    -p 8080:8080 \
    -p 2223:22 \
    -p 1338:1338 \
    "$VEHU_IMAGE"

echo "Container started..."
docker ps | grep "$VISTA_CONTAINER"

# Wait for VistA to be ready
wait_for_vista 180

# Get container IP for internal web access
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$VISTA_CONTAINER")
echo "Container IP: $CONTAINER_IP"
echo "$CONTAINER_IP" > /tmp/vista_container_ip

# Wait for initial VistA processes to start
echo "Waiting for VistA processes to initialize..."
sleep 10

# Restart YDBGui WITHOUT authentication for easier task completion
echo "Restarting YDBGui without authentication..."
docker exec "$VISTA_CONTAINER" pkill -f ydbgui 2>/dev/null || true
sleep 2

# Start YDBGui without auth file (makes it accessible without login)
docker exec -u vehu "$VISTA_CONTAINER" bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-noauth.log 2>&1 &'
sleep 5

# Verify YDBGui is running
echo "Verifying YDBGui..."
docker exec "$VISTA_CONTAINER" ps aux | grep ydbgui

# Wait for YDBGui to be ready
wait_for_ydbgui "$CONTAINER_IP" 60

# Show container logs
echo ""
echo "Recent VistA container logs:"
docker logs --tail 20 "$VISTA_CONTAINER" 2>&1 || true

# Create utility scripts for VistA database queries
echo "Creating VistA utility scripts..."

cat > /usr/local/bin/vista-query << 'VISTAQUERY'
#!/bin/bash
# Execute M/MUMPS query against VistA database
# Usage: vista-query 'M/MUMPS expression'
docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD '$1'" 2>/dev/null
VISTAQUERY
chmod +x /usr/local/bin/vista-query

cat > /usr/local/bin/vista-patient-count << 'PATCOUNT'
#!/bin/bash
# Get patient count from VistA
docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S C=0,X=0 F  S X=\$O(^DPT(X)) Q:X=\"\"  S C=C+1 S:C>9999 X=\"\" W:X=\"\" C"' 2>/dev/null
PATCOUNT
chmod +x /usr/local/bin/vista-patient-count

cat > /usr/local/bin/vista-list-patients << 'LISTPAT'
#!/bin/bash
# List first N patients from VistA (default 10)
COUNT=${1:-10}
docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'S U=\"^\",X=0,N=0 F  S X=\$O(^DPT(X)) Q:X=\"\"!(N>=$COUNT)  S N=N+1,NM=\$P(\$G(^DPT(X,0)),U,1) W N,\" DFN:\",X,\" \",NM,!'" 2>/dev/null
LISTPAT
chmod +x /usr/local/bin/vista-list-patients

# Query and display available patients
echo ""
echo "Querying VistA database for sample patients..."
PATIENT_LIST=$(/usr/local/bin/vista-list-patients 10)
if [ -n "$PATIENT_LIST" ]; then
    echo "Sample patients in VEHU database:"
    echo "$PATIENT_LIST"
    echo "$PATIENT_LIST" > /tmp/vista_sample_patients.txt
else
    echo "Could not query patients (VistA may still be initializing)"
fi

# Create desktop launcher for YDBGui
echo "Creating desktop launchers..."
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/VistA-YDBGui.desktop << DESKTOPEOF
[Desktop Entry]
Name=VistA YDBGui
Comment=VistA Database Web Interface
Exec=firefox http://${CONTAINER_IP}:8089/
Icon=web-browser
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Medical;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/VistA-YDBGui.desktop
chmod +x /home/ga/Desktop/VistA-YDBGui.desktop

# Mark desktop file as trusted
gio set /home/ga/Desktop/VistA-YDBGui.desktop metadata::trusted true 2>/dev/null || true

# NOTE: Firefox is launched by the task setup script (pre_task hook)
# This avoids timeout issues during post_start

echo ""
echo "=== VistA Setup Complete ==="
echo ""
echo "VistA VEHU Server:"
echo "  Container IP: ${CONTAINER_IP}"
echo "  XWB Port: 9430"
echo "  VistALink: 8001"
echo "  Container SSH: port 2223"
echo ""
echo "Web Interface:"
echo "  YDBGui URL: http://${CONTAINER_IP}:8089/"
echo "  Status: Running in Firefox (no login required)"
echo ""
echo "YDBGui Features:"
echo "  - Global Viewer: Browse VistA globals (^DPT for patients, ^GMR for vitals)"
echo "  - Routine Viewer: View M/MUMPS routines"
echo "  - Octo: SQL interface to VistA data"
echo "  - Dashboard: Database statistics and monitoring"
echo ""
echo "VistA Credentials (for RPC access):"
echo "  Access Code: ${VISTA_ACCESS_CODE}"
echo "  Verify Code: ${VISTA_VERIFY_CODE}"
echo ""
echo "Utility Commands:"
echo "  vista-query 'M/MUMPS expression'"
echo "  vista-list-patients [count]"
echo "  vista-patient-count"
echo ""
