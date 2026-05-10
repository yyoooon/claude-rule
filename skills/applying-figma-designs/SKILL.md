---
name: applying-figma-designs
description: Use when converting Figma designs into code. Emphasizes token efficiency by completely avoiding whole-page JSON parsing. Combines Vision (screenshots) for layout and targeted Figma MCP (node-id only) for specific components. Includes Co-generation (Component + Story) for future-proofing and CDD.
---

# Applying Figma Designs (Token Diet Protocol)

## Overview

**부분 노드 추출 및 Co-generation → 비전(Vision) 기반 전체 조립 → 시각적 검증 위임**

핵심 원칙: 전체 페이지 링크를 Figma MCP로 절대 읽지 않는다 (컨텍스트 폭발 및 환각 방지). 큰 레이아웃은 스크린샷(Vision)과 사용자의 명시적 수치로 잡고, 디테일한 컴포넌트는 단일 `node-id`로만 추출한다. 시각적 디자인 일치 여부는 AI(Playwright)가 평가하지 않으며, 사용자(인간)의 전용 시각 검증 툴(PerfectPixel 등)에 위임한다.

## The B Protocol (3 Steps)

### Step 1 — 작은 블록 생성 (Bottom-Up Component Extraction)
1. 사용자가 전달한 특정 컴포넌트의 `node-id` 링크만 Figma MCP로 호출한다. (전체 페이지 호출 절대 금지)
2. `vector`, `booleanOperation` 등 무거운 SVG/아이콘 데이터는 무시하고 lucide-react 등으로 임의 대체한다.
3. **Co-generation (동시 생성) 필수**: 컴포넌트 파일(`[Name].tsx`)과 스토리북 파일(`[Name].stories.tsx`)을 반드시 한 번에 같이 생성한다. (프로젝트에 당장 Storybook이 설치되어 있지 않더라도, CDD 아키텍처와 미래 확장을 위해 파일은 무조건 생성한다.)
4. 생성된 스토리 파일에는 사용자가 전달한 Figma 링크를 `parameters.design.url`에 임베딩하여 추후 `@storybook/addon-designs`가 작동할 수 있도록 세팅한다.

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
| Co-generation 누락 | 당장 Storybook이 없더라도 컴포넌트와 Story 파일은 항상 세트로 생성할 것 |