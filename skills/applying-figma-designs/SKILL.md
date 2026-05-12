---
name: applying-figma-designs
description: Figma 디자인을 코드로 변환할 때 사용하는 B Protocol (token-diet). Korean triggers — "피그마 적용해줘", "이 시안 적용해줘", "디자인 적용해줘", "이 화면 만들어줘", "이 컴포넌트 만들어줘", "node-id 가져와서 만들어줘", "이 노드 추출해줘", "디자인 반영해줘", "시안대로 만들어줘", "Figma 코드로 변환해줘" — 특히 Figma URL(figma.com/design/...)/node-id/스크린샷이 함께 첨부됐을 때. 핵심: 전체 페이지 Figma MCP 호출 금지 → 스크린샷(Vision)으로 레이아웃 잡고 단일 node-id만 Figma MCP로 추출, 시각적 검증은 사용자(PerfectPixel 등)에 위임. Storybook 동시 생성은 글로벌 기본값 OFF — Storybook 쓰는 프로젝트는 프로젝트 CLAUDE.md에 "Figma 작업 시 .stories.tsx 동시 생성" 한 줄로 옵트인. Skip — Figma로 write back은 figma:figma-generate-design, 다이어그램은 figma:figma-generate-diagram, Code Connect 매핑은 figma:figma-code-connect, 라이브러리/디자인 시스템 빌드는 figma:figma-generate-library 사용.
---

# Applying Figma Designs (Token Diet Protocol)

## Overview

**부분 노드 추출 → 비전(Vision) 기반 전체 조립 → 시각적 검증 위임**

핵심 원칙: 전체 페이지 링크를 Figma MCP로 절대 읽지 않는다 (컨텍스트 폭발 및 환각 방지). 큰 레이아웃은 스크린샷(Vision)과 사용자의 명시적 수치로 잡고, 디테일한 컴포넌트는 단일 `node-id`로만 추출한다. 시각적 디자인 일치 여부는 AI(Playwright)가 평가하지 않으며, 사용자(인간)의 전용 시각 검증 툴(PerfectPixel 등)에 위임한다.

**Storybook 동시 생성은 글로벌 기본값 OFF.** Storybook이 설치된 프로젝트에 한해 프로젝트 CLAUDE.md에 다음 한 줄로 옵트인:
> "applying-figma-designs 발화 시, 컴포넌트 파일과 함께 `.stories.tsx`를 동시 생성한다. Figma URL은 `parameters.design.url`에 임베딩한다."

이 옵트인이 없으면 글로벌 스킬은 Storybook 관련 동작을 일체 수행하지 않는다 (package.json 체크도 하지 않음).

## The B Protocol (3 Steps)

### Step 0 — 입력 검증 (URL Sanity Check, MANDATORY)
**Step 1 진입 전에 먼저 검증한다.**
1. 사용자가 전달한 Figma URL에 `node-id=` 쿼리 파라미터가 **있는지** 확인한다.
2. **없으면 즉시 중단하고 사용자에게 되묻는다**: "전체 페이지 URL이네요. B Protocol은 토큰 폭발 방지를 위해 단일 node-id만 추출합니다. 어떤 컴포넌트/프레임의 node-id를 작업할까요?"
3. node-id가 있으면 Step 1로 진행.

### Step 1 — 작은 블록 생성 (Bottom-Up Component Extraction)
1. 사용자가 전달한 특정 컴포넌트의 `node-id` 링크만 Figma MCP로 호출한다. (전체 페이지 호출 절대 금지)
2. `vector`, `booleanOperation` 등 무거운 SVG/아이콘 데이터는 무시하고 lucide-react 등으로 임의 대체한다.
3. 컴포넌트 파일(`[Name].tsx`)을 생성한다. (Storybook 동시 생성은 프로젝트 옵트인 시에만 — Overview 참고)

### Step 2 — 큰 뼈대 잡기 (Top-Down Layout Assembly)
화면 전체 레이아웃을 구성할 때는 다음 규칙을 따른다:
1. 사용자가 첨부한 전체 화면 스크린샷(Vision)을 기반으로 구조(Flex/Grid)를 파악한다.
2. Step 1에서 생성한(혹은 이미 존재하는) 공통 컴포넌트를 재사용하여 조립한다.
3. 간격(gap), 여백(padding) 등 거시적 수치는 AI가 임의로 추측하지 말고, 사용자가 텍스트로 전달한 명시적 수치(예: 좌우 패딩 `px-8`, 간격 `gap-6`)를 정확히 따른다.

### Step 3 — 시각적 검증 위임 (Verification Hand-off)
코드가 작성되면 시각적 검증을 위해 아래와 같이 사용자에게 안내하고 종료한다. 
"작업이 완료되었습니다. 레이아웃과 디자인 디테일 검증을 위해 브라우저에서 PerfectPixel로 시안 스크린샷을 겹쳐서 확인해 주세요. (또는 Storybook 환경이 구축되어 있다면 `npm run storybook`으로 Figma Addon과 비교해 주세요.)"
*(주의: Playwright를 사용하여 CSS 수치나 픽셀을 대조하는 Visual Diffing 시도 절대 금지)*

## Example Flow (Reference)

전형적인 1회 발화 흐름:

```
User: 이 컴포넌트 만들어줘 https://figma.com/design/abc.../?node-id=42-15

Model:
"node-id `42-15`만 핀포인트 추출해서 작업하겠습니다."

[Step 0: URL에 node-id 포함됨 → 통과]
[Step 1.1: Read package.json → @storybook 의존성 없음 → stories.tsx 생성 스킵]
[Step 1.2: Figma MCP get_design_context with nodeId='42:15' (전체 페이지 호출 X)]
[Step 1.3: vector 데이터 → lucide-react 아이콘으로 대체]
[Step 1.4: components/FooCard.tsx 생성 (Storybook 없음 → .stories.tsx 미생성)]

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

핵심 행동 신호:
- Figma MCP는 **단 1회**, **단일 node-id**로만 호출
- 레이아웃 수치가 없으면 **즉시 사용자에게 요청** (추측 금지)
- 마지막에 **사용자(인간) 검증으로 위임**하고 종료 (AI 자체 검증 금지)

## Common Mistakes — 절대 피할 것
| 실수 | 방지 |
|---|---|
| 전체 페이지 링크 호출 | 토큰 폭발의 주범. 반드시 특정 `node-id` 단위로만 MCP 호출할 것 |
| node-id 없는 URL을 받고도 그냥 진행 | Step 0에서 즉시 사용자에게 node-id 되묻기 |
| Storybook 설치 여부 확인 없이 .stories.tsx 생성 | Step 1.1에서 package.json/.storybook을 먼저 Read |
| 레이아웃 수치를 임의로 추측 | 스크린샷 없으면 사용자에게 padding/gap 명시 수치 요청 |
| AI 기반 Visual Diff 시도 | Playwright로 캡처/Computed Style을 대조하여 디자인 일치 여부를 판별하지 말 것 |
| Storybook 미설치 프로젝트에 `.stories.tsx` 생성 | Storybook이 설치된 프로젝트에서만 Story 파일을 함께 생성할 것 (불필요한 파일 금지) |