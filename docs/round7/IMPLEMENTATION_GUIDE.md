# ApplicationEvent 기반 트랜잭션 분리 구현 가이드

## 파일 구조

```
apps/commerce-api/src/main/kotlin/com/loopers/
├── domain/
│   ├── order/
│   │   ├── event/
│   │   │   └── OrderCreatedEvent.kt                    # 생성 필요
│   │   └── OrderService.kt                             # 수정 필요
│   ├── payment/
│   │   ├── event/
│   │   │   ├── PaymentCompletedEvent.kt                # 생성 필요
│   │   │   └── PaymentFailedEvent.kt                   # 생성 필요
│   │   └── PaymentCallbackService.kt                   # 수정 필요
│   ├── coupon/
│   │   ├── event/
│   │   │   └── CouponEventHandler.kt                   # 생성 필요
│   │   └── CouponService.kt                            # 수정 필요 (기존 로직 유지, 이벤트 핸들러에서 호출)
│   ├── like/
│   │   ├── event/
│   │   │   ├── ProductLikedEvent.kt                    # 생성 필요
│   │   │   └── ProductLikeEventHandler.kt              # 생성 필요
│   │   └── LikeService.kt                              # 수정 필요
│   └── statistics/
│       └── ProductStatisticsService.kt                 # 생성 필요 (좋아요 집계 로직)
├── infrastructure/
│   ├── event/
│   │   ├── DataPlatformEventHandler.kt                 # 생성 필요
│   │   └── UserActionEventHandler.kt                   # 생성 필요
│   └── dataplatform/
│       └── DataPlatformClient.kt                       # 생성 필요 (더미 구현)
├── config/
│   └── AsyncConfig.kt                                  # 생성 필요
└── support/
    └── event/
        └── UserActionEvent.kt                          # 생성 필요
```

---

## 1. 주문 생성 이벤트

### 1-1. OrderCreatedEvent.kt 생성
**경로**: `domain/order/event/OrderCreatedEvent.kt`

```kotlin
package com.loopers.domain.order.event

data class OrderCreatedEvent(
    val orderId: Long,
    val memberId: String,
    val orderAmount: Long,
    val couponId: Long?,
    val createdAt: String
)
```

### 1-2. OrderService.kt 수정
**기존**: `createOrderWithCalculation` 메서드에서 직접 쿠폰 사용 처리
**변경**: 주문 생성 후 이벤트 발행

```kotlin
package com.loopers.domain.order

import com.loopers.domain.order.event.OrderCreatedEvent
import org.springframework.context.ApplicationEventPublisher
// ... 기타 import

@Component
class OrderService(
    private val orderRepository: OrderRepository,
    private val productRepository: ProductRepository,
    private val memberRepository: MemberRepository,
    private val eventPublisher: ApplicationEventPublisher,  // 추가
    // couponService 제거 (이벤트로 분리)
) {
    @Transactional
    fun createOrderWithCalculation(
        memberId: String,
        orderItems: List<OrderItemCommand>,
        couponId: Long? = null,
        usePoint: Long = 0L
    ): Order {
        val productMap = loadProducts(orderItems)
        val member = memberRepository.findByMemberIdWithLockOrThrow(memberId)

        // 주문 생성 (쿠폰 적용 로직은 제거, 할인 없이 생성)
        val order = Order.create(
            memberId = memberId,
            orderItems = orderItems,
            productMap = productMap,
            discountAmount = 0L  // 일단 할인 없이 생성
        )

        // 포인트 사용 검증 및 차감
        val finalPaymentAmount = order.finalAmount.amount - usePoint
        if (finalPaymentAmount < 0) {
            throw CoreException(
                ErrorType.BAD_REQUEST,
                "포인트를 너무 많이 사용했습니다."
            )
        }

        if (usePoint > 0) {
            member.usePoint(usePoint)
        }

        val savedOrder = orderRepository.save(order)

        // 이벤트 발행 (트랜잭션 커밋 후 실행됨)
        if (couponId != null) {
            eventPublisher.publishEvent(
                OrderCreatedEvent(
                    orderId = savedOrder.id!!,
                    memberId = memberId,
                    orderAmount = savedOrder.totalAmount.amount,
                    couponId = couponId,
                    createdAt = savedOrder.createdAt.toString()
                )
            )
        }

        return savedOrder
    }

    // completeOrderWithPayment 등 나머지 메서드는 그대로 유지
}
```

---

## 2. 쿠폰 사용 처리 이벤트 핸들러

### 2-1. CouponEventHandler.kt 생성
**경로**: `domain/coupon/event/CouponEventHandler.kt`

```kotlin
package com.loopers.domain.coupon.event

import com.loopers.domain.coupon.CouponService
import com.loopers.domain.order.event.OrderCreatedEvent
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener

@Component
class CouponEventHandler(
    private val couponService: CouponService
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handleOrderCreated(event: OrderCreatedEvent) {
        try {
            logger.info("쿠폰 사용 처리 시작: orderId=${event.orderId}, couponId=${event.couponId}")

            // TODO: 쿠폰 사용 처리 로직
            // couponService에서 쿠폰 사용 메서드 호출
            // 실패 시에도 주문은 이미 생성된 상태로 유지됨
    
            logger.info("쿠폰 사용 처리 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("쿠폰 사용 처리 실패: orderId=${event.orderId}, error=${e.message}", e)
            // 주문은 이미 생성되었으므로 예외를 던지지 않음
        }
    }
}
```

---

## 3. 결제 이벤트

### 3-1. PaymentCompletedEvent.kt 생성
**경로**: `domain/payment/event/PaymentCompletedEvent.kt`

```kotlin
package com.loopers.domain.payment.event

data class PaymentCompletedEvent(
    val paymentId: Long,
    val orderId: Long,
    val amount: Long,
    val completedAt: String
)
```

### 3-2. PaymentFailedEvent.kt 생성
**경로**: `domain/payment/event/PaymentFailedEvent.kt`

```kotlin
package com.loopers.domain.payment.event

data class PaymentFailedEvent(
    val paymentId: Long,
    val orderId: Long,
    val reason: String,
    val failedAt: String
)
```

### 3-3. PaymentCallbackService.kt 수정
**기존**: 결제 성공/실패 시 직접 주문 상태 변경
**변경**: 이벤트 발행으로 분리

```kotlin
package com.loopers.domain.payment

import com.loopers.domain.payment.event.PaymentCompletedEvent
import com.loopers.domain.payment.event.PaymentFailedEvent
import org.springframework.context.ApplicationEventPublisher
import java.time.LocalDateTime
// ... 기타 import

@Component
class PaymentCallbackService(
    private val paymentRepository: PaymentRepository,
    private val orderRepository: OrderRepository,
    private val eventPublisher: ApplicationEventPublisher  // 추가
    // orderService 제거
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @Transactional
    fun handlePaymentCallback(callback: PaymentCallbackDto) {
        logger.info("결제 콜백 수신: transactionKey=${callback.transactionKey}")

        val payment = paymentRepository.findByTransactionKey(callback.transactionKey)
            ?: throw CoreException(ErrorType.PAYMENT_NOT_FOUND, "결제 정보를 찾을 수 없습니다.")

        if (payment.status != PaymentStatus.PENDING) {
            logger.warn("이미 처리된 결제: paymentId=${payment.id}")
            return
        }

        if (callback.isSuccess()) {
            payment.markAsSuccess()

            // 이벤트 발행 (주문 완료 처리는 이벤트 핸들러에서)
            eventPublisher.publishEvent(
                PaymentCompletedEvent(
                    paymentId = payment.id!!,
                    orderId = payment.orderId,
                    amount = payment.amount.amount,
                    completedAt = LocalDateTime.now().toString()
                )
            )
            logger.info("결제 완료 이벤트 발행: orderId=${payment.orderId}")
        } else {
            payment.markAsFailed(callback.reason ?: "결제 실패")

            // 이벤트 발행
            eventPublisher.publishEvent(
                PaymentFailedEvent(
                    paymentId = payment.id!!,
                    orderId = payment.orderId,
                    reason = callback.reason ?: "결제 실패",
                    failedAt = LocalDateTime.now().toString()
                )
            )
            logger.warn("결제 실패 이벤트 발행: orderId=${payment.orderId}")
        }
    }
}
```

### 3-4. OrderEventHandler.kt 생성
**경로**: `domain/order/event/OrderEventHandler.kt`

```kotlin
package com.loopers.domain.order.event

import com.loopers.domain.order.OrderService
import com.loopers.domain.order.OrderRepository
import com.loopers.domain.payment.event.PaymentCompletedEvent
import com.loopers.domain.payment.event.PaymentFailedEvent
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener

@Component
class OrderEventHandler(
    private val orderService: OrderService,
    private val orderRepository: OrderRepository
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        try {
            logger.info("결제 완료 처리 시작: orderId=${event.orderId}")
            orderService.completeOrderWithPayment(event.orderId)
            logger.info("결제 완료 처리 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("결제 완료 처리 실패: orderId=${event.orderId}, error=${e.message}", e)
            throw e
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handlePaymentFailed(event: PaymentFailedEvent) {
        try {
            logger.info("결제 실패 처리 시작: orderId=${event.orderId}")
            val order = orderRepository.findByIdOrThrow(event.orderId)
            order.fail()
            logger.info("결제 실패 처리 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("결제 실패 처리 실패: orderId=${event.orderId}, error=${e.message}", e)
            throw e
        }
    }
}
```

---

## 4. 좋아요 이벤트

### 4-1. ProductLikedEvent.kt 생성
**경로**: `domain/like/event/ProductLikedEvent.kt`

```kotlin
package com.loopers.domain.like.event

data class ProductLikedEvent(
    val likeId: Long,
    val memberId: Long,
    val productId: Long,
    val likedAt: String
)
```

### 4-2. LikeService.kt 수정
**기존**: 좋아요 저장 시 같은 트랜잭션에서 likesCount 증가
**변경**: 좋아요 저장 후 이벤트 발행, likesCount는 이벤트 핸들러에서 처리

```kotlin
package com.loopers.domain.like

import com.loopers.domain.like.event.ProductLikedEvent
import org.springframework.context.ApplicationEventPublisher
import java.time.LocalDateTime
// ... 기타 import

@Component
class LikeService(
    private val likeRepository: LikeRepository,
    private val memberRepository: MemberRepository,
    private val productRepository: ProductRepository,
    private val eventPublisher: ApplicationEventPublisher  // 추가
) {

    @Transactional
    fun addLike(memberId: String, productId: Long): Like {
        val member = memberRepository.findByMemberIdOrThrow(memberId)

        // 이미 좋아요가 있으면 기존 것 반환
        val existingLike = likeRepository.findByMemberIdAndProductId(member.id, productId)
        if (existingLike != null) {
            return existingLike
        }

        // 좋아요 저장 (집계는 제거)
        val product = productRepository.findByIdOrThrow(productId)  // 락 제거
        val like = Like.of(member, product)
        val savedLike = likeRepository.save(like)

        // 이벤트 발행 (집계는 이벤트 핸들러에서)
        eventPublisher.publishEvent(
            ProductLikedEvent(
                likeId = savedLike.id!!,
                memberId = member.id,
                productId = productId,
                likedAt = LocalDateTime.now().toString()
            )
        )

        return savedLike
    }

    @Transactional
    fun cancelLike(memberId: String, productId: Long) {
        val member = memberRepository.findByMemberIdOrThrow(memberId)
        val like = likeRepository.findByMemberIdAndProductId(member.id, productId)
            ?: return

        // 좋아요 삭제 (집계 감소는 별도 이벤트로 처리 가능)
        likeRepository.deleteByMemberIdAndProductId(member.id, productId)

        // TODO: ProductUnlikedEvent 발행 (선택사항)
    }

    // getMyLikes는 그대로 유지
}
```

### 4-3. ProductLikeEventHandler.kt 생성
**경로**: `domain/like/event/ProductLikeEventHandler.kt`

```kotlin
package com.loopers.domain.like.event

import com.loopers.domain.product.ProductRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Propagation
import org.springframework.transaction.annotation.Transactional
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener

@Component
class ProductLikeEventHandler(
    private val productRepository: ProductRepository
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    fun handleProductLiked(event: ProductLikedEvent) {
        try {
            logger.info("좋아요 집계 시작: productId=${event.productId}, likeId=${event.likeId}")

            val product = productRepository.findByIdWithLockOrThrow(event.productId)
            product.increaseLikesCount()

            logger.info("좋아요 집계 완료: productId=${event.productId}")
        } catch (e: Exception) {
            logger.error("좋아요 집계 실패: productId=${event.productId}, error=${e.message}", e)
            // 집계 실패해도 좋아요는 이미 저장되었으므로 예외를 던지지 않음
            // 재시도 로직이나 보상 트랜잭션 필요 시 여기에 추가
        }
    }
}
```

---

## 5. 데이터 플랫폼 전송

### 5-1. DataPlatformClient.kt 생성 (더미)
**경로**: `infrastructure/dataplatform/DataPlatformClient.kt`

```kotlin
package com.loopers.infrastructure.dataplatform

import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component

@Component
class DataPlatformClient {
    private val logger = LoggerFactory.getLogger(javaClass)

    fun sendOrderData(orderId: Long, memberId: String, amount: Long) {
        logger.info("데이터 플랫폼 전송 (더미): orderId=$orderId, memberId=$memberId, amount=$amount")
        // 실제로는 HTTP API 호출 등
        Thread.sleep(100) // 네트워크 지연 시뮬레이션
    }

    fun sendPaymentData(paymentId: Long, orderId: Long, amount: Long) {
        logger.info("데이터 플랫폼 전송 (더미): paymentId=$paymentId, orderId=$orderId, amount=$amount")
        Thread.sleep(100)
    }
}
```

### 5-2. DataPlatformEventHandler.kt 생성
**경로**: `infrastructure/event/DataPlatformEventHandler.kt`

```kotlin
package com.loopers.infrastructure.event

import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.payment.event.PaymentCompletedEvent
import com.loopers.infrastructure.dataplatform.DataPlatformClient
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Async
import org.springframework.stereotype.Component
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener

@Component
class DataPlatformEventHandler(
    private val dataPlatformClient: DataPlatformClient
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleOrderCreated(event: OrderCreatedEvent) {
        try {
            logger.info("주문 데이터 플랫폼 전송 시작: orderId=${event.orderId}")
            dataPlatformClient.sendOrderData(
                orderId = event.orderId,
                memberId = event.memberId,
                amount = event.orderAmount
            )
            logger.info("주문 데이터 플랫폼 전송 완료: orderId=${event.orderId}")
        } catch (e: Exception) {
            logger.error("주문 데이터 플랫폼 전송 실패: orderId=${event.orderId}, error=${e.message}", e)
            // 실패해도 주문에는 영향 없음
        }
    }

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handlePaymentCompleted(event: PaymentCompletedEvent) {
        try {
            logger.info("결제 데이터 플랫폼 전송 시작: paymentId=${event.paymentId}")
            dataPlatformClient.sendPaymentData(
                paymentId = event.paymentId,
                orderId = event.orderId,
                amount = event.amount
            )
            logger.info("결제 데이터 플랫폼 전송 완료: paymentId=${event.paymentId}")
        } catch (e: Exception) {
            logger.error("결제 데이터 플랫폼 전송 실패: paymentId=${event.paymentId}, error=${e.message}", e)
        }
    }
}
```

---

## 6. 사용자 행동 로깅

### 6-1. UserActionEvent.kt 생성
**경로**: `support/event/UserActionEvent.kt`

```kotlin
package com.loopers.support.event

data class UserActionEvent(
    val userId: String,
    val actionType: ActionType,
    val targetEntityType: EntityType,
    val targetEntityId: Long,
    val metadata: Map<String, Any> = emptyMap(),
    val occurredAt: String
)

enum class ActionType {
    VIEW,
    CLICK,
    LIKE,
    ORDER,
    SEARCH
}

enum class EntityType {
    PRODUCT,
    ORDER,
    BRAND
}
```

### 6-2. UserActionEventHandler.kt 생성
**경로**: `infrastructure/event/UserActionEventHandler.kt`

```kotlin
package com.loopers.infrastructure.event

import com.loopers.support.event.UserActionEvent
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Async
import org.springframework.stereotype.Component
import org.springframework.transaction.event.TransactionPhase
import org.springframework.transaction.event.TransactionalEventListener

@Component
class UserActionEventHandler {
    private val logger = LoggerFactory.getLogger(javaClass)

    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    fun handleUserAction(event: UserActionEvent) {
        // 사용자 행동 로그 적재
        logger.info(
            "USER_ACTION: userId=${event.userId}, " +
            "action=${event.actionType}, " +
            "entity=${event.targetEntityType}:${event.targetEntityId}, " +
            "metadata=${event.metadata}, " +
            "at=${event.occurredAt}"
        )

        // 실제로는 Kafka, Kinesis, 파일 등에 적재
    }
}
```

### 6-3. 각 도메인에서 이벤트 발행 예시
**LikeService에 추가 예시**:

```kotlin
// addLike 메서드에서
eventPublisher.publishEvent(
    UserActionEvent(
        userId = memberId,
        actionType = ActionType.LIKE,
        targetEntityType = EntityType.PRODUCT,
        targetEntityId = productId,
        metadata = mapOf("likeId" to savedLike.id!!),
        occurredAt = LocalDateTime.now().toString()
    )
)
```

---

## 7. Async 설정

### 7-1. AsyncConfig.kt 생성
**경로**: `config/AsyncConfig.kt`

```kotlin
package com.loopers.config

import org.slf4j.LoggerFactory
import org.springframework.aop.interceptor.AsyncUncaughtExceptionHandler
import org.springframework.context.annotation.Configuration
import org.springframework.scheduling.annotation.AsyncConfigurer
import org.springframework.scheduling.annotation.EnableAsync
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor
import java.util.concurrent.Executor

@Configuration
@EnableAsync
class AsyncConfig : AsyncConfigurer {
    private val logger = LoggerFactory.getLogger(javaClass)

    override fun getAsyncExecutor(): Executor {
        val executor = ThreadPoolTaskExecutor()
        executor.corePoolSize = 5
        executor.maxPoolSize = 10
        executor.queueCapacity = 100
        executor.setThreadNamePrefix("async-event-")
        executor.initialize()
        return executor
    }

    override fun getAsyncUncaughtExceptionHandler(): AsyncUncaughtExceptionHandler {
        return AsyncUncaughtExceptionHandler { ex, method, params ->
            logger.error(
                "비동기 작업 예외 발생: method=${method.name}, params=${params.contentToString()}, error=${ex.message}",
                ex
            )
        }
    }
}
```

---

## 구현 순서 권장사항

1. **Async 설정** - AsyncConfig.kt 먼저 생성
2. **주문 이벤트** - OrderCreatedEvent → CouponEventHandler → OrderService 수정
3. **결제 이벤트** - PaymentCompletedEvent/FailedEvent → OrderEventHandler → PaymentCallbackService 수정
4. **좋아요 이벤트** - ProductLikedEvent → ProductLikeEventHandler → LikeService 수정
5. **데이터 플랫폼** - DataPlatformClient → DataPlatformEventHandler
6. **사용자 행동 로깅** - UserActionEvent → UserActionEventHandler → 각 도메인에서 발행
7. **테스트 작성** - 각 플로우별 통합 테스트

---

## 주의사항

1. **@TransactionalEventListener(phase = AFTER_COMMIT)**: 트랜잭션 커밋 후 이벤트 처리
2. **@Transactional(propagation = REQUIRES_NEW)**: 별도 트랜잭션으로 실행
3. **@Async**: 비동기 실행 (데이터 플랫폼 전송, 사용자 행동 로깅)
4. **에러 처리**: 이벤트 핸들러에서 예외 발생 시 원본 트랜잭션에 영향 없도록 주의
5. **멱등성**: 같은 이벤트가 여러 번 처리될 수 있음을 고려

---

## 테스트 확인 포인트

1. 쿠폰 사용 실패해도 주문은 성공하는가?
2. 결제 완료 후 주문 상태가 COMPLETED로 변경되는가?
3. 좋아요 집계 실패해도 좋아요는 저장되는가?
4. 데이터 플랫폼 전송이 비동기로 실행되는가?
5. 사용자 행동 로그가 잘 적재되는가?
