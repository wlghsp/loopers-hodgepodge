# Round 6 작업 계획

## 현재 상황 파악

### PG Simulator 분석
- 위치: `apps/pg-simulator`
- 포트: (확인 필요)
- API 엔드포인트:
  - `POST /api/v1/payments` - 결제 요청
  - `GET /api/v1/payments/{transactionKey}` - 결제 정보 확인
  - `GET /api/v1/payments?orderId={orderId}` - 주문별 결제 조회

### PG Simulator 특성
```kotlin
// 요청 시 100~500ms 지연
Thread.sleep((100..500L).random())

// 40% 확률로 요청 실패
if ((1..100).random() <= 40) {
    throw CoreException(ErrorType.INTERNAL_ERROR, "현재 서버가 불안정합니다.")
}
```

### 기존 Order 도메인 구조
- `Order`: 주문 엔티티
- `OrderStatus`: PENDING, COMPLETED, FAILED, CANCELLED
- `processPayment(member: Member)`: 현재는 Member의 포인트로 결제

**문제점:**
- Order에 결제 로직이 강하게 결합되어 있음
- PG 결제와 포인트 결제를 분리할 필요

---

## 작업 단계

### Phase 1: Payment 도메인 설계 및 구현

#### 1.1 Payment 도메인 설계
- [ ] Payment 엔티티 설계
  - orderId (FK)
  - amount
  - paymentMethod (POINT, CARD)
  - paymentStatus (PENDING, SUCCESS, FAILED)
  - transactionKey (PG에서 발급)
  - cardType, cardNo (카드 결제 시)
  - createdAt, updatedAt

- [ ] PaymentStatus enum 정의
  ```kotlin
  enum class PaymentStatus {
      PENDING,      // 결제 요청 중
      SUCCESS,      // 결제 성공
      FAILED,       // 결제 실패
      TIMEOUT,      // 타임아웃
      CANCELLED     // 취소됨
  }
  ```

- [ ] PaymentMethod enum 정의
  ```kotlin
  enum class PaymentMethod {
      POINT,   // 기존 포인트 결제
      CARD     // PG 카드 결제
  }
  ```

#### 1.2 Payment 도메인 로직
- [ ] Payment 생성 팩토리 메서드
- [ ] Payment 상태 전이 메서드
  - `markAsSuccess(transactionKey: String)`
  - `markAsFailed(reason: String)`
  - `markAsTimeout()`

#### 1.3 PaymentRepository
- [ ] PaymentRepository 인터페이스 정의
- [ ] JPA 구현체 작성

---

### Phase 2: PG Client 구현

#### 2.1 기술 선택
- [ ] RestTemplate vs FeignClient 결정
  - 고려사항: Timeout 설정 용이성, Resilience4j 통합, 코드 간결성
  - 블로그에 선택 이유 기록

#### 2.2 PG Client 구현
- [ ] PgClient 인터페이스 정의
  ```kotlin
  interface PgClient {
      fun requestPayment(request: PgPaymentRequest): PgPaymentResponse
      fun getPaymentStatus(transactionKey: String): PgPaymentStatusResponse
      fun getPaymentsByOrderId(orderId: String): List<PgPaymentStatusResponse>
  }
  ```

- [ ] DTO 정의
  - PgPaymentRequest
  - PgPaymentResponse
  - PgPaymentStatusResponse

- [ ] Timeout 설정
  - connectionTimeout: ?ms (블로그에서 고민)
  - readTimeout: ?ms (블로그에서 고민)

---

### Phase 3: Resilience4j 적용

#### 3.1 의존성 추가
- [ ] build.gradle.kts에 resilience4j 의존성 추가
  ```kotlin
  implementation("io.github.resilience4j:resilience4j-spring-boot3:2.x.x")
  implementation("io.github.resilience4j:resilience4j-circuitbreaker:2.x.x")
  implementation("io.github.resilience4j:resilience4j-retry:2.x.x")
  implementation("io.github.resilience4j:resilience4j-timelimiter:2.x.x")
  ```

#### 3.2 CircuitBreaker 설정
- [ ] application.yml 설정
  ```yaml
  resilience4j.circuitbreaker:
    instances:
      pgClient:
        failure-rate-threshold: ?%
        slow-call-rate-threshold: ?%
        slow-call-duration-threshold: ?ms
        wait-duration-in-open-state: ?s
        permitted-number-of-calls-in-half-open-state: ?
        sliding-window-type: COUNT_BASED
        sliding-window-size: ?
        minimum-number-of-calls: ?
  ```
- [ ] 각 설정값에 대한 고민을 블로그에 기록

#### 3.3 Fallback 전략
- [ ] CircuitBreaker Open 시 처리 방식 결정
  - 옵션 1: 즉시 실패 응답
  - 옵션 2: 큐에 쌓고 나중에 재시도
  - 옵션 3: 다른 결제 수단 제안
- [ ] Fallback 메서드 구현

#### 3.4 Retry 정책 (Optional)
- [ ] Retry 필요 여부 결정
- [ ] Retry 설정
  ```yaml
  resilience4j.retry:
    instances:
      pgClient:
        max-attempts: ?
        wait-duration: ?ms
        retry-exceptions:
          - java.net.ConnectException
          - java.net.SocketTimeoutException
  ```

---

### Phase 4: 주문-결제 연동

#### 4.1 OrderService 수정
- [ ] 기존 `processPayment` 분리
  - `processPointPayment(member: Member)`
  - `processCardPayment(cardInfo: CardInfo)`

#### 4.2 PaymentService 구현
- [ ] `requestCardPayment(order: Order, cardInfo: CardInfo): Payment`
- [ ] PG 요청 실패 시 Order 상태 처리
- [ ] Payment 기록 저장

#### 4.3 결제 상태 전이 플로우 설계
```
주문 생성 → Order(PENDING)
재고 차감 → Product(stock -)
PG 요청 → Payment(PENDING)
  ├─ 성공 → Payment(SUCCESS), Order(COMPLETED)
  ├─ 실패 → Payment(FAILED), Order(FAILED), 재고 복구
  └─ 타임아웃 → Payment(TIMEOUT), 상태 확인 스케줄링
```

---

### Phase 5: 콜백 처리

#### 5.1 Callback API 구현
- [ ] `POST /api/v1/payments/callback` 엔드포인트
- [ ] 멱등성 보장 (중복 콜백 처리)
- [ ] 보안 검증 (서명 or IP 확인)

#### 5.2 Callback 처리 로직
- [ ] transactionKey로 Payment 조회
- [ ] Payment 상태 업데이트
- [ ] Order 상태 업데이트
- [ ] 재고 확정

---

### Phase 6: 결제 상태 폴링

#### 6.1 폴링 전략 결정
- [ ] 옵션 1: 콜백 일정 시간 미도착 시 자동 폴링
- [ ] 옵션 2: 스케줄러로 PENDING 상태 주기적 확인
- [ ] 옵션 3: 사용자 "결제 확인" 버튼

#### 6.2 구현
- [ ] Scheduler 설정 (선택한 옵션에 따라)
- [ ] PG 상태 조회 API 호출
- [ ] 상태 동기화

---

### Phase 7: 테스트

#### 7.1 단위 테스트
- [ ] Payment 도메인 로직 테스트
- [ ] PaymentService 테스트 (PgClient Mock)

#### 7.2 통합 테스트
- [ ] PG 요청 성공 시나리오
- [ ] PG 요청 실패 시나리오
- [ ] Timeout 시나리오
- [ ] CircuitBreaker 동작 확인

#### 7.3 E2E 테스트
- [ ] 실제 PG Simulator와 연동 테스트
- [ ] 콜백 처리 테스트
- [ ] 폴링 복구 테스트

---

### Phase 8: 체크리스트 확인

#### PG 연동 대응
- [ ] PG 연동 API는 RestTemplate 혹은 FeignClient로 외부 시스템을 호출한다.
- [ ] 응답 지연에 대해 타임아웃을 설정하고, 실패 시 적절한 예외 처리 로직을 구현한다.
- [ ] 결제 요청에 대한 실패 응답에 대해 적절한 시스템 연동을 진행한다.
- [ ] 콜백 방식 + 결제 상태 확인 API를 활용해 적절하게 시스템과 결제정보를 연동한다.

#### Resilience 설계
- [ ] 서킷 브레이커 혹은 재시도 정책을 적용하여 장애 확산을 방지한다.
- [ ] 외부 시스템 장애 시에도 내부 시스템은 정상적으로 응답하도록 보호한다.
- [ ] 콜백이 오지 않더라도, 일정 주기 혹은 수동 API 호출로 상태를 복구할 수 있다.
- [ ] PG에 대한 요청이 타임아웃에 의해 실패되더라도 해당 결제건에 대한 정보를 확인하여 정상적으로 시스템에 반영한다.

---

## 작업 우선순위

### Must-Have (이번 주 필수)
1. Payment 도메인 구현
2. PG Client 구현 (Timeout 설정)
3. Fallback 전략
4. CircuitBreaker 적용
5. 콜백 처리

### Nice-to-Have (시간이 허락하면)
1. Retry 정책
2. 폴링 자동화
3. 모니터링/로깅
4. 성능 테스트

---

## 블로그 작성 가이드

### 각 단계마다 기록할 내용
1. **왜 이 방식을 선택했는가?**
2. **다른 선택지는 무엇이 있었나?**
3. **테스트 결과는 어땠나?**
4. **어떤 문제에 부딪혔나?**
5. **어떻게 해결했나?**

### 좋은 예시
❌ "CircuitBreaker를 적용했다."
✅ "failure-rate-threshold를 50%로 설정했다가 너무 민감하게 반응해서 70%로 조정했다. 왜냐하면..."

---

## 참고 자료
- Resilience4j 공식 문서: https://resilience4j.readme.io/
- Spring RestTemplate Timeout: https://docs.spring.io/spring-framework/reference/integration/rest-clients.html
- Circuit Breaker Pattern: https://martinfowler.com/bliki/CircuitBreaker.html
