# 🚀 Guia Completo — Servidor Minecraft Java no Google Cloud

> Guia reproduzível para qualquer pessoa criar um servidor Minecraft Java Edition usando os créditos gratuitos do Google Cloud Platform.
>
> **Versão testada:** PaperMC 1.21.11 | Ubuntu 22.04 LTS | e2-standard-2 (São Paulo)

---

## ⚡ Instalação automática (recomendado)

Se preferir não seguir o guia manual, use o script `create-server.sh` para criar e configurar tudo automaticamente — VM, firewall, PaperMC, AuthMe, Chunky e systemd — com um único comando.

### Pré-requisitos para o script

- Conta Google com billing ativado e créditos disponíveis
- **Windows:** [Git Bash](https://gitforwindows.org/) ou [WSL](https://learn.microsoft.com/pt-br/windows/wsl/install)
- **macOS:** Terminal + [Homebrew](https://brew.sh/) (para instalar o gcloud automaticamente)
- **Linux:** Terminal

### Executar

```bash
# Baixar o script
wget https://raw.githubusercontent.com/vinicius-eng20/servidor-minecraft-gcp/main/create-server.sh

# Dar permissão e executar
chmod +x create-server.sh && ./create-server.sh
```

O script irá:

1. Instalar o gcloud CLI automaticamente (se necessário)
2. Abrir o navegador para autenticação com sua conta Google
3. Perguntar nome do projeto, versão do Minecraft, número de jogadores e raio de pré-geração de chunks
4. Criar a VM, configurar o firewall, instalar o PaperMC, AuthMe e Chunky
5. Configurar o systemd para iniciar/parar o servidor automaticamente com a VM
6. Exibir o IP do servidor ao final

> Se preferir fazer tudo manualmente ou entender cada etapa em detalhe, siga o guia abaixo.

---

## Pré-requisitos

- Conta Google
- Cartão de crédito (para verificação — não será cobrado automaticamente)
- Minecraft Java Edition (qualquer launcher)

---

## Sumário

1. [Criando a conta e a VM no GCP](#1-criando-a-conta-e-a-vm-no-gcp)
2. [Configurando o firewall](#2-configurando-o-firewall)
3. [Instalando o servidor](#3-instalando-o-servidor)
4. [Configurando o servidor](#4-configurando-o-servidor)
5. [Importando um mundo existente](#5-importando-um-mundo-existente)
6. [Instalando os plugins](#6-instalando-os-plugins)
7. [Protegendo o servidor com AuthMe](#7-protegendo-o-servidor-com-authme)
8. [Pré-gerando chunks com Chunky](#8-pré-gerando-chunks-com-chunky)
9. [Scripts de automação](#9-scripts-de-automação)
10. [Ligando e desligando a VM](#10-ligando-e-desligando-a-vm)
11. [Exportando o mundo](#11-exportando-o-mundo)

---

## 1. Criando a conta e a VM no GCP

### 1.1 Ativar os créditos

1. Acesse [console.cloud.google.com](https://console.cloud.google.com)
2. Faça login com sua conta Google
3. Crie um projeto (ex: `minecraft-server`)
4. Ative os **$300 de crédito gratuito** quando solicitado

> Você precisará de cartão de crédito para verificação, mas **não será cobrado automaticamente** — a cobrança só começa se você manualmente ativar a conta paga após os créditos acabarem.

### 1.2 Criar a VM

Navegue até **Compute Engine → VM Instances → + CREATE INSTANCE** e preencha:

| Campo | Valor |
|---|---|
| Name | `minecraft-server` |
| Region | `southamerica-east1` (São Paulo) |
| Zone | `southamerica-east1-b` |
| Machine family | General purpose |
| Series | E2 |
| Machine type | `e2-standard-2` |
| Boot disk OS | Ubuntu 22.04 LTS |
| Boot disk type | SSD persistent disk |
| Boot disk size | 30 GB |
| Firewall | ✅ Allow HTTP ✅ Allow HTTPS |

Clique em **Create** e aguarde a VM inicializar.

### 1.3 Reservar IP estático

Para que o endereço do servidor não mude a cada reinicialização:

1. Vá em **VPC Network → IP Addresses**
2. Clique em **+ RESERVE EXTERNAL STATIC IP ADDRESS**
3. Dê um nome (ex: `minecraft-ip`), selecione a região `southamerica-east1`
4. Clique em **Reserve** e associe à VM `minecraft-server`

---

## 2. Configurando o firewall

O Minecraft usa a porta **25565 TCP**. Crie a regra pelo terminal com o gcloud CLI ou pelo console do GCP.

### Via console do GCP

Vá em **VPC Network → Firewall → + CREATE FIREWALL RULE**:

| Campo | Valor |
|---|---|
| Name | `allow-minecraft` |
| Direction | Ingress |
| Targets | All instances in the network |
| Source IPv4 ranges | `0.0.0.0/0` |
| Protocols and ports | TCP `25565` |

### Via gcloud CLI (alternativa)

```bash
gcloud compute firewall-rules create allow-minecraft \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:25565 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=minecraft

gcloud compute instances add-tags minecraft-server \
  --tags=minecraft \
  --zone=southamerica-east1-b
```

---

## 3. Instalando o servidor

Clique em **SSH** na lista de VMs para abrir o terminal. Execute:

### 3.1 Atualizar o sistema e instalar dependências

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install openjdk-21-jdk-headless screen unzip -y

# Verificar instalação do Java
java -version
```

### 3.2 Criar a pasta e baixar o PaperMC

```bash
mkdir ~/minecraft && cd ~/minecraft

# Baixar o build mais recente do PaperMC 1.21.11
BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/1.21.11/builds" \
  | grep -o '"build":[0-9]*' | tail -1 | grep -o '[0-9]*')

wget -O server.jar "https://api.papermc.io/v2/projects/paper/versions/1.21.11/builds/$BUILD/downloads/paper-1.21.11-$BUILD.jar"

# Aceitar o EULA
echo "eula=true" > eula.txt
```

### 3.3 Primeira inicialização

```bash
java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
```

Aguarde aparecer `Done!` no console, depois pare o servidor:

```
stop
```

---

## 4. Configurando o servidor

### 4.1 server.properties

```bash
nano ~/minecraft/server.properties
```

Altere os seguintes valores:

```properties
# Performance
view-distance=6
simulation-distance=4
sync-chunk-writes=false

# Rede — CRÍTICO para evitar timeout na GCP
network-compression-threshold=64

# Contas offline (TLauncher, MultiMC, etc.)
online-mode=false
enforce-secure-profile=false

# Geral
max-players=10
server-ip=
server-port=25565
```

> ⚠️ **`network-compression-threshold=64` é essencial na GCP.** A rede VPC usa MTU de 1460 bytes (vs 1500 da internet residencial). Sem essa configuração, pacotes grandes de chunks são fragmentados e descartados, causando timeout de 30 segundos ao entrar no servidor.

> ⚠️ **`enforce-secure-profile=false` é obrigatório com launchers não oficiais.** Desde o Minecraft 1.19, o jogo valida chaves criptográficas com a Mojang. Com contas offline, isso gera erro 401 e trava a conexão.

### 4.2 spigot.yml

```bash
nano ~/minecraft/spigot.yml
```

```yaml
timeout-time: 120
```

### 4.3 config/paper-global.yml

```bash
nano ~/minecraft/config/paper-global.yml
```

Localize a seção `misc` e configure:

```yaml
misc:
  client-reader-timeout: 120
  compression-level: default
```

> ⚠️ YAML é sensível a indentação — use exatamente 2 espaços em cada nível. Um espaço a menos invalida a configuração silenciosamente.

### 4.4 Proteção contra spam de pacotes (paper-global.yml)

```yaml
packet-limiter:
  kick-on-violation: true
  all-packets:
    action: KICK
    interval: 7.0
    max-packet-rate: 500.0
```

---

## 5. Importando um mundo existente

Siga esta seção apenas se quiser usar um mundo já criado. Pule para a [seção 6](#6-instalando-os-plugins) para começar um mundo novo.

### 5.1 Preparar o mundo no seu PC

Localize a pasta do mundo em:
- **Windows:** `%APPDATA%\.minecraft\saves\NOME_DO_MUNDO`
- **Linux/Mac:** `~/.minecraft/saves/NOME_DO_MUNDO`

Compacte a pasta em um arquivo `.zip`.

### 5.2 Enviar para a VM

**Via navegador (mais fácil):** na janela SSH do GCP, clique em **⚙️ → Upload file**

**Via gcloud CLI:**
```bash
# No terminal do seu PC
gcloud compute scp ./NOME_DO_MUNDO.zip \
  minecraft-server:~/minecraft/ \
  --zone=southamerica-east1-b
```

### 5.3 Extrair e posicionar na VM

```bash
cd ~/minecraft

# Remover mundo gerado automaticamente pelo servidor
rm -rf world world_nether world_the_end

# Extrair
unzip NOME_DO_MUNDO.zip

# Renomear para "world" (nome padrão do servidor)
mv NOME_DO_MUNDO world
```

### 5.4 Verificar

```bash
ls ~/minecraft/world/
# Deve mostrar: level.dat, region/, entities/, etc.

ls ~/minecraft/world/region/ | wc -l
# Deve mostrar um número maior que 0
```

### 5.5 Definir o spawn corretamente

Na primeira inicialização com o mundo importado, defina o spawn nas coordenadas corretas do seu mundo. No console do servidor:

```
setworldspawn X Y Z
```

Substitua X, Y, Z pelas coordenadas da área principal do seu mundo.

---

## 6. Instalando os plugins

### 6.1 Criar a pasta de plugins

```bash
mkdir -p ~/minecraft/plugins
```

### 6.2 Chunky — Pré-geração de chunks

```bash
cd ~/minecraft/plugins
wget -O Chunky.jar \
  "https://hangarcdn.papermc.io/plugins/pop4959/Chunky/versions/1.4.40/PAPER/Chunky-Bukkit-1.4.40.jar"
```

### 6.3 AuthMe — Autenticação de jogadores

```bash
cd ~/minecraft/plugins
wget https://github.com/AuthMe/AuthMeReloaded/releases/download/5.6.0/AuthMe-5.6.0.jar
sudo chown -R $USER:$USER ~/minecraft/plugins/
```

---

## 7. Protegendo o servidor com AuthMe

Com `online-mode=false`, qualquer pessoa que souber o IP pode entrar usando qualquer nome. O AuthMe resolve isso.

### 7.1 Gerar os arquivos de configuração

Inicie o servidor uma vez para o AuthMe gerar seus arquivos:

```bash
screen -S minecraft
java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
```

Após o `Done!`, pare o servidor:
```
stop
```

### 7.2 Editar a configuração do AuthMe

```bash
nano ~/minecraft/plugins/AuthMe/config.yml
```

Configurações recomendadas:

```yaml
# Idioma das mensagens
messagesLanguage: 'br'

# Máximo de contas por IP — previne bots
maxRegPerIp: 2

# Sessão — evita re-login após queda rápida
sessions:
  enabled: true
  timeout: 10
```

### 7.3 Comandos dos jogadores

```
/register senha senha    # Primeiro acesso
/login senha             # Acessos seguintes
```

---

## 8. Pré-gerando chunks com Chunky

A pré-geração evita lag quando jogadores exploram novas áreas. **Execute isso antes de liberar o servidor para os jogadores.**

### 8.1 Iniciar o servidor

```bash
screen -S minecraft
java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
```

### 8.2 Gerar em etapas (recomendado)

No console do servidor:

```
chunky center 0 0
chunky radius 1000
chunky start
```

Acompanhe o progresso:
```
chunky status
```

Quando chegar em 100%, expanda:
```
chunky radius 3000
chunky start
```

Por fim:
```
chunky radius 5000
chunky start
```

### 8.3 Definir o World Border

Após terminar, impeça exploração além da área pré-gerada:

```
/worldborder center 0 0
/worldborder set 10000
```

### 8.4 Referência de custo

| Raio | Chunks | Disco | Tempo (e2-standard-2) |
|---|---|---|---|
| 1.000 blocos | ~4k | ~200 MB | 10–20 min |
| 3.000 blocos | ~113k | ~1–2 GB | 2–5h |
| 5.000 blocos | ~200k | ~5 GB | 8–15h |

> O Chunky precisa ser rodado **apenas uma vez**. Os chunks ficam salvos no disco e persistem entre reinicializações da VM.

---

## 9. Scripts de automação

Crie os três scripts abaixo. Eles automatizam a inicialização, o desligamento seguro e a exportação do mundo.

### 9.1 start.sh

```bash
nano ~/minecraft/start.sh
```

```bash
#!/bin/bash
cd /home/$(whoami)/minecraft
screen -dmS minecraft java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
```

### 9.2 stop.sh

```bash
nano ~/minecraft/stop.sh
```

```bash
#!/bin/bash
screen -S minecraft -X stuff "stop$(printf '\r')"
sleep 10
```

### 9.3 export_world.sh

```bash
nano ~/minecraft/export_world.sh
```

```bash
#!/bin/bash

echo "⏳ Preparando exportação do mundo..."

cd ~/minecraft

# Reintegra nether e the_end ao formato single player
cp -r world_nether/DIM-1 world/DIM-1
cp -r world_the_end/DIM1 world/DIM1

zip -r ~/mundo_exportado.zip world

echo "✅ Mundo exportado com sucesso em ~/mundo_exportado.zip"
echo ""
echo "📥 Para baixar:"
echo "   gcloud compute scp minecraft-server:~/mundo_exportado.zip ./ --zone=southamerica-east1-b"
echo "   Ou pelo navegador: SSH → ⚙️ → Download file → /home/$(whoami)/mundo_exportado.zip"
```

### 9.4 Dar permissão de execução

```bash
chmod +x ~/minecraft/start.sh
chmod +x ~/minecraft/stop.sh
chmod +x ~/minecraft/export_world.sh
```

### 9.5 Criar o serviço systemd

O systemd garante que o servidor inicia automaticamente quando a VM liga e para corretamente quando a VM é desligada.

```bash
sudo nano /etc/systemd/system/minecraft.service
```

Substitua `SEU_USUARIO` pelo seu usuário real (verifique com `whoami`):

```ini
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=SEU_USUARIO
ExecStart=/home/SEU_USUARIO/minecraft/start.sh
ExecStop=/home/SEU_USUARIO/minecraft/stop.sh
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

Ativar o serviço:

```bash
sudo systemctl daemon-reload
sudo systemctl enable minecraft
sudo systemctl start minecraft
```

---

## 10. Ligando e desligando a VM

### Pelo console do GCP (navegador)

**Desligar:**
1. Acesse [console.cloud.google.com](https://console.cloud.google.com)
2. Vá em **Compute Engine → VM Instances**
3. Marque sua VM → clique em **⊙ STOP**

> ⚠️ O systemd roda o `stop.sh` automaticamente antes de desligar, salvando o mundo.

**Ligar:**
1. Marque sua VM (status: Stopped)
2. Clique em **▶ START/RESUME**
3. O servidor sobe automaticamente via systemd

### Via gcloud CLI

```bash
# Instale o gcloud CLI em: https://cloud.google.com/sdk/docs/install

# Ligar
gcloud compute instances start minecraft-server --zone=southamerica-east1-b

# Desligar
gcloud compute instances stop minecraft-server --zone=southamerica-east1-b

# Ver IP atual
gcloud compute instances list

# SSH direto
gcloud compute ssh minecraft-server --zone=southamerica-east1-b
```

### Verificar se o servidor está rodando

```bash
# Processo Java ativo?
ps aux | grep java | grep -v grep

# Porta escutando?
ss -tlnp | grep 25565

# Teste local
nc -zv localhost 25565
```

---

## 11. Exportando o mundo

Quando decidir encerrar o servidor, execute:

```bash
~/minecraft/export_world.sh
```

Baixe o arquivo para o seu PC:

```bash
# No terminal do seu PC
gcloud compute scp \
  minecraft-server:~/mundo_exportado.zip \
  ./ \
  --zone=southamerica-east1-b
```

Extraia o zip e coloque a pasta em:

```
# Windows
%APPDATA%\.minecraft\saves\

# Linux/Mac
~/.minecraft/saves/
```

O mundo aparecerá normalmente na lista de mundos do single player com nether e the_end intactos.

---

## Checklist final

```
☐ Conta GCP criada e créditos ativados
☐ VM e2-standard-2 criada em southamerica-east1
☐ IP estático reservado e associado à VM
☐ Porta 25565 aberta no firewall
☐ Java 21 e Screen instalados
☐ PaperMC baixado e EULA aceita
☐ server.properties configurado (network-compression-threshold=64, enforce-secure-profile=false)
☐ spigot.yml e paper-global.yml configurados
☐ Mundo importado (se aplicável) e spawn definido
☐ AuthMe instalado e configurado
☐ Chunky instalado e chunks pré-gerados
☐ World border definido
☐ Scripts start.sh, stop.sh e export_world.sh criados
☐ Serviço systemd ativo (sudo systemctl enable minecraft)
☐ Alerta de billing configurado no GCP
```

---

## Comandos de referência rápida

```bash
# Iniciar servidor manualmente
cd ~/minecraft && screen -S minecraft java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui

# Reconectar ao console do servidor
screen -r minecraft

# Sair do console sem fechar o servidor
# Ctrl+A → D

# Ver IP externo da VM
curl ifconfig.me

# Ver logs em tempo real
tail -f ~/minecraft/logs/latest.log

# Exportar mundo
~/minecraft/export_world.sh
```
