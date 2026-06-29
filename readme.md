# Instalasi ownCloud + ONLYOFFICE Docs dengan Docker

README ini berisi langkah instalasi ulang ownCloud + ONLYOFFICE Docs menggunakan Docker Compose. Konfigurasi ini dibuat agar data disimpan di folder lokal server, bukan Docker named volume, dan agar file Office seperti `.docx`, `.xlsx`, dan `.pptx` bisa langsung dibuka melalui ONLYOFFICE di ownCloud.

---

## 1. Struktur Folder Project

Buat struktur project seperti berikut:

```bash
owncloud_config/
├── .env
├── docker-compose.yml
├── nginx.conf
├── run.sh
├── onlyoffice/
├── files/
├── db/
├── redis/
└── data/
    └── onlyoffice/
        ├── document_data/
        ├── document_log/
        ├── document_lib/
        └── document_db/
```

Keterangan folder:

| Folder | Fungsi |
|---|---|
| `files/` | Data file ownCloud |
| `db/` | Data database MariaDB |
| `redis/` | Data Redis |
| `data/onlyoffice/` | Data internal ONLYOFFICE Document Server |
| `onlyoffice/` | Connector ONLYOFFICE untuk ownCloud |

---

## 2. File `.env`

Buat file `.env`:

```env
OWNCLOUD_TRUSTED_DOMAINS=localhost,nginx-server,app-server,127.0.0.1
OWNCLOUD_DOMAIN=localhost
OWNCLOUD_OVERWRITE_CLI_URL=http://localhost

ADMIN_USERNAME=admin
ADMIN_PASSWORD=password

DB_NAME=owncloud
DB_ROOT_PASS=p455w0rd
DB_USERNAME=owncloud
DB_PASSWORD=p455w0rd

ONLYOFFICE_JWT_SECRET=secret
```

Kalau nanti dipakai di server publik/domain, ganti bagian ini:

```env
OWNCLOUD_TRUSTED_DOMAINS=domainkamu.com,nginx-server,app-server,127.0.0.1
OWNCLOUD_DOMAIN=domainkamu.com
OWNCLOUD_OVERWRITE_CLI_URL=https://domainkamu.com
```

---

## 3. File `docker-compose.yml`

Gunakan konfigurasi berikut:

```yaml
services:
  db:
    image: mariadb:10.11
    container_name: db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASS}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USERNAME}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    command: ["--max-allowed-packet=128M", "--innodb-log-file-size=64M"]
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-u", "root", "--password=${DB_ROOT_PASS}"]
      interval: 10s
      timeout: 5s
      retries: 20
    volumes:
      - ./db:/var/lib/mysql
    networks:
      - onlyoffice
    ports:
      - "23306:3306"

  redis:
    image: redis:6
    container_name: redis
    restart: unless-stopped
    command: ["redis-server", "--databases", "1", "--appendonly", "yes"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 20
    volumes:
      - ./redis:/data
    networks:
      - onlyoffice

  onlyoffice-document-server:
    image: onlyoffice/documentserver:latest
    container_name: onlyoffice-document-server
    restart: unless-stopped
    environment:
      JWT_ENABLED: "true"
      JWT_SECRET: ${ONLYOFFICE_JWT_SECRET}
      JWT_HEADER: Authorization
    expose:
      - "80"
    volumes:
      - ./data/onlyoffice/document_data:/var/www/onlyoffice/Data
      - ./data/onlyoffice/document_log:/var/log/onlyoffice
      - ./data/onlyoffice/document_lib:/var/lib/onlyoffice
      - ./data/onlyoffice/document_db:/var/lib/postgresql
    networks:
      - onlyoffice

  app:
    image: owncloud/server:latest
    container_name: app-server
    restart: unless-stopped
    stdin_open: true
    tty: true
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
      onlyoffice-document-server:
        condition: service_started
    environment:
      OWNCLOUD_DOMAIN: ${OWNCLOUD_DOMAIN}
      OWNCLOUD_TRUSTED_DOMAINS: ${OWNCLOUD_TRUSTED_DOMAINS}
      OWNCLOUD_OVERWRITE_CLI_URL: ${OWNCLOUD_OVERWRITE_CLI_URL}
      OWNCLOUD_ADMIN_USERNAME: ${ADMIN_USERNAME}
      OWNCLOUD_ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      OWNCLOUD_DB_TYPE: mysql
      OWNCLOUD_DB_NAME: ${DB_NAME}
      OWNCLOUD_DB_USERNAME: ${DB_USERNAME}
      OWNCLOUD_DB_PASSWORD: ${DB_PASSWORD}
      OWNCLOUD_DB_HOST: db
      OWNCLOUD_MYSQL_UTF8MB4: "true"
      OWNCLOUD_REDIS_ENABLED: "true"
      OWNCLOUD_REDIS_HOST: redis
      ONLYOFFICE_JWT_SECRET: ${ONLYOFFICE_JWT_SECRET}
    expose:
      - "8080"
    volumes:
      - ./files:/mnt/data
      - ./onlyoffice:/tmp/onlyoffice:ro
      - ./run.sh:/run.sh:ro
    command: ["bash", "/run.sh"]
    networks:
      - onlyoffice

  nginx:
    image: nginx:latest
    container_name: nginx-server
    restart: unless-stopped
    depends_on:
      - app
      - onlyoffice-document-server
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - onlyoffice

networks:
  onlyoffice:
    driver: bridge
```

Catatan penting:

- Jangan mount `./onlyoffice` langsung ke `/var/www/owncloud/custom/onlyoffice`.
- Mount ke `/tmp/onlyoffice:ro` saja, lalu `run.sh` yang akan copy ke folder custom ownCloud.
- Ini mencegah error:

```bash
rm: cannot remove '/var/www/owncloud/custom/onlyoffice': Device or resource busy
```

---

## 4. File `nginx.conf`

Buat file `nginx.conf`:

```nginx
user nginx;
worker_processes auto;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    upstream owncloud_backend {
        server app-server:8080;
    }

    upstream onlyoffice_backend {
        server onlyoffice-document-server:80;
    }

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 10G;

    map $http_host $this_host {
        "" $host;
        default $http_host;
    }

    map $http_x_forwarded_proto $the_scheme {
        default $http_x_forwarded_proto;
        "" $scheme;
    }

    map $http_x_forwarded_host $the_host {
        default $http_x_forwarded_host;
        "" $this_host;
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://owncloud_backend;
            proxy_http_version 1.1;

            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $the_host;
            proxy_set_header X-Forwarded-Proto $the_scheme;

            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
        }

        location ^~ /ds-vpath/ {
            rewrite ^/ds-vpath/(.*)$ /$1 break;
            proxy_pass http://onlyoffice_backend;

            proxy_redirect off;
            proxy_http_version 1.1;

            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $the_host/ds-vpath;
            proxy_set_header X-Forwarded-Proto $the_scheme;

            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
            client_max_body_size 100M;
        }
    }
}
```

---

## 5. File `run.sh`

Buat file `run.sh`:

```bash
#!/bin/bash

set -u

echo "=== Starting ownCloud server ==="
/usr/bin/owncloud server > /tmp/server.log 2>&1 &
OWNCLOUD_PID=$!

echo "=== Waiting until ownCloud installation is fully ready ==="
READY=0

for i in $(seq 1 180); do
  if ! kill -0 "$OWNCLOUD_PID" >/dev/null 2>&1; then
    echo "=== ERROR: ownCloud process stopped. Showing /tmp/server.log ==="
    cat /tmp/server.log || true
    echo "=== Container kept alive for debugging. ==="
    tail -f /dev/null
  fi

  STATUS_OUTPUT="$(occ --no-warnings status 2>/dev/null || true)"

  if echo "$STATUS_OUTPUT" | grep -q "installed: true"; then
    READY=1
    break
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsS -H "Host: localhost" http://127.0.0.1:8080/status.php 2>/dev/null | grep -q '"installed":true'; then
      READY=1
      break
    fi
  fi

  echo "Still waiting for ownCloud installed:true... ${i}/180"
  echo "$STATUS_OUTPUT" | sed 's/^/occ status: /' || true
  sleep 3
done

if [ "$READY" != "1" ]; then
  echo "=== ERROR: ownCloud did not reach installed:true. Last ownCloud log: ==="
  tail -n 250 /tmp/server.log || true
  echo "=== Container kept alive for debugging. ==="
  tail -f /dev/null
fi

echo "=== ownCloud is installed and ready ==="

echo "=== Installing ONLYOFFICE connector ==="
if [ ! -f /tmp/onlyoffice/appinfo/info.xml ]; then
  echo "WARNING: /tmp/onlyoffice/appinfo/info.xml not found."
  echo "Run on host:"
  echo "rm -rf onlyoffice && git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice"
else
  rm -rf /var/www/owncloud/custom/onlyoffice || true
  mkdir -p /var/www/owncloud/custom
  cp -a /tmp/onlyoffice /var/www/owncloud/custom/onlyoffice
  chown -R www-data:www-data /var/www/owncloud/custom/onlyoffice || true

  echo "=== Enabling ONLYOFFICE app ==="
  occ --no-warnings --no-interaction app:enable onlyoffice || true

  echo "=== Setting ONLYOFFICE connector config ==="
  occ --no-warnings --no-interaction config:app:set onlyoffice DocumentServerUrl --value="/ds-vpath/" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice-document-server/" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice StorageUrl --value="http://nginx-server/" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice jwt_secret --value="${ONLYOFFICE_JWT_SECRET:-secret}" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice jwt_header --value="Authorization" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice sameTab --value="true" || true
fi

echo "=== Ready. Showing ownCloud log ==="
tail -f /tmp/server.log
```

Beri permission execute:

```bash
chmod +x run.sh
```

---

## 6. Clone Connector ONLYOFFICE dengan Submodule

Ini bagian yang paling penting.

Jangan clone biasa seperti ini:

```bash
git clone --depth 1 https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice
```

Karena clone biasa tidak mengambil submodule `document-formats` dan `document-templates`.

Gunakan command ini:

```bash
rm -rf onlyoffice

git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice

cd onlyoffice
git submodule update --init --recursive
cd ..
```

Cek apakah submodule sudah masuk:

```bash
ls -lah onlyoffice/assets/document-formats
ls -lah onlyoffice/assets/document-templates
```

Pastikan file ini ada:

```bash
onlyoffice/assets/document-formats/onlyoffice-docs-formats.json
```

Kalau file tersebut tidak ada, daftar format `.docx`, `.xlsx`, `.pptx` tidak akan muncul di setting ONLYOFFICE.

---

## 7. Buat Folder Lokal

Jalankan:

```bash
mkdir -p files db redis

mkdir -p data/onlyoffice/document_data
mkdir -p data/onlyoffice/document_log
mkdir -p data/onlyoffice/document_lib
mkdir -p data/onlyoffice/document_db

sudo chown -R $USER:$USER files db redis data onlyoffice
chmod +x run.sh
```

---

## 8. Jalankan Docker Compose

Jalankan:

```bash
docker compose up -d --force-recreate
```

Lihat status container:

```bash
docker compose ps
```

Pastikan status container seperti ini:

```text
db                         healthy
redis                      healthy
app-server                 Up
nginx-server               Up
onlyoffice-document-server Up
```

Lihat log ownCloud:

```bash
docker compose logs -f app
```

Tunggu sampai muncul:

```text
=== ownCloud is installed and ready ===
=== Ready. Showing ownCloud log ===
```

---

## 9. Cek Healthcheck ONLYOFFICE

Cek dari host/browser:

```bash
curl http://localhost/ds-vpath/healthcheck
```

Output yang benar:

```text
true
```

Cek dari container ownCloud ke ONLYOFFICE:

```bash
docker compose exec app curl -s http://onlyoffice-document-server/healthcheck
```

Output yang benar:

```text
true
```

Cek dari container nginx ke ONLYOFFICE:

```bash
docker compose exec nginx curl -sS http://onlyoffice-document-server/healthcheck
```

Output yang benar:

```text
true
```

---

## 10. Cek App ONLYOFFICE di ownCloud

Jalankan:

```bash
docker compose exec app occ app:list | grep -i onlyoffice
```

Output yang benar:

```text
- onlyoffice:
  - Path: /var/www/owncloud/custom/onlyoffice
```

Cek config:

```bash
docker compose exec app occ config:app:get onlyoffice DocumentServerUrl
docker compose exec app occ config:app:get onlyoffice DocumentServerInternalUrl
docker compose exec app occ config:app:get onlyoffice StorageUrl
```

Output yang benar:

```text
/ds-vpath/
http://onlyoffice-document-server/
http://nginx-server/
```

---

## 11. Cek Format ONLYOFFICE

Jalankan:

```bash
docker compose exec app bash -lc "curl -s -u admin:password http://127.0.0.1:8080/apps/onlyoffice/ajax/settings | head -c 1000"
```

Output yang salah:

```json
{"formats":[]}
```

Kalau output masih seperti itu, berarti connector belum lengkap karena submodule belum ikut ter-clone.

Output yang benar harus berisi format seperti:

```json
"docx"
"xlsx"
"pptx"
```

---

## 12. Setting ONLYOFFICE dari UI ownCloud

Buka browser:

```text
http://localhost/settings/admin?sectionid=additional
```

Pastikan masuk ke:

```text
Admin > Additional
```

Bukan:

```text
Personal > Additional
```

Isi bagian **Server settings**:

```text
ONLYOFFICE Docs address:
/ds-vpath/

Secret key:
secret

Authorization header:
Authorization

ONLYOFFICE Docs address for internal requests from the server:
http://onlyoffice-document-server/

Server address for internal requests from ONLYOFFICE Docs:
http://nginx-server/
```

Klik **Save**.

---

## 13. Aktifkan Default Format

Masih di halaman:

```text
Admin > Additional > ONLYOFFICE
```

Scroll ke bagian:

```text
Common settings
The default application for opening the format
```

Centang minimal format berikut:

```text
docx
xlsx
pptx
```

Boleh juga centang format lain sesuai kebutuhan.

Pada bagian:

```text
Open the file for editing
```

Boleh centang format seperti:

```text
txt
csv
```

Lalu klik **Save** di bagian bawah Common settings.

---

## 14. Test Buka File Word

Upload file `.docx` ke ownCloud.

Lalu klik file tersebut.

Kalau benar, file akan terbuka di editor ONLYOFFICE, bukan download ke komputer lokal.

URL-nya kira-kira akan seperti ini:

```text
http://localhost/apps/onlyoffice/...
```

---

## 15. Troubleshooting

### A. File masih download ke komputer lokal

Penyebab umum:

1. Format `docx` belum dicentang di **The default application for opening the format**.
2. Connector belum lengkap karena clone tanpa submodule.
3. Browser masih menyimpan cache lama.

Solusi:

```bash
docker compose exec app bash -lc "curl -s -u admin:password http://127.0.0.1:8080/apps/onlyoffice/ajax/settings | head -c 1000"
```

Kalau masih:

```json
{"formats":[]}
```

Clone ulang connector dengan submodule:

```bash
docker compose down --remove-orphans

rm -rf onlyoffice

git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice

cd onlyoffice
git submodule update --init --recursive
cd ..

docker compose up -d --force-recreate
```

Lalu refresh browser dengan:

```text
Ctrl + F5
```

---

### B. `/ds-vpath/healthcheck` menghasilkan 502 Bad Gateway

Cek dari dalam nginx:

```bash
docker compose exec nginx curl -sS http://onlyoffice-document-server/healthcheck
```

Kalau hasilnya `true`, restart nginx:

```bash
docker compose restart nginx
```

Kalau masih gagal, restart ONLYOFFICE dan tunggu 1-3 menit:

```bash
docker compose restart onlyoffice-document-server
sleep 60
docker compose restart nginx
curl http://localhost/ds-vpath/healthcheck
```

Output yang benar:

```text
true
```

---

### C. Error `Device or resource busy`

Error:

```bash
rm: cannot remove '/var/www/owncloud/custom/onlyoffice': Device or resource busy
```

Penyebab:

```yaml
./onlyoffice:/var/www/owncloud/custom/onlyoffice
```

Jangan mount connector langsung ke folder custom ownCloud.

Gunakan:

```yaml
./onlyoffice:/tmp/onlyoffice:ro
```

Lalu biarkan `run.sh` copy connector ke:

```text
/var/www/owncloud/custom/onlyoffice
```

---

### D. Warning `There were problems with the code integrity check`

Ini muncul karena connector dipasang manual dari GitHub/copy folder, bukan dari signed Marketplace package.

Untuk lokal/development biasanya tidak fatal.

Kalau ingin bersih untuk production, install connector dari ownCloud Marketplace atau release resmi ONLYOFFICE.

---

### E. Command `onlyoffice:documentserver --check` tidak ada

Di ownCloud, command berikut bisa saja tidak tersedia:

```bash
docker compose exec app occ onlyoffice:documentserver --check
```

Jangan jadikan command itu patokan utama.

Gunakan pengecekan berikut:

```bash
curl http://localhost/ds-vpath/healthcheck
docker compose exec app curl -s http://onlyoffice-document-server/healthcheck
docker compose exec app occ app:list | grep -i onlyoffice
```

---

## 16. Command Reset Total

Kalau ingin install ulang dari nol, backup dulu data lama:

```bash
docker compose down --remove-orphans

mkdir -p backup-before-clean

sudo mv files backup-before-clean/files 2>/dev/null || true
sudo mv db backup-before-clean/db 2>/dev/null || true
sudo mv redis backup-before-clean/redis 2>/dev/null || true
sudo mv data backup-before-clean/data 2>/dev/null || true

mkdir -p files db redis
mkdir -p data/onlyoffice/document_data
mkdir -p data/onlyoffice/document_log
mkdir -p data/onlyoffice/document_lib
mkdir -p data/onlyoffice/document_db

rm -rf onlyoffice
git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice

cd onlyoffice
git submodule update --init --recursive
cd ..

chmod +x run.sh

docker compose up -d --force-recreate
docker compose logs -f app
```

---

## 17. Ringkasan Command Cepat

```bash
git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice

mkdir -p files db redis
mkdir -p data/onlyoffice/document_data
mkdir -p data/onlyoffice/document_log
mkdir -p data/onlyoffice/document_lib
mkdir -p data/onlyoffice/document_db

chmod +x run.sh

docker compose up -d --force-recreate

curl http://localhost/ds-vpath/healthcheck

docker compose exec app bash -lc "curl -s -u admin:password http://127.0.0.1:8080/apps/onlyoffice/ajax/settings | head -c 1000"
```

Kalau `healthcheck` menghasilkan `true` dan `ajax/settings` menampilkan daftar format, maka instalasi sudah benar.

---

## 18. Hasil Akhir yang Diharapkan

Setelah semua langkah benar:

- ownCloud bisa dibuka di `http://localhost`
- ONLYOFFICE bisa dicek di `http://localhost/ds-vpath/healthcheck`
- Output healthcheck adalah `true`
- Menu setting ONLYOFFICE muncul di `Admin > Additional`
- Daftar format `docx`, `xlsx`, dan `pptx` muncul
- File `.docx` tidak download lagi
- File `.docx` langsung terbuka di editor ONLYOFFICE
