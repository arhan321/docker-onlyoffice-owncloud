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
  echo "rm -rf onlyoffice && git clone --depth 1 https://github.com/ONLYOFFICE/onlyoffice-owncloud.git onlyoffice"
else
  rm -rf /var/www/owncloud/custom/onlyoffice || true
  mkdir -p /var/www/owncloud/custom
  cp -a /tmp/onlyoffice /var/www/owncloud/custom/onlyoffice
  chown -R www-data:www-data /var/www/owncloud/custom/onlyoffice || true

  echo "=== Available app commands ==="
  occ --no-warnings list app || true

  echo "=== Enabling ONLYOFFICE app ==="
  if occ --no-warnings --no-interaction app:enable onlyoffice; then
    echo "ONLYOFFICE app enabled."
  else
    echo "WARNING: app:enable failed. ownCloud tetap dijalankan."
    echo "Nanti coba enable manual dari UI: Settings > Admin > Apps > Disabled apps > ONLYOFFICE > Enable."
  fi

  echo "=== Setting ONLYOFFICE connector config ==="
  occ --no-warnings --no-interaction config:app:set onlyoffice DocumentServerUrl --value="/ds-vpath/" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice DocumentServerInternalUrl --value="http://onlyoffice-document-server/" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice StorageUrl --value="http://nginx-server/" || true
  occ --no-warnings --no-interaction config:app:set onlyoffice jwt_secret --value="${ONLYOFFICE_JWT_SECRET:-secret}" || true
fi

echo "=== Ready. Showing ownCloud log ==="
tail -f /tmp/server.log
