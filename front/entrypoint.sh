#!/bin/sh
CORE="${CORE_URL:-}"
AUTH="${AUTH_URL:-}"

sed -i "s|__CORE_URL__|${CORE}|g" /usr/share/nginx/html/index.html
sed -i "s|__AUTH_URL__|${AUTH}|g" /usr/share/nginx/html/index.html

PORT="${PORT:-8080}"
sed -i "s/listen\s*8080;/listen ${PORT};/g" /etc/nginx/conf.d/default.conf

exec nginx -g "daemon off;"
