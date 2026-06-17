#!/usr/bin/env bash
# =============================================================================
#  create-server.sh — Instalação automática de servidor Minecraft no GCP
#  Compatível com: Windows (Git Bash / WSL), macOS, Linux
#  Uso:
#    wget https://raw.githubusercontent.com/vinicius-eng20/servidor-minecraft-gcp/main/create-server.sh
#    chmod +x create-server.sh && ./create-server.sh
# =============================================================================

set -euo pipefail

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Funções de output ────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }
ask()     { echo -e "${YELLOW}[?]${NC} $*"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
clear
echo -e "${GREEN}"
cat << 'EOF'
  ███╗   ███╗██╗███╗   ██╗███████╗ ██████╗██████╗  █████╗ ███████╗████████╗
  ████╗ ████║██║████╗  ██║██╔════╝██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
  ██╔████╔██║██║██╔██╗ ██║█████╗  ██║     ██████╔╝███████║█████╗     ██║   
  ██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ██║     ██╔══██╗██╔══██║██╔══╝     ██║   
  ██║ ╚═╝ ██║██║██║ ╚████║███████╗╚██████╗██║  ██║██║  ██║██║        ██║   
  ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝   
                         no Google Cloud — Setup Automático
EOF
echo -e "${NC}"
echo -e "  PaperMC 1.21.11 • AuthMe • Chunky • Systemd • São Paulo\n"

# ─── Detectar SO do usuário ───────────────────────────────────────────────────
detect_os() {
  case "$(uname -s 2>/dev/null || echo Windows)" in
    Linux*)   echo "linux" ;;
    Darwin*)  echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*|Windows*) echo "windows" ;;
    *)        echo "unknown" ;;
  esac
}
OS=$(detect_os)
info "Sistema detectado: $OS"

# ─── Verificar / instalar gcloud CLI ──────────────────────────────────────────
step "Verificando gcloud CLI"

if ! command -v gcloud &>/dev/null; then
  warn "gcloud CLI não encontrado. Iniciando instalação..."

  case "$OS" in
    linux)
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
        https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
      sudo apt-get update -q && sudo apt-get install -y google-cloud-cli
      ;;
    macos)
      if command -v brew &>/dev/null; then
        brew install --cask google-cloud-sdk
      else
        error "Homebrew não encontrado. Instale o gcloud CLI manualmente em:\nhttps://cloud.google.com/sdk/docs/install"
      fi
      ;;
    windows)
      error "No Windows, instale o gcloud CLI manualmente:\nhttps://cloud.google.com/sdk/docs/install-sdk#windows\nDepois execute este script novamente no Git Bash ou WSL."
      ;;
    *)
      error "Sistema não reconhecido. Instale o gcloud CLI em:\nhttps://cloud.google.com/sdk/docs/install"
      ;;
  esac
  success "gcloud CLI instalado."
else
  success "gcloud CLI encontrado: $(gcloud --version | head -1)"
fi

# ─── Autenticação ─────────────────────────────────────────────────────────────
step "Autenticação no Google Cloud"

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
  info "Abrindo navegador para autenticação..."
  gcloud auth login --quiet
else
  ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
  success "Autenticado como: $ACCOUNT"
fi

# ─── Configuração interativa ───────────────────────────────────────────────────
step "Configuração do servidor"

echo ""
ask "Nome do projeto GCP (deixe vazio para criar novo 'minecraft-server'):"
read -r PROJECT_ID
PROJECT_ID="${PROJECT_ID:-minecraft-server-$(date +%s | tail -c 5)}"

ask "Nome da VM (padrão: minecraft-server):"
read -r VM_NAME
VM_NAME="${VM_NAME:-minecraft-server}"

ask "Versão do PaperMC (padrão: 1.21.11):"
read -r MC_VERSION
MC_VERSION="${MC_VERSION:-1.21.11}"

ask "Número máximo de jogadores (padrão: 10):"
read -r MAX_PLAYERS
MAX_PLAYERS="${MAX_PLAYERS:-10}"

ask "Raio de pré-geração de chunks em blocos (padrão: 3000, digite 0 para pular):"
read -r CHUNK_RADIUS
CHUNK_RADIUS="${CHUNK_RADIUS:-3000}"

ZONE="southamerica-east1-b"
REGION="southamerica-east1"
MACHINE="e2-standard-2"
DISK_SIZE="30"

echo ""
echo -e "${BOLD}Resumo da configuração:${NC}"
echo -e "  Projeto:      ${CYAN}$PROJECT_ID${NC}"
echo -e "  VM:           ${CYAN}$VM_NAME${NC}"
echo -e "  Região:       ${CYAN}$REGION (São Paulo)${NC}"
echo -e "  Máquina:      ${CYAN}$MACHINE (2 vCPU, 8 GB RAM)${NC}"
echo -e "  Disco:        ${CYAN}${DISK_SIZE} GB SSD${NC}"
echo -e "  MC Version:   ${CYAN}$MC_VERSION${NC}"
echo -e "  Max Players:  ${CYAN}$MAX_PLAYERS${NC}"
echo -e "  Chunk Radius: ${CYAN}$CHUNK_RADIUS blocos${NC}"
echo ""
ask "Confirmar e iniciar instalação? (s/N):"
read -r CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { info "Instalação cancelada."; exit 0; }

# ─── Criar / selecionar projeto ───────────────────────────────────────────────
step "Configurando projeto GCP"

if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  info "Projeto '$PROJECT_ID' já existe. Usando projeto existente."
else
  info "Criando projeto '$PROJECT_ID'..."
  gcloud projects create "$PROJECT_ID" --name="Minecraft Server" || \
    warn "Não foi possível criar o projeto. Verifique se você tem permissões de billing."
fi

gcloud config set project "$PROJECT_ID" --quiet
success "Projeto configurado: $PROJECT_ID"

# Ativar APIs necessárias
info "Ativando APIs do GCP..."
gcloud services enable compute.googleapis.com --quiet
success "API Compute Engine ativada."

# ─── Criar a VM ───────────────────────────────────────────────────────────────
step "Criando a VM"

if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
  warn "VM '$VM_NAME' já existe. Pulando criação."
else
  info "Criando VM $VM_NAME ($MACHINE) em $ZONE..."
  gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    --machine-type="$MACHINE" \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size="${DISK_SIZE}GB" \
    --boot-disk-type=pd-ssd \
    --tags=minecraft-server \
    --quiet
  success "VM criada com sucesso."
fi

# ─── Firewall ─────────────────────────────────────────────────────────────────
step "Configurando firewall"

if gcloud compute firewall-rules describe allow-minecraft --quiet &>/dev/null; then
  warn "Regra de firewall 'allow-minecraft' já existe. Pulando."
else
  gcloud compute firewall-rules create allow-minecraft \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:25565 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=minecraft-server \
    --quiet
  success "Regra de firewall criada: TCP 25565."
fi

# ─── Aguardar SSH disponível ──────────────────────────────────────────────────
step "Aguardando VM ficar disponível"

info "Aguardando 30 segundos para a VM inicializar..."
sleep 30

MAX_TRIES=10
TRIES=0
until gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
  --command="echo ok" --quiet 2>/dev/null; do
  TRIES=$((TRIES + 1))
  [[ $TRIES -ge $MAX_TRIES ]] && error "Não foi possível conectar à VM via SSH após $MAX_TRIES tentativas."
  info "Tentativa $TRIES/$MAX_TRIES — aguardando SSH..."
  sleep 10
done
success "VM acessível via SSH."

# ─── Instalação remota na VM ──────────────────────────────────────────────────
step "Instalando o servidor Minecraft na VM"

# Obter usuário remoto
REMOTE_USER=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
  --command="whoami" --quiet 2>/dev/null | tr -d '[:space:]')
info "Usuário remoto: $REMOTE_USER"

# Script de instalação que roda DENTRO da VM
INSTALL_SCRIPT=$(cat << REMOTE_SCRIPT
#!/bin/bash
set -euo pipefail

MC_VERSION="${MC_VERSION}"
MAX_PLAYERS="${MAX_PLAYERS}"
CHUNK_RADIUS="${CHUNK_RADIUS}"
REMOTE_USER="${REMOTE_USER}"

echo "==> Atualizando sistema..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

echo "==> Instalando Java 21, Screen e Unzip..."
sudo apt-get install -y -qq openjdk-21-jdk-headless screen unzip curl

echo "==> Criando pasta do servidor..."
mkdir -p ~/minecraft/plugins

echo "==> Baixando PaperMC \${MC_VERSION}..."
BUILD=\$(curl -s "https://api.papermc.io/v2/projects/paper/versions/\${MC_VERSION}/builds" \
  | grep -o '"build":[0-9]*' | tail -1 | grep -o '[0-9]*')

wget -q -O ~/minecraft/server.jar \
  "https://api.papermc.io/v2/projects/paper/versions/\${MC_VERSION}/builds/\${BUILD}/downloads/paper-\${MC_VERSION}-\${BUILD}.jar"

echo "==> Aceitando EULA..."
echo "eula=true" > ~/minecraft/eula.txt

echo "==> Configurando server.properties..."
cat > ~/minecraft/server.properties << 'PROPS'
online-mode=false
enforce-secure-profile=false
network-compression-threshold=64
view-distance=6
simulation-distance=4
sync-chunk-writes=false
server-ip=
server-port=25565
difficulty=normal
gamemode=survival
spawn-protection=16
rate-limit=20
PROPS
echo "max-players=${MAX_PLAYERS}" >> ~/minecraft/server.properties

echo "==> Inicializando servidor para gerar arquivos de configuração..."
cd ~/minecraft
timeout 90 java -Xms1G -Xmx2G -jar server.jar nogui || true

echo "==> Configurando spigot.yml..."
if [ -f ~/minecraft/spigot.yml ]; then
  sed -i 's/timeout-time: 30/timeout-time: 120/' ~/minecraft/spigot.yml || true
fi

echo "==> Configurando paper-global.yml..."
if [ -f ~/minecraft/config/paper-global.yml ]; then
  sed -i 's/client-reader-timeout: 30/client-reader-timeout: 120/' \
    ~/minecraft/config/paper-global.yml || true
fi

echo "==> Baixando Chunky..."
wget -q -O ~/minecraft/plugins/Chunky.jar \
  "https://hangarcdn.papermc.io/plugins/pop4959/Chunky/versions/1.4.40/PAPER/Chunky-Bukkit-1.4.40.jar"

echo "==> Baixando AuthMe..."
wget -q -O ~/minecraft/plugins/AuthMe.jar \
  "https://github.com/AuthMe/AuthMeReloaded/releases/download/5.6.0/AuthMe-5.6.0.jar"

echo "==> Criando script start.sh..."
cat > ~/minecraft/start.sh << 'STARTSH'
#!/bin/bash
cd /home/PLACEHOLDER_USER/minecraft
screen -dmS minecraft java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui
STARTSH
sed -i "s|PLACEHOLDER_USER|\${REMOTE_USER}|g" ~/minecraft/start.sh

echo "==> Criando script stop.sh..."
cat > ~/minecraft/stop.sh << 'STOPSH'
#!/bin/bash
screen -S minecraft -X stuff "stop\$(printf '\r')"
sleep 10
STOPSH

echo "==> Criando script export_world.sh..."
cat > ~/minecraft/export_world.sh << 'EXPORTSH'
#!/bin/bash
echo "Preparando exportação do mundo..."
cd ~/minecraft
cp -r world_nether/DIM-1 world/DIM-1 2>/dev/null || true
cp -r world_the_end/DIM1 world/DIM1 2>/dev/null || true
zip -r ~/mundo_exportado.zip world
echo "Mundo exportado em ~/mundo_exportado.zip"
EXPORTSH

chmod +x ~/minecraft/start.sh ~/minecraft/stop.sh ~/minecraft/export_world.sh

echo "==> Configurando serviço systemd..."
sudo bash -c "cat > /etc/systemd/system/minecraft.service << SYSTEMD
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=\${REMOTE_USER}
ExecStart=/home/\${REMOTE_USER}/minecraft/start.sh
ExecStop=/home/\${REMOTE_USER}/minecraft/stop.sh
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SYSTEMD"

sudo systemctl daemon-reload
sudo systemctl enable minecraft
success_msg="INSTALACAO_CONCLUIDA"
echo "\$success_msg"
REMOTE_SCRIPT
)

# Executar o script na VM
info "Executando instalação na VM (isso pode levar alguns minutos)..."
gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
  --command="bash -s" --quiet << EOF
$INSTALL_SCRIPT
EOF

# ─── Pré-geração de chunks ────────────────────────────────────────────────────
if [[ "$CHUNK_RADIUS" -gt 0 ]]; then
  step "Iniciando pré-geração de chunks (raio: ${CHUNK_RADIUS} blocos)"

  info "Iniciando servidor para pré-geração..."
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
    --command="cd ~/minecraft && screen -dmS minecraft java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui" \
    --quiet

  info "Aguardando servidor inicializar (60s)..."
  sleep 60

  info "Executando Chunky em etapas..."

  # Etapa 1: 1000 blocos
  if [[ "$CHUNK_RADIUS" -ge 1000 ]]; then
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
      --command="screen -S minecraft -X stuff 'chunky center 0 0\n'; \
                 screen -S minecraft -X stuff 'chunky radius 1000\n'; \
                 screen -S minecraft -X stuff 'chunky start\n'" \
      --quiet
    info "Gerando raio 1000 blocos... aguardando 120s"
    sleep 120
  fi

  # Etapa 2: até o raio solicitado
  if [[ "$CHUNK_RADIUS" -gt 1000 ]]; then
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
      --command="screen -S minecraft -X stuff 'chunky radius ${CHUNK_RADIUS}\n'; \
                 screen -S minecraft -X stuff 'chunky start\n'" \
      --quiet
    WAIT_TIME=$(( (CHUNK_RADIUS / 1000) * 300 ))
    info "Gerando raio ${CHUNK_RADIUS} blocos... aguardando ${WAIT_TIME}s"
    info "(Você pode acompanhar com: gcloud compute ssh $VM_NAME --zone=$ZONE --command='screen -S minecraft -X stuff \"chunky status\n\"')"
    sleep "$WAIT_TIME"
  fi

  # World border
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
    --command="BORDER=\$((CHUNK_RADIUS * 2)); \
               screen -S minecraft -X stuff '/worldborder center 0 0\n'; \
               screen -S minecraft -X stuff \"/worldborder set \${BORDER}\n\"" \
    --quiet

  success "Chunks pré-gerados e world border definido (${CHUNK_RADIUS} blocos de raio)."
else
  step "Iniciando o servidor"
  gcloud compute ssh "$VM_NAME" --zone="$ZONE" \
    --command="cd ~/minecraft && screen -dmS minecraft java -Xms4G -Xmx6G -XX:+UseG1GC -jar server.jar nogui" \
    --quiet
  info "Aguardando servidor inicializar (60s)..."
  sleep 60
fi

# ─── Obter IP externo ─────────────────────────────────────────────────────────
step "Obtendo IP externo"

EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
  --zone="$ZONE" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

# ─── Resumo final ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           ✅  SERVIDOR CRIADO COM SUCESSO!               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}IP do servidor:${NC}   ${CYAN}${EXTERNAL_IP}:25565${NC}"
echo -e "  ${BOLD}Versão:${NC}           ${CYAN}PaperMC ${MC_VERSION}${NC}"
echo -e "  ${BOLD}Região:${NC}           ${CYAN}São Paulo (southamerica-east1)${NC}"
echo -e "  ${BOLD}VM:${NC}               ${CYAN}${VM_NAME} (e2-standard-2)${NC}"
echo ""
echo -e "${BOLD}Próximos passos:${NC}"
echo -e "  1. Conecte no Minecraft com o IP: ${CYAN}${EXTERNAL_IP}:25565${NC}"
echo -e "  2. Digite ${CYAN}/register suasenha suasenha${NC} para criar sua conta no servidor"
echo -e "  3. Use ${CYAN}/login suasenha${NC} nos próximos acessos"
echo ""
echo -e "${BOLD}Comandos úteis:${NC}"
echo -e "  SSH no servidor:    ${CYAN}gcloud compute ssh ${VM_NAME} --zone=${ZONE}${NC}"
echo -e "  Console Minecraft:  ${CYAN}screen -r minecraft${NC}  (dentro do SSH)"
echo -e "  Desligar VM:        ${CYAN}gcloud compute instances stop ${VM_NAME} --zone=${ZONE}${NC}"
echo -e "  Ligar VM:           ${CYAN}gcloud compute instances start ${VM_NAME} --zone=${ZONE}${NC}"
echo -e "  Exportar mundo:     ${CYAN}~/minecraft/export_world.sh${NC}  (dentro do SSH)"
echo ""
echo -e "${YELLOW}O servidor inicia automaticamente quando a VM for ligada.${NC}"
echo -e "${YELLOW}O mundo é salvo automaticamente antes de desligar.${NC}"
echo ""
