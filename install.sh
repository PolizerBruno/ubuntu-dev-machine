#!/bin/bash
# Instala as melhorias deste repositório numa máquina Ubuntu de desenvolvimento. Pergunta componente por
# componente; as partes de root ficam desligadas por padrão e pedem a senha do sudo uma vez só.
#
# Uso: ./install.sh [--yes] [--dry-run] [--only LISTA]
#   --yes          aceita as respostas padrão sem perguntar
#   --dry-run      mostra o que faria, sem mudar nada
#   --only LISTA   instala só esses componentes, sem perguntar, separados por vírgula:
#                  cleanup, gradle, emulador, gnome, slack, skills, snaps, apt
#
# Sem terminal interativo (rodando pelo Claude, por exemplo) vale --yes: só os padrões, sem as partes de root.

set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"
MANIFEST="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-dev-machine/installed"
SKILLS_REPO="${CLAUDE_SKILLS_REPO:-https://github.com/PolizerBruno/claude-skills.git}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")/GitHub/claude-skills}"
ASSUME_YES=false
DRY_RUN=false
ONLY=""
ROOT_CMDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --yes | -y) ASSUME_YES=true ;;
    --dry-run | -n) DRY_RUN=true ;;
    --only)
      ONLY=",${2:?--only precisa de uma lista},"
      shift
      ;;
    -h | --help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      exit 1
      ;;
  esac
  shift
done

run() {
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

# ask componente "pergunta" s|n  →  0 para sim. O último argumento é a resposta padrão.
ask() {
  local component=$1 question=$2 default=$3 reply hint="[S/n]"
  [ "$default" = n ] && hint="[s/N]"
  if [ -n "$ONLY" ]; then
    if [[ "$ONLY" == *",$component,"* ]]; then
      echo "$question sim (--only)"
      return 0
    fi
    echo "$question não (fora do --only)"
    return 1
  fi
  if [ "$ASSUME_YES" = true ] || [ ! -t 0 ]; then
    echo "$question $hint ${default}"
    [ "$default" = s ]
    return
  fi
  read -r -p "$question $hint " reply
  reply=${reply:-$default}
  [[ "$reply" =~ ^[sSyY] ]]
}

record() {
  run mkdir -p "$(dirname "$MANIFEST")"
  if [ "$DRY_RUN" = false ] && ! grep -qx "$1" "$MANIFEST" 2>/dev/null; then
    echo "$1" >>"$MANIFEST"
  fi
}

install_bin() {
  local name=$1 dst="$BIN/$1"
  if [ -f "$dst" ] && ! cmp -s "$REPO/bin/$name" "$dst"; then
    run cp -p "$dst" "$dst.bak-$(date +%Y%m%d%H%M%S)"
    echo "  $dst já existia e era diferente; cópia de segurança ao lado (.bak-*)"
  fi
  run install -Dm755 "$REPO/bin/$name" "$dst"
}

header() { printf '\n\033[1m%s\033[0m\n' "$*"; }

echo "ubuntu-dev-machine: instalação em $HOME (usuário $USER)"
[ "$DRY_RUN" = true ] && echo "(dry-run: nada será alterado)"

missing=()
command -v notify-send >/dev/null || missing+=(libnotify-bin)
python3 -c 'import gi' 2>/dev/null || missing+=(python3-gi)
command -v zenity >/dev/null || missing+=(zenity)
if [ ${#missing[@]} -gt 0 ]; then
  echo
  echo "Faltam pacotes para os avisos com botão (o resto funciona sem eles): ${missing[*]}"
  echo "  sudo apt install ${missing[*]}"
fi

header "1. Limpeza de memória e disco (dev-cleanup)"
cat <<'EOF'
   Timer de 30 min: encerra daemons Gradle/Kotlin ociosos, processos Node órfãos, temporários de build,
   caches de yarn/npm/Gradle esquecidos; avisa de lixeiras escondidas de apps snap.
   Vigia a cada 15s: põe builds na menor prioridade de CPU e, com a RAM acabando, libera memória antes
   da máquina travar. Tudo no seu usuário, sem sudo.
EOF
if ask cleanup "   Instalar?" s; then
  install_bin dev-cleanup
  install_bin dev-machine-doctor
  for unit in dev-cleanup.service dev-cleanup.timer dev-cleanup-watch.service; do
    run install -Dm644 "$REPO/systemd/user/$unit" "$UNITS/$unit"
  done
  run systemctl --user daemon-reload
  run systemctl --user enable --now dev-cleanup.timer dev-cleanup-watch.service
  run systemctl --user restart dev-cleanup-watch.service
  record cleanup
fi

header "2. Gradle: encerrar daemons ociosos em 30 min e rodar com prioridade baixa"
props="$HOME/.gradle/gradle.properties"
if grep -q '^org.gradle.daemon.idletimeout' "$props" 2>/dev/null; then
  echo "   Já configurado em $props."
elif ask gradle "   Adicionar a $props?" s; then
  run mkdir -p "$(dirname "$props")"
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] acrescentar org.gradle.daemon.idletimeout=1800000 e org.gradle.priority=low em $props"
  else
    # Bloco delimitado para o uninstall.sh tirar exatamente o que foi posto aqui.
    {
      echo ""
      echo "# >>> ubuntu-dev-machine: daemons ociosos não ocupam RAM por horas; builds não disputam CPU"
      echo "org.gradle.daemon.idletimeout=1800000"
      grep -q '^org.gradle.priority' "$props" 2>/dev/null || echo "org.gradle.priority=low"
      echo "# <<< ubuntu-dev-machine"
    } >>"$props"
  fi
  record gradle
fi

header "3. Android Emulator"
if [ -d "${ANDROID_HOME:-$HOME/Android/Sdk}" ] || [ -d "$HOME/Android/sdk" ]; then
  cat <<'EOF'
   Script 'emulador': abre o AVD com GPU do host, sem snapshot e com a tela em resolução reduzida (mesmo
   layout em dp, ~70% menos pixels para desenhar). 'emulador --hd' volta à resolução original.
EOF
  if ask emulador "   Instalar o script emulador?" s; then
    install_bin emulador
    record emulador
  fi
  if [ "${XDG_CURRENT_DESKTOP:-}" != "${XDG_CURRENT_DESKTOP/GNOME/}" ]; then
    timeout=$(gsettings get org.gnome.mutter check-alive-timeout 2>/dev/null | awk '{print $NF}')
    if [ "${timeout:-0}" != 0 ]; then
      cat <<'EOF'
   No GNOME/Wayland o emulador dispara "Emulator não está respondendo" o tempo todo, mesmo respondendo
   (mutter #3543). Dá para desligar essa checagem do GNOME (vale para todos os apps).
EOF
      if ask gnome "   Desligar o aviso 'não está respondendo' do GNOME?" s; then
        run gsettings set org.gnome.mutter check-alive-timeout 0
        record gnome
      fi
    fi
  fi
else
  echo "   Android SDK não encontrado; pulando."
fi

header "4. Slack (snap): compartilhamento de tela no Wayland"
if [ -f /var/lib/snapd/desktop/applications/slack_slack.desktop ]; then
  slack_check=$("$REPO/bin/fix-slack-screenshare" --check)
  if grep -q 'já está aplicada' <<<"$slack_check"; then
    echo "   Correção já aplicada."
  elif grep -q 'não encontra' <<<"$slack_check"; then
    if ask slack "   O compartilhamento de tela do Slack vai falhar. Corrigir?" s; then
      install_bin fix-slack-screenshare
      if run "$BIN/fix-slack-screenshare"; then
        record slack
      else
        echo "   Não apliquei a correção do Slack; veja a mensagem acima."
      fi
    fi
  else
    echo "   Não precisa: $(tail -1 <<<"$slack_check")"
  fi
else
  echo "   Slack snap não instalado; pulando."
fi

header "5. Skills do Claude Code"
cat <<EOF
   Linka cada skill de $SKILLS_REPO em ~/.claude/skills, para o Claude Code
   usar em todos os projetos. Clona em $SKILLS_DIR se ainda não estiver lá.
   Outro repositório ou pasta: CLAUDE_SKILLS_REPO=url CLAUDE_SKILLS_DIR=pasta ./install.sh
EOF
# Desligado por padrão: o repositório padrão é privado. Liga sozinho quando o clone já existe.
skills_default=n
[ -d "$SKILLS_DIR" ] && skills_default=s
if ask skills "   Instalar?" "$skills_default"; then
  if [ ! -e "$SKILLS_DIR" ] && ! run git clone -q "$SKILLS_REPO" "$SKILLS_DIR"; then
    echo "   Não consegui clonar $SKILLS_REPO. Se for privado: gh auth login && gh auth setup-git"
  elif [ "$DRY_RUN" = true ] || [ -x "$SKILLS_DIR/install.sh" ]; then
    run "$SKILLS_DIR/install.sh"
    record skills
  else
    echo "   $SKILLS_DIR não tem install.sh; pulando."
  fi
fi

header "6. Partes de root (pedem a senha do sudo uma vez no fim)"
cat <<'EOF'
   snaps: remove toda semana as versões antigas guardadas dos snaps (pula as que ainda estão em uso).
   apt:   toda segunda 12:30, update + upgrade (sem remover pacotes) + autoremove + clean, com aviso no
          fim e alerta se o driver NVIDIA (DKMS) não foi compilado para um kernel novo.
EOF
if command -v snap >/dev/null && ask snaps "   Instalar a limpeza semanal de snaps?" n; then
  ROOT_CMDS+=("install -m 0755 '$REPO/system/snap-prune-disabled' /usr/local/sbin/snap-prune-disabled"
    "install -m 0644 '$REPO/system/snap-prune-disabled.service' '$REPO/system/snap-prune-disabled.timer' /etc/systemd/system/"
    "systemctl daemon-reload"
    "systemctl enable --now snap-prune-disabled.timer")
  record snaps
fi
if ask apt "   Instalar a atualização semanal do apt?" n; then
  ROOT_CMDS+=("install -m 0755 '$REPO/system/apt-weekly-maintenance' /usr/local/sbin/apt-weekly-maintenance"
    "install -m 0644 '$REPO/system/apt-weekly-maintenance.service' '$REPO/system/apt-weekly-maintenance.timer' /etc/systemd/system/"
    "systemctl daemon-reload"
    "systemctl enable --now apt-weekly-maintenance.timer")
  record apt
fi
if [ ${#ROOT_CMDS[@]} -gt 0 ]; then
  script=$(printf '%s && ' "${ROOT_CMDS[@]}")
  script=${script% && }
  if [ "$DRY_RUN" = true ]; then
    echo "    [dry-run] sudo sh -c \"$script\""
  else
    sudo sh -c "$script"
  fi
fi

header "Pronto"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "Atenção: $BIN não está no PATH; abra um terminal novo ou adicione ao ~/.bashrc / ~/.zshrc." ;;
esac
echo "Diagnóstico: dev-machine-doctor | Limpeza agora: dev-cleanup | Desfazer: $REPO/uninstall.sh"
