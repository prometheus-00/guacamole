```bash
#!/bin/bash

###############################################################################
# NGINX + HTTPS + LET'S ENCRYPT
# Apache Guacamole
#
# Domena:
#   guac.XXXXXXXXXXXXXXX.pl
#
# Backend:
#   http://127.0.0.1:8080/guacamole/
#
# Publicznie:
#   https://guac.twojadomena.pl/
#
# Uruchom:
#   chmod +x install-guacamole-nginx.sh
#   ./install-guacamole-nginx.sh
###############################################################################

set -Eeuo pipefail

###############################################################################
# KONFIGURACJA
###############################################################################

DOMAIN="guac.twojadomena.pl"

EMAIL=""

GUAC_BACKEND="http://127.0.0.1:8080"

NGINX_SITE="/etc/nginx/sites-available/${DOMAIN}"
NGINX_LINK="/etc/nginx/sites-enabled/${DOMAIN}"

WEBROOT="/var/www/letsencrypt"

###############################################################################
# KOLORY
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

###############################################################################
# FUNKCJE
###############################################################################

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

die() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

###############################################################################
# ROOT
###############################################################################

if [[ "${EUID}" -ne 0 ]]; then
    die "Uruchom skrypt jako root."
fi

###############################################################################
# SYSTEM
###############################################################################

if [[ ! -f /etc/os-release ]]; then
    die "Nie można wykryć systemu."
fi

source /etc/os-release

if [[ "${ID}" != "debian" ]]; then
    warn "System nie jest Debianem."
fi

if [[ "${VERSION_ID:-}" != "13" ]]; then
    warn "Wykryto Debian ${VERSION_ID:-unknown}. Skrypt przygotowany dla Debian 13."
fi

ok "System: ${PRETTY_NAME}"

###############################################################################
# SPRAWDZENIE GUACAMOLE
###############################################################################

log "Sprawdzanie Guacamole..."

if ! systemctl is-active --quiet guacd; then
    warn "guacd nie działa."
    systemctl --no-pager status guacd || true
fi

###############################################################################
# SPRAWDZENIE TOMCAT
###############################################################################

if systemctl list-unit-files | grep -q "^tomcat10.service"; then

    if ! systemctl is-active --quiet tomcat10; then
        warn "Tomcat nie działa."
        systemctl --no-pager status tomcat10 || true
    fi

else

    warn "Nie znaleziono usługi tomcat10."

fi

###############################################################################
# TEST BACKENDU
###############################################################################

log "Sprawdzanie backendu Guacamole..."

HTTP_CODE="$(curl -s \
    --connect-timeout 5 \
    --max-time 10 \
    -o /dev/null \
    -w "%{http_code}" \
    "${GUAC_BACKEND}/guacamole/" || true)"

if [[ "${HTTP_CODE}" == "200" ]]; then

    ok "Guacamole odpowiada HTTP ${HTTP_CODE}."

else

    warn "Backend Guacamole zwrócił HTTP ${HTTP_CODE}."

    echo
    echo "Sprawdź:"
    echo "  systemctl status tomcat10"
    echo "  ss -lntp | grep 8080"
    echo
fi

###############################################################################
# INSTALACJA NGINX
###############################################################################

log "Instalowanie Nginx..."

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nginx \
    certbot \
    python3-certbot-nginx \
    curl \
    ca-certificates \
    openssl

ok "Nginx i Certbot zainstalowane."

###############################################################################
# WEBROOT
###############################################################################

log "Tworzenie webroot dla Let's Encrypt..."

mkdir -p "${WEBROOT}/.well-known/acme-challenge"

chown -R www-data:www-data "${WEBROOT}"

chmod 755 "${WEBROOT}"

###############################################################################
# USUNIĘCIE DOMYŚLNEJ STRONY NGINX
###############################################################################

rm -f /etc/nginx/sites-enabled/default

###############################################################################
# KONFIGURACJA HTTP
###############################################################################

log "Tworzenie konfiguracji Nginx..."

cat > "${NGINX_SITE}" <<EOF
###############################################################################
# Apache Guacamole
# ${DOMAIN}
###############################################################################

server {

    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};

    ###########################################################################
    # Let's Encrypt
    ###########################################################################

    location ^~ /.well-known/acme-challenge/ {

        root ${WEBROOT};

        default_type "text/plain";

        try_files \$uri =404;
    }

    ###########################################################################
    # Guacamole
    #
    # Tymczasowo przekazujemy HTTP do Tomcata.
    # Certbot później zmieni konfigurację na HTTPS + redirect.
    ###########################################################################

    location / {

        proxy_pass ${GUAC_BACKEND}/guacamole/;

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        proxy_buffering off;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        #######################################################################
        # WebSocket
        #######################################################################

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

###############################################################################
# LINK
###############################################################################

ln -sf "${NGINX_SITE}" "${NGINX_LINK}"

###############################################################################
# TEST NGINX
###############################################################################

log "Testowanie konfiguracji Nginx..."

nginx -t

ok "Konfiguracja Nginx jest poprawna."

###############################################################################
# START NGINX
###############################################################################

systemctl enable nginx
systemctl restart nginx

sleep 2

if systemctl is-active --quiet nginx; then

    ok "Nginx działa."

else

    nginx -t
    systemctl --no-pager status nginx

    die "Nginx nie uruchomił się."

fi

###############################################################################
# DNS
###############################################################################

log "Sprawdzanie DNS..."

RESOLVED_IP="$(getent ahostsv4 "${DOMAIN}" | awk 'NR==1 {print $1}' || true)"

if [[ -n "${RESOLVED_IP}" ]]; then

    ok "${DOMAIN} → ${RESOLVED_IP}"

else

    warn "Nie można rozwiązać DNS dla ${DOMAIN}."

    echo
    echo "Upewnij się, że:"
    echo
    echo "${DOMAIN}"
    echo "        ↓"
    echo "PUBLICZNY_IP_SERWERA"
    echo

    die "Brak poprawnego DNS. Przerwano przed pobraniem certyfikatu."

fi

###############################################################################
# POBRANIE PUBLICZNEGO IP
###############################################################################

PUBLIC_IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)"

if [[ -n "${PUBLIC_IP}" ]]; then

    echo
    echo "Publiczny IP serwera: ${PUBLIC_IP}"
    echo "DNS ${DOMAIN}:        ${RESOLVED_IP}"
    echo

    if [[ "${RESOLVED_IP}" != "${PUBLIC_IP}" ]]; then

        warn "DNS nie wskazuje na wykryty publiczny IP serwera."

        echo
        echo "DNS:    ${RESOLVED_IP}"
        echo "Serwer: ${PUBLIC_IP}"
        echo

        read -r -p "Kontynuować mimo tego? [y/N]: " ANSWER

        if [[ ! "${ANSWER}" =~ ^[Yy]$ ]]; then
            die "Przerwano. Najpierw popraw rekord DNS."
        fi

    else

        ok "DNS wskazuje na publiczny IP serwera."

    fi

fi

###############################################################################
# TEST PORTU 80
###############################################################################

log "Testowanie lokalnego HTTP..."

HTTP_LOCAL="$(curl -s \
    --connect-timeout 5 \
    --max-time 10 \
    -o /dev/null \
    -w "%{http_code}" \
    "http://127.0.0.1/" || true)"

echo "HTTP localhost: ${HTTP_LOCAL}"

###############################################################################
# EMAIL
###############################################################################

if [[ -z "${EMAIL}" ]]; then

    echo
    echo "Let's Encrypt wymaga adresu e-mail do powiadomień."
    echo

    read -r -p "Podaj adres e-mail: " EMAIL

    if [[ -z "${EMAIL}" ]]; then
        die "Nie podano adresu e-mail."
    fi

fi

###############################################################################
# CERTBOT
###############################################################################

log "Pobieranie certyfikatu Let's Encrypt..."

certbot \
    --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "${EMAIL}" \
    -d "${DOMAIN}"

ok "Certyfikat Let's Encrypt został skonfigurowany."

###############################################################################
# DODATKOWA KONFIGURACJA NGINX
###############################################################################

log "Dodawanie ustawień bezpieczeństwa..."

# Certbot może przebudować konfigurację.
# Dodajemy osobny plik z ustawieniami.

cat > /etc/nginx/conf.d/guacamole-security.conf <<'EOF'
###############################################################################
# Apache Guacamole - security / performance
###############################################################################

proxy_cache_path /var/cache/nginx/guacamole
    levels=1:2
    keys_zone=guacamole_cache:10m
    max_size=100m
    inactive=60m
    use_temp_path=off;
EOF

###############################################################################
# BACKUP KONFIGURACJI
###############################################################################

cp "${NGINX_SITE}" "${NGINX_SITE}.backup"

###############################################################################
# WYŁĄCZENIE BUFOROWANIA DLA GUACAMOLE
###############################################################################

# Usuwamy ewentualne problematyczne proxy_buffering
# i dokładamy ustawienia potrzebne do długich sesji.

python3 - <<'PY'
from pathlib import Path

p = Path("/etc/nginx/sites-available/guac.twojadomena.pl")

if p.exists():

    data = p.read_text()

    if "proxy_buffering off;" not in data:
        data = data.replace(
            "proxy_http_version 1.1;",
            "proxy_http_version 1.1;\n\n        proxy_buffering off;"
        )

    if "proxy_read_timeout 3600s;" not in data:
        data = data.replace(
            "proxy_buffering off;",
            "proxy_buffering off;\n\n"
            "        proxy_read_timeout 3600s;\n"
            "        proxy_send_timeout 3600s;"
        )

    p.write_text(data)
PY

###############################################################################
# NAGŁÓWKI BEZPIECZEŃSTWA
###############################################################################

cat > /etc/nginx/snippets/guacamole-security.conf <<'EOF'
###############################################################################
# Security headers
###############################################################################

add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

###############################################################################
# HSTS
#
# Włączamy dopiero po prawidłowym HTTPS.
###############################################################################

add_header Strict-Transport-Security "max-age=31536000" always;
EOF

###############################################################################
# DODANIE SECURITY HEADERS DO HTTPS
###############################################################################

python3 - <<'PY'
from pathlib import Path

p = Path("/etc/nginx/sites-available/guac.twojadomena.pl")

if p.exists():

    data = p.read_text()

    if 'include /etc/nginx/snippets/guacamole-security.conf;' not in data:

        # Dodajemy include na początku pierwszego server {}
        data = data.replace(
            "server {",
            "server {\n\n    include /etc/nginx/snippets/guacamole-security.conf;",
            1
        )

    p.write_text(data)
PY

###############################################################################
# TEST NGINX
###############################################################################

log "Końcowy test Nginx..."

nginx -t

###############################################################################
# RELOAD
###############################################################################

systemctl reload nginx

sleep 2

###############################################################################
# CERTYFIKAT
###############################################################################

log "Sprawdzanie certyfikatu..."

CERTBOT_OUTPUT="$(certbot certificates 2>/dev/null || true)"

echo
echo "${CERTBOT_OUTPUT}"
echo

###############################################################################
# TEST HTTPS
###############################################################################

log "Test HTTPS..."

HTTPS_CODE="$(curl -k -s \
    --connect-timeout 10 \
    --max-time 15 \
    -o /dev/null \
    -w "%{http_code}" \
    "https://${DOMAIN}/" || true)"

if [[ "${HTTPS_CODE}" == "200" ]]; then

    ok "HTTPS działa — HTTP ${HTTPS_CODE}."

else

    warn "HTTPS zwróciło HTTP ${HTTPS_CODE}."

fi

###############################################################################
# TEST HTTP → HTTPS
###############################################################################

log "Test przekierowania HTTP → HTTPS..."

REDIRECT="$(curl -s \
    --connect-timeout 10 \
    --max-time 15 \
    -o /dev/null \
    -w "%{http_code}" \
    "http://${DOMAIN}/" || true)"

echo "HTTP status: ${REDIRECT}"

###############################################################################
# CERTBOT TIMER
###############################################################################

log "Sprawdzanie automatycznego odnawiania..."

if systemctl list-unit-files | grep -q "certbot.timer"; then

    systemctl enable --now certbot.timer

    ok "certbot.timer jest aktywny."

else

    warn "Nie znaleziono certbot.timer."

fi

###############################################################################
# TEST ODNAWIANIA
###############################################################################

log "Test certyfikatu..."

certbot renew --dry-run || warn "Test odnowienia certyfikatu nie przeszedł."

###############################################################################
# STATUS USŁUG
###############################################################################

echo
echo "============================================================"
echo " STATUS USŁUG"
echo "============================================================"
echo

echo "Nginx:"
systemctl is-active nginx || true

echo
echo "Tomcat:"
systemctl is-active tomcat10 || true

echo
echo "guacd:"
systemctl is-active guacd || true

echo
echo "Certbot:"
systemctl is-active certbot.timer || true

###############################################################################
# PORTY
###############################################################################

echo
echo "============================================================"
echo " PORTY"
echo "============================================================"
echo

ss -lntp | grep -E ':(80|443|8080|4822)\b' || true

###############################################################################
# INFORMACJE
###############################################################################

INFO_FILE="/root/guacamole-nginx-install.txt"

cat > "${INFO_FILE}" <<EOF
============================================================
Apache Guacamole + Nginx
============================================================

Domena:
https://${DOMAIN}/

Backend:
${GUAC_BACKEND}/guacamole/

Nginx:
${NGINX_SITE}

Webroot Let's Encrypt:
${WEBROOT}

------------------------------------------------------------
USŁUGI
------------------------------------------------------------

systemctl status nginx
systemctl status tomcat10
systemctl status guacd
systemctl status certbot.timer

------------------------------------------------------------
LOGI NGINX
------------------------------------------------------------

journalctl -u nginx -f

/var/log/nginx/access.log
/var/log/nginx/error.log

------------------------------------------------------------
LOGI CERTBOT
------------------------------------------------------------

journalctl -u certbot.timer

------------------------------------------------------------
TEST
------------------------------------------------------------

nginx -t

certbot certificates

certbot renew --dry-run

------------------------------------------------------------
WAŻNE PORTY
------------------------------------------------------------

80/tcp   HTTP / Let's Encrypt
443/tcp  HTTPS

8080/tcp Tomcat - NIE WYSTAWIAĆ DO INTERNETU
4822/tcp guacd  - NIE WYSTAWIAĆ DO INTERNETU

============================================================
EOF

chmod 600 "${INFO_FILE}"

###############################################################################
# PODSUMOWANIE
###############################################################################

echo
echo "============================================================"
echo -e "${GREEN} INSTALACJA ZAKOŃCZONA ${NC}"
echo "============================================================"
echo
echo "Guacamole:"
echo
echo "    https://${DOMAIN}/"
echo
echo "Backend:"
echo
echo "    ${GUAC_BACKEND}/guacamole/"
echo
echo "Certyfikat:"
echo
echo "    Let's Encrypt"
echo
echo "Automatyczne odnawianie:"
echo
echo "    certbot.timer"
echo
echo "Informacje:"
echo
echo "    ${INFO_FILE}"
echo
echo "============================================================"
echo

exit 0
```
