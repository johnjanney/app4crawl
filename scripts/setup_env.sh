#!/usr/bin/env bash
#
# setup_env.sh — Create the App4Crawl managed venv and install Crawl4AI.
#
# Mirrors the onboarding install flow (PROJECTBRIEF §4). Streams progress to
# stdout so the onboarding log view can display live output. Used by
# ServerManager / the install flow in Phase 3.
#
# Steps:
#   1. python3 -m venv ~/.app4crawl/venv
#   2. pip install -U crawl4ai
#   3. crawl4ai-setup     (installs Playwright + Chromium)
#   4. crawl4ai-doctor    (verification)

set -euo pipefail

APP_HOME="${HOME}/.app4crawl"
VENV_DIR="${APP_HOME}/venv"
LOG_DIR="${APP_HOME}/logs"
CONFIG_DIR="${APP_HOME}/config"
VENV_PY="${VENV_DIR}/bin/python"
VENV_PIP="${VENV_DIR}/bin/pip"

log() { printf '==> %s\n' "$*"; }

mkdir -p "${APP_HOME}" "${LOG_DIR}" "${CONFIG_DIR}"

log "Creating virtual environment at ${VENV_DIR}"
python3 -m venv "${VENV_DIR}"

log "Upgrading pip"
"${VENV_PY}" -m pip install --upgrade pip

log "Installing Crawl4AI"
"${VENV_PIP}" install -U crawl4ai

log "Installing Playwright + Chromium (crawl4ai-setup)"
"${VENV_DIR}/bin/crawl4ai-setup"

log "Verifying installation (crawl4ai-doctor)"
"${VENV_DIR}/bin/crawl4ai-doctor"

log "Done."
