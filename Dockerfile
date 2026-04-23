# Használjuk a hivatalos PHP 8.3 FPM image-t alapként
FROM php:8.3-fpm

# Környezeti változó, hogy az apt-get ne tegyen fel kérdéseket
ENV DEBIAN_FRONTEND=noninteractive

# Update és szükséges csomagok telepítése
# Tartalmazza az Apache2-t, supervisord-t és a Moodle PHP kiterjesztéseihez szükséges könyvtárakat
RUN apt-get update && apt-get install -y \
    apache2 \
    supervisor \
    libpng-dev \
    libjpeg-dev \
    libxml2-dev \
    libicu-dev \
    libzip-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libsodium-dev \
    libpq-dev \
    zlib1g-dev \
    libfreetype6-dev \
    unzip \
    git \
    cron \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# PHP kiterjesztések telepítése Moodle-höz
# Moodle 4.5+ kötelező / ajánlott: gd, intl, xml, zip, curl, mbstring, soap, mysqli/pgsql, sodium, opcache, exif
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    gd \
    intl \
    xml \
    zip \
    mbstring \
    soap \
    mysqli \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    sodium \
    exif \
    opcache

# Redis kiterjesztés telepítése (PECL-en keresztül) a Moodle gyorsítótárazásához
RUN pecl install redis \
    && docker-php-ext-enable redis

# Apache konfigurálása
# Felesleges MPM modulok kikapcsolása, MPM Event és a szükséges kiegészítők bekapcsolása (proxy_fcgi a PHP-FPM-hez)
RUN a2dismod mpm_prefork mpm_worker || true \
    && a2enmod mpm_event proxy_fcgi setenvif rewrite headers

# Konfigurációs fájlok másolása
COPY apache-vhost.conf /etc/apache2/sites-available/000-default.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# Opcionális: A default php-fpm pool config módosítása, ha szükséges, 
# de a php:8.3-fpm image alapból a 9000-es porton hallgat a 127.0.0.1 felületen.

# Moodle forráskód letöltése a megadott verzióhoz
# A user a 4.5.10-es verzióra kért konkrét fókuszálást,
# letöltjük a Moodle tárolójából
WORKDIR /var/www/html
RUN rm -rf /var/www/html/* \
    && curl -L https://github.com/moodle/moodle/archive/refs/tags/v4.5.10.tar.gz -o moodle.tar.gz \
    && tar -xzf moodle.tar.gz --strip-components=1 \
    && rm moodle.tar.gz

# Moodledata könyvtár létrehozása
RUN mkdir -p /var/www/moodledata \
    && chown -R www-data:www-data /var/www/html /var/www/moodledata \
    && chmod -R 775 /var/www/moodledata

RUN mkdir /var/www/localcache && chmod -R 775 /var/www/localcache && chown -R www-data:www-data /var/www/localcache

# Belépési pont (entrypoint) script másolása és beállítása
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Port definiálása
EXPOSE 80

# Kiszolgáló elindítása
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
