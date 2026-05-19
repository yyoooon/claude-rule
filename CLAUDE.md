# 전역 협업 규칙 (Yangyoon)

이 파일은 모든 프로젝트에서 자동 로드됩니다. 작업 시작 전 반드시 따릅니다.

## Behavioral Guidelines

Reduce common LLM coding mistakes. Bias toward caution over speed; for trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## 커뮤니케이션 스타일

**정확하면서도 이해하기 쉽게. 줄글 금지.**

### 1. 결론 먼저
- 첫 줄에 답. 이유는 그 다음 문단/리스트로.
- ❌ "A가 B이고 B는 C라서 X..."
- ✅ "X입니다. 이유: A→B→C."

### 2. 가독성 우선 — 시각적 구조
- **빈 줄로 문단 분리**, bullet/표/번호 적극 사용.
- 5줄 이상 한 단락 금지. 쪼개거나 리스트화.
- 비교/옵션 제시는 **표**로 (장단점, before/after 등).
- 코드/명령은 별도 코드 블록.

### 3. 전문 용어는 1줄 풀이
- 처음 등장하는 약어/도메인 용어는 **괄호로 즉시 풀이**.
- 예: "HMR(저장 시 페이지 새로고침 없이 모듈만 교체)이 안 잡는 케이스가..."
- 사용자가 명백히 아는 용어(JS/TS/React 등)는 풀이 생략.

### 4. 헷갈림 신호 = 다른 각도로 재구성
- 사용자가 "이해 안 가", "쉽게 설명해줘", "헷갈리네" → **같은 표현 반복 금지**. 비유/예시/구체화로 다시.

**Why:** 정확해도 이해 못 하면 사용자가 다시 물어야 함 → 왕복 낭비. 한 번에 명확히 = 더 빠름.

---

## 프로세스 규율

### 1. 스킬/에이전트 선택 의무
작업 시작 전 적합한 스킬/에이전트를 먼저 선택한다. 직접 처리 금지. 사용 가능한 스킬은 `Skill` 툴 호출 시점에 시스템 프롬프트로 노출되니 거기서 고른다.

### 2. 로직 구현 — TDD + 분리
- **UI와 비즈니스/계산 로직 분리.** domain 함수는 React 몰라야 함 (props·hooks·JSX 의존 X). UI 레이어는 domain 함수 호출만.
- **복잡한 순수 함수**(정책 로직, domain.ts 변환, 계산식 등) 구현 시 코드 작성 **전** `superpowers:test-driven-development` 또는 `/tdd` 실행.

**Why:** 테스트 없이 구현 후 웹뷰 디버깅하면 시간 낭비. 명세 → 테스트 → 구현 순서가 효율. 로직 분리하면 테스트가 빠르고(DOM 안 띄움), UI 변경에 로직 안 깨짐.

### 3. 자동 커밋 금지
사용자가 명시적으로 요청하지 않으면 `git commit` 실행 금지. 계획 문서에 커밋 단계가 있어도 건너뛰고 사용자에게 물을 것. eslint/prettier 자동 실행은 OK.

### 4. UI 구현 — 토큰 + 컴포넌트 재사용
- **디자인 토큰 우선.** raw hex/px hardcode 금지. Tailwind class / CSS variable 등 토큰 시스템 통해.
- **기존 컴포넌트 최대한 재사용.** 공통 컴포넌트(`Button`, shadcn 등) + **같은 페이지 내 이미 만들어진 컴포넌트** 둘 다 포함.
- **Cross-page 재사용은 승격 후.** 다른 페이지 전용 컴포넌트를 그대로 import하지 말 것. 공통화 가치 검토 → 사용자 동의 → 공통 위치로 옮긴 다음 사용. 자동 cross-page import는 의도치 않은 결합 생성.
- **Rule of Three.** 같은 패턴 3번째 등장하면 추상화. 2번까지는 두 개 두는 게 잘못된 추상화보다 쌈.

### 5. UI 스택 & 컨벤션 (React + Tailwind 프로젝트 한정)

해당 스택을 쓰는 프로젝트에서만 적용. 다른 스택이면 무시.

- **Framework:** Next.js App Router 또는 동급 React 프레임워크(Remix/Vite + React Router 등) / TypeScript.
- **Styling:** Tailwind CSS. 여백·간격은 기본 4px 배수(`p-4`, `gap-6`). 디자인이 명시적으로 다른 그리드(8px·10px 단위 등)를 요구하면 그쪽이 우선.
- **UI Library:** `shadcn/ui` + `Radix UI` 베이스. Dialog/Select/DatePicker 등 a11y가 까다로운 요소는 직접 구현하지 말고 shadcn에서 가져와서 스타일만 입힐 것 (바퀴 재발명 금지).
- **CDD (Component-Driven Development):** 페이지 한 번에 짜지 말고 작은 요소부터 Bottom-Up으로 조립. 같은 페이지 내 이미 만들어진 복합 컴포넌트(`<UserCard>`, `<ProductList>` 등) 먼저 탐색 후 조립.

**Why:** 매번 같은 컨벤션을 재설명하지 않으려고 한 곳에 박음. 4px 배수/shadcn 베이스는 디자인-코드 간 마찰을 줄이는 안전한 디폴트지 절대 규칙이 아님 — 디자인이 명시적으로 다르게 요구하면 그쪽이 우선.


