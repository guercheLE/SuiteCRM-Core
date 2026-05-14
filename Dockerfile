FROM composer:2 AS vendor

WORKDIR /app
COPY . .
RUN composer install \
    --no-dev \
    --no-scripts \
    --ignore-platform-req=ext-gd \
    --ignore-platform-req=ext-intl \
    --ignore-platform-req=ext-ldap \
    --ignore-platform-req=ext-mbstring \
    --ignore-platform-req=ext-pdo_mysql \
    --ignore-platform-req=ext-zip \
    --prefer-dist \
    --no-interaction \
    --no-progress \
    --optimize-autoloader

FROM php:8.2-apache

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

# install-php-extensions uses pre-compiled binaries where available,
# which is significantly faster than docker-php-ext-install under QEMU emulation.
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions \
    gd \
    intl \
    mbstring \
    mysqli \
    pdo_mysql \
    soap \
    zip \
    ldap \
    opcache \
    && a2enmod rewrite headers \
    && sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && sed -ri -e 's!AllowOverride None!AllowOverride All!g' /etc/apache2/apache2.conf \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

COPY --chown=www-data:www-data . .
COPY --from=vendor --chown=www-data:www-data /app/vendor ./vendor
COPY --chown=www-data:www-data docker/entrypoint.sh /usr/local/bin/suitecrm-entrypoint

RUN chmod +x /usr/local/bin/suitecrm-entrypoint \
    && su -s /bin/sh www-data -c 'php -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" vendor/bin/pscss --style=compressed public/legacy/themes/suite8/css/Dawn/style.scss public/legacy/themes/suite8/css/Dawn/style.css' \
    && mkdir -p /var/www/html/logs \
    /var/www/html/tmp \
    /var/www/html/cache \
    /var/www/html/public/legacy/cache \
    /var/www/html/public/legacy/custom \
    /var/www/html/public/legacy/modules \
    /var/www/html/public/legacy/themes \
    /var/www/html/public/legacy/upload \
    && chmod -R ug+rwX /var/www/html/logs \
    /var/www/html/tmp \
    /var/www/html/cache \
    /var/www/html/public/legacy/cache \
    /var/www/html/public/legacy/custom \
    /var/www/html/public/legacy/modules \
    /var/www/html/public/legacy/themes \
    /var/www/html/public/legacy/upload

EXPOSE 80

ENTRYPOINT ["suitecrm-entrypoint"]
CMD ["apache2-foreground"]
