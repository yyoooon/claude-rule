# 🌿 Git Workflow Rules

이 프로젝트의 Git 작업 시 아래 규칙을 무조건 준수합니다. 예외는 없습니다.

## 1. Pull — 항상 Rebase
```bash
git pull origin main --rebase
```
- `merge` 방식의 pull은 절대 사용하지 않습니다.
- 로컬 커밋이 origin/main 위에 쌓이도록 rebase로만 동기화합니다.

## 2. 브랜치 생성 — origin/main 기준
```bash
git fetch origin
git checkout -b feature/브랜치명 origin/main
```
- 로컬 `main`이 아닌 **원격 `origin/main`** 을 기준점으로 브랜치를 생성합니다.
- 브랜치 생성 전 반드시 `git fetch origin`으로 원격 상태를 최신화합니다.

## 3. 커밋 전 — Lint & Format 정리
커밋하기 전에 반드시 변경된 파일에 대해 아래 순서로 코드를 정리합니다.
```bash
npx eslint --fix 변경파일경로
npx prettier --write 변경파일경로
```
- ESLint 자동 수정으로 import 순서, 코드 규칙 위반을 정리합니다.
- Prettier로 따옴표, trailing comma, 줄 길이 등 포맷을 통일합니다.
- 수정 후 ESLint 에러가 0개인 상태에서만 커밋합니다.

## 4. 머지 — Squash Merge
```bash
git merge --squash feature/브랜치명
git commit -m "feat: 기능 설명"
```
- 일반 merge나 rebase merge는 사용하지 않습니다.
- 피처 브랜치의 모든 커밋을 하나로 압축(squash)하여 main에 단일 커밋으로 반영합니다.
- GitHub PR을 통한 머지 시에도 반드시 **"Squash and merge"** 옵션을 선택합니다.
