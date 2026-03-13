#!/usr/bin/env bash

# This script serves the current folder on localhost and opens it in the
# default browser. It is meant to be easy to run for someone who just wants
# to preview the files in this directory.
set -euo pipefail

host="127.0.0.1"
port="${1:-8000}"
root_dir="$PWD"
server_log=""

# Use color only when stdout is a terminal and the terminal reports support.
supports_color() {
  if [[ ! -t 1 ]]; then
    return 1
  fi

  if command -v tput >/dev/null 2>&1; then
    local colors
    colors="$(tput colors 2>/dev/null || printf '0')"
    [[ "$colors" =~ ^[0-9]+$ ]] && (( colors >= 8 ))
    return $?
  fi

  return 1
}

# Detect Git Bash / MSYS / Cygwin so browser launching can use Windows tools.
is_windows_bash() {
  case "${OSTYPE:-}" in
    msys*|cygwin*|win32*)
      return 0
      ;;
  esac

  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
      return 0
      ;;
  esac

  return 1
}

# Ensure a discovered runtime is actually executable, not just present on PATH.
runtime_is_usable() {
  local runtime="$1"

  case "$runtime" in
    python3|python)
      "$runtime" -c 'import sys; sys.exit(0)' >/dev/null 2>&1
      return $?
      ;;
    py)
      "$runtime" -3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1
      return $?
      ;;
    php|ruby)
      "$runtime" -v >/dev/null 2>&1
      return $?
      ;;
  esac

  return 1
}

# Pick the first local HTTP server runtime that is available on this machine.
find_server_command() {
  if command -v python3 >/dev/null 2>&1 && runtime_is_usable python3; then
    printf 'python3|-m|http.server|%s|--bind|%s' "$port" "$host"
    return 0
  fi

  if command -v python >/dev/null 2>&1 && runtime_is_usable python; then
    printf 'python|-m|http.server|%s|--bind|%s' "$port" "$host"
    return 0
  fi

  if command -v py >/dev/null 2>&1 && runtime_is_usable py; then
    printf 'py|-3|-m|http.server|%s|--bind|%s' "$port" "$host"
    return 0
  fi

  if command -v php >/dev/null 2>&1 && runtime_is_usable php; then
    printf 'php|-S|%s:%s' "$host" "$port"
    return 0
  fi

  if command -v ruby >/dev/null 2>&1 && runtime_is_usable ruby; then
    printf 'ruby|-run|-e|httpd|.|-p|%s|-b|%s' "$port" "$host"
    return 0
  fi

  return 1
}

# Check whether a port is already in use before starting the server.
port_is_busy() {
  local candidate_port="$1"

  # Fast path for Bash environments that support /dev/tcp.
  if (echo >"/dev/tcp/${host}/${candidate_port}") >/dev/null 2>&1; then
    return 0
  fi

  # Fallback for environments where /dev/tcp is unavailable or unreliable.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$host" "$candidate_port" <<'PY' >/dev/null 2>&1
import socket
import sys

sock = socket.socket()
sock.settimeout(0.2)
try:
    sock.connect((sys.argv[1], int(sys.argv[2])))
except OSError:
    raise SystemExit(1)
else:
    raise SystemExit(0)
finally:
    sock.close()
PY
    return $?
  fi

  if command -v python >/dev/null 2>&1; then
    python - "$host" "$candidate_port" <<'PY' >/dev/null 2>&1
import socket
import sys

sock = socket.socket()
sock.settimeout(0.2)
try:
    sock.connect((sys.argv[1], int(sys.argv[2])))
except OSError:
    raise SystemExit(1)
else:
    raise SystemExit(0)
finally:
    sock.close()
PY
    return $?
  fi

  return 1
}

# Print a visible stop hint, with color when the terminal supports it.
print_stop_message() {
  local border="================================="
  local message=" TO STOP: Press Q in this window "

  echo

  if supports_color; then
    local yellow reset
    yellow="$(tput setaf 3)"
    reset="$(tput sgr0)"
    printf '%s%s%s\n' "$yellow" "$border" "$reset"
    printf '%s%s%s\n' "$yellow" "$message" "$reset"
    printf '%s%s%s\n' "$yellow" "$border" "$reset"
    return 0
  fi

  echo "$border"
  echo "$message"
  echo "$border"
}

# Check whether the user pressed Q in the terminal.
stop_requested() {
  local key

  if [[ ! -t 0 ]]; then
    return 1
  fi

  if read -r -s -n 1 -t 1 key </dev/tty; then
    [[ "$key" == "q" || "$key" == "Q" ]]
    return $?
  fi

  return 1
}

# Wait until the background server is accepting connections or fails to start.
wait_for_server_start() {
  local attempts=50

  while (( attempts > 0 )); do
    if port_is_busy "$port"; then
      return 0
    fi

    if ! kill -0 "$server_pid" >/dev/null 2>&1; then
      return 1
    fi

    attempts=$((attempts - 1))
    sleep 0.1
  done

  return 1
}

# Show any captured startup error if the server process exits early.
print_server_error() {
  if [[ -n "$server_log" && -s "$server_log" ]]; then
    echo "Server failed to start. Output:" >&2
    cat "$server_log" >&2
    return
  fi

  echo "Server failed to start." >&2
}

# Stop the background server when the script exits.
cleanup() {
  if [[ -n "${server_pid:-}" ]] && kill -0 "$server_pid" >/dev/null 2>&1; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  fi

  if [[ -n "$server_log" && -f "$server_log" ]]; then
    rm -f "$server_log"
  fi
}

# Open the URL with the platform's default browser command.
open_browser() {
  local url="$1"

  # Git Bash needs Windows-native launch commands instead of macOS/Linux tools.
  if is_windows_bash; then
    if command -v cmd.exe >/dev/null 2>&1; then
      MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd.exe /c start "" "$url" >/dev/null 2>&1
      return 0
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
      MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' powershell.exe -NoProfile -Command "Start-Process '$url'" >/dev/null 2>&1
      return 0
    fi
  fi

  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 &
    return 0
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
    return 0
  fi

  return 1
}

# Move to the next port until a free one is found.
while port_is_busy "$port"; do
  port="$((port + 1))"
done

# Build the server command once the final port is known.
server_spec="$(find_server_command)" || {
  echo "No supported local HTTP server runtime found." >&2
  echo "Install one of: python3, python, php, or ruby." >&2
  exit 1
}

IFS='|' read -r -a server_args <<< "$server_spec"
url="http://${host}:${port}/"

echo "Serving ${root_dir}"
echo "Open ${url}"
print_stop_message

trap cleanup EXIT

server_log="$(mktemp "${TMPDIR:-/tmp}/open-in-browser.XXXXXX.log")"

nohup "${server_args[@]}" >"$server_log" 2>&1 < /dev/null &
server_pid=$!

if ! wait_for_server_start; then
  print_server_error
  exit 1
fi

# Open the browser only after the server is reachable.
open_browser "$url" || echo "Could not open browser automatically. Open ${url} manually."

while kill -0 "$server_pid" >/dev/null 2>&1; do
  if stop_requested; then
    echo
    echo "Stopping server..."
    break
  fi

  sleep 0.1
done