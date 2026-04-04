#!/bin/bash
# Microsoft SQL Server Setup Script (post_start hook)
# Starts SQL Server via Docker, restores AdventureWorks database, and launches Azure Data Studio
#
# SQL Server SA credentials:
#   Username: sa
#   Password: GymAnything#2024

echo "=== Setting up Microsoft SQL Server 2022 ==="

# Configuration
SA_PASSWORD="GymAnything#2024"
MSSQL_CONTAINER="mssql-server"
MSSQL_PORT="1433"
ADVENTUREWORKS_URL="https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak"

# Function to wait for SQL Server to be ready
wait_for_mssql() {
    local timeout=${1:-180}
    local elapsed=0

    echo "Waiting for SQL Server to be ready..."

    while [ $elapsed -lt $timeout ]; do
        # Try to connect using sqlcmd
        if docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$SA_PASSWORD" -C \
            -Q "SELECT 1" 2>/dev/null | grep -q "1"; then
            echo "SQL Server is ready after ${elapsed}s"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s"
    done

    echo "WARNING: SQL Server readiness check timed out after ${timeout}s"
    return 1
}

# Create docker-compose.yml for SQL Server
echo "Creating Docker Compose configuration..."
mkdir -p /home/ga/mssql/backup
cat > /home/ga/mssql/docker-compose.yml << 'DOCKERCOMPOSE'
version: '3.8'

services:
  mssql-server:
    image: mcr.microsoft.com/mssql/server:2022-latest
    container_name: mssql-server
    environment:
      - ACCEPT_EULA=Y
      - MSSQL_SA_PASSWORD=GymAnything#2024
      - MSSQL_PID=Developer
    ports:
      - "1433:1433"
    volumes:
      - mssql-data:/var/opt/mssql
      - /home/ga/mssql/backup:/backup
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'GymAnything#2024' -C -Q 'SELECT 1' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

volumes:
  mssql-data:
DOCKERCOMPOSE

chown -R ga:ga /home/ga/mssql

# Start SQL Server container
echo "Starting SQL Server Docker container..."
cd /home/ga/mssql
docker-compose up -d

echo "Container starting..."
docker-compose ps

# Wait for SQL Server to be fully ready
wait_for_mssql 180

# Download AdventureWorks sample database
echo ""
echo "Downloading AdventureWorks2022 sample database..."
cd /home/ga/mssql/backup

if [ ! -f "AdventureWorks2022.bak" ]; then
    wget -O AdventureWorks2022.bak "$ADVENTUREWORKS_URL" 2>&1 || {
        echo "Failed to download AdventureWorks2022.bak"
        echo "Continuing without sample database..."
    }
fi

# Restore AdventureWorks database if backup exists
if [ -f "AdventureWorks2022.bak" ]; then
    echo ""
    echo "Restoring AdventureWorks2022 database..."

    # Get logical file names from backup
    docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -Q "RESTORE FILELISTONLY FROM DISK = '/backup/AdventureWorks2022.bak'" 2>/dev/null | head -20

    # Restore the database
    docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -Q "
        RESTORE DATABASE AdventureWorks2022
        FROM DISK = '/backup/AdventureWorks2022.bak'
        WITH
            MOVE 'AdventureWorks2022' TO '/var/opt/mssql/data/AdventureWorks2022.mdf',
            MOVE 'AdventureWorks2022_log' TO '/var/opt/mssql/data/AdventureWorks2022_log.ldf',
            REPLACE
        " 2>&1 || {
            echo "Warning: Could not restore AdventureWorks database"
            echo "Agent may need to restore it manually"
        }

    # Verify restoration
    DB_CHECK=$(docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" -C \
        -Q "SELECT name FROM sys.databases WHERE name = 'AdventureWorks2022'" -h -1 2>/dev/null)

    if echo "$DB_CHECK" | grep -q "AdventureWorks2022"; then
        echo "AdventureWorks2022 database restored successfully!"

        # Get some stats
        PRODUCT_COUNT=$(docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$SA_PASSWORD" -C \
            -Q "SELECT COUNT(*) FROM AdventureWorks2022.Production.Product" -h -1 2>/dev/null | tr -d ' ')
        PERSON_COUNT=$(docker exec $MSSQL_CONTAINER /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "$SA_PASSWORD" -C \
            -Q "SELECT COUNT(*) FROM AdventureWorks2022.Person.Person" -h -1 2>/dev/null | tr -d ' ')

        echo "  Products: $PRODUCT_COUNT"
        echo "  People: $PERSON_COUNT"
    else
        echo "Warning: AdventureWorks2022 database may not have been restored properly"
    fi
fi

# Configure Azure Data Studio connection profile
echo ""
echo "Configuring Azure Data Studio..."

ADS_CONFIG_DIR="/home/ga/.config/azuredatastudio/User"
mkdir -p "$ADS_CONFIG_DIR"

# Create connection settings
cat > "$ADS_CONFIG_DIR/settings.json" << 'ADSSETTINGS'
{
    "workbench.enablePreviewFeatures": false,
    "workbench.colorTheme": "Default Dark+",
    "telemetry.enableTelemetry": false,
    "update.mode": "none",
    "window.restoreWindows": "none",
    "workbench.startupEditor": "none",
    "sql.defaultDatabase": "AdventureWorks2022"
}
ADSSETTINGS

# Create connection profile for SQL Server
cat > "$ADS_CONFIG_DIR/connections.json" << 'ADSCONNS'
{
    "datasource.connectionGroups": [
        {
            "name": "Local SQL Server",
            "id": "local-sql-group"
        }
    ],
    "datasource.connections": [
        {
            "options": {
                "server": "localhost,1433",
                "database": "AdventureWorks2022",
                "user": "sa",
                "authenticationType": "SqlLogin",
                "password": "GymAnything#2024",
                "connectionName": "Local SQL Server 2022",
                "groupId": "local-sql-group",
                "databaseDisplayName": "AdventureWorks2022",
                "encrypt": "Optional",
                "trustServerCertificate": true
            },
            "groupId": "local-sql-group",
            "providerName": "MSSQL",
            "savePassword": true,
            "id": "local-mssql-connection"
        }
    ]
}
ADSCONNS

chown -R ga:ga /home/ga/.config/azuredatastudio

# Create desktop shortcut
echo "Creating desktop shortcuts..."
mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/AzureDataStudio.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Azure Data Studio
Comment=Microsoft SQL Server Management
Exec=azuredatastudio
Icon=azuredatastudio
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
chmod +x /home/ga/Desktop/AzureDataStudio.desktop
chown ga:ga /home/ga/Desktop/AzureDataStudio.desktop

# Create utility script for database queries
echo "Creating utility scripts..."
cat > /usr/local/bin/mssql-query << 'SQLQUERYEOF'
#!/bin/bash
# Execute SQL query against SQL Server (via Docker)
# Usage: mssql-query "SELECT * FROM AdventureWorks2022.Production.Product"
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "GymAnything#2024" -C -d AdventureWorks2022 \
    -Q "$1"
SQLQUERYEOF
chmod +x /usr/local/bin/mssql-query

# Create script to list databases
cat > /usr/local/bin/mssql-databases << 'DBLISTEOF'
#!/bin/bash
# List all databases in SQL Server
docker exec mssql-server /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "GymAnything#2024" -C \
    -Q "SELECT name FROM sys.databases ORDER BY name"
DBLISTEOF
chmod +x /usr/local/bin/mssql-databases

# Launch Azure Data Studio for the ga user
echo "Launching Azure Data Studio..."
# Use snap path if available, otherwise fallback to standard path
ADS_CMD="/snap/bin/azuredatastudio"
if [ ! -x "$ADS_CMD" ]; then
    ADS_CMD="azuredatastudio"
fi
su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio.log 2>&1 &"

# Wait for Azure Data Studio window
sleep 8
ADS_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio\|welcome"; then
        ADS_STARTED=true
        echo "Azure Data Studio window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$ADS_STARTED" = true ]; then
    sleep 2
    # Maximize Azure Data Studio window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== Microsoft SQL Server Setup Complete ==="
echo ""
echo "SQL Server is running at: localhost:${MSSQL_PORT}"
echo ""
echo "Connection Details:"
echo "  Server: localhost,1433"
echo "  Username: sa"
echo "  Password: ${SA_PASSWORD}"
echo "  Database: AdventureWorks2022"
echo ""
echo "Utility commands:"
echo "  mssql-query \"SELECT TOP 10 * FROM Production.Product\""
echo "  mssql-databases"
echo ""
echo "Docker commands:"
echo "  docker-compose -f /home/ga/mssql/docker-compose.yml logs -f"
echo "  docker-compose -f /home/ga/mssql/docker-compose.yml ps"
echo ""
