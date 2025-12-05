# PG 연동 시 장애 대응을 위한 Resilience 패턴 적용기

## TL;DR

**비동기 PG 시스템 연동 시 타임아웃, 콜백 누락, 장애 확산 문제를 Circuit Breaker, Timeout, Fallback, 스케줄러 복구 패턴으로 해결한 경험을 정리했습니다.**

---

## 1. 배경: PG 연동이 어려운 이유

이번 과제에서 제공된 `pg-simulator`는 실제 PG 시스템의 특성을 시뮬레이션합니다:

### PG Simulator 특성
- **요청 성공률**: 60% (40%는 실패)
- **요청 지연**: 100ms ~ 500ms
- **처리 지연**: 1s ~ 5s
- **처리 결과**:
  - 성공: 70%
  - 한도 초과: 20%
  - 잘못된 카드: 10%

### 비동기 결제의 특성

PG는 **요청과 실제 처리가 분리된 비동기 시스템**입니다:

```
1. 결제 요청 → PG가 "접수됨(transactionKey 발급)" 응답
2. PG가 실제 카드사와 통신 (1~5초 소요)
3. 처리 완료 후 콜백 URL로 결과 전송
```

이런 비동기 특성 때문에 다음과 같은 문제들이 발생합니다:

### 직면한 문제들

**문제 1: 타임아웃 vs 실제 성공**
```
시나리오:
1. 내 서버가 PG에 결제 요청
2. 3초 대기했지만 응답 없음 → 타임아웃 실패 처리
3. 실제론 PG에서 결제 성공, 콜백 전송 시도
4. 내 서버는 이미 주문 실패 처리함
→ 고객 카드는 결제됐는데, 주문은 실패?
```

**문제 2: 콜백 누락**
```
시나리오:
1. PG 결제 성공
2. 콜백 전송 중 네트워크 장애
3. 콜백이 내 서버에 도착하지 않음
→ PG는 성공했는데, 주문은 계속 PENDING?
```

**문제 3: PG 장애 확산**
```
시나리오:
1. PG 서버가 느려짐 (응답 10초+)
2. 모든 결제 요청이 10초씩 대기
3. 서버 스레드 고갈
→ 결제뿐만 아니라 상품 조회, 회원가입까지 멈춤
```

---

## 2. 해결 전략: 3단계 방어선

이 문제들을 해결하기 위해 **3단계 방어선**을 구축했습니다:

```
1차 방어: Circuit Breaker → PG 장애 시 서비스 전체 보호
2차 방어: Timeout + Fallback → 무한 대기 방지 + 실패 시 안전하게 처리
3차 방어: 스케줄러 복구 → 콜백 누락 케이스 자동 복구
```

---

## 3. 1차 방어: Circuit Breaker - PG 장애로부터 서비스 보호

### 왜 필요한가?

PG가 장애 상태일 때 계속 요청을 보내면:
- 모든 요청이 타임아웃까지 기다림 (3초 × 100개 = 300초)
- 서버 리소스 고갈
- **결제와 무관한 기능까지 멈춤**

Circuit Breaker는 "이미 고장난 시스템에 요청 보내지 말자"는 아이디어입니다.

### 구현

```yaml
# application.yml
resilience4j:
  circuitbreaker:
    instances:
      pgCircuit:
        # 시간 기반 슬라이딩 윈도우 (트래픽 변동이 큰 PG에 적합)
        sliding-window-type: TIME_BASED
        sliding-window-size: 30  # 30초 동안의 호출 데이터 수집

        # 최소 호출 20번 이상이어야 실패율 계산 시작
        minimum-number-of-calls: 20

        # 실패율 60% 이상이면 Circuit Open
        failure-rate-threshold: 60

        # Slow Call 설정
        slow-call-duration-threshold: 2s  # 2초 이상이면 느린 호출
        slow-call-rate-threshold: 50      # 느린 호출 50% 이상이면 Open

        # Circuit Open 상태 유지 시간
        wait-duration-in-open-state: 10s

        # Half-Open 상태에서 테스트 호출 5번
        permitted-number-of-calls-in-half-open-state: 5
        automatic-transition-from-open-to-half-open-enabled: true
```

### 임계값을 이렇게 정한 이유

#### 1) 왜 실패율을 60%로?
```
PG Simulator 특성:
- 요청 성공률: 60%
- 즉, 정상 상태에서도 40% 실패

만약 50%로 설정하면?
→ 정상 동작 중에도 Circuit이 열림 (오탐)

60%로 설정:
→ 정상보다 명확히 나쁜 상태만 감지
```

#### 2) 왜 Slow Call을 2초로?
```
정상 응답 시간:
- 요청 지연: 최대 500ms
- 처리 시간: 비동기라 즉시 응답 (transactionKey만 받음)
- 예상: 500ms 이내

2초 이상이면:
→ 명백히 PG에 문제가 있는 상태
```

#### 3) 왜 Half-Open 테스트를 5번으로?
```
3번 vs 5번 고민:
- 3번: 빠르게 복구, 하지만 오판 가능성
- 5번: 조금 느리지만, 복구 신뢰도 높음

PG는 돈과 관련된 시스템이므로:
→ 신중하게 5번 테스트 후 복구
```

### 적용 코드

```kotlin
@Service
class PaymentService(
    private val paymentRepository: PaymentRepository,
    private val pgStrategies: List<PgStrategy>
) {
    @CircuitBreaker(name = "pgCircuit", fallbackMethod = "paymentFallback")
    @TimeLimiter(name = "pgTimeLimiter")
    @Transactional
    fun requestCardPayment(
        order: Order,
        userId: String,
        cardType: String,
        cardNo: String
    ): Payment {
        // PG 결제 요청
        val pgStrategy = pgStrategies.firstOrNull { it.supports(PaymentMethod.CARD) }
            ?: throw CoreException(ErrorType.PAYMENT_UNAVAILABLE, "사용 가능한 PG가 없습니다.")

        val pgResponse = pgStrategy.requestPayment(userId, pgRequest)

        // Payment 엔티티 생성 (PENDING 상태)
        val payment = Payment.createCardPayment(
            orderId = order.id!!,
            amount = order.finalAmount,
            transactionKey = pgResponse.transactionKey,
            cardType = cardType,
            cardNo = cardNo
        )

        return paymentRepository.save(payment)
    }
}
```

### 동작 흐름

```
정상 상태 (Circuit CLOSED):
1. 결제 요청
2. PG 호출
3. 성공 또는 실패

장애 감지 (30초 동안 실패율 60% 이상):
1. Circuit OPEN
2. 이후 요청은 PG 호출 없이 즉시 Fallback 실행
3. 10초 후 자동으로 Half-Open

복구 테스트 (Circuit HALF-OPEN):
1. 5번 테스트 호출
2. 3번 이상 성공 → CLOSED (정상 복구)
3. 실패 → 다시 OPEN (10초 대기)
```

---

## 4. 2차 방어: Timeout + Fallback

### Timeout: 무한 대기 방지

```yaml
resilience4j:
  timelimiter:
    instances:
      pgTimeLimiter:
        timeout-duration: 3s
```

#### 왜 3초로 설정했나?

```
PG 요청 지연: 최대 500ms
여유: 2.5초 (네트워크 지연, PG 처리 시간)

3초면:
- 정상 케이스는 모두 통과
- 비정상 케이스만 차단

10초는 너무 길다:
- 사용자가 3초 이상 기다리면 "뭔가 이상하다" 생각
- 서버 리소스도 오래 점유
```

**Feign 레벨에서도 이중 타임아웃 설정:**

```kotlin
@Configuration
class PgClientConfig {
    @Bean
    fun feignRequestOptions(): Request.Options {
        return Request.Options(
            1000,  // connectTimeout: 연결 자체가 1초 이상이면 이상함
            3000,  // readTimeout: 응답 대기는 3초
        )
    }
}
```

### Fallback: 실패 시 안전한 처리

타임아웃이 발생하거나 Circuit이 열렸을 때 어떻게 처리할까?

#### 선택지 1: 즉시 주문 실패 처리
```
장점: 빠르게 사용자에게 알림
단점:
- 타임아웃 후 실제로 PG가 성공할 수 있음
- 사용자는 재결제 → 중복 결제 위험
```

#### 선택지 2: PENDING 상태로 남기기 (선택!)
```
장점:
- 타임아웃 ≠ 실패 인정
- 스케줄러가 나중에 실제 상태 확인 후 처리
단점:
- 사용자는 일시적으로 불확실한 상태 경험
```

**구현:**

```kotlin
private fun paymentFallback(
    order: Order,
    userId: String,
    cardType: String,
    cardNo: String,
    ex: Exception
): Payment {
    logger.error("Payment fallback triggered for order: ${order.id}", ex)

    // 실패 기록은 남기되, Order는 PENDING 유지
    val payment = Payment.createFailedPayment(
        orderId = order.id!!,
        amount = order.finalAmount,
        reason = "PG 시스템 일시 불가: ${ex.message}"
    )

    paymentRepository.save(payment)

    throw CoreException(
        ErrorType.PAYMENT_UNAVAILABLE,
        "현재 카드 결제가 불가능합니다. 잠시 후 다시 시도해주세요."
    )
}
```

---

## 5. 3차 방어: 스케줄러 복구 - 콜백 누락 대응

### 콜백 방식의 맹점

```
정상 흐름:
1. PG 결제 요청 → transactionKey 받음
2. PG 처리 완료
3. 콜백 URL로 결과 전송
4. 재고 차감 + 주문 완료

문제:
- 3번에서 네트워크 장애 → 콜백 못 받음
- 타임아웃으로 실패 처리 → 실제론 PG 성공
→ Payment와 Order가 계속 PENDING
```

### 해결: 주기적 상태 확인

**1분마다 10분 이상 PENDING인 주문을 찾아서 PG에 직접 상태 확인**

```kotlin
@Component
class PaymentReconciliationScheduler(
    private val orderRepository: OrderRepository,
    private val paymentRepository: PaymentRepository,
    private val productService: ProductService,
    private val pgStrategies: List<PgStrategy>
) {
    @Scheduled(fixedDelay = 60000) // 1분마다
    fun reconcileStaleOrders() {
        val cutoffTime = LocalDateTime.now().minusMinutes(10)

        // 10분 이상 PENDING인 주문 조회
        val staleOrders = orderRepository.findByStatusAndCreatedAtBefore(
            OrderStatus.PENDING,
            cutoffTime
        )

        if (staleOrders.isEmpty()) return

        logger.info("Found ${staleOrders.size} stale orders to reconcile")

        // 각 주문마다 PG 상태 확인 후 복구
        staleOrders.forEach { order ->
            try {
                reconcileOrder(order)
            } catch (e: Exception) {
                logger.error("Failed to reconcile order: ${order.id}", e)
            }
        }
    }

    @Transactional
    fun reconcileOrder(order: Order) {
        val payments = paymentRepository.findByOrderId(order.id!!)
        val pendingPayment = payments.firstOrNull { it.status == PaymentStatus.PENDING }

        if (pendingPayment?.transactionKey == null) {
            // PG 요청 자체가 실패한 케이스
            order.fail()
            return
        }

        // PG에 실제 상태 확인
        val pgStrategy = pgStrategies.first { it.supports(pendingPayment.paymentMethod) }
        val pgStatus = pgStrategy.getPaymentStatus(order.memberId, pendingPayment.transactionKey!!)

        when (pgStatus.status) {
            "SUCCESS" -> {
                // 콜백 누락 케이스 복구!
                try {
                    productService.decreaseStockByOrder(order)
                    pendingPayment.markAsSuccess()
                    order.complete()
                    logger.info("Recovered payment: orderId=${order.id}")
                } catch (e: Exception) {
                    // 재고 부족 시 - 실제론 PG 취소 API 호출 필요
                    pendingPayment.markAsFailed("재고 부족: ${e.message}")
                    order.fail()
                    // TODO: PG 취소 API 호출 및 CS 팀 알림
                }
            }
            "FAILED" -> {
                pendingPayment.markAsFailed(pgStatus.reason ?: "알 수 없는 오류")
                order.fail()
            }
            else -> {
                // 아직 PENDING → 계속 대기
                logger.debug("Payment still pending: orderId=${order.id}")
            }
        }
    }
}
```

### 기준값을 이렇게 정한 이유

#### 왜 10분 기준?
```
PG 처리 지연: 최대 5초
여유: 9분 55초

10분이면:
- 정상 케이스는 이미 콜백 받음
- 비정상 케이스(콜백 누락, 타임아웃)만 감지

너무 짧으면 (예: 1분):
- 아직 처리 중인데 스케줄러가 조회 → 불필요한 API 호출

너무 길면 (예: 1시간):
- 고객이 너무 오래 기다림
```

#### 왜 1분 주기?
```
빠르게 복구 vs API 부하 트레이드오프

10초 주기:
- 빠른 복구, 하지만 PG에 부하

5분 주기:
- 부하 적음, 하지만 복구 느림

1분 주기:
- 균형점 (최악의 경우 고객이 11분 대기)
```

---

## 6. 멱등성 보장: 콜백 중복 처리 방지

콜백이 2번 올 수도 있습니다 (네트워크 재시도, PG 재전송 등).

### 문제 시나리오

```
1. 콜백 1차 수신 → 재고 10개 → 9개로 차감
2. 콜백 2차 수신 → 재고 9개 → 8개로 차감
→ 주문 1건인데 재고 2개 차감!
```

### 해결: Payment 상태 체크

```kotlin
@Component
class PaymentCallbackService(
    private val paymentRepository: PaymentRepository,
    private val orderRepository: OrderRepository,
    private val productService: ProductService
) {
    @Transactional
    fun handlePaymentCallback(callback: PaymentCallbackDto) {
        val payment = paymentRepository.findByTransactionKey(callback.transactionKey)
            ?: throw CoreException(ErrorType.PAYMENT_NOT_FOUND, "결제 정보를 찾을 수 없습니다.")

        // 멱등성: 이미 처리된 콜백이면 무시
        if (payment.status != PaymentStatus.PENDING) {
            logger.warn("Already processed payment: paymentId=${payment.id}, status=${payment.status}")
            return  // 조용히 무시
        }

        val order = orderRepository.findByIdOrThrow(payment.orderId)

        if (callback.isSuccess()) {
            try {
                productService.decreaseStockByOrder(order)  // 재고 차감
                payment.markAsSuccess()
                order.complete()
            } catch (e: Exception) {
                payment.markAsFailed("재고 차감 실패: ${e.message}")
                order.fail()
                // TODO: PG 취소 요청
            }
        } else {
            payment.markAsFailed(callback.reason ?: "알 수 없는 오류")
            order.fail()
        }
    }
}
```

**핵심: `payment.status != PaymentStatus.PENDING` 체크**
- 1차 콜백: PENDING → SUCCESS (재고 차감)
- 2차 콜백: SUCCESS → 조용히 무시 (재고 차감 X)

---

## 7. 구현 중 겪은 고민들

### 고민 1: 재고 차감 시점

**선택지 A: PG 요청 성공 시 즉시 차감**
```kotlin
fun requestCardPayment(...) {
    val pgResponse = pgStrategy.requestPayment(...)
    if (pgResponse.status == "SUCCESS") {  // transactionKey만 받는 단계
        productService.decreaseStock(...)  // ❌ 너무 이름
    }
}
```
- 장점: 빠른 재고 확보
- 단점: PG 요청 성공 ≠ 실제 결제 성공 (비동기!)

**선택지 B: 콜백 받고 차감 (채택)**
```kotlin
fun handlePaymentCallback(callback: PaymentCallbackDto) {
    if (callback.isSuccess()) {
        productService.decreaseStock(...)  // ✅ 확실한 성공 후
    }
}
```
- 장점: 정합성 보장
- 단점: 재고 확보가 1~5초 지연

**결론: 정합성 > 속도**

### 고민 2: 타임아웃 실패 vs PG 실제 성공

```
시나리오:
1. PG 요청 전송
2. 3초 대기 → 타임아웃
3. 실제로 PG는 성공했고, 5초 후 콜백 전송 예정

이 시점에 Order를 FAILED로?
```

**선택: PENDING 유지**
- Fallback에서 예외만 던지고, Order 상태는 유지
- 스케줄러가 나중에 PG 상태 확인 후 결정

### 고민 3: 재고 부족 시 PG 취소

```kotlin
try {
    productService.decreaseStockByOrder(order)
    payment.markAsSuccess()
} catch (e: Exception) {
    payment.markAsFailed("재고 부족")
    order.fail()
    // TODO: PG 취소 API 호출 및 CS 팀 알림
}
```

**현재 상태: TODO로 남음**

이유:
- PG Simulator에 취소 API가 없음
- 실제 운영 환경에서는 필수!

**실제 운영이라면:**
1. PG 취소 API 호출
2. 취소 성공 → Payment에 환불 기록
3. 취소 실패 → CS 팀 알림 (수동 처리)

### 고민 4: 코루틴 병렬 처리

**초기 계획:**
```kotlin
// 10개 주문씩 병렬 처리 (코루틴)
staleOrders.chunked(10).forEach { chunk ->
    chunk.map { order ->
        async(Dispatchers.IO) {
            reconcileOrder(order)
        }
    }.awaitAll()
}
```

**최종 결정: 제거**

이유:
1. 과제 범위를 벗어남 (Resilience 패턴이 핵심)
2. 아직 코루틴을 충분히 이해하지 못함
3. 순차 처리로도 1분마다 실행이므로 충분

**트레이드오프:**
- 100개 주문이 쌓이면 처리 시간 증가
- 하지만 실제론 10분마다 쌓이는 주문이 많지 않을 것

---

## 8. 전체 흐름도

### 정상 케이스: 콜백 성공

```
[사용자] → 주문 생성
    ↓
[주문 서비스] → Order 생성 (PENDING)
    ↓
[결제 서비스] → PG 요청 (Circuit Breaker + Timeout 적용)
    ↓
[PG] → transactionKey 반환 (3초 내)
    ↓
[결제 서비스] → Payment 저장 (PENDING)
    ↓ (1~5초 대기)
[PG] → 콜백 전송
    ↓
[콜백 핸들러] → Payment 조회
    ↓
상태 체크 (PENDING?) → Yes
    ↓
재고 차감 성공
    ↓
Payment SUCCESS + Order COMPLETED
```

### 케이스 1: 타임아웃 → 스케줄러 복구

```
[사용자] → 주문 생성
    ↓
[결제 서비스] → PG 요청
    ↓ (3초 대기)
[Timeout] → Fallback 실행
    ↓
[Fallback] → Payment 실패 기록 + 예외 발생
    ↓
[사용자] → "잠시 후 다시 시도해주세요" (Order는 PENDING 유지)
    ↓ (10분 경과)
[스케줄러] → PENDING 주문 발견
    ↓
[스케줄러] → PG 상태 조회 (getPaymentStatus)
    ↓
PG: "SUCCESS"
    ↓
[스케줄러] → 재고 차감 + Order COMPLETED (복구 완료!)
```

### 케이스 2: 콜백 누락 → 스케줄러 복구

```
[사용자] → 주문 생성
    ↓
[결제 서비스] → PG 요청 성공
    ↓
[PG] → transactionKey 반환
    ↓
Payment 저장 (PENDING)
    ↓ (1~5초 후)
[PG] → 콜백 전송 시도
    ↓ ❌ 네트워크 장애
콜백 미도착
    ↓ (10분 경과)
[스케줄러] → PENDING 주문 발견
    ↓
[스케줄러] → PG 상태 조회
    ↓
PG: "SUCCESS"
    ↓
[스케줄러] → 재고 차감 + Order COMPLETED (복구 완료!)
```

### 케이스 3: Circuit Open

```
[PG 장애 발생] → 30초 동안 실패율 60% 초과
    ↓
[Circuit Breaker] → OPEN 상태로 전환
    ↓
[사용자] → 주문 생성
    ↓
[결제 서비스] → PG 요청 시도
    ↓
[Circuit Breaker] → "Circuit Open!" → Fallback 즉시 실행 (PG 호출 X)
    ↓
[Fallback] → Payment 실패 기록 + 예외
    ↓
[사용자] → "현재 카드 결제가 불가능합니다"
    ↓ (10초 후)
[Circuit Breaker] → HALF-OPEN
    ↓
테스트 요청 5번 → 3번 이상 성공 시 CLOSED
```

---

## 9. 테스트 결과 및 학습한 점

### Circuit Breaker 동작 확인

**시뮬레이터의 40% 실패율에서는 Circuit이 열리지 않음:**
- 정상 상태: 실패율 40% → 임계값 60% 미만
- Circuit 상태: CLOSED 유지

**의도적으로 PG 서버 중단 시:**
- 20번 호출 후 실패율 100%
- Circuit 상태: OPEN
- 이후 요청들은 즉시 Fallback

### Timeout 효과

**3초 타임아웃 적용 전:**
- PG가 느려지면 요청당 10초+ 대기
- 10개 요청 = 100초

**3초 타임아웃 적용 후:**
- 최대 3초 대기
- 10개 요청 = 30초
- 사용자 경험 개선

### 스케줄러 복구

**테스트 시나리오:**
1. 주문 생성 후 Payment를 강제로 PENDING 유지
2. 10분 경과
3. 스케줄러 실행 → PG 상태 조회 → 복구

**로그:**
```
[Scheduler] Found 1 stale orders to reconcile
[Scheduler] Querying PG status: transactionKey=TR:123456
[PG] Status: SUCCESS
[Scheduler] Recovered payment: orderId=1
[Order] Status changed: PENDING → COMPLETED
```

---

## 10. 배운 점

### 1. 타임아웃은 실패가 아니다

```
타임아웃 = "아직 모르겠다"
```

3초 안에 응답 못 받았다고 해서 실제로 실패한 건 아닙니다.
→ PENDING으로 남기고 나중에 확인하는 게 안전

### 2. 비동기 시스템은 멱등성이 필수

콜백이 2번, 3번 올 수 있습니다.
→ 상태 체크로 중복 처리 방지

### 3. Circuit Breaker는 전체 서비스를 보호한다

PG 장애가 주문 전체를 멈추게 하면 안 됩니다.
→ Circuit을 열어서 빠르게 실패 처리

### 4. 코루틴은 나중에

병렬 처리가 필요한 건 맞지만, **지금 단계에서는 과한 최적화**.
→ 기본 패턴 이해가 우선

---

## 11. 아쉬운 점 및 개선 방향

### 현재 TODO로 남은 것들

#### 1. PG 취소 API 미구현
```kotlin
// TODO: PG 취소 API 호출 및 CS 팀 알림
```

**실제 운영이라면:**
- 재고 부족 시 PG 취소 API 호출
- 취소 실패 시 CS 팀 알림 (Slack, 이메일)

#### 2. 알림 기능 없음
- 스케줄러가 복구할 때 운영팀 알림
- Circuit Open 시 장애 알림

#### 3. 메트릭 및 모니터링 부재
- Circuit Breaker 상태 모니터링
- 복구된 주문 수 추적
- PG 응답 시간 메트릭

#### 4. 코루틴 병렬 처리
- 현재: 순차 처리
- 개선: 10개씩 병렬로 PG 조회 (성능 10배 향상)

### 다음에 시도해볼 것

#### 1. Retry 패턴 추가
```yaml
resilience4j:
  retry:
    instances:
      pgRetry:
        max-attempts: 3
        wait-duration: 1s
```

일시적 네트워크 오류는 재시도로 해결 가능

#### 2. Bulkhead 패턴
```yaml
resilience4j:
  bulkhead:
    instances:
      pgBulkhead:
        max-concurrent-calls: 10
```

PG 요청을 별도 스레드 풀로 격리

#### 3. Rate Limiter
```yaml
resilience4j:
  ratelimiter:
    instances:
      pgRateLimiter:
        limit-for-period: 100
        limit-refresh-period: 1s
```

PG API 호출량 제한 (PG 부하 방지)

---

## 12. 마무리

### 핵심 요약

1. **Circuit Breaker**: PG 장애가 전체 서비스를 멈추지 않게
2. **Timeout**: 무한 대기 방지 (3초)
3. **Fallback**: 실패 시 안전한 처리 (PENDING 유지)
4. **스케줄러**: 콜백 누락 자동 복구 (1분마다 10분 이상 PENDING 확인)
5. **멱등성**: 콜백 중복 처리 방지 (Payment 상태 체크)

### 가장 중요한 깨달음

**"외부 시스템은 언제든 실패할 수 있다"**

PG뿐만 아니라 모든 외부 API 연동 시:
- 타임아웃 설정 필수
- Circuit Breaker로 장애 격리
- Fallback으로 안전한 실패 처리
- 재시도 또는 스케줄러로 복구

이번 과제를 통해 단순히 "PG 연동"이 아니라, **"장애에 강한 시스템 설계"**를 경험할 수 있었습니다.

---

**작성일**: 2024-12-05
**태그**: #Resilience4j #CircuitBreaker #PG연동 #비동기결제 #SpringBoot #Kotlin
