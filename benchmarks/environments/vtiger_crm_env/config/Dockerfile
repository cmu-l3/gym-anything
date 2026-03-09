FROM php:8.1-apache-bookworm

# Install PHP extensions required by Vtiger CRM
RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libxml2-dev libzip-dev libicu-dev \
    libc-client2007e-dev libkrb5-dev \
    libcurl4-openssl-dev libonig-dev \
    cron curl unzip wget \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install -j$(nproc) imap \
    && docker-php-ext-install -j$(nproc) \
        mysqli pdo_mysql xml zip intl curl mbstring \
    && a2enmod rewrite \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure PHP for Vtiger
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
} > /usr/local/etc/php/conf.d/vtiger.ini

# Download and extract Vtiger CRM 8.3.0
RUN cd /tmp && \
    wget -q "https://sourceforge.net/projects/vtigercrm/files/vtiger%20CRM%208.3.0/Core%20Product/vtigercrm8.3.0.tar.gz/download" -O vtigercrm8.3.0.tar.gz && \
    tar -xzf vtigercrm8.3.0.tar.gz -C /var/www/html/ && \
    chown -R www-data:www-data /var/www/html/vtigercrm && \
    chmod -R 775 /var/www/html/vtigercrm && \
    rm -f vtigercrm8.3.0.tar.gz

# Configure Apache for Vtiger
RUN { \
    echo '<VirtualHost *:80>'; \
    echo '    DocumentRoot /var/www/html/vtigercrm'; \
    echo '    <Directory /var/www/html/vtigercrm>'; \
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
