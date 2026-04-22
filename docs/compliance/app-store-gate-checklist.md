# Gate de Conformidade App Store (Go/No-Go)

## Status atual
`em andamento`.

Enquanto este gate não estiver concluído com decisão `go`, qualquer build iOS deve ser tratado como `internal-only`.

## Checklist obrigatório

- [ ] Revisão de enquadramento das políticas App Store para o modelo de sessão/workspace.
- [ ] Revisão jurídica dos termos de uso de terceiros e impacto de distribuição mobile.
- [ ] Definição de política de incidentes e resposta de compliance.
- [ ] Aprovação conjunta de Produto + Engenharia + Compliance/Jurídico.
- [ ] Registro formal da decisão com data e responsáveis.

## Critérios de No-Go

- incerteza jurídica relevante sem mitigação aprovada;
- conflito com política de distribuição sem alternativa segura;
- ausência de trilha de auditoria para decisões e releases.

## Critérios de Go

- checklist completo e assinado;
- riscos críticos com mitigação aceita;
- decisão formal registrada no repositório.

## Resultado esperado desta trilha

- documento de decisão final anexado no diretório `docs/compliance/`;
- atualização de `docs/roadmap.md` com mudança de status do gate.
