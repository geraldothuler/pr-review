# pr-review

Review de PR em que cada finding precisa de prova, e o resultado é uma decisão.

## O problema

A maioria dos fluxos de review produz uma **lista de observações plausíveis**. Três coisas ficam de fora:

- **Nada derruba o falso positivo.** Um finding que parece certo e está errado custa mais caro que um finding a menos — consome o tempo de quem revisa e desgasta a confiança no review.
- **Nada prova o fix.** A sugestão sai sem nunca ter rodado: é palpite com formatação de código, e quem aplica descobre por conta própria que não fecha.
- **Ninguém conclui.** A lista sai, a decisão de aprovar ou não fica órfã.

## O que este plugin adiciona

**4 provas por finding.** Nenhum entra no draft sem passar:

| Prova | Pergunta |
|---|---|
| P1 Existência | O código é esse mesmo? |
| P2 Alcançabilidade | A execução real chega nessa linha? |
| P3 Contrato | A lib se comporta como eu afirmo, na versão em uso? |
| P4 Discriminação | O que separaria isso de um falso positivo? |

Cada finding sai como **CONFIRMADO**, **SUSPEITA** (dizendo qual prova falta) ou **DESCARTADO** (dizendo qual prova refutou).

**Ledger de evidência.** Uma linha por prova, com o comando executado e o trecho do output. **Sem linha no ledger, o finding some** — não vira "suspeita". SUSPEITA é a saída para prova que faltou declaradamente; inferência silenciosa não tem saída.

**Fix rodado antes de proposto.** Todo finding bloqueador ou importante sobe a infra local do próprio repo — o `docker compose` do repo, nunca um inventado — e prova o baseline discriminante: o teste falha **sem** o fix? Se passa, o finding volta a ser suspeita e não vira proposta. Porta ocupada vira project name isolado e override fora do repo; nenhum container de terceiro é parado; o teardown derruba só o que a review subiu. O fix validado não é commitado na branch de ninguém: o que vai pro PR é a proposta.

**Proposta sempre acionável.** Bloco `suggestion` quando o fix cabe no hunk, bloco de código com âncora `path:line` quando não cabe — e a frase dizendo por que não coube. Fix em prosa não existe.

**Veredito obrigatório**, por regra determinística: `APPROVE`, `REQUEST CHANGES`, `APPROVE SE <condição>` ou `Sem veredito`. Hedge é proibido — "provavelmente" e "parece que" não passam.

**Dedup nos 3 endpoints.** Comentário de PR vive em três lugares distintos (`pulls/N/comments`, `issues/N/comments`, `pulls/N/reviews`). Ler só um é a causa mais comum de duplicata. Sem whitelist de autor: bot ou humano, todos contam.

**Post que não polui a timeline.** Comentário inline postado um a um cria **um objeto review `COMMENTED` por comentário** — quatro comentários viram quatro reviews, e review submetido não pode ser deletado (a API responde 422). O fluxo é um review **PENDING** com o array inteiro, conferido contra o hunk real, e **um** submit.

**Gate mecânico nos 4 caminhos de publicação.** O hook incluído exige `CLAUDE_REVIEW_APPROVED=1` para `gh pr review --approve|--request-changes|--comment`, `gh pr merge`, `gh api POST .../pulls/N/comments|reviews` e `gh pr comment`. Os dois últimos costumam ficar de fora dos gates — e são justamente por onde o post prematuro escapa.

## Instalação

```
/plugin marketplace add <org>/<repo>
/plugin install pr-review@<marketplace>
```

Requisitos: `bash` e `jq`. No Windows, o Git Bash atende — o gate cobre as duas tools de terminal (`Bash` e `PowerShell`) e a dica de retry sai no dialeto de quem chamou.

Verificar que o gate está ativo:

```bash
gh pr comment 1 --repo <org>/<repo> --body teste   # deve ser bloqueado
```

Se em vez do bloqueio aparecer `PreToolUse:Bash hook error` com `No such file or directory`, o hook não está rodando — o gate está inerte, não ativo.

## Testes

```bash
bash plugins/pr-review/tests/preflight-review.test.sh
```

Rodar em **bash**, não em zsh: o caso do caminho de instalação com espaço depende do word-splitting do bash, e em zsh passa por engano.

## Uso

```
/pr-review 1234
```

O fluxo para no draft e espera confirmação explícita. Gatilhos: `post it`, `posta`, `LGTM`, `aprovado`, `manda`, `pode postar`.

Para rodar só a fase de verificação sobre um review que já existe, use o prompt canônico no fim do `SKILL.md` — serve para subagente.

## Composição com skills de domínio

Este plugin é **agnóstico de stack**: não carrega regras de Terraform, Helm, logging ou design de API. Se o seu ambiente já tem uma skill de review com as regras da sua org, as duas se compõem em eixos diferentes:

- a skill de domínio responde **o que olhar**
- esta responde **como provar e como concluir**

Rodar a de domínio para levantar candidatos, e esta a partir do passo 5 para verificar e decidir.

## Estrutura

```
pr-review/
├── .claude-plugin/plugin.json
├── hooks/hooks.json                  # PreToolUse → Bash|PowerShell
├── scripts/preflight-review.sh       # gate dos 4 caminhos de publicação
├── tests/preflight-review.test.sh    # 19 casos sobre o gate
└── skills/pr-review/
    ├── SKILL.md                      # o fluxo de 8 passos
    └── local-validate.md             # procedimento do passo 6b (infra local do fix)
```
