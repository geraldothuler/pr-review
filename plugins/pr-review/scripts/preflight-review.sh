#!/usr/bin/env bash
# preflight-review.sh — gate de confirmação para posts em PR.
#
# PreToolUse hook (matcher Bash): intercepta comandos que publicam algo num PR e
# bloqueia (exit 2 + decision:block) salvo override explícito via CLAUDE_REVIEW_APPROVED=1.
#
# Cobre os 4 caminhos de publicação — os dois últimos costumam ficar de fora:
#   1. gh pr review --approve|--request-changes|--comment   (submete review)
#   2. gh pr merge                                          (merge)
#   3. gh api POST .../pulls/N/comments|reviews             (inline comment via API)
#   4. gh pr comment                                        (comentário plano)
#
# Idempotente e stateless: só lê o comando, nunca escreve.

stdin=$(cat)
cmd=$(echo "$stdin" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Permite opt-in via prefixo inline (`CLAUDE_REVIEW_APPROVED=1 gh pr review ...`),
# sem depender do env do processo pai.
if [ -z "${CLAUDE_REVIEW_APPROVED:-}" ]; then
  CLAUDE_REVIEW_APPROVED=$(echo "$cmd" \
    | grep -oE '(^|[[:space:]])CLAUDE_REVIEW_APPROVED=[^[:space:]]+' \
    | head -1 | sed -E 's/.*CLAUDE_REVIEW_APPROVED=//')
fi

block() {
  local reason="$1"
  echo "{\"decision\":\"block\",\"reason\":$(printf '%s' "$reason" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
  exit 2
}

# --- 1 e 2: review submetido / merge ---
review_or_merge='\bgh[[:space:]]+pr[[:space:]]+(review[^|;&]*--(approve|request-changes|comment)|merge)\b'

# --- 3: POST na API de comments/reviews do PR ---
api_post='\bgh[[:space:]]+api\b[^|;&]*(-X[[:space:]]+POST|--method[[:space:]]+POST)[^|;&]*pulls/[0-9]+/(comments|reviews)\b'

# --- 3b: POST sem -X explícito (gh api usa POST quando há -f/-F) ---
api_field='\bgh[[:space:]]+api\b[^|;&]*pulls/[0-9]+/(comments|reviews)\b[^|;&]*(-f|-F|--field|--raw-field)[[:space:]]'

# --- 4: comentário plano ---
pr_comment='\bgh[[:space:]]+pr[[:space:]]+comment\b'

matched=""
echo "$cmd" | grep -qE "$review_or_merge" && matched="gh pr review/merge"
[ -z "$matched" ] && echo "$cmd" | grep -qE "$api_post"   && matched="gh api POST pulls/N/comments|reviews"
[ -z "$matched" ] && echo "$cmd" | grep -qE "$api_field"  && matched="gh api pulls/N/comments|reviews (campos -f/-F)"
[ -z "$matched" ] && echo "$cmd" | grep -qE "$pr_comment" && matched="gh pr comment"

if [ -n "$matched" ]; then
  if [ "${CLAUDE_REVIEW_APPROVED:-0}" != "1" ]; then
    block "🛑 preflight-review: publicação em PR bloqueada sem confirmação explícita do usuário.

Caminho detectado: $matched

Apresente o draft e espere a confirmação (post it / posta / LGTM / aprovado / manda / pode postar).
Antes de publicar, refaça o inventário de comentários — pode ter entrado comentário novo desde o draft:
  gh api repos/<org>/<repo>/pulls/<n>/comments  --paginate
  gh api repos/<org>/<repo>/issues/<n>/comments --paginate
  gh api repos/<org>/<repo>/pulls/<n>/reviews   --paginate

Review submetido não pode ser deletado (a API responde 422) — duplicata é permanente.

Após confirmação, rodar com: CLAUDE_REVIEW_APPROVED=1 $cmd"
  fi
fi

exit 0
