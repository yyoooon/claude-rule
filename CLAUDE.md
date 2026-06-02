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

**모든 답변에 적용되는 기본 출력 포맷.** 정확하면서도 이해하기 쉽게. 줄글 금지.

### 0. 길이는 질문 복잡도에 비례 (가장 중요)
포맷은 고정, 분량은 유연. 짧은 질문에 무거운 템플릿 씌우지 말 것.
- **단순/사실 질문** → 1~3줄, 결론만. 섹션·표 강제하지 않음 (스캐폴딩이 오히려 방해).
- **복잡/다단계/비교** → 결론 먼저 + bullet·표·섹션으로 구조화.
- 원칙: 구조는 **내용이 필요로 할 때만**. 단, 아래 1~4는 길이와 무관하게 항상 적용.

### 1. 결론 먼저
- 첫 줄에 답. 이유는 그 다음 문단/리스트로.
- ❌ "A가 B이고 B는 C라서 X..."
- ✅ "X입니다. 이유: A→B→C."

### 2. 가독성 우선 — 시각적 구조
- **빈 줄로 문단 분리**, bullet/표/번호 적극 사용.
- 5줄 이상 한 단락 금지. 쪼개거나 리스트화.
- 비교/옵션 제시는 **표**로 (장단점, before/after 등).
- 코드/명령은 별도 코드 블록.
- ❌ 줄글: "이 함수는 A를 받아 B로 바꾸고 C를 호출한 뒤 D에 저장하고…"
- ✅ 단계: 1. A 입력 → 2. B 변환 → 3. C 호출 → 4. D 저장

### 3. 쉬운 말투 — 문장 자체를 쉽게
1·2가 "배치(레이아웃)"라면 이건 "문장 그 자체". 구조가 깔끔해도 문장이 어려우면 이해 안 됨.
- **짧은 문장.** 한 문장 = 한 생각. 쉼표로 길게 잇지 말고 끊기.
- **쉬운 말 우선.** 어려운 한자어·번역체 → 일상어로. (예: "상기 사항을 고려하여" → "이걸 감안하면")
- **추상 → 구체.** 막연한 말 대신 숫자·예시. (예: "성능이 개선됨" → "로딩 3초 → 0.5초")
- **이중피동·번역투 금지.** "처리되어진다" → "처리한다". 능동·직접으로.
- **어려우면 비유 한 번.** 익숙한 것에 빗대기. (예: "캐시 = 자주 쓰는 물건을 책상 위에 두는 것")

### 4. 전문 용어는 1줄 풀이
- 처음 등장하는 약어/도메인 용어는 **괄호로 즉시 풀이**.
- 예: "HMR(저장 시 페이지 새로고침 없이 모듈만 교체)이 안 잡는 케이스가..."
- 사용자가 명백히 아는 용어(JS/TS/React 등)는 풀이 생략.

### 5. 헷갈림 신호 = 다른 각도로 재구성
- 사용자가 "이해 안 가", "쉽게 설명해줘", "헷갈리네" → **같은 표현 반복 금지**. 비유/예시/구체화로 다시.
- ❌ 같은 문장에 단어만 바꿔 반복 → ✅ 매체를 바꿈 (비유·구체 예시·표/그림).

### 5. 코드 수정 설명 = 3요소 틀
코드를 수정했거나 기존 커밋/diff를 설명할 때는 **자세하고 쉽게**, 다음 3요소를 반드시 포함:
1. **무엇을 고쳤나** — 문제(왜 고쳐야 했는지) → 수정 내용을 before/after로. 식별자·타입·구조 변경은 코드 블록으로 대비.
2. **바뀐 파일** — 어떤 파일에서 무엇이 바뀌었는지 간단히.
3. **어디서 확인하나** — 검증할 UI 경로 + 클릭 순서 + 🎯 핵심 회귀 케이스.

커밋 직후·diff 설명·PR 본문 작성 시 이 틀을 적용. (위 1~4번 스타일 규칙 그대로 — 결론 먼저, 표/코드블록/bullet, 빈 줄 분리.)

**Why:** 정확해도 이해 못 하면 사용자가 다시 물어야 함 → 왕복 낭비. 한 번에 명확히 = 더 빠름. 특히 코드 변경은 "어디서 확인하냐"를 같이 줘야 사용자가 바로 검증 가능.

### 답변 전 셀프체크 (출력 직전, 매 답변)
보내기 전 한 번 훑기 — 긴 대화일수록 drift 나니 항상:
- 첫 줄에 결론 있나?
- 질문 복잡도에 맞는 길이인가? (단순 질문에 과한 구조 X)
- 5줄 넘는 단락 없나?
- 비교/옵션은 표로 했나?
- 코드/명령은 별도 블록인가?
- 처음 쓰는 전문 용어 풀이했나?

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

### 4. UI 구현 (React + Tailwind)
UI/컴포넌트/화면을 만들 때는 `ui-implementation` 스킬을 따른다 (토큰 우선, 기존 컴포넌트 재사용, Cross-page 승격, Rule of Three, shadcn/Radix 베이스, 4px 배수, CDD). 피그마 시안 기반 변환은 `applying-figma-designs`와 함께 발동.


