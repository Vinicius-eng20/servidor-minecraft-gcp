# 🎮 Servidor Minecraft no Google Cloud — Documentação Completa

> **Versão do servidor:** PaperMC 1.21.11 (Mounts of Mayhem)  
> **Infraestrutura:** Google Cloud Platform — VM e2-standard-2 (São Paulo)  
> **Launcher do cliente:** TLauncher (conta offline)  
> **Data:** Junho de 2026
---

**OBS.:** Caso queira criar um servidor de minecraft no Google Cloud, siga as instruções do documento `create-server-gcp.md`.

## Sumário

1. [Objetivo](#objetivo)
2. [Infraestrutura escolhida](#infraestrutura-escolhida)
3. [Processo de criação da VM](#processo-de-criação-da-vm)
4. [Instalação do servidor](#instalação-do-servidor)
5. [Importando um mundo existente](#importando-um-mundo-existente)
6. [Erros encontrados e soluções](#erros-encontrados-e-soluções)
7. [Configurações finais que funcionaram](#configurações-finais-que-funcionaram)
8. [Automação de inicialização e desligamento](#automação-de-inicialização-e-desligamento)
9. [Proteção com AuthMe](#proteção-com-authme)
10. [Pré-geração de chunks com Chunky](#pré-geração-de-chunks-com-chunky)
11. [Exportando o mundo](#exportando-o-mundo)
12. [Aprendizados](#aprendizados)
13. [Alternativa: Raspberry Pi 5](#alternativa-raspberry-pi-5)

---

## Objetivo

Criar um servidor de Minecraft Java Edition 1.21.11 na nuvem (Google Cloud Platform), com:

- Baixa latência para jogadores no Brasil
- Suporte a um mundo já existente (criado em single player)
- Pré-geração de chunks para evitar lag de exploração
- Uso casual com possibilidade de desligar a VM quando não estiver em uso
- Suporte a contas offline (TLauncher)
- Proteção contra usuários indesejados e ataques

---

## Infraestrutura escolhida

### Por que Google Cloud?

O Google Cloud oferece **$300 de crédito gratuito** para novos usuários, válidos por 90 dias. Existe também um free tier permanente com a instância **e2-micro**, porém com apenas 1 GB de RAM — suficiente apenas para 2–3 jogadores em vanilla sem plugins.

### Especificações da VM

| Campo | Valor |
|---|---|
| Tipo | e2-standard-2 |
| vCPUs | 2 |
| RAM | 8 GB |
| Disco | 30 GB SSD |
| Sistema operacional | Ubuntu 22.04 LTS |
| Região | southamerica-east1 (São Paulo) |
| Zona | southamerica-east1-b |

### Custo estimado

Com uso casual (~4h/dia, 20 dias/mês), a e2-standard-2 consome cerca de **$5–6/mês**, fazendo os $300 de crédito durarem mais de 4 anos.

> ⚠️ Configure alertas de billing em **Billing → Budgets & Alerts** para monitorar o consumo.

---

## Processo de criação da VM

### 1. Criar a conta e ativar os créditos

1. Acesse [console.cloud.google.com](https://console.cloud.google.com)
2. Faça login com sua conta Google
3. Crie um novo projeto (ex: `minecraft-server`)
4. Ative os $300 de crédito — precisará de cartão de crédito para verificação, mas **não será cobrado automaticamente**

### 2. Criar a instância

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
| Firewall | ✅ Allow HTTP e HTTPS |

### 3. Reservar IP estático

1. Vá em **VPC Network → IP Addresses**
2. Clique em **+ RESERVE EXTERNAL STATIC IP ADDRESS**
3. Dê um nome, selecione a região `southamerica-east1` e clique em **Reserve**
4. Associe à sua VM

> ⚠️ IP estático custa ~$7/mês mesmo com a VM desligada. Alternativa: usar IP efêmero e comunicar o novo IP aos jogadores a cada vez que ligar.

### 4. Abrir a porta 25565

Vá em **VPC Network → Firewall → + CREATE FIREWALL RULE**:

| Campo | Valor |
|---|---|
| Name | `allow-minecraft` |
| Direction | Ingress |
| Targets | All instances in the network |
| Source IPv4 ranges | `0.0.0.0/0` |
| Protocols and ports | TCP `25565` |

---

## Instalação do servidor

### Dependências

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install openjdk-21-jdk-headless screen unzip -y
```

### Download do PaperMC 1.21.11

O PaperMC é baixado **diretamente na VM** via API oficial:

```bash
mkdir ~/minecraft && cd ~/minecraft

BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/1.21.11/builds" \
  | grep -o '"build":[0-9]*' | tail -1 | grep -o '[0-9]*')

wget -O server.jar "https://api.papermc.io/v2/projects/paper/versions/1.21.11/builds/$BUILD/downloads/paper-1.21.11-$BUILD.jar"

echo "eula=true" > eula.txt
```

### Primeira inicialização

```bash
java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
# Aguardar "Done!", depois:
stop
```

### Configurações de performance

Editar `server.properties`:

```properties
view-distance=6
simulation-distance=4
sync-chunk-writes=false
online-mode=false
enforce-secure-profile=false
network-compression-threshold=64
max-players=10
```

### Inicialização com Screen

```bash
screen -S minecraft
java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
# Sair do Screen sem fechar: Ctrl+A → D
# Reconectar: screen -r minecraft
```

---

## Importando um mundo existente

### Contexto

O mundo foi criado em **single player** (Minecraft vanilla 1.21.11) e estava na pasta `saves` do cliente. O processo correto é:

### 1. Preparar o mundo no PC

```bash
# Windows: botão direito na pasta do mundo → Enviar para → Pasta compactada
# Resultado: lowprofile.zip
```

### 2. Enviar para a VM

**Via navegador:** na janela SSH do GCP, clique em **⚙️ → Upload file**

**Via gcloud CLI:**
```bash
gcloud compute scp ./lowprofile.zip \
  minecraft-server:~/minecraft/ \
  --zone=southamerica-east1-b
```

### 3. Extrair e posicionar na VM

```bash
cd ~/minecraft

# Remover mundo gerado automaticamente
rm -rf world world_nether world_the_end

# Extrair
unzip lowprofile.zip

# Renomear para "world"
mv lowprofile world
```

### 4. Confirmar no server.properties

```bash
grep level-name server.properties
# Deve retornar: level-name=world
```

> O PaperMC migra automaticamente as pastas `DIM-1` (nether) e `DIM1` (the_end) para o formato Bukkit na primeira inicialização. Isso é **normal e esperado**.

---

## Erros encontrados e soluções

### ❌ Erro 1: Link de download do Chunky quebrado (404)

**Problema:** O Chunky migrou do GitHub Releases para o **Hangar** (repositório oficial do PaperMC).

**Solução:** Usar o link correto:
```bash
wget -O Chunky.jar \
  "https://hangarcdn.papermc.io/plugins/pop4959/Chunky/versions/1.4.40/PAPER/Chunky-Bukkit-1.4.40.jar"
```

---

### ❌ Erro 2: Versão 1.21.11 desconhecida

**Problema:** A versão 1.21.11 foi inicialmente descartada por desconhecimento. O Minecraft Java adotou numeração com terceiro dígito maior que 4/5 a partir do update *Mounts of Mayhem* (dezembro de 2025).

**Aprendizado:** Verificar sempre no [minecraft.wiki](https://minecraft.wiki) antes de afirmar que uma versão não existe.

---

### ❌ Erro 3: Regra de firewall não aplicada à VM

**Problema:** A regra de firewall existia, mas a VM não tinha a tag correspondente.

**Solução:**
```bash
gcloud compute firewall-rules delete allow-minecraft --quiet

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

### ❌ Erro 4: Mundo não carregava — pasta world gerada do zero

**Problema:** Após upload, o servidor carregava `0 persistent chunks`. O spawn estava em coordenadas sem chunks gerados.

**Solução:**
```bash
setworldspawn -31 71 50   # Coordenadas reais do spawn do mundo
```

---

### ❌ Erro 5 (Principal): Timeout de 30 segundos ao entrar no servidor

**Problema:** O jogador entrava no servidor, ficava exatamente 30 segundos na tela de carregamento e desconectava com "Tempo limite excedido".

**Log do servidor:**
```
[Netty Epoll IO #3/WARN]: io.netty.handler.timeout.ReadTimeoutException
```

**Log do cliente:**
```
[Download-1/ERROR]: Failed to retrieve profile key pair — Status: 401
[Render thread/WARN]: Client disconnected with reason: Tempo limite excedido
```

**Causa real — MTU da GCP:**

A rede VPC do Google Cloud usa MTU de **1460 bytes**, enquanto a internet residencial usa 1500 bytes. Ao entrar no servidor, um volume massivo de dados (chunks do spawn) é enviado. Pacotes grandes fragmentam e são descartados, fazendo o cliente aguardar indefinidamente até o timeout hardcoded de 30 segundos do cliente Minecraft.

**Causa secundária — enforce-secure-profile:**

Desde o Minecraft 1.19, o jogo tenta validar chaves criptográficas com a Mojang. Com TLauncher (conta offline), isso gera erro 401 e pode travar a conexão.

**Solução definitiva:**

```properties
# server.properties
network-compression-threshold=64
enforce-secure-profile=false
online-mode=false
```

---

### ❌ Erro 6: Erro de formatação no paper-global.yml

**Problema:** Ao editar manualmente, uma linha ficou com indentação errada:

```yaml
  client-reader-timeout: 120 
 compression-level: default   # ← 1 espaço em vez de 2 — YAML inválido
```

**Solução:** Corrigir a indentação para exatamente 2 espaços em todas as linhas da seção `misc`.

---

## Configurações finais que funcionaram

### server.properties

```properties
online-mode=false
enforce-secure-profile=false
network-compression-threshold=64
view-distance=6
simulation-distance=4
sync-chunk-writes=false
server-ip=
server-port=25565
```

### spigot.yml

```yaml
timeout-time: 120
```

### config/paper-global.yml (seção misc)

```yaml
misc:
  client-reader-timeout: 120
  compression-level: default
```

---

## Automação de inicialização e desligamento

### start.sh

```bash
#!/bin/bash
cd /home/$(whoami)/minecraft
screen -dmS minecraft java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
```

### stop.sh

```bash
#!/bin/bash
screen -S minecraft -X stuff "stop$(printf '\r')"
sleep 10
```

### export_world.sh

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

### Serviço systemd

Cria o arquivo `/etc/systemd/system/minecraft.service` — substitua `SEU_USUARIO` pelo usuário real:

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

Ativar:

```bash
sudo systemctl daemon-reload
sudo systemctl enable minecraft
sudo systemctl start minecraft
```

| Comando | Ação |
|---|---|
| `sudo systemctl start minecraft` | Inicia o servidor |
| `sudo systemctl stop minecraft` | Para o servidor |
| `sudo systemctl status minecraft` | Verifica se está rodando |
| `sudo systemctl restart minecraft` | Reinicia |

---

## Proteção com AuthMe

Com `online-mode=false`, qualquer pessoa que souber o IP do servidor pode entrar usando qualquer nome de usuário. O **AuthMe** resolve isso exigindo senha para jogar.

### Por que AuthMe?

- Impede que alguém entre usando o nome de um jogador já registrado
- Protege contra floods de bots (ataques com muitas conexões falsas)
- Congela o jogador no spawn até que ele faça login

### Instalação

```bash
cd ~/minecraft/plugins
wget https://github.com/AuthMe/AuthMeReloaded/releases/download/5.6.0/AuthMe-5.6.0.jar
sudo chown -R $USER:$USER ~/minecraft/plugins/
```

Reinicie ou recarregue o servidor:
```
reload confirm
```

### Configuração (plugins/AuthMe/config.yml)

```yaml
# Idioma das mensagens
messagesLanguage: 'br'

# Máximo de contas por IP — previne criação em massa de contas (bots)
maxRegPerIp: 2

# Sessão — jogador não precisa logar de novo se cair e voltar em até 10 min
sessions:
  enabled: true
  timeout: 10
```

### Comandos dos jogadores

```
/register senha senha    # Primeiro acesso — registra a conta
/login senha             # Acessos seguintes
```

### Proteção contra DDoS

O AuthMe por si só não bloqueia DDoS na camada de rede — para isso, as proteções do próprio GCP ajudam:

- O Google Cloud já oferece proteção básica contra DDoS na infraestrutura
- Configure `rate-limit: 20` no `server.properties` para limitar conexões por IP
- O `maxRegPerIp: 2` do AuthMe impede floods de registro de bots
- O `packet-limiter` no `paper-global.yml` já vem configurado para kickar jogadores que enviam pacotes em excesso:

```yaml
packet-limiter:
  kick-on-violation: true
  all-packets:
    action: KICK
    interval: 7.0
    max-packet-rate: 500.0
```

---

## Pré-geração de chunks com Chunky

### Por que pré-gerar?

Sem pré-geração, o servidor gera chunks em tempo real quando jogadores exploram. Isso causa lag perceptível e pode resultar em timeouts ao entrar no servidor pela primeira vez.

### Instalação

```bash
cd ~/minecraft/plugins
wget -O Chunky.jar \
  "https://hangarcdn.papermc.io/plugins/pop4959/Chunky/versions/1.4.40/PAPER/Chunky-Bukkit-1.4.40.jar"
```

### Referência de custo por raio

| Raio | Chunks | Disco | Tempo (e2-standard-2) |
|---|---|---|---|
| 1.000 blocos | ~4k | ~200 MB | 10–20 min |
| 3.000 blocos | ~113k | ~1–2 GB | 2–5h |
| 5.000 blocos | ~200k | ~5 GB | 8–15h |

### Comandos — gerar em etapas

```
chunky center 0 0
chunky radius 1000
chunky start
# Aguardar terminar (chunky status), depois:
chunky radius 3000
chunky start
# E por fim:
chunky radius 5000
chunky start

# Após terminar, definir world border:
/worldborder center 0 0
/worldborder set 10000
```

### Comportamento com a VM suspensa

| Item | Suspender/Desligar VM |
|---|---|
| Chunks na RAM | ❌ Perdido |
| Chunks no disco (.mca) | ✅ Mantido |
| Progresso do Chunky | ✅ Mantido |

O Chunky precisa ser rodado **apenas uma vez**. Após gerar e salvar os chunks no disco, desligar e religar a VM não afeta o resultado.

---

## Exportando o mundo

Quando decidir encerrar o servidor, use o script `export_world.sh` para baixar o mundo no formato correto para o single player:

```bash
~/minecraft/export_world.sh
```

Baixe o arquivo gerado para o seu PC:

```bash
# No terminal do seu PC:
gcloud compute scp \
  minecraft-server:~/mundo_exportado.zip \
  ./ \
  --zone=southamerica-east1-b
```

Extraia o zip e coloque a pasta dentro de:

```
# Windows
%APPDATA%\.minecraft\saves\

# Linux/Mac
~/.minecraft/saves/
```

A estrutura final dentro da pasta do mundo deve ser:

```
lowprofile/
├── level.dat
├── region/
├── DIM-1/      ← nether
└── DIM1/       ← the end
```

O mundo aparecerá normalmente na lista de mundos do single player, sem conflitos com o launcher.

---

## Aprendizados

1. **render-distance do cliente ≠ view-distance do servidor.** O cliente pode ter 20 chunks configurados localmente — isso não afeta a VM. O que pesa no servidor é o `view-distance` e o `simulation-distance`.

2. **O Chunky não tem limite de chunks** — o limite real é o disco e o tempo. Para a e2-standard-2, raio de 5.000 blocos é o limite prático.

3. **O problema de MTU da GCP é real e pouco documentado.** A rede VPC usa MTU 1460 em vez de 1500, fragmentando pacotes grandes. Reduzir `network-compression-threshold` para 64 resolve.

4. **O timeout de 30 segundos do cliente Minecraft é hardcoded.** Não adianta mudar apenas configurações do servidor — é preciso garantir que os chunks sejam enviados dentro desse tempo via compressão.

5. **`enforce-secure-profile=false` é obrigatório com TLauncher.** Desde o Minecraft 1.19, o jogo valida chaves criptográficas com a Mojang. Com contas offline, isso gera erro 401 e trava a conexão.

6. **YAML é sensível a indentação.** Um espaço a menos em uma linha do `paper-global.yml` foi suficiente para a configuração não ser aplicada.

7. **O PaperMC migra o nether e the_end automaticamente.** As pastas `DIM-1` e `DIM1` do formato vanilla são reorganizadas para `world_nether` e `world_the_end` na primeira inicialização — comportamento normal.

8. **Sempre verificar o log do cliente, não só do servidor.** O erro principal (timeout) só foi identificado corretamente quando o log do TLauncher foi analisado.

9. **Plugins migram de repositório.** O Chunky saiu do GitHub Releases para o Hangar. Sempre verificar o repositório oficial antes de usar links de tutoriais antigos.

10. **O server-ip deve ficar vazio.** Colocar o IP da instância no `server-ip` pode causar problemas de binding. Deixar vazio faz o servidor escutar em todas as interfaces.

---

## Alternativa: Raspberry Pi 5

Se preferir uma máquina física em casa, a **Raspberry Pi 5 com 8 GB de RAM** é a melhor opção para um servidor Minecraft doméstico — mesma quantidade de RAM da e2-standard-2 e processador ARM de alta eficiência.

### Hardware recomendado

| Componente | Recomendação |
|---|---|
| Modelo | Raspberry Pi 5 (8 GB) |
| Armazenamento | SSD NVMe via adaptador PCIe |
| Resfriamento | Case com cooler ativo (oficial da Raspberry) |
| Alimentação | Fonte oficial 27W USB-C |

### O desafio: acesso externo

Em casa, seu IP residencial muda periodicamente. Existem três formas de resolver:

**Opção 1 — DDNS (Dynamic DNS):**
Associa um domínio fixo ao seu IP residencial e atualiza automaticamente. Requer abertura da porta 25565 no roteador.

```bash
# DuckDNS — atualiza o IP a cada 5 minutos
echo "*/5 * * * * curl -s 'https://www.duckdns.org/update?domains=SEU_DOMINIO&token=SEU_TOKEN&ip='" | crontab -
```

**Opção 2 — Playit.gg (mais fácil, sem mexer no roteador):**
Cria um endereço público que redireciona o tráfego para a Raspberry sem configurar port forwarding.

```bash
curl -SsL https://playit-cloud.github.io/ppa/key.gpg | sudo apt-key add -
sudo apt install playit
playit
```

Gera um endereço como `seu-servidor.joinmc.link`.

**Opção 3 — WireGuard (mais avançado):**
VPN própria entre a Raspberry e os jogadores. Latência mínima, mas cada jogador precisa instalar e configurar o WireGuard.

### Comparação das opções

| | DDNS | Playit.gg | WireGuard |
|---|---|---|---|
| Dificuldade | Média | Fácil | Difícil |
| Mexe no roteador | ✅ Sim | ❌ Não | ❌ Não |
| Latência | Baixa | Média | Mínima |
| Custo | Grátis | Grátis | Grátis |

### Vantagens vs Google Cloud

| | Raspberry Pi 5 | Google Cloud |
|---|---|---|
| Custo mensal | ~$0 (só energia) | ~$5–6 com uso casual |
| Controle físico | Total | Via SSH/console |
| Disponibilidade | Depende da sua internet | Alta disponibilidade |
| Setup inicial | Mais trabalhoso | Mais simples |
| Latência | Depende da sua conexão | Previsível |

Para um grupo de amigos todos no Brasil com boa conexão em casa, a Raspberry Pi 5 com Playit.gg é uma excelente alternativa de custo zero a longo prazo.
