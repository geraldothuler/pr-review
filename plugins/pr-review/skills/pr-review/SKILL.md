---
name: pr-review
description: PR code review com verificação profunda antes de concluir — 4 provas por finding contra o codebase, a doc do framework e os serviços tocados, ledger de evidência, fix implementado e validado na infra local do próprio repo, proposta sempre como suggestion, dedup dos 3 endpoints de comentário, e veredito determinístico (APPROVE / REQUEST CHANGES / APPROVE SE &lt;condição&gt; / Sem veredito). Nunca publica sem confirmação explícita. Use quando pedirem "review PR", "/pr-review", "revisa o PR #X", ou antes de aprovar/comentar um PR.
user-invocable: true
---

# /pr-review — verificar antes de concluir

Review de PR em que **cada finding precisa de prova**, **cada fix é rodado antes de ser proposto**, e o resultado é **uma decisão**, não uma lista.

Três coisas que a maioria dos fluxos de review não faz, e que são o propósito desta skill:

1. **Derrubar o falso positivo** — um finding plausível e errado custa mais que um finding a menos.
2. **Provar o fix** — sugestão que nunca rodou é palpite com formatação de código.
3. **Concluir** — todo review termina em APPROVE ou REQUEST CHANGES, com a razão que decidiu.

## O que esta skill não faz

Ela é **agnóstica de stack**: não carrega regras de domínio (tagging de Terraform, secrets em Helm, política de logging, design de API). Se o seu ambiente tem uma skill de review com as regras da sua org, as duas se compõem:

- a skill de domínio responde **o que olhar**
- esta responde **como provar e como concluir**

Ordem sugerida quando ambas existem: rodar a de domínio para levantar candidatos, e esta a partir do passo 5 para verificar e decidir.

## Regras invioláveis

1. **NUNCA** publique comentário, review ou aprovação sem confirmação explícita do usuário. Gatilhos aceitos: `post it`, `posta`, `LGTM`, `aprovado`, `manda`, `pode postar`. Qualquer outra coisa → perguntar
2. **NUNCA** submeta review antes da confirmação. As flags que submetem são `--approve`, `--request-changes` e `--comment` (não existe `--submit` no `gh pr review`) — todas as três são gated
3. **NUNCA** duplique finding já levantado por outro revisor — bot ou humano, sem whitelist
4. **NUNCA** invente finding — todo finding precisa de `path:line` lido, das 4 provas do passo 5 e de linha no ledger do passo 5b
5. **NUNCA** inclua seção procedural genérica (deploy guide, cleanup notes) — só se o PR for sobre isso
6. **SEMPRE** termine com veredito explícito (`APPROVE` / `REQUEST CHANGES` / `APPROVE SE` / `Sem veredito`)
7. **NUNCA** entregue finding com hedge. Sem prova → é SUSPEITA declarada, ou não existe
8. **NUNCA** trate rótulo como veredito: `CodeRabbit: pass`, `checks green`, `0 findings` podem ser review skipado, rate limit ou check não registrado. Abrir o conteúdo
9. **NUNCA** proponha fix em prosa. Ou bloco `suggestion`, ou bloco de código com âncora — ver passo 8
10. **NUNCA** faça commit ou push na branch do PR de outra pessoa. O fix validado vive no worktree local; o que vai pro PR é a proposta
11. Use `gh` CLI autenticado, nunca API anônima

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

Classificar em **três** estados, e só três:

| Estado | Quando | Onde vai |
|---|---|---|
| **CONFIRMADO** | as 4 provas passaram, com evidência citável | vira finding no draft |
| **SUSPEITA** | sobreviveu às provas, mas falta uma — e ela é **nomeada** | seção própria, com o que a fecharia |
| **DESCARTADO** | alguma prova refutou | seção de descartados, com o trecho do output |

Um candidato sem linha no ledger (passo 5b) não é nenhum dos três: **some**.

Dois rótulos deste fluxo que **não** são estado de finding, e não devem ser usados como tal:

- **"Não coberto"** — seção do draft. É cobertura que faltou no review (arquivo não lido inteiro, prova não executável, validação local não feita), não um achado.
- **"Sem veredito"** — resultado do review inteiro, quando as provas não puderam ser completadas. Nunca se aplica a um finding isolado.

Proibido no draft: "provavelmente", "deve estar", "parece que", "deveria". Se a frase precisa de hedge, é SUSPEITA — ou não existe.

### Passo 5b — Ledger de evidência (gate contra inferência)

As 4 provas dizem **o que** provar. O ledger é o artefato que prova que a prova **rodou**. Montar antes do draft, uma linha por finding e prova:

| Finding | Prova | Comando ou leitura executada | Trecho do output |
|---|---|---|---|
| `path/file:42` | P2 | `grep -rn "processEvent(" --include=*.kt` | `handler/Router.kt:88: processEvent(evt)` |

Regras:

- **Sem linha no ledger, o finding não entra no draft — e não vira SUSPEITA, some.** SUSPEITA é a saída para prova que faltou *declaradamente*; inferência silenciosa não tem saída.
- "Li o arquivo" não é linha de ledger. A linha cita **o que foi lido e o que aquilo mostrou**.
- Prova cujo output contradiz o finding derruba o finding na hora — vai pra DESCARTADO com o trecho.
- O ledger fica no rascunho de trabalho. No draft publicável entra só a coluna de evidência, resumida por finding.

### Passo 6 — Draft + veredito

Só CONFIRMADO e SUSPEITA entram. Cada linha carrega a evidência que a sustenta.

```
## Review PR #<num> — <título>

**VEREDITO: <APPROVE | REQUEST CHANGES | APPROVE SE <condição objetiva>>**
<uma frase com a razão que decide — não um resumo>

### 🔴 Bloqueadores
- `path/file:42` — <problema>. <fix>. Evidência: <o que foi lido/rodado>. Fix validado: <sim, ver passo 6b | n/a>

### 🟠 Importantes
- `path/file:88` — <problema>. <fix>. Evidência: <...>

### 🟡 Menores / ⚪ Opiniões
- ...

### Suspeitas (prova faltando)
- `path/file:120` — <hipótese>. Falta: <P2 — quem chama isso de verdade>. Fecha com: <ação>

### Verificado e OK
- <serviço/consumidor/config/invariante checado que não virou finding — mostra a cobertura>

### Descartado
- <candidato> — refutado por <prova>, com o trecho do output

### Skipped (já levantado)
- <autor> `path:line` — <breve>

### Não coberto
- <arquivo não lido por inteiro, prova não executada, ou validação local não realizada e por quê>
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
| 🔴/🟠 CONFIRMADO cujo fix não pôde ser validado local | **REQUEST CHANGES**, com o motivo da não-validação declarado |

Um veredito nunca é "não sei" disfarçado de APPROVE. Se falta prova, é APPROVE SE ou Sem veredito — com o que falta explícito.

### Passo 6b — Fix: implementar e validar local

**Obrigatório para todo finding 🔴 ou 🟠 CONFIRMADO.** 🟡 e ⚪ vão como suggestion sem validação — o custo de subir infra não se paga para naming e dead code.

Procedimento completo em [`local-validate.md`](local-validate.md). O contrato, em resumo:

1. **Worktree isolado** — `git worktree add` na branch do PR, com submódulos inicializados. Nunca sujar o working tree do usuário, nunca trocar a branch dele.
2. **Baseline discriminante primeiro** — reproduzir o defeito **antes** do fix. Se não falha sem o fix, o finding cai de volta pra SUSPEITA e não vira proposta.
3. **Infra local: o `docker compose` do próprio repo.** Nunca compose inventado, nunca Dockerfile "equivalente" que não é o de produção.
4. **Porta em uso → porta alternativa**, via project name isolado e override gerado fora do repo. Nunca parar container de terceiro para liberar porta.
5. **Rodar a suíte real** e colar o output. Verde sem compilação, ou com zero testes executados, não é verde.
6. **Teardown** — derrubar tudo que a review subiu, preservando o que já estava de pé. Container de terceiro que estava parado: **relatar, nunca religar**.
7. **Delegar quando existir skill de domínio** para aquele serviço — ela conhece as armadilhas locais. O procedimento genérico é fallback, não substituto.

O fix validado **não é commitado nem pushado**. Ele existe para (a) provar que resolve, (b) produzir o texto exato da suggestion.

### Passo 7 — Esperar

**PARE.** Não publique nada. O usuário vai refinar, confirmar ou cancelar.

Se o ambiente tem uma skill dedicada a postar em PR (com dedup próprio), delegar a publicação a ela e encerrar aqui.

### Passo 8 — Publicar (só após confirmação)

Refazer o inventário do passo 1 antes de publicar — pode ter entrado comentário novo entre o draft e a confirmação.

⚠️ **Não poste comentário inline avulso.** Cada `POST /pulls/N/comments` cria **um objeto review `COMMENTED` próprio**: quatro comentários viram quatro reviews na timeline, e review submetido **não pode ser deletado** (422). O caminho é um review **PENDING** com o array inteiro e **um** submit.

**1. Criar o review pendente** — sem campo `event`, o review fica `PENDING`: invisível para os outros, reversível, deletável.

```bash
SHA=$(gh pr view <num> --repo <org>/<repo> --json headRefOid -q .headRefOid)

# Identificador desta execução. O payload NÃO pode ser nomeado só pelo PR: um retry, ou
# dois drafts do mesmo PR, sobrescrevem o arquivo um do outro e você submete o corpo errado.
RUN="<num>-$(date +%s)-$$"
BODY="${TMPDIR:-/tmp}/review-body-$RUN.json"
PAYLOAD="${TMPDIR:-/tmp}/review-$RUN.json"

cat > "$BODY" <<'JSON'
{
  "body": "<resumo — o veredito e a razão que decidiu>",
  "comments": [
    {
      "path": "src/Handler.kt",
      "line": 42,
      "side": "RIGHT",
      "body": "Descrição do problema.\n\n```suggestion\n    val timeout = Duration.ofSeconds(30)\n```"
    }
  ]
}
JSON

# O heredoc é literal ('JSON' entre aspas), então o SHA entra depois — por jq, não por
# `sed -i`, cuja sintaxe diverge entre BSD e GNU.
jq --arg sha "$SHA" '.commit_id = $sha' "$BODY" > "$PAYLOAD"

REVIEW_ID=$(CLAUDE_REVIEW_APPROVED=1 gh api repos/<org>/<repo>/pulls/<num>/reviews \
  --method POST --input "$PAYLOAD" --jq .id)
```

**2. Conferir antes de submeter** — ler o pendente de volta e checar cada `line`/`side` contra a posição real do hunk (`gh pr diff <num>`). Errado se deleta e refaz; depois do submit, não.

```bash
gh api repos/<org>/<repo>/pulls/<num>/reviews/$REVIEW_ID/comments \
  --jq '.[] | {path, line, side, snippet: .body[0:80]}'

# se errou:
gh api repos/<org>/<repo>/pulls/<num>/reviews/$REVIEW_ID --method DELETE
```

**3. Submeter uma única vez:**

```bash
CLAUDE_REVIEW_APPROVED=1 gh api \
  repos/<org>/<repo>/pulls/<num>/reviews/$REVIEW_ID/events \
  --method POST -f event=REQUEST_CHANGES     # ou APPROVE, ou COMMENT
```

Só usar `APPROVE` se o usuário pediu approve explicitamente.

> Equivalente por MCP do GitHub: `pull_request_review_write` (method `create`) → `add_comment_to_pending_review` (N vezes) → `pull_request_review_write` (method `submit_pending`).

**Formato de cada finding** — nunca prosa:

| Situação | Formato |
|---|---|
| Fix cabe em linhas contíguas **dentro do hunk**, lado RIGHT | bloco ` ```suggestion ` — primeira escolha sempre |
| Linha fora do diff, múltiplos arquivos, ou mudança estrutural | bloco de código com a linguagem + âncora `path:line` + uma frase dizendo por que suggestion não coube |
| Nenhum dos dois | Não existe |

Regras do `suggestion`:

- O conteúdo **substitui integralmente** as linhas comentadas: indentação exata, e as linhas vizinhas que precisam sobreviver incluídas.
- Só aplica em linha **presente no diff**, lado RIGHT — fora dele a API responde 422. Como o passo 3 manda ler o arquivo inteiro, é comum achar finding em linha não tocada: ancorar no hunk mais próximo e citar a linha real no corpo.
- Multi-linha: `start_line` + `line`, e o bloco cobre exatamente esse intervalo.
- O texto validado no passo 6b é o que entra no bloco — não uma variação reescrita de cabeça.
- Se um comentário do array der 422, **o POST inteiro falha** e nada é criado. Corrigir a âncora e repetir; nenhum lixo fica para trás. É a vantagem do PENDING.

**Reply em thread existente** é caso legítimo, mas **não escapa da mecânica**: cada reply cria seu próprio objeto review `COMMENTED`. Se a poluição importar, agrupar as respostas num único comentário plano em vez de uma por thread.

Para corrigir o texto de um review **já publicado**: `PUT repos/<org>/<repo>/pulls/<num>/reviews/$REVIEW_ID` edita o body sem criar objeto novo.

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

Monte um ledger com uma linha por prova: finding | prova | comando executado | trecho do
output. Finding sem linha no ledger não entra no resultado — e não vira suspeita, some.

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
- **Sem acesso ao repo local** (só o diff): P1 e P2 não fecham e o passo 6b não roda → veredito é **Sem veredito**, declarando isso
- **Repo sem `docker compose` e sem skill de domínio**: rodar a suíte que existe (unit, integração) e declarar em "Não coberto" que não houve validação end-to-end
- **PR é do próprio usuário e ele pede o commit**: aí sim commitar no worktree e pushar — mas só com pedido explícito; o default da regra 10 continua valendo
