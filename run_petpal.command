#!/bin/bash
set -e
cd "$(dirname "$0")"
PETPAL_SDK="../../work/sdk/flutter/bin/flutter"
if [ ! -x "$PETPAL_SDK" ]; then
  PETPAL_SDK="flutter"
fi
export XDG_CONFIG_HOME="$PWD/.dart_tool/tool-config"
export ANALYZER_STATE_LOCATION_OVERRIDE="$PWD/.dart_tool/analyzer"
export CI=true
"$PETPAL_SDK" pub get
printf '\nOpen http://localhost:8080 after Flutter finishes starting.\n\n'
"$PETPAL_SDK" run -d web-server --web-hostname 127.0.0.1 --web-port 8080
