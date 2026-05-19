---
name: applying-figma-designs
description: Figma 디자인을 코드로 변환할 때 사용하는 B Protocol (token-diet). Korean triggers — "피그마 적용해줘", "이 시안 적용해줘", "디자인 적용해줘", "이 화면 만들어줘", "이 컴포넌트 만들어줘", "node-id 가져와서 만들어줘", "이 노드 추출해줘", "디자인 반영해줘", "시안대로 만들어줘", "Figma 코드로 변환해줘" — 특히 Figma URL(figma.com/design/...)/node-id/스크린샷이 함께 첨부됐을 때. 핵심: 전체 페이지 Figma MCP 호출 금지 → 스크린샷(Vision)으로 레이아웃 잡고 단일 node-id만 Figma MCP로 추출, 시각적 검증은 사용자(PerfectPixel 등)에 위임. Storybook 동시 생성은 프로젝트 옵트인 시에만(본문 참고). Skip — Figma로 write back은 figma:figma-generate-design, 다이어그램은 figma:figma-generate-diagram, Code Connect 매핑은 figma:figma-code-connect, 라이브러리/디자인 시스템 빌드는 figma:figma-generate-library 사용.
---

# Applying Figma Designs (Token Diet Protocol)

## Overview

**부분 노드 추출 → 비전(Vision) 기반 전체 조립 → 작업 종료**

핵심 원칙: 전체 페이지 링크를 Figma MCP로 절대 읽지 않는다 (컨텍스트 폭발 및 환각 방지). 큰 레이아웃은 스크린샷(Vision)과 사용자의 명시적 수치로 잡고, 디테일한 컴포넌트는 단일 `node-id`로만 추출한다. **픽셀 단위 시안 일치 판정은 본 스킬 범위 밖** (사용자가 별도 판단).

**Storybook 동시 생성은 글로벌 기본값 OFF.** Storybook이 설치된 프로젝트에 한해 프로젝트 CLAUDE.md에 다음 한 줄로 옵트인:
> "applying-figma-designs 발화 시, 컴포넌트 파일과 함께 `.stories.tsx`를 동시 생성한다. Figma URL은 `parameters.design.url`에 임베딩한다."

이 옵트인이 없으면 글로벌 스킬은 Storybook 관련 동작을 일체 수행하지 않는다 (package.json 체크도 하지 않음).

## The B Protocol (3 Steps)

### Step 0 — 입력 분기 (Input Triage, MANDATORY)
**Step 1 진입 전에 사용자가 전달한 입력이 어떤 형태인지 분기한다.** 자료를 자의적으로 보충하지 말 것.

| 입력 형태 | 다음 단계 |
|---|---|
| Figma URL + `node-id=` 파라미터 있음 | **Step 1로 진행** |
| Figma URL은 있는데 `node-id=` 없음 (= 전체 페이지) | **즉시 중단하고 되묻기**: "전체 페이지 URL이네요. B Protocol은 토큰 폭발 방지를 위해 단일 node-id만 추출합니다. 어떤 컴포넌트/프레임의 node-id를 작업할까요?" |
| URL 없이 **스크린샷만** 첨부 | **Step 1 건너뛰고 Step 2부터** (Vision 기반 조립). 단, 새 컴포넌트가 필요한 게 명확하면 사용자에게 해당 부분의 Figma node-id를 요청한 뒤 Step 1로. |
| URL/스크린샷 모두 없음 (텍스트 설명만) | **즉시 중단하고 자료 요청**: Figma node-id 또는 화면 스크린샷 중 최소 하나 필요. |

### Step 1 — 작은 블록 생성 (Bottom-Up Component Extraction)
1. 사용자가 전달한 특정 컴포넌트의 `node-id` 링크만 Figma MCP로 호출한다. (전체 페이지 호출 절대 금지)
2. `vector`, `booleanOperation` 등 무거운 SVG/아이콘 데이터는 무시하고 lucide-react 등으로 임의 대체한다.
3. 컴포넌트 파일(`[Name].tsx`)을 생성한다. (Storybook 동시 생성은 프로젝트 옵트인 시에만 — Overview 참고)

**MCP 호출 실패 시 회복 (MANDATORY):** Figma MCP 호출이 권한/네트워크/timeout 등 어떤 이유로 실패하면, **전체 페이지 재호출이나 다른 node 추측 시도 절대 금지**. 즉시 중단하고 사용자에게 다음 둘 중 하나를 요청한다: (a) node-id가 올바른지 확인, (b) 해당 컴포넌트 스크린샷 첨부 (스크린샷이 오면 Step 1 건너뛰고 Step 2부터 진행).

### Step 2 — 큰 뼈대 잡기 (Top-Down Layout Assembly)
화면 전체 레이아웃을 구성할 때는 다음 규칙을 따른다:
1. 사용자가 첨부한 전체 화면 스크린샷(Vision)을 기반으로 구조(Flex/Grid)를 파악한다.
2. Step 1에서 생성한(혹은 이미 존재하는) 공통 컴포넌트를 재사용하여 조립한다.
3. **간격(gap)/여백(padding) 등 거시적 수치가 명시되지 않으면 추측하지 말고 사용자에게 즉시 요청한다.** AI가 임의로 px/gap 값을 채우면 작업 실패로 간주. 사용자가 텍스트로 전달한 명시 수치(예: 좌우 패딩 `px-8`, 간격 `gap-6`)만 사용한다.

### Step 3 — 시각적 검증 위임 (Verification Hand-off)
코드가 작성되면 다음 메시지를 출력하고 **즉시 종료한다**:
"작업이 완료되었습니다. 레이아웃과 디자인 디테일 검증을 위해 브라우저에서 PerfectPixel로 시안 스크린샷을 겹쳐서 확인해 주세요."

**종료 후 추가 검증 도구 호출 금지** — Playwright/webview computed-style diff 등 AI 측 시각 비교 시도 일체 금지. 검증은 사용자(인간)에게 위임된 상태이며, 모델 측 후속 작업은 종료된 것으로 간주한다.

## Example Flow (Reference)

전형적인 1회 발화 흐름:

```
User: 이 컴포넌트 만들어줘 https://figma.com/design/abc.../?node-id=42-15

Model:
"node-id `42-15`만 핀포인트 추출해서 작업하겠습니다."

[Step 0: URL에 node-id 포함됨 → Step 1 진행]
[Step 1-(1): Figma MCP get_design_context with nodeId='42:15' (전체 페이지 호출 X)]
[Step 1-(2): vector 데이터 → lucide-react 아이콘으로 대체]
[Step 1-(3): components/FooCard.tsx 생성]

Model:
"FooCard 컴포넌트를 만들었습니다. 화면 전체 배치를 위해
스크린샷을 첨부해주시거나, 컨테이너 padding/gap 수치를 알려주세요."

[사용자 스크린샷 도착]
[Step 2: Vision으로 구조 파악 → 기존 공통 컴포넌트 재사용해서 조립]

Model:
"작업이 완료되었습니다. 레이아웃과 디자인 디테일 검증을 위해
브라우저에서 PerfectPixel로 시안 스크린샷을 겹쳐서 확인해 주세요."
[Step 3: 종료. Playwright visual diff 시도 금지]
```

> **Storybook 옵트인 프로젝트:** Step 1-(3)에서 `.tsx` 옆에 `[Name].stories.tsx`를 같이 생성하고, `parameters.design.url`에 Figma 링크를 임베딩한다. 옵트인은 프로젝트 CLAUDE.md에 명시되어 있어야 한다 (Overview 참고).

핵심 행동 신호:
- Figma MCP는 **단 1회**, **단일 node-id**로만 호출
- 레이아웃 수치가 없으면 **즉시 사용자에게 요청** (추측 금지)
- 마지막에 **사용자(인간) 검증으로 위임**하고 종료 (AI 자체 검증 금지)

## Common Mistakes — 절대 피할 것
| 실수 | 방지 |
|---|---|
| 전체 페이지 링크 호출 | 토큰 폭발의 주범. 반드시 특정 `node-id` 단위로만 MCP 호출할 것 |
| node-id 없는 URL을 받고도 그냥 진행 | Step 0에서 즉시 사용자에게 node-id 되묻기 |
| MCP 호출 실패 → 전체 페이지 재호출 시도 | Step 1 fallback 준수: 호출 실패 시 사용자에게 node-id 재확인 또는 스크린샷 요청 |
| 레이아웃 수치를 임의로 추측 | 스크린샷/명시 수치 없으면 사용자에게 padding/gap 즉시 요청 (Step 2-3) |
| AI 기반 Visual Diff 시도 (Step 3 종료 후) | Playwright/webview computed-style 비교로 디자인 일치 판별 일체 금지 |
| 프로젝트 옵트인 없이 `.stories.tsx` 생성 | 글로벌 기본값은 OFF. 프로젝트 CLAUDE.md에 명시 옵트인이 있는 경우에만 생성 |