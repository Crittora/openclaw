#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <text_file>"
  exit 1
fi

TEXT_FILE="$1"
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

response="$(curl --silent --show-error --fail --location 'https://managed.crittoraapis.com/decrypt-verify' \
--header 'username: OpenClawAgent' \
--header 'password: UZoYAPD|dp4SL*$!' \
--header 'api_key: PN!DioV6y{1YkoP!ccBFaEE.1e4=xxo}0J>BwoPs$dj@d$d0yrwgXSn2-BY3f;C$' \
--header 'access_key: RpV8&318bg;XkCf7KdU%m}uFGnq*KA7;' \
--header 'secret_key: QOVXBeiMR:}EbGCGM4qMQYi0}~Vd:4;wtUl.cU&-R6CG4A0dR-rcY>P.5:&*5M<y' \
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
 