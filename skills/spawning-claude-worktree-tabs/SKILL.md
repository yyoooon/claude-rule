---
name: spawning-claude-worktree-tabs
description: Use when the user wants to (a) spawn N parallel Claude instances in cmux tabs, each in its own git worktree branched from the current branch with a unique dev-server port (PORT=3001, 3002, ...), (b) finish those worktrees by ff-merging them back into the source branch and cleaning up tabs/branches, or (c) relaunch claude (and restart the dev server) inside an already-spawned worktree without going through spawn.sh's port-collision footgun. Spawn triggers (Korean) — "탭 N개 워크트리로 만들어줘", "병렬로 클로드 N개 띄워줘", "cmux 탭 N개에 클로드", "워크트리 N개 만들어서 클로드 띄워", "병렬 작업 N개 만들어줘". Finish/cleanup triggers (Korean) — "워크트리 정리해줘", "워크트리 다 머지하고 정리", "탭 정리해줘", "병렬 작업 마무리", "wt 브랜치 정리". Relaunch triggers (Korean) — "워크트리 클로드 다시 켜줘", "탭에 클로드 재기동", "워크트리 다시 띄워줘", "claude 죽었는데 다시 실행", "열려있는 pane들에 클로드 실행시켜줘". Skip for tmux/iTerm setups, single-tab work, or when already inside a worktree.
---

# Spawning Claude Worktree Tabs

## Overview

Spawn N cmux tabs, each in its own git worktree branched from the current branch, with copied local config (`.env*`, `.mcp*`, `.claude/settings.local.json`) and a unique dev-server `PORT` (3001, 3002, 3003 …). Each new tab `cd`s into its worktree, runs `<pm> install` + `<pm> dev` in the background (logs to `dev.log`), and launches Claude in the foreground.

**Core principle:** One bash invocation → N fully wired-up tabs with running dev servers. The user shouldn't have to copy env files, set ports, install deps, or `cd` into worktrees by hand.

## When to Use

User wants parallel Claude work on isolated branches. Common Korean phrasings:

- "탭 N개 워크트리로 만들어줘"
- "병렬로 클로드 N개 띄워줘"
- "cmux 탭 N개에 클로드 띄워줘"
- "워크트리 N개 만들고 클로드"
- "병렬 작업 N개 만들어줘"

**Skip when:** not running in cmux, already inside a linked worktree, only one tab needed, or the user uses tmux/iTerm.

## Inputs to Collect

Confirm these with the user before running:

| Input | Required | Default |
|-------|----------|---------|
| `N` (number of tabs) | yes | — |
| Suffix list | no | auto: `a, b, c, …` (then `t27, t28, …`) |
| Initial prompt per tab | no | none — fresh Claude session |

If the suffix list is shorter than `N`, the missing positions auto-fill.

## Naming Rules

- **Branch:** `wt/<source-branch>/<suffix>` — e.g., on `feat/A-page` with suffix `login` → `wt/feat/A-page/login`. The `wt/` namespace prevents ref-storage collisions (you cannot otherwise create `feat/A-page/login` while `feat/A-page` exists) and groups all worktree branches together.
- **Worktree path:** `.worktrees/<suffix>` (flat, suffix only — keeps paths short).
- **Tab title:** `<branch> :<port>` — e.g., `wt/feat/A-page/x :3001`.

## Process

Run the helper script. The agent should call it directly — don't reimplement step-by-step:

```bash
bash ~/.claude/skills/spawning-claude-worktree-tabs/spawn.sh \
  -n 3 \
  -s "login,signup,profile" \
  -p prompts.txt
```

Flags:
- `-n N` — number of tabs/panes (required)
- `-s a,b,c` — suffix list (optional)
- `-p file` — file with one initial prompt per line (optional)
- `--layout MODE` — surface placement (default `tab`):
  - `tab` — new cmux tab anchored to the current one (current behavior)
  - `split-right` — split right of the previous spawn (progressive narrowing)
  - `split-down` — split down of the previous spawn
  - `grid` — 2x2 grid (N=3 only): main TL, P1 BL, P2 TR, P3 BR
- `--no-dev` — skip auto install + dev server (just `cd && claude`)
- `--dry-run` — print the plan without creating anything

What the script does:

1. **Verifies state** — must be in cmux, in a git repo, on a non-detached branch, in the main checkout (not nested in a worktree).
2. **One-time setup** — if `.worktrees/` is not gitignored, auto-adds the line to `.gitignore` and commits it (`chore: ignore .worktrees/`). Refuses if there are other staged changes (won't fold them into the commit).
3. For each tab `i` (1..N):
   - Creates worktree `.worktrees/<suffix>` on branch `wt/<current>/<suffix>`.
   - Copies allowlisted gitignored config: `.env`, `.env.*`, `.mcp.json`, `.mcp/`, `.claude/settings.local.json`.
   - Sets/overrides `PORT=300<i>` in the worktree's `.env.local` (for apps that read PORT from dotenv; the dev server itself receives PORT as a shell env var — see step 5).
   - Spawns a new cmux tab anchored to the current tab.
   - **Auto dev** (default ON, skipped if `--no-dev` or no `package.json` "dev" script): detects the package manager from the lockfile (`pnpm` / `yarn` / `bun` / `npm`) and sends a single chained command to the new tab:
     ```
     cd <wt> && <pm> install \
       && (PORT=<port> nohup <pm> dev > dev.log 2>&1 < /dev/null & echo $!) > dev.pid \
       && claude [<prompt>]
     ```
     `dev.log` captures the dev server's stdout/stderr; `dev.pid` records its PID so `finish.sh` can stop it. If install fails, claude won't start — the user sees the error in the tab.
   - Renames the tab to `<branch> :<port>` (e.g., `wt/feat/A-page/x :3001`).
4. **Reports** the tab → branch → path → port mapping and prints `git worktree list`.

## Verification

After running:

- `git worktree list` should show the N new entries.
- The new cmux tabs should be visible at the top of the workspace, each running `<pm> install` then `claude` once install finishes (a few seconds to a minute).
- Tell the user the port mapping (e.g., `login → 3001`) so they know which dev server hits which port.
- If dev servers don't come up, point the user to `.worktrees/<suffix>/dev.log` for the dev server output.

## Post-Spawn: Browser Tab Wiring

spawn.sh 완료 직후, Chrome 9223이 떠있으면 PORT→탭ID 매핑을 자동으로 저장하고 각 세션에 전달한다.

### 절차

1. **Chrome 9223 확인**
   ```bash
   agent-browser --cdp 9223 tab list 2>&1
   ```
   응답 없으면 이 단계 전체 스킵 (조용히 넘어감 — 필수 아님).

2. **PORT → tab ID 매핑 추출**
   `tab list` 출력에서 `http://localhost:<PORT>/` 패턴으로 각 워크트리 포트와 매칭.

3. **메모리 저장** — `$PROJECT_MEMORY/reference_webview_chrome_tabs.md` 갱신
   ```markdown
   | Worktree | PORT | Tab ID |
   |---|---|---|
   | .worktrees/a | 3001 | t<N> |
   | .worktrees/b | 3002 | t<N> |
   ...
   ```
   파일이 없으면 새로 생성, 있으면 표 부분만 덮어쓴다.
   `$PROJECT_MEMORY` = `~/.claude/projects/<encoded-project-path>/memory/`

4. **각 세션에 cmux send** — spawn.sh가 반환한 surface ID 기준
   ```bash
   cmux send --surface surface:N "이 워크트리의 검증용 Chrome 탭 ID는 t<N> (PORT <PORT>)야. browser-verification 스킬 Step 2에서 tab list 없이 바로 이 ID 써줘."
   cmux send-key --surface surface:N "enter"
   ```

5. **MEMORY.md 포인터 확인** — `reference_webview_chrome_tabs.md` 항목이 없으면 추가.

### 스킵 조건

- Chrome 9223 미응답 → 전체 스킵, 사용자에게 알리지 않음
- 특정 PORT에 매칭 탭 없음 → 해당 워크트리만 스킵, 나머지 계속

### 재실행 시

`relaunch.sh` 후에도 동일하게 실행한다 — 탭 ID가 바뀔 수 있으므로.

---

## Finishing (merge + cleanup)

When the work is done, fold the worktree branches back into the source branch and tear everything down. Run from the main checkout while on the **same source branch** the worktrees were spawned from.

```bash
bash ~/.claude/skills/spawning-claude-worktree-tabs/finish.sh -s "login,signup"
bash ~/.claude/skills/spawning-claude-worktree-tabs/finish.sh --all
bash ~/.claude/skills/spawning-claude-worktree-tabs/finish.sh -s "experiment" --no-merge
```

Flags:
- `-s a,b,c` — specific suffixes (mutually exclusive with `--all`)
- `--all` — every `wt/<current-branch>/*` worktree
- `--no-merge` — skip the merge, just tear down (use when discarding work or when the merge already happened externally via PR)

Per worktree, the script:

1. **Stops the dev server** if `dev.pid` exists (kills children via `pkill -P` then the parent), and removes `dev.log` / `dev.pid`. This must come before the clean-tree check, since those files are untracked-but-not-ignored.
2. Verifies the worktree's working tree is clean (otherwise skips that one).
3. **Rebases** `wt/<source>/<suffix>` onto `<source>` — gives a linear history.
4. **Fast-forward merges** the rebased branch into `<source>` — no merge commit.
5. Removes the worktree directory.
6. Deletes the branch (`-d` if merged, `-D` if `--no-merge`).
7. Closes the cmux tab whose title starts with `<branch> `.

Skip-don't-fail policy: any single worktree that can't be finished (uncommitted changes, rebase conflict, ff-merge fails) is reported and skipped — the script keeps going on the others. The summary at the end shows finished vs skipped lists.

**Preconditions:**
- The main checkout itself must be clean (no uncommitted changes), otherwise the ff-merge would mix in unrelated edits.
- You must be on the source branch (the one used when spawning). On a different branch, the script finds no matching worktrees and exits clean.

## Post-finish integration check (parallel merge hygiene)

After `finish.sh` folds multiple worktrees into the source branch, the source can be **silently broken** even when each worktree's tree was clean. Two failure modes seen in the wild:

### 1. Untracked file orphaned inside a worktree

A file added during the worktree session but never `git add`ed sits untracked. `finish.sh`'s clean-tree check **does** detect it and skips the worktree — but if the skip is ignored or finish was never run, the file dies with the worktree teardown while **other committed files import it**. The build fails on next CI run with `Cannot find module './foo'` even though the import looks correct.

Concrete case: worktree b had `src/.../_lib/glucosePolicy.ts` untracked, while `GlucoseDayChart.tsx` (committed) imported from it. CI build fail.

**Mitigation before tearing down:**
```bash
# Scan every worktree for untracked + modified files
for w in .worktrees/*/; do
  out=$(git -C "$w" status --porcelain)
  [[ -n "$out" ]] && echo "=== $w ===" && echo "$out"
done
```

If a worktree shows untracked files, **investigate before discarding** — a forgotten `git add` is the common cause. Stage and commit (or copy to the right branch) before running `finish.sh`.

### 2. Semantic conflict after parallel merges

Each worktree's file-level diff merges cleanly (no `<<<<<<` markers, no overlapping edits), but the **combined source branch is type-inconsistent**:

- Worktree A changes a type's shape (e.g., `IHealthRecordItem.value: string | IGlucoseValue`)
- Worktree B changes callers in different files to a new prop convention (`data` → `record`)
- Worktree C adds mock data using a shape only the OLD union allowed

No file conflicts → all three rebases succeed → CI tsc fails on 30+ unrelated sites.

**Mitigation: run a unified type check on the source branch after merge, before pushing.**

```bash
git switch <source-branch>
# Pull in all the finished worktree merges, then:
npx tsc --noEmit          # TypeScript projects
# or: <pm> run typecheck / <pm> run build
```

Do NOT trust `lint pass` as a proxy — lint catches import order, not cross-file type breakage.

## Common Mistakes

- **Running from a nested worktree** — script refuses; switch to the main checkout first.
- **Suffix collision** (`.worktrees/login` already exists) — script errors and skips that suffix; pick a different one.
- **Detached HEAD** — script refuses; the source branch needs a name.
- **`PORT` already set in `.env.local`** — script overrides it; if the user wanted a custom value they must edit after.
- **Expecting `.env.local`'s `PORT` to set the Next.js dev port** — Next.js reads `PORT` from the shell env, not from `.env.local`. spawn.sh handles this by exporting `PORT=<port>` inline before `<pm> dev`, so the dev server actually binds to the right port.
- **Confusing "메인 브랜치" with `main`** — the source branch is the **current** branch where the main Claude is running, not git's `main`.
- **Dev server still running after a tab is closed manually** — closing the cmux tab doesn't kill the backgrounded dev process (it was detached via `nohup`). Use `finish.sh` (it kills via `dev.pid`), or `kill $(cat .worktrees/<s>/dev.pid)` manually.
- **Target port already bound when re-running spawn.sh** — a previous spawn's `nohup` dev server can outlive its tab. spawn.sh now preflight-checks ports 3001..3000+N: if the holder's process tree is rooted at one of `.worktrees/*/dev.pid` it's killed automatically; if it's a foreign process the script aborts with PID/command and lets you decide. Don't manually `<pm> dev` into a colliding port — the new dev silently fails (EADDRINUSE) while the stale dev keeps serving outdated code.
- **Claude died inside a tab but the worktree is still set up** — don't re-run spawn.sh (it skips existing worktrees) and don't manually `<pm> dev && claude` (port collision footgun above). Run `bash ~/.claude/skills/spawning-claude-worktree-tabs/relaunch.sh -s a,b,c` (or `--all`). It stops the old dev, restarts it with the same `PORT` from `.env.local`, finds the cmux tab by title (creates one if missing), and re-launches claude.
- **Relaunching a worktree without auditing its state first** — if you didn't spawn this worktree in the current session, `relaunch.sh` blindly resumes whatever's there. Before relaunching, run `git -C .worktrees/<s> status --porcelain` to surface untracked/modified files left over from prior sessions. A stale untracked file may be a forgotten `git add` whose imports are already committed elsewhere — see "Post-finish integration check" above.

## Red Flags

- Don't reimplement worktree creation manually if this skill applies — you'll forget the file copy or port wiring.
- Don't omit the `wt/` namespace prefix — it prevents ref collisions when the parent has slashes.
- Don't push `wt/*` branches to `origin` unless the user explicitly asks; they're scratch namespaces.
