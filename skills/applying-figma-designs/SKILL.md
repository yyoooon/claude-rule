---
name: applying-figma-designs
description: Figma 디자인을 코드로 변환할 때 사용하는 B Protocol (token-diet). Korean triggers — "피그마 적용해줘", "이 시안 적용해줘", "디자인 적용해줘", "이 화면 만들어줘", "이 컴포넌트 만들어줘", "node-id 가져와서 만들어줘", "이 노드 추출해줘", "디자인 반영해줘", "시안대로 만들어줘", "Figma 코드로 변환해줘" — 특히 Figma URL(figma.com/design/...)/node-id/스크린샷이 함께 첨부됐을 때. 핵심: 전체 페이지 Figma MCP 호출 금지 → 스크린샷(Vision)으로 레이아웃 잡고 단일 node-id만 Figma MCP로 추출, Storybook이 이미 설치된 프로젝트에서만 .stories.tsx 동시 생성. Skip — Figma로 write back은 figma:figma-generate-design, 다이어그램은 figma:figma-generate-diagram, Code Connect 매핑은 figma:figma-code-connect, 라이브러리/디자인 시스템 빌드는 figma:figma-generate-library 사용.
---

# Applying Figma Designs (Token Diet Protocol)

## Overview

**부분 노드 추출 및 Co-generation → 비전(Vision) 기반 전체 조립 → 시각적 검증 위임**

핵심 원칙: 전체 페이지 링크를 Figma MCP로 절대 읽지 않는다 (컨텍스트 폭발 및 환각 방지). 큰 레이아웃은 스크린샷(Vision)과 사용자의 명시적 수치로 잡고, 디테일한 컴포넌트는 단일 `node-id`로만 추출한다. 시각적 디자인 일치 여부는 AI(Playwright)가 평가하지 않으며, 사용자(인간)의 전용 시각 검증 툴(PerfectPixel 등)에 위임한다.

## The B Protocol (3 Steps)

### Step 1 — 작은 블록 생성 (Bottom-Up Component Extraction)
1. 사용자가 전달한 특정 컴포넌트의 `node-id` 링크만 Figma MCP로 호출한다. (전체 페이지 호출 절대 금지)
2. `vector`, `booleanOperation` 등 무거운 SVG/아이콘 데이터는 무시하고 lucide-react 등으로 임의 대체한다.
3. **Co-generation (동시 생성)** — 프로젝트에 Storybook이 설치된 경우에만, 컴포넌트 파일(`[Name].tsx`)과 함께 스토리북 파일(`[Name].stories.tsx`)을 같이 생성한다. 설치 여부 판단: `package.json` 의존성에 `@storybook/*` 또는 `storybook`이 있거나 `.storybook/` 디렉토리가 존재할 때. 설치되어 있지 않다면 `.stories.tsx`는 생성하지 않는다 (불필요한 파일 추가 금지).
4. 스토리 파일을 생성하는 경우, 사용자가 전달한 Figma 링크를 `parameters.design.url`에 임베딩하여 `@storybook/addon-designs`가 작동할 수 있도록 세팅한다.

### Step 2 — 큰 뼈대 잡기 (Top-Down Layout Assembly)
화면 전체 레이아웃을 구성할 때는 다음 규칙을 따른다:
1. 사용자가 첨부한 전체 화면 스크린샷(Vision)을 기반으로 구조(Flex/Grid)를 파악한다.
2. Step 1에서 생성한(혹은 이미 존재하는) 공통 컴포넌트를 재사용하여 조립한다.
3. 간격(gap), 여백(padding) 등 거시적 수치는 AI가 임의로 추측하지 말고, 사용자가 텍스트로 전달한 명시적 수치(예: 좌우 패딩 `px-8`, 간격 `gap-6`)를 정확히 따른다.

### Step 3 — 시각적 검증 위임 (Verification Hand-off)
코드가 작성되면 시각적 검증을 위해 아래와 같이 사용자에게 안내하고 종료한다. 
"작업이 완료되었습니다. 레이아웃과 디자인 디테일 검증을 위해 브라우저에서 PerfectPixel로 시안 스크린샷을 겹쳐서 확인해 주세요. (또는 Storybook 환경이 구축되어 있다면 `npm run storybook`으로 Figma Addon과 비교해 주세요.)"
*(주의: Playwright를 사용하여 CSS 수치나 픽셀을 대조하는 Visual Diffing 시도 절대 금지)*

## Common Mistakes — 절대 피할 것
| 실수 | 방지 |
|---|---|
| 전체 페이지 링크 호출 | 토큰 폭발의 주범. 반드시 특정 `node-id` 단위로만 MCP 호출할 것 |
| AI 기반 Visual Diff 시도 | Playwright로 캡처/Computed Style을 대조하여 디자인 일치 여부를 판별하지 말 것 |
| Storybook 미설치 프로젝트에 `.stories.tsx` 생성 | Storybook이 설치된 프로젝트에서만 Story 파일을 함께 생성할 것 (불필요한 파일 금지) |