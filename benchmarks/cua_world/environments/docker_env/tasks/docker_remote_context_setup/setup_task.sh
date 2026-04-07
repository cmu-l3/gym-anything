#!/bin/bash
set -e
echo "=== Setting up Docker Remote Context Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for local docker to be ready
wait_for_docker

# Clean up previous run artifacts
echo "Cleaning up previous state..."
docker rm -f prod-node 2>/dev/null || true
docker network rm prod-net 2>/dev/null || true
rm -rf /home/ga/credentials
rm -rf /tmp/certs
docker context rm prod 2>/dev/null || true

# Create the network
echo "Creating network 'prod-net'..."
docker network create prod-net

# Generate TLS Certificates
echo "Generating TLS certificates..."
mkdir -p /tmp/certs
cd /tmp/certs

# 1. CA
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem -subj "/CN=AcmeCorp Root CA"

# 2. Server Certs (for prod-node)
openssl genrsa -out server-key.pem 4096
openssl req -subj "/CN=prod-node" -sha256 -new -key server-key.pem -out server.csr
# Important: IP SANs will be handled by knowing the subnet or just using the hostname 'prod-node'
# We will use the container hostname 'prod-node' and 'localhost' for SANs
echo "subjectAltName = DNS:prod-node,IP:127.0.0.1" > extfile.cnf
openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -extfile extfile.cnf

# 3. Client Certs (for the agent)
openssl genrsa -out key.pem 4096
openssl req -subj "/CN=client" -new -key key.pem -out client.csr
echo "extendedKeyUsage = clientAuth" > extfile-client.cnf
openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out cert.pem -extfile extfile-client.cnf

chmod 0400 ca-key.pem key.pem server-key.pem
chmod 0444 ca.pem server-cert.pem cert.pem

# Start the Remote Docker Daemon (dind)
echo "Starting remote Docker daemon (prod-node)..."
# We mount the certs into the container
docker run -d --privileged --name prod-node \
  --network prod-net \
  --hostname prod-node \
  -v /tmp/certs:/certs:ro \
  -e DOCKER_TLS_CERTDIR="/certs" \
  docker:dind \
  dockerd \
  --host=tcp://0.0.0.0:2376 \
  --tlsverify \
  --tlscacert=/certs/ca.pem \
  --tlscert=/certs/server-cert.pem \
  --tlskey=/certs/server-key.pem

# Wait for prod-node to be healthy
echo "Waiting for remote daemon to initialize..."
sleep 5
for i in {1..20}; do
    if docker exec prod-node docker info >/dev/null 2>&1; then
        echo "Remote daemon is ready."
        break
    fi
    sleep 2
done

# Prepare credentials for the agent
echo "Preparing agent credentials..."
mkdir -p /home/ga/credentials
cp ca.pem /home/ga/credentials/
cp cert.pem /home/ga/credentials/
cp key.pem /home/ga/credentials/
chown -R ga:ga /home/ga/credentials
chmod 600 /home/ga/credentials/key.pem

# Get the IP of the remote node for verification later
REMOTE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' prod-node)
echo "$REMOTE_IP" > /tmp/remote_ip.txt
echo "Remote Node IP: $REMOTE_IP"

# Record start time
date +%s > /tmp/task_start_time.txt

# Create initial screenshot
take_screenshot /tmp/task_initial.png

# Open terminal for agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"Docker Remote Context Setup Task\"; echo \"Credentials located in ~/credentials/\"; echo \"Remote node is running on network prod-net\"; exec bash'" > /tmp/terminal.log 2>&1 &

echo "=== Setup Complete ==="