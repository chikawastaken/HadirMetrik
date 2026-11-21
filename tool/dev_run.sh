#!/usr/bin/env bash
# Runs the app against the local Laravel backend on any network.
#
# `adb reverse` maps the device's 127.0.0.1:8000 to this computer, so the app
# keeps using its default http://127.0.0.1:8000/api/v1 even when the phone
# moves between campus Wi-Fi, a friend's network, USB, or wireless debugging.
#
# Usage:
#   tool/dev_run.sh
#   ANDROID_SERIAL=192.168.18.126:37215 tool/dev_run.sh -d 192.168.18.126:37215
#
# Requires the Laravel server to listen on all interfaces:
#   php artisan serve --host=0.0.0.0 --port=8000
set -euo pipefail

PORT="${PORT:-8000}"

if [[ -z "${ANDROID_SERIAL:-}" ]]; then
  count="$(adb devices | awk 'NR>1 && $2=="device" {c++} END {print c+0}')"
  if [[ "${count}" -gt 1 ]]; then
    echo "More than one device is connected. Pick one with ANDROID_SERIAL:" >&2
    adb devices -l >&2
    exit 1
  fi
fi

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  adb -s "${ANDROID_SERIAL}" reverse "tcp:${PORT}" "tcp:${PORT}"
else
  adb reverse "tcp:${PORT}" "tcp:${PORT}"
fi

exec flutter run "$@"
