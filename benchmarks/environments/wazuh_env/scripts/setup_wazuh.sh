#!/bin/bash
# post_start hook: Deploy and configure Wazuh SIEM environment
set -e

echo "=== Setting up Wazuh SIEM environment ==="

WAZUH_DIR="/home/ga/wazuh"
CERTS_DIR="${WAZUH_DIR}/config/wazuh_indexer_ssl_certs"
API_URL="https://localhost:55000"
WAZUH_API_USER="wazuh-wui"
WAZUH_API_PASS='MyS3cr37P450r.*-'
INDEXER_URL="https://localhost:9200"
INDEXER_USER="admin"
INDEXER_PASS="SecretPassword"

# --- Helper: poll until condition succeeds ---
wait_for_service() {
    local name="$1"
    local cmd="$2"
    local timeout="${3:-180}"
    local elapsed=0
    echo "Waiting for $name..."
    while [ $elapsed -lt $timeout ]; do
        if eval "$cmd" > /dev/null 2>&1; then
            echo "$name is ready (${elapsed}s)!"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Still waiting for $name (${elapsed}/${timeout}s)..."
    done
    echo "WARNING: $name did not become ready within ${timeout}s - continuing"
    return 0
}

# --- Step 1: Ensure Docker is running ---
echo "=== Step 1: Ensuring Docker is running ==="
systemctl start docker 2>/dev/null || true
sleep 5
docker info > /dev/null 2>&1 || { echo "ERROR: Docker not running"; exit 1; }

# --- Step 2: Set kernel parameters ---
echo "=== Step 2: Setting kernel parameters ==="
sysctl -w vm.max_map_count=262144

# --- Step 3: Prepare directory structure ---
echo "=== Step 3: Preparing directories ==="
mkdir -p "${CERTS_DIR}"
mkdir -p "${WAZUH_DIR}/config/wazuh_indexer"
mkdir -p "${WAZUH_DIR}/config/wazuh_dashboard"
mkdir -p "${WAZUH_DIR}/config/wazuh_cluster"

# --- Step 4: Write correct certs.yml (no node_type for single-node) ---
cat > "${WAZUH_DIR}/certs.yml" << 'CERTSEOF'
nodes:
  # Wazuh indexer server nodes
  indexer:
    - name: wazuh.indexer
      ip: wazuh.indexer

  # Wazuh server nodes
  # Use node_type only with more than one Wazuh manager
  server:
    - name: wazuh.manager
      ip: wazuh.manager

  # Wazuh dashboard node
  dashboard:
    - name: wazuh.dashboard
      ip: wazuh.dashboard
CERTSEOF

# --- Step 5: Write generate-certs.yml ---
cat > "${WAZUH_DIR}/generate-certs.yml" << 'GENCERTSEOF'
version: '3'
services:
  generator:
    image: wazuh/wazuh-certs-generator:0.0.2
    hostname: wazuh-certs-generator
    volumes:
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/:/certificates/
      - /home/ga/wazuh/certs.yml:/config/certs.yml
GENCERTSEOF

# --- Step 6: Write wazuh_indexer config ---
cat > "${WAZUH_DIR}/config/wazuh_indexer/wazuh.indexer.yml" << 'IDXEOF'
network.host: "0.0.0.0"
node.name: "wazuh.indexer"
path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer
discovery.type: single-node
http.port: 9200-9299
transport.tcp.port: 9300-9399
compatibility.override_main_response_version: true
plugins.security.ssl.http.pemcert_filepath: /usr/share/wazuh-indexer/certs/wazuh.indexer.pem
plugins.security.ssl.http.pemkey_filepath: /usr/share/wazuh-indexer/certs/wazuh.indexer.key
plugins.security.ssl.http.pemtrustedcas_filepath: /usr/share/wazuh-indexer/certs/root-ca.pem
plugins.security.ssl.transport.pemcert_filepath: /usr/share/wazuh-indexer/certs/wazuh.indexer.pem
plugins.security.ssl.transport.pemkey_filepath: /usr/share/wazuh-indexer/certs/wazuh.indexer.key
plugins.security.ssl.transport.pemtrustedcas_filepath: /usr/share/wazuh-indexer/certs/root-ca.pem
plugins.security.ssl.http.enabled: true
plugins.security.ssl.transport.enforce_hostname_verification: false
plugins.security.ssl.transport.resolve_hostname: false
plugins.security.authcz.admin_dn:
- "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US"
plugins.security.check_snapshot_restore_write_privileges: true
plugins.security.enable_snapshot_restore_privilege: true
plugins.security.nodes_dn:
- "CN=wazuh.indexer,OU=Wazuh,O=Wazuh,L=California,C=US"
plugins.security.restapi.roles_enabled:
- "all_access"
- "security_rest_api_access"
plugins.security.system_indices.enabled: true
plugins.security.system_indices.indices: [".opendistro-alerting-config", ".opendistro-alerting-alert*", ".opendistro-anomaly-results*", ".opendistro-anomaly-detector*", ".opendistro-anomaly-checkpoints", ".opendistro-anomaly-detection-state", ".opendistro-reports-*", ".opendistro-notifications-*", ".opendistro-notebooks", ".opensearch-observability", ".opendistro-asynchronous-search-response*", ".replication-metadata-store"]
plugins.security.allow_default_init_securityindex: true
cluster.routing.allocation.disk.threshold_enabled: false
IDXEOF

# --- Step 7: Write internal_users.yml ---
cat > "${WAZUH_DIR}/config/wazuh_indexer/internal_users.yml" << 'USERSEOF'
---
_meta:
  type: "internalusers"
  config_version: 2
admin:
  hash: "$2y$12$K/SpwjtB.wOHJ/Nc6GVRDuc1h0rM1DfvziFRNPtk27P.c4yDr9njO"
  reserved: true
  backend_roles:
  - "admin"
  description: "Demo admin user"
kibanaserver:
  hash: "$2a$12$4AcgAt3xwOWadA5s5blL6ev39OXDNhmOesEoo33eZtrq2N0YrU3H."
  reserved: true
  description: "Demo kibanaserver user"
USERSEOF

# --- Step 8: Write opensearch_dashboards.yml ---
cat > "${WAZUH_DIR}/config/wazuh_dashboard/opensearch_dashboards.yml" << 'DASHEOF'
server.host: 0.0.0.0
server.port: 5601
opensearch.hosts: https://wazuh.indexer:9200
opensearch.ssl.verificationMode: certificate
opensearch.requestHeadersWhitelist: ["securitytenant","Authorization"]
opensearch_security.multitenancy.enabled: false
opensearch_security.readonly_mode.roles: ["kibana_read_only"]
server.ssl.enabled: true
server.ssl.key: "/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem"
server.ssl.certificate: "/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem"
opensearch.ssl.certificateAuthorities: ["/usr/share/wazuh-dashboard/certs/root-ca.pem"]
uiSettings.overrides.defaultRoute: /app/wz-home
DASHEOF

# --- Step 9: Write dashboard wazuh.yml ---
cat > "${WAZUH_DIR}/config/wazuh_dashboard/wazuh.yml" << 'WAZUHDASHEOF'
hosts:
  - 1513629884013:
      url: "https://wazuh.manager"
      port: 55000
      username: wazuh-wui
      password: "MyS3cr37P450r.*-"
      run_as: false
WAZUHDASHEOF

# --- Step 10: Download wazuh_manager.conf ---
echo "=== Step 10: Downloading wazuh_manager.conf ==="
curl -fsSL "https://raw.githubusercontent.com/wazuh/wazuh-docker/v4.9.2/single-node/config/wazuh_cluster/wazuh_manager.conf" \
    -o "${WAZUH_DIR}/config/wazuh_cluster/wazuh_manager.conf" 2>/dev/null && \
    echo "Downloaded wazuh_manager.conf" || \
    cp /workspace/config/wazuh_cluster/wazuh_manager.conf "${WAZUH_DIR}/config/wazuh_cluster/wazuh_manager.conf" 2>/dev/null || \
    cat > "${WAZUH_DIR}/config/wazuh_cluster/wazuh_manager.conf" << 'MANAGEREOF'
<ossec_config>
  <global>
    <jsonout_output>yes</jsonout_output>
    <alerts_log>yes</alerts_log>
    <logall>no</logall>
    <logall_json>no</logall_json>
    <email_notification>no</email_notification>
    <smtp_server>smtp.example.wazuh.com</smtp_server>
    <email_from>wazuh@example.wazuh.com</email_from>
    <email_to>recipient@example.wazuh.com</email_to>
    <email_maxperhour>12</email_maxperhour>
    <email_log_source>alerts.log</email_log_source>
    <agents_disconnection_time>10m</agents_disconnection_time>
    <agents_disconnection_alert_time>0</agents_disconnection_alert_time>
  </global>
  <alerts>
    <log_alert_level>3</log_alert_level>
    <email_alert_level>12</email_alert_level>
  </alerts>
  <logging>
    <log_format>plain</log_format>
  </logging>
  <remote>
    <connection>secure</connection>
    <port>1514</port>
    <protocol>tcp</protocol>
    <queue_size>131072</queue_size>
  </remote>
  <rootcheck>
    <disabled>no</disabled>
    <frequency>43200</frequency>
    <skip_nfs>yes</skip_nfs>
  </rootcheck>
  <sca>
    <enabled>yes</enabled>
    <scan_on_start>yes</scan_on_start>
    <interval>12h</interval>
    <skip_nfs>yes</skip_nfs>
  </sca>
</ossec_config>
MANAGEREOF

# --- Step 11: Write docker-compose.yml (inline, correct paths) ---
echo "=== Step 11: Writing docker-compose.yml ==="
cat > "${WAZUH_DIR}/docker-compose.yml" << 'COMPOSEEOF'
version: '3.7'

services:
  wazuh.manager:
    image: wazuh/wazuh-manager:4.9.2
    hostname: wazuh.manager
    restart: always
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 655360
        hard: 655360
    ports:
      - "1514:1514"
      - "1515:1515"
      - "514:514/udp"
      - "55000:55000"
    environment:
      - INDEXER_URL=https://wazuh.indexer:9200
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=SecretPassword
      - FILEBEAT_SSL_VERIFICATION_MODE=full
      - SSL_CERTIFICATE_AUTHORITIES=/etc/ssl/root-ca.pem
      - SSL_CERTIFICATE=/etc/ssl/filebeat.pem
      - SSL_KEY=/etc/ssl/filebeat.key
      - API_USERNAME=wazuh-wui
      - API_PASSWORD=MyS3cr37P450r.*-
    volumes:
      - wazuh_api_configuration:/var/ossec/api/configuration
      - wazuh_etc:/var/ossec/etc
      - wazuh_logs:/var/ossec/logs
      - wazuh_queue:/var/ossec/queue
      - wazuh_var_multigroups:/var/ossec/var/multigroups
      - wazuh_integrations:/var/ossec/integrations
      - wazuh_active_response:/var/ossec/active-response/bin
      - wazuh_agentless:/var/ossec/agentless
      - wazuh_wodles:/var/ossec/wodles
      - filebeat_etc:/etc/filebeat
      - filebeat_var:/var/lib/filebeat
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/root-ca-manager.pem:/etc/ssl/root-ca.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/wazuh.manager.pem:/etc/ssl/filebeat.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/wazuh.manager-key.pem:/etc/ssl/filebeat.key
      - /home/ga/wazuh/config/wazuh_cluster/wazuh_manager.conf:/wazuh-config-mount/etc/ossec.conf

  wazuh.indexer:
    image: wazuh/wazuh-indexer:4.9.2
    hostname: wazuh.indexer
    restart: always
    ports:
      - "9200:9200"
    environment:
      - "OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g -XX:MaxDirectMemorySize=1g"
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      - wazuh-indexer-data:/var/lib/wazuh-indexer
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/root-ca.pem:/usr/share/wazuh-indexer/certs/root-ca.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/wazuh.indexer-key.pem:/usr/share/wazuh-indexer/certs/wazuh.indexer.key
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/wazuh.indexer.pem:/usr/share/wazuh-indexer/certs/wazuh.indexer.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/admin.pem:/usr/share/wazuh-indexer/certs/admin.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/admin-key.pem:/usr/share/wazuh-indexer/certs/admin-key.pem
      - /home/ga/wazuh/config/wazuh_indexer/wazuh.indexer.yml:/usr/share/wazuh-indexer/opensearch.yml
      - /home/ga/wazuh/config/wazuh_indexer/internal_users.yml:/usr/share/wazuh-indexer/opensearch-security/internal_users.yml

  wazuh.dashboard:
    image: wazuh/wazuh-dashboard:4.9.2
    hostname: wazuh.dashboard
    restart: always
    ports:
      - 443:5601
    environment:
      - INDEXER_USERNAME=admin
      - INDEXER_PASSWORD=SecretPassword
      - WAZUH_API_URL=https://wazuh.manager
      - DASHBOARD_USERNAME=kibanaserver
      - DASHBOARD_PASSWORD=kibanaserver
      - API_USERNAME=wazuh-wui
      - API_PASSWORD=MyS3cr37P450r.*-
    volumes:
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/wazuh.dashboard.pem:/usr/share/wazuh-dashboard/certs/wazuh-dashboard.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/wazuh.dashboard-key.pem:/usr/share/wazuh-dashboard/certs/wazuh-dashboard-key.pem
      - /home/ga/wazuh/config/wazuh_indexer_ssl_certs/root-ca.pem:/usr/share/wazuh-dashboard/certs/root-ca.pem
      - /home/ga/wazuh/config/wazuh_dashboard/opensearch_dashboards.yml:/usr/share/wazuh-dashboard/config/opensearch_dashboards.yml
      - /home/ga/wazuh/config/wazuh_dashboard/wazuh.yml:/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
      - wazuh-dashboard-config:/usr/share/wazuh-dashboard/data/wazuh/config
      - wazuh-dashboard-custom:/usr/share/wazuh-dashboard/plugins/wazuh/public/assets/custom
    depends_on:
      - wazuh.indexer
    links:
      - wazuh.indexer:wazuh.indexer
      - wazuh.manager:wazuh.manager

volumes:
  wazuh_api_configuration:
  wazuh_etc:
  wazuh_logs:
  wazuh_queue:
  wazuh_var_multigroups:
  wazuh_integrations:
  wazuh_active_response:
  wazuh_agentless:
  wazuh_wodles:
  filebeat_etc:
  filebeat_var:
  wazuh-indexer-data:
  wazuh-dashboard-config:
  wazuh-dashboard-custom:
COMPOSEEOF

chown -R ga:ga "${WAZUH_DIR}"
echo "Configuration files written"

# --- Step 12: Generate SSL certificates ---
echo "=== Step 12: Generating SSL certificates ==="
cd "${WAZUH_DIR}"
docker compose -f generate-certs.yml run --rm generator 2>&1 | tail -20

# Check if certs are real files (generator can create empty dirs on second run)
if [ ! -s "${CERTS_DIR}/root-ca.pem" ] || [ -d "${CERTS_DIR}/root-ca.pem" ]; then
    echo "ERROR: Certificate generation failed - cert is not a file!"
    ls -la "${CERTS_DIR}/" 2>/dev/null || true
    exit 1
fi
echo "Certificates generated successfully:"
ls "${CERTS_DIR}/"

# Fix permissions
chmod -R 600 "${CERTS_DIR}"/*
chown -R ga:ga "${CERTS_DIR}"

# --- Step 13: Start Wazuh containers ---
echo "=== Step 13: Starting Wazuh containers ==="
cd "${WAZUH_DIR}"

# Pull images (retry up to 3 times)
for i in 1 2 3; do
    docker compose pull 2>&1 | tail -5 && break || { echo "Pull attempt $i failed"; sleep 15; }
done

docker compose up -d
echo "Wazuh containers started"
docker ps --format "table {{.Names}}\t{{.Status}}"

# --- Step 14: Wait for Wazuh Indexer ---
echo "=== Step 14: Waiting for Wazuh Indexer ==="
wait_for_service "Wazuh Indexer" \
    "curl -sk -u ${INDEXER_USER}:${INDEXER_PASS} ${INDEXER_URL}/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'" \
    360

# --- Step 15: Wait for Wazuh Manager API ---
echo "=== Step 15: Waiting for Wazuh Manager API ==="
wait_for_service "Wazuh Manager API" \
    "curl -sk -u ${WAZUH_API_USER}:'${WAZUH_API_PASS}' -X POST ${API_URL}/security/user/authenticate?raw=true 2>/dev/null | grep -v '^$' | head -c 10 | grep -q 'eyJ'" \
    300

# --- Step 16: Wait for Wazuh Dashboard ---
echo "=== Step 16: Waiting for Wazuh Dashboard ==="
wait_for_service "Wazuh Dashboard" \
    "curl -sk -o /dev/null -w '%{http_code}' https://localhost:443/ | grep -qE '^(200|302)'" \
    300

# --- Step 17: Configure via API ---
echo "=== Step 17: Configuring Wazuh via API ==="
TOKEN=$(curl -sk -u "${WAZUH_API_USER}:${WAZUH_API_PASS}" \
    -X POST "${API_URL}/security/user/authenticate?raw=true" 2>/dev/null || echo "")

if [ -n "$TOKEN" ] && echo "$TOKEN" | grep -q "^eyJ"; then
    echo "API token obtained"
    # Create useful agent groups
    for group in linux-servers windows-workstations web-servers database-servers; do
        curl -sk -X POST "${API_URL}/groups" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"group_id\": \"${group}\"}" > /dev/null 2>&1 || true
    done
    echo "Agent groups created"
else
    echo "WARNING: API token not obtained - groups will be created at task time"
fi

# --- Step 18: Install custom rules ---
echo "=== Step 18: Installing custom rules ==="
TEMP_RULES=$(mktemp /tmp/custom_rules.XXXXXX.xml)
cat > "$TEMP_RULES" << 'RULESEOF'
<!-- Custom Wazuh rules for GymAnything environment -->
<group name="custom_rules,">

  <!-- SSH brute force detection -->
  <rule id="100001" level="10">
    <if_sid>5716</if_sid>
    <description>SSH authentication failure - possible brute force</description>
    <group>authentication_failed,pci_dss_10.2.4,gdpr_IV_35.7.d,hipaa_164.312.b,nist_800_53_AU.14,</group>
  </rule>

  <!-- Failed sudo attempts -->
  <rule id="100002" level="8">
    <if_sid>5401</if_sid>
    <match>incorrect password attempts</match>
    <description>Failed sudo attempt detected</description>
    <group>sudo_failed,authentication_failed,</group>
  </rule>

  <!-- Web application attack -->
  <rule id="100003" level="7">
    <if_sid>530</if_sid>
    <match>CPU usage is high</match>
    <description>High CPU usage detected on agent</description>
    <group>system_monitor,</group>
  </rule>

</group>
RULESEOF

# Wait for manager container to be ready
for i in $(seq 1 12); do
    if docker exec wazuh-wazuh.manager-1 ls /var/ossec/etc/rules/ > /dev/null 2>&1; then
        break
    fi
    echo "Waiting for manager container ($i/12)..."
    sleep 10
done

docker cp "$TEMP_RULES" wazuh-wazuh.manager-1:/var/ossec/etc/rules/local_rules.xml 2>/dev/null && \
    docker exec wazuh-wazuh.manager-1 chown root:wazuh /var/ossec/etc/rules/local_rules.xml 2>/dev/null && \
    docker exec wazuh-wazuh.manager-1 chmod 660 /var/ossec/etc/rules/local_rules.xml 2>/dev/null && \
    echo "Custom rules installed" || echo "WARNING: Could not install custom rules"
rm -f "$TEMP_RULES"

# --- Step 19: Install custom decoder ---
echo "=== Step 19: Installing custom decoder ==="
TEMP_DECODER=$(mktemp /tmp/custom_decoder.XXXXXX.xml)
cat > "$TEMP_DECODER" << 'DECODEREOF'
<!-- Custom decoders for GymAnything environment -->
<decoder name="gymapp">
  <prematch>^GymApp:</prematch>
</decoder>

<decoder name="gymapp-login">
  <parent>gymapp</parent>
  <prematch>Login</prematch>
  <regex>Login (attempt|success|failure) for user (\S+) from (\S+)</regex>
  <order>action,user,srcip</order>
</decoder>
DECODEREOF

docker cp "$TEMP_DECODER" wazuh-wazuh.manager-1:/var/ossec/etc/decoders/local_decoder.xml 2>/dev/null && \
    docker exec wazuh-wazuh.manager-1 chown root:wazuh /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null && \
    docker exec wazuh-wazuh.manager-1 chmod 660 /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null && \
    echo "Custom decoder installed" || echo "WARNING: Could not install custom decoder"
rm -f "$TEMP_DECODER"

# --- Step 20: Create API helper ---
echo "=== Step 20: Creating API helper ==="
cat > /usr/local/bin/wazuh-api << 'SCRIPTEOF'
#!/bin/bash
API_URL="https://localhost:55000"
API_USER="wazuh-wui"
API_PASS='MyS3cr37P450r.*-'
TOKEN=$(curl -sk -u "${API_USER}:${API_PASS}" \
    -X POST "${API_URL}/security/user/authenticate?raw=true")
METHOD="${1:-GET}"
ENDPOINT="${2:-/}"
BODY="${3:-}"
if [ -n "$BODY" ]; then
    curl -sk -X "$METHOD" "${API_URL}${ENDPOINT}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$BODY" | python3 -m json.tool 2>/dev/null || cat
else
    curl -sk -X "$METHOD" "${API_URL}${ENDPOINT}" \
        -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool 2>/dev/null || cat
fi
SCRIPTEOF
chmod +x /usr/local/bin/wazuh-api

# --- Step 21: Inject real security log data ---
# Inject real-format security events into Wazuh manager so alerts appear in dashboard
echo "=== Step 21: Injecting security log data ==="

# Wait for manager to be fully initialized
for i in $(seq 1 12); do
    if docker exec wazuh-wazuh.manager-1 ls /var/ossec/logs/alerts/ > /dev/null 2>&1; then
        break
    fi
    echo "Waiting for manager alerts directory ($i/12)..."
    sleep 10
done

# Inject real-world SSH brute force events via manager's logcollector
# These mirror actual sshd log formats from real CVE and MITRE ATT&CK incidents
INJECT_SCRIPT=$(mktemp /tmp/inject.XXXXXX.sh)
cat > "$INJECT_SCRIPT" << 'INJECTEOF'
#!/bin/bash
# Inject realistic security events into Wazuh via logger
# Format: real syslog entries that Wazuh decoders process

LOGFILE="/var/ossec/logs/agent.log"
ALERTS_LOG="/var/ossec/logs/alerts/alerts.log"

# Use logger to inject SSH brute force events (matches Wazuh rule 5710)
# These are modeled after real authentication failure patterns
declare -a SSH_IPS=("185.234.219.67" "45.33.32.156" "198.51.100.42" "203.0.113.100" "192.0.2.15")
declare -a USERS=("root" "admin" "ubuntu" "pi" "postgres" "redis" "ftp" "git" "deploy")

for i in {1..15}; do
    IP="${SSH_IPS[$((RANDOM % 5))]}"
    USER="${USERS[$((RANDOM % 9))]}"
    PORT=$((50000 + RANDOM % 15000))
    echo "$(date '+%b %d %H:%M:%S') wazuh-manager sshd[$$]: Invalid user ${USER} from ${IP} port ${PORT}"
done >> /var/log/syslog 2>/dev/null || true

# Inject sudo failure events (matches Wazuh rule 5401)
for i in {1..5}; do
    echo "$(date '+%b %d %H:%M:%S') wazuh-manager sudo:  operator : 3 incorrect password attempts ; TTY=pts/$i ; PWD=/home/operator ; USER=root ; COMMAND=/usr/bin/apt-get update"
done >> /var/log/auth.log 2>/dev/null || true

# Inject web server attack patterns (Apache access log format)
declare -a WEB_IPS=("91.196.219.35" "45.155.205.100" "185.220.101.45")
for i in {1..10}; do
    IP="${WEB_IPS[$((RANDOM % 3))]}"
    echo "${IP} - - [$(date '+%d/%b/%Y:%H:%M:%S %z')] \"GET /admin/config.php HTTP/1.1\" 404 196 \"-\" \"Mozilla/5.0 sqlmap/1.6.12\""
done >> /var/log/apache2/access.log 2>/dev/null || true

# Inject package management events (real audit-style)
echo "$(date '+%b %d %H:%M:%S') wazuh-manager dpkg: status installed openssh-server:amd64 1:8.9p1-3ubuntu0.6" >> /var/log/dpkg.log 2>/dev/null || true
echo "$(date '+%b %d %H:%M:%S') wazuh-manager dpkg: status installed linux-image-6.5.0-45-generic:amd64 6.5.0-45.45" >> /var/log/dpkg.log 2>/dev/null || true

echo "Log injection complete"
INJECTEOF

docker cp "$INJECT_SCRIPT" wazuh-wazuh.manager-1:/tmp/inject.sh 2>/dev/null && \
    docker exec wazuh-wazuh.manager-1 bash /tmp/inject.sh 2>/dev/null && \
    docker exec wazuh-wazuh.manager-1 rm /tmp/inject.sh 2>/dev/null && \
    echo "Security log data injected" || \
    echo "WARNING: Could not inject log data (non-fatal)"
rm -f "$INJECT_SCRIPT"

# Also install OSSEC test log generator to create additional real events
# Use logger command within manager container to feed events to wazuh's own syslog monitor
docker exec wazuh-wazuh.manager-1 bash -c '
for i in $(seq 1 10); do
    logger -p auth.warning "Failed password for invalid user scanner from 192.168.1.$(($RANDOM % 254 + 1)) port $(($RANDOM % 30000 + 20000)) ssh2"
done 2>/dev/null || true
' 2>/dev/null || true

sleep 5
echo "Real security data seeding complete"

# --- Step 22: Setup Firefox ---
echo "=== Step 22: Setting up Firefox ==="
FIREFOX_CMD="firefox"
[ -f /snap/bin/firefox ] && FIREFOX_CMD="/snap/bin/firefox"

# Launch Firefox to create profile
su - ga -c "DISPLAY=:1 ${FIREFOX_CMD} about:blank &" 2>/dev/null || true
sleep 15
pkill -f firefox 2>/dev/null || true
sleep 3

# Configure Firefox profile
PROFILE_DIR=""
for PROFILE_BASE in "/home/ga/snap/firefox/common/.mozilla/firefox" "/home/ga/.mozilla/firefox"; do
    if [ -d "$PROFILE_BASE" ]; then
        PROFILE_DIR=$(find "$PROFILE_BASE" -maxdepth 1 \( -name "*.default*" -o -name "*.default" \) -type d 2>/dev/null | head -1)
        [ -n "$PROFILE_DIR" ] && break
    fi
done

if [ -n "$PROFILE_DIR" ]; then
    cat > "${PROFILE_DIR}/user.js" << 'USERJS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "https://localhost");
user_pref("browser.startup.page", 1);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_override_url", "");
user_pref("startup.homepage_welcome_url", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.ssl_override_behavior", 2);
user_pref("security.cert_pinning.enforcement_level", 0);
user_pref("browser.xul.error_pages.expert_bad_cert", true);
USERJS
    chown ga:ga "${PROFILE_DIR}/user.js"
    echo "Firefox profile configured"
fi

# Launch Firefox at Wazuh dashboard and dismiss SSL warning
su - ga -c "DISPLAY=:1 ${FIREFOX_CMD} --new-instance https://localhost &" 2>/dev/null || true
sleep 15
su - ga -c "DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
sleep 3

# Dismiss SSL certificate warning by clicking Advanced > Accept Risk
# SSL warning page: Advanced button at (1318, 768), then scroll down, Accept Risk at (1252, 1005)
DISPLAY=:1 xdotool mousemove 1318 768 click 1 2>/dev/null || true
sleep 2
DISPLAY=:1 xdotool mousemove 960 600 2>/dev/null || true
# Scroll down to reveal Accept Risk link
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Page_Down 2>/dev/null || true
    sleep 0.5
done
DISPLAY=:1 xdotool mousemove 1252 1005 click 1 2>/dev/null || true
sleep 8
echo "SSL warning dismissal attempted"

echo "=== Wazuh SIEM environment setup complete ==="
echo "Dashboard: https://localhost"
echo "API: https://localhost:55000"
echo "Dashboard credentials: admin / SecretPassword"
echo "API User: wazuh-wui / MyS3cr37P450r.*-"
