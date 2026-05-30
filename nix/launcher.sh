#!/usr/bin/env bash
# Templated by nix/package.nix.
#   @SNAPSHOT@       -- /nix/store/<hash>-line-snapshot.tar.zst
#   @SNAPSHOT_HASH@  -- SRI hash, used as a versioning stamp
#
# Model: this script does extract-or-update + exec. Nothing else.
# All install/winetricks/security-check work happens in CI; the snapshot is
# an immutable, verified-working prefix tarball. User state (login token,
# chat history) lives under LINE/Data and LINE/UserData and is preserved
# across snapshot bumps.
set -euo pipefail

: "${XDG_DATA_HOME:=$HOME/.local/share}"
export WINEPREFIX="${LINE_NIX_PREFIX:-${WINEPREFIX:-$XDG_DATA_HOME/line-msgr}}"
export WINEDEBUG="${WINEDEBUG:-fixme-all,err-all}"
# Do NOT set WINEARCH -- let wine pick its native default (matches what CI
# used to build the snapshot). Forcing it causes prefix-arch conflicts.

SNAPSHOT='@SNAPSHOT@'
SNAPSHOT_HASH='@SNAPSHOT_HASH@'

# The snapshot was built in CI under the `runner` user; on extract we
# symlink users/$USER -> users/runner so wine resolves the current user's
# profile path to the snapshot's files.
SNAPSHOT_USER=runner

stamp_file="$WINEPREFIX/.line-nix-snapshot"
current_stamp=""
if [ -f "$stamp_file" ]; then
  current_stamp=$(cat "$stamp_file")
fi

if [ "$current_stamp" != "$SNAPSHOT_HASH" ]; then
  echo "line-nix: applying snapshot $SNAPSHOT_HASH (was: ${current_stamp:-none})" >&2

  # Preserve user state across bumps. Data/ holds chat DB, UserData/ holds
  # account/session. Anything else under LINE/ is part of the install and
  # gets replaced by the snapshot.
  backup=""
  state_root="$WINEPREFIX/drive_c/users/$SNAPSHOT_USER/AppData/Local/LINE"
  if [ -d "$state_root" ]; then
    backup=$(mktemp -d)
    for d in Data UserData; do
      if [ -d "$state_root/$d" ]; then
        mv "$state_root/$d" "$backup/$d"
      fi
    done
  fi

  rm -rf "$WINEPREFIX"
  mkdir -p "$WINEPREFIX"
  tar --zstd -xf "$SNAPSHOT" -C "$WINEPREFIX"

  # Map the current Linux user to the snapshot's user dir.
  if [ "$USER" != "$SNAPSHOT_USER" ]; then
    rm -rf "$WINEPREFIX/drive_c/users/$USER"
    ln -sfn "$SNAPSHOT_USER" "$WINEPREFIX/drive_c/users/$USER"
  fi

  # Restore user state if we had any.
  if [ -n "$backup" ]; then
    mkdir -p "$state_root"
    for d in Data UserData; do
      if [ -d "$backup/$d" ]; then
        rm -rf "${state_root:?}/$d"
        mv "$backup/$d" "$state_root/$d"
      fi
    done
    rmdir "$backup" 2>/dev/null || true
  fi

  echo "$SNAPSHOT_HASH" >"$stamp_file"
fi

exec wine "$WINEPREFIX/drive_c/users/$SNAPSHOT_USER/AppData/Local/LINE/bin/LineLauncher.exe" "$@"
