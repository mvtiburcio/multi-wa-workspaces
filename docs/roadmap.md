# Roadmap

## Fase 0 - Planejamento (concluída)
- consolidar requisitos;
- documentar arquitetura e riscos;
- preparar repositório open source.

## Fase 1 - POC macOS (v1 implementada)
Data de referência: 21 de abril de 2026.

- [x] criação de workspace;
- [x] renomeação de workspace;
- [x] remoção de workspace com limpeza transacional;
- [x] isolamento de sessão por `WKWebsiteDataStore`;
- [x] troca entre workspaces sem vazamento de sessão;
- [x] persistência de metadados locais com SwiftData;
- [x] monitoramento de estado (`loading`, `qrRequired`, `connected`, `failed`);
- [x] testes unitários e integração;
- [x] CI de build/test macOS.

## Fase 2 - Robustez (pendente)
- monitoramento técnico expandido (métricas por workspace);
- otimização de memória para cenários com muitos workspaces;
- testes de estabilidade de longa duração;
- política explícita de reconexão e recuperação automática.

## Fase 3 - UX e operação (pendente)
- refinamento visual e acessibilidade;
- fluxos detalhados de erro/reconexão;
- documentação operacional para uso interno;
- guia de troubleshooting com casos recorrentes.
