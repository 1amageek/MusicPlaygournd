#!/bin/zsh
set -euo pipefail

# The public SwiftMusic pin omits an iOS floor; apply the runtime floor to every package target.
ipad_repo_root="${0:A:h:h}"
ipad_action="${1:-build}"
if (( $# > 0 )); then shift; fi
case "$ipad_action" in
    build|test|build-for-testing|test-without-building) ;;
    *) print -u2 'Usage: build-ipad.sh [build|test|build-for-testing|test-without-building] [xcodebuild options]'; exit 2 ;;
esac
exec python3 - "$ipad_repo_root" "$ipad_action" "$@" <<'PY'
import os
import signal
import subprocess
import sys

repo, action, *extra = sys.argv[1:]
command = [
    'xcodebuild', action,
    '-project', repo + '/MusicPlayground/MusicPlayground.xcodeproj',
    '-scheme', 'MusicPlayground',
    '-configuration', 'Debug',
    '-destination', os.environ.get('IPAD_DESTINATION', 'generic/platform=iOS'),
    '-derivedDataPath', os.environ.get('IPAD_DERIVED_DATA', repo + '/.build/iPad'),
    'TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault',
    'IPHONEOS_DEPLOYMENT_TARGET=27.0',
    *extra,
]
process = subprocess.Popen(command, start_new_session=True)
try:
    status = process.wait(timeout=int(os.environ.get('IPAD_BUILD_TIMEOUT', '300')))
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    print('iPad build/test exceeded its timeout.', file=sys.stderr)
    sys.exit(124)
sys.exit(status)
PY
