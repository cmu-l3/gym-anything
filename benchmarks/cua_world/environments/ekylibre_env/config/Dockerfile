# Ekylibre Farm Management System Docker Image
# Based on Ruby 2.7.8 (Ekylibre requires >= 2.6.6, < 3.0.0)
# Built without development/test gems (no libqtwebkit dependency needed)

FROM ruby:2.7.8-slim

# Install system dependencies
# Note: No libqtwebkit-dev needed (that's only for test/dev gems)
RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
    apt-get update -qq && \
    apt-get install -yq --no-install-recommends \
        build-essential \
        git \
        curl \
        wget \
        gnupg2 \
        libpq-dev \
        postgresql-client \
        imagemagick \
        graphicsmagick \
        libproj-dev \
        libgeos-dev \
        libgeos++-dev \
        libffi-dev \
        libicu-dev \
        libxml2-dev \
        libxslt1-dev \
        libyaml-dev \
        libssl-dev \
        libreadline-dev \
        zlib1g-dev \
        nodejs \
        npm \
        redis-tools \
        pdftk \
        tesseract-ocr \
        default-jdk \
        shared-mime-info \
        poppler-utils \
        ghostscript \
        && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create PROJ4 epsg file (PROJ 7.x removed this text-format file but rgeo-proj4 gem still opens it)
# The rgeo-proj4 Proj4Data class reads /usr/share/proj/epsg for CRS lookups (e.g., EPSG:2154 Lambert-93)
RUN mkdir -p /usr/share/proj
COPY proj_epsg.txt /usr/share/proj/epsg

# Clone Ekylibre (main branch, the stable open-source FMIS)
RUN git clone --depth=1 https://github.com/ekylibre/ekylibre.git /app

# --- Compatibility patch 1: apartment.rb ---
# Add 'public' to persistent_schemas so PostGIS functions (in 'public' schema) are accessible
# when Apartment switches to a tenant. Without this, search_path = 'demo,postgis,lexicon'
# (no 'public'), and ST_AsEWKT / ST_MakeValid calls fail with "function does not exist".
RUN if grep -q 'postgis lexicon\]' /app/config/initializers/apartment.rb 2>/dev/null; then \
        sed -i 's/persistent_schemas = %w\[postgis lexicon\]/persistent_schemas = %w[postgis lexicon public]/' \
            /app/config/initializers/apartment.rb && \
        echo "Patched apartment.rb: public added to persistent_schemas"; \
    else \
        echo "apartment.rb: pattern not found (may be different version, check manually)"; \
    fi

# --- Compatibility patch 1b: apartment.rb adapter ---
# Switch Apartment from postgresql_adapter to postgis_adapter so that
# ActiveRecord uses PostGIS::TableDefinition (which has st_point, st_polygon, etc.)
# instead of the standard PostgreSQL::TableDefinition.
RUN sed -i "s|require 'apartment/adapters/postgresql_adapter'|require 'apartment/adapters/postgis_adapter'|" \
        /app/config/initializers/apartment.rb && \
    echo "Patched apartment.rb: switched to postgis adapter"

# --- Compatibility patch 2: shape_corrector.rb ---
# Add nil guard after }[geometry_type] hash lookup in postgis_geometries_extraction.
# Without it, ST_CollectionExtract(geom, ) with empty int_type causes a SQL syntax error
# when geometry_type is not in the lookup hash (e.g., :any).
RUN ruby -e ' \
  f = "/app/app/services/shape_corrector.rb"; \
  c = File.read(f) rescue nil; \
  unless c; puts "shape_corrector.rb not found, skipping"; exit 0; end; \
  if c.include?("int_type.nil?"); puts "shape_corrector.rb already patched"; exit 0; end; \
  nc = c.sub(/^(\s+)\}\[geometry_type\]\n/, "\\1}[geometry_type]\n\\1return None() if int_type.nil?\n"); \
  if nc != c; File.write(f, nc); puts "Patched shape_corrector.rb: nil guard added"; \
  else; \
    lines = c.lines; \
    idx = lines.rindex { |l| l =~ /\}\[geometry_type\]/ }; \
    if idx; \
      ind = lines[idx][/^\s*/]; \
      lines.insert(idx + 1, "#{ind}return None() if int_type.nil?\n"); \
      File.write(f, lines.join); \
      puts "Patched shape_corrector.rb (line insert fallback)"; \
    else; \
      warn "shape_corrector.rb: pattern not found, skipping"; \
    end; \
  end \
'

# Install bundler (compatible with Gemfile.lock)
# Pin rubygems to 3.4.x — rubygems 4.x requires Ruby >= 3.2.0, but we use Ruby 2.7.8
RUN gem update --system 3.4.22 && gem install bundler -v '~> 2.4'

# Configure bundler to skip development and test gems
# This avoids the libqtwebkit-dev dependency (capybara-webkit is test-only)
RUN bundle config set --local without 'development test'

# mimemagic 0.3.x requires freedesktop.org.xml (provided by shared-mime-info)
ENV FREEDESKTOP_MIME_TYPES_PATH=/usr/share/mime/packages/freedesktop.org.xml

# rjb requires JAVA_HOME to be set (for the Ruby-Java Bridge native extension)
ENV JAVA_HOME=/usr/lib/jvm/default-java

# Install gems (this is the slow step — ~20-30 minutes)
RUN bundle install --jobs 4 --retry 3

# --- Compatibility patch 3: freezer.rb ---
# Fix pdf_format? to use magic bytes instead of readline+regex.
# The regex /\A\%PDF-\d+(\.\d+)?$/ fails on PDFs with Windows \r\n line endings because
# $ matches before \n but not before \r. When pdf_format? returns false, Docsplit tries
# to convert a non-PDF (actually a valid PDF), which requires LibreOffice (not installed).
RUN ruby -e ' \
  files = Dir.glob("/usr/local/bundle/gems/paperclip-document-*/lib/paperclip/document/processors/freezer.rb"); \
  if files.empty?; puts "freezer.rb not found, skipping"; exit 0; end; \
  f = files.first; \
  c = File.read(f); \
  if c.include?("start_with?(\"%PDF-\")"); puts "#{f}: already patched"; exit 0; end; \
  nc = c.sub( \
    /File\.open\(file_path, ['"'"'"]rb['"'"'"], &:readline\)\.to_s =~ \/[^\/]+\//, \
    "File.open(file_path, '"'"'rb'"'"') { |f| f.read(8) }.to_s.start_with?(\"%PDF-\")" \
  ); \
  if nc != c; File.write(f, nc); puts "Patched #{f}"; \
  else; warn "#{f}: pattern not found, skipping"; end \
'

# Install JavaScript packages
RUN yarn install --frozen-lockfile || yarn install || echo "WARNING: yarn install had issues"

# Create default .env for asset precompilation (overridden at runtime)
RUN cat > /app/.env << 'ENVEOF'
DEVISE_SECRET_KEY=cbfa6828e7f6f052484db145404f9b00bf3ba234fedcbb1db9c79b85c8f0291b
SECRET_KEY_BASE=c4b280c6d3e57376151af41fbc69a5609a89c851b92da6c41216b7ed38323dde
HOST_DOMAIN_NAME=ekylibre.local
GPG_EMAIL=ekylibre@example.org
MAILER_SENDER=noreply@ekylibre.local
ELASTIC_APM_ACTIVE=false
ENVEOF

# Precompile assets for production
RUN RAILS_ENV=production \
    SECRET_KEY_BASE=c4b280c6d3e57376151af41fbc69a5609a89c851b92da6c41216b7ed38323dde \
    bundle exec rake assets:precompile \
    || echo "WARNING: asset precompile had errors (may be OK)"

# Create first_runs directory (will be volume-mounted with demo data)
RUN mkdir -p /app/db/first_runs

# Copy entrypoint script (COPY is more reliable than heredoc in RUN)
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000", "-e", "production"]
