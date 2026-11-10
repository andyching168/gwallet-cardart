#!/usr/bin/env sh
# Build the flashable module zip into dist/
set -e
cd "$(dirname "$0")"
v=$(sed -n 's/^version=//p' module/module.prop)
mkdir -p dist
rm -f "dist/gwallet-cardart-$v.zip"
(cd module && zip -r9 "../dist/gwallet-cardart-$v.zip" . -x '*.DS_Store')
echo "dist/gwallet-cardart-$v.zip"
