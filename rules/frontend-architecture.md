# 🚨 Frontend Architecture Rules

이 프로젝트의 코드를 작성할 때는 아래의 강제 규칙(Rule)을 무조건 준수해야 합니다. 예외는 없습니다.

## 1. Directory Structure (2-Tier)
파일은 오직 두 폴더로만 격리되어야 합니다.
- `/components/`: UI 렌더링을 담당하는 React 컴포넌트 파일(`.tsx`)만 위치합니다.
- `/services/`: API, 타입, 상태 관리, 순수 비즈니스 로직 등 컴포넌트가 아닌 모든 로직이 위치합니다.

## 2. Separation of Concerns (관심사 분리)
- **UI 컴포넌트의 제약:** 컴포넌트 내부에는 어떠한 데이터 가공 로직, API 호출, 복잡한 상태 분기문도 작성하지 않습니다. 오직 `/services`에서 가져온 상태를 화면에 그리고, 이벤트를 전달하는 역할만 수행합니다.
- **도메인 로직의 제약:** `/services/**/*.domain.ts` 파일에는 `React` 종속성(Hook 등)이나 전역 상태, API 호출 로직을 절대 포함하지 않습니다. 오직 순수 함수(Pure Function)로만 작성합니다.

## 3. Controller(Custom Hook) 단일 진입점
- 컴포넌트는 `/services`의 개별 파일(api, domain, types 등)을 직접 여러 개 import 하지 않습니다.
- 반드시 `use[Feature].ts` 형태의 커스텀 훅을 통해 정제된 상태와 핸들러만 제공받습니다 (Facade Pattern).

## 4. State Management 제약
- 기본적으로 `useState`를 사용하되, 여러 상태가 동시에 변하거나 로직이 복잡해질 경우에만 **`useReducer`**를 도입하여 상태 변경 로직을 UI 외부로 분리합니다.
