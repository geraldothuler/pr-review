---
name: pr-review
description: PR code review com verificação profunda antes de concluir — 4 provas por finding contra o codebase, a doc do framework e os serviços tocados, dedup dos 3 endpoints de comentário, e veredito assertivo (approve / request changes). Nunca publica sem confirmação explícita. Use quando pedirem "review PR", "/pr-review", "revisa o PR #X", ou antes de aprovar/comentar um PR.
user-invocable: true
---

# /pr-review — verificar antes de concluir

Review de PR em que **cada finding precisa de prova** e o resultado é **uma decisão**, não uma lista.

Duas coisas que a maioria dos fluxos de review não faz, e que são o propósito desta skill:

1. **Derrubar o falso positivo** — um finding plausível e errado custa mais que um finding a menos.
2. **Concluir** — todo review termina em APPROVE ou REQUEST CHANGES, com a razão que decidiu.

## O que esta skill não faz

Ela é **agnóstica de stack**: não carrega regras de domínio (tagging de Terraform, secrets em Helm, política de logging, design de API). Se o seu ambiente tem uma skill de review com as regras da sua org, as duas se compõem:

- a skill de domínio responde **o que olhar**
- esta responde **como provar e como concluir**

Ordem sugerida quando ambas existem: rodar a de domínio para levantar candidatos, e esta a partir do passo 5 para verificar e decidir.

## Regras invioláveis

1. **NUNCA** publique comentário, review ou aprovação sem confirmação explícita do usuário. Gatilhos aceitos: `post it`, `posta`, `LGTM`, `aprovado`, `manda`, `pode postar`. Qualquer outra coisa → perguntar
2. **NUNCA** submeta review antes da confirmação. As flags que submetem são `--approve`, `--request-changes` e `--comment` (não existe `--submit` no `gh pr review`) — todas as três são gated
3. **NUNCA** duplique finding já levantado por outro revisor — bot ou humano, sem whitelist
4. **NUNCA** invente finding — todo finding precisa de `path:line` lido e das 4 provas do passo 5
5. **NUNCA** inclua seção procedural genérica (deploy guide, cleanup notes) — só se o PR for sobre isso
6. **SEMPRE** termine com veredito explícito (`APPROVE` / `REQUEST CHANGES` / `APPROVE SE` / `Sem veredito`)
7. **NUNCA** entregue finding com hedge. Sem prova → é SUSPEITA declarada, ou não existe
8. **NUNCA** trate rótulo como veredito: `CodeRabbit: pass`, `checks green`, `0 findings` podem ser review skipado, rate limit ou check não registrado. Abrir o conteúdo
9. Use `gh` CLI autenticado, nunca API anônima

## Fluxo

### Passo 1 — Fetch

```bash
gh pr view <num> --repo <org>/<repo> --json title,body,baseRefName,headRefName,changedFiles,additions,deletions
gh pr diff <num> --repo <org>/<repo>

# SHA do head — necessário pro commit_id do passo 8
gh pr view <num> --repo <org>/<repo> --json headRefOid -q .headRefOid

# Os TRÊS endpoints de comentário — são distintos, e ler só um gera duplicata
gh api repos/<org>/<repo>/pulls/<num>/comments  --paginate   # inline, tem path+line
gh api repos/<org>/<repo>/issues/<num>/comments --paginate   # planos, sem threading
gh api repos/<org>/<repo>/pulls/<num>/reviews   --paginate   # bodies de review
```

### Passo 2 — Listar findings existentes (anti-dup)

Agrupar tudo que os 3 endpoints retornaram, por autor. **Sem whitelist de bots** — enum fechado fura silencioso. Todo autor conta: CodeRabbit, Copilot, `claude[bot]`, bots de infra da sua org, colegas humanos.

Dois lugares onde finding se esconde:

- **Blocos colapsados** (`<details>`, "Additional comments", "Outside diff range") — expandir e ler. A contagem no cabeçalho da review não é o total.
- **Body de review** (`pulls/<num>/reviews`) — não aparece em nenhum endpoint de `comments`.

Critério de duplicata: mesmo `path:line`, ou mesmo tema/trecho citado. Se já existe, vai pra seção Skipped — não pro draft.

### Passo 3 — Ler os arquivos alterados (inteiros, não só o diff)

Para cada arquivo modificado: `Read` do arquivo inteiro. Verifique cada finding candidato contra o código real — não infira de nome de função ou variável.

Arquivo grande (>2000 linhas) ou diff >1000 linhas: ler o entorno completo de cada hunk mais as definições que ele toca (função chamada, classe, config lida), e **declarar no draft** o que não foi lido. Nunca fingir cobertura total.

### Passo 4 — Levantar candidatos

Severidade:

- 🔴 **bloqueador** — bug de correção, security, perda de dados, quebra de runtime
- 🟠 **importante** — race condition, leak, idempotência, lock, performance
- 🟡 **menor** — naming, dead code, log/métrica ausente
- ⚪ **opinião** — refactor sugerido, alternativa idiomática

Descartar já aqui: o que outro revisor já levantou, estilo coberto por linter (exceto se o linter está desligado no projeto), e fluff procedural.

### Passo 5 — Verificação profunda (obrigatório — nada de inferência)

**Nenhum finding entra no draft sem passar por aqui.**

Cada candidato precisa sobreviver às **4 provas**. Prova não executada não conta como passada:

| Prova | Pergunta | Como provar |
|---|---|---|
| **P1 — Existência** | O código é esse mesmo? | `Read` do arquivo inteiro, `path:line` citado. Nunca inferir do nome ou do patch |
| **P2 — Alcançabilidade** | A execução real chega nessa linha? | Achar o chamador (`grep` em **todos** os módulos) e os gates a montante: feature flag, env, `if` de config, status/enum que barra o caminho |
| **P3 — Contrato** | A lib/framework se comporta como eu afirmo? | Conferir a doc **da versão em uso** (lockfile/manifest de dependências) ou o código da dependência. Nunca de memória, nunca pelo nome do método |
| **P4 — Discriminação** | O que separaria isso de um falso positivo? | Achar o grupo de controle: caso equivalente que **não** deveria exibir o sintoma. Se ele exibe igual, a causa é outra |

Além das provas por finding, avaliar o **entorno**:

- **Config viva vence o código.** Ler a config efetiva do ambiente, não o default do repo: env do deployment, arquivo de properties do **módulo executável** (que pode vencer o do módulo compartilhado no classpath), values de chart, ConfigMap, variável de ambiente. Quando possível, confirmar o valor no log de boot do serviço.
- **Serviços tocados.** Para cada consumidor do contrato alterado — produtores e consumidores do topic, chamadores do endpoint, jobs que leem a tabela — ele tolera a mudança? Nomear cada um verificado.
- **Doc e invariantes.** ADR, `CONTEXT.md`, SPEC ou equivalente que a mudança encosta. Violar invariante documentado é 🔴 por definição.
- **Testes.** Um teste que passa nas duas versões não prova nada. Exigir o **discriminating check**: o teste falha sem o fix? Atenção a teste que já codifica o bug como comportamento esperado, e a guard novo a montante que torna um teste existente degenerado sem quebrá-lo.

Classificar:

- **CONFIRMADO** — 4 provas passaram, com evidência citável
- **SUSPEITA** — sobreviveu, mas falta prova; dizer **qual** e o que a fecharia
- **DESCARTADO** — alguma prova refutou; vai pra seção de descartados com o motivo

Proibido no draft: "provavelmente", "deve estar", "parece que", "deveria". Se a frase precisa de hedge, é SUSPEITA — ou não existe.

### Passo 6 — Draft + veredito

Só CONFIRMADO e SUSPEITA entram. Cada linha carrega a evidência que a sustenta.

```
## Review PR #<num> — <título>

**VEREDITO: <APPROVE | REQUEST CHANGES | APPROVE SE <condição objetiva>>**
<uma frase com a razão que decide — não um resumo>

### 🔴 Bloqueadores
- `path/file:42` — <problema>. <fix>. Evidência: <o que foi lido/rodado>

### 🟠 Importantes
- `path/file:88` — <problema>. <fix>. Evidência: <...>

### 🟡 Menores / ⚪ Opiniões
- ...

### Suspeitas (prova faltando)
- `path/file:120` — <hipótese>. Falta: <P2 — quem chama isso de verdade>. Fecha com: <ação>

### Verificado e OK
- <serviço/consumidor/config/invariante checado que não virou finding — mostra a cobertura>

### Descartado
- <candidato> — refutado por <prova>

### Skipped (já levantado)
- <autor> `path:line` — <breve>

### Não coberto
- <arquivo não lido por inteiro, ou prova que não deu pra executar>
  (omitir a seção se a cobertura foi total — nunca omitir se não foi)

Aguardando confirmação para publicar.
```

**Regra de decisão** — determinística, sem hedge:

| Situação | Veredito |
|---|---|
| ≥1 🔴 CONFIRMADO | **REQUEST CHANGES** |
| 🟠 CONFIRMADO que toca dado de cliente, produção, contrato de API/topic ou migration | **REQUEST CHANGES** |
| 🟠 CONFIRMADO sem alcance em produção, ou SUSPEITA que viraria 🔴 | **APPROVE SE** \<condição objetiva e verificável\> |
| Só 🟡 / ⚪ | **APPROVE** |
| Não deu pra completar as provas (sem acesso, sem repo, diff grande demais) | **Sem veredito** — declarar o que bloqueou e o que falta |

Um veredito nunca é "não sei" disfarçado de APPROVE. Se falta prova, é APPROVE SE ou Sem veredito — com o que falta explícito.

### Passo 7 — Esperar

**PARE.** Não publique nada. O usuário vai refinar, confirmar ou cancelar.

Se o ambiente tem uma skill dedicada a postar em PR (com dedup próprio), delegar a publicação a ela e encerrar aqui.

### Passo 8 — Publicar (só após confirmação)

Refazer o inventário do passo 1 antes de publicar — pode ter entrado comentário novo entre o draft e a confirmação.

```bash
SHA=$(gh pr view <num> --repo <org>/<repo> --json headRefOid -q .headRefOid)

CLAUDE_REVIEW_APPROVED=1 gh api -X POST repos/<org>/<repo>/pulls/<num>/comments \
  -f body="<finding>" \
  -f commit_id="$SHA" \
  -f path="<path>" \
  -F line=<line> \
  -f side=RIGHT
```

`line` precisa ser linha **presente no diff** — a API responde 422 fora dele. Como o passo 3 manda ler o arquivo inteiro, é comum achar finding em linha não tocada: ancorar no hunk mais próximo e citar a linha real no corpo, ou publicar como comentário plano.

Review consolidado:

```bash
CLAUDE_REVIEW_APPROVED=1 gh pr review <num> --repo <org>/<repo> \
  --<approve|request-changes|comment> --body "<summary>"
```

Só usar `--approve` se o usuário pediu approve explicitamente.

⚠️ **Review submetido não pode ser deletado** (422). Duplicata é permanente — daí o inventário refeito.

## Gate mecânico — o que o hook cobre

Este plugin inclui `scripts/preflight-review.sh`, registrado como `PreToolUse` em `Bash`. Ele exige `CLAUDE_REVIEW_APPROVED=1` nos **quatro** caminhos de publicação:

| Caminho | Coberto |
|---|---|
| `gh pr review --approve` / `--request-changes` / `--comment` | ✅ |
| `gh pr merge` | ✅ |
| `gh api -X POST .../pulls/N/comments` ou `/reviews` | ✅ |
| `gh pr comment` | ✅ |

O hook é uma rede de segurança, não a regra. A regra é a 1: confirmação explícita. O hook existe porque a disciplina falha — e o caminho que costuma faltar em outros gates é justamente o de comentário via API.

Verificar que está ativo:

```bash
gh pr comment 1 --repo <org>/<repo> --body teste   # deve ser bloqueado
```

## Prompt canônico da verificação

Para rodar o passo 5 isolado — em subagente, ou sobre um review que já existe:

```
Valide de forma aprofundada no codebase para confirmar cada achado. Para cada um,
execute as 4 provas e cite a evidência:

  P1 existência      — leia o arquivo inteiro, cite path:line
  P2 alcançabilidade — ache o chamador real e os gates a montante (flag, env, config, status)
  P3 contrato        — confirme o comportamento da lib/framework na doc da versão em uso, não de memória
  P4 discriminação   — ache o grupo de controle que NÃO deveria exibir o sintoma; se exibir, a causa é outra

Avalie também: config efetiva do ambiente acima do default do repo; cada serviço ou
consumidor tocado pelo contrato mudado; invariantes de ADR/CONTEXT.md que a mudança
encosta; e se a suite tem discriminating check para o comportamento alterado.

Não infira nada. Classifique em CONFIRMADO / SUSPEITA (dizendo qual prova falta) /
DESCARTADO (dizendo qual prova refutou).

Entregue um draft limpo com veredito na primeira linha: APPROVE, REQUEST CHANGES ou
APPROVE SE <condição objetiva>. Sem hedge — se falta prova, o veredito diz o que falta.
```

## Casos edge

- **PR sem revisor automático**: dedup **continua obrigatório** — comentário de humano ou de outro bot duplica igual
- **PR grande**: pedir confirmação se o diff > 1000 linhas ("vou ler 12 arquivos, ok?")
- **PR em outro idioma**: responder no idioma do PR
- **Conflict markers no diff**: bloquear o review e pedir a resolução primeiro
- **Sem acesso ao repo local** (só o diff): P1 e P2 não fecham → veredito é **Sem veredito**, declarando isso
