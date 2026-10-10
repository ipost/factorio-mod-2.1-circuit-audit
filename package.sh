#!/usr/bin/env bash
set -euo pipefail

mod_dir="src"
version=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$mod_dir/info.json")
zip_name="mod.zip"

rm -f "$zip_name"
(cd "$mod_dir" && zip -r "../$zip_name" .)

echo "Created $zip_name"