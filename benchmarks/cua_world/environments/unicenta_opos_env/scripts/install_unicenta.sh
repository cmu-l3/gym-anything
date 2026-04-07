#!/bin/bash
# pre_start hook — install uniCenta oPOS 4.6.4 and dependencies
# Runs as root before the desktop starts

echo "=== Installing uniCenta oPOS ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Install Java 11, MySQL, GUI tools
echo "Installing Java 11..."
apt-get install -y openjdk-11-jre openjdk-11-jdk

echo "Installing MySQL Server..."
apt-get install -y mysql-server mysql-client

echo "Installing GUI tools..."
apt-get install -y \
    xdotool wmctrl x11-utils scrot imagemagick \
    wget unzip python3 python3-pip python3-pymysql \
    net-tools curl jq dos2unix \
    fonts-liberation fonts-dejavu-extra fonts-noto

# -----------------------------------------------------------------------
# Download uniCenta oPOS 4.6.4 from SourceForge
# -----------------------------------------------------------------------
echo "Downloading uniCenta oPOS 4.6.4..."
DEST="/tmp/unicentaopos-installer.run"

wget -q --no-check-certificate --tries=3 --timeout=180 --content-disposition \
     -O "$DEST" \
     "https://sourceforge.net/projects/unicentaopos/files/releases/linux/unicentaopos-4.6.4-linux-x64-installer.run/download"

# Validate download (should be >100MB)
if [ -f "$DEST" ]; then
    FILESIZE=$(stat -c%s "$DEST" 2>/dev/null || echo "0")
    if [ "$FILESIZE" -lt 100000000 ]; then
        echo "Primary download too small ($FILESIZE bytes), trying v4.6.1..."
        rm -f "$DEST"
        wget -q --no-check-certificate --tries=3 --timeout=180 --content-disposition \
             -O "$DEST" \
             "https://sourceforge.net/projects/unicentaopos/files/releases/linux/unicentaopos-4.6.1-linux-x64-installer.run/download"
    fi
fi

if [ ! -f "$DEST" ] || [ ! -s "$DEST" ]; then
    echo "ERROR: Could not download uniCenta oPOS installer"
    touch /tmp/unicenta_install_failed
    exit 1
fi

echo "Download complete: $(du -sh $DEST | cut -f1)"

# Run installer in unattended mode
echo "Running uniCenta oPOS installer..."
chmod +x "$DEST"
"$DEST" --mode unattended --prefix /opt/unicentaopos 2>/tmp/unicenta_installer.log || true
rm -f "$DEST"

# Verify installation
UNICENTA_JAR=$(find /opt/unicentaopos -maxdepth 2 -name "unicentaopos.jar" 2>/dev/null | head -1)
if [ -z "$UNICENTA_JAR" ] || [ ! -f "$UNICENTA_JAR" ]; then
    echo "ERROR: unicentaopos.jar not found after installation"
    touch /tmp/unicenta_install_failed
    exit 1
fi

UNICENTA_DIR=$(dirname "$UNICENTA_JAR")
echo "uniCenta oPOS installed at: $UNICENTA_DIR"
echo "$UNICENTA_DIR" > /tmp/unicenta_install_dir.txt

# -----------------------------------------------------------------------
# Download MySQL Connector/J 8.0.33 (required for MySQL 8.0 + Java 11)
# The bundled connector 5.1.x has timezone and classloader issues with Java 11
# -----------------------------------------------------------------------
echo "Downloading MySQL Connector/J 8.0.33..."
wget -q -O "$UNICENTA_DIR/lib/mysql-connector-j-8.0.33.jar" \
    "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.0.33/mysql-connector-j-8.0.33.jar"

if [ ! -s "$UNICENTA_DIR/lib/mysql-connector-j-8.0.33.jar" ]; then
    echo "WARNING: Failed to download MySQL Connector 8.0.33"
    # Keep existing 5.1.x connector as fallback
fi

MYSQL_JAR=$(ls "$UNICENTA_DIR/lib/mysql-connector-j-8.0.33.jar" "$UNICENTA_DIR/lib/mysql-connector-java"*.jar 2>/dev/null | head -1)
echo "MySQL connector JAR: $MYSQL_JAR"
echo "$MYSQL_JAR" > /tmp/unicenta_mysql_jar.txt

# -----------------------------------------------------------------------
# Extract schema SQL and template resources from JAR
# -----------------------------------------------------------------------
echo "Extracting schema SQL and templates from JAR..."
mkdir -p /opt/unicentaopos/sql /tmp/unicenta_resources

# Extract schema SQL
unzip -p "$UNICENTA_JAR" "com/openbravo/pos/scripts/MySQL-create.sql" \
    > /opt/unicentaopos/sql/MySQL-create.sql 2>/dev/null || true

# Fix ROW_FORMAT for MySQL 8.0 compatibility (Compact → DYNAMIC)
if [ -s /opt/unicentaopos/sql/MySQL-create.sql ]; then
    cp /opt/unicentaopos/sql/MySQL-create.sql /opt/unicentaopos/sql/MySQL-create-fixed.sql
    sed -i 's/ROW_FORMAT = Compact/ROW_FORMAT = DYNAMIC/g' /opt/unicentaopos/sql/MySQL-create-fixed.sql
    sed -i 's/ROW_FORMAT=Compact/ROW_FORMAT=DYNAMIC/g' /opt/unicentaopos/sql/MySQL-create-fixed.sql
    echo "Schema SQL extracted and fixed: $(wc -l < /opt/unicentaopos/sql/MySQL-create-fixed.sql) lines"
fi

# Extract template resources (for system data insertion)
cd /tmp/unicenta_resources
jar xf "$UNICENTA_JAR" com/openbravo/pos/templates/ 2>/dev/null || true
echo "Templates extracted: $(ls /tmp/unicenta_resources/com/openbravo/pos/templates/ 2>/dev/null | wc -l) files"

# -----------------------------------------------------------------------
# Create launcher script (uses -cp, NOT -jar)
# CRITICAL: uniCenta's start.sh uses -cp with unicentaopos.jar + locales/ + reports/
# The lib/ JARs are loaded dynamically by the app via dirname.path property
# The MySQL connector must be on the classpath for DriverManager to find it
# -----------------------------------------------------------------------
cat > /usr/local/bin/unicenta-pos << LAUNCHEOF
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
DIRNAME=$UNICENTA_DIR
CP=\$DIRNAME/unicentaopos.jar
CP=\$CP:\$DIRNAME/locales/
CP=\$CP:\$DIRNAME/reports/
CP=\$CP:$MYSQL_JAR
LIBRARYPATH=/lib/Linux/x86_64-unknown-linux-gnu
exec java -cp \$CP -Xms512m -Xmx1024m -Djava.library.path=\$DIRNAME\$LIBRARYPATH -Ddirname.path=\$DIRNAME/ com.openbravo.pos.forms.StartPOS "\$@"
LAUNCHEOF
chmod +x /usr/local/bin/unicenta-pos

# -----------------------------------------------------------------------
# Fix permissions
# -----------------------------------------------------------------------
chown -R ga:ga /opt/unicentaopos/
chmod -R 755 /opt/unicentaopos/

apt-get clean
rm -rf /var/lib/apt/lists/*

touch /tmp/unicenta_install_done

echo "=== uniCenta oPOS installation complete ==="
echo "JAR: $UNICENTA_JAR"
echo "MySQL JAR: $MYSQL_JAR"
