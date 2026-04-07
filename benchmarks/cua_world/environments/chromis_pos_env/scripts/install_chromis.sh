#!/bin/bash
set -e

echo "=== Installing Chromis POS ==="

export DEBIAN_FRONTEND=noninteractive

# ── 1. System packages ──────────────────────────────────────────────────────
echo "--- Installing system dependencies ---"
apt-get update
apt-get install -y \
    mariadb-server mariadb-client \
    wget curl unzip \
    xdotool wmctrl x11-utils scrot imagemagick \
    python3 python3-pip \
    libxrender1 libxtst6 libxi6 libxinerama1 libfreetype6 \
    fonts-dejavu-core fonts-liberation \
    libgtk-3-0 libgl1-mesa-glx

# ── 2. Install Liberica JDK 11 Full (includes JavaFX) ───────────────────────
echo "--- Installing Liberica JDK 11 Full (with JavaFX) ---"
LIBERICA_URL="https://download.bell-sw.com/java/11.0.25+11/bellsoft-jdk11.0.25+11-linux-amd64-full.deb"
LIBERICA_DEB="/tmp/liberica-jdk11-full.deb"

if wget -q --timeout=120 "$LIBERICA_URL" -O "$LIBERICA_DEB" 2>/dev/null && [ -s "$LIBERICA_DEB" ]; then
    dpkg -i "$LIBERICA_DEB" 2>/dev/null || apt-get install -f -y
    echo "Liberica JDK 11 Full installed"
else
    echo "Liberica download failed, trying OpenJDK + OpenJFX..."
    apt-get install -y openjdk-11-jdk openjdk-11-jre openjfx libopenjfx-java libopenjfx-jni 2>/dev/null || \
    apt-get install -y openjdk-11-jdk openjdk-11-jre 2>/dev/null
fi
rm -f "$LIBERICA_DEB"

# Set JAVA_HOME (Liberica installs to /usr/lib/jvm/bellsoft-java11-full-amd64)
if [ -d "/usr/lib/jvm/bellsoft-java11-full-amd64" ]; then
    export JAVA_HOME=/usr/lib/jvm/bellsoft-java11-full-amd64
elif [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
fi
echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment
echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile.d/java.sh
export PATH="$JAVA_HOME/bin:$PATH"

# Set Liberica as default java
update-alternatives --install /usr/bin/java java "$JAVA_HOME/bin/java" 100 2>/dev/null || true
update-alternatives --set java "$JAVA_HOME/bin/java" 2>/dev/null || true

echo "--- Java version ---"
java -version 2>&1

# ── 3. Start MariaDB ────────────────────────────────────────────────────────
echo "--- Starting MariaDB ---"
systemctl enable mariadb
systemctl start mariadb

TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
        echo "MariaDB is ready"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: MariaDB failed to start within ${TIMEOUT}s"
    exit 1
fi

# ── 4. Create Chromis POS database ──────────────────────────────────────────
echo "--- Creating Chromis POS database ---"
mysql -u root << 'SQLEOF'
CREATE DATABASE IF NOT EXISTS chromispos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- Use root user directly with no password for simplicity (Chromis password handling quirk)
GRANT ALL PRIVILEGES ON chromispos.* TO 'root'@'localhost';
-- Also create a chromispos user with native auth and explicit plugin
CREATE USER IF NOT EXISTS 'chromispos'@'localhost' IDENTIFIED WITH mysql_native_password BY 'chromispos123';
GRANT ALL PRIVILEGES ON chromispos.* TO 'chromispos'@'localhost';
FLUSH PRIVILEGES;
SQLEOF
echo "Database 'chromispos' created"

# ── 5. Download and install Chromis POS ──────────────────────────────────────
echo "--- Downloading Chromis POS ---"
CHROMIS_DIR="/opt/chromispos"
mkdir -p "$CHROMIS_DIR"

INSTALLER_URL="https://sourceforge.net/projects/chromispos/files/Linux/ChromisPOS_unix_154-232306.sh/download"
INSTALLER_PATH="/tmp/chromispos_installer.sh"

echo "Downloading from SourceForge..."
wget --timeout=180 -L "$INSTALLER_URL" -O "$INSTALLER_PATH" 2>&1 || true

FILE_SIZE=0
if [ -f "$INSTALLER_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$INSTALLER_PATH" 2>/dev/null || echo "0")
    echo "Downloaded installer: ${FILE_SIZE} bytes"
fi

INSTALLED=0
if [ "$FILE_SIZE" -gt 50000000 ]; then
    chmod +x "$INSTALLER_PATH"

    # Use text mode with automated input (unattended mode hangs on this installer)
    echo "Running installer in text mode with automated input..."
    # Generate plenty of Enter presses + 'y' for license acceptance
    # The installer prompts: info screen (Enter), license (y+Enter), dir (Enter), confirm (y+Enter)
    (for i in $(seq 1 20); do echo ""; sleep 0.5; done; echo "y"; for i in $(seq 1 20); do echo ""; sleep 0.5; done) | \
        timeout 300 "$INSTALLER_PATH" --mode text --prefix "$CHROMIS_DIR" 2>&1 || true

    # Check if installation succeeded
    if [ -f "$CHROMIS_DIR/chromispos.jar" ] || [ -f "$CHROMIS_DIR/ChromisPOS.jar" ] || [ -f "$CHROMIS_DIR/start.sh" ]; then
        echo "Installer completed successfully"
        INSTALLED=1
    else
        echo "Text mode install may have failed, checking subdirectories..."
    fi
fi

# Verify the installation
if [ -f "$CHROMIS_DIR/chromispos.jar" ] || [ -f "$CHROMIS_DIR/ChromisPOS.jar" ]; then
    echo "Chromis POS JAR found after installer"
    INSTALLED=1
fi

# Check if installer put files in a subdirectory
if [ $INSTALLED -eq 0 ]; then
    for subdir in "$CHROMIS_DIR"/*/; do
        if [ -f "${subdir}chromispos.jar" ] || [ -f "${subdir}ChromisPOS.jar" ]; then
            echo "Found JAR in subdirectory: $subdir"
            mv "${subdir}"* "$CHROMIS_DIR/" 2>/dev/null || true
            INSTALLED=1
            break
        fi
    done
fi

# Fallback: try to extract the installer as a self-extracting archive
if [ $INSTALLED -eq 0 ] && [ -f "$INSTALLER_PATH" ] && [ "$FILE_SIZE" -gt 50000000 ]; then
    echo "--- Attempting to extract installer payload ---"
    # Bitrock installers have a payload after the shell script header
    SKIP_LINES=$(awk '/^exit 0/{print NR+1; exit}' "$INSTALLER_PATH" 2>/dev/null || echo "")
    if [ -n "$SKIP_LINES" ]; then
        tail -n +$SKIP_LINES "$INSTALLER_PATH" > /tmp/chromis_payload.tar.gz 2>/dev/null || true
        if [ -s /tmp/chromis_payload.tar.gz ]; then
            cd "$CHROMIS_DIR"
            tar xzf /tmp/chromis_payload.tar.gz 2>/dev/null || \
            unzip /tmp/chromis_payload.tar.gz 2>/dev/null || true
        fi
    fi
fi

# Final fallback: build from GitHub source
if [ ! -f "$CHROMIS_DIR/chromispos.jar" ] && [ ! -f "$CHROMIS_DIR/ChromisPOS.jar" ]; then
    echo "--- Building from GitHub source as fallback ---"
    apt-get install -y ant git 2>/dev/null || true

    cd /tmp
    rm -rf ChromisPOS
    git clone --depth 1 https://github.com/ChromisPos/ChromisPOS.git 2>&1 || true

    if [ -d "ChromisPOS" ]; then
        cd ChromisPOS
        if [ -f "build.xml" ]; then
            echo "Building with ant..."
            ant 2>&1 || true
        fi

        # Copy build artifacts
        mkdir -p "$CHROMIS_DIR/lib"
        find . -name "*.jar" -exec cp {} "$CHROMIS_DIR/lib/" \; 2>/dev/null || true
        find . -name "chromispos*.jar" -exec cp {} "$CHROMIS_DIR/" \; 2>/dev/null || true

        # Copy resource directories
        for d in reports locales images; do
            [ -d "$d" ] && cp -r "$d" "$CHROMIS_DIR/" 2>/dev/null || true
            [ -d "src-pos/$d" ] && cp -r "src-pos/$d" "$CHROMIS_DIR/" 2>/dev/null || true
        done
        cd /tmp
    fi
fi

# ── 6. Find the JAR and set up ───────────────────────────────────────────────
echo "--- Verifying Chromis POS installation ---"
CHROMIS_JAR=""
# Check common locations
for candidate in \
    "$CHROMIS_DIR/chromispos.jar" \
    "$CHROMIS_DIR/ChromisPOS.jar" \
    "$CHROMIS_DIR/chromis.jar"; do
    if [ -f "$candidate" ]; then
        CHROMIS_JAR="$candidate"
        break
    fi
done

# Search more broadly
if [ -z "$CHROMIS_JAR" ]; then
    CHROMIS_JAR=$(find "$CHROMIS_DIR" -maxdepth 3 -name "chromis*.jar" -o -name "Chromis*.jar" 2>/dev/null | head -1)
fi

echo "Chromis POS JAR: ${CHROMIS_JAR:-NOT FOUND}"
echo "Files in $CHROMIS_DIR:"
find "$CHROMIS_DIR" -maxdepth 2 -type f \( -name "*.jar" -o -name "*.sh" -o -name "*.properties" \) 2>/dev/null | head -20

# ── 7. Download MySQL connector ─────────────────────────────────────────────
MYSQL_CONNECTOR=$(find "$CHROMIS_DIR" -name "mysql-connector*.jar" 2>/dev/null | head -1)
if [ -z "$MYSQL_CONNECTOR" ]; then
    echo "Downloading MySQL JDBC connector..."
    mkdir -p "$CHROMIS_DIR/lib"
    wget -q "https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar" \
        -O "$CHROMIS_DIR/lib/mysql-connector-java-5.1.49.jar" 2>/dev/null || true
    MYSQL_CONNECTOR="$CHROMIS_DIR/lib/mysql-connector-java-5.1.49.jar"
fi

# ── 8. Create launcher script ───────────────────────────────────────────────
echo "--- Creating launcher script ---"

cat > /usr/local/bin/launch-chromispos << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/run/user/1000/gdm/Xauthority

# Use Liberica if available (has JavaFX), fall back to OpenJDK
if [ -d "/usr/lib/jvm/bellsoft-java11-full-amd64" ]; then
    export JAVA_HOME=/usr/lib/jvm/bellsoft-java11-full-amd64
elif [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
fi
export PATH="$JAVA_HOME/bin:$PATH"

CHROMIS_DIR="/opt/chromispos"
cd "$CHROMIS_DIR"

# Try start.sh first (only if it has content - installer sometimes creates empty file)
if [ -f "$CHROMIS_DIR/start.sh" ] && [ -s "$CHROMIS_DIR/start.sh" ]; then
    exec bash "$CHROMIS_DIR/start.sh" "$@"
fi

# Find the main JAR
CHROMIS_JAR=""
for candidate in "$CHROMIS_DIR/chromispos.jar" "$CHROMIS_DIR/ChromisPOS.jar"; do
    if [ -f "$candidate" ]; then
        CHROMIS_JAR="$candidate"
        break
    fi
done

if [ -z "$CHROMIS_JAR" ]; then
    CHROMIS_JAR=$(find "$CHROMIS_DIR" -maxdepth 3 -name "chromis*.jar" -o -name "Chromis*.jar" 2>/dev/null | head -1)
fi

if [ -n "$CHROMIS_JAR" ] && [ -f "$CHROMIS_JAR" ]; then
    # Build classpath from lib/
    CLASSPATH="$CHROMIS_JAR"
    if [ -d "$CHROMIS_DIR/lib" ]; then
        for jar in "$CHROMIS_DIR/lib"/*.jar; do
            [ -f "$jar" ] && CLASSPATH="$CLASSPATH:$jar"
        done
    fi
    exec java -Xms512m -Xmx2048m -cp "$CLASSPATH" -jar "$CHROMIS_JAR" "$@"
else
    echo "ERROR: Cannot find Chromis POS JAR or start script"
    ls -la "$CHROMIS_DIR"
    exit 1
fi
LAUNCHEOF
chmod +x /usr/local/bin/launch-chromispos

# ── 9. Pre-create config ────────────────────────────────────────────────────
echo "--- Setting up configuration ---"
mkdir -p /home/ga/.chromispos

# Copy config to app dir and home dir
cp /workspace/config/chromisposconfig.properties "$CHROMIS_DIR/chromisposconfig.properties" 2>/dev/null || true
cp /workspace/config/chromisposconfig.properties /home/ga/chromisposconfig.properties 2>/dev/null || true

# Update MySQL connector library path in properties to match actual file
if [ -n "$MYSQL_CONNECTOR" ] && [ -f "$MYSQL_CONNECTOR" ]; then
    sed -i "s|database.library=.*|database.library=$MYSQL_CONNECTOR|" "$CHROMIS_DIR/chromisposconfig.properties" 2>/dev/null || true
    sed -i "s|database.library=.*|database.library=$MYSQL_CONNECTOR|" /home/ga/chromisposconfig.properties 2>/dev/null || true
fi

# ── 10. Set permissions ─────────────────────────────────────────────────────
echo "--- Setting permissions ---"
chmod -R 755 "$CHROMIS_DIR"
chown -R ga:ga "$CHROMIS_DIR" 2>/dev/null || true
chown -R ga:ga /home/ga/.chromispos
chown ga:ga /home/ga/chromisposconfig.properties 2>/dev/null || true

# Desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ChromisPOS.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Chromis POS
Exec=/usr/local/bin/launch-chromispos
Icon=/opt/chromispos/chromispos.png
Type=Application
Categories=Office;Finance;
Terminal=false
DESKTOPEOF
chmod +x /home/ga/Desktop/ChromisPOS.desktop
chown ga:ga /home/ga/Desktop/ChromisPOS.desktop

echo "=== Chromis POS installation complete ==="
echo "JAVA_HOME=$JAVA_HOME"
java -version 2>&1
echo "JAR: ${CHROMIS_JAR:-NOT FOUND}"
echo "MySQL connector: ${MYSQL_CONNECTOR:-NOT FOUND}"
