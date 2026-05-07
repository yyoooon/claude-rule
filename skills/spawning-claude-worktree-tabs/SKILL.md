---
name: spawning-claude-worktree-tabs
description: Use when the user wants to (a) spawn N parallel Claude instances in cmux tabs, each in its own git worktree branched from the current branch with a unique dev-server port (PORT=3001, 3002, ...), or (b) finish those worktrees by ff-merging them back into the source branch and cleaning up tabs/branches. Spawn triggers (Korean) — "탭 N개 워크트리로 만들어줘", "병렬로 클로드 N개 띄워줘", "cmux 탭 N개에 클로드", "워크트리 N개 만들어서 클로드 띄워", "병렬 작업 N개 만들어줘". Finish/cleanup triggers (Korean) — "워크트리 정리해줘", "워크트리 다 머지하고 정리", "탭 정리해줘", "병렬 작업 마무리", "wt 브랜치 정리". Skip for tmux/iTerm setups, single-tab work, or when already inside a worktree.
---

# Spawning Claude Worktree Tabs

## Overview

Spawn N cmux tabs, each in its own git worktree branched from the current branch, with copied local config (`.env*`, `.mcp*`, `.claude/settings.local.json`) and a unique dev-server `PORT` (3001, 3002, 3003 …). Each new tab `cd`s into its worktree and launches Claude.

**Core principle:** One bash invocation → N fully wired-up tabs. The user shouldn't have to copy env files, set ports, or `cd` into worktrees by hand.

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
- `-n N` — number of tabs (required)
- `-s a,b,c` — suffix list (optional)
- `-p file` — file with one initial prompt per line (optional)
- `--dry-run` — print the plan without creating anything

What the script does:

1. **Verifies state** — must be in cmux, in a git repo, on a non-detached branch, in the main checkout (not nested in a worktree).
2. **One-time setup** — if `.worktrees/` is not gitignored, auto-adds the line to `.gitignore` and commits it (`chore: ignore .worktrees/`). Refuses if there are other staged changes (won't fold them into the commit).
3. For each tab `i` (1..N):
   - Creates worktree `.worktrees/<suffix>` on branch `wt/<current>/<suffix>`.
   - Copies allowlisted gitignored config: `.env`, `.env.*`, `.mcp.json`, `.mcp/`, `.claude/settings.local.json`.
   - Sets/overrides `PORT=300<i>` in the worktree's `.env.local`.
   - Spawns a new cmux tab anchored to the current tab.
   - Sends `cd <worktree-abs-path> && claude [<prompt>]` to the new tab.
   - Renames the tab to `<branch> :<port>` (e.g., `wt/feat/A-page/x :3001`).
4. **Reports** the tab → branch → path → port mapping and prints `git worktree list`.

## Verification

After running:

- `git worktree list` should show the N new entries.
- The new cmux tabs should be visible at the top of the workspace, each focused on its own shell with `claude` running.
- Tell the user the port mapping (e.g., `login → 3001`) so they know which dev server hits which port.

Don't auto-start dev servers — that's the user's call.

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

1. Verifies the worktree's working tree is clean (otherwise skips that one).
2. **Rebases** `wt/<source>/<suffix>` onto `<source>` — gives a linear history.
3. **Fast-forward merges** the rebased branch into `<source>` — no merge commit.
4. Removes the worktree directory.
5. Deletes the branch (`-d` if merged, `-D` if `--no-merge`).
6. Closes the cmux tab whose title starts with `<branch> `.

Skip-don't-fail policy: any single worktree that can't be finished (uncommitted changes, rebase conflict, ff-merge fails) is reported and skipped — the script keeps going on the others. The summary at the end shows finished vs skipped lists.

**Preconditions:**
- The main checkout itself must be clean (no uncommitted changes), otherwise the ff-merge would mix in unrelated edits.
- You must be on the source branch (the one used when spawning). On a different branch, the script finds no matching worktrees and exits clean.

## Common Mistakes

- **Running from a nested worktree** — script refuses; switch to the main checkout first.
- **Suffix collision** (`.worktrees/login` already exists) — script errors and skips that suffix; pick a different one.
- **Detached HEAD** — script refuses; the source branch needs a name.
- **`PORT` already set in `.env.local`** — script overrides it; if the user wanted a custom value they must edit after.
- **Confusing "메인 브랜치" with `main`** — the source branch is the **current** branch where the main Claude is running, not git's `main`.

## Red Flags

- Don't reimplement worktree creation manually if this skill applies — you'll forget the file copy or port wiring.
- Don't omit the `wt/` namespace prefix — it prevents ref collisions when the parent has slashes.
- Don't push `wt/*` branches to `origin` unless the user explicitly asks; they're scratch namespaces.
