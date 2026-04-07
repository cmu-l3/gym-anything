#!/bin/bash
# pre_start hook: Install Docker, pull OpenKM CE image, download real documents
# NOTE: set -e removed - many steps can fail gracefully

echo "=== Installing OpenKM dependencies (pre_start) ==="
export DEBIAN_FRONTEND=noninteractive

# ── 1. System packages ────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y \
    curl wget jq unzip \
    firefox \
    wmctrl xdotool x11-utils xclip \
    scrot imagemagick \
    python3-pip python3-requests \
    net-tools ca-certificates gnupg lsb-release \
    openjdk-11-jre-headless

# ── 2. Install Docker ─────────────────────────────────────────────────────────
echo "=== Installing Docker ==="
# Install docker.io separately — docker-compose-plugin may not exist in all repos
apt-get install -y docker.io
# Try to install compose plugin (optional, not needed for simple docker run)
apt-get install -y docker-compose-plugin 2>/dev/null \
    || apt-get install -y docker-compose-v2 2>/dev/null \
    || apt-get install -y docker-compose 2>/dev/null \
    || echo "WARNING: docker-compose not available, not needed for OpenKM"

systemctl enable docker 2>/dev/null || true
systemctl start docker 2>/dev/null || true
usermod -aG docker ga 2>/dev/null || true

# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon..."
for i in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready after ${i}s"
        break
    fi
    sleep 2
done

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon failed to start"
    echo "Attempting manual dockerd start..."
    dockerd &>/var/log/dockerd.log &
    sleep 10
    docker info >/dev/null 2>&1 && echo "Docker started via manual dockerd" || echo "ERROR: Docker still not available"
fi

# ── 3. Pull OpenKM CE Docker image ────────────────────────────────────────────
echo "=== Pulling OpenKM CE Docker image ==="
docker pull openkm/openkm-ce:latest || docker pull openkm/openkm-ce:6.3.12 || {
    echo "WARNING: Could not pull latest, trying older tag"
    docker pull openkm/openkm-ce:6.3.9
}

# ── 4. Download real public domain documents ──────────────────────────────────
echo "=== Downloading real documents ==="
DOCS_DIR="/home/ga/openkm_data"
mkdir -p "$DOCS_DIR"

# Download real documents from stable public URLs
# 1. NIST Cybersecurity Framework (real government publication)
wget -q --timeout=30 -O "$DOCS_DIR/NIST_Cybersecurity_Framework.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.04162018.pdf" 2>/dev/null || \
    echo "Note: NIST Cybersecurity Framework download failed, will retry in setup"

# 2. NIST SP 800-53 Rev 5 - Security and Privacy Controls (real NIST special publication)
# This is a separate document used for the upload task
wget -q --timeout=60 -O "$DOCS_DIR/NIST_SP_800-53_Security_Controls.pdf" \
    "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf" 2>/dev/null || \
    echo "Note: NIST SP 800-53 download failed, will use fallback"

# 3. US GAO report - Government Accountability Office (real report)
wget -q --timeout=30 -O "$DOCS_DIR/GAO_Federal_IT_Report.pdf" \
    "https://www.gao.gov/assets/gao-23-106782.pdf" 2>/dev/null || \
    echo "Note: GAO PDF download failed"

# 3. RFC 2616 - HTTP/1.1 specification (real technical standard)
wget -q --timeout=30 -O "$DOCS_DIR/RFC2616_HTTP_Specification.txt" \
    "https://www.rfc-editor.org/rfc/rfc2616.txt" 2>/dev/null || \
    echo "Note: RFC 2616 download failed"

# 4. RFC 7231 - HTTP/1.1 Semantics (real technical standard)
wget -q --timeout=30 -O "$DOCS_DIR/RFC7231_HTTP_Semantics.txt" \
    "https://www.rfc-editor.org/rfc/rfc7231.txt" 2>/dev/null || \
    echo "Note: RFC 7231 download failed"

# 5. WHO Constitution (real international legal document)
wget -q --timeout=30 -O "$DOCS_DIR/WHO_Constitution.pdf" \
    "https://apps.who.int/gb/bd/PDF/bd47/EN/constitution-en.pdf" 2>/dev/null || \
    echo "Note: WHO Constitution download failed"

# 6. Creative Commons legal code (real legal document)
wget -q --timeout=30 -O "$DOCS_DIR/Creative_Commons_BY_4.0_Legal_Code.txt" \
    "https://creativecommons.org/licenses/by/4.0/legalcode.txt" 2>/dev/null || \
    echo "Note: CC legal code download failed"

# 7. Project Gutenberg - The Art of War by Sun Tzu (real public domain book)
wget -q --timeout=30 -O "$DOCS_DIR/Art_of_War_Sun_Tzu.txt" \
    "https://www.gutenberg.org/cache/epub/132/pg132.txt" 2>/dev/null || \
    echo "Note: Art of War download failed"

# 8. Project Gutenberg - US Constitution text
wget -q --timeout=30 -O "$DOCS_DIR/US_Constitution.txt" \
    "https://www.gutenberg.org/cache/epub/5/pg5.txt" 2>/dev/null || \
    echo "Note: US Constitution download failed"

# 9. OWASP Testing Guide (real cybersecurity document)
wget -q --timeout=30 -O "$DOCS_DIR/OWASP_Testing_Guide_Summary.pdf" \
    "https://owasp.org/www-project-web-security-testing-guide/assets/archive/OWASP_Testing_Guide_v4.pdf" 2>/dev/null || \
    echo "Note: OWASP guide download failed"

# 10. EPA Environmental Justice report (real environmental document)
wget -q --timeout=30 -O "$DOCS_DIR/EPA_Environmental_Justice_Report.pdf" \
    "https://www.epa.gov/sites/default/files/2015-02/documents/exec_order_12898.pdf" 2>/dev/null || \
    echo "Note: EPA report download failed"

# Remove any empty/broken downloads so they don't confuse agents browsing the DMS
find "$DOCS_DIR" -type f -empty -delete

# Report what we downloaded
echo "=== Downloaded documents ==="
ls -la "$DOCS_DIR/"
DOC_COUNT=$(find "$DOCS_DIR" -type f -size +100c | wc -l)
echo "Successfully downloaded $DOC_COUNT documents"

chown -R ga:ga "$DOCS_DIR"

echo "=== OpenKM dependencies installation complete ==="
