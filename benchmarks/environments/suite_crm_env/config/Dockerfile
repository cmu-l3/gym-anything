FROM php:8.1-apache-bookworm

# Install PHP extensions required by SuiteCRM
RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libxml2-dev libzip-dev libicu-dev \
    libc-client2007e-dev libkrb5-dev \
    libcurl4-openssl-dev libonig-dev \
    libldap2-dev \
    cron curl unzip wget \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install -j$(nproc) imap \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j$(nproc) ldap \
    && docker-php-ext-install -j$(nproc) \
        mysqli pdo_mysql xml zip intl curl mbstring bcmath soap \
    && a2enmod rewrite headers \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure PHP for SuiteCRM
RUN { \
    echo 'memory_limit = 512M'; \
    echo 'max_execution_time = 600'; \
    echo 'upload_max_filesize = 25M'; \
    echo 'post_max_size = 25M'; \
    echo 'max_input_vars = 10000'; \
    echo 'display_errors = Off'; \
    echo 'short_open_tag = Off'; \
    echo 'error_reporting = E_ALL & ~E_NOTICE & ~E_DEPRECATED & ~E_STRICT'; \
    echo 'date.timezone = UTC'; \
} > /usr/local/etc/php/conf.d/suitecrm.ini

# Download pre-built SuiteCRM 7.14.6 release (includes vendor/ directory)
RUN cd /tmp && \
    wget -q "https://github.com/salesagility/SuiteCRM/releases/download/v7.14.6/SuiteCRM-7.14.6.zip" -O suitecrm.zip && \
    unzip -q suitecrm.zip -d /tmp/suitecrm_extract && \
    SUITE_DIR=$(find /tmp/suitecrm_extract -maxdepth 1 -type d -name 'SuiteCRM*' | head -1) && \
    if [ -n "$SUITE_DIR" ]; then cp -a "$SUITE_DIR"/. /var/www/html/; \
    else cp -a /tmp/suitecrm_extract/. /var/www/html/; fi && \
    rm -rf /tmp/suitecrm_extract /tmp/suitecrm.zip && \
    chown -R www-data:www-data /var/www/html && \
    chmod -R 775 /var/www/html

# Configure Apache
RUN { \
    echo '<VirtualHost *:80>'; \
    echo '    DocumentRoot /var/www/html'; \
    echo '    <Directory /var/www/html>'; \
    echo '        AllowOverride All'; \
    echo '        Require all granted'; \
    echo '    </Directory>'; \
    echo '</VirtualHost>'; \
} > /etc/apache2/sites-available/000-default.conf

# Create entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

CMD ["/entrypoint.sh"]
