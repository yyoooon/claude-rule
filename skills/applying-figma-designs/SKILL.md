---
name: applying-figma-designs
description: Use when a Figma URL is given with implementation intent ("적용해줘", "구현해줘", "리디자인", "피그마랑 똑같이", "픽셀 단위", "1:1"), or when matching a Figma design with high fidelity (multiple variants, precise spec match). Skip for fuzzy "분위기/느낌으로 비슷하게" tone — that path uses a lighter fallback.
---

# Applying Figma Designs

## Overview

**정답 먼저(get_design_context) → 구현 → 자체 검증(Playwright) → 사용자 마지막 확인.**

핵심 원칙: 측정값을 신뢰하기 전에 정답(design_context spec)을 먼저 확보한다. `variable_defs`는 평면 토큰 리스트일 뿐 — 어느 토큰이 어느 요소에 매핑되는지 알 수 없다. 추측 기반으로 시작하면 사용자 피드백 라운드가 누적되어 결국 정밀 모드보다 비싸진다.

**권장 런타임:** Sonnet 4.6. 이 스킬은 정해진 4단계 프로토콜을 충실히 따르는 게 핵심이라 창의적 판단력보다 속도·정확한 병렬 호출이 중요. Opus는 spec이 모호하거나 레이아웃 디버깅 깊게 들어가야 할 때만. 단일 페이지 단위 작업이면 서브에이전트 불필요 — 메인 세션에서 진행 (인터랙티브 spot fix 이점이 컨텍스트 절약보다 큼).

## When to Use

| 톤 | 패턴 | 신호 |
|---|---|---|
| **B (디폴트)** | 정밀 4단계 | Figma URL + "적용/구현/리디자인", "피그마랑 똑같이/1:1/픽셀 단위", variant 여러 개 |
| **A (fallback)** | 가벼운 자료 → 피드백 → 정밀 | "분위기/느낌으로 비슷하게", 단일 mock-up만, 토큰 자체가 없는 신규 컴포넌트 |

사용자가 "정확하게"라고 명시하지 않아도 **Figma URL + 적용 톤이면 B 디폴트.**

## The B Protocol (4 Steps)

### Step 1 — Spec 수집 (Figma side)

**1-0. URL 파싱**
- `figma.com/design/:fileKey/:fileName?node-id=42-1234` → `fileKey=:fileKey`, `nodeId=42:1234` (하이픈→콜론 변환 필수)
- `branch/:branchKey/...`이면 `branchKey`를 fileKey로 사용
- `figma.com/board/...`은 FigJam → 이 스킬 적용 대상 아님 (`get_figjam` 사용)

**1-1.** `get_metadata` 1콜로 노드 트리 받기.

**1-2. 핵심 sub-node 5~8개 추출 — 선택 기준**
- **시각적 region 단위로**: 헤더 / 메인 콘텐츠 블록 / 카드 / 폼 / 푸터 / 모달 등 화면을 자연스럽게 끊는 단위. depth가 아니라 "사용자 눈에 한 덩어리로 보이는가"가 기준.
- **반복 패턴은 1개만**: 리스트 row 5개면 첫 row만. 동일 컴포넌트 variant가 여러 개면 대표 1개 + 명시적 차이 있는 것만 추가.
- **variant / state 다른 컴포넌트는 별도**: `Button/primary` vs `Button/secondary`는 둘 다 추출 (스펙이 다름).
- **8개 넘으면 중복 가능성**: 비슷한 region 합치거나 가장 복잡한 것 우선.
- **3개 미만이면 재검토**: metadata가 평탄할 가능성 — depth 한 단계 더 들어가서 보라.

**1-3.** 다음 3종을 **병렬**로 호출:
- `get_screenshot` 전체 페이지 (시각 레퍼런스 1장)
- `get_design_context` × 각 sub-node ID (`excludeScreenshot: true`) — 정답 명세
- `get_variable_defs` (토큰 매핑 사전)

총 비용 ~30–50KB. 풀 frame 한 번(100KB+)보다 가볍고 정확.

### Step 2 — 구현

- 각 region의 design_context 스펙 기반 코드 작성
- variable_defs는 사전(dict)으로 활용 → Figma 토큰 → 프로젝트 토큰(Tailwind 등) 매핑
- 기존 컴포넌트(`Button`, shadcn 등) 우선 재사용
- **모든 수치는 design_context에서만**. variable_defs로 수치 추측 금지

### Step 3 — 자체 검증 (Playwright)

1. `browser_navigate` → `browser_resize` (모바일이면 360×800)
2. `browser_take_screenshot` 1장 — 화면 깨짐 sanity check
3. `browser_evaluate` — 핵심 요소 computed style 일괄 추출 (fontSize / lineHeight / fontWeight / letterSpacing / color / padding / gap)
4. design_context 스펙과 diff → 차이만 수정 → 재측정
5. **"diff 0" 판정 기준** (이 임계값 만족하면 통과):

| 속성 | 허용 오차 | 비고 |
|---|---|---|
| `fontSize` / `lineHeight` / `letterSpacing` | **±0.5px** | 브라우저 반올림 / 서브픽셀 렌더링 마진 |
| `padding` / `margin` / `gap` / `width` / `height` | **0px (정확 일치)** | 레이아웃 수치는 타협 없음 |
| `color` / `background-color` / `border-color` | **정확 일치** (rgb/oklch 정규화 후) | 1단위 차이도 fail — 토큰 매핑 잘못된 신호 |
| `fontWeight` | **정확 일치** | 400 vs 500은 다른 폰트 |
| `borderRadius` | **0px (정확 일치)** | |
| `boxShadow` | offset/blur ±1px, color 정확 | 합성값이라 약간 관대 |

6. 위 기준으로 diff 0이 될 때까지 2~3회 자동 반복 (사용자 안 깨움). 3회 넘게 안 맞으면 stop — design_context를 잘못 읽었거나 토큰 매핑이 빠졌을 가능성, 사용자에게 보고.

### Step 4 — 사용자 보고

- 1줄 요약 + 스크린샷 1장 + 적용 변경사항 리스트
- "다른 데 짚어주세요" — 이 시점에서 거의 안 나와야 정상

## Spot Fix (사용자 피드백 받았을 때만)

전체 재실행 ❌. **포인트 수정만**:

1. 해당 sub-node ID로 `get_design_context` (`excludeScreenshot: true`) — 1콜
2. 코드 수정
3. `browser_evaluate`로 그 요소만 재측정 → 검증

## A Workflow (fuzzy 톤일 때만)

1. `get_screenshot` + `get_variable_defs` + `get_metadata` (가벼움)
2. 1차 적용 → "피그마 대비 다른 점 짚어주세요" 보고
3. 짚어준 부분만 Spot fix 절차로 처리

## 사용자 메시지 표준 형식 (B 트리거)

```
[Figma URL] (variant들 있으면 여러 개)
[페이지 라우트] (예: /care-plan)
[특이사항] (모바일 viewport, dev 서버 포트 등)
→ 적용해줘
```

추가 지시 없어도 위 4단계 자동 실행.

## Common Mistakes — 절대 피할 것

| 실수 | 발생 패턴 | 방지 |
|---|---|---|
| 추측 기반 측정 도장 | variable_defs로 코드 짠 후 Playwright "맞다" | design_context 없이 측정값 신뢰 금지 |
| 풀 frame design_context | 부모 frame 통째로 호출 → 100KB+ 깨짐 | 항상 sub-node ID 지정 + `excludeScreenshot: true` |
| 사용자 일을 측정으로 대체 | 정답 없이 측정 5회 | 정답 먼저 확보 후 측정 |
| Spot fix에 풀 워크플로 | 작은 피드백에 4단계 재실행 | 1콜 design_context로 포인트만 |

## Red Flags — STOP and Restart

이런 생각 들면 멈추고 정답(sub-node design_context) 먼저 확보:

- "variable_defs만 보고 토큰 매핑하면 될 것 같다"
- "design_context는 풀 frame으로 한 번에"
- "Playwright 측정값이 일관되니 OK"
- "사용자한테 먼저 다른 점 짚어달라고 하자" (B 톤일 때)

## Why

- `variable_defs`는 평면 토큰 리스트 — 어느 토큰이 어느 요소에 매핑되는지 정보 없음. 추측하면 빗나감
- SVG 아이콘 path / asset URL은 `get_design_context`에만 노출 → A 가도 결국 한 라운드 더 들어감
- A 패턴 라운드 2~3회 누적 토큰 > B 1회 (region별 병렬 design_context = 30~50KB)
- 검증된 케이스: 2026-04-29 onboarding, 2026-05-05 /care-plan — variable_defs만으로 추측 시작 → 사용자 피드백 라운드 4회 이상 발생
