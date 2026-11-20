# Transportes FSC

Plataforma de pedidos de transporte do Fayal Sport Club.

- `site/` — aplicação (publicada no GitHub Pages)
- `supabase/` — base de dados (migrações com regras de segurança) e função de administração
- `.github/workflows/` — publicação automática e tarefa que mantém o Supabase ativo

Nenhum dado pessoal é guardado neste repositório: tudo fica no Supabase do clube,
protegido por regras de acesso (cada encarregado só vê os seus dados).

## Cópias de segurança

Todos os domingos a tarefa «Cópia de segurança» exporta os dados, encripta-os (AES-256, chave no segredo
`BACKUP_KEY`) e guarda o ficheiro encriptado na execução da tarefa durante 90 dias.
Sem a chave o ficheiro é ilegível. **A chave tem de estar guardada pela Comissão de Gestão fora do GitHub.**

Para desencriptar (só para repor dados):

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in copia-transportes-AAAA-MM-DD.tgz.enc -out copia.tgz
