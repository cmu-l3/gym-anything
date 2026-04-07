#!/bin/bash
set -e
# Visallo 2.2.14 Installation Script (pre_start hook)
# Installs Java 8, Elasticsearch 1.7.6, Jetty 9, and Visallo WAR + plugins directly

echo "=== Installing Visallo Dependencies ==="

export DEBIAN_FRONTEND=noninteractive

VISALLO_VERSION=2.2.14
VERTEXIUM_VERSION=2.4.7
VISALLO_DIR=/opt/visallo
ES_HOME=/opt/elasticsearch
JETTY_HOME=/opt/jetty
MAVEN_BASE="https://repo1.maven.org/maven2"

# ── 1. System packages ──────────────────────────────────────────────────────
echo "=== Installing system packages ==="
apt-get update -qq
apt-get install -y \
    openjdk-8-jdk openjdk-8-jre \
    ca-certificates curl wget \
    firefox \
    wmctrl xdotool x11-utils xclip \
    scrot imagemagick \
    python3-pip python3-requests \
    net-tools jq unzip \
    dbus-x11 libcanberra-gtk-module libcanberra-gtk3-module

# Set Java 8 as default
update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java 2>/dev/null || true
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
cat > /etc/profile.d/visallo.sh << 'ENVEOF'
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export VISALLO_DIR=/opt/visallo
export ES_HOME=/opt/elasticsearch
export JETTY_HOME=/opt/jetty
export PATH=$JAVA_HOME/bin:$PATH
ENVEOF

echo "Java: $(java -version 2>&1 | head -1)"

# ── 2. Create swap ──────────────────────────────────────────────────────────
echo "=== Creating swap space ==="
if [ ! -f /swapfile ]; then
    if fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null; then
        chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        echo "Swap enabled"
    fi
else
    swapon /swapfile 2>/dev/null || true
fi

# ── 3. Install Elasticsearch 1.7.6 ──────────────────────────────────────────
echo "=== Installing Elasticsearch 1.7.6 ==="
mkdir -p ${VISALLO_DIR}/{lib,config,datastore/{files,httpCache,elasticsearch/{data,logs,work}}}

if [ ! -f ${ES_HOME}/bin/elasticsearch ]; then
    wget -q "https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.7.6.tar.gz" -O /tmp/es.tar.gz || { echo "ERROR: Failed to download Elasticsearch"; exit 1; }
    mkdir -p ${ES_HOME}
    tar xzf /tmp/es.tar.gz -C /opt
    cp -r /opt/elasticsearch-1.7.6/* ${ES_HOME}/ 2>/dev/null || true
    rm -rf /opt/elasticsearch-1.7.6 /tmp/es.tar.gz

    cat > ${ES_HOME}/config/elasticsearch.yml << 'ESEOF'
cluster.name: visallo
node.name: visallo-node
network.host: 127.0.0.1
discovery.zen.ping.multicast.enabled: false
index.number_of_shards: 1
index.number_of_replicas: 0
ESEOF
    echo "Elasticsearch 1.7.6 installed"
fi

# Install Vertexium ES plugin
mkdir -p ${ES_HOME}/plugins/vertexium
wget -q "${MAVEN_BASE}/org/vertexium/vertexium-elasticsearch-singledocument-plugin/${VERTEXIUM_VERSION}/vertexium-elasticsearch-singledocument-plugin-${VERTEXIUM_VERSION}.jar" \
    -O ${ES_HOME}/plugins/vertexium/vertexium-elasticsearch-singledocument-plugin-${VERTEXIUM_VERSION}.jar 2>/dev/null || true

# Create ES user
id esuser >/dev/null 2>&1 || useradd -m -s /bin/bash esuser
chown -R esuser:esuser ${ES_HOME}

# ── 4. Install Jetty 9.4 ────────────────────────────────────────────────────
echo "=== Installing Jetty 9.4 ==="
if [ ! -f ${JETTY_HOME}/start.jar ]; then
    wget -q "${MAVEN_BASE}/org/eclipse/jetty/jetty-distribution/9.4.53.v20231009/jetty-distribution-9.4.53.v20231009.tar.gz" -O /tmp/jetty.tar.gz || { echo "ERROR: Failed to download Jetty"; exit 1; }
    tar xzf /tmp/jetty.tar.gz -C /opt
    mv /opt/jetty-distribution-9.4.53.v20231009 ${JETTY_HOME} 2>/dev/null || true
    rm -f /tmp/jetty.tar.gz
    echo "Jetty 9.4 installed"
fi

# ── 5. Download Visallo WAR and plugins ──────────────────────────────────────
echo "=== Downloading Visallo ${VISALLO_VERSION} WAR and plugins ==="

# WAR file
if [ ! -f ${JETTY_HOME}/webapps/root.war ]; then
    echo "Downloading WAR (~53MB)..."
    wget -q "${MAVEN_BASE}/org/visallo/visallo-web-war/${VISALLO_VERSION}/visallo-web-war-${VISALLO_VERSION}.war" \
        -O ${JETTY_HOME}/webapps/root.war || { echo "ERROR: Failed to download Visallo WAR"; exit 1; }
fi

if [ ! -f ${JETTY_HOME}/webapps/root.war ]; then
    echo "ERROR: Visallo WAR file missing after download"
    exit 1
fi

# Visallo plugin JARs
echo "Downloading plugin JARs..."
for p in visallo-web-auth-username-only visallo-model-vertexium-inmemory visallo-model-vertexium visallo-model-queue-inmemory; do
    wget -q "${MAVEN_BASE}/org/visallo/${p}/${VISALLO_VERSION}/${p}-${VISALLO_VERSION}.jar" \
        -O ${VISALLO_DIR}/lib/${p}-${VISALLO_VERSION}.jar 2>/dev/null || true
done

# Vertexium JARs
for vp in vertexium-inmemory vertexium-core vertexium-elasticsearch-singledocument; do
    wget -q "${MAVEN_BASE}/org/vertexium/${vp}/${VERTEXIUM_VERSION}/${vp}-${VERTEXIUM_VERSION}.jar" \
        -O ${VISALLO_DIR}/lib/${vp}-${VERTEXIUM_VERSION}.jar 2>/dev/null || true
done

# SimpleORM JARs (for in-memory ORM session)
wget -q "${MAVEN_BASE}/com/v5analytics/simpleorm/simple-orm-in-memory/1.3.0/simple-orm-in-memory-1.3.0.jar" \
    -O ${VISALLO_DIR}/lib/simple-orm-in-memory-1.3.0.jar 2>/dev/null || true
wget -q "${MAVEN_BASE}/com/v5analytics/simpleorm/simple-orm-core/1.3.0/simple-orm-core-1.3.0.jar" \
    -O ${VISALLO_DIR}/lib/simple-orm-core-1.3.0.jar 2>/dev/null || true

# Elasticsearch + Lucene JARs (ES 1.7.6 uses Lucene 4.10.4, but singledocument-2.4.7 built with 4.10.3)
wget -q "${MAVEN_BASE}/org/elasticsearch/elasticsearch/1.4.4/elasticsearch-1.4.4.jar" \
    -O ${VISALLO_DIR}/lib/elasticsearch-1.4.4.jar 2>/dev/null || true

for ljar in lucene-core lucene-analyzers-common lucene-queries lucene-queryparser lucene-sandbox \
            lucene-suggest lucene-misc lucene-join lucene-grouping lucene-spatial lucene-highlighter lucene-memory; do
    wget -q "${MAVEN_BASE}/org/apache/lucene/${ljar}/4.10.3/${ljar}-4.10.3.jar" \
        -O ${VISALLO_DIR}/lib/${ljar}-4.10.3.jar 2>/dev/null || true
done

# Recurrent (retry library needed by Vertexium)
wget -q "${MAVEN_BASE}/net/jodah/recurrent/0.3.3/recurrent-0.3.3.jar" \
    -O ${VISALLO_DIR}/lib/recurrent-0.3.3.jar 2>/dev/null || true

# Groovy (for ES scripting)
wget -q "${MAVEN_BASE}/org/codehaus/groovy/groovy/2.4.5/groovy-2.4.5.jar" \
    -O ${VISALLO_DIR}/lib/groovy-2.4.5.jar 2>/dev/null || true

# Spatial4j
wget -q "${MAVEN_BASE}/com/spatial4j/spatial4j/0.4.1/spatial4j-0.4.1.jar" \
    -O ${VISALLO_DIR}/lib/spatial4j-0.4.1.jar 2>/dev/null || true

# Remove any empty/failed downloads
find ${VISALLO_DIR}/lib -empty -delete
echo "Plugin JARs: $(ls ${VISALLO_DIR}/lib/*.jar 2>/dev/null | wc -l) files"

# ── 6. Inject plugin JARs into WAR ──────────────────────────────────────────
echo "=== Injecting plugin JARs into WAR ==="
if [ -f ${JETTY_HOME}/webapps/root.war ]; then
    mkdir -p /tmp/visallo-war
    cd /tmp/visallo-war
    jar xf ${JETTY_HOME}/webapps/root.war
    cp ${VISALLO_DIR}/lib/*.jar WEB-INF/lib/ 2>/dev/null || true
    echo "Total JARs in WAR: $(ls WEB-INF/lib/*.jar | wc -l)"
    jar cf ${JETTY_HOME}/webapps/root.war .
    cd /
    rm -rf /tmp/visallo-war
fi

# ── 7. Download and configure sample ontology ────────────────────────────────
echo "=== Setting up ontology ==="
mkdir -p ${VISALLO_DIR}/config/ontology-sample

# Use local ontology (bundled in config mount) — GitHub source may be unreliable
if [ -f /workspace/config/ontology/sample.owl ]; then
    cp /workspace/config/ontology/sample.owl ${VISALLO_DIR}/config/ontology-sample/
    echo "Ontology copied from local config"
else
    wget -q "https://raw.githubusercontent.com/FantasyNitroGEN/visallo/master/config/ontology-sample/sample.owl" \
        -O ${VISALLO_DIR}/config/ontology-sample/sample.owl 2>/dev/null || echo "WARNING: Failed to download ontology"
fi

# Extract entity.png icon from core JAR and create all icon variants
cd /tmp
mkdir -p icon-extract && cd icon-extract
jar xf ${JETTY_HOME}/webapps/root.war WEB-INF/lib/visallo-core-${VISALLO_VERSION}.jar
jar xf WEB-INF/lib/visallo-core-${VISALLO_VERSION}.jar org/visallo/core/model/ontology/entity.png 2>/dev/null || true
if [ -f org/visallo/core/model/ontology/entity.png ]; then
    for ic in audio contactInformation document emailAddress image location person phoneNumber raw video zipCode entity; do
        cp org/visallo/core/model/ontology/entity.png ${VISALLO_DIR}/config/ontology-sample/${ic}.png
    done
fi
cd / && rm -rf /tmp/icon-extract

# ── 8. Write Visallo configuration ──────────────────────────────────────────
echo "=== Writing Visallo configuration ==="
cp /workspace/config/visallo/visallo.properties ${VISALLO_DIR}/config/ 2>/dev/null || true

# Set permissions
chown -R ga:ga ${VISALLO_DIR}
chmod -R 755 ${VISALLO_DIR}

# ── 9. Pre-stage ICIJ Panama Papers data ───────────────────────────────────
echo "=== Staging ICIJ Panama Papers data ==="
mkdir -p /home/ga/Documents
cp /workspace/data/panama_papers_*.csv /home/ga/Documents/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents
echo "ICIJ data files copied: $(ls /home/ga/Documents/panama_papers_*.csv 2>/dev/null | wc -l) files"

echo "=== Visallo Installation Complete ==="
echo "Elasticsearch: ${ES_HOME}"
echo "Jetty: ${JETTY_HOME}"
echo "Visallo config: ${VISALLO_DIR}/config"
echo "WAR: ${JETTY_HOME}/webapps/root.war"
