# 💡 Frontend Implementation Skills (Playbook)

복잡한 요구사항을 해결할 때는 다음의 아키텍처 스킬과 패턴을 적용하여 코드를 설계하세요.

## Skill 1. 도메인 로직 3대장 분리 (Domain Layer)
비즈니스 요구사항은 다음 3가지 유형의 순수 함수(`.domain.ts`)로 쪼개어 해결합니다.
1. **계산기 (데이터 가공):** 주어진 데이터를 가공하거나 수학적 계산을 수행 (예: 총액 계산, 목록 필터링)
2. **판사 (UI 정책 결정):** 여러 도메인 데이터를 종합하여 화면에 렌더링할 명확한 상태값(`View Mode` 또는 `Status Flag`) 반환
3. **검사관 (유효성 검사):** 사용자 입력이나 액션이 서비스 정책에 부합하는지 검증 (예: 결제 가능 여부 `boolean` 반환)

## Skill 2. 데이터 수집가 패턴 (Aggregator Hook)
- 커스텀 훅(`use[Feature].ts`)은 도메인 함수 안에서 직접 데이터를 조회하지 않도록 방어하는 역할을 합니다.
- 서버 상태(React Query), 전역 상태(Zustand), 로컬 상태를 모두 **수집(Aggregate)**한 뒤, 도메인 로직(순수 함수)의 매개변수(Arguments)로 주입하여 판단을 위임하세요.

## Skill 3. Action 캡슐화 (은닉화)
- `useReducer`를 사용할 때, UI 컴포넌트에 `dispatch` 함수를 날것으로 노출하지 마세요.
- 커스텀 훅 내부에서 직관적인 이름의 핸들러(예: `handleAddItem`, `toggleEditMode`)로 감싸서 UI에 제공하세요. UI는 그저 "무슨 일이 일어났다"고 호출만 할 뿐, 내부 원리를 몰라야 합니다.
