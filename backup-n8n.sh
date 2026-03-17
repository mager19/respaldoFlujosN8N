#!/usr/bin/env bash
set -euo pipefail

if [ -f ".env.local" ]; then
  set -a
  . ./.env.local
  set +a
fi

# ---- Configura estas variables ----
N8N_BASE_URL="${N8N_BASE_URL:-https://simianlab.app.n8n.cloud}"
BACKUP_DIR="workflows"
# -----------------------------------

N8N_API_KEY="${N8N_API_KEY:-}"

if [ -z "$N8N_API_KEY" ]; then
  echo "Falta N8N_API_KEY."
  echo "1. Crea .env.local desde .env.example"
  echo "2. Agrega N8N_API_KEY y N8N_BASE_URL en .env.local"
  echo "3. No subas .env.local a git"
  exit 1
fi

N8N_BASE_URL="${N8N_BASE_URL%/}"
WORKFLOW_ID="${1:-}"

write_manifest_for_single() {
  local workflow_json="$1"
  local manifest_tmp
  manifest_tmp="$BACKUP_DIR/.manifest.tmp"
  WORKFLOW_JSON="$workflow_json" N8N_BASE_URL="$N8N_BASE_URL" BACKUP_DIR="$BACKUP_DIR" python3 - <<'PY' > "$manifest_tmp"
import json
import os
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

wf = json.loads(os.environ["WORKFLOW_JSON"])
workflow_id = wf.get("id")
manifest_path = os.path.join(os.environ["BACKUP_DIR"], "manifest.json")

def format_dt(value):
    if not value:
        return None
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return dt.astimezone(ZoneInfo("America/Bogota")).strftime("%d/%m/%Y:%H:%M")

existing = {"workflows": []}
if os.path.exists(manifest_path):
    try:
        with open(manifest_path, "r", encoding="utf-8") as fh:
            existing = json.load(fh)
    except Exception:
        existing = {"workflows": []}

workflows = existing.get("workflows", [])
entry = {
    "id": workflow_id,
    "name": wf.get("name"),
    "updatedAt": format_dt(wf.get("updatedAt")),
    "file": f"{os.environ['BACKUP_DIR']}/{workflow_id}.json",
}

replaced = False
for index, item in enumerate(workflows):
    if item.get("id") == workflow_id:
        workflows[index] = entry
        replaced = True
        break

if not replaced:
    workflows.append(entry)

workflows.sort(key=lambda item: (item.get("name") or "", item.get("id") or ""))

manifest = {
    "backupGeneratedAt": datetime.now(timezone.utc).astimezone(ZoneInfo("America/Bogota")).strftime("%d/%m/%Y:%H:%M"),
    "baseUrl": os.environ["N8N_BASE_URL"],
    "timezone": "America/Bogota",
    "workflowCount": len(workflows),
    "workflows": workflows,
}
json.dump(manifest, sys.stdout, ensure_ascii=True, indent=2)
PY
  mv "$manifest_tmp" "$BACKUP_DIR/manifest.json"
}

write_manifest_for_all() {
  local workflows_json="$1"
  local manifest_tmp
  manifest_tmp="$BACKUP_DIR/.manifest.tmp"
  WORKFLOWS_JSON="$workflows_json" N8N_BASE_URL="$N8N_BASE_URL" BACKUP_DIR="$BACKUP_DIR" python3 - <<'PY' > "$manifest_tmp"
import json
import os
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

data = json.loads(os.environ["WORKFLOWS_JSON"])

def format_dt(value):
    if not value:
        return None
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return dt.astimezone(ZoneInfo("America/Bogota")).strftime("%d/%m/%Y:%H:%M")

workflows = []
for wf in data.get("data", []):
    workflow_id = wf.get("id")
    if not workflow_id:
        continue
    workflows.append(
        {
            "id": workflow_id,
            "name": wf.get("name"),
            "updatedAt": format_dt(wf.get("updatedAt")),
            "file": f"{os.environ['BACKUP_DIR']}/{workflow_id}.json",
        }
    )

workflows.sort(key=lambda item: (item.get("name") or "", item.get("id") or ""))

manifest = {
    "backupGeneratedAt": datetime.now(timezone.utc).astimezone(ZoneInfo("America/Bogota")).strftime("%d/%m/%Y:%H:%M"),
    "baseUrl": os.environ["N8N_BASE_URL"],
    "timezone": "America/Bogota",
    "workflowCount": len(workflows),
    "workflows": workflows,
}
json.dump(manifest, sys.stdout, ensure_ascii=True, indent=2)
PY
  mv "$manifest_tmp" "$BACKUP_DIR/manifest.json"
}

if [[ "$N8N_BASE_URL" == *"TU_SUBDOMINIO"* ]]; then
  echo "Falta N8N_BASE_URL. Edita el script y pon tu subdominio real."
  exit 1
fi

request_json() {
  local url="$1"
  local response
  local status
  local body
  response=$(curl -sS -H "X-N8N-API-KEY: $N8N_API_KEY" -w "\n%{http_code}" "$url")
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [ "$status" != "200" ]; then
    echo "HTTP $status al llamar $url"
    echo "$body"
    exit 1
  fi
  if [ -z "$body" ]; then
    echo "Respuesta vacia al llamar $url"
    exit 1
  fi
  if ! printf '%s' "$body" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    echo "Respuesta no JSON al llamar $url"
    echo "$body"
    exit 1
  fi
  echo "$body"
}

mkdir -p "$BACKUP_DIR"
if [ -n "$WORKFLOW_ID" ]; then
  wf_json="$(request_json "$N8N_BASE_URL/api/v1/workflows/$WORKFLOW_ID")"
  printf '%s' "$wf_json" > "$BACKUP_DIR/${WORKFLOW_ID}.json"
  write_manifest_for_single "$wf_json"
  echo "Backup individual completado: $BACKUP_DIR/${WORKFLOW_ID}.json"
  exit 0
fi

# Trae todos los workflows
workflows_json="$(request_json "$N8N_BASE_URL/api/v1/workflows")"
echo "$workflows_json" > "$BACKUP_DIR/_workflows_index.json"
write_manifest_for_all "$workflows_json"

ids_file="$BACKUP_DIR/_workflow_ids.txt"
printf '%s' "$workflows_json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for wf in data.get("data", []):
    wf_id = wf.get("id")
    if wf_id:
        print(wf_id)
' > "$ids_file"

count=$(wc -l < "$ids_file" | tr -d ' ')
echo "Workflows encontrados: $count"

if [ ! -s "$ids_file" ]; then
  echo "No se encontraron workflows."
  exit 0
fi

files_written=0
while IFS= read -r id; do
  if [ -z "$id" ]; then
    continue
  fi
  wf_json="$(request_json "$N8N_BASE_URL/api/v1/workflows/$id")"
  printf '%s' "$wf_json" > "$BACKUP_DIR/${id}.json"
  files_written=$((files_written + 1))
done < "$ids_file"

if [ "$files_written" -eq 0 ]; then
  echo "No se escribieron archivos."
  exit 1
fi

echo "Backup local completado en $BACKUP_DIR"
