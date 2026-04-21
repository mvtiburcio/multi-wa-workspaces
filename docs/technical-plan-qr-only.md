# Plano Técnico QR-only

## Premissa
Modelo sem API oficial, focado em sessões Web isoladas.

## Pilar técnico
- `WKWebView` por workspace ativo;
- `WKWebsiteDataStore` persistente por workspace (`UUID`);
- metadados locais para nome, estado e `dataStoreID`.

## Fluxo principal
1. Criar workspace.
2. Alocar data store próprio.
3. Abrir `web.whatsapp.com`.
4. Escanear QR.
5. Persistir sessão localmente.

## Exclusão de workspace
- encerrar webview;
- remover data store;
- apagar metadados locais.

## Status de implementação (v1 - 21/04/2026)
- [x] shell nativo macOS em SwiftUI;
- [x] `WorkspaceManager` com criação/seleção/renomeação/remoção;
- [x] `WebSessionEngine` com `WebViewPool` (até 2 webviews aquecidas);
- [x] persistência com SwiftData (`id`, `name`, `colorTag`, `dataStoreID`, `state`, `createdAt`, `lastOpenedAt`);
- [x] logs estruturados em `os.Logger` com `workspace_id`, `event`, `duration_ms`, `result`;
- [x] testes e CI para build/test em macOS.

## Limites
- sem contrato oficial de dados para UI nativa completa;
- dependência de mudanças no frontend web do provedor;
- limitações de background no iOS.
