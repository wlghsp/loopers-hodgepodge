# 7주차 미션 태스크 리스트

## 개요
ApplicationEvent를 활용한 트랜잭션 분리 작업

---

## 1. 현재 코드베이스 분석

### 1.1 주문/결제 플로우 파악
- [ ] 현재 주문 생성 로직 분석
- [ ] 결제 처리 로직 분석
- [ ] 쿠폰 사용 처리 로직 파악
- [ ] 데이터 플랫폼 전송 로직 파악
- [ ] 트랜잭션 경계 확인

### 1.2 좋아요/집계 플로우 파악
- [ ] 좋아요 처리 로직 분석
- [ ] 좋아요 집계 로직 분석
- [ ] 현재 트랜잭션 경계 확인

---

## 2. 주문 생성 이벤트 구현

### 2.1 OrderCreatedEvent 정의
```kotlin
// 구현 내용:
// - 주문 ID
// - 사용자 ID
// - 주문 금액
// - 쿠폰 ID (있는 경우)
// - 주문 생성 시간
```
- [ ] 이벤트 클래스 생성
- [ ] 필요한 데이터 필드 정의
- [ ] 불변 객체로 설계

### 2.2 주문 생성 시 이벤트 발행
- [ ] OrderService에서 이벤트 발행 (ApplicationEventPublisher 사용)
- [ ] 트랜잭션 커밋 후 발행되도록 설정

---

## 3. 쿠폰 사용 처리 이벤트 기반 분리

### 3.1 쿠폰 사용 이벤트 리스너 구현
```kotlin
// 구현 내용:
// @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
// - OrderCreatedEvent를 구독
// - 쿠폰이 있는 경우 사용 처리
// - 별도 트랜잭션으로 실행
```
- [ ] CouponEventHandler 클래스 생성
- [ ] @TransactionalEventListener 설정
- [ ] 쿠폰 사용 로직 이동
- [ ] 에러 처리 전략 수립

---

## 4. 결제 완료/실패 이벤트 구현

### 4.1 결제 이벤트 정의
```kotlin
// PaymentCompletedEvent:
// - 결제 ID
// - 주문 ID
// - 결제 금액
// - 결제 완료 시간

// PaymentFailedEvent:
// - 결제 ID
// - 주문 ID
// - 실패 사유
// - 실패 시간
```
- [ ] PaymentCompletedEvent 클래스 생성
- [ ] PaymentFailedEvent 클래스 생성

### 4.2 결제 결과에 따른 주문 상태 업데이트 분리
```kotlin
// 구현 내용:
// - PaymentCompletedEvent 구독 시 주문 상태를 CONFIRMED로 변경
// - PaymentFailedEvent 구독 시 주문 상태를 FAILED로 변경
// - 별도 트랜잭션으로 실행
```
- [ ] OrderEventHandler 클래스 생성
- [ ] 결제 완료 이벤트 리스너 구현
- [ ] 결제 실패 이벤트 리스너 구현
- [ ] PaymentService에서 이벤트 발행

---

## 5. 데이터 플랫폼 전송 이벤트 구현

### 5.1 데이터 플랫폼 전송 핸들러
```kotlin
// 구현 내용:
// @Async
// @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
// - 주문/결제 완료 후 데이터 플랫폼에 비동기 전송
// - 실패해도 주문/결제에 영향 없음
```
- [ ] DataPlatformEventHandler 클래스 생성
- [ ] 비동기 이벤트 리스너 구현
- [ ] 재시도 로직 고려
- [ ] 실패 로깅 구현

---

## 6. 좋아요 이벤트 구현

### 6.1 ProductLikedEvent 정의
```kotlin
// 구현 내용:
// - 상품 ID
// - 사용자 ID
// - 좋아요 ID
// - 좋아요 시간
```
- [ ] ProductLikedEvent 클래스 생성

### 6.2 좋아요 처리 시 이벤트 발행
- [ ] ProductLikeService에서 이벤트 발행
- [ ] 트랜잭션 커밋 후 발행되도록 설정

---

## 7. 좋아요 집계 로직 이벤트 기반 분리

### 7.1 좋아요 집계 이벤트 리스너 구현
```kotlin
// 구현 내용:
// @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
// - ProductLikedEvent를 구독
// - eventual consistency로 집계 처리
// - 집계 실패해도 좋아요는 성공 처리
```
- [ ] ProductStatisticsEventHandler 클래스 생성
- [ ] 집계 로직 이동
- [ ] 별도 트랜잭션으로 실행

### 7.2 트랜잭션 분리 검증
- [ ] 집계 실패 시 좋아요가 롤백되지 않는지 확인
- [ ] 로그로 검증

---

## 8. 사용자 행동 로깅 이벤트 구현

### 8.1 UserActionEvent 정의
```kotlin
// 구현 내용:
// - 사용자 ID
// - 액션 타입 (VIEW, CLICK, LIKE, ORDER 등)
// - 대상 엔티티 타입 (PRODUCT, ORDER 등)
// - 대상 엔티티 ID
// - 메타데이터 (JSON)
// - 발생 시간
```
- [ ] UserActionEvent 클래스 생성
- [ ] ActionType enum 정의

### 8.2 사용자 행동 로깅 핸들러 구현
```kotlin
// 구현 내용:
// - 서버 레벨에서 사용자 행동 추적
// - 로그 적재 (로그 파일 또는 별도 저장소)
// - 비동기 처리
```
- [ ] UserActionEventHandler 클래스 생성
- [ ] 각 도메인에서 행동 이벤트 발행
  - [ ] 상품 조회 시
  - [ ] 상품 클릭 시
  - [ ] 좋아요 시
  - [ ] 주문 시

---

## 9. Spring Async 설정

### 9.1 AsyncConfigurer 구성
```kotlin
// 구현 내용:
// @Configuration
// @EnableAsync
// - ThreadPoolTaskExecutor 설정
// - Core pool size, max pool size, queue capacity 설정
// - Exception handler 설정
```
- [ ] AsyncConfig 클래스 생성
- [ ] ThreadPoolTaskExecutor 빈 등록
- [ ] 적절한 스레드 풀 크기 설정
- [ ] AsyncUncaughtExceptionHandler 구현

---

## 10. 이벤트 실패 처리 전략 구현

### 10.1 로깅 및 모니터링
- [ ] 이벤트 핸들러 실패 시 로그 기록
- [ ] 실패 원인 추적 가능하도록 구조화된 로그 작성
- [ ] 메트릭 수집 (선택사항)

### 10.2 예외 처리
- [ ] 각 이벤트 핸들러에 try-catch 추가
- [ ] 재시도가 필요한 경우 고려
- [ ] Dead Letter Queue 패턴 고려 (선택사항)

---

## 11. 통합 테스트 작성

### 11.1 주문 생성 후 쿠폰 사용 처리 검증
```kotlin
// 테스트 시나리오:
// 1. 쿠폰이 포함된 주문 생성
// 2. 주문이 정상적으로 생성되는지 확인
// 3. 이벤트가 발행되어 쿠폰이 사용 처리되는지 확인 (비동기이므로 약간의 대기 필요)
// 4. 쿠폰 처리 실패 시 주문은 성공하는지 확인
```
- [ ] 테스트 클래스 작성
- [ ] 쿠폰 사용 성공 케이스
- [ ] 쿠폰 사용 실패 케이스 (주문은 성공)

### 11.2 결제 완료 후 주문 상태 업데이트 검증
```kotlin
// 테스트 시나리오:
// 1. 주문 생성
// 2. 결제 완료 처리
// 3. PaymentCompletedEvent 발행
// 4. 주문 상태가 CONFIRMED로 변경되는지 확인
// 5. 결제 실패 시 주문 상태가 FAILED로 변경되는지 확인
```
- [ ] 결제 완료 시나리오 테스트
- [ ] 결제 실패 시나리오 테스트

### 11.3 좋아요와 집계의 트랜잭션 분리 검증
```kotlin
// 테스트 시나리오:
// 1. 상품 좋아요 처리
// 2. 좋아요가 정상적으로 저장되는지 확인
// 3. 집계 로직에서 예외를 강제로 발생
// 4. 좋아요는 성공, 집계는 실패하는지 확인
// 5. eventual consistency 검증
```
- [ ] 좋아요 성공, 집계 성공 케이스
- [ ] 좋아요 성공, 집계 실패 케이스
- [ ] 집계가 eventual consistency로 처리되는지 확인

---

## 12. 블로그 글 작성

### 12.1 블로그 구조
```markdown
# ApplicationEvent로 트랜잭션 분리하기

## TL;DR
- 핵심 내용 3-5줄 요약

## 문제 인식
- 왜 트랜잭션 분리가 필요했는가?
- 기존 코드의 문제점은?

## 구현 과정
- 어떻게 구현했는가?
- 주요 코드 스니펫

## 판단 근거
- 왜 이 방식을 선택했는가?
- 다른 방법들과 비교

## 트레이드오프
- 이벤트 기반 아키텍처의 장단점
- eventual consistency의 장단점
- 복잡도 증가 vs 성능/안정성 향상

## 회고
- 배운 점
- 아쉬운 점
- 개선할 점
```

- [ ] TL;DR 작성
- [ ] 문제 인식 섹션 작성
- [ ] 구현 과정 섹션 작성 (코드 스니펫 포함)
- [ ] 판단 근거 섹션 작성
- [ ] 트레이드오프 섹션 작성
- [ ] 회고 섹션 작성
- [ ] 최종 리뷰 및 퇴고

---

## 참고 사항

### 주요 어노테이션
- `@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)`: 트랜잭션 커밋 후 이벤트 처리
- `@Async`: 비동기 실행
- `ApplicationEventPublisher`: 이벤트 발행

### 트레이드오프 고려사항
- **복잡도 증가**: 이벤트 기반으로 전환하면 코드 흐름 추적이 어려워짐
- **Eventual Consistency**: 즉시 일관성이 보장되지 않음
- **성능 향상**: 불필요한 트랜잭션 대기 시간 감소
- **안정성 향상**: 부가 기능 실패가 핵심 기능에 영향을 주지 않음
- **실패 처리 복잡도**: 이벤트 실패 시 재시도/보상 로직 필요

### 테스트 시 주의사항
- 비동기 이벤트는 테스트에서 대기 시간 필요 (`Thread.sleep` 또는 `Awaitility` 사용)
- `@TransactionalEventListener`는 실제 트랜잭션 커밋이 필요하므로 통합 테스트로 검증
