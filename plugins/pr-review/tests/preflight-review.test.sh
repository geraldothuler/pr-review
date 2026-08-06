#!/usr/bin/env bash
# Testes do gate preflight-review. Roda em bash (NÃO em zsh): o caso do caminho com
# espaço depende do word-splitting do bash, que o zsh não faz — em zsh o teste passa
# por engano.
#
#   bash plugins/pr-review/tests/preflight-review.test.sh
#
# Exit 0 = tudo passou. Exit 1 = pelo menos um caso falhou.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$HERE/.." && pwd)
SCRIPT="$PLUGIN_ROOT/scripts/preflight-review.sh"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ✅ %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  ❌ %s\n' "$1"; [ $# -gt 1 ] && printf '     %s\n' "$2"; }

# Roda o hook como o Claude Code roda: JSON no stdin. Ecoa "<exit>|<stdout>".
run_hook() {
  local tool="$1" cmd="$2" out rc
  out=$(jq -nc --arg t "$tool" --arg c "$cmd" '{tool_name:$t,tool_input:{command:$c}}' \
        | bash "$SCRIPT" 2>/dev/null)
  rc=$?
  printf '%s|%s' "$rc" "$out"
}

expect_block() {
  local label="$1" tool="$2" cmd="$3" res rc out
  res=$(run_hook "$tool" "$cmd"); rc=${res%%|*}; out=${res#*|}
  if [ "$rc" != "2" ]; then
    bad "$label" "esperava exit 2 (bloqueio), veio $rc"
    return
  fi
  if ! printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    bad "$label" "stdout não é JSON com decision:block — $out"
    return
  fi
  # A dica de retry precisa sair no dialeto da tool que chamou.
  local reason expected
  reason=$(printf '%s' "$out" | jq -r '.reason')
  if [ "$tool" = "PowerShell" ]; then
    expected="\$env:CLAUDE_REVIEW_APPROVED='1';"
  else
    expected="CLAUDE_REVIEW_APPROVED=1 "
  fi
  case "$reason" in
    *"$expected"*) ok "$label" ;;
    *) bad "$label" "dica de retry não está na sintaxe de $tool" ;;
  esac
}

expect_allow() {
  local label="$1" tool="$2" cmd="$3" res rc out
  res=$(run_hook "$tool" "$cmd"); rc=${res%%|*}; out=${res#*|}
  if [ "$rc" != "0" ]; then
    bad "$label" "esperava exit 0 (libera), veio $rc"
  elif [ -n "$out" ]; then
    bad "$label" "esperava stdout vazio, veio: $out"
  else
    ok "$label"
  fi
}

echo "== bloqueio e liberação por tool =="
expect_allow "Bash + comando inofensivo passa calado"                Bash       'git status'
expect_block "Bash + gh pr comment bloqueia"                         Bash       'gh pr comment 123 --body oi'
expect_block "Bash + gh pr review --approve bloqueia"                Bash       'gh pr review 123 --approve'
expect_block "PowerShell + gh pr review --approve bloqueia"          PowerShell 'gh pr review 123 --approve'
expect_allow "Bash + override inline libera"                         Bash       'CLAUDE_REVIEW_APPROVED=1 gh pr review 123 --approve'
expect_allow "PowerShell + override \$env: libera"                   PowerShell "\$env:CLAUDE_REVIEW_APPROVED='1'; gh pr review 123 --approve"

echo "== acentuação da mensagem (UTF-8, sem dupla codificação) =="
res=$(run_hook Bash 'gh pr comment 123 --body oi')
reason=$(printf '%s' "${res#*|}" | jq -r '.reason')
case "$reason" in
  *"publicação em PR bloqueada"*) ok "razão volta com acento íntegro" ;;
  *) bad "razão volta com acento íntegro" "veio: $(printf '%s' "$reason" | head -1)" ;;
esac
case "$reason" in
  *Ã*|*â€*) bad "razão sem mojibake" "texto duplamente codificado na razão" ;;
  *) ok "razão sem mojibake" ;;
esac

echo "== comando do hook sobrevive a caminho com espaço =="
# Reproduz o caso do Windows (C:\Users\Nome Sobrenome) copiando o plugin para um
# caminho com espaço e executando o comando exatamente como o hooks.json o declara.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Com Espaco/scripts"
cp "$SCRIPT" "$tmp/Com Espaco/scripts/"
hook_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HOOKS_JSON")
out=$(CLAUDE_PLUGIN_ROOT="$tmp/Com Espaco" \
      bash -c "$hook_cmd" < /dev/null 2>&1)
rc=$?
if [ "$rc" = "0" ] && [ -z "$out" ]; then
  ok "comando do hooks.json roda com CLAUDE_PLUGIN_ROOT contendo espaço"
else
  bad "comando do hooks.json roda com CLAUDE_PLUGIN_ROOT contendo espaço" \
      "exit $rc — $out"
fi

echo "== matcher cobre as duas tools de terminal =="
matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$HOOKS_JSON")
for t in Bash PowerShell; do
  if printf '%s' "$t" | grep -qE "^($matcher)$"; then
    ok "matcher casa a tool $t"
  else
    bad "matcher casa a tool $t" "matcher atual: $matcher"
  fi
done

echo
printf '%s passaram, %s falharam\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
