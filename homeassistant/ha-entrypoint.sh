#!/bin/sh
# Wrapper: export Docker secrets as env vars before starting Home Assistant
# Prevents credentials from leaking via `docker inspect`

if [ -f /run/secrets/RECORDER_DB_URL ]; then
  export RECORDER_DB_URL="$(cat /run/secrets/RECORDER_DB_URL)"
fi

exec /init
