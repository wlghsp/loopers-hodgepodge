## 📌 Summary

이벤트 기반 아키텍처를 도입하여 트랜잭션 경계를 재설계하고, 코루틴을 활용한 비동기 처리로 성능을 개선하고자 시도했습니다.

**주요 변경사항:**
- 이벤트 기반 아키텍처 도입: 결제, 주문, 좋아요 처리를 이벤트로 분리
- 좋아요 집계를 Eventual Consistency로 변경: 코루틴 기반 비동기 처리로 응답 속도 개선
- 비관적 락 최적화: 주문 생성 시 불필요한 Product 락 제거
- 코루틴 도입: ThreadPool 대신 코루틴으로 리소스 효율 극대화
- DDD 계층에 맞춘 이벤트 핸들러 재배치: domain/application/infrastructure 계층 분리
- UserActionEvent 아키텍처: 도메인 이벤트와 사용자 행동 추적 관심사 분리 (LIKE/UNLIKE/ORDER/VIEW/BROWSE)

## 💬 Review Points

### 1. 코루틴 적용

**배경:**
- `@Async` + ThreadPool 사용 시 DB 커넥션 풀 고갈 문제
- 코루틴으로 전환하여 경량 스레드로 리소스 효율화

**구현:**
- `Dispatchers.IO.limitedParallelism(50)` 사용
- `SupervisorJob` + `CoroutineExceptionHandler`로 예외 처리
- `@PreDestroy`에서 `scope.cancel()` (CodeRabbit 리뷰 반영)

**질문:**
- 이벤트 핸들러에 코루틴 적용이 적절한지 확인 부탁드립니다.
- 멘토님은 어떤 경우에 코루틴을 적극적으로 사용하시는지 궁금합니다. 

### 2. 비동기 테스트

**문제:**
- 코루틴 비동기 처리로 테스트에서 이벤트 처리 완료 대기 필요
- 현재 `Thread.sleep(100)` 사용 중

**질문:**
- 더 나은 비동기 테스트 방법이 있을까요? 

### 3. TransactionalEventListener

**현재:**
- 모든 이벤트 핸들러에 `AFTER_COMMIT` 적용
- 메인 트랜잭션 커밋 후 부가 작업 수행

**질문:**
- `BEFORE_COMMIT`는 언제 사용하는 게 좋은지 아직 잘 모르겠는데 알려주시면 감사하겠습니다. 

### 4. UserActionEvent 아키텍처

**관심사 분리:**
- 도메인 서비스: 도메인 이벤트만 발행 (`ProductLikedEvent`, `OrderCreatedEvent` 등)
- EventHandler: 도메인 이벤트를 `UserActionEvent`로 변환하여 데이터 플랫폼 전송

**구현:**
- `UserActionTrackingEventHandler`: 도메인 이벤트 → `UserActionEvent` 변환
- 추적 대상: LIKE, UNLIKE, ORDER, VIEW, BROWSE
- 비로그인 사용자는 도메인 이벤트는 발행되지만 `UserActionEvent`는 제외

**질문:**
- 이벤트 변환 레이어 분리가 적절한지 궁금합니다. 


## ✅ Checklist

- [x] 이벤트 기반 아키텍처 도입
- [x] 코루틴 기반 비동기 이벤트 처리 구현
- [x] 비관적 락 최적화 (주문 생성 시 Product 락 제거)
- [x] DDD 계층에 맞춘 이벤트 핸들러 재배치
- [x] UserActionEvent 아키텍처 적용 (도메인 이벤트와 사용자 행동 추적 분리)
- [x] 테스트 코드 작성 및 수정 (비동기 이벤트 처리 대기 로직 포함)
- [x] 동시성 테스트 통과 확인
- [x] 불필요한 코드 제거

## 📎 References


<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

# 릴리스 노트

* **New Features**
  * 이벤트 기반 아키텍처 도입으로 주문, 결제, 상품 좋아요 처리 개선
  * 비동기 처리 지원으로 시스템 응답성 향상
  * 데이터 플랫폼 통합으로 사용자 활동 데이터 수집
  * 사용자 행동 추적(조회, 클릭, 좋아요, 검색) 기능 추가
  * 회로 차단기 모니터링 및 로깅 기능 추가

* **Tests**
  * 비동기 이벤트 처리 검증을 위한 테스트 업데이트

<sub>✏️ Tip: You can customize this high-level summary in your review settings.</sub>

<!-- end of auto-generated comment: release notes by coderabbit.ai -->