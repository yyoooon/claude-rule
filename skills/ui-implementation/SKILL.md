---
name: ui-implementation
description: React + Tailwind UI를 만들 때 따르는 토큰·컴포넌트 재사용·스택 컨벤션. Korean triggers — "UI 만들어줘", "화면 만들어줘", "페이지 만들어줘", "컴포넌트 만들어줘", "이 컴포넌트 짜줘", "버튼/모달/다이얼로그/폼 만들어줘", "리스트/카드/테이블 만들어줘", "스타일 입혀줘", "Tailwind로 만들어줘", "shadcn으로 만들어줘", "레이아웃 잡아줘" — 피그마 시안 없이 코드/설명만으로 UI를 구현할 때도 포함. 핵심: 디자인 토큰 우선(raw hex/px 금지), 기존 컴포넌트 최대 재사용, Cross-page import는 승격 후, Rule of Three, shadcn/Radix 베이스, 4px 배수 간격, CDD(Bottom-Up 조립). 적용 대상은 React + Tailwind 스택뿐 — 다른 스택이면 무시. Skip — Figma 시안/URL/node-id 기반 변환 절차는 applying-figma-designs 사용(이 스킬과 함께 발동 권장).
---

# UI Implementation (React + Tailwind)

해당 스택을 쓰는 프로젝트에서만 적용. 다른 스택이면 무시.

## 1. 토큰 + 컴포넌트 재사용

- **디자인 토큰 우선.** raw hex/px hardcode 금지. Tailwind class / CSS variable 등 토큰 시스템 통해.
- **기존 컴포넌트 최대한 재사용.** 공통 컴포넌트(`Button`, shadcn 등) + **같은 페이지 내 이미 만들어진 컴포넌트** 둘 다 포함.
- **Cross-page 재사용은 승격 후.** 다른 페이지 전용 컴포넌트를 그대로 import하지 말 것. 공통화 가치 검토 → 사용자 동의 → 공통 위치로 옮긴 다음 사용. 자동 cross-page import는 의도치 않은 결합 생성.
- **Rule of Three.** 같은 패턴 3번째 등장하면 추상화. 2번까지는 두 개 두는 게 잘못된 추상화보다 쌈.

## 2. 스택 & 컨벤션

- **Framework:** Next.js App Router 또는 동급 React 프레임워크(Remix/Vite + React Router 등) / TypeScript.
- **Styling:** Tailwind CSS. 여백·간격은 기본 4px 배수(`p-4`, `gap-6`). 디자인이 명시적으로 다른 그리드(8px·10px 단위 등)를 요구하면 그쪽이 우선.
- **UI Library:** `shadcn/ui` + `Radix UI` 베이스. Dialog/Select/DatePicker 등 a11y가 까다로운 요소는 직접 구현하지 말고 shadcn에서 가져와서 스타일만 입힐 것 (바퀴 재발명 금지).
- **CDD (Component-Driven Development):** 페이지 한 번에 짜지 말고 작은 요소부터 Bottom-Up으로 조립. 같은 페이지 내 이미 만들어진 복합 컴포넌트(`<UserCard>`, `<ProductList>` 등) 먼저 탐색 후 조립.

**Why:** 매번 같은 컨벤션을 재설명하지 않으려고 한 곳에 박음. 4px 배수/shadcn 베이스는 디자인-코드 간 마찰을 줄이는 안전한 디폴트지 절대 규칙이 아님 — 디자인이 명시적으로 다르게 요구하면 그쪽이 우선.

## 로직 분리 (UI 작업 시)

- **UI와 비즈니스/계산 로직 분리.** domain 함수는 React 몰라야 함 (props·hooks·JSX 의존 X). UI 레이어는 domain 함수 호출만.
- 복잡한 순수 함수는 `superpowers:test-driven-development`로 먼저 테스트 작성 후 구현.
