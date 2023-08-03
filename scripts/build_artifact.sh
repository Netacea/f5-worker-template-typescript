#!/bin/bash
set -euxo pipefail
chmod -R 777 ./dist/
version=$(npm list @netacea/f5\
  | grep '@netacea/f5'\
  | sed 's/.*netacea\/f5@//')
tar -czvf ./NetaceaF5-v$version.tar.gz -C ./dist .
