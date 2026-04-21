# Plano Técnico Completo - App Interno Multi-Instância WhatsApp (iOS, iPadOS, macOS)

## 1) Objetivo do Produto
Criar um app interno, com visual 100% nativo e padronizado, para operar múltiplas instâncias de WhatsApp em paralelo, com:
- gestão centralizada de conversas;
- notificações em tempo real;
- separação clara por instância/conta;
- UX premium (animações, fluidez, consistência visual);
- qualidade de engenharia em padrão profissional.

---

## 2) Resumo Executivo (decisão crítica)
Você quer:
1. escanear QR;
2. manter várias contas conectadas;
3. interface nativa própria (não interface do WhatsApp Web);
4. tudo em tempo real e sem divergência.

### Fato técnico importante
Sem usar integração oficial, não existe caminho robusto para “interface nativa própria” com dados em tempo real do WhatsApp sem depender de scraping/automação não oficial.

### Recomendação principal
Adotar **WhatsApp Business Platform (oficial)** + backend + app Swift nativo.  
Isso entrega exatamente o que você quer em UX, robustez, escalabilidade e governança.

---

## 3) O que é viável x não viável

## 3.1 Viável (recomendado)
- App nativo SwiftUI (iOS/iPadOS/macOS) com inbox unificada;
- múltiplas instâncias oficiais por número empresarial;
- mensagens recebidas por webhook e enviadas via API;
- push nativo (APNs) por instância e conversa;
- sincronização estável e auditável.

## 3.2 Não viável de forma robusta
- “Abrir WhatsApp Web e re-skin completo em UI nativa” sem integração oficial;
- usar WhatsApp Web no mobile como base confiável de produção;
- escalar várias contas com consistência forte sem backend/estado persistido.

## 3.3 Sobre “10 WhatsApp conectados”
- O limite não é por IP;
- o limite é definido por política/capacidade da conta/plataforma do WhatsApp;
- para escala real, a modelagem correta é por números/instâncias oficiais no Business Platform.

---

## 4) Arquitetura Recomendada (produção interna séria)

## 4.1 Camadas
1. **App Cliente (SwiftUI)**
- iOS/iPadOS/macOS (projeto multiplataforma);
- design system unificado;
- inbox por instância + inbox consolidada.

2. **Backend de Orquestração**
- integra com WhatsApp Business Platform;
- recebe webhooks, aplica regras, normaliza eventos;
- garante idempotência, ordenação e consistência.

3. **Banco de Dados (obrigatório para robustez)**
- persistência de mensagens, estados, leituras, atribuídos e auditoria.

4. **Canal de Notificação**
- APNs para push nativo;
- fallback de sincronização por pull incremental.

## 4.2 Por que DB é necessário
Sem DB, você perde:
- histórico consistente entre dispositivos;
- deduplicação de eventos;
- estado de leitura/não lida por usuário;
- auditoria e rastreabilidade;
- recuperação após falha/reconexão.

Conclusão: para “tudo em tempo real, sem divergência”, DB não é opcional.

---

## 5) Modelo de Dados (MVP robusto)

## 5.1 Entidades mínimas
- `Workspace` (empresa/time)
- `Instance` (número/canal WhatsApp)
- `Contact`
- `Conversation`
- `Message`
- `Participant`
- `Assignment` (responsável)
- `ReadState`
- `DeliveryEvent` (sent/delivered/read)
- `WebhookEventLog` (idempotência/auditoria)

## 5.2 Regras essenciais
- `external_message_id` único por instância;
- idempotência por `event_id`;
- ordering por `event_timestamp` + sequência interna;
- soft delete para trilha de auditoria.

---

## 6) App Swift (iOS + iPadOS + macOS)

## 6.1 Stack sugerida
- Swift 6+;
- SwiftUI + Observation;
- `async/await` + `actors` para concorrência segura;
- SwiftData/Core Data para cache local;
- URLSession + WebSocket/SSE (quando aplicável).

## 6.2 Módulos
- `DesignSystem`
- `Auth`
- `Instances`
- `Inbox`
- `Conversation`
- `Notifications`
- `Settings`
- `SyncEngine`
- `Telemetry`

## 6.3 Padrão de arquitetura
- Clean Architecture + MVVM (ou TCA, se preferir disciplina máxima de estado);
- boundary claro entre UI, domínio e infraestrutura;
- DI por protocolo.

---

## 7) UX e Design (padrão premium)

## 7.1 Direção visual
- interface nativa, sem aparência de webview;
- identidade única para cada instância (cor/ícone/tag);
- foco em velocidade de atendimento (menos toques).

## 7.2 Componentes-chave
- Sidebar de instâncias;
- Inbox consolidada e inbox por instância;
- badges por conta;
- filtros rápidos (não lidas, com responsável, urgentes);
- composer com anexos e templates.

## 7.3 Animações
- transições de contexto (instância -> conversa) suaves;
- microinterações funcionais (sem excesso);
- feedback imediato de envio/erro/reenvio.

---

## 8) Tempo Real e Consistência

## 8.1 Fluxo de entrada
1. WhatsApp envia webhook ao backend.
2. Backend valida assinatura e deduplica evento.
3. Persiste no DB e atualiza projeções de inbox.
4. Dispara push/APNs e evento de sync.

## 8.2 Fluxo de saída
1. Usuário envia no app.
2. Backend registra `pending`.
3. Envia via API oficial.
4. Atualiza status (`sent` -> `delivered` -> `read`) via callbacks.

## 8.3 Estratégia anti-divergência
- idempotência forte;
- reconciliação periódica;
- dead-letter queue para eventos inválidos;
- monitoramento de lag de webhook.

---

## 9) Segurança e Compliance

## 9.1 Segurança técnica
- criptografia em trânsito (TLS) e em repouso;
- tokens em cofre (KMS/Secrets Manager);
- device binding + biometria opcional;
- RBAC por perfil (admin/atendente/somente leitura);
- logs auditáveis.

## 9.2 Política operacional
- uso exclusivo corporativo interno;
- consentimento e governança de dados;
- política de retenção e exclusão;
- trilha de acesso por usuário.

---

## 10) Distribuição interna

## 10.1 Opções
1. TestFlight privado (rápido para equipe pequena).
2. Apple Developer Enterprise Program (cenário corporativo formal).
3. Ad Hoc (grupos muito pequenos e controlados).

## 10.2 Recomendação prática inicial
- iniciar com TestFlight interno e governança de dispositivos.

---

## 11) Roadmap de Implementação

## Fase 0 - Descoberta e travas (1 semana)
- fechar decisão de integração oficial;
- definir escopo MVP;
- mapear riscos legais e operacionais.

## Fase 1 - Fundação de arquitetura (2 semanas)
- backend base + DB + autenticação;
- onboarding de instâncias;
- pipeline webhook com idempotência.

## Fase 2 - Produto MVP (3 semanas)
- inbox multi-instância;
- tela de conversa;
- envio/recebimento em tempo real;
- push por instância.

## Fase 3 - Qualidade e escala (2 semanas)
- observabilidade (logs/métricas/tracing);
- testes E2E e carga;
- hardening de falhas e reconciliação.

## Fase 4 - UX premium (2 semanas)
- refinamento visual completo;
- motion e acessibilidade;
- otimização de performance em listas grandes.

---

## 12) Critérios de Aceite (MVP)
- múltiplas instâncias ativas simultaneamente;
- recebimento em tempo real < 3s (p95);
- envio com confirmação de status;
- zero duplicação funcional de mensagens;
- push funcionando por instância e conversa;
- sincronização correta entre iPhone, iPad e Mac;
- logs auditáveis por ação crítica.

---

## 13) Riscos e Mitigações

1. **Risco de integração não oficial**
- Mitigação: usar plataforma oficial.

2. **Divergência de estado**
- Mitigação: idempotência + reconciliação + DLQ.

3. **Escalabilidade de notificações**
- Mitigação: fila assíncrona + retry exponencial.

4. **Queda de qualidade UX em alto volume**
- Mitigação: paginação, cache inteligente, profiling contínuo.

---

## 14) Decisões que você precisa bater o martelo
1. Confirmar rota oficial (recomendado).
2. Definir backend stack (ex.: Swift/Vapor ou Node/Nest).
3. Definir DB (PostgreSQL recomendado).
4. Definir distribuição interna inicial (TestFlight).
5. Definir escopo MVP (campos, filtros, permissões).

---

## 15) Próximo passo objetivo
Assim que você confirmar a rota oficial, o próximo entregável é:
- PRD + arquitetura detalhada + diagrama de sequência + backlog por sprint + estrutura inicial do monorepo (app + backend) prontos para iniciar codificação.
