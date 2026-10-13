#!/bin/bash
# Desfaz o que o install.sh instalou, a partir do registro que ele grava. Partes de root pedem sudo.
#
# Uso: ./uninstall.sh [--dry-run]

set -euo pipefail

BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"
MANIFEST="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-dev-machine/installed"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")/GitHub/claude-skills}"
DRY_RUN=false
case "${1:-}" in
  --dry-run | -n) DRY_RUN=true ;;
esac

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

if [ ! -f "$MANIFEST" ]; then
  echo "Nada registrado em $MANIFEST; nada a desfazer."
  exit 0
fi
installed() { grep -qx "$1" "$MANIFEST"; }
root_cmds=()

if installed cleanup; then
  echo "== dev-cleanup"
  run systemctl --user disable --now dev-cleanup.timer dev-cleanup-watch.service 2>/dev/null || true
  run rm -f "$UNITS/dev-cleanup.service" "$UNITS/dev-cleanup.timer" "$UNITS/dev-cleanup-watch.service" \
    "$BIN/dev-cleanup" "$BIN/dev-machine-doctor"
  run systemctl --user daemon-reload
  # /tmp/$USER aponta para o disco até o próximo boot; o tmpfs some e ninguém recria o link.
fi

if installed gradle; then
  echo "== Gradle"
  run sed -i '/^# >>> ubuntu-dev-machine/,/^# <<< ubuntu-dev-machine/d' "$HOME/.gradle/gradle.properties"
fi

if installed emulador; then
  echo "== emulador"
  run rm -f "$BIN/emulador"
fi

if installed gnome; then
  echo "== GNOME"
  run gsettings reset org.gnome.mutter check-alive-timeout
fi

if installed slack; then
  echo "== Slack"
  if [ -x "$BIN/fix-slack-screenshare" ]; then
    run "$BIN/fix-slack-screenshare" --remove
  fi
  run rm -f "$BIN/fix-slack-screenshare"
fi

if installed skills; then
  echo "== Skills do Claude Code"
  # Tira só os links de ~/.claude/skills; o clone em $SKILLS_DIR fica, é onde as skills são editadas.
  if [ -x "$SKILLS_DIR/install.sh" ]; then
    run "$SKILLS_DIR/install.sh" --uninstall
  fi
fi

if installed snaps; then
  root_cmds+=("systemctl disable --now snap-prune-disabled.timer"
    "rm -f /etc/systemd/system/snap-prune-disabled.service /etc/systemd/system/snap-prune-disabled.timer /usr/local/sbin/snap-prune-disabled")
fi
if installed apt; then
  root_cmds+=("systemctl disable --now apt-weekly-maintenance.timer"
    "rm -f /etc/systemd/system/apt-weekly-maintenance.service /etc/systemd/system/apt-weekly-maintenance.timer /usr/local/sbin/apt-weekly-maintenance")
fi
if [ ${#root_cmds[@]} -gt 0 ]; then
  echo "== Partes de root (sudo)"
  root_cmds+=("systemctl daemon-reload")
  script=$(printf '%s; ' "${root_cmds[@]}")
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] sudo sh -c \"$script\""
  else
    sudo sh -c "$script"
  fi
fi

run rm -f "$MANIFEST"
echo "Pronto."
