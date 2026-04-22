# Riscos e Limites

## Riscos de Conformidade e Distribuição

- reprovação na App Store por interpretação de política de plataforma/terceiros;
- exigências legais e de termos de uso mudarem após início da implementação;
- necessidade de ajustes rápidos de UX/fluxo para manter conformidade.

Mitigações:

- gate obrigatório de conformidade antes de codificar iOS;
- revisão periódica jurídica/política durante a implementação;
- documentação de decisão e trilha de auditoria por release.

## Riscos Técnicos

- mudanças frequentes no frontend web de origem quebrarem parser/normalização;
- divergência semântica entre dados extraídos e modelo nativo de inbox/thread;
- latência de sincronização degradar UX em picos de eventos;
- consumo de memória/CPU no iOS ao processar muitos eventos.

Mitigações:

- contratos versionados de dados e testes de regressão de parsing;
- fallback híbrido para WebView controlada quando parser falhar;
- sync incremental por cursor e cache local otimizado;
- limites operacionais por workspace e monitoramento de performance.

## Riscos Operacionais de Cloud Worker

- custo de infraestrutura crescer linearmente com número de workspaces ativos;
- indisponibilidade parcial de workers impactar continuidade em background;
- filas de comando/evento acumularem sob falha de rede.

Mitigações:

- autoscaling e política de capacidade por workspace;
- retries com backoff, dead-letter queue e replay por cursor;
- SLOs com alertas por latência, erro e backlog;
- runbooks de incidentes e fallback operacional.

## Limites Conhecidos

- estratégia local-only não atende requisito de tempo real contínuo no iOS;
- fallback híbrido é contingência, não substituto da trilha nativa;
- lançamento App Store depende de aprovação no gate de conformidade.

## Decisão de Produto Relacionada

A escolha oficial para iOS v1 é:

- app `iPhone-first` com UI 100% nativa;
- backend bridge com worker por workspace como pré-requisito de tempo real total;
- fallback híbrido somente em degradação controlada.
