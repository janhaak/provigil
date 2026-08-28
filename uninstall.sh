#!/bin/bash
# uninstall.sh — remove the provigil symlink and the passwordless-pmset sudoers file.
#
#   ./uninstall.sh                 interactive
#   ./uninstall.sh --yes           assume yes to every prompt
#   ./uninstall.sh --keep-sudoers  leave /etc/sudoers.d/pmset-nopasswd in place
#
# This does not delete the repository itself.

set -euo pipefail

ASSUME_YES=0
DO_SUDOERS=1

while (( $# )); do
  case "$1" in
    -y|--yes)       ASSUME_YES=1 ;;
    --keep-sudoers) DO_SUDOERS=0 ;;
    -h|--help)      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "uninstall.sh: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC="$REPO_DIR/bin/provigil"
SUDOERS_FILE=/etc/sudoers.d/pmset-nopasswd

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

ask() {  # prompt -> 0 if yes
  local prompt=$1 reply
  if (( ASSUME_YES )); then
    info "  $prompt  -> yes (--yes)"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    info "  $prompt  -> skipped (not a terminal; re-run with --yes to accept)"
    return 1
  fi
  read -r -p "  $prompt [y/N] " reply
  [[ "$reply" == [yY]* ]]
}

# --- 1. Symlinks -------------------------------------------------------------
info "==> Removing provigil symlinks"
FOUND=0
for dir in /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
  t="$dir/provigil"
  [[ -L "$t" ]] || continue
  FOUND=1
  cur=$(readlink "$t" || true)
  if [[ "$cur" == "$SRC" ]]; then
    rm -f "$t"
    info "  removed $t"
  else
    warn "$t is a symlink to $cur — not this repo's copy."
    if ask "Remove it anyway?"; then
      rm -f "$t"
      info "  removed $t"
    else
      info "  left $t alone"
    fi
  fi
done

# A non-symlink `provigil` on PATH is not ours; report but never delete it.
if command -v provigil >/dev/null 2>&1; then
  still=$(command -v provigil)
  if [[ ! -L "$still" ]]; then
    warn "a non-symlink 'provigil' is still on your PATH at $still — leaving it alone"
  fi
fi

(( FOUND )) || info "  no provigil symlinks found"

# --- 2. Sudoers file ---------------------------------------------------------
if (( DO_SUDOERS )); then
  info "==> Removing $SUDOERS_FILE"
  if [[ -e "$SUDOERS_FILE" ]]; then
    warn "other tools on this machine may also rely on passwordless pmset."
    if ask "Delete $SUDOERS_FILE?"; then
      sudo rm -f "$SUDOERS_FILE"
      # Confirm the remaining sudoers set still parses.
      if sudo visudo -c >/dev/null 2>&1; then
        info "  removed $SUDOERS_FILE (sudoers still parses OK)"
      else
        warn "removed $SUDOERS_FILE but 'sudo visudo -c' now reports a problem — check it."
      fi
    else
      info "  left $SUDOERS_FILE in place"
    fi
  else
    info "  not present — nothing to do"
  fi
else
  info "==> Keeping $SUDOERS_FILE (--keep-sudoers)"
fi

# --- 3. Stale lockfile -------------------------------------------------------
LOCK=/tmp/provigil.pid
if [[ -f "$LOCK" ]] && ! kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  rm -f "$LOCK"
  info "==> Removed stale lockfile $LOCK"
fi

info "==> Done."
