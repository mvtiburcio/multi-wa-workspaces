# Visão do Projeto

## Contexto

WASpaces nasceu com uma POC macOS para operar múltiplas sessões com isolamento por workspace. A evolução planejada agora prioriza iOS com experiência nativa completa.

## Direção Atual

- plataforma prioritária: `iPhone-first`;
- experiência principal: UI/UX 100% nativa;
- requisito de tempo real total: backend bridge com worker dedicado por workspace;
- fallback: WebView somente em degradação controlada.

## Problema que estamos resolvendo

Operação de múltiplos workspaces com troca rápida, leitura e envio de mensagens em tempo real, mantendo isolamento entre contas e previsibilidade operacional no mobile.

## Resultado esperado (iOS v1 planejado)

- onboarding por QR por workspace;
- inbox nativa atualizada em tempo real;
- thread nativa com composer e status de envio;
- alternância entre workspaces sem vazamento;
- continuidade em background suportada pelo plano cloud.

## Pré-requisito para iniciar codificação iOS

Antes do desenvolvimento Swift iOS, o projeto exige gate formal de conformidade App Store com decisão de go/no-go registrada.

## Escopo desta rodada

Esta etapa evoluiu para implementação inicial iOS Sprint 1 (`internal-only`) em paralelo ao gate de conformidade.
