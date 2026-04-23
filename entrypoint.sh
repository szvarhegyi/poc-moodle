#!/bin/bash

PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-512M}
PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME:-180}
PHP_MAX_INPUT_VARS=${PHP_MAX_INPUT_VARS:-5000}
PHP_POST_MAX_SIZE=${PHP_POST_MAX_SIZE:-100M}
PHP_UPLOAD_MAX_FILESIZE=${PHP_UPLOAD_MAX_FILESIZE:-100M}
PHP_OPCACHE_MEMORY_CONSUMPTION=${PHP_OPCACHE_MEMORY_CONSUMPTION:-256}
PHP_TIMEZONE=${PHP_TIMEZONE:-Europe/Budapest}

PHP_FPM_PM=${PHP_FPM_PM:-dynamic}
PHP_FPM_MAX_CHILDREN=${PHP_FPM_MAX_CHILDREN:-50}
PHP_FPM_START_SERVERS=${PHP_FPM_START_SERVERS:-5}
PHP_FPM_MIN_SPARE_SERVERS=${PHP_FPM_MIN_SPARE_SERVERS:-5}
PHP_FPM_MAX_SPARE_SERVERS=${PHP_FPM_MAX_SPARE_SERVERS:-35}
PHP_FPM_MAX_REQUESTS=${PHP_FPM_MAX_REQUESTS:-500}


APACHE_START_SERVERS=${APACHE_START_SERVERS:-2}
APACHE_MIN_SPARE_THREADS=${APACHE_MIN_SPARE_THREADS:-25}
APACHE_MAX_SPARE_THREADS=${APACHE_MAX_SPARE_THREADS:-75}
APACHE_THREAD_LIMIT=${APACHE_THREAD_LIMIT:-64}
APACHE_THREADS_PER_CHILD=${APACHE_THREADS_PER_CHILD:-25}
APACHE_MAX_REQUEST_WORKERS=${APACHE_MAX_REQUEST_WORKERS:-150}
APACHE_MAX_CONNECTIONS_PER_CHILD=${APACHE_MAX_CONNECTIONS_PER_CHILD:-0}

cat <<EOF > /usr/local/etc/php/conf.d/php-moodle.ini
; Moodle Recommended PHP Settings
memory_limit = ${PHP_MEMORY_LIMIT}
max_execution_time = ${PHP_MAX_EXECUTION_TIME}
max_input_vars = ${PHP_MAX_INPUT_VARS}
post_max_size = ${PHP_POST_MAX_SIZE}
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}
date.timezone = ${PHP_TIMEZONE}

[opcache]
opcache.enable = 1
opcache.memory_consumption = ${PHP_OPCACHE_MEMORY_CONSUMPTION}
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
opcache.use_cwd = 1
opcache.validate_timestamps = 1
opcache.save_comments = 1
opcache.enable_file_override = 0
EOF

echo "; --- Dinamikusan Hozzáadott Változók ---" >> /usr/local/etc/php/conf.d/php-moodle.ini
for var in "${!PHP_INI_@}"; do
    key="${var#PHP_INI_}"
    key="${key//__/.}"
    val="${!var}"
    echo "${key} = ${val}" >> /usr/local/etc/php/conf.d/php-moodle.ini
done

cat <<EOF > /usr/local/etc/php-fpm.d/zz-moodle.conf
[www]
pm = ${PHP_FPM_PM}
pm.max_children = ${PHP_FPM_MAX_CHILDREN}
pm.start_servers = ${PHP_FPM_START_SERVERS}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS}
EOF

cat <<EOF > /etc/apache2/mods-available/mpm_event.conf
<IfModule mpm_event_module>
    StartServers             ${APACHE_START_SERVERS}
    MinSpareThreads          ${APACHE_MIN_SPARE_THREADS}
    MaxSpareThreads          ${APACHE_MAX_SPARE_THREADS}
    ThreadLimit              ${APACHE_THREAD_LIMIT}
    ThreadsPerChild          ${APACHE_THREADS_PER_CHILD}
    MaxRequestWorkers        ${APACHE_MAX_REQUEST_WORKERS}
    MaxConnectionsPerChild   ${APACHE_MAX_CONNECTIONS_PER_CHILD}
</IfModule>
EOF

exec "$@"
