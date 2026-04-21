# Segurança para Repositório Open Source

## Política de segredos
- proibido commitar segredos;
- usar apenas placeholders;
- revisar diff antes de cada push.

## Checklist antes de publicar
- [ ] nenhum `.env` real
- [ ] nenhuma chave/token
- [ ] nenhum endpoint interno sensível
- [ ] nenhum dado de cliente

## Ferramentas recomendadas
- secret scanning no GitHub;
- branch protection;
- code review obrigatório para mudanças críticas.
