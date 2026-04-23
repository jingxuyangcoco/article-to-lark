#!/bin/bash
# article-to-lark installer
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/<user>/article-to-lark/main/install.sh | bash
#
# Clones this skill into ~/.claude/skills/article-to-lark and checks for
# prerequisite tools. Does NOT install lark-cli itself — follow your
# organization's lark-cli setup guide separately.

set -e

REPO_URL="${REPO_URL:-https://github.com/<your-username>/article-to-lark.git}"
TARGET="$HOME/.claude/skills/article-to-lark"

echo "==> Installing article-to-lark skill"
echo "    repo:   $REPO_URL"
echo "    target: $TARGET"
echo

# 1. Skill directory
if [ -d "$TARGET" ]; then
  echo "==> $TARGET already exists — pulling latest"
  git -C "$TARGET" pull --ff-only
else
  mkdir -p "$(dirname "$TARGET")"
  git clone "$REPO_URL" "$TARGET"
fi

echo

# 2. Prerequisite checks
warn=0

check() {
  local cmd="$1"
  local hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  [ok]   $cmd"
  else
    echo "  [miss] $cmd — $hint"
    warn=1
  fi
}

echo "==> Checking prerequisites"
check lark-cli "install lark-cli (required for all Feishu operations)"
check curl     "install curl (required for image downloads)"
check bash     "install bash (should be present)"
echo

# 3. Companion skill checks
echo "==> Checking companion skills"
for skill in lark-doc lark-shared; do
  if [ -f "$HOME/.claude/skills/$skill/SKILL.md" ]; then
    echo "  [ok]   $skill"
  else
    echo "  [miss] $skill — install alongside lark-cli"
    warn=1
  fi
done
echo

# 4. Auth check (best-effort, non-fatal)
if command -v lark-cli >/dev/null 2>&1; then
  echo "==> Probing lark-cli auth (best-effort)"
  if lark-cli api GET /open-apis/authen/v1/user_info >/dev/null 2>&1; then
    echo "  [ok]   lark-cli is authenticated"
  else
    echo "  [warn] lark-cli appears not logged in — run your org's login flow"
    warn=1
  fi
  echo
fi

if [ $warn -eq 0 ]; then
  echo "==> All checks passed. Start a new Claude Code session and try:"
  echo "    把 <article-url> 转成飞书文档"
else
  echo "==> Installed with warnings. Resolve the [miss]/[warn] items above"
  echo "    before using the skill. See README.md for details."
fi
