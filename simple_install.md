# Simple Install ownCloud + ONLYOFFICE Docker

Panduan singkat ini untuk install ulang ownCloud + ONLYOFFICE Docs di device/server lain.

---

## 1. Clone Project

```bash
git clone https://github.com/arhan321/docker-onlyoffice-owncloud.git owncloud_config
cd owncloud_config
```

Kalau folder project sudah ada, cukup masuk ke foldernya:

```bash
cd owncloud_config
```

---

## 2. Buat File `.env`

```bash
nano .env
```

Isi:

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

Kalau pakai domain, ganti `localhost` menjadi domain kamu.

---

## 3. Clone Connector ONLYOFFICE

PENTING: wajib pakai `--recurse-submodules`.

```bash
rm -rf onlyoffice

git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice

cd onlyoffice
git submodule update --init --recursive
cd ..
```

Cek file formatnya:

```bash
ls -lah onlyoffice/assets/document-formats/onlyoffice-docs-formats.json
```

Kalau file itu ada, berarti aman.

---

## 4. Buat Folder Data Lokal

```bash
mkdir -p files db redis
mkdir -p data/onlyoffice/document_data
mkdir -p data/onlyoffice/document_log
mkdir -p data/onlyoffice/document_lib
mkdir -p data/onlyoffice/document_db

chmod +x run.sh
```

---

## 5. Jalankan Docker

```bash
docker compose down --remove-orphans
docker compose up -d --force-recreate
```

Cek container:

```bash
docker compose ps
```

Pastikan container ini `Up` atau `Healthy`:

```text
db
redis
app-server
nginx-server
onlyoffice-document-server
```

---

## 6. Cek ONLYOFFICE Healthcheck

```bash
curl http://localhost/ds-vpath/healthcheck
```

Output harus:

```text
true
```

Cek dari container ownCloud:

```bash
docker compose exec app curl -s http://onlyoffice-document-server/healthcheck
```

Output harus:

```text
true
```

---

## 7. Cek App ONLYOFFICE

```bash
docker compose exec app occ app:list | grep -i onlyoffice
```

Output harus ada:

```text
- onlyoffice:
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

## 8. Cek Format Document

```bash
docker compose exec app bash -lc "curl -s -u admin:password http://127.0.0.1:8080/apps/onlyoffice/ajax/settings | head -c 1000"
```

Kalau benar, output akan berisi format seperti:

```text
docx
xlsx
pptx
```

Kalau output masih:

```json
{"formats":[]}
```

berarti connector ONLYOFFICE salah clone. Ulangi langkah nomor 3.

---

## 9. Setting dari UI ownCloud

Buka:

```text
http://localhost/settings/admin?sectionid=additional
```

Pastikan masuk ke:

```text
Admin > Additional > ONLYOFFICE
```

Isi:

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

## 10. Aktifkan Format Default

Masih di halaman ONLYOFFICE, scroll ke:

```text
Common settings
```

Pada bagian:

```text
The default application for opening the format
```

Centang minimal:

```text
docx
xlsx
pptx
```

Lalu klik **Save**.

---

## 11. Test

Upload file `.docx`, lalu klik file tersebut.

Kalau benar, file akan terbuka di ONLYOFFICE, bukan download ke komputer lokal.

---

## Troubleshooting Cepat

### File masih download

Cek format:

```bash
docker compose exec app bash -lc "curl -s -u admin:password http://127.0.0.1:8080/apps/onlyoffice/ajax/settings | head -c 1000"
```

Kalau `formats` kosong, clone ulang ONLYOFFICE pakai submodule:

```bash
docker compose down --remove-orphans
rm -rf onlyoffice
git clone --depth 1 --recurse-submodules https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice
cd onlyoffice
git submodule update --init --recursive
cd ..
docker compose up -d --force-recreate
```

### Healthcheck 502

```bash
docker compose restart onlyoffice-document-server
sleep 60
docker compose restart nginx
curl http://localhost/ds-vpath/healthcheck
```

### Reset total dari nol

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
```
