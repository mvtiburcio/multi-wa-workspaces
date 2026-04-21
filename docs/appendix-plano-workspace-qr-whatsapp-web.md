# Plano Técnico - App Interno com Workspaces de WhatsApp Web via QR (sem API oficial)

## 1) Escopo Exato (alinhado ao que você descreveu)
Você quer um app interno onde:
- cada `Workspace` representa uma sessão independente de WhatsApp Web;
- cada sessão é autenticada por QR Code (no celular que já tem o WhatsApp);
- múltiplos Workspaces ficam conectados em paralelo (ex.: XY, XZ, XA);
- não haverá cadastro de número via API oficial;
- a experiência do app deve ser organizada e profissional.

Perfeito: isso é um **gerenciador de sessões Web** com isolamento por Workspace.

---

## 2) Decisão técnica principal
Sem API oficial, o app será baseado em **WebKit + sessões isoladas**.

Isso significa:
- você consegue múltiplos WhatsApp Webs em paralelo (estilo Chrome/Brave/Safari com perfis diferentes);
- mas o núcleo do chat continuará vindo do WhatsApp Web (não há contrato oficial para render nativo completo sem API).

---

## 3) Arquitetura proposta (sem API)

## 3.1 Camadas
1. **App Shell nativo (SwiftUI)**
- tela de Workspaces;
- onboarding, configurações, permissões;
- indicadores, status, atalhos e UX geral.

2. **Engine de Sessões Web (WebKit)**
- 1 `WKWebView` por Workspace ativo;
- URL base: `https://web.whatsapp.com`;
- autenticação por QR no próprio Workspace.

3. **Isolamento de sessão por Workspace**
- cada Workspace usa um `WKWebsiteDataStore` persistente próprio;
- API nativa disponível (iOS 17+/macOS 14+):
  - `WKWebsiteDataStore.dataStoreForIdentifier(...)`
  - `WKWebsiteDataStore.removeDataStoreForIdentifier(...)`
- isso separa cookies/storage/cache por Workspace.

4. **Store local de metadados**
- SwiftData/SQLite para salvar:
  - id do Workspace;
  - id do DataStore WebKit;
  - nome/cor/ícone;
  - último status (conectado, reconectar etc.).

---

## 4) Fluxo funcional

## 4.1 Criar Workspace
1. Usuário toca `Novo Workspace`.
2. App cria `UUID` do Workspace.
3. App cria `WKWebsiteDataStore` dedicado para esse UUID.
4. Abre `web.whatsapp.com` nesse container isolado.
5. Usuário escaneia QR com o celular dono da conta.

## 4.2 Trocar Workspace
- ao trocar, app exibe webview ligada ao DataStore daquele Workspace;
- sessão permanece independente das outras.

## 4.3 Remover Workspace
- app encerra webview;
- remove DataStore do Workspace;
- remove metadados locais.

---

## 5) O que é viável e o que não é

## 5.1 Viável
- múltiplos Workspaces independentes via QR;
- sessões persistentes por Workspace;
- alternância rápida entre contas;
- app com navegação e gestão nativas.

## 5.2 Limite duro (importante)
- sem API oficial, **UI de conversa 100% nativa e estável** não é robusta;
- re-renderizar chats em UI própria a partir de DOM é frágil e quebra quando o WhatsApp Web mudar.

Resumo direto:
- para QR-only: experiência ideal é **shell nativo + conteúdo do chat web**.
- para chat 100% nativo confiável: precisa API oficial.

---

## 6) Tempo real e notificações

## 6.1 Foreground (app aberto)
- viável monitorar eventos da página e gerar alertas no app;
- badge por Workspace também é viável no shell nativo.

## 6.2 Background (principal risco no iOS)
- iOS suspende WebView quando app vai para background;
- sem API/webhook oficial, não há canal robusto para manter “tempo real real” com app fechado.

Condição prática:
- **tempo real pleno só com app em uso ativo**;
- em background/fechado no iOS, comportamento é limitado.

(Para macOS, o comportamento é mais permissivo, mas ainda depende do ciclo de vida do app e WebKit.)

---

## 7) Padrão profissional de engenharia

## 7.1 Estrutura recomendada
- `WorkspaceManager`
- `WebSessionEngine`
- `WebViewPool`
- `StorageRepository`
- `StateSyncCoordinator`
- `Telemetry/Crash`

## 7.2 Qualidade
- logs estruturados por Workspace;
- recovery automático de sessão inválida;
- métricas de memória/CPU por quantidade de WebViews;
- testes de regressão de login, troca e reconexão.

## 7.3 Segurança
- bloqueio por biometria no app;
- proteção de dados locais;
- opção de “wipe” de Workspace;
- trilha de auditoria de ações administrativas.

---

## 8) Estratégia de performance (fundamental)
Muitos Workspaces simultâneos podem consumir memória.

Modelo recomendado:
- manter até 1-2 WebViews “quentes”;
- demais Workspaces em estado “frio” (recarrega ao abrir);
- snapshots visuais para navegação rápida sem manter tudo ativo.

---

## 9) Matriz de viabilidade por plataforma

1. **macOS**
- melhor plataforma para esse modelo;
- uso mais próximo de desktop web.

2. **iPadOS**
- viável, melhor que iPhone para WhatsApp Web.

3. **iOS (iPhone)**
- tecnicamente possível, porém com UX limitada por layout desktop e restrições de background.

---

## 10) Roadmap de execução

## Fase 0 - POC técnica (5 dias)
- criar 3 Workspaces isolados;
- validar QR/login persistente em cada um;
- validar troca sem vazamento de sessão.

## Fase 1 - Core do produto (2 semanas)
- gestão completa de Workspaces;
- engine de ciclo de vida de WebViews;
- metadados, rename, cor, estado, remoção.

## Fase 2 - Robustez (2 semanas)
- recuperação de falhas;
- telemetria;
- otimização de memória;
- testes de longa duração.

## Fase 3 - UX premium (1-2 semanas)
- refino visual do shell;
- animações e feedbacks;
- acessibilidade.

---

## 11) Critérios de aceite (POC)
- criar e manter 3+ Workspaces independentes;
- cada Workspace com QR próprio e sessão isolada;
- reiniciar app e manter sessões;
- remover Workspace e invalidar dados locais daquele perfil;
- sem mistura de conta entre Workspaces.

---

## 12) Riscos de negócio/técnicos
1. Mudanças no WhatsApp Web quebrarem automações de detecção no front.
2. Limitação de tempo real em background no iOS.
3. Dependência de comportamento não contratado para integração profunda de UI.
4. Risco de conformidade de uso da plataforma.

---

## 13) Próximo passo objetivo
Se você aprovar este modelo QR-only, o próximo passo é implementar a **POC (Fase 0)** com:
- app SwiftUI;
- Workspaces com `WKWebsiteDataStore` por UUID;
- validação prática em iPhone + iPad + Mac.
