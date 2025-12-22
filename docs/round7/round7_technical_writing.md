# 이벤트로 트랜잭션 분리하기: 언제 어떻게 나눌 것인가?

## TL;DR

**"이 작업이 실패하면 메인 로직도 실패해야 하는가?"**를 기준으로 트랜잭션 경계를 나눈다: 강한 결합은 직접 호출, 약한 결합은 동기 이벤트(AFTER_COMMIT + REQUIRES_NEW), 완전히 독립적이면 비동기 이벤트(코루틴). 외부 I/O는 트랜잭션 밖에서 실행하고, 코루틴으로 비동기 처리하여 성능을 개선한다.

## 목차

1. [트랜잭션 경계를 나누는 기준: 무엇을 분리할 것인가?](#1-트랜잭션-경계를-나누는-기준-무엇을-분리할-것인가)
2. [동기 이벤트: AFTER_COMMIT + REQUIRES_NEW](#2-동기-이벤트-after_commit--requires_new)
3. [비동기 이벤트: 코루틴으로 성능 개선하기](#3-비동기-이벤트-코루틴으로-성능-개선하기)
4. [외부 호출과 트랜잭션 경계](#4-외부-호출과-트랜잭션-경계)

---

## 1. 트랜잭션 경계를 나누는 기준: 무엇을 분리할 것인가?

### 문제 상황

결제 서비스를 구현하면서 모든 로직을 하나의 트랜잭션에 넣었더니 문제가 발생했다:

```kotlin
@Transactional
fun processPayment(...) {
    // 1. 결제 처리 (핵심 로직)
    payment.markAsSuccess()

    // 2. 주문 완료 처리 (핵심 로직)
    orderService.completeOrderWithPayment(orderId)

    // 3. 데이터 플랫폼 전송 (부가 로직)
    dataPlatformClient.sendPaymentData(...)

    // 4. 유저 행동 로깅 (부가 로깅)
    userActionLogger.log(...)
}
```

**발생한 문제:**
- 데이터 플랫폼 전송 실패 → 결제와 주문까지 롤백됨
- 외부 I/O가 느리면 → 전체 트랜잭션이 느려짐
- 도메인 경계가 불명확해짐

### 해결 방법: 이벤트로 트랜잭션 분리

핵심 질문: **"이 작업이 실패하면 메인 로직도 실패해야 하는가?"**

이 질문을 기준으로 3가지로 분류했다:

#### 1️⃣ 별도 트랜잭션, 순서 보장 필요 → 동기 이벤트 (AFTER_COMMIT + REQUIRES_NEW)

```kotlin
// 결제 → 주문 완료
@Component
class PaymentCallbackService(
    private val eventPublisher: ApplicationEventPublisher
) {
    @Transactional
    fun handlePaymentCallback(callback: PaymentCallbackDto) {
        payment.markAsSuccess()

        // 이벤트 발행 (주문 완료는 별도 트랜잭션에서)
        eventPublisher.publishEvent(
            PaymentCompletedEvent(
                orderId = payment.orderId,
                memberId = order.memberId
            )
        )
    }
}

@Component
class OrderEventHandler(
    private val orderService: OrderService
) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        orderService.completeOrderWithPayment(event.orderId)
    }
}
```

**왜 이렇게?**
- 결제와 주문은 별도 도메인 → 실패를 독립적으로 처리
- 결제 커밋 후 주문 완료 → 재시도 로직으로 복구 가능
- 각 도메인의 책임이 명확해짐

#### 2️⃣ 실패해도 괜찮음 → 비동기 이벤트 (코루틴)

```kotlin
// 결제 → 데이터 플랫폼 전송
@Component
class DataPlatformEventHandler(
    private val dataPlatformClient: DataPlatformClient,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        coroutineScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    dataPlatformClient.sendPaymentData(...)
                }
            } catch (e: Exception) {
                logger.error("데이터 플랫폼 전송 실패", e)
            }
        }
    }
}
```

**왜 이렇게?**
- 데이터 플랫폼 전송은 결제와 독립적
- 실패해도 나중에 재전송 가능
- 코루틴으로 비동기 처리 (메인 트랜잭션은 빠르게 종료)

#### 3️⃣ 실패하면 안 됨 → 직접 호출 (같은 트랜잭션)

```kotlin
// 주문 → 재고 차감
@Transactional
fun createOrder(...) {
    val order = orderRepository.save(order)

    // 재고 차감 실패 → 주문도 롤백되어야 함
    productService.decreaseStock(productId, quantity)
}
```

### 핵심 교훈

| 기준 | 구현 방식 | 예시 |
|------|----------|------|
| 강한 결합 필요 | 직접 호출 (같은 트랜잭션) | 주문 → 재고 차감 |
| 약한 결합 가능 | 동기 이벤트 (별도 트랜잭션) | 결제 → 주문 완료 |
| 완전히 독립적 | 비동기 이벤트 | 결제 → 데이터 플랫폼 전송 |

**무조건 이벤트로 분리하는 게 아니라, 비즈니스 요구사항에 따라 결정해야 한다.**

---

## 2. 동기 이벤트: AFTER_COMMIT + REQUIRES_NEW

### TransactionalEventListener의 phase 옵션

**AFTER_COMMIT (권장):**
- 메인 트랜잭션이 커밋된 후에 실행
- 커밋 실패 시 핸들러도 실행되지 않음
- 데이터 정합성 보장

**BEFORE_COMMIT:**
- 메인 트랜잭션 커밋 전에 실행
- 핸들러 실패 시 메인 트랜잭션도 롤백
- 거의 사용하지 않음 (이벤트 실패가 메인 로직에 영향)

### REQUIRES_NEW로 독립 트랜잭션 보장

```kotlin
@Component
class PaymentRecoveryTransactionService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentSuccess(orderId: Long, paymentId: Long) {
        // ID만 받아서 내부에서 재조회 (영속성 컨텍스트 분리)
        val payment = paymentRepository.findByIdOrThrow(paymentId)
        orderService.completeOrderWithPayment(orderId)
        payment.markAsSuccess()
        paymentRepository.save(payment)
    }
}
```

**핵심 포인트:**
1. **ID만 전달**: 엔티티를 넘기면 영속성 컨텍스트 꼬임 위험
2. **내부에서 재조회**: 새 트랜잭션에서 깨끗한 엔티티 조회
3. **독립적 실패 처리**: 이 핸들러 실패가 메인 트랜잭션에 영향 없음

---

## 3. 비동기 이벤트: 코루틴으로 성능 개선하기

### 왜 코루틴을 사용하는가?

**@Async + ThreadPool의 문제점:**
- 이벤트 핸들러마다 스레드 생성 → DB 커넥션 소진
- ThreadPool 관리가 복잡함
- 리소스 효율이 낮음

**코루틴의 장점:**
- 경량 스레드로 리소스 효율 극대화
- Kotlin 생태계와 자연스러운 통합
- 더 적은 리소스로 더 많은 동시 작업 처리

### 구현 예시

```kotlin
@Component
class DataPlatformEventHandler(
    private val dataPlatformClient: DataPlatformClient,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        coroutineScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    dataPlatformClient.sendPaymentData(...)
                }
            } catch (e: Exception) {
                logger.error("데이터 플랫폼 전송 실패", e)
            }
        }
    }
}
```

**코루틴 설정:**

```kotlin
@Configuration
class CoroutineConfig {
    @Bean("eventCoroutineScope")
    fun eventCoroutineScope(): CoroutineScope {
        return CoroutineScope(
            Dispatchers.IO.limitedParallelism(50) +
            SupervisorJob() +
            CoroutineExceptionHandler { _, e ->
                logger.error("이벤트 처리 중 예외 발생", e)
            }
        )
    }
}
```

### 성능 개선 효과

**Before (@Async):**
- 100개 요청 + 50개 스레드 = 최대 150개 커넥션 필요
- 스레드 생성/관리 오버헤드

**After (코루틴):**
- 스레드 공유로 실제 커넥션 사용량이 이론적 최대보다 훨씬 낮음
- 원래 설정(10개 커넥션 풀)으로도 충분
- 메인 트랜잭션은 빠르게 종료, 부가 작업은 백그라운드에서 처리

**핵심:**
- 코루틴으로 비동기 처리하여 메인 트랜잭션 응답 속도 개선
- 실패해도 메인 로직에 영향 없음
- 리소스 효율 극대화

---

## 4. 외부 호출과 트랜잭션 경계

### 문제 상황

결제 복구 서비스에서 PG 상태 조회를 트랜잭션 내부에서 실행했더니 문제가 발생했다:

```kotlin
@Transactional
fun recoverPendingPayments() {
    val staleOrders = findStaleOrders()
    
    staleOrders.forEach { order ->
        // PG 조회가 트랜잭션 내부에서 실행됨
        val pgStatus = pgStrategy.getPaymentStatus(...)  // 외부 I/O
        // DB 커넥션을 오래 점유
    }
}
```

**발생한 문제:**
- PG 조회(외부 I/O)가 느리면 DB 커넥션을 오래 점유
- 다른 트랜잭션이 커넥션을 기다리며 대기
- 커넥션 풀 고갈 위험

### 해결 방법: 트랜잭션 경계 재조정

```kotlin
@Component
class PaymentRecoveryService {
    // 트랜잭션 없이 실행
    fun recoverPendingPayments() {
        val cutoffTime = ZonedDateTime.now().minusMinutes(10)
        
        // 조회만 인라인으로 처리 (self-invocation 방지)
        val staleOrders = orderRepository.findByStatusAndCreatedAtBefore(
            OrderStatus.PENDING,
            cutoffTime
        )

        staleOrders.forEach { order ->
            try {
                // PG 조회는 트랜잭션 밖에서 실행
                processStaleOrder(order)
            } catch (e: Exception) {
                log.error("주문 복구 실패: orderId=${order.id}", e)
            }
        }
    }

    private fun processStaleOrder(order: Order) {
        // 트랜잭션 없이 PG 조회
        val pgStatus = pgStrategy.getPaymentStatus(...)
        
        // 상태에 따라 별도 트랜잭션 서비스 호출
        when (pgStatus.status) {
            "SUCCESS" -> transactionService.handlePaymentSuccess(order.id, payment.id)
            "FAILED" -> transactionService.handlePaymentFailure(order.id, payment.id, reason)
        }
    }
}

@Component
class PaymentRecoveryTransactionService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentSuccess(orderId: Long, paymentId: Long) {
        val payment = paymentRepository.findByIdOrThrow(paymentId)
        orderService.completeOrderWithPayment(orderId)
        payment.markAsSuccess()
        paymentRepository.save(payment)
    }
}
```

**핵심 포인트:**
1. **외부 I/O는 트랜잭션 밖에서**: PG 조회 같은 외부 호출은 트랜잭션 없이 실행
2. **조회는 인라인 처리**: self-invocation 방지를 위해 별도 메서드로 분리하지 않음
3. **REQUIRES_NEW에 ID만 전달**: 엔티티를 넘기면 영속성 컨텍스트 꼬임 위험
4. **트랜잭션 경계 명확화**: 외부 호출 → 트랜잭션 없음, DB 작업 → 별도 트랜잭션

---

## 마치며

가장 크게 배운 건 **"모든 걸 하나의 트랜잭션에 넣지 말자"**가 아니라 **"적절한 경계를 구분하자"**였다.

### 핵심 요약

1. **트랜잭션 경계 결정 기준**: "이 작업이 실패하면 메인 로직도 실패해야 하는가?"
2. **동기 이벤트**: AFTER_COMMIT + REQUIRES_NEW로 독립 트랜잭션 보장
3. **비동기 이벤트**: 코루틴으로 비동기 처리하여 성능 개선
4. **외부 호출**: 트랜잭션 밖에서 실행, DB 작업만 별도 트랜잭션으로

무조건 이벤트로 분리하는 게 정답이 아니다. 각 상황에서 **"왜 분리해야 하는가?"**를 끊임없이 질문하고, 비즈니스 요구사항을 먼저 이해해야 한다.
