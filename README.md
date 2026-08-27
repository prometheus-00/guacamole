# Apache Guacamole na Debian 13

Automatyczna instalacja **Apache Guacamole 1.6.0** na **Debian 13 (Trixie)** wraz z:

* Apache Guacamole
* `guacd`
* Apache Tomcat 10
* MariaDB
* JDBC Authentication
* Nginx
* Let's Encrypt
* HTTPS
* automatycznym odnawianiem certyfikatu

Projekt przeznaczony jest do szybkiego uruchomienia własnego serwera zdalnego dostępu przez przeglądarkę.

---

## Architektura

```text
                         INTERNET
                             │
                             │ HTTPS :443
                             ▼
                  ┌─────────────────────┐
                  │        NGINX        │
                  │ guac.twojadomena.pl│
                  └──────────┬──────────┘
                             │
                             │ HTTP
                             │ localhost:8080
                             ▼
                  ┌─────────────────────┐
                  │       TOMCAT        │
                  │        :8080        │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │      GUACAMOLE      │
                  │      Web App        │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │       guacd         │
                  │       :4822         │
                  └──────┬────┬────────┘
                         │    │
                        RDP  SSH/VNC
```

---

# Wymagania

## System

* Debian 13 (Trixie)
* dostęp `root`
* działające połączenie z Internetem
* minimum 2 GB RAM
* minimum 10 GB wolnego miejsca

## DNS

Przed instalacją należy utworzyć rekord DNS:

```text
guac.twojadomena.pl → PUBLICZNY_IP_SERWERA
```

Przykład:

```text
A
guac.twojadomena.pl
203.0.113.10
```

Adres IP należy oczywiście zastąpić rzeczywistym publicznym adresem serwera.

---

# Wymagane porty

Na firewallu / routerze należy zezwolić na:

| Port | Protokół | Zastosowanie         |
| ---: | :------: | -------------------- |
|   80 |    TCP   | HTTP / Let's Encrypt |
|  443 |    TCP   | HTTPS / Guacamole    |

## Porty, których NIE należy wystawiać do Internetu

| Port | Usługa  | Dostęp          |
| ---: | ------- | --------------- |
| 8080 | Tomcat  | tylko localhost |
| 4822 | guacd   | tylko localhost |
| 3306 | MariaDB | tylko localhost |

Docelowo:

```text
Internet
   │
   ├── TCP 80  → Nginx
   │
   └── TCP 443 → Nginx

localhost
   │
   ├── TCP 8080 → Tomcat
   │
   ├── TCP 4822 → guacd
   │
   └── TCP 3306 → MariaDB
```

---

# Instalacja

Instalacja składa się z dwóch etapów.

## 1. Instalacja Apache Guacamole

Uruchom:

```bash
chmod +x install-guacamole.sh
```

następnie:

```bash
./install-guacamole.sh
```

Skrypt zainstaluje:

```text
Apache Guacamole 1.6.0
guacamole-server
guacd
Apache Tomcat 10
MariaDB
JDBC Authentication
```

---

# 2. Instalacja Nginx + HTTPS

Po poprawnym zainstalowaniu Guacamole uruchom:

```bash
chmod +x install-guacamole-nginx.sh
```

następnie:

```bash
./install-guacamole-nginx.sh
```

Skrypt:

* zainstaluje Nginx,
* skonfiguruje reverse proxy,
* skonfiguruje Let's Encrypt,
* pobierze certyfikat SSL,
* wymusi HTTPS,
* skonfiguruje WebSocket,
* skonfiguruje nagłówki bezpieczeństwa,
* skonfiguruje automatyczne odnawianie certyfikatu.

---

# Adres Guacamole

Po zakończeniu instalacji panel będzie dostępny pod:

```text
https://guac.twojadomena.pl/
```

---

# Konfiguracja

Główna konfiguracja Guacamole:

```text
/etc/guacamole/guacamole.properties
```

Rozszerzenia:

```text
/etc/guacamole/extensions/
```

Konfiguracja Nginx:

```text
/etc/nginx/sites-available/guac.twojadomena.pl
```

Link:

```text
/etc/nginx/sites-enabled/guac.xxxxxx.pl
```

---

# Usługi

## Nginx

Sprawdzenie:

```bash
systemctl status nginx
```

Restart:

```bash
systemctl restart nginx
```

Przeładowanie konfiguracji:

```bash
systemctl reload nginx
```

---

## Tomcat

```bash
systemctl status tomcat10
```

Restart:

```bash
systemctl restart tomcat10
```

---

## guacd

```bash
systemctl status guacd
```

Restart:

```bash
systemctl restart guacd
```

---

## MariaDB

```bash
systemctl status mariadb
```

Restart:

```bash
systemctl restart mariadb
```

---

# Sprawdzanie portów

Do sprawdzenia nasłuchujących portów:

```bash
ss -lntp
```

Tylko interesujące nas porty:

```bash
ss -lntp | grep -E ':(80|443|8080|4822|3306)\b'
```

Prawidłowo skonfigurowany serwer powinien mieć:

```text
:80
:443
:8080
:4822
:3306
```

ale porty `8080`, `4822` i `3306` powinny być dostępne wyłącznie lokalnie.

---

# Sprawdzanie Guacamole

Test backendu Tomcat:

```bash
curl -I http://127.0.0.1:8080/guacamole/
```

Przykładowa poprawna odpowiedź:

```text
HTTP/1.1 200
```

Test HTTPS:

```bash
curl -I https://guac.xxxxx.pl/
```

---

# Sprawdzanie Nginx

Test konfiguracji:

```bash
nginx -t
```

Poprawny wynik:

```text
syntax is ok
test is successful
```

---

# Logi

## Nginx

Log dostępu:

```bash
tail -f /var/log/nginx/access.log
```

Log błędów:

```bash
tail -f /var/log/nginx/error.log
```

lub:

```bash
journalctl -u nginx -f
```

---

## Tomcat

```bash
journalctl -u tomcat10 -f
```

---

## guacd

```bash
journalctl -u guacd -f
```

---

## MariaDB

```bash
journalctl -u mariadb -f
```

---

# Let's Encrypt

Lista certyfikatów:

```bash
certbot certificates
```

Test automatycznego odnowienia:

```bash
certbot renew --dry-run
```

Sprawdzenie timera:

```bash
systemctl status certbot.timer
```

Ręczne uruchomienie:

```bash
certbot renew
```

---

# Baza danych

Instalator automatycznie tworzy:

```text
Database:
guacamole_db
```

oraz użytkownika:

```text
guacamole_user
```

Hasło jest generowane automatycznie.

Dane wygenerowane podczas instalacji są zapisywane w:

```text
/root/guacamole-install.txt
```

Uprawnienia pliku:

```text
600
```

czyli:

```bash
-rw------- root root
```

---

# Połączenia RDP

Guacamole umożliwia połączenia między innymi przez:

* RDP
* SSH
* VNC
* Telnet

Przykład połączenia RDP:

```text
Protocol:
RDP

Hostname:
192.168.1.100

Port:
3389

Username:
administrator

Password:
********
```

Adres `192.168.1.100` należy zastąpić adresem komputera, z którym chcemy się połączyć.

---

# Bezpieczeństwo

## Nie wystawiaj guacd

Port:

```text
4822/tcp
```

nie powinien być dostępny z Internetu.

Sprawdzenie:

```bash
ss -lntp | grep 4822
```

Preferowany wynik:

```text
127.0.0.1:4822
```

---

## Nie wystawiaj Tomcata

Port:

```text
8080/tcp
```

powinien być dostępny wyłącznie lokalnie.

Preferowany wynik:

```text
127.0.0.1:8080
```

---

## Nie wystawiaj MariaDB

Port:

```text
3306/tcp
```

również powinien być lokalny:

```text
127.0.0.1:3306
```

---

# Firewall

Przykładowa konfiguracja UFW:

```bash
apt install ufw
```

SSH:

```bash
ufw allow 22/tcp
```

HTTP:

```bash
ufw allow 80/tcp
```

HTTPS:

```bash
ufw allow 443/tcp
```

Włączenie:

```bash
ufw enable
```

Sprawdzenie:

```bash
ufw status verbose
```

Nie należy dodawać:

```bash
ufw allow 8080/tcp
ufw allow 4822/tcp
ufw allow 3306/tcp
```

---

# Przydatne polecenia

## Status wszystkich komponentów

```bash
systemctl status nginx tomcat10 guacd mariadb
```

## Restart całego środowiska

```bash
systemctl restart mariadb
systemctl restart guacd
systemctl restart tomcat10
systemctl restart nginx
```

## Sprawdzenie procesów

```bash
ps aux | grep -E 'nginx|tomcat|guacd|mariadb'
```

## Sprawdzenie pamięci

```bash
free -h
```

## Sprawdzenie dysku

```bash
df -h
```

## Sprawdzenie obciążenia

```bash
uptime
```

---

# Pliki instalacyjne

Repozytorium powinno zawierać:

```text
.
├── README.md
├── install-guacamole.sh
└── install-guacamole-nginx.sh
```

Nadaj skryptom prawa wykonywania:

```bash
chmod +x install-guacamole.sh
chmod +x install-guacamole-nginx.sh
```

---

# Kolejność instalacji

```text
1. Debian 13
      │
      ▼
2. DNS
   guac.xxxxxx.pl
      │
      ▼
3. install-guacamole.sh
      │
      ├── guacd
      ├── Tomcat
      ├── MariaDB
      └── Guacamole
      │
      ▼
4. install-guacamole-nginx.sh
      │
      ├── Nginx
      ├── Let's Encrypt
      ├── HTTPS
      └── Reverse Proxy
      │
      ▼
5. https://guac.twojadomena.pl/
```

---

# Troubleshooting

## Guacamole nie działa

Sprawdź:

```bash
systemctl status guacd
systemctl status tomcat10
```

Następnie:

```bash
journalctl -u guacd -n 100 --no-pager
```

oraz:

```bash
journalctl -u tomcat10 -n 100 --no-pager
```

---mm

## Nginx pokazuje 502 Bad Gateway

Najczęściej oznacza to problem z Tomcatem.

Sprawdź:

```bash
ss -lntp | grep 8080
```

oraz:

```bash
curl -I http://127.0.0.1:8080/guacamole/
```

Jeżeli Tomcat nie odpowiada:

```bash
systemctl restart tomcat10
```

---

## HTTPS nie działa

Sprawdź:

```bash
nginx -t
```

następnie:

```bash
systemctl status nginx
```

Sprawdź certyfikat:

```bash
certbot certificates
```

oraz DNS:

```bash
getent ahostsv4 guac.twojadomena.pl
```

---

## Certbot nie może pobrać certyfikatu

Sprawdź, czy:

```text
guac.twojadomena.pl
```

wskazuje na właściwy publiczny adres IP.

Sprawdź również, czy port:

```text
TCP/80
```

jest dostępny z Internetu.

---

# Aktualizacja

Przed aktualizacją wykonaj kopię konfiguracji:

```bash
cp -a /etc/guacamole /root/guacamole-backup
```

Kopia konfiguracji Nginx:

```bash
cp -a /etc/nginx/sites-available/guac..pl \
      /root/guacamole-nginx-backup
```

Kopia bazy:

```bash
mysqldump guacamole_db > /root/guacamole_db_backup.sql
```

---

# Backup

Minimalny backup powinien obejmować:

```text
/etc/guacamole/
/etc/nginx/sites-available/guac.xxxxxxx.pl
/var/lib/tomcat10/
/root/guacamole-install.txt
```

oraz bazę:

```bash
mysqldump guacamole_db > /root/guacamole_db.sql
```

---

# Autor

**PK**

Projekt przygotowany do automatycznej instalacji Apache Guacamole na Debianie 13.

---

# Licencja

Skrypty instalacyjne mogą być używane, modyfikowane i dostosowywane do własnych potrzeb.

Apache Guacamole jest projektem Apache Software Foundation i podlega własnej licencji.

Więcej informacji:

```text
https://guacamole.apache.org/
```

---

## Status projektu

```text
Apache Guacamole     1.6.0
Debian               13 Trixie
Tomcat               10
MariaDB              ✓
JDBC                 ✓
Nginx                ✓
Let's Encrypt        ✓
HTTPS                ✓
Reverse Proxy        ✓
WebSocket            ✓
```
