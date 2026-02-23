#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <text_file>"
  exit 1
fi

TEXT_FILE="$1"
ENV_FILE="${CRITTORA_ENV_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/crittora-secure-config.env}"
OPENCLAW_CONFIG="/home/node/.openclaw/openclaw.json"

if [[ ! -f "$TEXT_FILE" ]]; then
  echo "Error: file not found: $TEXT_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed."
  exit 1
fi

if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
  echo "Error: config file not found: $OPENCLAW_CONFIG"
  exit 1
fi

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace.
    line="${line#"${line%%[!$' \t\r\n']*}"}"
    line="${line%"${line##*[!$' \t\r\n']}"}"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    local key value
    IFS='=' read -r key value <<<"$line"
    key="${key#"${key%%[!$' \t\r\n']*}"}"
    key="${key%"${key##*[!$' \t\r\n']}"}"
    value="${value#"${value%%[!$' \t\r\n']*}"}"
    value="${value%"${value##*[!$' \t\r\n']}"}"

    # Only allow the known keys.
    case "$key" in
      CRITTORA_USERNAME|CRITTORA_PASSWORD|CRITTORA_API_KEY|CRITTORA_ACCESS_KEY|CRITTORA_SECRET_KEY)
        # Strip surrounding quotes if present (single or double).
        if [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
          value="${value:1:-1}"
        elif [[ "${value:0:1}" == "\"" && "${value: -1}" == "\"" ]]; then
          value="${value:1:-1}"
        fi
        export "$key=$value"
        ;;
    esac
  done < "$file"
}

load_env_file "$ENV_FILE"

missing_env=0
for key in CRITTORA_USERNAME CRITTORA_PASSWORD CRITTORA_API_KEY CRITTORA_ACCESS_KEY CRITTORA_SECRET_KEY; do
  if [[ -z "${!key:-}" ]]; then
    echo "Error: missing env var: $key"
    missing_env=1
  fi
done
if [[ "$missing_env" -ne 0 ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: env file not found: $ENV_FILE"
  fi
  exit 1
fi

response="$(curl --silent --show-error --fail --location 'https://managed.crittoraapis.com/decrypt-verify' \
--header "username: ${CRITTORA_USERNAME}" \
--header "password: ${CRITTORA_PASSWORD}" \
--header "api_key: ${CRITTORA_API_KEY}" \
--header "access_key: ${CRITTORA_ACCESS_KEY}" \
--header "secret_key: ${CRITTORA_SECRET_KEY}" \
--header 'Content-Type: application/json' \
  --data-binary "@$TEXT_FILE")"

tmp_file="$(mktemp)"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

if ! jq -e '.decrypted_data' >/dev/null 2>&1 <<<"$response"; then
  echo "Error: response missing decrypted_data"
  echo "$response"
  exit 1
fi

jq \
  --argjson api "$response" \
  '.agents.list = ($api.decrypted_data.list // $api.decrypted_data)' \
  "$OPENCLAW_CONFIG" > "$tmp_file"

mv "$tmp_file" "$OPENCLAW_CONFIG"
trap - EXIT

echo "Updated $OPENCLAW_CONFIG: agents.list replaced from decrypted_data."
 
