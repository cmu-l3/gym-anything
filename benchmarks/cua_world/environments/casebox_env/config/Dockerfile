FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

# Install core packages
RUN apt-get update && apt-get install -y \
    apache2 libapache2-mod-php7.2 \
    php7.2 php7.2-mysql php7.2-mbstring php7.2-xml php7.2-curl \
    php7.2-bcmath php7.2-json php7.2-tidy php7.2-cli \
    php7.2-common php-imagick php7.2-intl php7.2-zip php7.2-soap \
    openjdk-8-jdk-headless \
    git wget curl zip unzip lsof \
    imagemagick supervisor mysql-client \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install Solr 6.0.1 from Apache archive
RUN cd /tmp && \
    wget -q http://archive.apache.org/dist/lucene/solr/6.0.1/solr-6.0.1.tgz && \
    tar xzf solr-6.0.1.tgz solr-6.0.1/bin/install_solr_service.sh --strip-components=2 && \
    bash install_solr_service.sh solr-6.0.1.tgz -n && \
    rm -f solr-6.0.1.tgz install_solr_service.sh

# Clone Casebox from KETSE repository
RUN git clone https://github.com/KETSE/casebox.git /var/www/casebox

WORKDIR /var/www/casebox

# Pre-create parameters.yml to avoid interactive prompts during composer install
RUN mkdir -p app/config/default
COPY parameters.yml app/config/default/parameters.yml

# Install Composer dependencies (allow failures for old packages)
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --no-interaction --no-dev --prefer-dist 2>&1 || \
    COMPOSER_ALLOW_SUPERUSER=1 composer update --no-interaction --no-dev --prefer-dist 2>&1 || \
    echo "WARNING: Composer install had issues, continuing..."

# Set up Solr configsets
RUN mkdir -p /var/solr/data/configsets/ && \
    ln -sf /var/www/casebox/var/solr/default /var/solr/data/configsets/casebox && \
    ln -sf /var/www/casebox/var/solr/log /var/solr/data/configsets/casebox_log && \
    chown -R solr:solr /var/solr/data/configsets/ 2>/dev/null || true

# Set permissions
RUN mkdir -p /var/www/casebox/var/cache /var/www/casebox/var/logs /var/www/casebox/var/files \
    /var/www/casebox/var/sessions && \
    chmod -R 777 /var/www/casebox/var/cache /var/www/casebox/var/logs \
    /var/www/casebox/var/files /var/www/casebox/var/sessions

# Configure Apache
COPY casebox-apache.conf /etc/apache2/sites-available/casebox.conf
RUN a2ensite casebox && a2dissite 000-default && a2enmod rewrite

# Supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/casebox.conf

# Entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 80

CMD ["/docker-entrypoint.sh"]
