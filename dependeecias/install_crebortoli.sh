#!/bin/sh
set -eu

# ==============================================================
# Script de instalação — API Crebortoli (Docker)
# Uso: sudo bash install_crebortoli.sh          (instalar)
#       sudo bash install_crebortoli.sh uninstall (desinstalar)
#
# API REST com Fastify + SQLite (node:sqlite built-in) em container Docker.
# Requer: Debian 11+ (sudo apt para dependências)
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/var/www/crebortoli"
SRC_DIR="$INSTALL_DIR/api/src"
NGINX_CONF="/etc/nginx/sites-available/default"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_crebortoli.sh"


# ==============================================================
# Uninstall
# ==============================================================
uninstall() {
  echo ""
  info "===== Iniciando desinstalação da API Crebortoli (Docker) ====="

  echo ""

  [ -f "$INSTALL_DIR/.env" ] && . "$INSTALL_DIR/.env" || true

  dname="${COMPOSE_PROJECT_NAME:-crebortoli}"

  _dc_cmd="docker compose"
  docker compose version >/dev/null 2>&1 || _dc_cmd="docker-compose"

  echo ""
  info "[1/4] Parando e removendo containers Docker ($dname)..."
  if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    $_dc_cmd -f "$INSTALL_DIR/docker-compose.yml" down -v --rmi local 2>/dev/null && \
      info "Containers, volumes e imagens do projeto removidos" || \
      warn "Falha ao derrubar containers"
  else
    warn "docker-compose.yml não encontrado"
  fi

  echo ""
  info "[2/4] Removendo configuracao nginx..."
  NGINX_LOCATIONS="/etc/nginx/${dname}-locations.conf"
  rm -f "$NGINX_LOCATIONS" && info "${NGINX_LOCATIONS} removido" || warn "Falha ao remover ${NGINX_LOCATIONS}"
  sed -i "/${dname}-locations.conf/d" "$NGINX_CONF" 2>/dev/null || true
  sed -i "/# BEGIN ${dname}_site/,/# END ${dname}_site/d" "$NGINX_CONF" 2>/dev/null || true
  if nginx -t 2>/dev/null; then
    systemctl reload nginx.service 2>/dev/null && info "Nginx recarregado" || warn "Falha ao recarregar nginx"
  else
    warn "Configuração do nginx inválida — verifique manualmente"
  fi

  echo ""
  info "[3/4] Removendo imagens Docker do projeto..."
  dimg=$(printf '%s' "$dname" | tr '[:upper:]' '[:lower:]')
  for img in "${dimg}-api:latest" "${dimg}_api:latest"; do
    docker images -q "$img" 2>/dev/null | xargs -r docker rmi -f 2>/dev/null || true
  done
  [ -z "$(docker images -q "${dimg}-api:latest" "${dimg}_api:latest" 2>/dev/null)" ] && \
    info "Imagens Docker do projeto removidas" || warn "Falha ao remover algumas imagens"

  echo ""
  info "[4/4] Removendo diretório $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR" && info "Diretório $INSTALL_DIR removido com sucesso" || warn "Falha ao remover diretório $INSTALL_DIR"

  echo ""
  info "Desinstalação concluída!"
}

case "${1:-}" in
  uninstall) uninstall; exit 0 ;;
esac

echo ""
info "===== Iniciando instalação da API Crebortoli (Docker) ====="
echo ""


# --------------------------------------------------------------
# Checagem de dependências — Debian 11+ (Magalu Cloud)
# --------------------------------------------------------------
info "===== Verificando dependências do servidor ====="

# Função auxiliar para detectar gerenciador de pacotes
_apt_update_done=0
_apt_update() {
  if [ "$_apt_update_done" -eq 0 ]; then
    info "Executando apt-get update..."
    apt-get update -qq || error "Falha ao executar apt-get update"
    _apt_update_done=1
  fi
}

# Verificar Debian/Ubuntu
if [ ! -f /etc/debian_version ]; then
  error "Este script requer Debian 11+ ou Ubuntu. /etc/debian_version não encontrado."
fi
DEB_VER=$(cat /etc/debian_version 2>/dev/null || echo "desconhecido")
info "Sistema: Debian $DEB_VER"

# Verificar root
[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_crebortoli.sh"

# curl — necessário para download e healthcheck
if ! command -v curl >/dev/null 2>&1; then
  warn "curl não encontrado — instalando..."
  _apt_update && apt-get install -y -qq curl
  command -v curl >/dev/null 2>&1 && info "curl instalado" || error "Falha ao instalar curl"
else
  info "curl: $(curl --version 2>&1 | head -1)"
fi

# openssl — necessário para gerar API_TOKEN
if ! command -v openssl >/dev/null 2>&1; then
  warn "openssl não encontrado — instalando..."
  _apt_update && apt-get install -y -qq openssl
  command -v openssl >/dev/null 2>&1 && info "openssl instalado" || error "Falha ao instalar openssl"
else
  info "openssl: $(openssl version 2>&1)"
fi

# ss ou lsof — necessário para verificar portas
if ! command -v ss >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
  warn "ss/lsof não encontrado — instalando iproute2..."
  _apt_update && apt-get install -y -qq iproute2
  command -v ss >/dev/null 2>&1 && info "ss instalado" || warn "ss não disponível — verificação de portas limitada"
else
  info "ss/lsof: disponível"
fi

# fuser — necessário para liberar portas
if ! command -v fuser >/dev/null 2>&1; then
  warn "fuser não encontrado — instalando psmisc..."
  _apt_update && apt-get install -y -qq psmisc
  command -v fuser >/dev/null 2>&1 && info "fuser instalado" || warn "fuser não disponível"
fi


# --------------------------------------------------------------
# Docker Engine — instala via apt se não existir
# --------------------------------------------------------------
info "Verificando Docker Engine..."
if ! command -v docker >/dev/null 2>&1; then
  warn "Docker não encontrado — instalando docker.io via apt..."
  _apt_update && apt-get install -y -qq docker.io
  systemctl enable --now docker
  sleep 2
  if docker --version >/dev/null 2>&1; then
    info "Docker instalado: $(docker --version)"
  else
    error "Falha ao instalar Docker Engine"
  fi
else
  info "Docker: $(docker --version 2>&1)"
fi

# Verificar se Docker daemon está rodando
if ! docker info >/dev/null 2>&1; then
  warn "Docker daemon não está rodando — tentando iniciar..."
  systemctl start docker 2>/dev/null || service docker start 2>/dev/null
  sleep 3
  docker info >/dev/null 2>&1 || error "Docker daemon não está rodando. Verifique: systemctl status docker"
fi
info "Docker daemon: ativo"


# --------------------------------------------------------------
# Docker Compose — plugin ou standalone
# --------------------------------------------------------------
info "Verificando Docker Compose..."
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
  info "Docker Compose (plugin): $(docker compose version --short 2>/dev/null || echo 'ok')"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
  info "Docker Compose (standalone): $(docker-compose --version 2>&1)"
else
  warn "Docker Compose não encontrado — instalando plugin..."
  _apt_update && apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
    apt-get install -y -qq docker-compose 2>/dev/null || {
      # Fallback: instalar standalone via curl
      warn "apt falhou — instalando docker-compose standalone via curl..."
      COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
      curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
    }
  if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
    info "Docker Compose (plugin) instalado: $(docker compose version --short 2>/dev/null || echo 'ok')"
  elif docker-compose --version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    info "Docker Compose (standalone) instalado: $(docker-compose --version 2>&1)"
  else
    error "Falha ao instalar Docker Compose — instale manualmente"
  fi
fi


# --------------------------------------------------------------
# Nginx
# --------------------------------------------------------------
info "Verificando Nginx..."
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
info "  Docker:         $(docker --version 2>&1 | awk '{print $3}' | tr -d ',')"
info "  Docker Compose: $($DOCKER_COMPOSE_CMD version --short 2>/dev/null || $DOCKER_COMPOSE_CMD --version 2>&1 | awk '{print $NF}')"
info "  Nginx:          $(nginx -v 2>&1 | awk -F/ '{print $2}')"
info "  curl:           $(curl --version 2>&1 | head -1 | awk '{print $2}')"
info "  openssl:        $(openssl version 2>&1 | awk '{print $2}')"
info "===================================="


# --------------------------------------------------------------
# Inputs do usuário
# --------------------------------------------------------------
echo "============ Configuração da instalação ============"

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
  printf "Porta do app (host) [3001]: "; read -r APP_PORT
  APP_PORT=${APP_PORT:-3001}
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
info "Porta definida: $APP_PORT"

printf "Nome do projeto Docker/compose [crebortoli]: "; read -r COMPOSE_PROJECT_NAME
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-crebortoli}; info "COMPOSE_PROJECT_NAME: $COMPOSE_PROJECT_NAME"
APP_DOMAIN=api.projetosdinamicos.com.br


# --------------------------------------------------------------
# Criar diretórios e copiar projeto
# --------------------------------------------------------------
info "Criando diretórios..."
mkdir -p "$SRC_DIR" && info "Diretórios criados: $SRC_DIR" || warn "Erro ao criar diretórios"
UPLOAD_DIR="$INSTALL_DIR/uploads"
mkdir -p "$UPLOAD_DIR" && chown 1000:1000 "$UPLOAD_DIR" && info "Diretório de uploads criado: $UPLOAD_DIR (owner 1000:1000)" || warn "Erro ao criar/ajustar diretório de uploads"


# --------------------------------------------------------------
# .env  (usado pelo docker-compose e pelo container)
# --------------------------------------------------------------
API_TOKEN=$(openssl rand -hex 16 2>/dev/null || echo "$(date +%s)$RANDOM" | md5sum | head -c 32)
info "Criando .env (PORT=$APP_PORT, API_TOKEN gerado)"
cat > "$INSTALL_DIR/.env" <<ENVEOF
# App
PORT=$APP_PORT
API_TOKEN=$API_TOKEN
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME

# Banco de dados SQLite (arquivo dentro do volume /data)
DB_PATH=/data/crebortoli.db

# PM2_APP_NAME mantido para compatibilidade com nginx
PM2_APP_NAME=$COMPOSE_PROJECT_NAME
ENVEOF
chmod 600 "$INSTALL_DIR/.env" && info "Permissões do .env ajustadas (600)" || warn "Falha ao ajustar permissões"


# --------------------------------------------------------------
# package.json
# --------------------------------------------------------------
info "Criando package.json"
cat > "$INSTALL_DIR/api/package.json" <<'JSONEOF'
{
  "name": "crebortoli-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js",
    "test": "node tests/api.test.js"
  },
  "dependencies": {
    "@fastify/cors": "^9.0.0",
    "@fastify/multipart": "^8.0.0",
    "@fastify/rate-limit": "^9.0.0",
    "@fastify/static": "^7.0.0",
    "dotenv": "^16.4.0",
    "fastify": "^4.28.0",
    "undici": "^5.28.4"
  }
}
JSONEOF


# --------------------------------------------------------------
# servicos.json (dados iniciais — copiado para o container)
# --------------------------------------------------------------
info "Criando servicos.json"
cat > "$INSTALL_DIR/servicos.json" <<'SVCEOF'
{
  "servicos": [
    { "id": "dep_perna", "nome": "Depilação Perna", "categoria": "Depilação", "preco": 25, "duracao_minutos": 45, "ativo": 1 },
    { "id": "dep_virilha", "nome": "Depilação Virilha Completa", "categoria": "Depilação", "preco": 50, "duracao_minutos": 40, "ativo": 1 },
    { "id": "dep_buco", "nome": "Depilação Buço", "categoria": "Depilação", "preco": 15, "duracao_minutos": 15, "ativo": 1 },
    { "id": "dep_axilas", "nome": "Depilação Axilas", "categoria": "Depilação", "preco": 20, "duracao_minutos": 20, "ativo": 1 },
    { "id": "dep_pacote", "nome": "Pacote Mensal Depilação", "categoria": "Depilação", "preco": 90, "duracao_minutos": 60, "ativo": 1, "desconto": "De R$110 por R$90" },
    { "id": "barreira_cutanea", "nome": "Reparação de Barreira Cutânea", "categoria": "Tratamento", "preco": 50, "duracao_minutos": 40, "ativo": 1 },
    { "id": "limpeza_pele", "nome": "Limpeza de Pele", "categoria": "Tratamento", "preco": 100, "duracao_minutos": 60, "ativo": 1 },
    { "id": "massagem", "nome": "Massagem Relaxante", "categoria": "Massagem", "preco": 50, "duracao_minutos": 60, "ativo": 1 }
  ]
}
SVCEOF
info "servicos.json criado"


# --------------------------------------------------------------
# src/server.js
# --------------------------------------------------------------
info "Criando src/server.js"
cat > "$SRC_DIR/server.js" <<'SVREOF'
import Fastify from 'fastify';
import fastifyStatic from '@fastify/static';
import cors from '@fastify/cors';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import { DatabaseSync } from 'node:sqlite';
import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import crypto from 'crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

const fastify = Fastify({ logger: true });

const logOperations = (operation, details) => {
  const log = {
    timestamp: new Date().toISOString(),
    operation,
    ...details
  };
  fastify.log.info(log);
};

const DB_PATH = process.env.DB_PATH || path.join(PROJECT_ROOT, 'data', 'crebortoli.db');
const DB_DIR = process.env.DB_DIR || path.dirname(DB_PATH);

const PROJECTS = {
  crebortoli: {
    dbPath: DB_PATH,
    root: PROJECT_ROOT,
  },
};

const TABLES = {
  default: [
    { name: 'agendamentos', columns: 'id TEXT PRIMARY KEY, cliente TEXT, telefone TEXT, servico TEXT, servico_nome TEXT, valor REAL, data TEXT, hora TEXT, status TEXT DEFAULT \'pendente\', pago INTEGER DEFAULT 0, observacoes TEXT, created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'servicos', columns: 'id TEXT PRIMARY KEY, nome TEXT, descricao TEXT, categoria TEXT, preco REAL, duracao_minutos INTEGER, ativo INTEGER DEFAULT 1, created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'clientes', columns: 'id TEXT PRIMARY KEY, nome TEXT, telefone TEXT, email TEXT, cpf TEXT, endereco TEXT, observacoes TEXT, created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'receitas', columns: 'id TEXT PRIMARY KEY, paciente TEXT, data TEXT, data_formatada TEXT, indicacao TEXT, medicamentos TEXT, observacoes TEXT, comentarios TEXT, nome_arquivo TEXT, cliente_id TEXT, diagnostico TEXT, prescricao TEXT, validado INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'contatos', columns: 'id TEXT PRIMARY KEY, nome TEXT, email TEXT, telefone TEXT, mensagem TEXT, lido INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'sessoes', columns: 'id TEXT PRIMARY KEY, token TEXT UNIQUE, url_aprovacao TEXT, status TEXT DEFAULT \'pendente\', last_sync TEXT, access_token TEXT, aprovado_em TEXT, created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'usuarios', columns: 'id TEXT PRIMARY KEY, email TEXT UNIQUE, senha TEXT, nome TEXT, nivel TEXT DEFAULT \'user\', created_at TEXT DEFAULT (datetime(\'now\'))' },
    { name: 'configuracoes', columns: 'id TEXT PRIMARY KEY, chave TEXT UNIQUE, valor TEXT, updated_at TEXT DEFAULT (datetime(\'now\'))' },
  ]
};

const dbs = {};
function getDb(project) {
  if (!dbs[project]) {
    const { dbPath } = PROJECTS[project];
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    const db = new DatabaseSync(dbPath);
    db.exec('PRAGMA journal_mode = WAL');
    db.exec('PRAGMA busy_timeout = 5000');
    dbs[project] = db;
  }
  return dbs[project];
}

const API_TOKEN = process.env.API_TOKEN;

if (!API_TOKEN) {
  console.error('ERRO: API_TOKEN nao definido. Defina via variavel de ambiente.');
  process.exit(1);
}

const API_WRITE_KEY = process.env.API_WRITE_KEY || process.env.API_TOKEN;

await fastify.register(cors, { origin: true, methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'], allowedHeaders: ['Content-Type', 'Authorization', 'X-Write-Key'] });
await fastify.register(multipart, { limits: { fileSize: 50 * 1024 * 1024 } });
await fastify.register(rateLimit, { max: 100, timeWindow: '1 minute', keyGenerator: (req) => req.ip });

function validateTableName(table) {
  return /^[a-z_][a-z0-9_]{0,63}$/.test(table);
}
function validateId(id) {
  return /^[a-zA-Z0-9_-]{1,128}$/.test(id);
}

function sanitizeSqlParams(params) {
  return params.map(v => {
    if (typeof v === 'boolean') return v ? 1 : 0;
    if (v === undefined) return null;
    return v;
  });
}

function query(project, sql, params = []) {
  if (!PROJECTS[project]) throw new Error('Projeto nao encontrado');
  const stmt = getDb(project).prepare(sql);
  const safe = sanitizeSqlParams(params);
  if (/^\s*(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b/i.test(sql) && !/RETURNING\b/i.test(sql)) {
    return { rows: [], changes: stmt.run(...safe).changes };
  }
  return { rows: stmt.all(...safe) };
}

const authMiddleware = async (req, reply) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token || token !== API_TOKEN) {
    reply.code(401).send({ success: false, error: 'Unauthorized' });
    return;
  }
};

const writeAuthMiddleware = async (req, reply) => {
  const writeKey = req.headers['x-write-key'];
  const authToken = req.headers.authorization?.replace('Bearer ', '');

  if (!writeKey && !authToken) {
    reply.code(403).send({ success: false, error: 'Write access denied' });
    return;
  }

  if (writeKey && writeKey !== API_WRITE_KEY) {
    reply.code(403).send({ success: false, error: 'Invalid write key' });
    return;
  }

  if (authToken && authToken !== API_TOKEN) {
    reply.code(403).send({ success: false, error: 'Invalid token' });
    return;
  }
};

fastify.get('/health', async () => {
  const checks = {};
  for (const [name, config] of Object.entries(PROJECTS)) {
    try { getDb(name).prepare('SELECT 1').get(); checks[name] = 'ok'; }
    catch (err) { checks[name] = 'error'; }
  }
  return { status: 'ok', projects: checks, timestamp: new Date().toISOString() };
});

fastify.get('/ping', async () => ({ pong: true }));

fastify.get('/data/:table', async (req, res) => {
  const { table } = req.params;
  if (!['servicos', 'agendamentos', 'clientes', 'contatos', 'receitas', 'sessoes'].includes(table)) {
    return res.code(400).send({ error: 'Tabela invalida' });
  }
  const result = await query('crebortoli', 'SELECT * FROM "' + table + '" ORDER BY created_at DESC LIMIT 100');
  return res.code(200).send(result.rows);
});

fastify.get('/crebortoli/data/:table', async (req, res) => {
  const { table } = req.params;
  if (!['servicos', 'agendamentos', 'clientes', 'contatos', 'receitas', 'sessoes'].includes(table)) {
    return res.code(400).send({ error: 'Tabela invalida' });
  }
  const result = await query('crebortoli', 'SELECT * FROM "' + table + '" ORDER BY created_at DESC LIMIT 100');
  return res.code(200).send(result.rows);
});

fastify.get('/crebortoli/:table', async (req, res) => {
  const { table } = req.params;
  if (!['servicos', 'agendamentos', 'clientes', 'contatos', 'receitas', 'sessoes'].includes(table)) {
    return res.code(400).send({ error: 'Tabela invalida' });
  }
  const result = await query('crebortoli', 'SELECT * FROM "' + table + '" ORDER BY created_at DESC LIMIT 100');
  const rows = result.rows.map(row => {
    if (row.data && typeof row.data === 'string') {
      row.data = row.data.split('T')[0];
    }
    return row;
  });
  return res.code(200).send(rows);
});

fastify.get('/config/:chave', async (req, res) => {
  const { chave } = req.params;
  const result = await query('crebortoli', 'SELECT valor FROM configuracoes WHERE chave = ?', [chave]);
  if (!result.rows.length) {
    return res.code(200).send({ data: null });
  }
  try {
    return res.code(200).send({ data: JSON.parse(result.rows[0].valor) });
  } catch {
    return res.code(200).send({ data: result.rows[0].valor });
  }
});

fastify.post('/api.php', async (req, res) => {
  const { action, ...data } = req.body || {};

  switch (action) {
    case 'criar_sessao': {
      const { token, urlAprovacao } = data;
      const id = crypto.randomUUID();
      await query('crebortoli', "INSERT INTO sessoes (id, token, url_aprovacao, status, created_at) VALUES (?, ?, ?, 'aguardando', datetime('now')) ON CONFLICT (token) DO UPDATE SET url_aprovacao = ?, status = 'aguardando'", [id, token, urlAprovacao, urlAprovacao]);
      return { sucesso: true, token };
    }
    case 'verificar_sessao': {
      const { token } = data;
      const result = await query('crebortoli', 'SELECT status FROM sessoes WHERE token = ?', [token]);
      if (!result.rows.length) return { sucesso: false, erro: 'Token nao encontrado' };
      const row = result.rows[0];
      if (row.status === 'aprovado') {
        await query('crebortoli', "UPDATE sessoes SET status = 'usada' WHERE token = ?", [token]);
        return { sucesso: true, aprovado: true };
      }
      return { sucesso: true, aprovado: false };
    }
    case 'sync_timer': {
      const { token } = data;
      await query('crebortoli', "UPDATE sessoes SET last_sync = datetime('now') WHERE token = ?", [token]);
      return { sucesso: true };
    }
    case 'login': {
      const { email, senha } = data;
      const result = await query('crebortoli', 'SELECT * FROM usuarios WHERE email = ? AND senha = ?', [email, senha]);
      if (!result.rows.length) return { sucesso: false, erro: 'Credenciais invalidas' };
      return { sucesso: true, usuario: result.rows[0] };
    }
    default:
      return { erro: 'Acao desconhecida: ' + action };
  }
});

fastify.get('/api/config', async (req, res) => {
  return { token: API_TOKEN, writeKey: API_WRITE_KEY, project: 'crebortoli' };
});

fastify.get('/api/projects', { preHandler: authMiddleware }, async () =>
  Object.keys(PROJECTS).map(name => ({ name, database: path.basename(PROJECTS[name].dbPath) })));

fastify.get('/api/tables/:project', { preHandler: authMiddleware }, async (req) => {
  const { project } = req.params;
  const result = await query(project, "SELECT name AS table_name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  return result.rows;
});

fastify.post('/api/project/create', { preHandler: authMiddleware }, async (req, res) => {
  const { name, tables = TABLES.default } = req.body || {};
  if (!name || !/^[a-z_][a-z0-9_]{0,63}$/.test(name)) {
    return res.code(400).send({ error: 'Nome de projeto invalido' });
  }

  const dbPath = path.join(DB_DIR, name + '.db');
  fs.mkdirSync(DB_DIR, { recursive: true });
  PROJECTS[name] = { dbPath, root: PROJECT_ROOT };

  const db = getDb(name);
  for (const table of tables) {
    try {
      db.exec('CREATE TABLE IF NOT EXISTS "' + table.name + '" (' + table.columns + ')');
    } catch (e) {
      console.error('Erro ao criar tabela ' + table.name + ':', e.message);
    }
  }

  return { success: true, project: name, tables: tables.map(t => t.name) };
});

fastify.post('/api/config/get', { preHandler: authMiddleware }, async (req, res) => {
  const { chave } = req.body || {};
  if (!chave) {
    return res.code(400).send({ error: 'Chave requerida' });
  }
  const result = await query('crebortoli', 'SELECT valor FROM configuracoes WHERE chave = ?', [chave]);
  if (!result.rows.length) {
    return { data: null };
  }
  try {
    return { data: JSON.parse(result.rows[0].valor) };
  } catch {
    return { data: result.rows[0].valor };
  }
});

fastify.post('/api/config/set', { preHandler: authMiddleware }, async (req, res) => {
  const { chave, valor } = req.body || {};
  if (!chave) {
    return res.code(400).send({ error: 'Chave requerida' });
  }
  const valorJson = typeof valor === 'object' ? JSON.stringify(valor) : valor;
  const result = await query('crebortoli', "INSERT INTO configuracoes (id, chave, valor, updated_at) VALUES (?, ?, ?, datetime('now')) ON CONFLICT (chave) DO UPDATE SET valor = ?, updated_at = datetime('now') RETURNING *", [crypto.randomUUID(), chave, valorJson, valorJson]);
  return { success: true, data: result.rows[0] };
});

fastify.post('/api/table/create', { preHandler: authMiddleware }, async (req, res) => {
  const { project, table_name, columns } = req.body || {};
  if (!project || !PROJECTS[project] || !table_name || !columns) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  if (!validateTableName(table_name)) {
    return res.code(400).send({ error: 'Nome de tabela invalido' });
  }

  try {
    await query(project, 'CREATE TABLE IF NOT EXISTS "' + table_name + '" (' + columns + ')');
    return { success: true, table: table_name };
  } catch (e) {
    return res.code(400).send({ error: e.message });
  }
});

fastify.post('/crebortoli/api/read', async (req, res) => {
  const { project = 'crebortoli', table, filters = {}, columns = ['*'], order_by = 'created_at', order_dir = 'DESC', limit = 100, offset = 0 } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table)) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const colList = (!columns || (Array.isArray(columns) && columns.length === 1 && columns[0] === '*')) ? '*' : columns.map(c => '"' + c + '"').join(', ');
  if (!validateTableName(order_by)) return res.code(400).send({ error: 'Invalid order_by' });
  const conditions = Object.keys(filters).map((k) => {
    if (!validateTableName(k)) return null;
    return Array.isArray(filters[k])
      ? '"' + k + '" IN (' + filters[k].map(() => '?').join(',') + ')'
      : '"' + k + '" = ?';
  }).filter(Boolean).join(' AND ');
  const params = Object.values(filters).flat();
  const lim = Math.min(parseInt(limit) || 100, 1000);

  const [countRes, dataRes] = await Promise.all([
    query(project, 'SELECT COUNT(*) FROM "' + table + '"' + (conditions ? ' WHERE ' + conditions : ''), params),
    query(project, 'SELECT ' + colList + ' FROM "' + table + '"' + (conditions ? ' WHERE ' + conditions : '') + ' ORDER BY "' + order_by + '" ' + (order_dir.toUpperCase() === 'ASC' ? 'ASC' : 'DESC') + ' LIMIT ' + lim + ' OFFSET ' + offset, params),
  ]);

  return { data: dataRes.rows, pagination: { total: parseInt(countRes.rows[0].count), limit: lim, offset } };
});

fastify.post('/crebortoli/data/create', { preHandler: writeAuthMiddleware }, async (req, res) => {
  const { project = 'crebortoli', table, data } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table) || !data) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const sanitized = {};
  for (const [k, v] of Object.entries(data)) {
    if (validateTableName(k)) sanitized[k] = v;
  }
  sanitized.id = sanitized.id || crypto.randomUUID();
  sanitized.created_at = sanitized.created_at || new Date().toISOString();
  const cols = Object.keys(sanitized).map(c => '"' + c + '"').join(', ');
  const vals = Object.keys(sanitized).map(() => '?').join(', ');
  const result = await query(project, 'INSERT INTO "' + table + '" (' + cols + ') VALUES (' + vals + ') RETURNING *', Object.values(sanitized));
  return { success: true, data: result.rows[0] };
});

fastify.post('/crebortoli/data/update', { preHandler: writeAuthMiddleware }, async (req, res) => {
  const { project = 'crebortoli', table, id, data } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table) || !validateId(id) || !data) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const sanitized = {};
  for (const [k, v] of Object.entries(data)) {
    if (validateTableName(k) && !['id', 'created_at'].includes(k)) sanitized[k] = v;
  }
  if (!Object.keys(sanitized).length) return res.code(400).send({ error: 'No valid fields' });
  const sets = Object.keys(sanitized).map(k => '"' + k + '" = ?').join(', ');
  const result = await query(project, 'UPDATE "' + table + '" SET ' + sets + ' WHERE id = ? RETURNING *', [...Object.values(sanitized), id]);
  if (!result.rows.length) return res.code(404).send({ error: 'Not found' });
  return { success: true, data: result.rows[0] };
});

fastify.post('/crebortoli/data/delete', { preHandler: writeAuthMiddleware }, async (req, res) => {
  const { project = 'crebortoli', table, id } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table) || !validateId(id)) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const result = await query(project, 'DELETE FROM "' + table + '" WHERE id = ? RETURNING id', [id]);
  if (!result.rows.length) return res.code(404).send({ error: 'Not found' });
  return { success: true, deleted: true, id };
});

fastify.post('/crebortoli/create', { preHandler: writeAuthMiddleware }, async (req, res) => {
  const { project = 'crebortoli', table, data } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table) || !data) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const item = {};
  for (const [k, v] of Object.entries(data)) {
    if (validateTableName(k)) item[k] = v;
  }
  item.id = item.id || crypto.randomUUID();
  item.created_at = item.created_at || new Date().toISOString();
  const cols = Object.keys(item).map(c => '"' + c + '"').join(', ');
  const vals = Object.keys(item).map(() => '?').join(', ');
  try {
    const result = await query(project, 'INSERT INTO "' + table + '" (' + cols + ') VALUES (' + vals + ') RETURNING *', Object.values(item));
    return { success: true, data: result.rows[0] };
  } catch (e) {
    return res.code(500).send({ error: e.message });
  }
});

fastify.post('/crebortoli/update', { preHandler: writeAuthMiddleware }, async (req, res) => {
  const { project = 'crebortoli', table, id, data } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table) || !validateId(id) || !data) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const item = {};
  for (const [k, v] of Object.entries(data)) {
    if (validateTableName(k) && !['id', 'created_at'].includes(k)) item[k] = v;
  }
  if (!Object.keys(item).length) return res.code(400).send({ error: 'No valid fields' });
  const sets = Object.keys(item).map(k => '"' + k + '" = ?').join(', ');
  try {
    const result = await query(project, 'UPDATE "' + table + '" SET ' + sets + ' WHERE id = ? RETURNING *', [...Object.values(item), id]);
    if (!result.rows.length) return res.code(404).send({ error: 'Not found' });
    return { success: true, data: result.rows[0] };
  } catch (e) {
    return res.code(500).send({ error: e.message });
  }
});

fastify.post('/crebortoli/delete', { preHandler: writeAuthMiddleware }, async (req, res) => {
  const { project = 'crebortoli', table, id } = req.body || {};
  if (!PROJECTS[project] || !validateTableName(table) || !validateId(id)) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const result = await query(project, 'DELETE FROM "' + table + '" WHERE id = ? RETURNING id', [id]);
  if (!result.rows.length) return res.code(404).send({ error: 'Not found' });
  return { success: true, deleted: true, id };
});

fastify.post('/api/read', { preHandler: authMiddleware }, async (req, res) => {
  const { project, table, filters = {}, columns = ['*'], order_by = 'created_at', order_dir = 'DESC', limit = 100, offset = 0 } = req.body || {};
  if (!project || !PROJECTS[project] || !validateTableName(table)) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  if (!validateTableName(order_by)) {
    return res.code(400).send({ error: 'Invalid order_by' });
  }
  const colList = (!columns || (Array.isArray(columns) && columns.length === 1 && columns[0] === '*')) ? '*' : columns.map(c => '"' + c + '"').join(', ');
  const conditions = Object.keys(filters).map((k) => {
    if (!validateTableName(k)) return null;
    return Array.isArray(filters[k])
      ? '"' + k + '" IN (' + filters[k].map(() => '?').join(',') + ')'
      : '"' + k + '" = ?';
  }).filter(Boolean).join(' AND ');
  const params = Object.values(filters).flat();
  const lim = Math.min(parseInt(limit) || 100, 1000);

  const [countRes, dataRes] = await Promise.all([
    query(project, 'SELECT COUNT(*) FROM "' + table + '"' + (conditions ? ' WHERE ' + conditions : ''), params),
    query(project, 'SELECT ' + colList + ' FROM "' + table + '"' + (conditions ? ' WHERE ' + conditions : '') + ' ORDER BY "' + order_by + '" ' + (order_dir.toUpperCase() === 'ASC' ? 'ASC' : 'DESC') + ' LIMIT ' + lim + ' OFFSET ' + offset, params),
  ]);

  return { data: dataRes.rows, pagination: { total: parseInt(countRes.rows[0].count), limit: lim, offset } };
});

fastify.post('/api/create', { preHandler: authMiddleware }, async (req, res) => {
  const { project, table, data } = req.body || {};
  logOperations('create', { project, table, data });
  if (!project || !PROJECTS[project] || !validateTableName(table) || !data) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const sanitized = {};
  for (const [k, v] of Object.entries(data)) {
    if (validateTableName(k)) sanitized[k] = v;
  }
  sanitized.id = sanitized.id || crypto.randomUUID();
  sanitized.created_at = sanitized.created_at || new Date().toISOString();
  const cols = Object.keys(sanitized).map(c => '"' + c + '"').join(', ');
  const vals = Object.keys(sanitized).map(() => '?').join(', ');
  try {
    const result = await query(project, 'INSERT INTO "' + table + '" (' + cols + ') VALUES (' + vals + ') RETURNING *', Object.values(sanitized));
    return { success: true, data: result.rows[0] };
  } catch (e) {
    fastify.log.error('Erro ao criar registro:', e.message);
    return res.code(500).send({ error: e.message });
  }
});

fastify.post('/api/update', { preHandler: authMiddleware }, async (req, res) => {
  const { project, table, id, data } = req.body || {};
  logOperations('update', { project, table, id });
  if (!project || !PROJECTS[project] || !validateTableName(table) || !validateId(id) || !data) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  const sanitized = {};
  for (const [k, v] of Object.entries(data)) {
    if (validateTableName(k) && !['id', 'created_at'].includes(k)) sanitized[k] = v;
  }
  if (!Object.keys(sanitized).length) return res.code(400).send({ error: 'No valid fields' });
  const sets = Object.keys(sanitized).map(k => '"' + k + '" = ?').join(', ');
  try {
    const result = await query(project, 'UPDATE "' + table + '" SET ' + sets + ' WHERE id = ? RETURNING *', [...Object.values(sanitized), id]);
    if (!result.rows.length) return res.code(404).send({ error: 'Not found' });
    return { success: true, data: result.rows[0] };
  } catch (e) {
    fastify.log.error('Erro ao atualizar registro:', e.message);
    return res.code(500).send({ error: e.message });
  }
});

fastify.post('/api/delete', { preHandler: authMiddleware }, async (req, res) => {
  const { project, table, id } = req.body || {};
  logOperations('delete', { project, table, id });
  if (!project || !PROJECTS[project] || !validateTableName(table) || !validateId(id)) {
    return res.code(400).send({ error: 'Invalid request' });
  }
  try {
    const result = await query(project, 'DELETE FROM "' + table + '" WHERE id = ? RETURNING id', [id]);
    if (!result.rows.length) return res.code(404).send({ error: 'Not found' });
    return { success: true, deleted: true, id };
  } catch (e) {
    fastify.log.error('Erro ao excluir registro:', e.message);
    return res.code(500).send({ error: e.message });
  }
});

fastify.post('/api/upload', { preHandler: authMiddleware }, async (req, res) => {
  const data = await req.file();
  if (!data) return res.code(400).send({ error: 'No file' });

  const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'application/pdf'];
  if (!allowedTypes.includes(data.mimetype)) return res.code(400).send({ error: 'File type not allowed' });

  const ext = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/gif': 'gif', 'image/webp': 'webp', 'application/pdf': 'pdf' }[data.mimetype];
  const filename = crypto.randomUUID() + '.' + ext;
  const buffer = await data.toBuffer();

  const uploadDir = path.join(__dirname, '..', process.env.UPLOAD_DIR || 'uploads');
  await fs.promises.mkdir(uploadDir, { recursive: true });
  await fs.promises.writeFile(uploadDir + '/' + filename, buffer);

  return { success: true, filename, url: '/uploads/' + filename, size: buffer.length };
});

fastify.get('/uploads/:name', async (req, res) => {
  const { name } = req.params;
  if (name.includes('..') || name.includes('/')) return res.code(400).send({ error: 'Invalid filename' });
  const filepath = path.join(__dirname, '..', process.env.UPLOAD_DIR || 'uploads', name);
  if (!fs.existsSync(filepath)) return res.code(404).send({ error: 'Not found' });
  return res.send(fs.createReadStream(filepath));
});

const SQL_TOKEN_PREFIX = 'st_';
const SQL_TOKEN_EXPIRY_MS = 30 * 60 * 1000;
const sqlTokenStore = new Map();

setInterval(() => {
  const now = Date.now();
  for (const [token, entry] of sqlTokenStore) {
    if (now - entry.created > SQL_TOKEN_EXPIRY_MS) sqlTokenStore.delete(token);
  }
}, 5 * 60 * 1000);

function sqlTokenize(value) {
  if (value == null || value === '') return value;
  const strVal = String(value);
  for (const [token, entry] of sqlTokenStore) {
    if (entry.value === strVal && Date.now() - entry.created < SQL_TOKEN_EXPIRY_MS) {
      entry.created = Date.now();
      return token;
    }
  }
  const buf = crypto.randomBytes(16);
  const token = SQL_TOKEN_PREFIX + buf.toString('base64url').slice(0, 12);
  sqlTokenStore.set(token, { value: strVal, created: Date.now() });
  return token;
}

function sqlResolve(token) {
  if (!token || typeof token !== 'string' || !token.startsWith(SQL_TOKEN_PREFIX)) return token;
  const entry = sqlTokenStore.get(token);
  if (!entry) return token;
  if (Date.now() - entry.created > SQL_TOKEN_EXPIRY_MS) {
    sqlTokenStore.delete(token);
    return token;
  }
  entry.created = Date.now();
  return entry.value;
}

function sqlSanitizeForLog(sql, params = []) {
  if (!params || !Array.isArray(params)) return sql;
  let s = sql;
  for (const p of params) {
    const r = typeof p === 'string' ? "'" + p.slice(0, 3) + "..[REDACTED]'" : '[REDACTED]';
    s = s.replace('?', r);
  }
  return s;
}

const EXTERNAL_API = process.env.EXTERNAL_API || 'https://api.projetosdinamicos.com.br/crebortoli';

fastify.post('/api/sql/resolve', { preHandler: authMiddleware }, async (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.code(400).send({ error: 'Token required' });
  return { value: sqlResolve(token) };
});

async function proxyHandler(req, reply) {
  const rawProject = req.query.project || 'crebortoli';
  const rawTable = req.query.table || 'agendamentos';
  const action = req.query.action || 'read';
  const rawId = req.query.id;
  const { limit, offset, order_by, order_dir } = req.query;

  const project = sqlResolve(rawProject);
  const table = sqlResolve(rawTable);
  const id = rawId ? sqlResolve(rawId) : null;

  const body = { project, table: sqlTokenize(table) };
  if (action === 'read') {
    if (limit) body.limit = parseInt(limit);
    if (offset) body.offset = parseInt(offset);
    if (order_by) body.order_by = order_by;
    if (order_dir) body.order_dir = order_dir;
  }
  if (action === 'update' || action === 'delete') body.id = id ? sqlTokenize(id) : null;
  if (req.body && typeof req.body === 'object') {
    const safe = {};
    for (const [k, v] of Object.entries(req.body)) {
      safe[k] = ['table', 'id', 'project'].includes(k) ? sqlTokenize(v) : v;
    }
    Object.assign(body, safe);
  }

  try {
    const res = await fetch(EXTERNAL_API + '/api/' + action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + API_TOKEN },
      body: JSON.stringify(body),
    });
    return reply.code(res.status).send(await res.json());
  } catch (err) {
    return reply.code(502).send({ error: 'External API unavailable', details: err.message });
  }
}

fastify.all('/api', proxyHandler);
fastify.all('/api/*', proxyHandler);

await fastify.register(fastifyStatic, {
  root: PROJECT_ROOT,
  prefix: '/',
  wildcard: false,
  setHeaders: (res, filePath) => {
    if (filePath.match(/\.html$/)) {
      res.setHeader('X-Robots-Tag', 'noindex');
    }
  },
});

fastify.setNotFoundHandler(async (req, res) => {
  const indexPath = path.join(PROJECT_ROOT, 'index.html');
  if (fs.existsSync(indexPath)) {
    const content = await fs.promises.readFile(indexPath, 'utf-8');
    res.type('text/html').send(content);
  } else {
    res.code(404).send('Not Found');
  }
});

const start = async () => {
  for (const [name, config] of Object.entries(PROJECTS)) {
    const db = getDb(name);
    try {
      for (const table of TABLES.default) {
        db.exec('CREATE TABLE IF NOT EXISTS "' + table.name + '" (' + table.columns + ')');
        console.log('Tabela "' + table.name + '" verificada/criada em ' + name);
      }

      const tableCols = (tbl) => db.prepare('PRAGMA table_info("' + tbl + '")').all().map(r => r.name);

      const agendamentosNewCols = [
        { name: 'telefone', sql: 'ALTER TABLE "agendamentos" ADD COLUMN telefone TEXT' },
        { name: 'servico_nome', sql: 'ALTER TABLE "agendamentos" ADD COLUMN servico_nome TEXT' },
        { name: 'valor', sql: 'ALTER TABLE "agendamentos" ADD COLUMN valor REAL' },
        { name: 'pago', sql: 'ALTER TABLE "agendamentos" ADD COLUMN pago INTEGER DEFAULT 0' },
      ];

      const existingAgendamentosCols = tableCols('agendamentos');
      for (const col of agendamentosNewCols) {
        if (!existingAgendamentosCols.includes(col.name)) {
          db.exec(col.sql);
          console.log('Coluna "' + col.name + '" adicionada a tabela agendamentos em ' + name);
        }
      }

      const receitasNewCols = [
        { name: 'paciente', sql: 'ALTER TABLE "receitas" ADD COLUMN paciente TEXT' },
        { name: 'data', sql: 'ALTER TABLE "receitas" ADD COLUMN data TEXT' },
        { name: 'data_formatada', sql: 'ALTER TABLE "receitas" ADD COLUMN data_formatada TEXT' },
        { name: 'indicacao', sql: 'ALTER TABLE "receitas" ADD COLUMN indicacao TEXT' },
        { name: 'medicamentos', sql: 'ALTER TABLE "receitas" ADD COLUMN medicamentos TEXT' },
        { name: 'observacoes', sql: 'ALTER TABLE "receitas" ADD COLUMN observacoes TEXT' },
        { name: 'comentarios', sql: 'ALTER TABLE "receitas" ADD COLUMN comentarios TEXT' },
        { name: 'nome_arquivo', sql: 'ALTER TABLE "receitas" ADD COLUMN nome_arquivo TEXT' },
      ];

      const existingReceitasCols = tableCols('receitas');
      for (const col of receitasNewCols) {
        if (!existingReceitasCols.includes(col.name)) {
          db.exec(col.sql);
          console.log('Coluna "' + col.name + '" adicionada a tabela receitas em ' + name);
        }
      }

      const updated_at_tables = ['servicos', 'agendamentos', 'clientes', 'contatos', 'sessoes', 'usuarios'];
      for (const tbl of updated_at_tables) {
        if (!tableCols(tbl).includes('updated_at')) {
          db.exec('ALTER TABLE "' + tbl + '" ADD COLUMN updated_at TEXT');
        }
      }

      const sessoesNewCols = [
        { name: 'access_token', sql: 'ALTER TABLE "sessoes" ADD COLUMN access_token TEXT' },
        { name: 'aprovado_em', sql: 'ALTER TABLE "sessoes" ADD COLUMN aprovado_em TEXT' },
      ];
      const existingSessoesCols = tableCols('sessoes');
      for (const col of sessoesNewCols) {
        if (!existingSessoesCols.includes(col.name)) {
          db.exec(col.sql);
          console.log('Coluna "' + col.name + '" adicionada a tabela sessoes em ' + name);
        }
      }

      // Seed servicos from servicos.json (apenas se tabela vazia)
      // Migration: adicionar coluna categoria se nao existir
      if (!tableCols('servicos').includes('categoria')) {
        db.exec('ALTER TABLE "servicos" ADD COLUMN categoria TEXT');
        console.log('Coluna "categoria" adicionada a tabela servicos em ' + name);
      }

      const servicosCount = db.prepare('SELECT COUNT(*) as cnt FROM servicos').get();
      if (servicosCount.cnt === 0) {
        const servicosPath = path.join(PROJECT_ROOT, 'servicos.json');
        if (fs.existsSync(servicosPath)) {
          try {
            const raw = fs.readFileSync(servicosPath, 'utf-8');
            const json = JSON.parse(raw);
            const items = json.servicos || json;
            if (Array.isArray(items) && items.length > 0) {
              const stmt = db.prepare('INSERT OR IGNORE INTO servicos (id, nome, descricao, categoria, preco, duracao_minutos, ativo, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime(\'now\'))');
              for (const s of items) {
                stmt.run(s.id || crypto.randomUUID(), s.nome || '', s.descricao || '', s.categoria || '', s.preco || 0, s.duracao_minutos || 30, s.ativo ?? 1);
              }
              console.log('Seed: ' + items.length + ' servicos inseridos de servicos.json');
            }
          } catch (e) {
            console.error('Erro ao fazer seed de servicos.json:', e.message);
          }
        } else {
          console.log('servicos.json nao encontrado em ' + PROJECT_ROOT + ' — seed ignorado');
        }
      } else {
        console.log('Tabela servicos ja possui dados (' + servicosCount.cnt + ' registros) — seed ignorado');
      }

    } catch (e) {
      console.error('Erro ao criar tabelas em ' + name + ':', e.message);
    }
  }
  const PORT = process.env.PORT || 3001;
  await fastify.listen({ port: PORT, host: '0.0.0.0' });
  console.log('Server: http://0.0.0.0:' + PORT);
};
start();
SVREOF
info "src/server.js criado"


# --------------------------------------------------------------
# Dockerfile
# --------------------------------------------------------------
info "Criando Dockerfile"
cat > "$INSTALL_DIR/Dockerfile" <<'DOCKEREOF'
FROM node:22-alpine

WORKDIR /app

# Dependências primeiro (cache de camada)
COPY api/package.json ./
RUN npm install --production

# Código-fonte
COPY api/src/ ./src/

# Dados iniciais de serviços (seed SQLite)
COPY servicos.json ./servicos.json

EXPOSE 3001

CMD ["node", "src/server.js"]
DOCKEREOF


# --------------------------------------------------------------
# docker-compose.yml
# --------------------------------------------------------------
info "Criando docker-compose.yml"
cat > "$INSTALL_DIR/docker-compose.yml" <<'COMPOSEEOF'
services:
  api:
    build: .
    ports:
      - "127.0.0.1:${PORT}:${PORT}"
    environment:
      PORT: ${PORT}
      API_TOKEN: ${API_TOKEN}
      DB_PATH: /data/crebortoli.db
      UPLOAD_DIR: /uploads
    volumes:
      - ./data:/data
      - ./uploads:/uploads
      - ./servicos.json:/app/servicos.json:ro
    restart: unless-stopped
COMPOSEEOF


# --------------------------------------------------------------
# Migration SQL (arquivo de referência — tabelas criadas automaticamente no startup)
# --------------------------------------------------------------
info "Criando migration de referência..."
mkdir -p "$INSTALL_DIR/migrations"
cat > "$INSTALL_DIR/migrations/001_create_tables.sql" <<SQLEOF
-- ============================================================
-- Migration 001: Cria todas as tabelas do sistema Crebortoli (SQLite)
-- NOTA: As tabelas são criadas automaticamente no startup da API.
-- Este arquivo é mantido como referência/documentação.
-- ============================================================

CREATE TABLE IF NOT EXISTS agendamentos (
    id TEXT PRIMARY KEY, cliente TEXT, telefone TEXT, servico TEXT,
    servico_nome TEXT, valor REAL, data TEXT, hora TEXT,
    status TEXT DEFAULT 'pendente', pago INTEGER DEFAULT 0,
    observacoes TEXT, created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS servicos (
    id TEXT PRIMARY KEY, nome TEXT, descricao TEXT, categoria TEXT, preco REAL,
    duracao_minutos INTEGER, ativo INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS clientes (
    id TEXT PRIMARY KEY, nome TEXT, telefone TEXT, email TEXT, cpf TEXT,
    endereco TEXT, observacoes TEXT, created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS receitas (
    id TEXT PRIMARY KEY, paciente TEXT, data TEXT, data_formatada TEXT,
    indicacao TEXT, medicamentos TEXT, observacoes TEXT, comentarios TEXT,
    nome_arquivo TEXT, cliente_id TEXT, diagnostico TEXT, prescricao TEXT,
    validado INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS contatos (
    id TEXT PRIMARY KEY, nome TEXT, email TEXT, telefone TEXT,
    mensagem TEXT, lido INTEGER DEFAULT 0, created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sessoes (
    id TEXT PRIMARY KEY, token TEXT UNIQUE, url_aprovacao TEXT,
    status TEXT DEFAULT 'pendente', last_sync TEXT,
    access_token TEXT, aprovado_em TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS usuarios (
    id TEXT PRIMARY KEY, email TEXT UNIQUE, senha TEXT, nome TEXT,
    nivel TEXT DEFAULT 'user', created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS configuracoes (
    id TEXT PRIMARY KEY, chave TEXT UNIQUE, valor TEXT,
    updated_at TEXT DEFAULT (datetime('now'))
);
SQLEOF


# --------------------------------------------------------------
# Nginx — gera config separada (locations) + include
# --------------------------------------------------------------
info "Configurando Nginx"

NGINX_LOCATIONS="/etc/nginx/${COMPOSE_PROJECT_NAME}-locations.conf"

info "Criando ${NGINX_LOCATIONS}..."
cat > "$NGINX_LOCATIONS" <<NGINXEOF
location /${COMPOSE_PROJECT_NAME}/ {
    proxy_pass http://127.0.0.1:${APP_PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
NGINXEOF
info "${NGINX_LOCATIONS} criado"

info "Adicionando include ao nginx default..."
if [ -f "$NGINX_CONF" ]; then
  if ! grep -q "${COMPOSE_PROJECT_NAME}-locations.conf" "$NGINX_CONF"; then
    sed -i "/^\s*server_name api\.projetosdinamicos\.com\.br;$/a\    include ${NGINX_LOCATIONS};" "$NGINX_CONF"
    info "Include adicionado ao nginx"
  else
    info "Include ja existe no nginx"
  fi
fi

# Garantir server block para www.crebortoli.com.br
if ! grep -q "server_name www.crebortoli.com.br" "$NGINX_CONF" 2>/dev/null; then
  info "Adicionando server block para www.crebortoli.com.br..."
  cat >> "$NGINX_CONF" <<SERVEOF

# BEGIN crebortoli_site
server {
    listen 80;
    listen [::]:80;
    server_name www.crebortoli.com.br crebortoli.com.br;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
# END crebortoli_site
SERVEOF
  info "Server block adicionado"
fi


# --------------------------------------------------------------
# Docker Compose — build e start
# --------------------------------------------------------------
info "Fazendo build da imagem Docker..."
if $DOCKER_COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" build 2>&1; then
  info "Build concluído com sucesso!"
else
  error "Falha no build da imagem Docker — verifique o Dockerfile e logs acima"
fi

info "Iniciando containers com Docker Compose..."
if $DOCKER_COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" --project-name "$COMPOSE_PROJECT_NAME" up -d 2>&1; then
  info "Containers iniciados!"
else
  error "Falha ao iniciar containers — verifique docker-compose.yml e logs"
fi

info "Aguardando API ficar saudável..."
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$APP_PORT/health" >/dev/null 2>&1; then
    info "API saudável após ${i}s!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    warn "API não respondeu após 30s — verifique logs: $DOCKER_COMPOSE_CMD logs api"
  fi
  sleep 1
done


# --------------------------------------------------------------
# Nginx reload
# --------------------------------------------------------------
info "Testando e recarregando Nginx"
if nginx -t 2>&1; then
  info "Nginx: configuração válida"
  if systemctl reload nginx.service 2>&1; then
    info "Nginx recarregado com sucesso!"
  else
    warn "Erro ao recarregar nginx — execute manualmente: sudo systemctl reload nginx.service"
  fi
else
  warn "Configuração do nginx inválida — execute manualmente: sudo nginx -t"
fi


# --------------------------------------------------------------
# Final
# --------------------------------------------------------------
echo ""
info "===== Instalação concluída! ====="
echo ""
echo "  Domínio: $APP_DOMAIN  |  Location: /crebortoli/  |  Porta: $APP_PORT"
echo "  Docker:  $COMPOSE_PROJECT_NAME"
echo "  .env:    $INSTALL_DIR/.env"
echo ""
echo "  Comandos úteis:"
echo "    Logs:     $DOCKER_COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml logs -f"
echo "    Restart:  $DOCKER_COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml restart"
echo "    Stop:     $DOCKER_COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml down"
echo "    Shell:    $DOCKER_COMPOSE_CMD -f $INSTALL_DIR/docker-compose.yml exec api sh"
echo ""

info "Testando API..." && sleep 2
resp=$(curl -s "http://127.0.0.1:$APP_PORT/health" 2>/dev/null) || resp=""
echo "$resp" | grep -q '"status":"ok"\|"ok"' && info "Local:      ✓ http://127.0.0.1:$APP_PORT/health" || warn "Local:      ✗ $resp"
resp2=$(curl -s "http://127.0.0.1:$APP_PORT/ping" 2>/dev/null) || resp2=""
echo "$resp2" | grep -q '"pong":true' && info "Ping:       ✓ http://127.0.0.1:$APP_PORT/ping" || warn "Ping:       ✗ $resp2"

info "Testando via URL externa (aguardarpropagação DNS)..."
EXT_URL="https://${APP_DOMAIN}/${COMPOSE_PROJECT_NAME}/health"
resp3=$(curl -s --max-time 10 "$EXT_URL" 2>/dev/null) || resp3=""
echo "$resp3" | grep -q '"status":"ok"\|"ok"' && info "Externo:    ✓ $EXT_URL" || warn "Externo:    ✗ $EXT_URL — $resp3"

echo && info "Testes concluídos!"
echo ""
echo "  .env:    $INSTALL_DIR/.env"
echo ""
