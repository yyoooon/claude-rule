# claude_rule

`~/.claude/` 개인 설정의 단일 소스. 캐노니컬은 `~/.claude/`이고 이 리포는 미러.

## 동기화 범위

| 파일/디렉토리 | sync |
|---|---|
| `~/.claude/CLAUDE.md` | ✓ |
| `~/.claude/skills/` | ✓ (rsync --delete) |
| `~/.claude/settings.json` | ✓ |
| `~/.claude/scripts/` | ✓ (rsync --delete) |
| `~/.claude/settings.local.json` | ✗ (gitignore, 머신별 오버라이드) |

PostToolUse 훅이 위 경로 편집 후 자동 미러 + commit + push.

## 새 머신 부트스트랩

```sh
git clone https://github.com/yyoooon/claude.git ~/Desktop/claude_rule
mkdir -p ~/.claude
cp ~/Desktop/claude_rule/CLAUDE.md     ~/.claude/CLAUDE.md
cp ~/Desktop/claude_rule/settings.json ~/.claude/settings.json
cp -r ~/Desktop/claude_rule/skills     ~/.claude/skills
cp -r ~/Desktop/claude_rule/scripts    ~/.claude/scripts
chmod +x ~/.claude/scripts/*.sh
```

## 주의

- `settings.json`/`scripts/`의 절대경로는 `/Users/yoon/...` 기준. 다른 머신도 username이 `yoon`이어야 그대로 동작 (아니면 `$HOME` 사용으로 교체).
- 머신 고유값(토큰, 고유 path, env)은 `~/.claude/settings.local.json`로 분리. Claude Code가 settings.json과 자동 머지.
