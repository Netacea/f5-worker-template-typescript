#!/bin/bash
set -euxo pipefail

# Clean-up in prepartion for bundling
rm -rf NetaceaF5-v*.tar.gz ./dist/
mkdir -p ./dist/extensions/netacea
mkdir -p ./dist/rules/

# Copy assets
cp ./src/version ./src/node_version ./dist/
cp ./rules/netacea_mitigate.tcl ./dist/rules/
cp ./package.json ./src/NetaceaConfig.json ./dist/extensions/netacea/

# Perform rollup
npx rollup -c rollup.config.mjs

# Create the zip
chmod -R 777 ./dist/
version=$(npm list @netacea/f5\
  | grep '@netacea/f5'\
  | sed 's/.*netacea\/f5@//')
tar -czvf ./NetaceaF5-v$version.tar.gz -C ./dist .
