---
name: code-review
description: Use when reviewing PR/branch/commit diffs as a reviewer ("코드 리뷰", "diff 봐줘", "@diff", "PR 리뷰", "리뷰해줘", "검토해줘", "이거 리뷰", "변경사항 봐줘", "머지 직전 점검") — applies project rules (nextjs-rules.mdc + toss-frontend-rules.mdc), every comment cites specific rule items via [rule-ref], decides Approve / Request Changes / Comment. Skip for own-code self-review during implementation, security-only reviews, type-error/lint fixes.
---

# Code Review

## Overview

PR/브랜치/커밋 diff를 **프로젝트 룰 기준으로** 평가하는 리뷰어 역할. 코멘트마다 어느 룰의 어떤 항목을 근거로 하는지 `[rule-ref]`로 명시.

**참조 룰:**
- 구현/코딩 규율 (early return, Tailwind, a11y, 네이밍, 타입 등) — 본문 체크리스트(아래)가 단일 진실
- 설계 원칙 (Readability / Predictability / Cohesion / Coupling) — 요약은 본문에, **상세 원문은 `references/toss-frontend-rules.md`** (스킬 디렉토리 기준)

체크리스트 요약은 본문에 두고, **토스 룰 항목 정확히 인용 시 `references/toss-frontend-rules.md`를 `Read`로 펼쳐 원문 확인 후 코멘트에 삽입**.

**권장 런타임:** Sonnet 4.6 디폴트. 룰 항목 매핑·코멘트 템플릿 충실 작성이 핵심이라 절차 안정성이 중요. Opus 4.7은 (1) 큰 PR(50+ 파일/1000+ 줄) (2) 추상화 정도·결합도 같은 **미묘한 설계 판단** 필요 시. Haiku 비추 — 룰 ↔ 코드 매핑·근거 작성 추론 부족.

**실행 위치:** 서브에이전트 가치 있음. 리뷰는 독립적 read-only 작업이라 메인 컨텍스트 보호 효과 큼. 결과만 메인이 받음. 메인 세션 직접 진행은 (1) 작은 diff (2) 즉시 토론·spot fix 의도 있을 때만.

## When to Use

- "코드 리뷰", "diff 봐줘", "PR 리뷰", "검토해줘" 같은 **명시적 리뷰 요청**
- @diff/@branch 컨텍스트 첨부와 함께 평가 요청 들어올 때
- 머지 직전 점검

## When NOT to Use

- 본인이 방금 작성한 코드의 자가 검토 → `superpowers:requesting-code-review` (별도 역할)
- 보안 특화 리뷰 → 내장 `/security-review`
- 단순 타입 에러/lint 픽스 — 룰 매핑 가치 없음

## Workflow (6 단계)

### 1. 변경 범위 파악
- 무엇을·왜 바꿨는지(요구사항/문제)와 영향 범위(페이지/도메인/공용 컴포넌트) 정리
- 위험도 높은 부분(인증/권한/결제/데이터 정합성/폼/테이블/필터/페이징) 표시

### 2. 동작/요구사항 충족 여부 확인
- 누락된 케이스 없는지
- 엣지 케이스(빈 값/로딩/에러/권한 없음/데이터 없음) 처리 확인

### 3. "구현 품질" 체크
아래 체크리스트 훑어서 위반 항목 표시. (별도 reference 없이 본문 체크리스트가 단일 진실)

### 4. "설계 품질" 체크 (토스 4원칙)
**Readability → Predictability → Cohesion → Coupling 순서.** 위반 의심 시 `references/toss-frontend-rules.md` Read로 원문 확인 후 인용.

### 5. 코멘트 작성
- Must Fix / Suggestion / Question 으로 구분
- 가능하면 개선 방향 + 짧은 예시 제시
- **모든 코멘트에 `[rule-ref]` 명시** (예: `toss-frontend-rules: Naming Magic Numbers`)

### 6. 결론
Approve / Request Changes / Comment 로 명확히 표시.

## 체크리스트 (요약)

### 구현/코딩 규율

- **요구사항 준수**: 정확히 충족, 범위 넘는 변경 과도하지 않음
- **완성도**: TODO/placeholder 없이 동작 완결
- **가독성 우선**: 성능보다 읽기 쉬운 코드
- **DRY**: 중복 제거 적절(과도한 추상화 금지), 동일 로직 한 곳
- **early return**: 복잡 분기 단순화
- **Tailwind 사용**: 스타일은 Tailwind class만, 불필요 CSS 없음
- **클래스 조건 처리**: 가능하면 삼항 대신 `class:` 패턴
- **이벤트 핸들러 네이밍**: `handleClick`, `handleKeyDown` 등 handle-prefix
- **접근성(a11y)**: 상호작용 요소에 `aria-label` / `tabIndex` / `onKeyDown`
- **const + 타입**: `const fn = () => {}` + 타입 정의로 의도 드러냄
- **정직한 리뷰**: 확실하지 않으면 "모르겠다/확인 필요" 명시 (추측 금지)

### 설계 원칙 (Toss frontend rules — 상세는 `references/toss-frontend-rules.md`)

#### Readability
- **Naming Magic Numbers**: 매직 넘버 → 의미 있는 상수
- **Abstracting Implementation Details**: 복잡 로직 → 전용 컴포넌트/HOC로 격리
- **Separating Code Paths**: 조건 따라 UI/로직 크게 다르면 컴포넌트 분리
- **Simplifying Ternary Operators**: 중첩/복잡 삼항 → if/else 또는 IIFE
- **Reducing Eye Movement**: 단순 로직은 콜로케이트
- **Naming Complex Conditions**: 복잡 조건 → 의미 있는 boolean 변수

#### Predictability
- **Standardizing Return Types**: 유사 훅/함수 일관 반환 타입
- **Single Responsibility / Hidden Side Effects**: 시그니처에서 안 드러나는 부수효과 X
- **Unique & Descriptive Names**: 래퍼/유틸 함수명 동작이 드러남

#### Cohesion
- **Form Cohesion**: 폼 검증/구조 field-level vs form-level 적절
- **Organizing by Feature/Domain**: 기능/도메인 기준 모임
- **Relating Constants to Logic**: 상수가 관련 로직 근처 또는 이름으로 연결

#### Coupling
- **Avoid Premature Abstraction**: 곧 diverge 가능하면 섣부른 추상화 X
- **Scoping State Management**: 상태 범위 적정, 과도하게 넓지 않음
- **Composition over Props Drilling**: 합성으로 결합도 낮춤

## 리뷰 코멘트 템플릿

### 요약
- **변경 목적**:
- **핵심 변경점(1~3개)**:
- **영향 범위**:
- **리스크**: (낮음/중간/높음) — 근거:

### Must Fix (차단)
- **[rule-ref]**: (문제 요약)
  - **근거**: (왜 문제인지, 어떤 버그/유지보수 위험)
  - **제안**: (구체적 수정 방향)

### Suggestion (권장)
- **[rule-ref]**: (개선 아이디어)
  - **이유**:
  - **대안**:

### Question (확인)
- **[rule-ref]**: (질문)
  - **확인 필요 이유**:

### 결론
- **결정**: Approve / Request Changes / Comment
- **추가 확인사항**: (있다면)

## Common Mistakes

| 실수 | 발생 패턴 | 방지 |
|---|---|---|
| 코멘트에 룰 근거 누락 | "이거 좀 이상함" 정도로 끝냄 | `[rule-ref]` 형식 의무 — 어느 룰 어떤 항목인지 명시 |
| 추측으로 단정 | 코드 의도 모르면서 "버그임" 단정 | 모르면 Question 섹션. "확인 필요" 명시. 추측 금지 |
| 범위 초과 변경 안 짚음 | 요구사항 외 리팩터를 그냥 넘김 | Step 1에서 요구사항 비교 후 over-scope 표시 |
| 과도한 추상화 vs 적절한 추상화 헷갈림 | DRY 일률 권고 | `Avoid Premature Abstraction` 적용 — 곧 diverge 가능하면 두는 게 쌈 |
| Approve 남발 | 별 문제 없어 보이면 무조건 Approve | Question 있으면 **Comment**, 머지 차단 사유 있으면 **Request Changes** |
| 룰 원문 안 보고 인용 | 기억으로 항목명만 적음 | 토스 룰 인용 전 `references/toss-frontend-rules.md` `Read`로 원문 확인 |
