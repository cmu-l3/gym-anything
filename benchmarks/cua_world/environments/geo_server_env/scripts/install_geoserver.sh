#!/bin/bash
set -e

echo "=== Installing GeoServer Environment ==="

export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Docker from official repository
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker GPG key and repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || {
    echo "Docker CE install failed, trying docker.io..."
    apt-get install -y docker.io docker-compose
}

# Create docker-compose wrapper if needed
if ! command -v docker-compose &>/dev/null; then
    if docker compose version &>/dev/null; then
        cat > /usr/local/bin/docker-compose << 'DCEOF'
#!/bin/bash
exec docker compose "$@"
DCEOF
        chmod +x /usr/local/bin/docker-compose
    else
        curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
fi

# Enable Docker service
systemctl enable docker
systemctl start docker
usermod -aG docker ga

# Install GUI tools and utilities
apt-get install -y \
    firefox \
    wmctrl xdotool x11-utils xclip \
    imagemagick scrot \
    jq curl wget unzip \
    python3-pip python3-psycopg2

# Pre-pull Docker images to avoid timeout during post_start
echo "=== Pre-pulling Docker images ==="
docker pull kartoza/geoserver:2.25.2 || echo "WARNING: Failed to pull GeoServer image"
docker pull kartoza/postgis:15-3.3 || echo "WARNING: Failed to pull PostGIS image"

# Download Natural Earth data (real geospatial data)
echo "=== Downloading Natural Earth data ==="
DATA_DIR="/home/ga/natural_earth"
mkdir -p "$DATA_DIR"

# Download 1:110m cultural data (countries, populated places) — small, fast
wget -q "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip" -O /tmp/ne_110m_countries.zip || \
    wget -q "https://naturalearth.s3.amazonaws.com/110m_cultural/ne_110m_admin_0_countries.zip" -O /tmp/ne_110m_countries.zip || \
    echo "WARNING: Failed to download countries shapefile"

wget -q "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places.zip" -O /tmp/ne_110m_places.zip || \
    wget -q "https://naturalearth.s3.amazonaws.com/110m_cultural/ne_110m_populated_places.zip" -O /tmp/ne_110m_places.zip || \
    echo "WARNING: Failed to download populated places shapefile"

# Download 1:110m physical data (rivers, lakes)
wget -q "https://naciscdn.org/naturalearth/110m/physical/ne_110m_rivers_lake_centerlines.zip" -O /tmp/ne_110m_rivers.zip || \
    wget -q "https://naturalearth.s3.amazonaws.com/110m_physical/ne_110m_rivers_lake_centerlines.zip" -O /tmp/ne_110m_rivers.zip || \
    echo "WARNING: Failed to download rivers shapefile"

wget -q "https://naciscdn.org/naturalearth/110m/physical/ne_110m_lakes.zip" -O /tmp/ne_110m_lakes.zip || \
    wget -q "https://naturalearth.s3.amazonaws.com/110m_physical/ne_110m_lakes.zip" -O /tmp/ne_110m_lakes.zip || \
    echo "WARNING: Failed to download lakes shapefile"

# Extract shapefiles
for zipfile in /tmp/ne_110m_*.zip; do
    if [ -f "$zipfile" ]; then
        unzip -o "$zipfile" -d "$DATA_DIR/" || echo "WARNING: Failed to extract $zipfile"
    fi
done

chown -R ga:ga "$DATA_DIR"
echo "Natural Earth data files:"
ls -la "$DATA_DIR/"

echo "=== GeoServer environment installation complete ==="
