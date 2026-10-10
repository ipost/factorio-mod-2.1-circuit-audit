#!/usr/bin/env bash
set -euo pipefail

mod_dir="src"
mod_name=$(grep -oP '"name"\s*:\s*"\K[^"]+' "$mod_dir/info.json")
version=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$mod_dir/info.json")
package_dir="${mod_name}_${version}"
zip_name="${package_dir}.zip"

rm -rf "$package_dir" "$zip_name"
mkdir "$package_dir"
cp -a "$mod_dir/." "$package_dir/"
rm -rf "$package_dir/.git"

zip -r "$zip_name" "$package_dir"
rm -rf "$package_dir"

echo "Created $zip_name"