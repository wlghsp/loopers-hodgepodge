# CodeRabbit 리뷰 수정 가이드

## 🔴 Critical (우선 수정 필요)

### 1. OrderEventHandler - 결제 실패 시 주문 상태 처리 추가

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderEventHandler.kt`

**수정 내용**: `handlePaymentFailed` 메서드에 주문 실패 처리 로직 추가 (기존 코루틴 패턴 유지)

```kotlin
@Component
class OrderEventHandler(
    private val orderService: OrderService,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        orderService.completeOrderWithPayment(event.orderId)
    }

    // 수정: 로깅만 하던 것을 주문 실패 처리 추가 (코루틴 유지)
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentFailed(event: PaymentFailedEvent) {
        coroutineScope.launch {
            try {
                logger.info("결제 실패 처리 시작: orderId=${event.orderId}, reason=${event.reason}")

                // 주문 상태를 실패로 변경
                orderService.failOrder(event.orderId)

                logger.info("주문 실패 처리 완료: orderId=${event.orderId}")
            } catch (e: Exception) {
                logger.error("주문 실패 처리 실패: orderId=${event.orderId}", e)
                // 필요시 재시도 로직이나 알람 추가 가능
            }
        }
    }
}
```

**핵심 변경점**:
- 기존: `logger.info("결제 실패 처리: ...")` - 로깅만
- 수정: `orderService.failOrder(event.orderId)` - 주문 상태 변경 추가
- 패턴: 코루틴 유지 (다른 핸들러들과 일관성)

**추가 작업**: `OrderService`에 `failOrder` 메서드 추가 필요

```kotlin
// OrderService.kt에 추가
@Transactional
fun failOrder(orderId: Long) {
    val order = orderRepository.findByIdOrThrow(orderId)
    order.fail()
    orderRepository.save(order)
}
```

---

### 2. PaymentRecoveryService - 트랜잭션 분리 및 PG 상태 처리

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentRecoveryService.kt`

**⚠️ Self-Invocation 문제**: `@Transactional(REQUIRES_NEW)`를 같은 클래스 내부에서 호출하면 프록시를 거치지 않아 새 트랜잭션이 생성되지 않습니다.

**해결책**: 트랜잭션 처리를 별도 서비스로 분리

#### 1) 새 파일 생성: PaymentRecoveryTransactionService.kt

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionService.kt`

```kotlin
package com.loopers.domain.payment

import com.loopers.domain.order.OrderService
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional

@Service
class PaymentRecoveryTransactionService(
    private val orderService: OrderService,
    private val paymentRepository: PaymentRepository,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentSuccess(orderId: Long, payment: Payment) {
        orderService.completeOrderWithPayment(orderId)

        payment.markAsSuccess()
        paymentRepository.save(payment)

        log.info("결제 복구 완료: orderId=$orderId")
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentFailure(orderId: Long, payment: Payment, reason: String?) {
        payment.markAsFailed(reason ?: "PG에서 결제 실패")
        paymentRepository.save(payment)

        orderService.failOrder(orderId)

        log.info("결제 실패 처리 완료: orderId=$orderId, reason=${reason ?: "PG에서 결제 실패"}")
    }
}
```

#### 2) PaymentRecoveryService 수정

**전체 수정 코드**:

```kotlin
package com.loopers.domain.payment

import com.loopers.domain.order.OrderRepository
import com.loopers.domain.order.OrderService
import com.loopers.domain.order.OrderStatus
import com.loopers.infrastructure.payment.PgStrategy
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import java.time.ZonedDateTime

@Component
class PaymentRecoveryService(
    private val orderRepository: OrderRepository,
    private val paymentRepository: PaymentRepository,
    private val transactionService: PaymentRecoveryTransactionService,  // 별도 서비스 주입
    private val pgStrategies: List<PgStrategy>,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun recoverPendingPayments() {
        val cutoffTime = ZonedDateTime.now().minusMinutes(10)

        // 1. 트랜잭션 내에서 대상 조회만
        val staleOrders = findStaleOrders(cutoffTime)

        if (staleOrders.isEmpty()) return

        log.info("복구 대상 주문 발견: ${staleOrders.size}건")

        // 2. 트랜잭션 외부에서 각 주문 처리
        staleOrders.forEach { order ->
            try {
                processStaleOrder(order)
            } catch (e: Exception) {
                log.error("주문 복구 실패: orderId=${order.id}", e)
            }
        }
    }

    @Transactional(readOnly = true)
    private fun findStaleOrders(cutoffTime: ZonedDateTime) =
        orderRepository.findByStatusAndCreatedAtBefore(OrderStatus.PENDING, cutoffTime)

    private fun processStaleOrder(order: com.loopers.domain.order.Order) {
        val payment = paymentRepository.findByOrderId(order.id!!)
            .firstOrNull { it.status == PaymentStatus.PENDING }

        if (payment == null) {
            log.warn("PENDING Payment not found for orderId=${order.id}")
            return
        }

        if (payment.transactionKey == null) {
            log.warn("TransactionKey is null for orderId=${order.id}, paymentId=${payment.id}")
            return
        }

        val pgStrategy = pgStrategies.firstOrNull { it.supports(payment.paymentMethod) }
        if (pgStrategy == null) {
            log.warn("No PG strategy found for paymentMethod=${payment.paymentMethod}")
            return
        }

        // PG 조회 (트랜잭션 외부에서 실행)
        val pgStatus = pgStrategy.getPaymentStatus(order.memberId, payment.transactionKey!!)
        log.info("PG 상태 조회: orderId=${order.id}, status=${pgStatus.status}")

        // 3. PG 상태에 따라 별도 서비스의 트랜잭션 메서드 호출 (프록시를 거침)
        when (pgStatus.status) {
            "SUCCESS" -> transactionService.handlePaymentSuccess(order.id!!, payment)
            "FAILED", "CANCELED" -> transactionService.handlePaymentFailure(order.id!!, payment, pgStatus.reason)
            else -> log.info("PG에서 여전히 대기 중: orderId=${order.id}, status=${pgStatus.status}")
        }
    }
}
```

---

### 3. OrderService - 상품 조회 결과 검증

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt`

**수정할 메서드들**:

```kotlin
// loadProductsWithoutLock 메서드 수정
private fun loadProductsWithoutLock(orderItems: List<OrderItem>): Map<Long, Product> {
    val productIds = orderItems.map { it.productId }
    val products = productRepository.findAllByIdIn(productIds)

    // 검증 추가
    val foundIds = products.map { it.id }.toSet()
    val requestedIds = productIds.toSet()
    val missingIds = requestedIds - foundIds

    if (missingIds.isNotEmpty()) {
        throw CoreException(
            ErrorType.PRODUCT_NOT_FOUND,
            "상품을 찾을 수 없습니다: productIds=$missingIds"
        )
    }

    return products.associateBy { it.id }
}

// completeOrderWithPayment 메서드의 상품 조회 부분도 동일하게 수정
@Transactional
fun completeOrderWithPayment(orderId: Long) {
    val order = orderRepository.findByIdOrThrow(orderId)

    // 재고 차감을 위해 상품 조회 (락 필요)
    val productIds = order.items.map { it.productId }
    val products = productRepository.findAllByIdInWithLock(productIds)

    // 검증 추가
    val foundIds = products.map { it.id }.toSet()
    val requestedIds = productIds.toSet()
    val missingIds = requestedIds - foundIds

    if (missingIds.isNotEmpty()) {
        throw CoreException(
            ErrorType.PRODUCT_NOT_FOUND,
            "상품을 찾을 수 없습니다: productIds=$missingIds"
        )
    }

    val productMap = products.associateBy { it.id }

    // 재고 차감
    order.items.forEach { orderItem ->
        val product = productMap[orderItem.productId]!!
        product.decreaseStock(orderItem.quantity)
    }

    // 주문 완료 처리
    order.complete()
}
```

---

### 4. OrderService - 이벤트 발행 조건 수정

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt`

**옵션 1**: 항상 이벤트 발행 (추천)

```kotlin
@Transactional
fun createOrderWithCalculation(
    memberId: String,
    orderItems: List<OrderItem>,
    couponId: Long?,
    pointsToUse: Long,
): Order {
    // 주문 생성 시에는 Product를 읽기만 하므로 락 불필요
    val productMap = loadProductsWithoutLock(orderItems)

    // 쿠폰 할인 계산 및 사용 처리 - 조건부로 변경
    val discountAmount = if (couponId != null) {
        couponService.applyAndUseCouponForOrder(
            memberId = memberId,
            couponId = couponId,
            orderItems = orderItems,
            productMap = productMap
        )
    } else {
        Money.ZERO
    }

    // 주문 생성
    val order = createOrder(memberId, orderItems, productMap, discountAmount)

    // 포인트 사용
    if (pointsToUse > 0) {
        val member = memberRepository.findByMemberIdOrThrow(memberId)
        member.usePoint(pointsToUse)
    }

    val savedOrder = orderRepository.save(order)

    // 항상 이벤트 발행 (couponId nullable로 전달)
    publishOrderCreatedEvent(savedOrder, couponId)

    return savedOrder
}

private fun publishOrderCreatedEvent(savedOrder: Order, couponId: Long?) {
    eventPublisher.publishEvent(
        OrderCreatedEvent(
            orderId = savedOrder.id,
            memberId = savedOrder.memberId,
            orderAmount = savedOrder.totalAmount.amount,
            couponId = couponId, // nullable로 전달
            createdAt = java.time.Instant.now().toString(),
        )
    )
}
```

**OrderCreatedEvent도 수정**:

```kotlin
data class OrderCreatedEvent(
    val orderId: Long,
    val memberId: String,
    val orderAmount: Long,
    val couponId: Long?, // nullable로 변경
    val createdAt: String,
)
```

---

## 🟡 Major (중요)

### 5. 이벤트 Timestamp String → Instant 변경

**모든 이벤트 파일 수정**:

#### ProductLikedEvent.kt
```kotlin
package com.loopers.domain.like.event

import java.time.Instant

data class ProductLikedEvent(
    val likeId: Long,
    val memberId: Long,
    val productId: Long,
    val likedAt: Instant,
)
```

#### ProductUnlikedEvent.kt
```kotlin
package com.loopers.domain.like.event

import java.time.Instant

data class ProductUnlikedEvent(
    val productId: Long,
    val memberId: Long,
    val unlikedAt: Instant,
)
```

#### PaymentCompletedEvent.kt
```kotlin
package com.loopers.domain.payment.event

import java.time.Instant

data class PaymentCompletedEvent(
    val paymentId: Long,
    val orderId: Long,
    val memberId: String,
    val amount: Long,
    val completedAt: Instant,
)
```

#### PaymentFailedEvent.kt
```kotlin
package com.loopers.domain.payment.event

import java.time.Instant

data class PaymentFailedEvent(
    val orderId: Long,
    val reason: String,
    val failedAt: Instant,
)
```

#### OrderCreatedEvent.kt
```kotlin
package com.loopers.domain.order.event

import java.time.Instant

data class OrderCreatedEvent(
    val orderId: Long,
    val memberId: String,
    val orderAmount: Long,
    val couponId: Long?,
    val createdAt: Instant,
)
```

#### UserActionEvent.kt
```kotlin
package com.loopers.support.event

import java.time.Instant

data class UserActionEvent(
    val userId: String,
    val actionType: ActionType,
    val targetEntityType: EntityType,
    val targetEntityId: Long,
    val metadata: Map<String, String> = emptyMap(), // Any에서 String으로 변경
    val occurredAt: Instant,
)
```

**이벤트 발행하는 모든 곳 수정**:

```kotlin
// LocalDateTime.now().toString() 대신
Instant.now()
```

수정 대상 파일:
- `LikeService.kt` - publishProductLikedEvent
- `PaymentCallbackService.kt` - handlePaymentCallback
- `OrderService.kt` - publishOrderCreatedEvent

---

### 6. 이벤트 핸들러에서 중복 withContext 제거

#### DataPlatformEventHandler.kt

```kotlin
package com.loopers.infrastructure.event

import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.payment.event.PaymentCompletedEvent
import com.loopers.infrastructure.dataplatform.DataPlatformClient
import kotlinx.coroutines.CoroutineScope
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.stereotype.Component
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener
import kotlinx.coroutines.launch

@Component
class DataPlatformEventHandler(
    private val dataPlatformClient: DataPlatformClient,
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleOrderCreated(event: OrderCreatedEvent) {
        coroutineScope.launch {
            try {
                logger.info("주문 데이터 플랫폼 전송 시작: orderId=${event.orderId}")
                // withContext 제거
                dataPlatformClient.sendOrderData(
                    orderId = event.orderId,
                    memberId = event.memberId,
                    amount = event.orderAmount
                )
                logger.info("주문 데이터 플랫폼 전송 완료: orderId=${event.orderId}")
            } catch (e: Exception) {
                logger.error("주문 데이터 플랫폼 전송 실패: orderId=${event.orderId}, error=${e.message}", e)
            }
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        coroutineScope.launch {
            try {
                logger.info("결제 데이터 플랫폼 전송 시작: paymentId=${event.paymentId}")
                // withContext 제거
                dataPlatformClient.sendPaymentData(
                    paymentId = event.paymentId,
                    orderId = event.orderId,
                    memberId = event.memberId,
                    amount = event.amount
                )
                logger.info("결제 데이터 플랫폼 전송 완료: paymentId=${event.paymentId}")
            } catch (e: Exception) {
                logger.error("결제 데이터 플랫폼 전송 실패: paymentId=${event.paymentId}, error=${e.message}", e)
            }
        }
    }
}
```

#### ProductLikeEventHandler.kt

```kotlin
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun handleProductLiked(event: ProductLikedEvent) {
    coroutineScope.launch {
        try {
            // withContext 제거
            productLikeEventProcessor.processProductLiked(event.productId)
        } catch (e: Exception) {
            logger.error("좋아요 집계 실패: productId=${event.productId}", e)
        }
    }
}

@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
fun handleProductUnliked(event: ProductUnlikedEvent) {
    coroutineScope.launch {
        try {
            // withContext 제거
            productLikeEventProcessor.processProductUnliked(event.productId)
        } catch (e: Exception) {
            logger.error("좋아요 취소 집계 실패: productId=${event.productId}", e)
        }
    }
}
```

---

### 7. PaymentCallbackService - 불필요한 order 조회 제거

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt`

```kotlin
@Transactional
fun handlePaymentCallback(callback: PaymentCallback) {
    val payment = paymentRepository.findByIdOrThrow(callback.orderId)

    when (callback.status) {
        "success" -> {
            payment.markAsSuccess()

            // order 조회를 성공 분기 안으로 이동
            val order = orderRepository.findByIdOrThrow(callback.orderId)

            eventPublisher.publishEvent(
                PaymentCompletedEvent(
                    paymentId = requireNotNull(payment.id) { "Payment ID는 null일 수 없습니다" },
                    orderId = callback.orderId,
                    memberId = order.memberId,
                    amount = payment.amount.amount,
                    completedAt = java.time.Instant.now()
                )
            )
        }

        else -> {
            payment.markAsFailed(callback.message ?: "결제 실패")

            eventPublisher.publishEvent(
                PaymentFailedEvent(
                    orderId = callback.orderId,
                    reason = callback.message ?: "결제 실패",
                    failedAt = java.time.Instant.now()
                )
            )
        }
    }

    paymentRepository.save(payment)
}
```

---

## 🟢 Minor (개선)

### 8. ProductLikeEventHandler - 불필요한 의존성 제거

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt`

```kotlin
package com.loopers.domain.like.event

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.stereotype.Component
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener

@Component
class ProductLikeEventHandler(
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope,
    private val productLikeEventProcessor: ProductLikeEventProcessor
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleProductLiked(event: ProductLikedEvent) {
        coroutineScope.launch {
            try {
                productLikeEventProcessor.processProductLiked(event.productId)
            } catch (e: Exception) {
                logger.error("좋아요 집계 실패: productId=${event.productId}", e)
            }
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleProductUnliked(event: ProductUnlikedEvent) {
        coroutineScope.launch {
            try {
                productLikeEventProcessor.processProductUnliked(event.productId)
            } catch (e: Exception) {
                logger.error("좋아요 취소 집계 실패: productId=${event.productId}", e)
            }
        }
    }
}
```

**import도 제거**:
```kotlin
// 제거: import com.loopers.domain.product.ProductRepository
```

---

### 9. CoroutineConfig - PreDestroy 추가

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/config/CoroutineConfig.kt`

```kotlin
package com.loopers.config

import jakarta.annotation.PreDestroy
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.slf4j.LoggerFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration

@Configuration
class CoroutineConfig {

    private val logger = LoggerFactory.getLogger(javaClass)
    private lateinit var scope: CoroutineScope

    @Bean("eventDispatcher")
    fun eventDispatcher(): CoroutineDispatcher {
        return Dispatchers.IO.limitedParallelism(50)
    }

    @Bean("eventExceptionHandler")
    fun eventExceptionHandler(): CoroutineExceptionHandler {
        return CoroutineExceptionHandler { _, throwable ->
            logger.error("이벤트 처리 중 예외 발생", throwable)
        }
    }

    @Bean("eventCoroutineScope")
    fun eventCoroutineScope(
        eventDispatcher: CoroutineDispatcher,
        eventExceptionHandler: CoroutineExceptionHandler,
    ): CoroutineScope {
        scope = CoroutineScope(
            eventDispatcher + SupervisorJob() + eventExceptionHandler
        )
        return scope
    }

    @PreDestroy
    fun cleanup() {
        logger.info("이벤트 코루틴 스코프 종료 중...")
        if (::scope.isInitialized) {
            scope.cancel()
        }
    }
}
```

---

### 10. CircuitBreakerEventListener - 동적 등록 지원

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/config/CircuitBreakerEventListener.kt`

```kotlin
package com.loopers.config

import io.github.resilience4j.circuitbreaker.CircuitBreaker
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry
import io.github.resilience4j.circuitbreaker.event.CircuitBreakerOnStateTransitionEvent
import jakarta.annotation.PostConstruct
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component

@Component
class CircuitBreakerEventListener(
    private val circuitBreakerRegistry: CircuitBreakerRegistry,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @PostConstruct
    fun init() {
        // 기존 Circuit Breaker에 리스너 등록
        circuitBreakerRegistry.allCircuitBreakers.forEach { circuitBreaker ->
            registerEventListeners(circuitBreaker)
        }

        // 동적으로 추가되는 Circuit Breaker에도 리스너 등록
        circuitBreakerRegistry.eventPublisher
            .onEntryAdded { event ->
                val addedCircuitBreaker = event.addedEntry
                logger.info("새로운 Circuit Breaker 등록됨: ${addedCircuitBreaker.name}")
                registerEventListeners(addedCircuitBreaker)
            }

        logger.info("Circuit Breaker event listeners initialized")
    }

    private fun registerEventListeners(circuitBreaker: CircuitBreaker) {
        circuitBreaker.eventPublisher
            .onStateTransition { event: CircuitBreakerOnStateTransitionEvent ->
                logger.warn(
                    """
                    ========================================
                    Circuit Breaker State Changed!
                    Name: ${event.circuitBreakerName}
                    From: ${event.stateTransition.fromState}
                    To: ${event.stateTransition.toState}
                    ========================================
                    """.trimIndent()
                )
            }
            .onError { event ->
                logger.debug(
                    "Circuit Breaker Error: {} - {}",
                    circuitBreaker.name,
                    event.throwable.message,
                    event.throwable
                )
            }
            .onSuccess { event ->
                logger.debug("Circuit Breaker Success: ${circuitBreaker.name}")
            }
            .onCallNotPermitted { event ->
                logger.warn("Circuit Breaker Call Not Permitted: ${circuitBreaker.name} - Circuit is OPEN")
            }
    }
}
```

---

### 11. DataPlatformClient - memberId 마스킹

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/dataplatform/DataPlatformClient.kt`

```kotlin
package com.loopers.infrastructure.dataplatform

import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component

@Component
class DataPlatformClient {
    private val logger = LoggerFactory.getLogger(javaClass)

    fun sendOrderData(orderId: Long, memberId: String, amount: Long) {
        logger.info("데이터 플랫폼 전송 (더미): orderId=$orderId, memberId=${maskMemberId(memberId)}, amount=$amount")
        Thread.sleep(100)
    }

    fun sendPaymentData(paymentId: Long, orderId: Long, memberId: String, amount: Long) {
        logger.info("데이터 플랫폼 전송 (더미): paymentId=$paymentId, orderId=$orderId, memberId=${maskMemberId(memberId)}, amount=$amount")
        Thread.sleep(100)
    }

    private fun maskMemberId(memberId: String): String {
        return if (memberId.length <= 3) {
            "*".repeat(memberId.length)
        } else {
            memberId.take(2) + "*".repeat(memberId.length - 2)
        }
    }
}
```

---

### 12. 테스트 - 이벤트 발행 검증 추가

**파일**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/order/OrderServiceTest.kt`

```kotlin
@Test
fun `createOrderWithCouponAndPoint - 쿠폰과 포인트를 사용하여 주문을 생성한다`() {
    // given
    val memberId = "testuser01"
    val member = Member.of(MemberId(memberId), "테스트", "test@example.com")
    val product1 = createProduct(1L, "상품1", 10000L, 100)
    val product2 = createProduct(2L, "상품2", 20000L, 50)

    val orderItems = listOf(
        OrderItem(productId = 1L, productName = "상품1", quantity = 2, price = Money.of(10000)),
        OrderItem(productId = 2L, productName = "상품2", quantity = 1, price = Money.of(20000)),
    )

    every { memberRepository.findByMemberIdOrThrow(memberId) } returns member
    every { productRepository.findAllByIdIn(any()) } returns listOf(product1, product2)
    every { couponService.applyAndUseCouponForOrder(any(), any(), any(), any()) } returns Money.of(5000)
    every { orderRepository.save(any()) } answers { firstArg() }

    // 이벤트 캡처 추가
    val eventSlot = slot<OrderCreatedEvent>()
    every { eventPublisher.publishEvent(capture(eventSlot)) } just Runs

    // when
    val result = orderService.createOrderWithCalculation(
        memberId = memberId,
        orderItems = orderItems,
        couponId = 1L,
        pointsToUse = 3000L,
    )

    // then
    verify(exactly = 1) { couponService.applyAndUseCouponForOrder(any(), any(), any(), any()) }
    verify(exactly = 1) { member.usePoint(3000L) }

    // 이벤트 발행 검증 추가
    verify(exactly = 1) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
    assertThat(eventSlot.captured.orderId).isEqualTo(result.id)
    assertThat(eventSlot.captured.memberId).isEqualTo(memberId)
    assertThat(eventSlot.captured.couponId).isEqualTo(1L)
}
```

---

## 📝 수정 순서 추천

1. **5번** - 이벤트 Timestamp 변경 (모든 이벤트 + 발행처)
2. **1번** - OrderEventHandler 결제 실패 처리
3. **3번** - OrderService 상품 조회 검증
4. **2번** - PaymentRecoveryService 트랜잭션 분리
5. **4번** - OrderService 이벤트 발행 조건
6. **6번** - 중복 withContext 제거
7. **7번** - PaymentCallbackService order 조회 최적화
8. **8-12번** - 나머지 개선 사항들

---

## ✅ 수정 완료 체크리스트

- [ ] 1. OrderEventHandler - 결제 실패 처리
- [ ] 2. PaymentRecoveryService - 트랜잭션 분리
- [ ] 3. OrderService - 상품 조회 검증
- [ ] 4. OrderService - 이벤트 발행 조건
- [ ] 5. 이벤트 Timestamp 변경
- [ ] 6. 중복 withContext 제거
- [ ] 7. PaymentCallbackService 최적화
- [ ] 8. ProductLikeEventHandler 의존성 제거
- [ ] 9. CoroutineConfig PreDestroy
- [ ] 10. CircuitBreakerEventListener 동적 등록
- [ ] 11. DataPlatformClient memberId 마스킹
- [ ] 12. 테스트 이벤트 검증
