# Validação local do fix — procedimento do passo 6b

Referência do passo 6b do `SKILL.md`. Obrigatório para todo finding 🔴 ou 🟠 **CONFIRMADO**.

O ponto: **sugestão que nunca rodou é palpite com formatação de código.** O que sai daqui é o texto exato que vai para o bloco `suggestion`, mais o output que prova que ele resolve.

---

## 0. Existe skill de domínio para este serviço?

Se sim, **delegar a ela** e voltar com o output. Ela conhece a ordem obrigatória de comandos, as portas reais e as armadilhas do serviço; este procedimento genérico é fallback, não substituto.

Sinais de que existe: skill cujo nome cita o serviço, ou o padrão `*-local-*` / `*-local-validate` no diretório de skills.

---

## 1. Worktree isolado

Nunca trocar a branch do usuário, nunca sujar o working tree dele.

```bash
REPO=<caminho do clone>
PR=<número>

# RUN é o identificador desta execução, e ele entra em TUDO: worktree, branch temporária,
# project name do Compose e override. Nome derivado só do PR colide entre duas validações
# simultâneas do mesmo PR (ou entre um retry e a execução que ainda está de pé), e aí o
# teardown de uma apaga os volumes da outra.
RUN="$PR-$(date +%s)-$$"
WT="${TMPDIR:-/tmp}/review-$RUN"
BR="review/pr-$RUN"

git -C "$REPO" fetch origin "pull/$PR/head:$BR"
git -C "$REPO" worktree add "$WT" "$BR"

# worktree NÃO inicializa submódulo — sem isso, código gerado (proto, stubs) some
# e a ausência parece quebra do PR
git -C "$WT" submodule update --init --recursive
```

Ao final: `git -C "$REPO" worktree remove "$WT" --force` e `git -C "$REPO" branch -D "$BR"`.

---

## 2. Baseline discriminante — antes do fix

**Ordem importa.** Rodar o teste que expõe o defeito **no código do PR, sem o fix**:

- Falhou → o finding está provado, siga.
- Passou → o finding **não** está provado. Volta pra SUSPEITA no draft, com "o teste que eu esperava falhar passou" declarado. Não vira proposta.

Teste que passa nas duas versões não prova nada. Se não existe teste que discrimine, escrever um — é ele que vira parte da suggestion.

Dois casos que produzem verde enganoso:

- **Mock que recebe a função e não a invoca** — desvia do caminho real e codifica o bug como esperado.
- **Guard novo a montante** que torna um teste existente degenerado sem quebrá-lo.

---

## 3. Infra local: o `docker compose` do próprio repo

Nunca um compose inventado, nunca um Dockerfile "equivalente" — só o que o repo usa.

```bash
cd "$WT"
COMPOSE=$(ls docker-compose.y*ml compose.y*ml 2>/dev/null | head -1)
[ -z "$COMPOSE" ] && echo "sem compose no repo — ver seção 7"
```

**Project name isolado** é o que torna o teardown mecânico: tudo que a review subir fica sob um prefixo próprio, e nada do que já estava de pé entra na conta.

```bash
PROJ="rv$(printf '%s' "$RUN" | tr -cd '[:alnum:]')"
```

---

## 4. Portas em uso → portas alternativas

Primeiro **medir**, depois remapear. Nunca parar container de terceiro para liberar porta.

```bash
# portas que o compose quer expor no host
grep -oE '^\s*-\s*"?[0-9]+:[0-9]+' "$COMPOSE" | grep -oE '[0-9]+:' | tr -d ':' | sort -u

# quem está ocupando cada uma (docker ou processo nativo)
lsof -nP -iTCP:<porta> -sTCP:LISTEN
docker ps --format '{{.Names}}\t{{.Ports}}' | grep ':<porta>->'
```

Para cada porta ocupada, um override **fora do repo** — arquivo dentro do repo vaza no diff e polui o PR:

```bash
OVR="${TMPDIR:-/tmp}/review-$RUN-ports.yml"
cat > "$OVR" <<'YAML'
services:
  postgres:
    ports: ["55432:5432"]
YAML

docker compose -p "$PROJ" -f "$COMPOSE" -f "$OVR" up -d --wait
```

Ajustar a config da aplicação para as portas novas por **variável de ambiente**, não editando arquivo versionado.

Porta tomada por container de outro repo ou por processo nativo do usuário: o remap resolve os dois casos. Em nenhum deles se mata o que estava rodando.

---

## 5. Rodar a suíte real

Comando do próprio repo (`Makefile`, `gradlew`, `package.json`, `pytest.ini`, README). Colar o **output real**, não um resumo.

Verde não conta quando:

- **Nada compilou** — build que não mostra "compilando N arquivos" pode ser no-op de multi-módulo.
- **Zero testes executados** — a suíte falhou antes de rodar e a saída parece sucesso.
- **O runtime não é o que se pensa** — conferir a versão efetiva, não a que o wrapper deveria escolher.

Ordem: reproduzir a falha (§2) → aplicar o fix → rodar de novo → **os dois outputs entram no ledger**.

Armadilha frequente de suíte de integração em compose: banco do compose com limite de conexões baixo estoura sob suíte grande (`too many clients`), derruba o contexto da aplicação e **parece regressão do PR**. Conferir os logs do serviço de infra antes de acusar o código.

---

## 6. Teardown — só o que a review subiu

```bash
docker compose -p "$PROJ" -f "$COMPOSE" ${OVR:+-f "$OVR"} down -v --remove-orphans
docker ps -a --filter "label=com.docker.compose.project=$PROJ" --format '{{.Names}}'  # deve sair vazio
rm -f "$OVR"
git -C "$REPO" worktree remove "$WT" --force
git -C "$REPO" branch -D "$BR"
```

Regras:

- **Some tudo que fugiu do padrão original** — containers do project name da review, override, worktree, branch temporária.
- **Fica tudo que já estava de pé antes.** Não é da review — e como todo nome carrega o `RUN`, uma validação concorrente do mesmo PR não é tocada.
- **Container de terceiro encontrado parado: relatar, nunca religar.** Pode ter sido parado de propósito.
- Recurso efêmero criado fora do Docker (pod de debug em cluster, por exemplo) também é removido — e nomeado no draft.

Fechar declarando o estado: o que subiu, o que foi derrubado, o que ficou de pé e por quê.

---

## 7. Quando não dá para validar

Sem compose, sem skill de domínio, infra indisponível, serviço que só existe em cloud:

1. Rodar o que existir (unit, integração com testcontainers, lint).
2. Declarar na seção **"Não coberto"** do draft o que não foi validado e por quê.
3. O veredito **não vira APPROVE** com 🔴/🟠 confirmado e fix não validado — é REQUEST CHANGES com o motivo, ou APPROVE SE com a condição objetiva.

Não validar é um resultado legítimo. Fingir que validou não.
