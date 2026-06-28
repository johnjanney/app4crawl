#!/usr/bin/env bash
#
# check_env.sh — Detect the App4Crawl Python / Crawl4AI environment.
#
# Detection order (per PROJECTBRIEF §3):
#   1. App4Crawl-managed venv at ~/.app4crawl/venv
#   2. System python3 with crawl4ai importable
#
# Prints a JSON object describing what was found and exits 0 if a usable
# Crawl4AI environment exists, 1 otherwise. Used by EnvironmentChecker.swift.

set -euo pipefail

APP_HOME="${HOME}/.app4crawl"
VENV_DIR="${APP_HOME}/venv"
VENV_PY="${VENV_DIR}/bin/python"
MIN_PY_MAJOR=3
MIN_PY_MINOR=10

emit() {
  # $1 found(true/false)  $2 source  $3 python_version  $4 crawl4ai_version
  printf '{"found":%s,"source":"%s","python":"%s","crawl4ai":"%s"}\n' \
    "$1" "$2" "$3" "$4"
}

check_python() {
  # Echoes the python version (e.g. 3.11.5) if >= minimum, else empty.
  local py="$1"
  "$py" -c "import sys; v=sys.version_info; print('%d.%d.%d'%v[:3]) if (v[0],v[1])>=(${MIN_PY_MAJOR},${MIN_PY_MINOR}) else sys.exit(1)" 2>/dev/null || true
}

crawl4ai_version() {
  local py="$1"
  "$py" -c "import crawl4ai; print(getattr(crawl4ai,'__version__','unknown'))" 2>/dev/null || true
}

# 1. Managed venv.
if [[ -x "${VENV_PY}" ]]; then
  pyver="$(check_python "${VENV_PY}")"
  c4ai="$(crawl4ai_version "${VENV_PY}")"
  if [[ -n "${c4ai}" ]]; then
    emit true managed-venv "${pyver}" "${c4ai}"
    exit 0
  fi
fi

# 2. System python3.
if command -v python3 >/dev/null 2>&1; then
  pyver="$(check_python python3)"
  c4ai="$(crawl4ai_version python3)"
  if [[ -n "${c4ai}" ]]; then
    emit true system-python "${pyver}" "${c4ai}"
    exit 0
  fi
  # Python present but Crawl4AI missing.
  emit false none "${pyver}" ""
  exit 1
fi

emit false none "" ""
exit 1
