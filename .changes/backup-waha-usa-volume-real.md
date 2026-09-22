---
impacto: nada_mudou
secao: corrigido
titulo: Backup do WhatsApp passa a usar o volume real de sessões
---

Os comandos de backup e restauração agora identificam o volume físico montado no WAHA, evitando gerar arquivos vazios quando o nome do projeto é prefixado pelo Docker Compose. Backups das sessões feitos antes desta versão podem ter saído vazios: depois de atualizar, rode um backup novo.

Contribuição de @matheuspedro360 (#1429).
