# PRD — iOS Native UI (WASpaces)

## 1. Objetivo de Produto

Entregar um app iOS (`iPhone-first`) com experiência nativa completa para operar múltiplos workspaces, com leitura e envio de mensagens em tempo real, sem depender da UI do WhatsApp Web como experiência principal.

## 2. Problema

Usuários operacionais precisam de:

- múltiplas sessões isoladas por workspace;
- troca rápida entre contextos;
- continuidade de atualização em background;
- feedback confiável de envio e estado de conversa.

## 3. Escopo Funcional v1

- onboarding por QR e ativação de workspace;
- inbox nativa com atualização em tempo real;
- thread nativa com histórico e composer;
- envio de mensagem textual com estado de entrega;
- alternância entre workspaces sem vazamento;
- fallback híbrido para WebView em degradação controlada.

## 4. Jornada Ponta a Ponta

1. Usuário abre app e seleciona/cria workspace.
2. Faz onboarding por QR.
3. Recebe snapshot inicial da inbox e começa sync incremental.
4. Abre thread, lê histórico e envia mensagem.
5. Recebe atualização de status (`sent`, `delivered`, `read`).
6. Alterna workspace e repete fluxo sem mistura de conta.

## 5. Regras de Navegação e Estado

- navegação primária: `Workspaces -> Inbox -> Thread`;
- estado por workspace isolado no cliente;
- troca de workspace preserva contexto anterior em cache;
- erro transitório mostra estado degradado e opção de retentativa;
- fallback WebView só ativa sob política de `FallbackRenderState`.

## 6. Requisitos de UX Nativa

- visual iOS nativo, sem espelhamento da interface web;
- feedback claro para estados: conectando, conectado, degradado, desconectado;
- badges de unread consistentes em lista de workspaces e inbox;
- transições rápidas na alternância de workspace.

## 7. Requisitos de Acessibilidade

- suporte a Dynamic Type;
- contraste adequado e sem dependência exclusiva de cor;
- labels acessíveis para elementos críticos (workspace, unread, status de envio);
- fluxo navegável com VoiceOver nas jornadas principais.

## 8. Requisitos Operacionais

- observabilidade por workspace (latência, erro, fallback);
- logs estruturados para incidentes;
- capacidade de reprocessar sync e comandos com segurança;
- push pipeline para notificações por workspace.

## 9. Dependências Críticas

- gate de conformidade App Store aprovado;
- Session Bridge Cloud disponível com worker por workspace;
- contratos de dados versionados e estáveis para app.

## 10. Não Objetivos v1

- redesign para iPad/macOS nesta rodada;
- suporte a recursos avançados fora do escopo de chat base;
- operação local-only para tempo real contínuo.
