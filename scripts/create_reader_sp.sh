#!/usr/bin/env bash
# Creates the reader service principal (not an admin) and a 7-day OAuth secret,
# then writes .env without printing the secret.
# Usage: PROFILE=FREE WAREHOUSE_ID=<id> bash scripts/create_reader_sp.sh
set -euo pipefail
PROFILE=${PROFILE:-FREE}
cd "$(dirname "$0")/.."
umask 077

HOST=$(databricks --profile "$PROFILE" auth describe -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["details"]["host"].rstrip("/"))')
WS_ID=$(databricks --profile "$PROFILE" api get /api/2.1/unity-catalog/current-metastore-assignment | python3 -c 'import json,sys; print(json.load(sys.stdin)["workspace_id"])')
if [[ -n "${SP_ID:-}" && -n "${APP_ID:-}" ]]; then
  echo "reusing existing service principal"
else
  SP=$(databricks --profile "$PROFILE" service-principals create --display-name sp-xabac-reader -o json)
  SP_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$SP")
  APP_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["applicationId"])' <<<"$SP")
fi
echo "service principal: id=$SP_ID applicationId=$APP_ID"

databricks --profile "$PROFILE" api post \
  "/api/2.0/accounts/servicePrincipals/$SP_ID/credentials/secrets" \
  --json '{"lifetime":"604800s"}' \
| python3 -c '
import json, sys
d = json.load(sys.stdin)
host, ws, wh, app, sp_id = sys.argv[1:6]
if "secret" not in d:
    sys.exit("secret not created: " + str({k: v for k, v in d.items() if k != "secret"}))
with open(".env", "w") as f:
    f.write(f"DATABRICKS_HOST={host}\nDATABRICKS_WORKSPACE_ID={ws}\nDATABRICKS_WAREHOUSE_ID={wh}\n")
    secret = d["secret"]
    f.write(f"DATABRICKS_CLIENT_ID={app}\nDATABRICKS_CLIENT_SECRET={secret}\nREADER_SP_ID={sp_id}\n")
print("credentials written to .env, secret expires", d.get("expire_time"))
' "$HOST" "$WS_ID" "${WAREHOUSE_ID:?set WAREHOUSE_ID}" "$APP_ID" "$SP_ID"
