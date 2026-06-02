#!/bin/sh
set -eu

# ==============================================================
# Script de instalação — ERP Fiscal
# Uso: sudo bash install.sh          (instalar)
#       sudo bash install.sh uninstall (desinstalar)
#
# Plataforma de Gestão ERP com Calculadora Tributária CBS/IBS
# ==============================================================

INSTALL_DIR="/var/www/erpfiscal"
SRC_DIR="$INSTALL_DIR/src"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_CONF="$NGINX_AVAILABLE/default"
BACKUP_ROOT="/var/backups/erpfiscal"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install.sh"

if [ -n "${SUDO_USER:-}" ]; then
  PM2_USER="$SUDO_USER"
else
  PM2_USER="root"
fi
PM2_AS_USER=""
[ "$PM2_USER" != "root" ] && PM2_AS_USER="sudo -u $PM2_USER"

# ==============================================================
# Uninstall
# ==============================================================
uninstall_app() {
  [ -f "$INSTALL_DIR/.env" ] || error ".env não encontrado em $INSTALL_DIR"

  local udb_host udb_port udb_name udb_user udb_pass upm2 unginx_bkp
  upm2="erpfiscal"

  udb_host=$(grep -oP '^DB_HOST=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "localhost")
  udb_port=$(grep -oP '^DB_PORT=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "5432")
  udb_name=$(grep -oP '^DB_NAME=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "")
  udb_user=$(grep -oP '^DB_USER=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "")
  udb_pass=$(grep -oP '^PASSWORD=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "")
  grep -oP '^PM2_APP_NAME=\K.*' "$INSTALL_DIR/.env" 2>/dev/null && upm2=$(grep -oP '^PM2_APP_NAME=\K.*' "$INSTALL_DIR/.env") || true
  unginx_bkp=$(grep -oP '^NGINX_BKP=\K.*' "$INSTALL_DIR/.env" 2>/dev/null || echo "")

  info "Parando PM2 ($upm2)"
  $PM2_AS_USER pm2 delete "$upm2" 2>/dev/null || true
  $PM2_AS_USER pm2 save --force 2>/dev/null || true

  if [ -n "$unginx_bkp" ] && [ -f "$unginx_bkp" ]; then
    info "Restaurando nginx de $unginx_bkp"
    cp "$unginx_bkp" "$NGINX_CONF"
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  else
    warn "Backup nginx não encontrado — removendo bloco # BEGIN $upm2"
    cp "$NGINX_CONF" "$NGINX_CONF.bkp.$(date +%Y%m%d_%H%M%S)"
    sed -i "/^# BEGIN $upm2\$/,/^# END $upm2\$/d" "$NGINX_CONF" 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  fi

  if [ -n "$udb_name" ] && [ -n "$udb_user" ]; then
    info "Removendo banco $udb_name..."
    export PGPASSWORD="$udb_pass"
    TABLES=$(psql -h "$udb_host" -p "$udb_port" -U "$udb_user" -d "$udb_name" -t -c "SELECT tablename FROM pg_tables WHERE schemaname='public';" 2>/dev/null) || true
    for tbl in $TABLES; do
      psql -h "$udb_host" -p "$udb_port" -U "$udb_user" -d "$udb_name" -c "DROP TABLE IF EXISTS \"$tbl\" CASCADE;" 2>/dev/null || true
    done
    unset PGPASSWORD
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$udb_name\";" 2>/dev/null || true
    info "Banco $udb_name removido"
  fi

  info "Removendo $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"

  info "Desinstalação concluída!"
}

case "${1:-}" in
  uninstall) uninstall_app; exit 0 ;;
esac

# ==============================================================
# Rollback automático
# ==============================================================
ROLLBACK_DIR=""
cleanup_on_error() {
  local rc=$?
  [ $rc -eq 0 ] && return 0
  warn "ERRO: Instalação falhou (código $rc) — revertendo..."
  if [ -n "$ROLLBACK_DIR" ] && [ -d "$ROLLBACK_DIR" ]; then
    info "Restaurando backup de $ROLLBACK_DIR"
    rm -rf "$SRC_DIR" 2>/dev/null || true
    [ -f "$ROLLBACK_DIR/env.bkp" ] && cp "$ROLLBACK_DIR/env.bkp" "$INSTALL_DIR/.env" 2>/dev/null || true
    [ -f "$ROLLBACK_DIR/package.json.bkp" ] && cp "$ROLLBACK_DIR/package.json.bkp" "$INSTALL_DIR/package.json" 2>/dev/null || true
    [ -f "$ROLLBACK_DIR/nginx_default.bkp" ] && cp "$ROLLBACK_DIR/nginx_default.bkp" "$NGINX_CONF" 2>/dev/null || true
    info "Rollback concluído."
  else
    warn "Nenhum backup — removendo artefatos..."
    $PM2_AS_USER pm2 delete "$PM2_APP_NAME" 2>/dev/null || true
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
  fi
  exit $rc
}
trap 'cleanup_on_error' EXIT
trap 'error "Instalação interrompida"' INT TERM

if [ -d "$INSTALL_DIR" ] || [ -f "$NGINX_CONF" ]; then
  ROLLBACK_DIR="$BACKUP_ROOT/preinstall_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$ROLLBACK_DIR"
  info "Backup pré-instalação em $ROLLBACK_DIR"
  [ -f "$INSTALL_DIR/.env" ] && cp "$INSTALL_DIR/.env" "$ROLLBACK_DIR/env.bkp" 2>/dev/null || true
  [ -f "$INSTALL_DIR/package.json" ] && cp "$INSTALL_DIR/package.json" "$ROLLBACK_DIR/package.json.bkp" 2>/dev/null || true
  [ -d "$SRC_DIR" ] && cp -r "$SRC_DIR" "$ROLLBACK_DIR/src.bkp" 2>/dev/null || true
  [ -f "$NGINX_CONF" ] && cp "$NGINX_CONF" "$ROLLBACK_DIR/nginx_default.bkp" 2>/dev/null || true
fi

command -v node >/dev/null 2>&1 || error "Node.js não encontrado"
command -v npm  >/dev/null 2>&1 || error "npm não encontrado"
command -v psql >/dev/null 2>&1 || warn "psql não encontrado"

mkdir -p "$SRC_DIR" "$INSTALL_DIR/backups"

echo ""
echo "============================================"
echo "  Configuração ERP Fiscal"
echo "============================================"
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
  printf "Porta do app [3003]: "; read -r APP_PORT
  APP_PORT=${APP_PORT:-3003}
  if _check_port "$APP_PORT"; then
    warn "Porta $APP_PORT já está em uso!"
    printf "  (M)atar, (T)rocar, (C)ancelar [M/t/c]: "; read -r PORT_ACT
    case "$PORT_ACT" in
      [Tt]) continue ;;
      [Cc]) error "Cancelado" ;;
      *) fuser -k "$APP_PORT/tcp" 2>/dev/null; sleep 1 ;;
    esac
  fi
  break
done

printf "Nome do banco PostgreSQL [erpfiscal_db]: "; read -r DB_NAME
DB_NAME=${DB_NAME:-erpfiscal_db}
printf "Nome do app no PM2 [erpfiscal]: "; read -r PM2_APP_NAME
PM2_APP_NAME=${PM2_APP_NAME:-erpfiscal}
printf "Email do admin: "; read -r ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@erpfiscal.com.br}
printf "Nome do admin [$ADMIN_EMAIL]: "; read -r ADMIN_NOME
ADMIN_NOME=${ADMIN_NOME:-$ADMIN_EMAIL}
printf "Senha do admin [@admin123]: "; stty -echo; read -r ADMIN_PASS; stty echo; echo ""
ADMIN_PASS=${ADMIN_PASS:-@admin123}
DB_USER=postgres
DB_PASS=wander
DB_HOST=localhost
DB_PORT=5432
APP_DOMAIN=api.projetosdinamicos.com.br
APP_LOCATION=/$PM2_APP_NAME/

# .env
info "Criando .env"
cat > "$INSTALL_DIR/.env" <<ENVEOF
PORT=$APP_PORT
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
PM2_APP_NAME=$PM2_APP_NAME
APP_DOMAIN=$APP_DOMAIN
APP_LOCATION=$APP_LOCATION
NGINX_BKP=
PASSWORD=$DB_PASS
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_NOME=$ADMIN_NOME
ADMIN_PASS=$ADMIN_PASS
ENVEOF
chmod 600 "$INSTALL_DIR/.env"
chown "$PM2_USER" "$INSTALL_DIR/.env"

# package.json
info "Criando package.json"
cat > "$INSTALL_DIR/package.json" <<'JSONEOF'
{
  "name": "erpfiscal-api",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js"
  },
  "dependencies": {
    "dotenv": "^16.4.5",
    "express": "^4.21.0",
    "pg": "^8.12.0"
  }
}
JSONEOF

# src/server.js — API do ERP com calculadora tributária
info "Criando src/server.js"
cat > "$SRC_DIR/server.js" <<'SVREOF'
const { Pool } = require('pg');
const express = require('express');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const app = express();
const PORT = process.env.PORT || 3000;

const pool = new Pool({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.PASSWORD
});

pool.on('error', (err) => console.error('DB Error:', err));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

app.use((req, res, next) => {
    const origin = req.headers.origin;
    const allowedOrigins = [
        'https://www.projetosdinamicos.com.br',
        'https://api.projetosdinamicos.com.br',
        'https://erp.projetosdinamicos.com.br'
    ];
    if (origin) {
        const match = allowedOrigins.find(o => origin === o || origin.endsWith('://' + o.split('://')[1]));
        if (match) res.header('Access-Control-Allow-Origin', match);
    }
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (req.method === 'OPTIONS') return res.sendStatus(200);
    next();
});

// Health
app.get('/', (req, res) => {
    res.json({ message: 'ERP Fiscal API', status: 'OK', version: '1.0.0' });
});

app.get('/health', async (req, res) => {
    try {
        await pool.query('SELECT 1');
        res.json({ status: 'healthy', database: 'connected' });
    } catch (err) {
        res.json({ status: 'unhealthy', database: 'disconnected', error: err.message });
    }
});

// Auth
app.post('/auth/login', async (req, res) => {
    const { nome, email, senha } = req.body;
    if ((!nome && !email) || !senha) {
        return res.status(400).json({ error: 'Nome ou email e senha obrigatórios' });
    }
    try {
        let result;
        if (nome) {
            result = await pool.query('SELECT id, nome, email, tipo FROM usuarios WHERE nome = $1 AND senha = $2', [nome, senha]);
        } else {
            result = await pool.query('SELECT id, nome, email, tipo FROM usuarios WHERE email = $1 AND senha = $2', [email, senha]);
        }
        if (result.rows.length === 0) return res.status(401).json({ error: 'Credenciais inválidas' });
        const usuario = result.rows[0];
        const token = crypto.createHash('sha256').update(usuario.email + Date.now() + 'erpfiscal_secret').digest('hex');
        res.json({ success: true, token, usuario });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Settings
app.get('/settings', async (req, res) => {
    try {
        const result = await pool.query('SELECT chave, valor FROM settings');
        const settings = {};
        result.rows.forEach(r => { settings[r.chave] = r.valor; });
        res.json(settings);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/settings', async (req, res) => {
    const pairs = req.body;
    try {
        for (const chave of Object.keys(pairs)) {
            await pool.query('INSERT INTO settings (chave, valor) VALUES ($1, $2) ON CONFLICT (chave) DO UPDATE SET valor = $2', [chave, pairs[chave]]);
        }
        res.json({ success: true });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ===================== CALCULADORA TRIBUTÁRIA =====================
// Diferencial da plataforma: calcula CBS + IBS (IVA Dual - EC 132/2023)
app.post('/calculadora/tributos', async (req, res) => {
    try {
        const { cnpj_emitente, uf_destino, municipio_destino, regime_tributario, itens } = req.body;

        if (!cnpj_emitente || !uf_destino || !itens || !Array.isArray(itens) || itens.length === 0) {
            return res.status(400).json({ error: 'Dados obrigatórios: cnpj_emitente, uf_destino, itens' });
        }

        // Calcular base (soma valor_unitario * quantidade)
        let base_calculo = 0;
        itens.forEach(item => {
            base_calculo += (parseFloat(item.valor_unitario) || 0) * (parseInt(item.quantidade) || 1);
        });

        // PIS: 1.65%, COFINS: 7.6% (regime cumulativo - Lucro Presumido)
        let pis_aliquota = 0.0165;
        let cofins_aliquota = 0.076;

        // Simples Nacional tem aliquotas menores
        if (regime_tributario === 'Simples Nacional') {
            pis_aliquota = 0.0;
            cofins_aliquota = 0.0;
        } else if (regime_tributario === 'MEI') {
            pis_aliquota = 0.0;
            cofins_aliquota = 0.0;
        }

        // CBS/IBS: EC 132/2023 - alíquotas experimentais de transição
        const cbs_aliquota = 0.009;  // 0.9%
        const ibs_aliquota = 0.001;  // 0.1%

        // IBS pode variar por UF (estados podem ter alíquotas diferentes)
        let ibs_ajustada = ibs_aliquota;
        const uf_aliquotas = {
            'SP': 0.0012, 'RJ': 0.0011, 'MG': 0.0010,
            'RS': 0.0009, 'SC': 0.0009, 'PR': 0.0009
        };
        if (uf_aliquotas[uf_destino]) {
            ibs_ajustada = uf_aliquotas[uf_destino];
        }

        const pis_valor = Math.round(base_calculo * pis_aliquota * 100) / 100;
        const cofins_valor = Math.round(base_calculo * cofins_aliquota * 100) / 100;
        const cbs_valor = Math.round(base_calculo * cbs_aliquota * 100) / 100;
        const ibs_valor = Math.round(base_calculo * ibs_ajustada * 100) / 100;

        // Salvar log do cálculo
        try {
            await pool.query(
                `INSERT INTO calculos_tributos (cnpj_emitente, uf_destino, municipio_destino, regime_tributario, base_calculo, pis_valor, cofins_valor, cbs_aliquota, cbs_valor, ibs_aliquota, ibs_valor) 
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
                [cnpj_emitente, uf_destino, municipio_destino, regime_tributario, base_calculo, pis_valor, cofins_valor, cbs_aliquota, cbs_valor, ibs_ajustada, ibs_valor]
            );
        } catch (e) { /* log não crítico */ }

        const response = {
            status: 'sucesso',
            base_calculo: base_calculo,
            tributos_antigos: {
                pis: pis_valor,
                cofins: cofins_valor
            },
            tributos_novos_2026: {
                cbs_aliquota: cbs_aliquota,
                cbs_valor: cbs_valor,
                ibs_aliquota: ibs_ajustada,
                ibs_valor: ibs_valor
            },
            texto_legal_obrigatorio: `Operação com incidência experimental de CBS (${(cbs_aliquota * 100).toFixed(1)}%) e IBS (${(ibs_ajustada * 100).toFixed(1)}%) conforme EC 132/2023.`
        };

        res.json(response);
    } catch (err) {
        res.status(500).json({ status: 'erro', error: err.message });
    }
});

// ===================== CRUD GENÉRICO =====================
const TABELAS = [
    'clientes', 'fornecedores', 'produtos', 'vendas', 'nfe', 'calculos_tributos'
];

app.get('/:tabela', async (req, res) => {
    const { tabela } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error: 'Tabela não encontrada' });
    try {
        const result = await pool.query(`SELECT * FROM "${tabela}" ORDER BY id DESC LIMIT 500`);
        res.json(result.rows);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/:tabela', async (req, res) => {
    const { tabela } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error: 'Tabela não encontrada' });
    const data = req.body;
    try {
        const keys = Object.keys(data).map(k => `"${k}"`).join(', ');
        const values = Object.keys(data).map((_, i) => `$${i + 1}`).join(', ');
        const result = await pool.query(`INSERT INTO "${tabela}" (${keys}) VALUES (${values}) RETURNING *;`, Object.values(data));
        res.json(result.rows[0]);
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.put('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error: 'Tabela não encontrada' });
    const data = req.body;
    try {
        const keys = Object.keys(data).map((k, i) => `"${k}" = $${i + 1}`).join(', ');
        const result = await pool.query(`UPDATE "${tabela}" SET ${keys} WHERE id = $${Object.keys(data).length + 1} RETURNING *;`, [...Object.values(data), id]);
        res.json(result.rows[0] || { error: 'Registro não encontrado' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

app.delete('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!TABELAS.includes(tabela)) return res.status(404).json({ error: 'Tabela não encontrada' });
    try {
        await pool.query(`DELETE FROM "${tabela}" WHERE id = $1`, [id]);
        res.json({ success: true, message: 'Registro excluído' });
    } catch (err) { res.status(500).json({ error: err.message }); }
});

// ===================== START =====================
app.listen(PORT, () => {
    console.log(`ERP Fiscal API running on port ${PORT}`);
});
SVREOF
sed -i "s/process\.env\.PORT || 3000/process.env.PORT || $APP_PORT/" "$SRC_DIR/server.js"

# ==============================================================
# Nginx
# ==============================================================
info "Configurando Nginx"
if [ ! -f "$NGINX_CONF" ]; then
  echo "# Nginx default" > "$NGINX_CONF"
fi

if grep -q "^# BEGIN $PM2_APP_NAME\$" "$NGINX_CONF"; then
  warn "Bloco já existe — pulando"
else
  NGINX_BKP_VAL="$NGINX_CONF.bkp.$(date +%Y%m%d_%H%M%S)"
  cp "$NGINX_CONF" "$NGINX_BKP_VAL"
  sed -i "s|^NGINX_BKP=.*|NGINX_BKP=$NGINX_BKP_VAL|" "$INSTALL_DIR/.env"

  SSL_DIR="/etc/letsencrypt/live"
  SSL_CERT=""; SSL_KEY=""
  for d in "$SSL_DIR"/*/; do
    [ -f "${d}fullchain.pem" ] || continue
    if echo "$d" | grep -qi "$(echo "$APP_DOMAIN" | sed 's/^www\.//')"; then
      SSL_CERT="${d}fullchain.pem"; SSL_KEY="${d}privkey.pem"; break
    fi
  done
  if [ -z "$SSL_CERT" ]; then
    for d in "$SSL_DIR"/*/; do
      [ -f "${d}fullchain.pem" ] || continue
      SSL_CERT="${d}fullchain.pem"; SSL_KEY="${d}privkey.pem"; break
    done
  fi
  PROXY_TRAIL="/"
  [ "$APP_LOCATION" = "/" ] && PROXY_TRAIL=""

  cat >> "$NGINX_CONF" <<NGINXEOF

# BEGIN $PM2_APP_NAME
server {
    listen 80;
    listen [::]:80;
    server_name $APP_DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www; }
    location $APP_LOCATION { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl; listen [::]:443 ssl; http2 on;
    server_name $APP_DOMAIN;
NGINXEOF

  if [ -n "$SSL_CERT" ]; then
    cat >> "$NGINX_CONF" <<NGINXEOF
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
NGINXEOF
  fi

  cat >> "$NGINX_CONF" <<NGINXEOF
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;
    location /.well-known/acme-challenge/ { root /var/www; }
    location $APP_LOCATION {
        proxy_pass http://127.0.0.1:$APP_PORT$PROXY_TRAIL;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    client_max_body_size 15M;
}
# END $PM2_APP_NAME
NGINXEOF
  info "Server block inserido"
fi

# ==============================================================
# PostgreSQL
# ==============================================================
info "Criando banco PostgreSQL"
if command -v sudo >/dev/null 2>&1 && sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
  if [ "$DB_USER" != "postgres" ]; then
    if [ -n "$DB_PASS" ]; then
      sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>/dev/null || true
    else
      sudo -u postgres psql -c "CREATE USER $DB_USER;" 2>/dev/null || true
    fi
  fi
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || warn "Banco $DB_NAME já existe"
  info "Banco criado"
else
  warn "Crie manualmente: sudo -u postgres createdb $DB_NAME -O $DB_USER"
fi

# ==============================================================
# Migration
# ==============================================================
info "Executando migration..."
MIGRATION_FILE="$INSTALL_DIR/migrations/001_create_tables.sql"
mkdir -p "$INSTALL_DIR/migrations"

cat > "$MIGRATION_FILE" <<SQLEOF
-- ============================================================
-- Migration 001: ERP Fiscal — Reforma Tributária CBS/IBS
-- ============================================================

CREATE TABLE IF NOT EXISTS settings (
    chave VARCHAR(100) PRIMARY KEY,
    valor TEXT
);

CREATE TABLE IF NOT EXISTS clientes (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    fantasia VARCHAR(255),
    documento VARCHAR(20),
    ie VARCHAR(50),
    email VARCHAR(255),
    telefone VARCHAR(50),
    cep VARCHAR(10),
    endereco TEXT,
    bairro VARCHAR(100),
    cidade VARCHAR(100),
    uf VARCHAR(2),
    regime_tributario VARCHAR(50) DEFAULT 'Lucro Presumido',
    status VARCHAR(20) DEFAULT 'Ativo',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fornecedores (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    fantasia VARCHAR(255),
    documento VARCHAR(20),
    ie VARCHAR(50),
    contato VARCHAR(255),
    telefone VARCHAR(50),
    email VARCHAR(255),
    cep VARCHAR(10),
    cidade VARCHAR(100),
    uf VARCHAR(2),
    status VARCHAR(20) DEFAULT 'Ativo',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS produtos (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(50) NOT NULL,
    descricao VARCHAR(255) NOT NULL,
    ncm VARCHAR(20),
    preco DECIMAL(10,2) DEFAULT 0,
    estoque INTEGER DEFAULT 0,
    categoria VARCHAR(50),
    unidade VARCHAR(10) DEFAULT 'UN',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS vendas (
    id SERIAL PRIMARY KEY,
    cliente_id INTEGER REFERENCES clientes(id),
    cliente_nome VARCHAR(255),
    descricao TEXT,
    valor DECIMAL(10,2) DEFAULT 0,
    cbs_valor DECIMAL(10,2) DEFAULT 0,
    ibs_valor DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'Concluída',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nfe (
    id SERIAL PRIMARY KEY,
    numero VARCHAR(20) NOT NULL,
    serie VARCHAR(10) DEFAULT '1',
    chave_acesso VARCHAR(44),
    cliente_id INTEGER REFERENCES clientes(id),
    cliente_nome VARCHAR(255),
    valor_total DECIMAL(10,2) DEFAULT 0,
    cbs_aliquota DECIMAL(5,4) DEFAULT 0.009,
    cbs_valor DECIMAL(10,2) DEFAULT 0,
    ibs_aliquota DECIMAL(5,4) DEFAULT 0.001,
    ibs_valor DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'Pendente',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS calculos_tributos (
    id SERIAL PRIMARY KEY,
    cnpj_emitente VARCHAR(20),
    uf_destino VARCHAR(2),
    municipio_destino VARCHAR(20),
    regime_tributario VARCHAR(50),
    base_calculo DECIMAL(10,2),
    pis_valor DECIMAL(10,2) DEFAULT 0,
    cofins_valor DECIMAL(10,2) DEFAULT 0,
    cbs_aliquota DECIMAL(5,4) DEFAULT 0.009,
    cbs_valor DECIMAL(10,2) DEFAULT 0,
    ibs_aliquota DECIMAL(5,4) DEFAULT 0.001,
    ibs_valor DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS usuarios (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    senha VARCHAR(255) NOT NULL,
    tipo VARCHAR(50) DEFAULT 'admin',
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO settings (chave, valor) VALUES
    ('versao_plataforma', '1.0.0'),
    ('cbs_aliquota', '0.009'),
    ('ibs_aliquota', '0.001')
ON CONFLICT (chave) DO NOTHING;

INSERT INTO usuarios (nome, email, senha, tipo)
VALUES ('${ADMIN_NOME}', '${ADMIN_EMAIL}', '${ADMIN_PASS}', 'admin')
ON CONFLICT (email) DO NOTHING;
SQLEOF

if command -v sudo >/dev/null 2>&1 && sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
  PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$MIGRATION_FILE" 2>/dev/null && \
    info "Migration executada!" || warn "Erro na migration — execute manualmente"
else
  warn "Migration não executada. Execute: psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f $MIGRATION_FILE"
fi

# ==============================================================
# Dependências
# ==============================================================
info "Instalando dependências"
npm install --prefix "$INSTALL_DIR" --production

# ==============================================================
# PM2
# ==============================================================
info "Registrando no PM2"
$PM2_AS_USER pm2 delete "$PM2_APP_NAME" 2>/dev/null || true
$PM2_AS_USER pm2 start "$INSTALL_DIR/src/server.js" --name "$PM2_APP_NAME"
$PM2_AS_USER pm2 save --force

# ==============================================================
# Nginx reload
# ==============================================================
info "Recarregando Nginx"
nginx -t && systemctl reload nginx && info "Nginx OK" || warn "Falha nginx"

echo ""
info "==========================================="
info " Instalação ERP Fiscal concluída!"
info "==========================================="
echo ""
echo "  Domínio:   $APP_DOMAIN"
echo "  Location:  $APP_LOCATION"
echo "  Porta:     $APP_PORT"
echo "  PM2:       $PM2_APP_NAME"
echo ""
echo "  Endpoints:"
echo "    GET  ${APP_LOCATION}"
echo "    GET  ${APP_LOCATION}health"
echo "    POST ${APP_LOCATION}auth/login"
echo "    POST ${APP_LOCATION}calculadora/tributos   ← DIFERENCIAL"
echo ""
echo "  Admin: $ADMIN_EMAIL / $ADMIN_PASS"
echo ""

info "Testando API..."
sleep 2
BASE="http://127.0.0.1:$APP_PORT/"
curl -s "${BASE}health" 2>/dev/null | grep -q '"healthy"' && info "Health: ✓" || warn "Health: ✗"
curl -s "${BASE}" 2>/dev/null | grep -q '"OK"' && info "Root: ✓" || warn "Root: ✗"

# Test calculadora
CALC_TEST=$(curl -s -X POST "${BASE}calculadora/tributos" \
  -H "Content-Type: application/json" \
  -d '{"cnpj_emitente":"12.345.678/0001-99","uf_destino":"SP","municipio_destino":"3550308","regime_tributario":"Lucro Presumido","itens":[{"codigo_produto":"1020","ncm":"8471.30.12","valor_unitario":1000,"quantidade":1}]}' 2>/dev/null)
if echo "$CALC_TEST" | grep -q '"sucesso"'; then
  info "Calculadora: ✓"
else
  warn "Calculadora: ✗ $CALC_TEST"
fi

info "Testes concluídos!"
