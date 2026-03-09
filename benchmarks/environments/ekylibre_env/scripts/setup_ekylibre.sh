#!/bin/bash
# Ekylibre Setup Script (post_start hook)
# Waits for Docker image build to complete, then starts Ekylibre services,
# initializes the database with real farm demo data (GAEC JOULIN farm),
# and opens Firefox to the Ekylibre interface.

set -euo pipefail

echo "=== Setting up Ekylibre ==="

EKYLIBRE_DIR="/home/ga/ekylibre"
EKYLIBRE_URL="http://demo.ekylibre.farm:3000"
BUILD_MARKER="/tmp/ekylibre_build_complete.marker"
BUILD_ERROR_MARKER="/tmp/ekylibre_build_error.marker"
FIRST_RUN_DIR="/home/ga/first_run_data"

# ============================================================
# Helper: Wait for Docker build to complete (pattern #23)
# ============================================================
wait_for_build() {
    local timeout_sec=3600  # 60 minutes — Docker image build is slow
    local elapsed=0

    echo "Waiting for Ekylibre Docker image build to complete..."
    echo "(Build includes Ruby gems compilation — may take 30-50 minutes)"

    while [ "$elapsed" -lt "$timeout_sec" ]; do
        if [ -f "$BUILD_MARKER" ]; then
            echo "Build complete after ${elapsed}s."
            return 0
        fi

        if [ -f "$BUILD_ERROR_MARKER" ]; then
            echo "ERROR: Docker image build failed! Check /tmp/ekylibre_build.log"
            tail -50 /tmp/ekylibre_build.log 2>/dev/null || true
            return 1
        fi

        # Print progress every 2 minutes
        if [ $((elapsed % 120)) -eq 0 ] && [ "$elapsed" -gt 0 ]; then
            echo "  Still waiting... ${elapsed}s elapsed"
            # Show last line of build log
            tail -1 /tmp/ekylibre_build.log 2>/dev/null || true
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    echo "ERROR: Build timed out after ${timeout_sec}s"
    return 1
}

# ============================================================
# Helper: Wait for HTTP readiness
# ============================================================
wait_for_http() {
    local url="$1"
    local timeout_sec="${2:-300}"
    local elapsed=0

    echo "Waiting for HTTP readiness: $url"

    while [ "$elapsed" -lt "$timeout_sec" ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
        [ -z "$code" ] && code="000"

        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "303" ] || [ "$code" = "301" ]; then
            echo "HTTP ready after ${elapsed}s (HTTP $code)"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  waiting... ${elapsed}s (HTTP $code)"
        fi
    done

    echo "ERROR: Timeout waiting for $url"
    return 1
}

# ============================================================
# Helper: Run a rails command in the ekylibre container
# ============================================================
ekylibre_exec() {
    docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production $*"
}

# ============================================================
# 1. Wait for Docker image build to complete
# ============================================================
wait_for_build

echo ""
echo "=== Docker image ready. Starting Ekylibre services... ==="

# ============================================================
# 2. Ensure we have the .dockerhub credentials and re-authenticate
# ============================================================
if [ -f "$EKYLIBRE_DIR/.dockerhub_credentials" ]; then
    source "$EKYLIBRE_DIR/.dockerhub_credentials"
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

# ============================================================
# 3. Clone the first_run-demo data (real farm data)
#    From GAEC JOULIN farm (Charente-Maritime, France)
# ============================================================
echo "Cloning Ekylibre first_run demo data (real farm: GAEC JOULIN)..."
if [ ! -d "$FIRST_RUN_DIR" ]; then
    git clone --depth=1 https://github.com/ekylibre/first_run-demo.git "$FIRST_RUN_DIR" \
        || git clone https://github.com/ekylibre/first_run-demo.git "$FIRST_RUN_DIR" \
        || { echo "WARNING: Could not clone demo data; will use default first_run"; FIRST_RUN_DIR=""; }
fi

if [ -d "$FIRST_RUN_DIR" ]; then
    chown -R ga:ga "$FIRST_RUN_DIR" 2>/dev/null || true
    echo "Demo data ready at $FIRST_RUN_DIR"
fi

# ============================================================
# 4. Start Ekylibre containers via Docker Compose
# ============================================================
echo "Starting Ekylibre containers..."
cd "$EKYLIBRE_DIR"

# Update docker-compose.yml with the first_run data volume mount
if [ -n "$FIRST_RUN_DIR" ] && [ -d "${FIRST_RUN_DIR}/demo" ]; then
    # Replace placeholder with actual bind-mount path for first_run demo data
    sed -i "s|FIRST_RUN_DATA_PATH|${FIRST_RUN_DIR}/demo|g" docker-compose.yml
    echo "First run demo data bound at ${FIRST_RUN_DIR}/demo"
else
    # No demo data or demo subdirectory missing - remove the volume mount line
    sed -i '/FIRST_RUN_DATA_PATH/d' docker-compose.yml
    echo "No demo subdirectory found; skipping first_run volume mount"
fi

docker compose pull
docker compose up -d

echo "Container status:"
docker compose ps

# ============================================================
# 4b. Apply compatibility patches (idempotent)
#     These fix known issues with Ekylibre + modern system libs.
#     All patches check if already applied, so safe to re-run.
#     Also applied in Dockerfile for fresh image builds; applied
#     here as a fallback for pre-built images lacking the patches.
# ============================================================
echo ""
echo "=== Applying compatibility patches to ekylibre-web container ==="

# Wait for the container to be fully up before patching
echo "Waiting for ekylibre-web container to start..."
for i in $(seq 1 30); do
    if docker exec ekylibre-web true 2>/dev/null; then
        echo "Container ready after ${i}s"
        break
    fi
    sleep 2
done

# Patch 1: apartment.rb — add 'public' to persistent_schemas
# PostGIS functions (ST_AsEWKT, ST_MakeValid, ST_GeomFromEWKT, etc.) live in the 'public'
# schema. Apartment's SecuredSubdomain elevator sets search_path to 'tenant + persistent_schemas'.
# Without 'public', those functions are not found in tenant context → PG errors.
echo "  [1/5] Patching apartment.rb (add public to persistent_schemas)..."
docker exec ekylibre-web bash -c "
    if grep -q 'postgis lexicon public' /app/config/initializers/apartment.rb 2>/dev/null; then
        echo '    already patched'
    elif grep -q 'postgis lexicon\]' /app/config/initializers/apartment.rb 2>/dev/null; then
        sed -i 's/persistent_schemas = %w\[postgis lexicon\]/persistent_schemas = %w[postgis lexicon public]/' \
            /app/config/initializers/apartment.rb
        echo '    patched: public added to persistent_schemas'
    else
        echo '    WARNING: pattern not found (different Ekylibre version?)'
    fi
" || echo "WARNING: apartment.rb patch failed (continuing)"

# Patch 2: shape_corrector.rb — nil guard in postgis_geometries_extraction
# When geometry_type is :any (not in the int_type hash), int_type is nil.
# ST_CollectionExtract(geom, ) with a nil int_type generates invalid SQL.
# Fix: return early if int_type.nil?
echo "  [2/5] Patching shape_corrector.rb (nil guard for int_type)..."
docker exec -i ekylibre-web ruby << 'RUBYEOF'
f = '/app/app/services/shape_corrector.rb'
c = File.read(f) rescue nil
unless c
  puts '    not found, skipping'
  exit 0
end
if c.include?('int_type.nil?')
  puts '    already patched'
  exit 0
end
# Try regex sub first: insert nil guard after the }[geometry_type] line
nc = c.sub(/^(\s+)\}\[geometry_type\]\n/, "\\1}[geometry_type]\n\\1return None() if int_type.nil?\n")
if nc != c
  File.write(f, nc)
  puts '    patched: nil guard added after }[geometry_type]'
else
  # Fallback: find the line by index and insert after it
  lines = c.lines
  idx = lines.rindex { |l| l =~ /\}\[geometry_type\]/ }
  if idx
    ind = lines[idx][/^\s*/]
    lines.insert(idx + 1, "#{ind}return None() if int_type.nil?\n")
    File.write(f, lines.join)
    puts '    patched: nil guard inserted (fallback method)'
  else
    puts '    WARNING: pattern not found, skipping'
  end
end
RUBYEOF

# Patch 3: freezer.rb — fix pdf_format? to use magic bytes
# The paperclip-document gem's pdf_format? uses a readline + regex approach.
# The regex /\A\%PDF-\d+(\.\d+)?$/ fails on PDFs with Windows \r\n line endings
# ($ matches before \n, not before \r). This causes valid PDFs to be treated as
# non-PDFs, triggering Docsplit.extract_pdf which requires LibreOffice (absent).
echo "  [3/5] Patching freezer.rb (pdf_format? magic bytes)..."
docker exec -i ekylibre-web ruby << 'RUBYEOF'
files = Dir.glob('/usr/local/bundle/gems/paperclip-document-*/lib/paperclip/document/processors/freezer.rb')
if files.empty?
  puts '    freezer.rb not found, skipping'
  exit 0
end
f = files.first
c = File.read(f)
if c.include?("start_with?('%PDF-')")
  puts "    #{f}: already patched"
  exit 0
end
nc = c.sub(
  /File\.open\(file_path, ['"]rb['"], &:readline\)\.to_s =~ \/[^\/]+\//,
  "File.open(file_path, 'rb') { |f| f.read(8) }.to_s.start_with?('%PDF-')"
)
if nc != c
  File.write(f, nc)
  puts "    patched #{f}"
else
  puts "    WARNING: readline pattern not found in #{f}"
end
RUBYEOF

# Patch 4: Create /usr/share/proj/epsg (PROJ 7.x removed this file)
# rgeo-proj4 (2.0.1) uses Proj4Data which opens /usr/share/proj/epsg by name.
# PROJ 7.x replaced the text-format epsg file with proj.db (SQLite) only.
# The telepac loader transforms coordinates from EPSG:2154 (Lambert-93) to WGS84.
echo "  [4/5] Creating /usr/share/proj/epsg (PROJ4 CRS definitions)..."
if docker exec ekylibre-web test -f /usr/share/proj/epsg 2>/dev/null; then
    echo "    already exists"
else
    docker exec ekylibre-web mkdir -p /usr/share/proj
    cat > /tmp/proj_epsg_setup << 'EPSGEOF'
# PROJ4 EPSG definition file - Generated for Ekylibre
# Includes common French and worldwide projections
# Format: <EPSG_CODE> +proj=... <> # name

# Geographic CRS
<4326> +proj=longlat +datum=WGS84 +no_defs <> # WGS 84
<4258> +proj=longlat +ellps=GRS80 +no_defs <> # ETRS89
<4171> +proj=longlat +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +no_defs <> # RGF93
<4230> +proj=longlat +ellps=intl +no_defs <> # ED50
<4269> +proj=longlat +datum=NAD83 +no_defs <> # NAD83
<4267> +proj=longlat +datum=NAD27 +no_defs <> # NAD27

# Web Mercator
<3857> +proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +wktext +no_defs <> # WGS 84 / Pseudo-Mercator
<900913> +proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +wktext +no_defs <> # Google Maps Global Mercator

# French national projections
<2154> +proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # RGF93v1 / Lambert-93
<27561> +proj=lcc +lat_1=49.5 +lat_0=49.5 +lon_0=0 +k_0=0.999877341 +x_0=600000 +y_0=200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / Lambert I Nord
<27562> +proj=lcc +lat_1=46.8 +lat_0=46.8 +lon_0=0 +k_0=0.99987742 +x_0=600000 +y_0=2200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / Lambert II Centre
<27563> +proj=lcc +lat_1=44.1 +lat_0=44.1 +lon_0=0 +k_0=0.999877499 +x_0=600000 +y_0=3200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / Lambert III Sud
<27564> +proj=lcc +lat_1=42.165 +lat_0=42.165 +lon_0=0 +k_0=0.99994471 +x_0=234.358 +y_0=4185861.369 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / Lambert IV Corse
<27571> +proj=lcc +lat_1=49.5 +lat_0=49.5 +lon_0=0 +k_0=0.999877341 +x_0=600000 +y_0=1200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / France Nord
<27572> +proj=lcc +lat_1=46.8 +lat_0=46.8 +lon_0=0 +k_0=0.99987742 +x_0=600000 +y_0=2200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / France Centre
<27573> +proj=lcc +lat_1=44.1 +lat_0=44.1 +lon_0=0 +k_0=0.999877499 +x_0=600000 +y_0=3200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / France Sud
<27574> +proj=lcc +lat_1=42.165 +lat_0=42.165 +lon_0=0 +k_0=0.99994471 +x_0=234.358 +y_0=185861.369 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs <> # NTF Paris / France Corse

# French overseas
<2975> +proj=utm +zone=40 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # RGR92 / UTM zone 40S - Reunion
<2980> +proj=utm +zone=38 +south +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # Mayotte UTM zone 38S
<2970> +proj=utm +zone=20 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # RRAF 1991 / UTM zone 20N
<2971> +proj=utm +zone=22 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # RGFG95 / UTM zone 22N - Guyane

# UTM zones - WGS84
<32630> +proj=utm +zone=30 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 30N
<32631> +proj=utm +zone=31 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 31N
<32632> +proj=utm +zone=32 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 32N
<32633> +proj=utm +zone=33 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 33N
<32634> +proj=utm +zone=34 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 34N
<32635> +proj=utm +zone=35 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 35N
<32636> +proj=utm +zone=36 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 36N
<32637> +proj=utm +zone=37 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 37N
<32640> +proj=utm +zone=40 +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 40N
<32728> +proj=utm +zone=28 +south +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 28S
<32740> +proj=utm +zone=40 +south +datum=WGS84 +units=m +no_defs <> # WGS 84 / UTM zone 40S

# European projections
<25830> +proj=utm +zone=30 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # ETRS89 / UTM zone 30N
<25831> +proj=utm +zone=31 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # ETRS89 / UTM zone 31N
<25832> +proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # ETRS89 / UTM zone 32N
<25833> +proj=utm +zone=33 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # ETRS89 / UTM zone 33N
<2192> +proj=lcc +lat_1=46.8 +lat_0=46.8 +lon_0=3 +k_0=0.99987742 +x_0=600000 +y_0=2200000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs <> # ED50 / France EuroLambert
<27700> +proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +ellps=airy +towgs84=446.448,-125.157,542.06,0.15,0.247,0.842,-20.489 +units=m +no_defs <> # OSGB 1936 / British National Grid
<3003> +proj=tmerc +lat_0=0 +lon_0=9 +k=0.9996 +x_0=1500000 +y_0=0 +ellps=intl +towgs84=-104.1,-49.1,-9.9,0.971,-2.917,0.714,-11.68 +units=m +no_defs <> # Monte Mario / Italy zone 1
<3004> +proj=tmerc +lat_0=0 +lon_0=15 +k=0.9996 +x_0=2520000 +y_0=0 +ellps=intl +towgs84=-104.1,-49.1,-9.9,0.971,-2.917,0.714,-11.68 +units=m +no_defs <> # Monte Mario / Italy zone 2
<31467> +proj=tmerc +lat_0=0 +lon_0=9 +k=1 +x_0=3500000 +y_0=0 +ellps=bessel +towgs84=598.1,73.7,418.2,0.202,0.045,-2.455,6.7 +units=m +no_defs <> # DHDN / Gauss-Kruger zone 3
<31468> +proj=tmerc +lat_0=0 +lon_0=12 +k=1 +x_0=4500000 +y_0=0 +ellps=bessel +towgs84=598.1,73.7,418.2,0.202,0.045,-2.455,6.7 +units=m +no_defs <> # DHDN / Gauss-Kruger zone 4
EPSGEOF
    docker cp /tmp/proj_epsg_setup ekylibre-web:/usr/share/proj/epsg
    rm -f /tmp/proj_epsg_setup
    echo "    /usr/share/proj/epsg created"
fi

# Patch 5: Install poppler-utils and ghostscript (PDF processing pipeline)
# poppler-utils provides pdftotext (used by Docsplit for text extraction from PDFs)
# ghostscript provides gs (used by GraphicsMagick to convert PDF pages to images)
# Both are needed for the paperclip attachment processing pipeline in first_run.
echo "  [5/5] Checking PDF processing tools (poppler-utils, ghostscript)..."
docker exec ekylibre-web bash -c "
    NEED_INSTALL=false
    which pdftotext >/dev/null 2>&1 || NEED_INSTALL=true
    which gs >/dev/null 2>&1 || NEED_INSTALL=true
    if [ \"\$NEED_INSTALL\" = \"true\" ]; then
        echo '    installing poppler-utils and ghostscript...'
        apt-get update -qq 2>/dev/null
        apt-get install -y --no-install-recommends poppler-utils ghostscript 2>/dev/null \
            && echo '    installed successfully' \
            || echo '    WARNING: install failed (PDF processing may be limited)'
    else
        echo '    already installed'
    fi
" || echo "WARNING: Could not check/install PDF tools (non-critical)"

echo "=== Compatibility patches complete ==="
echo ""

# ============================================================
# 5. Wait for the database to be healthy
# ============================================================
echo "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 60); do
    if docker exec ekylibre-db pg_isready -U ekylibre 2>/dev/null; then
        echo "PostgreSQL ready after ${i}s"
        break
    fi
    sleep 2
done

# ============================================================
# 6. Initialize the Ekylibre database
# ============================================================
echo "Creating and migrating Ekylibre database..."
docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production bundle exec rake db:create" \
    || echo "WARNING: db:create may have failed (possibly already exists)"

sleep 5

echo "Running database migrations..."
docker exec ekylibre-web bash -c "cd /app && RAILS_ENV=production bundle exec rake db:migrate" \
    2>&1 | tail -20

# ============================================================
# 7. Generate GPG key in the container (required by Ekylibre)
# ============================================================
echo "Setting up GPG key for Ekylibre..."
docker exec ekylibre-web bash -c "
    if ! gpg --list-keys ekylibre@example.org 2>/dev/null | grep -q ekylibre; then
        echo '%no-protection
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Ekylibre Demo
Name-Email: ekylibre@example.org
Expire-Date: 0
%commit' | gpg --batch --gen-key
    fi
    echo 'GPG key ready'
" 2>/dev/null || echo "WARNING: GPG setup may have issues (non-critical)"

# ============================================================
# 8. Run first_run to load GAEC JOULIN demo farm data
#    This creates the 'demo' tenant with a real French farm dataset
# ============================================================
echo "Loading GAEC JOULIN farm demo data (bin/rake first_run)..."
echo "This may take several minutes..."

if [ -d "/home/ga/first_run_data/demo" ]; then
    # Use the real farm demo data (GAEC JOULIN farm from Charente-Maritime)
    # Parameters: folder=demo (subdirectory in db/first_runs/), name=demo (tenant name)
    docker exec ekylibre-web bash -c "
        cd /app
        echo 'Contents of db/first_runs/:'
        ls db/first_runs/ 2>/dev/null || echo '  (empty or missing)'
        RAILS_ENV=production folder=demo name=demo verbose=true bundle exec rake first_run
    " 2>&1 | tail -80 || echo "WARNING: first_run with demo folder may have failed; trying default..."

    # Verify the demo tenant was created (Ekylibre creates per-tenant databases)
    DEMO_CHECK=$(docker exec ekylibre-db psql -U ekylibre -lqt 2>/dev/null | grep "demo" | wc -l)
    if [ "$DEMO_CHECK" -lt 1 ]; then
        echo "Demo tenant not found; trying default first_run..."
        docker exec ekylibre-web bash -c "
            cd /app
            RAILS_ENV=production bundle exec rake first_run:default VERBOSE=1
        " 2>&1 | tail -30 || echo "WARNING: Default first_run also failed"
    fi
else
    # No demo data available - use built-in default first_run
    echo "Demo data not available; loading default tenant..."
    docker exec ekylibre-web bash -c "
        cd /app
        RAILS_ENV=production bundle exec rake first_run:default VERBOSE=1
    " 2>&1 | tail -30 || echo "WARNING: first_run failed; app may have limited data"
fi

echo "Database initialization complete."

# ============================================================
# 9. Configure /etc/hosts for Ekylibre tenant domains
#    - demo.ekylibre.farm is from the GAEC JOULIN manifest.yml
#    - demo.ekylibre.local and default.ekylibre.local as fallbacks
# ============================================================
echo "Configuring /etc/hosts for Ekylibre..."
# Remove any existing entries
sed -i '/ekylibre\.farm/d' /etc/hosts
sed -i '/ekylibre\.local/d' /etc/hosts
sed -i '/ekylibre\.lan/d' /etc/hosts

# Add entries for all possible tenant domain patterns
echo "127.0.0.1 demo.ekylibre.farm" >> /etc/hosts
echo "127.0.0.1 demo.ekylibre.local" >> /etc/hosts
echo "127.0.0.1 demo.ekylibre.lan" >> /etc/hosts
echo "127.0.0.1 default.ekylibre.local" >> /etc/hosts
echo "127.0.0.1 default.ekylibre.lan" >> /etc/hosts

echo "Hosts configured:"
grep "ekylibre" /etc/hosts

# ============================================================
# 10. Wait for Ekylibre web interface to be ready
# ============================================================
echo "Waiting for Ekylibre web interface..."

# Give Rails server a few extra seconds to fully start after first_run
sleep 10

EKYLIBRE_READY=false
# The GAEC JOULIN demo manifest uses demo.ekylibre.farm as the host
for URL in "http://demo.ekylibre.farm:3000" "http://demo.ekylibre.local:3000" "http://demo.ekylibre.lan:3000" "http://default.ekylibre.lan:3000" "http://localhost:3000"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
        EKYLIBRE_URL="$URL"
        EKYLIBRE_READY=true
        echo "Ekylibre accessible at $URL"
        break
    fi
done

if [ "$EKYLIBRE_READY" = "false" ]; then
    # Try polling with timeout
    for i in $(seq 1 60); do
        for URL in "http://demo.ekylibre.farm:3000" "http://demo.ekylibre.local:3000" "http://localhost:3000"; do
            code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
            if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
                EKYLIBRE_URL="$URL"
                EKYLIBRE_READY=true
                echo "Ekylibre accessible at $URL after ${i}x5s"
                break 2
            fi
        done
        sleep 5
    done
fi

# ============================================================
# 11. Configure Firefox profile
# ============================================================
echo "Setting up Firefox profile..."

SNAP_FF_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
STD_FF_DIR="/home/ga/.mozilla/firefox"

# Detect which Firefox type is installed
if [ -d "/snap/firefox" ] || snap list firefox 2>/dev/null | grep -q firefox; then
    # Snap Firefox
    FF_PROFILE_ROOT="$SNAP_FF_DIR"
    mkdir -p "$FF_PROFILE_ROOT/ekylibre.profile"
    PROFILE_DIR="$FF_PROFILE_ROOT/ekylibre.profile"
    cat > "$FF_PROFILE_ROOT/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=ekylibre
IsRelative=1
Path=ekylibre.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
else
    # Standard Firefox
    FF_PROFILE_ROOT="$STD_FF_DIR"
    mkdir -p "$FF_PROFILE_ROOT/ekylibre.profile"
    PROFILE_DIR="$FF_PROFILE_ROOT/ekylibre.profile"
    cat > "$FF_PROFILE_ROOT/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=ekylibre
IsRelative=1
Path=ekylibre.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
fi

cat > "$PROFILE_DIR/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
USERJS

chown -R ga:ga "$FF_PROFILE_ROOT" 2>/dev/null || true

# ============================================================
# 12. Launch Firefox warm-up to load Ekylibre
# ============================================================
echo "Launching Firefox with Ekylibre URL: $EKYLIBRE_URL..."

pkill -f firefox 2>/dev/null || true
sleep 2

# Remove lock files
find "$FF_PROFILE_ROOT" -name ".parentlock" -delete 2>/dev/null || true
find "$FF_PROFILE_ROOT" -name "lock" -type l -delete 2>/dev/null || true

if [ -d "/snap/firefox" ] || snap list firefox 2>/dev/null | grep -q firefox; then
    # Snap Firefox
    su - ga -c "
        rm -f '$SNAP_FF_DIR/ekylibre.profile/.parentlock' \
              '$SNAP_FF_DIR/ekylibre.profile/lock' 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        setsid firefox --new-instance \
        -profile '$SNAP_FF_DIR/ekylibre.profile' \
        '$EKYLIBRE_URL' > /tmp/firefox_ekylibre.log 2>&1 &
    "
else
    # Standard Firefox
    su - ga -c "
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        XDG_RUNTIME_DIR=/run/user/1000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
        setsid firefox \
        -profile '$STD_FF_DIR/ekylibre.profile' \
        '$EKYLIBRE_URL' > /tmp/firefox_ekylibre.log 2>&1 &
    "
fi

# Wait for Firefox window to appear (up to 30s)
FF_STARTED=false
for i in $(seq 1 30); do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|ekylibre"; then
        FF_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FF_STARTED" = "true" ]; then
    sleep 2
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Firefox maximized."
else
    echo "WARNING: Firefox window not detected within 30s; continuing anyway"
fi

# ============================================================
# Done
# ============================================================
echo ""
echo "=== Ekylibre setup complete ==="
echo "URL: $EKYLIBRE_URL"
echo "Admin login: admin@ekylibre.org / 12345678"
echo "Farm data: GAEC JOULIN (real French farm from Charente-Maritime)"
echo ""
docker compose ps 2>/dev/null || true
