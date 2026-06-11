#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <manifest.json> <ed25519-private-key.pem> <envelope.json>" >&2
  exit 2
fi

manifest="$1"
private_key="$2"
output="$3"
signature_file="$(mktemp)"
trap 'rm -f "$signature_file"' EXIT

openssl pkeyutl -sign -rawin -inkey "$private_key" \
  -in "$manifest" -out "$signature_file"

python3 - "$manifest" "$signature_file" "$output" <<'PY'
import base64
import json
import pathlib
import sys

manifest, signature, output = map(pathlib.Path, sys.argv[1:])
envelope = {
    "payload": base64.b64encode(manifest.read_bytes()).decode("ascii"),
    "signature": base64.b64encode(signature.read_bytes()).decode("ascii"),
}
output.write_text(json.dumps(envelope, separators=(",", ":")) + "\n")
PY
