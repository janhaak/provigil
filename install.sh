#!/bin/bash
# install.sh — install provigil.
#
# Idempotent: safe to run as many times as you like. It will not overwrite an
# existing, unrelated file without telling you and asking first.
#
#   ./install.sh                 interactive
#   ./install.sh --yes           assume yes to every prompt
#   ./install.sh --no-sudoers    skip the passwordless-pmset step
#   ./install.sh --prefix DIR    install the symlink into DIR

set -euo pipefail

ASSUME_YES=0
DO_SUDOERS=1
PREFIX=""

while (( $# )); do
  case "$1" in
    -y|--yes)     ASSUME_YES=1 ;;
    --no-sudoers) DO_SUDOERS=0 ;;
    --prefix)     shift; PREFIX="${1:-}" ;;
    -h|--help)    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC="$REPO_DIR/bin/provigil"
SUDOERS_FILE=/etc/sudoers.d/pmset-nopasswd
PMSET=$(command -v pmset || echo /usr/bin/pmset)

info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

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

# --- Sanity ------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "provigil is macOS-only (uname says $(uname -s))."
[[ -f "$SRC" ]] || die "cannot find $SRC"
chmod +x "$SRC"
bash -n "$SRC" || die "$SRC failed a syntax check; refusing to install."

# --- 1. Pick an install directory --------------------------------------------
pick_bindir() {
  if [[ -n "$PREFIX" ]]; then
    mkdir -p "$PREFIX" || die "cannot create --prefix directory $PREFIX"
    printf '%s' "$PREFIX"; return
  fi
  if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
    printf '%s' /usr/local/bin; return
  fi
  if [[ ! -d /usr/local/bin && -d /usr/local && -w /usr/local ]]; then
    mkdir -p /usr/local/bin && { printf '%s' /usr/local/bin; return; }
  fi
  mkdir -p "$HOME/.local/bin" || die "cannot create $HOME/.local/bin"
  printf '%s' "$HOME/.local/bin"
}

BINDIR=$(pick_bindir)
TARGET="$BINDIR/provigil"
info "==> Installing symlink into $BINDIR"

if [[ -L "$TARGET" ]]; then
  CURRENT=$(readlink "$TARGET" || true)
  if [[ "$CURRENT" == "$SRC" ]]; then
    info "  $TARGET -> $SRC (already installed, nothing to do)"
  else
    warn "$TARGET is already a symlink to: $CURRENT"
    if ask "Repoint it at $SRC?"; then
      ln -sfn "$SRC" "$TARGET"
      info "  repointed $TARGET -> $SRC"
    else
      info "  left $TARGET alone"
    fi
  fi
elif [[ -e "$TARGET" ]]; then
  warn "$TARGET already exists and is NOT a symlink created by provigil:"
  ls -ld "$TARGET" >&2
  if ask "Move it aside to ${TARGET}.bak and install the symlink?"; then
    mv "$TARGET" "$TARGET.bak"
    ln -sfn "$SRC" "$TARGET"
    info "  backed up to $TARGET.bak; installed $TARGET -> $SRC"
  else
    info "  left $TARGET alone — provigil was NOT linked onto your PATH"
  fi
else
  ln -sfn "$SRC" "$TARGET"
  info "  created $TARGET -> $SRC"
fi

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) warn "$BINDIR is not on your PATH. Add it, e.g.:"
     warn "  echo 'export PATH=\"$BINDIR:\$PATH\"' >> ~/.zshrc" ;;
esac

# --- 2. Passwordless pmset ---------------------------------------------------
# provigil calls `sudo -n pmset -a disablesleep 1`, so pmset must be runnable
# without a password prompt or the tool fail-fasts.
if (( DO_SUDOERS )); then
  info "==> Checking passwordless pmset"
  if sudo -n pmset -g >/dev/null 2>&1; then
    info "  already working — nothing to do"
  else
    info "  \`sudo -n pmset -g\` does not work yet."
    info "  provigil needs this line in $SUDOERS_FILE:"
    RULE="$(id -un) ALL=(root) NOPASSWD: $PMSET"
    info "      $RULE"
    if [[ -e "$SUDOERS_FILE" ]]; then
      warn "$SUDOERS_FILE already exists (contents not shown; it is root-owned)."
      warn "Inspect it yourself with: sudo cat $SUDOERS_FILE"
      warn "Not touching it. Add the line above by hand with: sudo visudo -f $SUDOERS_FILE"
    elif ask "Write it now (validated with visudo -c before installing)?"; then
      TMP=$(mktemp "${TMPDIR:-/tmp}/pmset-nopasswd.XXXXXX")
      # shellcheck disable=SC2064  # expand TMP now, on purpose
      trap "rm -f '$TMP'" EXIT
      printf '%s\n' \
        '# Installed by provigil (https://github.com/janhaak/provigil).' \
        '# Lets provigil toggle sleep without an interactive password prompt.' \
        "$RULE" > "$TMP"
      if ! visudo -c -f "$TMP"; then
        die "the generated sudoers fragment failed validation — NOT installing it."
      fi
      # install(1) sets owner, group and mode atomically. 0440 root:wheel is what
      # sudo requires of files in /etc/sudoers.d.
      sudo install -m 0440 -o root -g wheel "$TMP" "$SUDOERS_FILE"
      rm -f "$TMP"; trap - EXIT
      if sudo -n pmset -g >/dev/null 2>&1; then
        info "  installed $SUDOERS_FILE and verified passwordless pmset works"
      else
        warn "installed $SUDOERS_FILE but \`sudo -n pmset -g\` still fails."
        warn "Open a new shell and try again, or check the file with: sudo visudo -c"
      fi
    else
      warn "skipped. provigil will refuse to start until this is configured."
      warn "See the README section 'Passwordless sudo for pmset'."
    fi
  fi
else
  info "==> Skipping passwordless-pmset step (--no-sudoers)"
fi

info "==> Done. Try: provigil default"
