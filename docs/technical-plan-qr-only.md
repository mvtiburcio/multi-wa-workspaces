# Plano Técnico QR-only

## Premissa
Modelo sem API oficial, focado em sessões Web isoladas.

## Pilar técnico
- `WKWebView` por workspace ativo;
- `WKWebsiteDataStore` persistente por workspace (`UUID`);
- metadados locais para nome, estado e dataStoreID.

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

## Limites
- sem contrato oficial de dados para UI nativa completa;
- dependência de mudanças no frontend web do provedor;
- limitações de background no iOS.
