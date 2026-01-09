#!/bin/bash
###############################################################################
# Script       : install_java21_corretto.sh
# Purpose      : Install + switch default Java to Amazon Corretto 21 on RHEL 9.x
#                Works behind HTTP proxy for ALL downloads (dnf/yum/curl).
###############################################################################

set -euo pipefail

###############################################################################
# Config
###############################################################################
DEFAULT_PROXY_URL="http://sappaccess.ril.com:8080"   # default proxy
PROXY_URL="${PROXY_URL:-$DEFAULT_PROXY_URL}"         # override via env or --proxy
NO_PROXY_LIST="${NO_PROXY_LIST:-localhost,127.0.0.1,::1}"

LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/java21_install_$(date +%Y%m%d_%H%M%S).log"

# We will AUTO-DETECT Java 21 home after install (do not hardcode)
JAVA21_HOME=""

JAVA8_HOME_CANDIDATES=(
  "/usr/lib/jvm/java-1.8.0-amazon-corretto"
  "/usr/lib/jvm/java-1.8.0-amazon-corretto.x86_64"
  "/usr/lib/jvm/java-1.8.0-amazon-corretto/jre"
  "/usr/lib/jvm/java-1.8.0-amazon-corretto.x86_64/jre"
)

CORRETTO_GPG_KEY_URL="https://yum.corretto.aws/corretto.key"
CORRETTO_REPO_URL="https://yum.corretto.aws/corretto.repo"
CORRETTO_REPO_FILE="/etc/yum.repos.d/corretto.repo"

PKG_MANAGER=""
SUDO=""
JAVA8_INSTALLED=false
JAVA8_HOME_FOUND=""

###############################################################################
# Helpers
###############################################################################
setup_logging() {
  mkdir -p "$LOG_DIR" 2>/dev/null || {
    LOG_DIR="$HOME"
    LOG_FILE="${LOG_DIR}/java21_install_$(date +%Y%m%d_%H%M%S).log"
  }
  touch "$LOG_FILE"
  chmod 640 "$LOG_FILE" || true
  exec > >(tee -a "$LOG_FILE") 2>&1

  echo "============================================================================="
  echo "Amazon Corretto Java 21 Installation Log"
  echo "============================================================================="
  echo "Timestamp  : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Hostname   : $(hostname)"
  echo "OS         : $(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
  echo "Log File   : $LOG_FILE"
  echo "Proxy      : ${PROXY_URL:-<none>}"
  echo "No Proxy   : ${NO_PROXY_LIST}"
  echo "============================================================================="
  echo
}

log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2"; }

error_exit() {
  log_msg "ERROR" "$1"
  log_msg "ERROR" "Installation failed. Check log file: $LOG_FILE"
  exit 1
}

detect_privilege() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
    log_msg "INFO" "Running as root (sudo not required)"
  else
    command -v sudo >/dev/null 2>&1 || error_exit "Not running as root and sudo is not available"
    SUDO="sudo"
    $SUDO -v >/dev/null 2>&1 || error_exit "Sudo privileges are required"
    log_msg "INFO" "Sudo access confirmed"
  fi
}

detect_os() {
  [[ -f /etc/os-release ]] || error_exit "Cannot detect OS: /etc/os-release missing"
  # shellcheck disable=SC1091
  source /etc/os-release
  log_msg "INFO" "OS Detected: ${NAME:-unknown} (${ID:-unknown}) version ${VERSION_ID:-unknown}"
}

detect_package_manager() {
  if command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  else
    error_exit "Neither dnf nor yum found"
  fi
  log_msg "INFO" "Package manager: $PKG_MANAGER"
}

export_proxy_env() {
  if [[ -n "${PROXY_URL:-}" ]]; then
    export http_proxy="$PROXY_URL"
    export https_proxy="$PROXY_URL"
    export HTTP_PROXY="$PROXY_URL"
    export HTTPS_PROXY="$PROXY_URL"
    export no_proxy="$NO_PROXY_LIST"
    export NO_PROXY="$NO_PROXY_LIST"
    log_msg "INFO" "Proxy env exported for this script session"
  else
    log_msg "INFO" "No proxy configured (PROXY_URL empty)"
  fi
}

curl_fetch() {
  local url="$1"
  local dest="$2"

  local curl_args=(-fsSL --retry 5 --retry-delay 2 --connect-timeout 10 --max-time 300)
  if [[ -n "${PROXY_URL:-}" ]]; then
    curl_args+=(--proxy "$PROXY_URL")
  fi

  curl "${curl_args[@]}" -o "$dest" "$url" || error_exit "curl failed for $url"
}

pkg_cmd() {
  if [[ "$PKG_MANAGER" == "dnf" ]]; then
    if [[ -n "${PROXY_URL:-}" ]]; then
      $SUDO dnf --setopt=proxy="$PROXY_URL" "$@"
    else
      $SUDO dnf "$@"
    fi
  else
    if [[ -n "${PROXY_URL:-}" ]]; then
      $SUDO yum --setopt=proxy="$PROXY_URL" "$@"
    else
      $SUDO yum "$@"
    fi
  fi
}

check_existing_java() {
  log_msg "INFO" "Checking for existing Java installations..."

  for p in "${JAVA8_HOME_CANDIDATES[@]}"; do
    if [[ -d "$p" && -x "$p/bin/java" ]]; then
      JAVA8_INSTALLED=true
      JAVA8_HOME_FOUND="$p"
      break
    fi
  done

  if [[ "$JAVA8_INSTALLED" == "true" ]]; then
    log_msg "INFO" "Found Java 8 at: $JAVA8_HOME_FOUND"
    "$JAVA8_HOME_FOUND/bin/java" -version 2>&1 | head -n 1 || true
  else
    log_msg "INFO" "Java 8 not detected in common Corretto paths"
  fi

  if command -v java >/dev/null 2>&1; then
    log_msg "INFO" "Current default 'java -version':"
    java -version 2>&1 | head -n 3 || true
  fi
}

configure_repository() {
  log_msg "INFO" "Configuring Corretto repository..."

  # For RHEL 9: add Corretto repo via proxy-aware curl
  local tmp_key="/tmp/corretto.key.$$"
  local tmp_repo="/tmp/corretto.repo.$$"

  log_msg "INFO" "Downloading Corretto GPG key + repo file via proxy..."
  curl_fetch "$CORRETTO_GPG_KEY_URL" "$tmp_key"
  curl_fetch "$CORRETTO_REPO_URL" "$tmp_repo"

  log_msg "INFO" "Importing GPG key..."
  $SUDO rpm --import "$tmp_key" || error_exit "Failed to import Corretto GPG key"

  log_msg "INFO" "Installing repo file to $CORRETTO_REPO_FILE ..."
  $SUDO install -m 0644 "$tmp_repo" "$CORRETTO_REPO_FILE" || error_exit "Failed to install repo file"

  rm -f "$tmp_key" "$tmp_repo" || true
  log_msg "INFO" "Corretto repository configured at: $CORRETTO_REPO_FILE"
}

install_java() {
  log_msg "INFO" "Cleaning package cache..."
  pkg_cmd clean all >/dev/null 2>&1 || true

  log_msg "INFO" "Installing Amazon Corretto Java 21..."
  pkg_cmd install -y java-21-amazon-corretto-devel || error_exit "Failed to install java-21-amazon-corretto-devel"
  log_msg "INFO" "Java 21 package installation completed"
}

detect_java21_home() {
  # Robust detection for RHEL9 where directory is often versioned:
  # /usr/lib/jvm/java-21-amazon-corretto-21.x.y.../bin/java
  log_msg "INFO" "Detecting installed Corretto 21 JAVA_HOME..."

  local java_path=""

  if rpm -q java-21-amazon-corretto-devel >/dev/null 2>&1; then
    java_path="$(rpm -ql java-21-amazon-corretto-devel | grep -E '/bin/java$' | head -n 1 || true)"
  fi

  if [[ -z "$java_path" ]] && rpm -q java-21-amazon-corretto >/dev/null 2>&1; then
    java_path="$(rpm -ql java-21-amazon-corretto | grep -E '/bin/java$' | head -n 1 || true)"
  fi

  if [[ -z "$java_path" ]]; then
    java_path="$(ls -1 /usr/lib/jvm/java-21-amazon-corretto*/bin/java 2>/dev/null | head -n 1 || true)"
  fi

  [[ -n "$java_path" ]] || error_exit "Could not locate Corretto 21 java binary after install"

  JAVA21_HOME="$(dirname "$(dirname "$java_path")")"
  [[ -d "$JAVA21_HOME" && -x "$JAVA21_HOME/bin/java" ]] || error_exit "Detected JAVA_HOME is invalid: $JAVA21_HOME"

  log_msg "INFO" "Detected Corretto 21 JAVA_HOME: $JAVA21_HOME"
}

verify_installation() {
  log_msg "INFO" "Verifying Java 21 installation..."

  [[ -n "$JAVA21_HOME" ]] || error_exit "JAVA21_HOME is empty (detection failed)"
  [[ -d "$JAVA21_HOME" ]] || error_exit "Java 21 directory not found at $JAVA21_HOME"
  [[ -x "$JAVA21_HOME/bin/java" ]] || error_exit "Java 21 binary not executable at $JAVA21_HOME/bin/java"

  "$JAVA21_HOME/bin/java" -version 2>&1 | grep -qi "corretto" || error_exit "Java 21 verification failed (expected Corretto build)"

  echo
  echo "Java 21 Version Information:"
  echo "----------------------------"
  "$JAVA21_HOME/bin/java" -version
  echo
  log_msg "INFO" "Java 21 verification successful"
}

configure_system_java_home() {
  log_msg "INFO" "Configuring system-wide JAVA_HOME in /etc/profile.d/java21.sh ..."
  $SUDO tee /etc/profile.d/java21.sh >/dev/null <<EOF
# Amazon Corretto Java 21 Environment
# Auto-generated by install_java21_corretto.sh on $(date '+%Y-%m-%d %H:%M:%S')
export JAVA_HOME=${JAVA21_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
  $SUDO chmod 0644 /etc/profile.d/java21.sh || true
  log_msg "INFO" "Created /etc/profile.d/java21.sh"
}

update_user_bashrc() {
  log_msg "INFO" "Updating user .bashrc files (safe + idempotent)..."

  local homes_to_update=("/root")

  while IFS=: read -r _ _ uid _ _ home _; do
    if [[ "$uid" =~ ^[0-9]+$ ]] && [[ "$uid" -ge 1000 ]] && [[ -d "$home" ]]; then
      homes_to_update+=("$home")
    fi
  done < /etc/passwd

  local marker_start="# >>> Java Corretto 21 installer >>>"
  local marker_end="# <<< Java Corretto 21 installer <<<"

  for user_home in "${homes_to_update[@]}"; do
    local bashrc_file="${user_home}/.bashrc"
    [[ -f "$bashrc_file" ]] || { log_msg "INFO" "No .bashrc at $bashrc_file, skipping"; continue; }

    log_msg "INFO" "Processing $bashrc_file ..."

    local backup_ts
    backup_ts="$(date +%Y%m%d_%H%M%S)"
    cp -a "$bashrc_file" "${bashrc_file}.backup.${backup_ts}"
    log_msg "INFO" "Backup created: ${bashrc_file}.backup.${backup_ts}"

    # Remove previous installer block if present
    if grep -qF "$marker_start" "$bashrc_file"; then
      sed -i "/$(printf '%s' "$marker_start" | sed 's/[.[\*^$(){}?+|/]/\\&/g')/,/$(printf '%s' "$marker_end" | sed 's/[.[\*^$(){}?+|/]/\\&/g')/d" "$bashrc_file"
    fi

    # Replace Corretto 8 JAVA_HOME if present
    if grep -Eq '^[[:space:]]*JAVA_HOME=.*java-1\.8\.0-amazon-corretto' "$bashrc_file"; then
      sed -i -E "s|^[[:space:]]*JAVA_HOME=.*java-1\.8\.0-amazon-corretto[^[:space:]]*|JAVA_HOME=${JAVA21_HOME}|g" "$bashrc_file"
      log_msg "INFO" "Replaced Corretto 8 JAVA_HOME with Corretto 21 in $bashrc_file"
    fi

    cat >>"$bashrc_file" <<EOF

${marker_start}
# Added by install_java21_corretto.sh on $(date '+%Y-%m-%d %H:%M:%S')
export JAVA_HOME=${JAVA21_HOME}
export PATH=\$JAVA_HOME/bin\${CATALINA_HOME:+:\$CATALINA_HOME/bin}:\$PATH
${marker_end}
EOF

    log_msg "INFO" "Updated $bashrc_file"
  done
}

update_alternatives() {
  log_msg "INFO" "Configuring system alternatives for Java..."

  local java21_bin="${JAVA21_HOME}/bin/java"
  local javac21_bin="${JAVA21_HOME}/bin/javac"

  [[ -x "$java21_bin" ]] || error_exit "Cannot set alternatives: $java21_bin missing"

  $SUDO alternatives --set java "$java21_bin" >/dev/null 2>&1 || log_msg "WARN" "Could not set 'java' alternative automatically"
  log_msg "INFO" "Set java alternative to: $java21_bin"

  if [[ -x "$javac21_bin" ]]; then
    $SUDO alternatives --set javac "$javac21_bin" >/dev/null 2>&1 || log_msg "WARN" "Could not set 'javac' alternative automatically"
    log_msg "INFO" "Set javac alternative to: $javac21_bin"
  fi

  log_msg "INFO" "Alternatives configuration completed"
}

print_summary() {
  echo "============================================================================="
  echo "Installation Completed Successfully"
  echo "============================================================================="
  echo "Timestamp        : $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Proxy Used       : ${PROXY_URL:-<none>}"
  echo "Java 21 Home     : $JAVA21_HOME"
  echo "Default java     : $(readlink -f "$(command -v java 2>/dev/null || echo /usr/bin/java)" 2>/dev/null || true)"
  echo "Java Version     : $("$JAVA21_HOME/bin/java" -version 2>&1 | head -n 1)"
  echo "Profile Script   : /etc/profile.d/java21.sh"
  echo "Log File         : $LOG_FILE"
  echo "============================================================================="
  echo
  echo "Apply env in current shell:"
  echo "  source /etc/profile.d/java21.sh"
  echo "  source ~/.bashrc"
  echo
}

usage() {
  cat <<EOF
Usage:
  sudo ./install_java21_corretto.sh [--proxy http://host:port] [--no-proxy]

Options:
  --proxy <url>     Proxy URL to use for ALL downloads (dnf/yum/curl)
  --no-proxy        Disable proxy usage (direct internet)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --proxy)
        shift
        [[ $# -gt 0 ]] || error_exit "--proxy requires a value"
        PROXY_URL="$1"
        shift
        ;;
      --no-proxy)
        PROXY_URL=""
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error_exit "Unknown argument: $1"
        ;;
    esac
  done
}

###############################################################################
# Main
###############################################################################
main() {
  parse_args "$@"
  setup_logging
  detect_privilege
  detect_os
  detect_package_manager
  export_proxy_env
  check_existing_java
  configure_repository
  install_java
  detect_java21_home
  verify_installation
  update_alternatives
  configure_system_java_home
  update_user_bashrc
  print_summary
}

main "$@"
exit 0