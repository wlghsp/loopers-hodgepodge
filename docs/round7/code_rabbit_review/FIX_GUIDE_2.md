# CodeRabbit 2차 리뷰 수정 가이드

> **📌 아키텍처 변경 노트**: 이 가이드 작성 이후 UserActionEvent 아키텍처가 개선되었습니다.
> - **변경 내용**: 도메인 서비스(LikeService 등)는 도메인 이벤트만 발행하고, UserActionEvent는 전용 EventHandler(ProductLikeEventHandler, UserActionTrackingEventHandler)에서 발행하도록 관심사 분리
> - **영향받는 이슈**: Issue #2 (현재 코드 반영), Issue #8 (자연스럽게 해결됨)
> - **참고 문서**: `.codeguide/round7/USER_ACTION_EVENT_GUIDE.md`

## 🔴 Critical (즉시 수정 필요)

### 1. PaymentRecoveryTransactionService - 로그 문자열 컴파일 에러

**파일**: `PaymentRecoveryTransactionService.kt:33`

**문제**:
- 단일 따옴표 `'` 사용으로 컴파일 에러 (Kotlin에서 `'`는 Char 타입)
- 중괄호 `{}`는 Kotlin 문자열 템플릿이 아니라 단순 문자로 출력됨

```kotlin
// ❌ Before (현재 코드)
logger.info("결제 실패 처리 완료: orderId=$orderId, reason={$reason ?: 'PG에서 결제 실패'}")

// ✅ After (옵션 1: Kotlin 문자열 템플릿)
logger.info("결제 실패 처리 완료: orderId=$orderId, reason=${reason ?: \"PG에서 결제 실패\"}")

// ✅ After (옵션 2: SLF4J 플레이스홀더 - 권장)
logger.info("결제 실패 처리 완료: orderId={}, reason={}", orderId, reason ?: "PG에서 결제 실패")
```

**권장**: SLF4J 플레이스홀더 방식(`{}`)을 사용하면 로그 레벨이 비활성화된 경우 문자열 보간을 건너뛰어 성능상 이점이 있습니다.

---

### 2. LikeService - 동시성 멱등성 보장 안됨

**파일**: `LikeService.kt:26-42`

**문제**:
- `existingLike` 체크가 원자적이지 않음
- 동시 요청 시 둘 다 `null`로 판단 → 중복 insert 시도
- DB 유니크 제약으로 `DataIntegrityViolationException` 발생 → 500 에러

**현재 상태**:
```kotlin
@Transactional
fun addLike(memberId: String, productId: Long): Like {
    val member = memberRepository.findByMemberIdOrThrow(memberId)

    // 이미 좋아요가 있으면 기존 것 반환 (멱등성 보장)
    val existingLike = likeRepository.findByMemberIdAndProductId(member.id, productId)
    if (existingLike != null) {
        return existingLike
    }

    // 좋아요 저장 (집계는 제거)
    val product = productRepository.findByIdOrThrow(productId)
    val like = Like.of(member, product)
    val savedLike = likeRepository.save(like)

    // 이벤트 발행 (ProductLikedEvent만 발행, UserActionEvent는 EventHandler에서 발행)
    publishProductLikedEvent(savedLike, member, productId)

    return savedLike
}
```

**해결 방법**: try-catch로 동시성 처리

```kotlin
@Transactional
fun addLike(memberId: String, productId: Long): Like {
    val member = memberRepository.findByMemberIdOrThrow(memberId)

    // 기존 좋아요 확인
    val existingLike = likeRepository.findByMemberIdAndProductId(member.id, productId)
    if (existingLike != null) {
        return existingLike
    }

    try {
        // 좋아요 저장
        val product = productRepository.findByIdOrThrow(productId)
        val like = Like.of(member, product)
        val savedLike = likeRepository.save(like)

        // 이벤트 발행 (ProductLikedEvent만, UserActionEvent는 ProductLikeEventHandler에서 발행)
        eventPublisher.publishEvent(
            ProductLikedEvent(
                likeId = savedLike.id,
                memberId = member.id,
                productId = productId,
                likedAt = Instant.now()
            )
        )

        return savedLike
    } catch (e: DataIntegrityViolationException) {
        // 동시 요청으로 인한 중복 insert 시도 - 기존 데이터 반환
        return likeRepository.findByMemberIdAndProductId(member.id, productId)
            ?: throw CoreException(ErrorType.INTERNAL_ERROR, "좋아요 생성 중 오류 발생")
    }
}
```

---

### 3. PaymentRecoveryTransactionService - REQUIRES_NEW에 엔티티 파라미터 전달

**파일**: `PaymentRecoveryTransactionService.kt:18-32`

**문제**:
- 외부 컨텍스트의 엔티티를 새 트랜잭션에 전달
- 영속성 컨텍스트 꼬임 위험 (merge/detach/stale update)

**해결 방법**: ID만 전달하고 내부에서 재조회

```kotlin
@Component
class PaymentRecoveryTransactionService(
    private val orderService: OrderService,
    private val paymentRepository: PaymentRepository,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentSuccess(orderId: Long, paymentId: Long) {
        val payment = paymentRepository.findByIdOrThrow(paymentId)

        orderService.completeOrderWithPayment(orderId)

        payment.markAsSuccess()
        paymentRepository.save(payment)

        logger.info("결제 복구 완료: orderId=$orderId")
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentFailure(orderId: Long, paymentId: Long, reason: String?) {
        val payment = paymentRepository.findByIdOrThrow(paymentId)

        payment.markAsFailed(reason ?: "PG에서 결제 실패")
        paymentRepository.save(payment)

        orderService.failOrder(orderId)

        logger.info("결제 실패 처리 완료: orderId=$orderId, reason=${reason ?: \"PG에서 결제 실패\"}")
    }
}
```

**PaymentRecoveryService 호출부도 수정**:

```kotlin
when (pgStatus.status) {
    "SUCCESS" -> transactionService.handlePaymentSuccess(order.id!!, payment.id!!)
    "FAILED", "CANCELED" -> transactionService.handlePaymentFailure(order.id!!, payment.id!!, pgStatus.reason)
    else -> logger.info("PG에서 여전히 대기 중: orderId=${order.id}, status=${pgStatus.status}")
}
```

---

## 🟠 Major (중요)

### 4. ProductLikeEventHandler - 비동기 집계 실패 시 재시도/복구 전략 없음

**파일**: `ProductLikeEventHandler.kt:16-33`

**문제**:
- 예외 발생 시 로그만 남기고 이벤트 유실
- `Dispatchers.IO.limitedParallelism(50)` 큐는 무제한 → 이벤트 폭주 시 메모리 압박
- 복구 메커니즘 없음

**현재 상태**:
```kotlin
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun handleProductLiked(event: ProductLikedEvent) {
    coroutineScope.launch {
        try {
            productLikeEventProcessor.processProductLiked(event.productId)
        } catch (e: Exception) {
            logger.error("좋아요 집계 실패: productId=${event.productId}", e)
            // 여기서 끝! 재시도 없음
        }
    }
}
```

**권장 해결책** (선택):

**옵션 1: Resilience4j Retry 적용**
```kotlin
@Component
class ProductLikeEventProcessor(
    private val productRepository: ProductRepository,
    @Qualifier("likeRetry") private val retry: Retry
) {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun processProductLiked(productId: Long) {
        retry.executeSupplier {
            val product = productRepository.findByIdWithLockOrThrow(productId)
            product.increaseLikesCount()
            productRepository.save(product)
        }
    }
}
```

**옵션 2: 실패 이벤트를 Outbox 테이블에 저장**
```kotlin
catch (e: Exception) {
    logger.error("좋아요 집계 실패: productId=${event.productId}", e)
    // Outbox 테이블에 저장하여 나중에 재시도
    failedEventRepository.save(FailedEvent(
        eventType = "ProductLiked",
        payload = event.toJson(),
        error = e.message
    ))
}
```

**옵션 3: 메트릭/알람 추가**
```kotlin
catch (e: Exception) {
    logger.error("좋아요 집계 실패: productId=${event.productId}", e)
    meterRegistry.counter("like.aggregate.failure").increment()
}
```

**→ 일단은 로깅만 하고 넘어가되, PR에 코멘트 남기기**

---

### 5. PaymentRecoveryService - PG 조회가 여전히 트랜잭션 내부

**파일**: `PaymentRecoveryService.kt:20-40`

**문제**:
- `recoverPendingPayments()`에서 `@Transactional` 제거했지만
- `processStaleOrder()`에서 PG 조회하는 부분이 여전히 DB 커넥션을 점유할 수 있음

**현재 상태**:
```kotlin
// @Transactional 제거됨 ✅
fun recoverPendingPayments() {
    val cutoffTime = ZonedDateTime.now().minusMinutes(10)
    val staleOrders = findStaleOrders(cutoffTime)

    staleOrders.forEach { order ->
        try {
            processStaleOrder(order) // 여기서 PG 조회
        } catch (e: Exception) {
            logger.error("주문 복구 실패: orderId=${order.id}", e)
        }
    }
}

@Transactional(readOnly = true)
private fun findStaleOrders(cutoffTime: ZonedDateTime) =
    orderRepository.findByStatusAndCreatedAtBefore(OrderStatus.PENDING, cutoffTime)
```

**→ 이미 트랜잭션 밖으로 빠져있으므로 OK. 단, `findStaleOrders`는 read-only 트랜잭션으로 최소화됨**

---

### 6. OrderServiceTest - 이벤트 검증 불완전

**파일**: `OrderServiceTest.kt:98-101`

**문제**: `orderAmount`, `createdAt` 검증 누락

```kotlin
// ❌ Before
verify(exactly = 1) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
assertThat(eventSlot.captured.orderId).isEqualTo(result.id)
assertThat(eventSlot.captured.memberId).isEqualTo(memberId)
assertThat(eventSlot.captured.couponId).isEqualTo(1L)

// ✅ After
verify(exactly = 1) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
assertThat(eventSlot.captured.orderId).isEqualTo(result.id)
assertThat(eventSlot.captured.memberId).isEqualTo(memberId)
assertThat(eventSlot.captured.orderAmount).isEqualTo(result.totalAmount.amount)
assertThat(eventSlot.captured.couponId).isEqualTo(1L)
assertThat(eventSlot.captured.createdAt).isNotNull()
```

---

## 🟡 Minor (선택 사항)

### 7. CircuitBreakerEventListener - 에러 로깅 레벨

**파일**: `CircuitBreakerEventListener.kt:48-55`

**제안**: `DEBUG` → `WARN` 으로 변경

```kotlin
// ❌ Before
.onError { event ->
    logger.debug("Circuit Breaker Error: {} - {}", ...)
}

// ✅ After
.onError { event ->
    logger.warn("Circuit Breaker Error: {} - {}", ...)
}
```

---

### 8. ~~LikeService - 동일 Instant 재사용~~ (해결됨)

**파일**: ~~`LikeService.kt:47-73`~~

**상태**: ✅ **이미 해결됨**

**설명**:
- UserActionEvent 발행은 LikeService에서 제거되고 ProductLikeEventHandler로 이동
- LikeService는 ProductLikedEvent/ProductUnlikedEvent만 발행하므로 Instant.now()를 한 번만 호출
- 이벤트 아키텍처 개선으로 자연스럽게 해결됨

---

### 9. PaymentRecoveryService - findByOrderId 최적화

**파일**: `PaymentRecoveryService.kt:42-45`

**제안**: 리포지토리 레벨에서 필터링

```kotlin
// ❌ Before
val payment = paymentRepository.findByOrderId(order.id!!)
    .firstOrNull { it.status == PaymentStatus.PENDING }

// ✅ After (Repository 추가)
interface PaymentRepository {
    fun findPendingByOrderId(orderId: Long): Payment?
}

// Service
val payment = paymentRepository.findPendingByOrderId(order.id!!)
```

---

### 10. OrderServiceTest - 쿠폰 없는 케이스 테스트 추가

**제안**: `couponId = null` 케이스 테스트 추가

```kotlin
@DisplayName("쿠폰 없이 주문을 생성하고 이벤트를 발행한다")
@Test
fun createOrderWithoutCouponAndPublishEvent() {
    // given
    val memberId = "testuser01"
    val product = mockk<Product>(relaxed = true) {
        every { id } returns 1L
        every { name } returns "상품1"
        every { price } returns Money.of(10000L)
        every { validateStock(any()) } just Runs
    }
    val member = mockk<Member>(relaxed = true) {
        every { point.amount } returns 50000L
    }
    val orderItems = listOf(OrderItemCommand(productId = 1L, quantity = 1))

    every { productRepository.findAllByIdIn(any()) } returns listOf(product)
    every { memberRepository.findByMemberIdWithLockOrThrow(memberId) } returns member
    every { couponService.applyAndUseCouponForOrder(any(), any(), any(), any()) } returns Money.zero()
    every { orderRepository.save(any()) } answers { firstArg() }

    val eventSlot = slot<OrderCreatedEvent>()
    every { eventPublisher.publishEvent(capture(eventSlot)) } just Runs

    // when
    val result = orderService.createOrderWithCalculation(
        memberId = memberId,
        orderItems = orderItems,
        couponId = null,
        usePoint = 0L,
    )

    // then
    verify(exactly = 1) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
    assertThat(eventSlot.captured.orderId).isEqualTo(result.id)
    assertThat(eventSlot.captured.memberId).isEqualTo(memberId)
    assertThat(eventSlot.captured.couponId).isNull()
}
```

---

## 📋 수정 우선순위

### 즉시 수정 (Critical)
1. ✅ PaymentRecoveryTransactionService 로그 문자열 수정
2. ✅ LikeService 동시성 멱등성 보장 (try-catch 추가)
3. ✅ PaymentRecoveryTransactionService REQUIRES_NEW 파라미터 수정

### 중요 (Major)
4. ⚠️ ProductLikeEventHandler 재시도 전략 (일단 넘어가고 PR 코멘트)
5. ✅ OrderServiceTest 이벤트 검증 보완

### 선택 사항 (Minor)
6. CircuitBreakerEventListener 로그 레벨
7. ~~LikeService Instant 재사용~~ (아키텍처 개선으로 해결됨)
8. PaymentRecoveryService 쿼리 최적화
9. 쿠폰 없는 케이스 테스트 추가

---

## 🤔 논의 필요

### ProductLikeEventHandler 재시도 전략
- 현재: 실패 시 로그만 남김
- 옵션: Resilience4j Retry, Outbox 패턴, 메트릭/알람
- **결정**: 일단 로그만 남기고, 운영 중 실패율 모니터링 후 필요시 추가

### PaymentRecoveryService PG 조회
- CodeRabbit 지적: 여전히 트랜잭션 내부
- 실제: `@Transactional` 제거되어 트랜잭션 밖
- **결론**: 이미 해결됨

---

## 📝 추가 구현 사항 (가이드 작성 이후)

### UserActionEvent 아키텍처 구현 완료

**구현된 ActionType**:
- `VIEW` - 상품 상세 조회 (ProductViewedEvent → UserActionEvent)
- `BROWSE` - 상품 목록 조회 (ProductBrowsedEvent → UserActionEvent)
- `LIKE` - 상품 좋아요 (ProductLikedEvent → UserActionEvent)
- `UNLIKE` - 상품 좋아요 취소 (ProductUnlikedEvent → UserActionEvent)
- `ORDER` - 주문 생성 (OrderCreatedEvent → UserActionEvent)

**주요 파일**:
- `UserActionEvent.kt` - ActionType enum에 BROWSE, UNLIKE 추가
- `ProductBrowsedEvent.kt` - 새로 생성
- `ProductLikeEventHandler.kt` - LIKE/UNLIKE → UserActionEvent 변환
- `UserActionTrackingEventHandler.kt` - VIEW/BROWSE/ORDER → UserActionEvent 변환
- `ProductV1Controller.kt` - getProducts()에 ProductBrowsedEvent 발행 추가

**아키텍처 원칙**:
- 도메인 서비스는 도메인 이벤트만 발행 (ProductLikedEvent, OrderCreatedEvent 등)
- EventHandler가 UserActionEvent로 변환하여 DataPlatform으로 전송
- 비회원 사용자는 도메인 이벤트는 발행되지만 UserActionEvent는 발행되지 않음 (analytics tracking 제외)

**참고 문서**: `.codeguide/round7/USER_ACTION_EVENT_GUIDE.md` (전체 구현 가이드)
