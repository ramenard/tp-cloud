#!/bin/sh
# Remplace le placeholder BACKEND_URL dans le HTML par la vraie valeur de l'env
BACKEND="${BACKEND_URL:-}"
sed -i "s|window.BACKEND_URL \|\| \"\"|window.BACKEND_URL \|\| \"${BACKEND}\"|g" /usr/share/nginx/html/index.html

# Nginx écoute sur le port défini par Cloud Run (défaut 8080)
PORT="${PORT:-8080}"
sed -i "s/listen\s*80;/listen ${PORT};/g" /etc/nginx/conf.d/default.conf

exec nginx -g "daemon off;"