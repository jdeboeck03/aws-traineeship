#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): scans for secrets before letting a
# `git commit` or `git push` command run, using gitleaks. Defense-in-depth
# alongside the repo's git-level pre-commit hook and GitHub push protection —
# this layer also covers `git push` (which pre-commit hooks don't see) and
# `--no-verify` bypasses of the git hook.
#
# Fails open (allows the command) if gitleaks isn't installed, or if a push
# has no configured upstream to diff against yet.
set -u

if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"jq not found on PATH — skipping secret scan before git commit/push."}'
  exit 0
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Determine intent by whichever keyword appears LEFTMOST in the command —
# not just "does the word appear anywhere". A plain substring search gets
# fooled by e.g. a commit message body that itself mentions "git push" in
# prose, appearing after the real (and earlier) "git commit" invocation.
commit_pos=$(printf '%s' "$cmd" | grep -aboE 'git[[:space:]]+commit([[:space:]]|$)' | head -1 | cut -d: -f1)
push_pos=$(printf '%s' "$cmd" | grep -aboE 'git[[:space:]]+push([[:space:]]|$)' | head -1 | cut -d: -f1)

mode=""
if [ -n "$commit_pos" ] && { [ -z "$push_pos" ] || [ "$commit_pos" -le "$push_pos" ]; }; then
  mode="commit"
elif [ -n "$push_pos" ]; then
  mode="push"
fi

# Not a git commit/push invocation at all.
if [ -z "$mode" ]; then
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  printf '{"systemMessage":"gitleaks not found on PATH — skipping secret scan before git commit/push."}'
  exit 0
fi

deny() {
  reason=$(printf '%s' "$1" | tail -c 2000 | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$reason"
  exit 0
}

if [ "$mode" = "push" ]; then
  # Scan only the commits about to be pushed. Prefer the configured push
  # target (@{push}); fall back to the origin/<branch> remote-tracking ref,
  # since plain `git push origin <branch>` never sets up @{push} tracking.
  # Skip gracefully if neither exists yet (e.g. first-ever push of a branch).
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if git rev-parse --abbrev-ref --symbolic-full-name '@{push}' >/dev/null 2>&1; then
    range='@{push}..'
  elif [ -n "$branch" ] && git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
    range="origin/$branch.."
  else
    range=''
  fi

  if [ -n "$range" ]; then
    log=$(gitleaks git --redact --no-banner --no-color --log-opts="$range" 2>&1)
    if [ $? -ne 0 ]; then
      deny "Secrets detected by gitleaks in commits about to be pushed. Fix before pushing.

$log"
    fi
  fi
  exit 0
fi

# git commit: scan staged changes.
log=$(gitleaks git --pre-commit --staged --redact --no-banner --no-color 2>&1)
if [ $? -ne 0 ]; then
  deny "Secrets detected by gitleaks in staged changes. Fix before committing.

$log"
fi

exit 0
