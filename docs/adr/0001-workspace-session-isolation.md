# ADR-0001: Isolamento de Sessão por Workspace

## Status
Aceita

## Contexto
Projeto precisa operar múltiplas sessões independentes de WhatsApp Web no mesmo app.

## Decisão
Cada workspace terá seu próprio `WKWebsiteDataStore` persistente, identificado por UUID.

## Consequências
### Positivas
- isolamento de cookies/storage por workspace;
- troca de workspace sem mistura de sessão;
- remoção seletiva de dados por workspace.

### Negativas
- maior complexidade de gerenciamento de ciclo de vida;
- consumo de memória com muitas webviews ativas.

## Notas de implementação
- usar pool de webviews com limite de aquecimento;
- manter metadados locais com `workspaceID -> dataStoreID`.
