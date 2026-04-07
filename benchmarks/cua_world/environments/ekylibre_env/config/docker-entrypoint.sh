#!/bin/bash
set -e

# Fix 1: Unset DATABASE_URL (overrides adapter: postgis when baked into image)
unset DATABASE_URL

# Fix 2: Switch apartment to postgis adapter (postgresql_adapter overrides PostGIS)
sed -i "s|require 'apartment/adapters/postgresql_adapter'|require 'apartment/adapters/postgis_adapter'|" /app/config/initializers/apartment.rb 2>/dev/null || true

# Fix 3: Disable eager_load (active_list gem crashes on boot inspecting associations)
sed -i 's/config.eager_load = true/config.eager_load = false/' /app/config/environments/production.rb 2>/dev/null || true

# Load .env file if present
if [ -f /app/.env ]; then
    set -a
    source /app/.env
    set +a
fi

export RAILS_ENV="${RAILS_ENV:-production}"

echo "Starting Ekylibre (RAILS_ENV=$RAILS_ENV)..."
cd /app

# Remove stale PID file
rm -f /app/tmp/pids/server.pid

exec "$@"
