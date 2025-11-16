#!/usr/bin/env bash
set -euo pipefail

VAGRANT_USER="vagrant"
VAGRANT_HOME="/home/${VAGRANT_USER}"
BRC="${VAGRANT_HOME}/.bashrc"
BPF="${VAGRANT_HOME}/.profile"
NVM_DIR="${VAGRANT_HOME}/.nvm"

# ----- Hostname setup -----
NEW_HOSTNAME="pfa-devbox"
echo "${NEW_HOSTNAME}" | sudo tee /etc/hostname >/dev/null
sudo hostnamectl set-hostname "${NEW_HOSTNAME}"

# ---------- NVM + Node (as vagrant) ----------
if ! sudo -u "${VAGRANT_USER}" bash -lc 'command -v nvm >/dev/null 2>&1'; then
  sudo -u "${VAGRANT_USER}" bash -lc 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
fi

# Ensure NVM init lines exist in both .bashrc and .profile (APPEND ONLY)
sudo -u "${VAGRANT_USER}" bash -lc "
  grep -qxF 'export NVM_DIR=\"$NVM_DIR\"'    '${BRC}' || {
    echo 'export NVM_DIR=\"$NVM_DIR\"' >> '${BRC}';
    echo '[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"' >> '${BRC}';
  }
  grep -qxF 'export NVM_DIR=\"$NVM_DIR\"'    '${BPF}' || {
    echo 'export NVM_DIR=\"$NVM_DIR\"' >> '${BPF}';
    echo '[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"' >> '${BPF}';
  }
"

# Install Node 24; set default; enable Corepack (APPEND ONLY behavior)
sudo -u "${VAGRANT_USER}" bash -lc "
  export NVM_DIR='${NVM_DIR}';
  [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\";
  nvm install 24 >/dev/null
  nvm alias default 24
  nvm use 24 >/dev/null
  corepack enable >/dev/null 2>&1 || true
"

# ---------- OS packages ----------
export DEBIAN_FRONTEND=noninteractive
if ! dpkg -s postgresql >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y postgresql postgresql-contrib libpq-dev build-essential
fi

# ---------- Postgres: roles & database ----------
# dev role (cluster powers for local dev)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='dev'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE dev LOGIN PASSWORD 'dev' CREATEDB CREATEROLE REPLICATION BYPASSRLS"
fi

# app role
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='pfa'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE pfa LOGIN"
fi

# app database
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='pfa'" | grep -q 1; then
  sudo -u postgres createdb pfa --owner=pfa
fi

# ---------- pg_hba.conf: relax to trust for local (DEV ONLY) ----------
HBA_FILE="$(sudo -u postgres psql -tAc "SHOW hba_file")"
sudo cp --update=none "$HBA_FILE" "$HBA_FILE.bak" || true  # one-time backup

# Only adjust local/loopback auth; leave everything else alone (APPEND-STYLE edits)
sudo sed -i -E 's/^(local[[:space:]]+all[[:space:]]+all[[:space:]]+)(peer|md5|scram-sha-256)/\1trust/' "$HBA_FILE"
sudo sed -i -E 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+127\.0\.0\.1\/32[[:space:]]+)(md5|scram-sha-256)/\1trust/' "$HBA_FILE"
sudo sed -i -E 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+::1\/128[[:space:]]+)(md5|scram-sha-256)/\1trust/' "$HBA_FILE"

sudo systemctl reload postgresql 2>/dev/null || sudo service postgresql reload

# ---------- DB ownership & sane defaults (APPEND ONLY) ----------
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
-- No-op if already owner
ALTER DATABASE pfa OWNER TO pfa;

-- Sensible DB/session defaults
ALTER DATABASE pfa SET client_encoding = 'UTF8';
ALTER DATABASE pfa SET timezone = 'UTC';

-- Predictable search_path for the app role
ALTER ROLE pfa SET search_path TO public, pg_catalog;
SQL

# ---------- Grants with full coverage (minus TYPES) (APPEND ONLY) ----------
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
\connect pfa

-- Base access
GRANT CONNECT, TEMP ON DATABASE pfa TO pfa;
GRANT USAGE, CREATE ON SCHEMA public TO pfa;

-- Existing objects in public
GRANT ALL PRIVILEGES ON ALL TABLES                 IN SCHEMA public TO pfa;
GRANT ALL PRIVILEGES ON ALL SEQUENCES              IN SCHEMA public TO pfa;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS              IN SCHEMA public TO pfa;

-- Future objects (default privileges)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES                TO pfa;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES             TO pfa;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS             TO pfa;
SQL

# ---------- Developer env vars for the vagrant user (APPEND ONLY) ----------
sudo -u "${VAGRANT_USER}" bash -lc "
  grep -qxF 'export PGDATABASE=pfa' '${BRC}' || echo 'export PGDATABASE=pfa' >> '${BRC}';
  grep -qxF 'export PGUSER=pfa'     '${BRC}' || echo 'export PGUSER=pfa'     >> '${BRC}';
"

# ---------- SSH keys from /vagrant/keys (if present) ----------
KEYS_SRC="/vagrant/keys"
SSH_DIR="${VAGRANT_HOME}/.ssh"

if [ -d "${KEYS_SRC}" ]; then
  KEYS_INSTALLED=1
  sudo -u "${VAGRANT_USER}" mkdir -p "${SSH_DIR}"
  sudo cp "${KEYS_SRC}"/* "${SSH_DIR}/" 2>/dev/null || true
  sudo chown -R "${VAGRANT_USER}:${VAGRANT_USER}" "${SSH_DIR}"
  sudo chmod 700 "${SSH_DIR}"
  sudo chmod 600 "${SSH_DIR}"/* 2>/dev/null || true
fi

# ---------- Clone product-feedback-app-2 repo ----------
REPO_DIR="${VAGRANT_HOME}/code"

if [ ! -d "${REPO_DIR}" ]; then
  if [ "${KEYS_INSTALLED}" -eq 1 ]; then
    # SSH clone (keys available)
    sudo -u "${VAGRANT_USER}" bash -lc "
      export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new';
      git -C '${VAGRANT_HOME}' clone git@github.com:MadOgre/product-feedback-app-2.git code
    "
  else
    # HTTPS clone (no keys installed)
    sudo -u "${VAGRANT_USER}" git -C "${VAGRANT_HOME}" clone https://github.com/MadOgre/product-feedback-app-2.git code
  fi
fi

# ---------- Run pnpm install in repo ----------
sudo -u "${VAGRANT_USER}" bash -lc "
  export NVM_DIR='${NVM_DIR}';
  [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\";
  nvm use 24 >/dev/null;
  cd '${REPO_DIR}' && pnpm install
"
