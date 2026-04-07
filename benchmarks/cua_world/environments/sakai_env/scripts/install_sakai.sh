#!/bin/bash
# Sakai LMS Installation Script (pre_start hook)
# Installs Docker (for MariaDB), Java 17, Tomcat 9, and deploys pre-built Sakai 25.0 artifacts
set -e

echo "=== Installing Sakai LMS and Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update

# ============================================================
# 1. Install Docker (for MariaDB container)
# ============================================================
echo "--- Installing Docker ---"
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install Docker Compose v2 plugin
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VER="v2.24.5"
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

# ============================================================
# 2. Install Java 17 (Eclipse Temurin)
# ============================================================
echo "--- Installing Java 17 ---"
apt-get install -y wget apt-transport-https gnupg

# Add Eclipse Temurin (Adoptium) repository
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | apt-key add - 2>/dev/null || true
echo "deb https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/adoptium.list
apt-get update

# Try Temurin first, fall back to OpenJDK
if apt-get install -y temurin-17-jdk 2>/dev/null; then
    export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
else
    echo "Temurin not available, falling back to OpenJDK 17..."
    apt-get install -y openjdk-17-jdk
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi

echo "JAVA_HOME=$JAVA_HOME"
"$JAVA_HOME/bin/java" -version

echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile.d/java.sh
echo "export PATH=$JAVA_HOME/bin:\$PATH" >> /etc/profile.d/java.sh
chmod +x /etc/profile.d/java.sh

# ============================================================
# 3. Install Tomcat 9
# ============================================================
echo "--- Installing Tomcat 9 ---"
TOMCAT_VERSION="9.0.97"
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_FALLBACK="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"

for url in "$TOMCAT_URL" "$TOMCAT_FALLBACK"; do
    wget -q "$url" -O /tmp/tomcat.tar.gz && break
done

tar -xzf /tmp/tomcat.tar.gz -C /opt
ln -sf /opt/apache-tomcat-${TOMCAT_VERSION} /opt/tomcat
rm -f /tmp/tomcat.tar.gz

export CATALINA_HOME=/opt/tomcat
TOMCAT_REAL=$(readlink -f "$CATALINA_HOME")

# Configure Tomcat JVM with Java 17 module opens required by Sakai 25 + Ignite
cat > "$CATALINA_HOME/bin/setenv.sh" << 'SETENV'
#!/bin/bash
export JAVA_OPTS="-server -Xms1g -Xmx3g \
  -Djava.awt.headless=true \
  -Dhttp.agent=Sakai \
  -Dorg.apache.jasper.compiler.Parser.STRICT_QUOTE_ESCAPING=false \
  -Dsakai.home=/opt/sakai \
  -Dsakai.security=/opt/sakai \
  -Duser.timezone=US/Eastern \
  -Dsakai.cookieName=SAKAI_SESSION \
  --add-opens=java.base/java.lang=ALL-UNNAMED \
  --add-opens=java.base/java.io=ALL-UNNAMED \
  --add-opens=java.base/java.util=ALL-UNNAMED \
  --add-opens=java.base/java.util.concurrent=ALL-UNNAMED \
  --add-opens=java.rmi/sun.rmi.transport=ALL-UNNAMED \
  --add-opens=java.base/java.nio=ALL-UNNAMED \
  --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
  --add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
  --add-opens=java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens=java.base/java.net=ALL-UNNAMED \
  --add-opens=java.base/java.security=ALL-UNNAMED \
  --add-opens=java.base/sun.security.ssl=ALL-UNNAMED \
  --add-opens=java.base/sun.security.util=ALL-UNNAMED \
  --add-opens=java.base/java.text=ALL-UNNAMED \
  --add-opens=java.base/java.math=ALL-UNNAMED \
  --add-opens=java.sql/java.sql=ALL-UNNAMED \
  --add-opens=java.xml/com.sun.org.apache.xerces.internal.jaxp=ALL-UNNAMED"
SETENV
chmod +x "$CATALINA_HOME/bin/setenv.sh"

# Create Sakai config directory
mkdir -p /opt/sakai
mkdir -p /opt/sakai-data/content

# Remove default Tomcat webapps (except ROOT)
rm -rf "$CATALINA_HOME/webapps/docs" "$CATALINA_HOME/webapps/examples" "$CATALINA_HOME/webapps/host-manager"

# Increase Tomcat connector timeout and max upload size
sed -i 's/connectionTimeout="20000"/connectionTimeout="60000" maxPostSize="52428800"/' "$CATALINA_HOME/conf/server.xml"

# Disable JreMemoryLeakPreventionListener (causes JDBC driver scan crashes with Sakai's lib JARs)
sed -i 's|<Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener"|<!-- <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener"|' "$CATALINA_HOME/conf/server.xml"
sed -i 's|JreMemoryLeakPreventionListener" />|JreMemoryLeakPreventionListener" /> -->|' "$CATALINA_HOME/conf/server.xml"

echo "export CATALINA_HOME=$CATALINA_HOME" >> /etc/profile.d/tomcat.sh
chmod +x /etc/profile.d/tomcat.sh

# ============================================================
# 4. Deploy pre-built Sakai WAR files
# ============================================================
echo "--- Deploying pre-built Sakai artifacts ---"

DEPLOY_SRC="/workspace/data/sakai-deploy"

if [ -d "$DEPLOY_SRC/webapps" ]; then
    echo "Found pre-built Sakai webapps, deploying..."
    cp -r "$DEPLOY_SRC/webapps"/* "$CATALINA_HOME/webapps/" 2>/dev/null || true
    echo "Deployed $(ls "$CATALINA_HOME/webapps/" | wc -l) webapps"
else
    echo "ERROR: Pre-built Sakai webapps not found at $DEPLOY_SRC/webapps"
    exit 1
fi

if [ -d "$DEPLOY_SRC/components" ]; then
    mkdir -p "$CATALINA_HOME/components"
    cp -r "$DEPLOY_SRC/components"/* "$CATALINA_HOME/components/" 2>/dev/null || true
    echo "Deployed $(ls "$CATALINA_HOME/components/" | wc -l) components"
fi

if [ -d "$DEPLOY_SRC/lib" ]; then
    cp "$DEPLOY_SRC/lib"/*.jar "$CATALINA_HOME/lib/" 2>/dev/null || true
    echo "Deployed $(ls "$DEPLOY_SRC/lib"/*.jar 2>/dev/null | wc -l) additional lib JARs"
fi

# ============================================================
# 5. Install Firefox and GUI automation tools
# ============================================================
echo "--- Installing Firefox and automation tools ---"
apt-get install -y \
    firefox \
    wmctrl \
    xdotool \
    x11-utils \
    xclip \
    curl \
    jq \
    scrot \
    imagemagick \
    python3-pip

apt-get install -y python3-pymysql || true
pip3 install --no-cache-dir PyMySQL mysql-connector-python 2>/dev/null || true

# ============================================================
# 6. Set permissions
# ============================================================
echo "--- Setting permissions ---"
chmod +x "$TOMCAT_REAL"/bin/*.sh
chown -R ga:ga "$TOMCAT_REAL"
chown -R ga:ga /opt/sakai
chown -R ga:ga /opt/sakai-data
chown -h ga:ga /opt/tomcat

apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "=== Sakai Installation Complete ==="
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"
echo "Java: $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "Tomcat: $CATALINA_HOME"
echo "Sakai webapps: $(ls $CATALINA_HOME/webapps/ | wc -l)"
echo "Sakai components: $(ls $CATALINA_HOME/components/ 2>/dev/null | wc -l)"
echo "Sakai config: /opt/sakai"
echo "Firefox: $(which firefox)"
echo ""
echo "Sakai will be configured in post_start hook"
