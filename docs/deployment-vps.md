# Deploy VPS — Session Bridge (Docker + Caddy)

## Escopo

Este guia sobe a Session Bridge em VPS Linux com TLS automático e domínio via Caddy.

## Pré-requisitos

- domínio apontando para o IP da VPS (`A` record);
- portas `80` e `443` liberadas;
- Docker Engine e Docker Compose plugin instalados na VPS.

## Estrutura usada

- `deploy/bridge/Dockerfile`
- `deploy/bridge/docker-compose.yml`
- `deploy/bridge/Caddyfile`
- `deploy/bridge/.env` (copiar de `.env.example`)

## Passo a passo

1. Copiar o projeto para a VPS.
2. Entrar em `deploy/bridge`.
3. Criar `.env` com token forte.
4. Subir stack com compose.

Exemplo:

```bash
cd /opt
git clone <repo-url> multi-wa-workspaces
cd multi-wa-workspaces/deploy/bridge
cp .env.example .env
# editar .env com token real
docker compose up -d --build
```

## Opção com CloudPanel/Nginx existente (sem Caddy)

Quando a VPS já usa porta `80/443` (ex.: CloudPanel), use:

```bash
cd /opt/multi-wa-workspaces/deploy/bridge
cp .env.example .env
# editar token
docker compose -f docker-compose.cloudpanel.yml up -d --build
```

Nesse modo, a bridge fica em `127.0.0.1:18080` e o domínio deve ser publicado por reverse proxy no CloudPanel.

## Endpoints de validação

- `GET https://<dominio>/healthz` (sem token)
- `GET https://<dominio>/readyz` (sem token)
- `GET https://<dominio>/v1/workspaces` (com `Authorization: Bearer <token>`)

## Variáveis de ambiente críticas

- `DOMAIN`: domínio público do serviço.
- `WASPACES_BRIDGE_API_TOKEN`: token Bearer obrigatório para APIs `/v1/*`.
- `WASPACES_BRIDGE_SEED_MODE`: use `none` em produção para evitar dados de seed.
- `WASPACES_BRIDGE_WAHA_ENABLED`: `1` para habilitar provider real de sessão WhatsApp.
- `WASPACES_WAHA_BASE_URL`: URL do serviço WAHA (ex.: `http://127.0.0.1:3000`).
- `WASPACES_WAHA_API_KEY`: chave de API do WAHA (quando habilitado).
- `WASPACES_WAHA_SESSION_PREFIX`: prefixo de sessão por workspace (padrão `ws`).
- `WASPACES_WAHA_FORCE_DEFAULT_SESSION`: `1` para usar sessão única `default` (necessário em WAHA Core).

## Observações

- a base SQLite persiste em volume Docker (`bridge_data`);
- este deploy cobre bridge MVP em produção interna;
- com WAHA habilitado, QR/sync/send passam a operar com sessão real por workspace;
- em WAHA Core, múltiplas sessões independentes não são suportadas; para multi-workspace real use WAHA Plus ou configure `WASPACES_WAHA_FORCE_DEFAULT_SESSION=1` (sessão única compartilhada).
- APNs real ainda segue como próxima etapa.
