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
  python3 - <<'PY' <<< "$body" >/dev/null 2>&1
import json, sys
json.load(sys.stdin)
PY
  if [ $? -ne 0 ]; then
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
  echo "Backup individual completado: $BACKUP_DIR/${WORKFLOW_ID}.json"
  exit 0
fi

# Trae todos los workflows
workflows_json="$(request_json "$N8N_BASE_URL/api/v1/workflows")"
echo "$workflows_json" > "$BACKUP_DIR/_workflows_index.json"

ids_file="$BACKUP_DIR/_workflow_ids.txt"
python3 - <<'PY' > "$ids_file"
import json, sys
data = json.load(sys.stdin)
for wf in data.get("data", []):
    wf_id = wf.get("id")
    if wf_id:
        print(wf_id)
PY
<<< "$workflows_json"

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
