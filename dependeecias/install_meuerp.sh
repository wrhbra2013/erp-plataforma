#!/bin/sh
set -eu

# ==============================================================
# Script de instalação — API MeuERP (.NET / ASP.NET Core)
# Uso: sudo bash install_meuerp.sh            (instalar)
#       sudo bash install_meuerp.sh uninstall (desinstalar)
#
# Publica a API ASP.NET Core (net10.0 + SQLite), roda como serviço
# systemd (nome do projeto) e expõe via Nginx (proxy reverso).
# Requer: Debian 11+ (sudo apt para dependências).
# O .NET SDK 10 usa o instalado globalmente OU é instalado AUTOMATICAMENTE
# a partir do tarball dotnet-sdk-10.*-linux-x64.tar.gz presente em dependeecias/.
#
# IMPORTANTE: o script deve estar dentro do projeto (ex.: dependeecias/),
# pois ele localiza e publica o MeuErpApi.csproj.
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTNET_DEFAULT_PORT="5003"
DOTNET_DIR="/opt/dotnet"
PROJECT_NAME="meuerp"   # padrão — pode ser alterado durante a instalação/desinstalação

# Deriva pastas/serviço/usuário/nginx a partir do nome do projeto.
set_project_names() {
  SERVICE_NAME="$PROJECT_NAME"
  INSTALL_DIR="/var/www/$PROJECT_NAME"
  APP_DIR="$INSTALL_DIR/app"
  DATA_DIR="$INSTALL_DIR/data"
  SYSTEM_USER="$PROJECT_NAME"
  NGINX_SITE="/etc/nginx/sites-available/$PROJECT_NAME.conf"
}

# Valida o nome do projeto (usado em serviço systemd, usuário, pastas e nginx):
# minúsculo, sem espaços, só [a-z0-9_-], iniciando com letra e até 24 caracteres.
_valid_name() {
  case "$1" in
    ''|*[!a-z0-9_-]*) return 1 ;;
    [a-z]*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 24 ] || return 1
  return 0
}

_normalize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_meuerp.sh"


# ==============================================================
# Uninstall
# ==============================================================
uninstall() {
  echo ""
  info "===== Iniciando desinstalação da API MeuERP ====="

  echo ""
  info "[1/4] Parando e removendo o serviço systemd ($SERVICE_NAME)..."
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    info "Serviço $SERVICE_NAME removido"
  else
    warn "Serviço não encontrado"
  fi

  echo ""
  info "[2/4] Removendo configuração Nginx..."
  rm -f "$NGINX_SITE"
  rm -f "/etc/nginx/sites-enabled/${PROJECT_NAME}.conf"
  if nginx -t 2>/dev/null; then
    systemctl reload nginx.service 2>/dev/null && info "Nginx recarregado" || warn "Falha ao recarregar nginx"
  else
    warn "Configuração do nginx inválida — verifique manualmente"
  fi

  echo ""
  info "[3/4] Removendo usuário de sistema ($SYSTEM_USER)..."
  userdel -r "$SYSTEM_USER" 2>/dev/null && info "Usuário removido" || warn "Falha ao remover usuário (pode estar em uso)"

  echo ""
  info "[4/4] Removendo diretório $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR" && info "Diretório $INSTALL_DIR removido" || warn "Falha ao remover diretório"

  echo ""
  info "Desinstalação concluída!"
  info "Nota: o .NET SDK não é removido. Se foi instalado POR ESTE SCRIPT (tarball em $DOTNET_DIR):"
  info "      sudo rm -rf $DOTNET_DIR /usr/local/bin/dotnet"
}


# ==============================================================
# Help
# ==============================================================
if [ "${1:-}" = "uninstall" ]; then
  # Nome do projeto: aceita como 2º argumento ou pergunta (ex.: install_meuerp.sh uninstall meuapp)
  if [ -n "${2:-}" ]; then
    PROJECT_NAME="$(_normalize_name "$2")"
  else
    printf "Nome do projeto a desinstalar [%s]: " "$PROJECT_NAME"; read -r _uninstall_name
    _uninstall_name=$(_normalize_name "${_uninstall_name:-$PROJECT_NAME}")
    PROJECT_NAME="$_uninstall_name"
  fi
  if ! _valid_name "$PROJECT_NAME"; then
    error "Nome de projeto inválido para desinstalação: $PROJECT_NAME"
  fi
  set_project_names
  uninstall; exit 0
fi
if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'HELP'
Instalador da API MeuERP (.NET).

  sudo bash install_meuerp.sh                   instala/publica a API
  sudo bash install_meuerp.sh uninstall [nome]  desinstala (informe o nome se for diferente)

Requisitos:
  - Rodar o script DENTRO da pasta do projeto (ex.: dependeecias/)
  - Servidor Debian 11+ com acesso à internet (NuGet para restore)
  - Portas 80 (nginx) e a porta da API (padrão 5003)

.NET SDK 10:
  - Use o dotnet 10 GLOBAL do servidor, OU
  - deixe o tarball dotnet-sdk-10.*-linux-x64.tar.gz em dependeecias/ que o script
    INSTALA AUTOMATICAMENTE em /opt/dotnet (sem depender do servidor).

Durante a instalação você pode RENOMEAR o projeto. O nome escolhido é usado
geralmente no serviço systemd, usuário, pastas /var/www e arquivo do nginx.
HELP
  exit 0
fi


echo ""
info "===== Iniciando instalação da API MeuERP (.NET) ====="
echo ""


# --------------------------------------------------------------
# Verificação de sistema — Debian 11+
# --------------------------------------------------------------
if [ ! -f /etc/debian_version ]; then
  error "Este script requer Debian 11+ ou Ubuntu. /etc/debian_version não encontrado."
fi
DEB_VER=$(cat /etc/debian_version 2>/dev/null || echo "desconhecido")
info "Sistema: Debian $DEB_VER"

# --------------------------------------------------------------
# Localização do projeto (o script vive dentro do projeto MeuErpApi)
# --------------------------------------------------------------
PROJECT_SRC="${PROJECT_SRC:-}"
if [ -z "$PROJECT_SRC" ]; then
  if [ -f "$SCRIPT_DIR/../MeuErpApi.csproj" ]; then
    PROJECT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
  elif [ -f "$SCRIPT_DIR/MeuErpApi.csproj" ]; then
    PROJECT_SRC="$SCRIPT_DIR"
  fi
fi
if [ -z "$PROJECT_SRC" ] || [ ! -f "$PROJECT_SRC/MeuErpApi.csproj" ]; then
  error "MeuErpApi.csproj não encontrado. Copie o script PARA DENTRO do projeto MeuErpApi (ex.: na subpasta dependeecias/) antes de instalar. Ou defina: PROJECT_SRC=/caminho/do/projeto sudo bash install_meuerp.sh"
fi
info "Projeto encontrado: $PROJECT_SRC"


# --------------------------------------------------------------
# Dependências de sistema
# --------------------------------------------------------------
info "===== Verificando dependências do servidor ====="

_apt_update_done=0
_apt_update() {
  if [ "$_apt_update_done" -eq 0 ]; then
    info "Executando apt-get update..."
    apt-get update -qq || error "Falha ao executar apt-get update"
    _apt_update_done=1
  fi
}

# curl — download/fallback e healthcheck
if ! command -v curl >/dev/null 2>&1; then
  warn "curl não encontrado — instalando..."
  _apt_update && apt-get install -y -qq curl
  command -v curl >/dev/null 2>&1 && info "curl instalado" || error "Falha ao instalar curl"
else
  info "curl: $(curl --version 2>&1 | head -1)"
fi

# openssl — gerar chave JWT
if ! command -v openssl >/dev/null 2>&1; then
  warn "openssl não encontrado — instalando..."
  _apt_update && apt-get install -y -qq openssl
  command -v openssl >/dev/null 2>&1 && info "openssl instalado" || error "Falha ao instalar openssl"
else
  info "openssl: $(openssl version 2>&1)"
fi

# ca-certificates — necessária para HTTPS (NuGet)
if ! command -v update-ca-certificates >/dev/null 2>&1; then
  _apt_update && apt-get install -y -qq ca-certificates
fi

# ss/lsof — verificação de portas
if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
  warn "ss/lsof não encontrados — instalando iproute2..."
  _apt_update && apt-get install -y -qq iproute2
fi

# fuser — liberar portas
if ! command -v fuser >/dev/null 2>&1; then
  warn "fuser não encontrado — instalando psmisc..."
  _apt_update && apt-get install -y -qq psmisc
fi

# --------------------------------------------------------------
# .NET SDK 10 — usa o global do servidor OU instala automaticamente
# a partir do tarball local (ex.: dependeecias/dotnet-sdk-10.*-linux-x64.tar.gz)
# --------------------------------------------------------------
info "===== Verificando .NET SDK 10 ====="

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) DOTNET_RID="linux-x64" ;;
  aarch64|arm64) DOTNET_RID="linux-arm64" ;;
  *) DOTNET_RID="linux-x64" ;;
esac

DOTNET_BIN=""
DOTNET_ROOT=""

# 1) .NET 10 já global no servidor → usa-o
if command -v dotnet >/dev/null 2>&1 && [ -n "$(dotnet --version 2>/dev/null)" ]; then
  if printf '%s' "$(dotnet --version 2>/dev/null)" | grep -q '^10\.'; then
    DOTNET_BIN="$(command -v dotnet)"
    info ".NET SDK 10 global: $(dotnet --version 2>&1)"
  elif [ "$DOTNET_RID" = "linux-x64" ]; then
    warn "dotnet global é versão $(dotnet --version 2>/dev/null) — o projeto exige 10. Será instalado do tarball."
  fi
fi

# 2) Instalação automática a partir do tarball local
if [ -z "$DOTNET_BIN" ] && [ "$DOTNET_RID" = "linux-x64" ] \
   && ls "$SCRIPT_DIR"/dotnet-sdk-10.*-linux-${DOTNET_RID}.tar.gz >/dev/null 2>&1; then
  SDK_TARBALL="$(ls "$SCRIPT_DIR"/dotnet-sdk-10.*-linux-${DOTNET_RID}.tar.gz | head -1)"
  info "Instalando .NET SDK automaticamente a partir de: $SDK_TARBALL"

  if ! command -v tar >/dev/null 2>&1 || ! command -v gzip >/dev/null 2>&1; then
    _apt_update && apt-get install -y -qq tar gzip
  fi

  mkdir -p "$DOTNET_DIR"
  info "Extraindo para $DOTNET_DIR (pode demorar alguns minutos)..."
  tar zxf "$SDK_TARBALL" -C "$DOTNET_DIR" || error "Falha ao extrair o SDK do tarball: $SDK_TARBALL"
  ln -sf "$DOTNET_DIR/dotnet" /usr/local/bin/dotnet

  DOTNET_BIN="$DOTNET_DIR/dotnet"
  DOTNET_ROOT="$DOTNET_DIR"
  DOTNET_VER="$($DOTNET_BIN --version 2>/dev/null || true)"
  case "$DOTNET_VER" in
    10.*) info ".NET SDK 10 instalado do tarball: $DOTNET_VER" ;;
    *) error "Falha ao instalar o .NET do tarball (versão detectada: ${DOTNET_VER:-nenhuma})." ;;
  esac
fi

[ -n "$DOTNET_BIN" ] && [ -n "$($DOTNET_BIN --version 2>/dev/null)" ] \
  || error ".NET SDK 10 indisponível. Instale-o globalmente no servidor OU coloque o tarball dotnet-sdk-10.*-linux-x64.tar.gz em $SCRIPT_DIR e rode de novo."

info ".NET:   $($DOTNET_BIN --version 2>&1)  (bin: $DOTNET_BIN)"

# DOTNET_ROOT no systemd: apenas quando o SDK foi instalado pelo script (tarball)
if [ -n "$DOTNET_ROOT" ]; then
  DOTNET_ROOT_LINE="Environment=DOTNET_ROOT=$DOTNET_ROOT"
else
  DOTNET_ROOT_LINE="# DOTNET_ROOT: SDK global do servidor (sem definição explícita)"
fi


# --------------------------------------------------------------
# Nginx (proxy reverso)
# --------------------------------------------------------------
info "===== Verificando Nginx ====="
if ! command -v nginx >/dev/null 2>&1; then
  warn "Nginx não encontrado — instalando..."
  _apt_update && apt-get install -y -qq nginx
  systemctl enable nginx 2>/dev/null || true
  systemctl start nginx 2>/dev/null || true
  command -v nginx >/dev/null 2>&1 && info "Nginx instalado" || error "Falha ao instalar Nginx"
else
  info "Nginx: $(nginx -v 2>&1)"
fi


# --------------------------------------------------------------
# Resumo das dependências
# --------------------------------------------------------------
info "===== Resumo das dependências ====="
info "  .NET:           $(${DOTNET_BIN:-dotnet} --version 2>&1)"
info "  Nginx:          $(nginx -v 2>&1 | awk -F/ '{print $2}')"
info "  curl:           $(curl --version 2>&1 | head -1 | awk '{print $2}')"
info "  openssl:        $(openssl version 2>&1 | awk '{print $2}')"
info "===================================="


# --------------------------------------------------------------
# Configuração da instalação (inputs do usuário)
# --------------------------------------------------------------
echo "============ Configuração da instalação ============"

# Nome do projeto — usado em service systemd, usuário, pastas e nginx
while :; do
  printf "Nome do projeto (sem espaços, minúsculas) [%s]: " "$PROJECT_NAME"; read -r _proj_name_input
  _proj_name_input=$(_normalize_name "${_proj_name_input:-$PROJECT_NAME}")
  if _valid_name "$_proj_name_input"; then
    PROJECT_NAME="$_proj_name_input"
    break
  fi
  warn "Nome inválido. Use apenas letras minúsculas, números, '_' ou '-', iniciando com letra (máx. 24)."
done
set_project_names
info "Projeto: $PROJECT_NAME  (serviço: $SERVICE_NAME, dir: $INSTALL_DIR, user: $SYSTEM_USER)"

_check_port() {
  local p=$1
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp "sport = :$p" 2>/dev/null | grep -qv 'State.*Recv-Q' && return 0
  elif command -v lsof >/dev/null 2>&1; then
    lsof -i:"$p" 2>/dev/null | grep -q LISTEN && return 0
  fi
  return 1
}

while :; do
  printf "Porta da API (host) [%s]: " "$DOTNET_DEFAULT_PORT"; read -r APP_PORT
  APP_PORT=${APP_PORT:-$DOTNET_DEFAULT_PORT}
  case "$APP_PORT" in *[!0-9]*|'') error "Porta inválida: $APP_PORT" ;; esac
  if _check_port "$APP_PORT"; then
    warn "Porta $APP_PORT já está em uso!"
    printf "  (M)atar processo, (T)rocar porta, (C)ancelar [M/t/c]: "; read -r PORT_ACT
    case "$PORT_ACT" in
      [Tt]) continue ;;
      [Cc]) error "Instalação cancelada pelo usuário" ;;
      *)
        fuser -k "$APP_PORT/tcp" 2>/dev/null && info "Processo na porta $APP_PORT encerrado" || warn "Não foi possível encerrar — tente trocar a porta"
        sleep 1
        ;;
    esac
  fi
  break
done
info "Porta da API: $APP_PORT"

# Localização no Nginx: "/" (raiz) ou "/meuerp/" (subcaminho)
while :; do
  printf "Caminho (location) no Nginx — raiz ou subpasta? [/] ou [/%s/]: " "$PROJECT_NAME"; read -r APP_LOCATION
  APP_LOCATION=${APP_LOCATION:-/}
  case "$APP_LOCATION" in
    /)      break ;;
    /*/)    break ;;
    /*)     warn "Use a barra final (ex.: /meuerp/)" ;;
    *)      warn "O caminho deve começar com /" ;;
  esac
done
info "Location Nginx: $APP_LOCATION"

# Domínio ou IP público (para o server_name do Nginx)
printf "Domínio/IP (server_name) — se vazio usa '_' (qualquer) [ex.: api.meuserver.com.br]: "; read -r APP_SERVER_NAME
APP_SERVER_NAME=${APP_SERVER_NAME:-_}
info "server_name: $APP_SERVER_NAME"


# --------------------------------------------------------------
# Publish da API (dotnet publish)
# --------------------------------------------------------------
info "===== Publicando a API ASP.NET Core ====="
mkdir -p "$APP_DIR"
info "Executando: dotnet publish (pode levar alguns minutos — requer acesso ao NuGet)..."
if ! "$DOTNET_BIN" publish "$PROJECT_SRC/MeuErpApi.csproj" -c Release -o "$APP_DIR" --nologo; then
  error "Falha no dotnet publish. Verifique a conexão com NuGet (https://api.nuget.org) e o SDK."
fi
[ -f "$APP_DIR/MeuErpApi.dll" ] || error "MeuErpApi.dll não foi gerada — publish incompleto."
info "Publish concluído em $APP_DIR"


# --------------------------------------------------------------
# Diretórios, usuário e .env (segredos usados pelo systemd)
# --------------------------------------------------------------
info "===== Preparando diretórios e configuração ====="
mkdir -p "$DATA_DIR"
id -u "$SYSTEM_USER" >/dev/null 2>&1 || useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SYSTEM_USER"

MEUERP_JWT_KEY=$(openssl rand -hex 48 2>/dev/null || openssl rand -hex 32)
cat > "$INSTALL_DIR/.env" <<ENVEOF
# MeuERP API — variáveis de ambiente do serviço systemd
MEUERP_DB=$DATA_DIR/erp.db
MEUERP_JWT_KEY=$MEUERP_JWT_KEY
ENVEOF
chmod 600 "$INSTALL_DIR/.env"

chown -R "$SYSTEM_USER":"$SYSTEM_USER" "$INSTALL_DIR" && info "Permissões ajustadas ($SYSTEM_USER)"
info "Banco SQLite: $DATA_DIR/erp.db  |  Chave JWT gerada (MUDE via $INSTALL_DIR/.env)"

# --------------------------------------------------------------
# Serviço systemd
# --------------------------------------------------------------
info "===== Criando serviço systemd ($SERVICE_NAME) ====="
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SVCEOF
[Unit]
Description=MeuERP API (.NET ASP.NET Core)
After=network.target

[Service]
Type=simple
User=$SYSTEM_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$INSTALL_DIR/.env
Environment=ASPNETCORE_URLS=http://127.0.0.1:${APP_PORT}
Environment=ASPNETCORE_ENVIRONMENT=Production
${DOTNET_ROOT_LINE}
Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ExecStart=$DOTNET_BIN $APP_DIR/MeuErpApi.dll
Restart=always
RestartSec=5
LimitNOFILE=65535
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl start "$SERVICE_NAME"
info "Serviço iniciado (systemctl status $SERVICE_NAME)"


# --------------------------------------------------------------
# Nginx — proxy reverso
# --------------------------------------------------------------
info "===== Configurando Nginx ====="

# DSB: upstream com "/" no final para "tirar" o prefixo da URL no subcaminho.
REDIRECT_BLOCK=""
if [ "$APP_LOCATION" != "/" ]; then
  REDIRECT_BLOCK="    location = ${APP_LOCATION%/} { return 301 ${APP_LOCATION}; }
"
fi
cat > "$NGINX_SITE" <<NGINXEOF
# MeuERP API — gerado por install_meuerp.sh
# para HTTPS, gere um certificado (ex.: certbot --nginx) ou adicione o bloco 443.
server {
    listen 80;
    listen [::]:80;
    server_name ${APP_SERVER_NAME};
    client_max_body_size 50m;

    location ~ /\. {
        deny all;
        return 404;
    }

${REDIRECT_BLOCK}    location ${APP_LOCATION} {
        proxy_pass http://127.0.0.1:${APP_PORT}/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXEOF

# Ativa o site (sites-enabled) — padrão do pacote nginx do Debian
if [ -d /etc/nginx/sites-enabled ]; then
  ln -sf "$NGINX_SITE" "/etc/nginx/sites-enabled/${PROJECT_NAME}.conf"
else
  error "Pasta /etc/nginx/sites-enabled não existe no seu Nginx — configure manualmente."
fi

# Se server_name é "_" e o site default "catch-all" estiver ativo, desative-o para evitar conflito
if [ "${APP_SERVER_NAME}" = "_" ] && [ -e /etc/nginx/sites-enabled/default ]; then
  warn "Desativando o site default do Debian para evitar conflito com server_name '_'..."
  rm -f /etc/nginx/sites-enabled/default
fi

if nginx -t 2>&1; then
  systemctl reload nginx.service 2>/dev/null || service nginx reload 2>/dev/null
  info "Nginx recarregado com sucesso!"
else
  warn "Configuração do nginx inválida — execute: sudo nginx -t"
fi


# --------------------------------------------------------------
# Healthcheck
# --------------------------------------------------------------
info "===== Aguardando a API responder ====="
HTTP_CODE=000
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$APP_PORT/" 2>/dev/null || echo 000)
  [ "$HTTP_CODE" = "200" ] && { info "API respondendo em http://127.0.0.1:$APP_PORT/ (HTTP $HTTP_CODE)"; break; }
  [ "$i" -eq 30 ] && warn "A API não respondeu (HTTP $HTTP_CODE). Veja: sudo journalctl -u $SERVICE_NAME -n 50"
  sleep 1
done


# --------------------------------------------------------------
# Final
# --------------------------------------------------------------
echo ""
info "===== Instalação concluída! ====="
echo ""
LOCAL_URL="http://127.0.0.1:${APP_PORT}${APP_LOCATION}"
if [ "${APP_SERVER_NAME}" = "_" ]; then
  EXT_BASE="http://<IP-DO-SERVIDOR>${APP_LOCATION}"
else
  EXT_BASE="http://${APP_SERVER_NAME}${APP_LOCATION}"
fi
echo "  Local:    $LOCAL_URL  (página e API)"
echo "  Externo:  ${EXT_BASE}"
echo "  .env:     $INSTALL_DIR/.env"
echo "  Banco:    $DATA_DIR/erp.db"
echo ""
echo "  Credenciais padrão:  login=admin  senha=admin123   (administrador)"
echo ""
echo "  Teste a API:"
echo "    curl -s -X POST ${EXT_BASE}api/Auth/login \\"
echo "           -H 'Content-Type: application/json' \\"
echo "           -d '{\"login\":\"admin\",\"senha\":\"admin123\"}'"
echo ""
echo "    # Use o token retornado:"
echo "    curl -s -H \"Authorization: Bearer <TOKEN>\" ${EXT_BASE}api/Produtos"
echo ""
echo "  Swagger (somente em Development):"
echo "    O serviço roda com ASPNETCORE_ENVIRONMENT=Production."
echo "    Para habilitar, troque para Development em /etc/systemd/system/${SERVICE_NAME}.service e reinicie."
echo ""
echo "  Comandos úteis:"
echo "    Logs:      sudo journalctl -u $SERVICE_NAME -f"
echo "    Status:    sudo systemctl status $SERVICE_NAME"
echo "    Restart:   sudo systemctl restart $SERVICE_NAME"
echo "    Desinstall: sudo bash $SCRIPT_DIR/install_meuerp.sh uninstall $PROJECT_NAME"
echo ""