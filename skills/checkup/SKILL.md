---
name: checkup
description: Diagnostica e corrige uma máquina Ubuntu de desenvolvimento lenta, travando ou sem espaço. Use quando a pessoa disser que a máquina está lenta, travando, sem memória, com swap cheio ou disco cheio; quando builds Gradle/React Native/EAS pesarem demais; quando o compartilhamento de tela do Slack falhar no Wayland; quando o GNOME mostrar "Emulator não está respondendo"; ou quando pedir para configurar limpeza automática ou atualização semanal. Also use for: slow/freezing Ubuntu dev machine, out of memory, full disk, Slack screen share broken on Wayland, Android emulator "not responding" on GNOME.
---

# Checkup de máquina Ubuntu de desenvolvimento

Os scripts deste plugin ficam em `${CLAUDE_PLUGIN_ROOT}`. O `README.md` de lá explica cada problema em detalhe.

## Regras
- Diagnostique antes de mudar qualquer coisa, e explique o que encontrou em linguagem simples, com números.
- Instale só o que a pessoa aprovar. Nunca apague dados dela (lixeiras, dados de AVD, modelos, projetos): mostre o tamanho e o comando, e deixe que ela rode.
- Partes de root (timers de snaps e apt) precisam da senha do sudo: você não consegue digitá-la. Mostre o comando para a pessoa rodar no terminal dela.
- Não encerre processos que não são de build: apps abertos, servidores de outras sessões do Claude e emuladores ficam.

## 1. Diagnóstico
Rode e leia a saída inteira:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/dev-machine-doctor"
```
Linhas `!!` são o que vale corrigir; `--` é contexto. Se a pessoa reclamou de travamento, veja também a memória ao longo do dia (`sar -r -S` se o sysstat estiver instalado) e o PSI em `/proc/pressure/memory`.

## 2. O que fazer com cada achado

| Achado (`!!`) | Correção | Componente do install.sh |
|---|---|---|
| `dev-cleanup.timer` / `dev-cleanup-watch.service` não ativos | Limpeza a cada 30 min + vigia de memória a cada 15s | `cleanup` |
| `/tmp` é tmpfs e builds do EAS vão para a RAM | O dev-cleanup cria `/tmp/$USER` no disco | `cleanup` |
| Daemons do Gradle ficam 3h ociosos | `org.gradle.daemon.idletimeout=1800000` | `gradle` |
| Lixeiras escondidas de snaps (GBs) | Explique: o VS Code snap guarda o que é apagado pelo explorador dele em `~/snap/code/<rev>/.local/share/Trash`, fora da lixeira do GNOME, e copia tudo a cada atualização. Mostre os caminhos e tamanhos; a pessoa esvazia (`rm -rf ~/snap/*/*/.local/share/Trash`) ou usa o botão do aviso do dev-cleanup | `cleanup` (só avisa) |
| Caches de yarn/npm/Gradle grandes | O dev-cleanup limpa uma vez por dia: yarn/npm acima de 2 GB, versões do Gradle sem uso há 30 dias | `cleanup` |
| Slack snap: compartilhamento de tela | `fix-slack-screenshare`; depois a pessoa fecha o Slack com Ctrl+Q e abre de novo | `slack` |
| "Emulator não está respondendo" no GNOME | Falso alarme do mutter (#3543); `check-alive-timeout 0` desliga a checagem para todos os apps | `gnome` |
| AVDs renderizando em resolução alta | Script `emulador` com resolução reduzida e mesmo layout em dp | `emulador` |
| Revisões antigas de snaps, pacotes órfãos | Timers semanais de root | `snaps`, `apt` |
| NVIDIA DKMS sem módulo no kernel mais novo | Não reiniciar; `dkms status` e `sudo dkms autoinstall` | — |

## 3. Instalar o que foi aprovado
Componentes sem sudo, direto (troque a lista pelo que a pessoa aprovou):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/install.sh" --only cleanup,gradle
```
Para conferir antes, `--dry-run` mostra o que seria feito. As partes de root (`snaps`, `apt`) a pessoa roda no terminal dela, que pede a senha:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/install.sh" --only snaps,apt
```
Depois, rode o `dev-machine-doctor` de novo e mostre o antes e depois.

## 4. Desfazer
```bash
bash "${CLAUDE_PLUGIN_ROOT}/uninstall.sh"
```
