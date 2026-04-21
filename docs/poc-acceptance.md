# Critérios de Aceite da POC (macOS)

## Objetivo
Validar isolamento de sessões por workspace com QR-only em app nativo macOS.

## Cenários automatizados
- criação gera `dataStoreID` único;
- seleção de workspace não substitui sessão dos demais;
- remoção limpa metadado e sessão associada;
- renomeação altera somente o workspace alvo;
- criação de 3 workspaces com sessões independentes;
- reinício preserva associação `workspaceID -> dataStoreID`.

## Cenários manuais obrigatórios
1. Criar workspaces `A`, `B` e `C`.
2. Logar apenas no `A` via QR e confirmar que `B` e `C` continuam pedindo QR.
3. Alternar repetidamente entre `A`, `B` e `C`.
4. Remover `A`.
5. Confirmar que `A` não aparece mais na lista e que `B` e `C` continuam ativos.
6. Recriar `A` e confirmar exigência de novo QR (sem sessão anterior).

## Evidência mínima
- saída verde de `swift test`;
- registro de eventos com campos `workspace_id`, `event`, `duration_ms`, `result`.
