# ubuntu-dev-machine

Correções e automações para máquinas **Ubuntu de desenvolvimento** (testado no Ubuntu 26.04, GNOME 50 em
Wayland, NVIDIA): memória e builds que travam a máquina, disco que some sem explicação, Slack que não
compartilha tela e o falso "não está respondendo" do Android Emulator.

Funciona de dois jeitos: como **plugin do Claude Code**, em que o Claude diagnostica a sua máquina e
instala só o que faz sentido nela, ou com o **`install.sh`**, que pergunta componente por componente.

## O que resolve

| Sintoma | Causa | Correção |
|---|---|---|
| Máquina trava durante builds; swap enche em minutos | Builds Gradle/Kotlin/React Native disputam CPU e RAM com o desktop; daemons ociosos ficam horas na memória | Vigia de memória a cada 15s: builds com prioridade mínima e, com a RAM acabando, derruba o build antes de travar |
| `node_modules` "lotando a memória" em builds do EAS local | `/tmp` é tmpfs (RAM) e o `eas-cli build --local` monta o projeto inteiro em `/tmp/$USER` | `/tmp/$USER` vira link para o disco; o comando do build não muda |
| Disco cheio sem explicação | O VS Code snap guarda o que você apaga pelo explorador dele numa lixeira própria (`~/snap/code/<rev>/.local/share/Trash`) que não aparece no GNOME e é copiada a cada atualização. Já foram 160 GB numa máquina | Aviso quando passa de 5 GB, com botão para esvaziar (pede confirmação) |
| Caches de pacotes crescendo para sempre | yarn/npm guardam toda versão baixada; o Gradle guarda GBs por versão, mesmo sem uso | Limpeza diária: yarn/npm acima de 2 GB, versões do Gradle sem uso há 30 dias |
| Slack: "Verifique as preferências do sistema para permitir o compartilhamento de tela" | O snap do Slack não aponta `PIPEWIRE_CONFIG_DIR` para o `client.conf` que ele mesmo carrega: `Failed to create PipeWire context` | Atalho do usuário que abre o Slack com a variável |
| GNOME: "Emulator não está respondendo" o tempo todo | Falso alarme do mutter no Wayland ([mutter#3543](https://gitlab.gnome.org/GNOME/mutter/-/issues/3543)): o emulador responde ao ping em milissegundos | `gsettings set org.gnome.mutter check-alive-timeout 0` |
| Emulador pesado | AVDs recentes renderizam 1280×2856 numa janela de ~470×990 | Script `emulador`: resolução reduzida com o mesmo layout em dp (−75% de GPU rolando a tela) |
| Snaps e apt acumulando lixo | Revisões antigas de snaps e pacotes órfãos | Timers semanais (root): remove revisões antigas; update + upgrade + autoremove |

## Instalação

### Pelo Claude Code (recomendado)
```
/plugin marketplace add PolizerBruno/ubuntu-dev-machine
/plugin install ubuntu-dev-machine@ubuntu-dev-machine
```
Depois peça "minha máquina está lenta" ou rode `/ubuntu-dev-machine:checkup`. O Claude roda o diagnóstico,
explica o que achou e instala só o que você aprovar. As partes de root ficam para você rodar.

### Sem o Claude
```bash
git clone https://github.com/PolizerBruno/ubuntu-dev-machine.git
cd ubuntu-dev-machine
./install.sh            # pergunta componente por componente
./install.sh --dry-run  # só mostra o que faria
```

Dependências dos avisos com botão (o resto funciona sem elas): `sudo apt install libnotify-bin python3-gi zenity`.

## Componentes

| Componente | O que instala | Precisa de sudo | Padrão |
|---|---|---|---|
| `cleanup` | `dev-cleanup` + timer de 30 min + vigia de memória (`~/.local/bin`, `~/.config/systemd/user`) | não | sim |
| `gradle` | `org.gradle.daemon.idletimeout=1800000` e `org.gradle.priority=low` em `~/.gradle/gradle.properties` | não | sim |
| `emulador` | Script `emulador` (só se houver Android SDK) | não | sim |
| `gnome` | `check-alive-timeout 0` (só no GNOME com Android SDK) | não | sim |
| `slack` | Correção do compartilhamento de tela (só se o Slack snap precisar) | não | sim |
| `skills` | Clona um repositório de skills do Claude Code em `~/Documentos/GitHub/claude-skills` e linka cada skill em `~/.claude/skills`. Repositório e pasta mudam com `CLAUDE_SKILLS_REPO` e `CLAUDE_SKILLS_DIR` | não | só se a pasta já existir |
| `snaps` | Remoção semanal das revisões antigas de snaps | sim | não |
| `apt` | Toda segunda 12:30: update, upgrade sem remover pacotes, autoremove, clean; avisa se o driver NVIDIA não compilou para o kernel novo | sim | não |

Ferramentas que ficam no PATH:
- `dev-machine-doctor`: diagnóstico, só lê.
- `dev-cleanup [-n]`: limpeza agora (`-n` = simulação).
- `emulador [--hd]`: abre o AVD.
- `fix-slack-screenshare [--check|--remove]`: correção do Slack.

### O que o `dev-cleanup` faz
- **A cada 30 min:**
  - encerra daemons Gradle **ociosos** (os em uso ficam) e daemons Kotlin órfãos;
  - encerra processos Node órfãos (dev servers cujo terminal fechou);
  - apaga temporários de build com mais de 2h e working dirs do EAS de builds que já acabaram.
- **A cada 15s (vigia):**
  - põe em prioridade mínima de CPU e disco todas as threads de Gradle, Kotlin, `ninja`, `clang` e `aapt2`;
  - abaixo de ~19% de RAM livre, limpa o que está ocioso e avisa;
  - abaixo de ~9%, ou com a máquina travando por falta de memória (PSI), derruba os builds Gradle/Kotlin.
- **1× por dia:** caches de yarn, npm e Gradle.
- **A cada 12h:** lixeiras escondidas de apps snap.
- **Nunca toca** em apps abertos (navegador, IDE, Slack, emulador) nem em arquivos seus.

Limites configuráveis por variável de ambiente; veja `dev-cleanup --help`.

## Desinstalar
```bash
./uninstall.sh   # desfaz só o que o install.sh registrou
```

## Detalhes técnicos que custaram para descobrir
- **Prioridade é por thread no Linux.** `renice` no PID só muda a thread principal, e o Gradle cria compiladores a partir de outras threads. O vigia rebaixa thread por thread, e os filhos herdam.
- **Botões em notificação no GNOME 50.** O `notify-send` 0.8.8 recusa botões ("Actions are not supported") mesmo com o servidor aceitando. Além disso, o GNOME só manda o clique para a conexão D-Bus que criou o aviso. Por isso o aviso com botão é feito por um trecho em Python (`gi`).
- **`INVOCATION_ID` não serve para saber se veio do timer.** Apps que rodam como serviço do systemd passam essa variável para os terminais deles. O serviço define `DEV_CLEANUP_TIMER=1`.
- **Emulador em resolução reduzida.** A moldura do aparelho ignora `hw.lcd.width/height`, mas aplica a densidade nova (o app ficaria quase 2× mais largo). Por isso o modo leve roda sem moldura. Os overlays de recorte de câmera do aparelho são desenhados em pixels da tela original, e o script desliga eles depois do boot. `--hd` volta tudo.
- **Slack snap.** A variável não pode ir em `environment.d`: o caminho só existe dentro do snap, e os outros apps quebrariam.

## Licença
MIT
