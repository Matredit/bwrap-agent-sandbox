#!/usr/bin/env bash

set -euo pipefail

# Preset Aliases: map shortcut name to default agent command
declare -A PRESETS=(
  [g]="agy --dangerously-skip-permissions"
  [agy]="agy --dangerously-skip-permissions"
  [oc]="opencode --auto"
  [opencode]="opencode --auto"
)

COMMAND=()

CLI_WRITABLE=() # dirs only
CLI_OVERLAYS=() # dirs only
CLI_READONLY=()
CLI_MASKS=()

PRESET_SELECTED=""
CWD_MODE="" # write | overlay | readonly | masked?
STEALTH_MASK=false
GIT_CHANGE_IN_PRESET=true

BWRAP_ARGS=(
  --ro-bind / /  # The core rule: Entire host is read-only
  --dev /dev     # Required for pseudoterminals (PTYs) and basic IO
  --proc /proc   # Required for process management
  --tmpfs /tmp   # Isolated scratchpad; prevents reading host /tmp sockets
  --tmpfs "${XDG_RUNTIME_DIR:-/run/user/$UID}" # maybe Fixes Neovim crashes
  --tmpfs /var/tmp                             # maybe Needed for large compiler temps
  --tmpfs /dev/shm                             # maybe Needed for Node/Python shared memory
)

# Temporary files for masking
EMPTY_FILE=$(mktemp)
NOTICE_FILE=$(mktemp)
trap 'rm -f "$EMPTY_FILE" "$NOTICE_FILE"' EXIT  # Clean up automatically when script exits

cat <<'EOF' > "$NOTICE_FILE"
[SANDBOX NOTICE]
This file or directory is masked by the Bubblewrap sandbox (agent-sandbox).
Access to this content has been restricted to protect sensitive personal data or system integrity.

If you are an AI coding agent and require access to this path to complete your task:
- DO NOT assume this file or directory is missing, empty, or corrupted.
- DO NOT attempt to recreate, overwrite, or bypass this restriction.
- Please inform the user and ask them to grant access by updating their sandbox configuration or command-line flags.
EOF

usage() {
  echo ""
  echo "Usage:"
  echo "  $0 [<preset> [-o|-r|-w]] [OPTIONS]... [-- [agent-args...]]"
  echo "  $0 [-w dir]... [-o dir]... [-r path]... [-m path]... -- <command> [args...]"
  echo ""
  echo "Available presets: ${!PRESETS[*]}"
  echo ""
  echo "If a preset is used, modes for current directory can be specified:"
  echo "  (default)  Read-write workspace with .git protected as read-only"
  echo "  -o         Ephemeral OverlayFS (all changes in RAM, discarded on exit)"
  echo "  -r         Read-only workspace (no writes allowed anywhere in project)"
  echo ""
  echo "Available options: "
  echo "  -w, --workspace, --writable [dir]"
  echo "                         Make specific directory writable"
  echo "  -o, --overlay [dir]    Mount directory as an overlay"
  echo "  -r, -ro, --ro, --readonly, --read-only [path]"
  echo "                         Mount path as read-only"
  echo "  -m, --mask <path>      Mask out or hide a specific path"
  echo "  --stealth, --stealth-mask, --empty-mask, --ambiguous"
  echo "                         Enable stealth mask mode"
  echo "  --                     Separate flags from command/preset arguments"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workspace|--writable)
      # If followed by an existing directory, mount that directory as workspace
      if [[ -n "${2:-}" && "$2" != -* && "$2" != "--" && -d "$2" ]]; then
        CLI_WRITABLE+=("$(realpath "$2")")
        shift 2
      else
        # Bare -w: set CWD mode to write
        CWD_MODE="write"
        GIT_CHANGE_IN_PRESET=false
        shift
      fi
      ;;
    -o|--overlay)
      # If followed by an existing directory, mount that directory as overlay
      if [[ -n "${2:-}" && "$2" != -* && "$2" != "--" && -d "$2" ]]; then
        CLI_OVERLAYS+=("$(realpath "$2")")
        shift 2
      else
        # Bare -o: set CWD mode to overlay
        CWD_MODE="overlay"
        shift
      fi
      ;;
    -r|-ro|--ro|--readonly|--read-only)
      # If followed by an existing file/directory, mount that path as read-only
      if [[ -n "${2:-}" && "$2" != -* && "$2" != "--" && -e "$2" ]]; then
        CLI_READONLY+=("$(realpath "$2")")
        shift 2
      else
        # Bare -r: set CWD mode to readonly
        CWD_MODE="readonly"
        shift
      fi
      ;;
    -m|--mask)
      if [[ -z "${2:-}" || "$2" == -* || "$2" == "--" || ! -e "$2" ]]; then
        echo "Error: $1 requires a path argument."
        exit 1
      fi
      CLI_MASKS+=("$(realpath "$2")")
      shift 2
      ;;
    --stealth|--stealth-mask|--empty-mask|--ambiguous)
      STEALTH_MASK=true
      shift
      ;;
    --)
      shift
      if [[ -n "$PRESET_SELECTED" ]]; then
        # Append extra arguments to the preset command
        COMMAND+=("$@")
      else
        # Classic syntax: user supplies the entire command
        COMMAND=("$@")
      fi
      break
      ;;
    *)
      # Check if argument matches a registered preset alias
      if [[ -n "${PRESETS[$1]:-}" ]]; then
        PRESET_SELECTED="$1"
        read -ra CMD_ARRAY <<< "${PRESETS[$1]}"
        COMMAND=("${CMD_ARRAY[@]}")
        # Presets default to CWD writable, unless modified by -o or -r
        if [[ -z "$CWD_MODE" ]]; then
          CWD_MODE="write"
        fi
        shift
      else
        echo "Error: Invalid argument '$1'"
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ ${#COMMAND[@]} -eq 0 ]]; then
  echo "Error: No agent preset or command provided."
  usage
  exit 1
fi



DEFAULT_WRITABLE_DIRS=(
  # Top-level agent folders
  "$HOME/.claude"
  "$HOME/.codex"
  "$HOME/.copilot"
  "$HOME/.gemini"
  "$HOME/.pi"
  
  # Base Cache
  "$HOME/.cache"
  
  # Specific Configs
  "$HOME/.config/mise"
  "$HOME/.config/opencode"
  
  # Specific Local States
  "$HOME/.local/share/mise"
  "$HOME/.local/share/opencode"
  "$HOME/.local/share/opentui"
  "$HOME/.local/state/mise"
  "$HOME/.local/state/nvim"  # Fixes Neovim crashes
  "$HOME/.local/state/opencode"
)

DEFAULT_MASKED=(
  # FILES:
  
  # Histories
  "$HOME/.bash_history"
  "$HOME/.mariadb_history"
  "$HOME/.node_repl_history"
  "$HOME/.psql_history"
  "$HOME/.python_history"
  
  # some shit
  "$HOME/.pulse-cookie"
  "$HOME/default_pwtimer.json"
  "$HOME/.my_file2"

  # DIRS:

  # Home Directory Secrets & Personal Folders
  "$HOME/.ssh"
  "$HOME/.gnupg"
  "$HOME/.keepass"
  "$HOME/.ViberPC"
  "$HOME/.mozilla"
  "$HOME/.pki"
  "$HOME/Desktop"
  "$HOME/Documents"
  "$HOME/Downloads"
  "$HOME/Games"
  "$HOME/Music"
  "$HOME/Photos"
  "$HOME/Pictures"
  "$HOME/Videos"
  "$HOME/Work"
  # "$HOME/Projects" # symlinks are evil, never again

  # Caches to hide inside the writable ~/.cache
  "$HOME/.cache/thumbnails"
  "$HOME/.cache/BraveSoftware"
  "$HOME/.cache/chromium"
  "$HOME/.cache/mozilla"
  "$HOME/.cache/torbrowser"
  "$HOME/.cache/com.bitwarden.desktop"
  "$HOME/.cache/keepassxc"
  "$HOME/.cache/TelegramDesktop"
  "$HOME/.cache/TeamSpeak"

  # Configs to hide
  "$HOME/.config/1Password"
  "$HOME/.config/Bitwarden"
  "$HOME/.config/keepassxc"
  "$HOME/.config/BraveSoftware"
  "$HOME/.config/chromium"
  "$HOME/.config/google-chrome"
  "$HOME/.config/google-chrome-beta"
  "$HOME/.config/google-chrome-unstable"
  "$HOME/.config/microsoft-edge"
  "$HOME/.config/microsoft-edge-dev"
  "$HOME/.config/mozilla"
  "$HOME/.config/torbrowser"
  "$HOME/.config/vivaldi"
  "$HOME/.config/vivaldi-snapshot"
  "$HOME/.config/discord"
  "$HOME/.config/Signal"
  "$HOME/.config/TeamSpeak"
  "$HOME/.config/obsidian"

  # Local states to hide
  "$HOME/.local/share/keyrings"
  "$HOME/.local/share/TelegramDesktop"
  "$HOME/.local/share/torbrowser"
  "$HOME/.local/share/Trash"
)

add_writable() {
  if [[ -d "$1" ]]; then
    BWRAP_ARGS+=(--bind "$1" "$1")
  elif [[ -z "$2" ]]; then
    echo "Warning: Writable directory does not exist: $1"
  fi
}

add_overlay() {
  if [[ -d "$1" ]]; then
    BWRAP_ARGS+=(--overlay-src "$1" --tmp-overlay "$1")
  else
    echo "Warning: Overlay directory does not exist: $1"
  fi
}

add_readonly() {
  if [[ -e "$1" ]]; then
    BWRAP_ARGS+=(--ro-bind "$1" "$1")
  else
    echo "Warning: Read-only path does not exist: $1"
  fi
}

add_mask() {
  if [[ -d "$1" ]]; then
    BWRAP_ARGS+=(--tmpfs "$1")
    if [[ "$STEALTH_MASK" == false ]]; then
      BWRAP_ARGS+=(--ro-bind "$NOTICE_FILE" "$1/README.txt")
    fi
  elif [[ -f "$1" ]]; then
    if [[ "$STEALTH_MASK" == false ]]; then
      BWRAP_ARGS+=(--ro-bind "$NOTICE_FILE" "$1")
    else
      BWRAP_ARGS+=(--ro-bind "$EMPTY_FILE" "$1")
    fi
  elif [[ -z "$2" ]]; then
    echo "Warning: Mask path does not exist: $1"
  fi
}

# Apply

# DEFAULTS

# / is already readonly
for dir in "${DEFAULT_WRITABLE_DIRS[@]}"; do
  add_writable "$dir" quiet
done

for dir in "${DEFAULT_MASKED[@]}"; do
  add_mask "$dir" quiet
done

# PRESETS

# CWD mode
CWD="$(realpath ".")"
case "$CWD_MODE" in
  write)
    add_writable "$CWD"
    ;;
  overlay)
   add_overlay "$CWD"
   ;;
  readonly)
    add_readonly "$CWD"
    ;;
esac

# .git is READONLY by default if PRESET if used
if [[ -e "$CWD/.git" && "$CWD_MODE" == "write" && GIT_CHANGE_IN_PRESET == true ]]; then
  GIT_PATH="$(realpath "$CWD/.git")"
  add_readonly "$GIT_PATH"
fi

# CLI

for dir in "${CLI_WRITABLE[@]}"; do
  add_writable "$dir"
done

for dir in "${CLI_OVERLAYS[@]}"; do
  add_overlay "$dir"
done

for dir in "${CLI_READONLY[@]}"; do
  add_readonly "$dir"
done

for dir in "${CLI_MASKS[@]}"; do
  add_mask "$dir"
done

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "COMMAND: ${COMMAND[*]}"
  printf 'BWRAP_ARGS:\n'
  printf '  %s\n' "${BWRAP_ARGS[@]}"
  exit 0
fi

# Execute the target agent inside the sandbox
# 'exec' replaces the current bash process with bwrap, passing signals cleanly.
exec bwrap "${BWRAP_ARGS[@]}" "${COMMAND[@]}"
