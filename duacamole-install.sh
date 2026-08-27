```bash
#!/bin/bash

###############################################################################
# Apache Guacamole 1.6.0
# Debian 13 (Trixie)
#
# Instalacja:
#   guacamole-server 1.6.0
#   guacamole-client 1.6.0
#   Apache Tomcat
#   MariaDB
#   JDBC Authentication
#
# Obsługiwane protokoły:
#   RDP
#   SSH
#   VNC
#   Telnet
#
# Uruchom jako root:
#   chmod +x install-guacamole.sh
#   ./install-guacamole.sh
###############################################################################

set -Eeuo pipefail

###############################################################################
# KONFIGURACJA
###############################################################################

GUAC_VERSION="1.6.0"

GUAC_SERVER_URL="https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz"
GUAC_WAR_URL="https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war"
GUAC_JDBC_URL="https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz"

GUAC_HOME="/etc/guacamole"
GUAC_LIB="/etc/guacamole/lib"
GUAC_EXT="/etc/guacamole/extensions"

GUAC_USER="guacamole"
GUAC_DB="guacamole_db"
GUAC_DB_USER="guacamole_user"

TOMCAT_WEBAPPS="/var/lib/tomcat10/webapps"

BUILD_DIR="/usr/local/src/guacamole"

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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

###############################################################################
# OBSŁUGA BŁĘDÓW
###############################################################################

trap 'error "Błąd w linii $LINENO. Instalacja przerwana."' ERR

###############################################################################
# ROOT
###############################################################################

if [[ "${EUID}" -ne 0 ]]; then
    die "Uruchom skrypt jako root."
fi

###############################################################################
# SYSTEM
###############################################################################

log "Sprawdzanie systemu..."

if [[ ! -f /etc/os-release ]]; then
    die "Nie można wykryć systemu."
fi

source /etc/os-release

if [[ "${ID}" != "debian" ]]; then
    die "Ten skrypt jest przeznaczony dla Debiana."
fi

if [[ "${VERSION_ID}" != "13" ]]; then
    warn "Wykryto Debian ${VERSION_ID}. Skrypt był przygotowany dla Debian 13."
fi

ok "System: ${PRETTY_NAME}"

###############################################################################
# AKTUALIZACJA
###############################################################################

log "Aktualizacja systemu..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

###############################################################################
# ZALEŻNOŚCI
###############################################################################

log "Instalowanie zależności..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget \
    curl \
    ca-certificates \
    gnupg \
    unzip \
    tar \
    gzip \
    bzip2 \
    build-essential \
    gcc \
    g++ \
    make \
    pkg-config \
    autoconf \
    automake \
    libtool \
    libcairo2-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libuuid1 \
    uuid-dev \
    libossp-uuid-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev \
    freerdp2-dev \
    libpango1.0-dev \
    libssh2-1-dev \
    libtelnet-dev \
    libvncserver-dev \
    libwebsockets-dev \
    libpulse-dev \
    libssl-dev \
    libvorbis-dev \
    libwebp-dev \
    ffmpeg \
    mariadb-server \
    mariadb-client \
    tomcat10 \
    default-jdk

ok "Zależności zainstalowane."

###############################################################################
# SPRAWDZENIE WERSJI JAVA
###############################################################################

log "Sprawdzanie Java..."

java -version

###############################################################################
# UŻYTKOWNIK GUACAMOLE
###############################################################################

if ! id "${GUAC_USER}" >/dev/null 2>&1; then
    log "Tworzenie użytkownika ${GUAC_USER}..."

    useradd \
        --system \
        --home-dir /var/lib/guacamole \
        --create-home \
        --shell /usr/sbin/nologin \
        "${GUAC_USER}"
fi

ok "Użytkownik ${GUAC_USER} gotowy."

###############################################################################
# KATALOGI
###############################################################################

log "Tworzenie katalogów..."

mkdir -p "${GUAC_HOME}"
mkdir -p "${GUAC_LIB}"
mkdir -p "${GUAC_EXT}"
mkdir -p "${BUILD_DIR}"

chown -R root:root "${GUAC_HOME}"
chmod 755 "${GUAC_HOME}"

###############################################################################
# MARIA DB
###############################################################################

log "Uruchamianie MariaDB..."

systemctl enable --now mariadb

sleep 3

###############################################################################
# GENEROWANIE HASŁA
###############################################################################

DB_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
DB_ROOT_RANDOM="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"

###############################################################################
# BAZA
###############################################################################

log "Tworzenie bazy MariaDB..."

mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${GUAC_DB}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${GUAC_DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASSWORD}';

ALTER USER '${GUAC_DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${GUAC_DB}\`.*
    TO '${GUAC_DB_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF

ok "Baza ${GUAC_DB} utworzona."

###############################################################################
# GUACAMOLE SERVER
###############################################################################

cd "${BUILD_DIR}"

SERVER_ARCHIVE="guacamole-server-${GUAC_VERSION}.tar.gz"

if [[ ! -f "${SERVER_ARCHIVE}" ]]; then

    log "Pobieranie guacamole-server ${GUAC_VERSION}..."

    wget -O "${SERVER_ARCHIVE}" \
        "${GUAC_SERVER_URL}"

fi

rm -rf "guacamole-server-${GUAC_VERSION}"

tar -xzf "${SERVER_ARCHIVE}"

cd "guacamole-server-${GUAC_VERSION}"

###############################################################################
# AUTOGENERATE
###############################################################################

log "Uruchamianie autoreconf..."

autoreconf -fi

###############################################################################
# CONFIGURE
###############################################################################

log "Konfiguracja guacamole-server..."

./configure \
    --with-systemd-dir=/usr/lib/systemd/system

###############################################################################
# BUILD
###############################################################################

log "Kompilowanie guacamole-server..."

make -j"$(nproc)"

###############################################################################
# INSTALL
###############################################################################

log "Instalowanie guacamole-server..."

make install

###############################################################################
# LD CONFIG
###############################################################################

ldconfig

###############################################################################
# SYSTEMD
###############################################################################

systemctl daemon-reload

###############################################################################
# GUACD
###############################################################################

if systemctl list-unit-files | grep -q "^guacd.service"; then

    log "Włączanie usługi guacd..."

    systemctl enable guacd
    systemctl restart guacd

else

    warn "Nie znaleziono automatycznie jednostki guacd.service."

    cat > /etc/systemd/system/guacd.service <<'EOF'
[Unit]
Description=Apache Guacamole proxy daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/guacd -f
Restart=on-failure
RestartSec=5
User=guacamole
Group=guacamole

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now guacd

fi

###############################################################################
# TEST GUACD
###############################################################################

sleep 3

if systemctl is-active --quiet guacd; then
    ok "guacd działa."
else
    journalctl -u guacd --no-pager -n 50
    die "guacd nie uruchomił się."
fi

###############################################################################
# GUACAMOLE CLIENT
###############################################################################

cd "${BUILD_DIR}"

WAR_FILE="guacamole-${GUAC_VERSION}.war"

log "Pobieranie Guacamole Web Application..."

wget -O "${WAR_FILE}" \
    "${GUAC_WAR_URL}"

###############################################################################
# TOMCAT
###############################################################################

log "Konfiguracja Tomcat..."

systemctl enable tomcat10

###############################################################################
# DEPLOY WAR
###############################################################################

rm -f "${TOMCAT_WEBAPPS}/guacamole.war"
rm -rf "${TOMCAT_WEBAPPS}/guacamole"

cp "${WAR_FILE}" "${TOMCAT_WEBAPPS}/guacamole.war"

chown tomcat:tomcat "${TOMCAT_WEBAPPS}/guacamole.war"

###############################################################################
# JDBC
###############################################################################

cd "${BUILD_DIR}"

JDBC_ARCHIVE="guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz"

log "Pobieranie JDBC authentication..."

wget -O "${JDBC_ARCHIVE}" \
    "${GUAC_JDBC_URL}"

rm -rf "guacamole-auth-jdbc-${GUAC_VERSION}"

tar -xzf "${JDBC_ARCHIVE}"

###############################################################################
# KOPIOWANIE JDBC JAR
###############################################################################

find \
    "guacamole-auth-jdbc-${GUAC_VERSION}" \
    -type f \
    -name "guacamole-auth-jdbc-mariadb-${GUAC_VERSION}.jar" \
    -exec cp {} "${GUAC_EXT}/" \;

###############################################################################
# SPRAWDZENIE JDBC
###############################################################################

if ! ls "${GUAC_EXT}"/guacamole-auth-jdbc-mariadb-*.jar >/dev/null 2>&1; then
    die "Nie znaleziono rozszerzenia JDBC MariaDB."
fi

ok "JDBC MariaDB zainstalowane."

###############################################################################
# SCHEMAT BAZY
###############################################################################

SCHEMA_FILE="$(
    find \
        "guacamole-auth-jdbc-${GUAC_VERSION}" \
        -type f \
        -name "001-create-schema.sql" \
        | head -n 1
)"

if [[ -z "${SCHEMA_FILE}" ]]; then
    die "Nie znaleziono pliku 001-create-schema.sql."
fi

log "Importowanie schematu Guacamole do MariaDB..."

cat "${SCHEMA_FILE}" | mysql "${GUAC_DB}"

ok "Schemat bazy zaimportowany."

###############################################################################
# GUACAMOLE.PROPERTIES
###############################################################################

log "Tworzenie guacamole.properties..."

cat > "${GUAC_HOME}/guacamole.properties" <<EOF
###############################################################################
# Apache Guacamole
# Generated automatically
###############################################################################

guacd-hostname: 127.0.0.1
guacd-port: 4822

###############################################################################
# MariaDB / JDBC
###############################################################################

mysql-hostname: 127.0.0.1
mysql-port: 3306
mysql-database: ${GUAC_DB}
mysql-username: ${GUAC_DB_USER}
mysql-password: ${DB_PASSWORD}

###############################################################################
# Encoding
###############################################################################

mysql-default-max-connections: 8
mysql-default-max-group-connections: 8
EOF

chmod 640 "${GUAC_HOME}/guacamole.properties"

###############################################################################
# GUACAMOLE_HOME DLA TOMCAT
###############################################################################

log "Konfiguracja GUACAMOLE_HOME..."

mkdir -p /etc/systemd/system/tomcat10.service.d

cat > /etc/systemd/system/tomcat10.service.d/guacamole.conf <<EOF
[Service]
Environment="GUACAMOLE_HOME=${GUAC_HOME}"
EOF

###############################################################################
# TOMCAT DOSTĘP DO GUACAMOLE
###############################################################################

chown -R root:tomcat "${GUAC_HOME}"
chmod 750 "${GUAC_HOME}"
chmod 640 "${GUAC_HOME}/guacamole.properties"

###############################################################################
# ROZMIARY / PERMISSIONS EXTENSIONS
###############################################################################

chown -R root:tomcat "${GUAC_EXT}"
chmod 750 "${GUAC_EXT}"

for file in "${GUAC_EXT}"/*.jar; do
    chmod 640 "$file"
done

###############################################################################
# RESTART TOMCAT
###############################################################################

systemctl daemon-reload

systemctl restart tomcat10

sleep 8

###############################################################################
# STATUS TOMCAT
###############################################################################

if systemctl is-active --quiet tomcat10; then
    ok "Tomcat działa."
else
    journalctl -u tomcat10 --no-pager -n 80
    die "Tomcat nie uruchomił się."
fi

###############################################################################
# SPRAWDZENIE PORTÓW
###############################################################################

log "Sprawdzanie portów..."

echo
ss -lntp | grep -E ':(4822|8080|3306)\b' || true
echo

###############################################################################
# TEST HTTP
###############################################################################

log "Test aplikacji Guacamole..."

sleep 3

HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" \
    http://127.0.0.1:8080/guacamole/ || true)"

if [[ "${HTTP_CODE}" == "200" ]]; then
    ok "Guacamole odpowiada HTTP 200."
else
    warn "Guacamole zwróciło HTTP ${HTTP_CODE}."
fi

###############################################################################
# INFORMACJE LOGOWANIA
###############################################################################

CREDENTIALS_FILE="/root/guacamole-install.txt"

cat > "${CREDENTIALS_FILE}" <<EOF
============================================================
 Apache Guacamole ${GUAC_VERSION}
============================================================

URL:
http://SERVER-IP:8080/guacamole/

------------------------------------------------------------
MariaDB
------------------------------------------------------------

Database:
${GUAC_DB}

Username:
${GUAC_DB_USER}

Password:
${DB_PASSWORD}

------------------------------------------------------------
Usługi
------------------------------------------------------------

guacd:
systemctl status guacd

Tomcat:
systemctl status tomcat10

MariaDB:
systemctl status mariadb

------------------------------------------------------------
Logi
------------------------------------------------------------

journalctl -u guacd -f
journalctl -u tomcat10 -f
journalctl -u mariadb -f

------------------------------------------------------------
Konfiguracja
------------------------------------------------------------

${GUAC_HOME}/guacamole.properties

Extensions:
${GUAC_EXT}

============================================================
EOF

chmod 600 "${CREDENTIALS_FILE}"

###############################################################################
# INFORMACJE KOŃCOWE
###############################################################################

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "============================================================"
echo -e "${GREEN} INSTALACJA GUACAMOLE ZAKOŃCZONA ${NC}"
echo "============================================================"
echo
echo "Guacamole:     ${GUAC_VERSION}"
echo
echo "URL:"
echo "http://${SERVER_IP}:8080/guacamole/"
echo
echo "guacd:"
systemctl is-active guacd || true
echo
echo "Tomcat:"
systemctl is-active tomcat10 || true
echo
echo "MariaDB:"
systemctl is-active mariadb || true
echo
echo "Dane instalacyjne:"
echo "${CREDENTIALS_FILE}"
echo
echo "============================================================"
echo

###############################################################################
# STATUS
###############################################################################

systemctl --no-pager --full status guacd || true
echo
systemctl --no-pager --full status tomcat10 || true

exit 0
```
