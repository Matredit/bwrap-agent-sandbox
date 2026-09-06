#!/usr/bin/env bash
###############################
###### Vibecoded testing ######
###############################
# test.sh - Comprehensive automated test suite for bbox.sh / agent-sandbox.sh
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$SCRIPT_DIR/bbox.sh}"

if [[ ! -x "$TARGET" ]]; then
  echo "Error: Target script not executable or not found: $TARGET"
  echo "Usage: $0 [path/to/bbox.sh]"
  exit 1
fi

TARGET="$(realpath "$TARGET")"

# Colors for formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Temporary workspace for all tests (guarantees host is never touched)
TEST_ROOT=$(mktemp -d /tmp/bbox_test_suite.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT

pass() {
  PASSED_TESTS=$((PASSED_TESTS + 1))
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo -e "  [ ${GREEN}PASS${NC} ] $1"
}

fail() {
  FAILED_TESTS=$((FAILED_TESTS + 1))
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo -e "  [ ${RED}FAIL${NC} ] $1"
  if [[ -n "${2:-}" ]]; then
    echo -e "         ${YELLOW}Details:${NC} $2"
  fi
}

section() {
  echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"
}

# Helper: setup fresh dummy project in a subdirectory
setup_test_repo() {
  local repo_dir="$1"
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir/.git" "$repo_dir/src" "$repo_dir/private_dir"
  echo "PROJECT_CODE=v1" > "$repo_dir/src/app.py"
  echo "INITIAL_FILE" > "$repo_dir/file.txt"
  echo "gitdir: mock" > "$repo_dir/.git/config"
  echo "SUPER_SECRET_TOKEN=xyz123" > "$repo_dir/secret.env"
  echo "private_key" > "$repo_dir/private_dir/id_rsa"
}

# ==============================================================================
# SECTION 1: DRY-RUN PARSING & CONFIGURATION TESTS
# ==============================================================================
section "1. Argument Parsing & Dry-Run Tests (Zero-execution verification)"

test_no_args_shows_usage() {
  local output exit_code=0
  output=$( "$TARGET" 2>&1 ) || exit_code=$?
  if [[ $exit_code -ne 0 ]] && echo "$output" | grep -q "Usage:"; then
    pass "No arguments prints usage and exits with error code"
  else
    fail "No arguments should show usage and fail" "Exit code: $exit_code, Output: $output"
  fi
}
test_no_args_shows_usage

test_preset_g_command_and_git_protect() {
  local repo="$TEST_ROOT/dry_repo"
  setup_test_repo "$repo"
  local output
  output=$(cd "$repo" && DRY_RUN=1 "$TARGET" g)

  local ok_cmd=0 ok_bind=0 ok_git_ro=0
  if echo "$output" | grep -q "^COMMAND: agy --dangerously-skip-permissions"; then
    ok_cmd=1
  fi
  # Verify CWD is bound
  if echo "$output" | grep -A 2 -E "^\s*--bind" | grep -q "$repo"; then
    ok_bind=1
  fi
  # Verify .git is read-only
  if echo "$output" | grep -A 2 -E "^\s*--ro-bind" | grep -q "$repo/\.git"; then
    ok_git_ro=1
  fi

  if [[ $ok_cmd -eq 1 && $ok_bind -eq 1 && $ok_git_ro -eq 1 ]]; then
    pass "Preset 'g' expands command, binds CWD, and protects .git as read-only"
  else
    fail "Preset 'g' failed configuration check" "cmd=$ok_cmd, bind=$ok_bind, git_ro=$ok_git_ro"
  fi
}
test_preset_g_command_and_git_protect

test_preset_oc_command() {
  local output
  output=$(cd "$TEST_ROOT" && DRY_RUN=1 "$TARGET" oc)
  if echo "$output" | grep -q "^COMMAND: opencode --auto"; then
    pass "Preset 'oc' expands to 'opencode --auto'"
  else
    fail "Preset 'oc' did not expand to 'opencode --auto'" "$output"
  fi
}
test_preset_oc_command

test_preset_overlay_flag() {
  local repo="$TEST_ROOT/dry_repo_ovl"
  setup_test_repo "$repo"
  local output
  output=$(cd "$repo" && DRY_RUN=1 "$TARGET" g -o)

  if echo "$output" | grep -A 2 -E "^\s*--overlay-src" | grep -q "$repo" && \
     echo "$output" | grep -A 2 -E "^\s*--tmp-overlay" | grep -q "$repo"; then
    pass "Flag '-o' with preset mounts CWD as ephemeral OverlayFS"
  else
    fail "Flag '-o' did not mount CWD as OverlayFS" "$output"
  fi
}
test_preset_overlay_flag

test_preset_readonly_flag() {
  local repo="$TEST_ROOT/dry_repo_ro"
  setup_test_repo "$repo"
  local output
  output=$(cd "$repo" && DRY_RUN=1 "$TARGET" g -r)

  local has_bind=0 has_ro=0
  if echo "$output" | grep -A 2 -E "^\s*--bind" | grep -q "$repo$"; then
    has_bind=1
  fi
  if echo "$output" | grep -A 2 -E "^\s*--ro-bind" | grep -q "$repo$"; then
    has_ro=1
  fi

  if [[ $has_bind -eq 0 && $has_ro -eq 1 ]]; then
    pass "Flag '-r' with preset mounts CWD as strictly read-only (no writable bind)"
  else
    fail "Flag '-r' configuration incorrect" "has_bind=$has_bind, has_ro=$has_ro"
  fi
}
test_preset_readonly_flag

test_preset_with_extra_args() {
  local output
  output=$(cd "$TEST_ROOT" && DRY_RUN=1 "$TARGET" g -- "fix the authentication bug" -c)
  if echo "$output" | grep -q "^COMMAND: agy --dangerously-skip-permissions fix the authentication bug -c"; then
    pass "Extra arguments after '--' append cleanly to preset command"
  else
    fail "Extra arguments after '--' failed to append to preset" "$output"
  fi
}
test_preset_with_extra_args

test_classic_syntax_custom_cmd() {
  local repo="$TEST_ROOT/dry_classic"
  setup_test_repo "$repo"
  local output
  output=$(cd "$TEST_ROOT" && DRY_RUN=1 "$TARGET" -w "$repo" -r "$repo/.git" -- my-agent-tool --flag)

  if echo "$output" | grep -q "^COMMAND: my-agent-tool --flag" && \
     echo "$output" | grep -A 2 -E "^\s*--bind" | grep -q "$repo$" && \
     echo "$output" | grep -A 2 -E "^\s*--ro-bind" | grep -q "$repo/\.git"; then
    pass "Classic syntax (-w path -r path -- cmd) works as expected"
  else
    fail "Classic syntax failed" "$output"
  fi
}
test_classic_syntax_custom_cmd

test_mask_flag_parsing() {
  local repo="$TEST_ROOT/dry_mask"
  setup_test_repo "$repo"
  local output
  output=$(cd "$repo" && DRY_RUN=1 "$TARGET" g -m "$repo/secret.env")

  if echo "$output" | grep -A 2 -E "^\s*--ro-bind" | grep -q "$repo/secret\.env"; then
    pass "Flag '-m' mounts notice file over target"
  else
    fail "Flag '-m' did not mount notice over target" "$output"
  fi
}
test_mask_flag_parsing

test_stealth_mask_parsing() {
  local repo="$TEST_ROOT/dry_stealth"
  setup_test_repo "$repo"
  local output
  output=$(cd "$repo" && DRY_RUN=1 "$TARGET" g -m "$repo/private_dir" --stealth)

  # In stealth mode, directory gets --tmpfs without --ro-bind README.txt
  if echo "$output" | grep -A 1 -E "^\s*--tmpfs" | grep -q "$repo/private_dir" && \
     ! echo "$output" | grep -q "$repo/private_dir/README\.txt"; then
    pass "Flag '--stealth' mounts empty tmpfs without README notice"
  else
    fail "Flag '--stealth' did not produce silent empty mask" "$output"
  fi
}
test_stealth_mask_parsing

# ==============================================================================
# SECTION 2: LIVE SANDBOX EXECUTION & PERMISSIONS TESTS
# ==============================================================================
section "2. Live Sandbox Execution Tests (Real kernel bwrap verification)"

test_live_default_write_and_git_protect() {
  local repo="$TEST_ROOT/live_default"
  setup_test_repo "$repo"

  ( cd "$repo" && "$TARGET" -w -- bash -c 'echo "edit" >> file.txt && touch new.txt' )
  local can_write=0
  if [[ -f "$repo/new.txt" ]] && grep -q "edit" "$repo/file.txt"; then
    can_write=1
  fi

  local git_blocked=0
  if ( cd "$repo" && "$TARGET" -w -- bash -c 'touch .git/leak.txt 2>/dev/null || exit 0; exit 1' ); then
    git_blocked=1
  fi

  if [[ $can_write -eq 1 && $git_blocked -eq 1 && ! -f "$repo/.git/leak.txt" ]]; then
    pass "Live: CWD is fully writable, but .git is strictly protected from writes"
  else
    fail "Live: Default write or .git protection failed" "can_write=$can_write, git_blocked=$git_blocked"
  fi
}
test_live_default_write_and_git_protect

test_live_git_writable_override() {
  local repo="$TEST_ROOT/live_git_write"
  setup_test_repo "$repo"

  (
    cd "$repo"
    "$TARGET" -w -w .git -- bash -c '
      touch .git/allowed_write.txt 2>/dev/null || true
    '
  )

  if [[ -f "$repo/.git/allowed_write.txt" ]]; then
    pass "Live: Explicit '-w .git' allows writing to .git when user intends it"
  else
    fail "Live: Explicit '-w .git' failed to make .git writable"
  fi
}
test_live_git_writable_override

test_live_overlay_mode() {
  local repo="$TEST_ROOT/live_overlay"
  setup_test_repo "$repo"

  (
    cd "$repo"
    "$TARGET" -o -- bash -c '
      echo "modified in overlay" >> file.txt
      touch overlay_scratch.txt
    '
  )

  # Check host filesystem
  if [[ ! -f "$repo/overlay_scratch.txt" ]] && ! grep -q "modified in overlay" "$repo/file.txt"; then
    pass "Live: OverlayFS allows writes in sandbox, but host remains 100% clean on exit"
  else
    fail "Live: OverlayFS failed isolation (host files modified or created)"
  fi
}
test_live_overlay_mode

test_live_readonly_mode() {
  local repo="$TEST_ROOT/live_ro"
  setup_test_repo "$repo"

  local write_blocked=0
  if ( cd "$repo" && "$TARGET" -r -- bash -c 'touch should_fail.txt 2>/dev/null || exit 0; exit 1' ); then
    write_blocked=1
  fi

  if [[ $write_blocked -eq 1 && ! -f "$repo/should_fail.txt" ]]; then
    pass "Live: Read-only mode (-r) strictly blocks all file modifications"
  else
    fail "Live: Read-only mode allowed file writes"
  fi
}
test_live_readonly_mode

test_live_mask_file() {
  local repo="$TEST_ROOT/live_mask_file"
  setup_test_repo "$repo"

  local output=""
  output=$(
    cd "$repo"
    "$TARGET" -w -m secret.env -- bash -c '
      cat secret.env
      echo "hacked" > secret.env 2>/dev/null || true
    ' 2>/dev/null
  )

  local notice_shown=0 host_secret_safe=0
  if echo "$output" | grep -q "SANDBOX NOTICE"; then
    notice_shown=1
  fi
  if grep -q "SUPER_SECRET_TOKEN=xyz123" "$repo/secret.env"; then
    host_secret_safe=1
  fi

  if [[ $notice_shown -eq 1 && $host_secret_safe -eq 1 ]]; then
    pass "Live: Masked file displays sandbox notice and cannot be overwritten"
  else
    fail "Live: Masked file failed verification" "notice=$notice_shown, safe=$host_secret_safe"
  fi
}
test_live_mask_file

test_live_mask_dir() {
  local repo="$TEST_ROOT/live_mask_dir"
  setup_test_repo "$repo"

  local output=""
  output=$(
    cd "$repo"
    "$TARGET" -w -m private_dir -- bash -c '
      ls -1 private_dir
      cat private_dir/README.txt
    '
  )

  local original_hidden=0 readme_exists=0
  if ! echo "$output" | grep -q "id_rsa"; then
    original_hidden=1
  fi
  if echo "$output" | grep -q "README.txt" && echo "$output" | grep -q "SANDBOX NOTICE"; then
    readme_exists=1
  fi

  if [[ $original_hidden -eq 1 && $readme_exists -eq 1 ]]; then
    pass "Live: Masked directory hides internal files and contains README notice"
  else
    fail "Live: Masked directory failed to hide contents or display notice"
  fi
}
test_live_mask_dir

test_live_stealth_mask() {
  local repo="$TEST_ROOT/live_stealth_mask"
  setup_test_repo "$repo"

  local file_bytes dir_files
  read -r file_bytes dir_files < <(
    cd "$repo"
    "$TARGET" -w -m secret.env -m private_dir --stealth -- bash -c '
      echo "$(wc -c < secret.env) $(ls -1 private_dir | wc -l)"
    '
  )

  if [[ "$file_bytes" -eq 0 && "$dir_files" -eq 0 ]]; then
    pass "Live: Stealth mode creates 0-byte file and completely empty directory"
  else
    fail "Live: Stealth mask failed" "file_bytes=$file_bytes, dir_files=$dir_files"
  fi
}
test_live_stealth_mask

# ==============================================================================
# SECTION 3: SYSTEM INTEGRITY & SECURITY BOUNDARIES
# ==============================================================================
section "3. Security Boundaries & System Integrity"

test_host_root_immutable() {
  local blocked=0
  if ( cd "$TEST_ROOT" && "$TARGET" -w -- bash -c 'touch /usr/bin/sandbox_leak_test 2>/dev/null || exit 0; exit 1' ); then
    blocked=1
  fi

  if [[ $blocked -eq 1 ]]; then
    pass "Security: Host /usr filesystem is strictly read-only"
  else
    fail "Security: Host /usr allowed writes inside sandbox!"
  fi
}
test_host_root_immutable

test_tmpfs_isolation() {
  local scratch_file="sandbox_tmp_leak_test_$$"
  ( cd "$TEST_ROOT" && "$TARGET" -w -- bash -c "touch /tmp/$scratch_file" )

  if [[ ! -f "/tmp/$scratch_file" ]]; then
    pass "Security: /tmp is an isolated in-memory scratchpad and does not leak to host /tmp"
  else
    fail "Security: /tmp sandbox isolation failed"
    rm -f "/tmp/$scratch_file"
  fi
}
test_tmpfs_isolation

test_dev_shm_isolation() {
  local shm_file="sandbox_shm_test_$$"
  ( cd "$TEST_ROOT" && "$TARGET" -w -- bash -c "touch /dev/shm/$shm_file" )

  if [[ ! -f "/dev/shm/$shm_file" ]]; then
    pass "Security: /dev/shm is isolated and does not leak to host shared memory"
  else
    fail "Security: /dev/shm isolation failed"
    rm -f "/dev/shm/$shm_file"
  fi
}
test_dev_shm_isolation

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}TEST RESULTS FOR: ${CYAN}$(basename "$TARGET")${NC}"
echo -e "  Total Tests:  ${BOLD}$TOTAL_TESTS${NC}"
echo -e "  Passed:       ${GREEN}${BOLD}$PASSED_TESTS${NC}"
echo -e "  Failed:       ${RED}${BOLD}$FAILED_TESTS${NC}"
echo -e "${BOLD}========================================${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}ALL TESTS PASSED SUCCESSFULLY!${NC}\n"
  exit 0
else
  echo -e "${RED}${BOLD}SOME TESTS FAILED.${NC}\n"
  exit 1
fi
