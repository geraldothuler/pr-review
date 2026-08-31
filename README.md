# pr-review

Um plugin de code review para [Claude Code](https://claude.com/claude-code) que **exige prova antes de concluir — e conclui**.

```
/plugin marketplace add geraldothuler/pr-review
/plugin install pr-review@pr-review
```

## Por que

A maioria dos fluxos de review produz uma lista de observações plausíveis. Três coisas ficam de fora:

**Nada derruba o falso positivo.** Um finding que parece certo e está errado custa mais caro que um finding a menos — queima o tempo de quem revisa e desgasta a confiança no review inteiro.

**Nada prova o fix.** A sugestão sai sem nunca ter rodado: é palpite com formatação de código, e quem aplica descobre por conta própria que não fecha.

**Ninguém conclui.** A lista sai; a decisão de aprovar ou não fica órfã.

## O que ele faz

### 4 provas por finding

Nenhum finding entra no draft sem passar:

| Prova | Pergunta |
|---|---|
| **P1 Existência** | O código é esse mesmo? |
| **P2 Alcançabilidade** | A execução real chega nessa linha? |
| **P3 Contrato** | A lib se comporta como eu afirmo, na versão em uso? |
| **P4 Discriminação** | O que separaria isso de um falso positivo? |

Prova não executada não conta como passada. Cada finding sai como **CONFIRMADO**, **SUSPEITA** (dizendo qual prova falta e o que a fecharia) ou **DESCARTADO** (dizendo qual prova refutou).

P4 é a que mais derruba achado errado: obriga a achar o **grupo de controle** — o caso equivalente que *não* deveria exibir o sintoma. Se ele exibe igual, a causa é outra.

### Ledger de evidência

Uma linha por prova: finding, prova, comando executado, trecho do output. **Sem linha no ledger, o finding some** — não vira "suspeita". SUSPEITA é a saída para prova que faltou declaradamente; inferência silenciosa não tem saída.

### Fix rodado antes de proposto

Todo finding bloqueador ou importante tem o fix implementado e validado antes de virar proposta:

- **Baseline discriminante primeiro** — o teste falha *sem* o fix? Se passa, o finding volta a ser suspeita e não vira proposta. Teste que passa nas duas versões não prova nada.
- **Infra local com o `docker compose` do próprio repo**, em worktree isolado com submódulos inicializados. Nunca um compose inventado, nunca a branch do usuário.
- **Porta ocupada vira porta alternativa** por project name isolado e override fora do repo. Nenhum container de terceiro é parado para liberar porta; o que já estava de pé continua de pé.
- **Teardown do que a review subiu**, e só disso. Container de terceiro encontrado parado se relata, não se religa.
- **O fix não é commitado na branch de ninguém.** Ele existe para provar que resolve e para produzir o texto exato da proposta.

Não deu para validar é resultado legítimo, declarado em "Não coberto" — e o veredito não vira APPROVE. Fingir que validou, não.

### Proposta sempre acionável

Bloco `suggestion` quando o fix cabe em linhas contíguas dentro do hunk; bloco de código com âncora `path:line` quando não cabe, com a frase dizendo por que não coube. Fix em prosa não existe.

### Post que não polui a timeline

Comentário inline postado um a um cria **um objeto review `COMMENTED` por comentário** — quatro comentários viram quatro reviews, e review submetido não pode ser deletado (a API responde 422).

O fluxo é: review **PENDING** com o array `comments` inteiro → conferir cada `line`/`side` contra o hunk real (errado ainda dá para deletar) → **um** submit.

### Veredito obrigatório

Todo review termina em decisão, por regra determinística:

| Situação | Veredito |
|---|---|
| ≥1 bloqueador confirmado | **REQUEST CHANGES** |
| Importante confirmado tocando dado de cliente, produção, contrato de API ou migration | **REQUEST CHANGES** |
| Importante sem alcance em produção, ou suspeita que viraria bloqueador | **APPROVE SE** \<condição objetiva\> |
| Só menores e opiniões | **APPROVE** |
| Provas não completadas | **Sem veredito** — declarando o que bloqueou |
| Confirmado cujo fix não pôde ser validado local | **REQUEST CHANGES**, com o motivo declarado |

Hedge é proibido: "provavelmente", "parece que" e "deveria" não passam. Se a frase precisa de hedge, é suspeita declarada — ou não existe.

### Dedup nos 3 endpoints

Comentário de PR vive em três lugares distintos na API do GitHub:

```
pulls/{n}/comments    → inline, com path e line
issues/{n}/comments   → planos, sem threading
pulls/{n}/reviews     → bodies de review
```

Ler só um é a causa mais comum de comentário duplicado. Sem whitelist de autor — bot ou humano, todos contam, porque enum fechado fura silencioso.

### Gate mecânico nos 4 caminhos de publicação

O hook incluído exige `CLAUDE_REVIEW_APPROVED=1` em:

| Caminho | Coberto |
|---|---|
| `gh pr review --approve` / `--request-changes` / `--comment` | ✅ |
| `gh pr merge` | ✅ |
| `gh api POST .../pulls/{n}/comments` ou `/reviews` | ✅ |
| `gh pr comment` | ✅ |

Os dois últimos costumam ficar de fora dos gates — e são exatamente por onde o post prematuro escapa. Note que **não existe** flag `--submit` no `gh pr review`: as flags que submetem são `--approve`, `--request-changes` e `--comment`, e um gate escrito contra `--submit` nunca dispara.

Conferir que está ativo depois de instalar:

```bash
gh pr comment 1 --repo <org>/<repo> --body teste   # deve ser bloqueado
```

## Uso

```
/pr-review 1234
```

O fluxo tem 8 passos e **para no draft**, esperando confirmação explícita (`post it`, `posta`, `LGTM`, `aprovado`, `manda`, `pode postar`).

Para rodar só a fase de verificação sobre um review que já existe — inclusive em subagente — use o prompt canônico no fim do [SKILL.md](plugins/pr-review/skills/pr-review/SKILL.md).

## Composição com skills de domínio

Este plugin é **agnóstico de stack**. Ele não carrega regras de Terraform, Helm, logging ou design de API.

Se o seu ambiente já tem uma skill de review com as regras da sua organização, as duas se compõem em eixos ortogonais:

- a skill de domínio responde **o que olhar**
- esta responde **como provar, como validar e como concluir**

Rode a de domínio para levantar candidatos, e esta a partir do passo 5 para verificar e decidir.

## Estrutura

```
plugins/pr-review/
├── .claude-plugin/plugin.json
├── hooks/hooks.json                # PreToolUse → Bash|PowerShell
├── scripts/preflight-review.sh     # gate dos 4 caminhos
├── tests/preflight-review.test.sh  # 11 casos sobre o gate
└── skills/pr-review/
    ├── SKILL.md                    # o fluxo de 8 passos
    └── local-validate.md           # procedimento do passo 6b
```

## Licença

MIT
