# pr-review

Review de PR em que cada finding precisa de prova, e o resultado é uma decisão.

## O problema

A maioria dos fluxos de review produz uma **lista de observações plausíveis**. Duas coisas ficam de fora:

- **Nada derruba o falso positivo.** Um finding que parece certo e está errado custa mais caro que um finding a menos — consome o tempo de quem revisa e desgasta a confiança no review.
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

**Veredito obrigatório**, por regra determinística: `APPROVE`, `REQUEST CHANGES`, `APPROVE SE <condição>` ou `Sem veredito`. Hedge é proibido — "provavelmente" e "parece que" não passam.

**Dedup nos 3 endpoints.** Comentário de PR vive em três lugares distintos (`pulls/N/comments`, `issues/N/comments`, `pulls/N/reviews`). Ler só um é a causa mais comum de duplicata. Sem whitelist de autor: bot ou humano, todos contam.

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
├── tests/preflight-review.test.sh    # 11 casos sobre o gate
└── skills/pr-review/SKILL.md         # o fluxo de 8 passos
```
