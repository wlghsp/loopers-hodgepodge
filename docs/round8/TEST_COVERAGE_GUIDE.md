# 테스트 커버리지 개선 가이드

## 📊 현재 상태 요약 (2025-12-15 기준)

### 전체 커버리지
- **Domain Entity**: 85% ✅ (우수)
- **Domain Service**: 40% ⚠️ (개선 필요)
- **Application Layer**: 85% ✅ (우수)
- **Event Handler**: 0% ❌ (부재)
- **Repository**: 0% ❌ (부재)
- **동시성**: 80% ✅ (우수)

### 기존 테스트 현황 (✅ = 존재, ❌ = 부재)

**Service 계층:**
- ✅ OrderService (OrderServiceTest.kt)
- ✅ PaymentCallbackService (PaymentCallbackServiceTest.kt)
- ✅ PaymentRecoveryTransactionService (PaymentRecoveryTransactionServiceTest.kt)
- ❌ MemberService
- ❌ CouponService
- ❌ ProductService
- ❌ LikeService
- ❌ BrandService
- ❌ PaymentService
- ❌ PaymentRecoveryService

**Event Handler:**
- ❌ ProductLikeEventHandler (Round 7/8에서 중요!)
- ❌ UserActionTrackingEventHandler

**Facade Integration:**
- ✅ LikeFacadeIntegrationTest (비동기 대기 로직 포함)
- ✅ OrderFacadeIntegrationTest
- ✅ ConcurrencyIntegrationTest (동시성 테스트)

### 주요 문제점
1. **Service 계층** 테스트 부족: 12개 Service 중 3개만 테스트 존재 (25%)
2. **Event Handler** 테스트 전무: Round 7/8 핵심 기능인데 테스트 없음
3. **Repository** 직접 테스트 없음 (Facade 테스트로만 간접 검증)
4. **Round 8 Kafka 관련** 테스트 없음 (Outbox, DLQ, Consumer 등)

---

## 🎯 테스트 추가 우선순위

### 🔴 최우선 (Critical) - Round 7/8 관련 테스트

#### 0. ProductLikeEventHandler 통합 테스트 (Round 7 필수!)

**중요도**: ⭐⭐⭐⭐⭐ (Round 7 핵심 기능)
**예상 작업 시간**: 30분

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/like/event/ProductLikeEventHandlerIntegrationTest.kt`

**Round 7 BEFORE_COMMIT 전환 후 테스트 방법:**

```kotlin
package com.loopers.domain.like.event

import com.loopers.domain.member.Member
import com.loopers.domain.product.Product
import com.loopers.domain.product.Money
import com.loopers.domain.product.Stock
import com.loopers.infrastructure.jpa.member.MemberJpaRepository
import com.loopers.infrastructure.jpa.product.ProductJpaRepository
import com.loopers.supports.test.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.ApplicationEventPublisher
import java.time.Instant
import java.time.LocalDate

@SpringBootTest
class ProductLikeEventHandlerIntegrationTest @Autowired constructor(
    private val eventPublisher: ApplicationEventPublisher,
    private val productJpaRepository: ProductJpaRepository,
    private val memberJpaRepository: MemberJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("ProductLikedEvent 발행 시 likesCount 증가 (BEFORE_COMMIT - 동기 처리)")
    @Test
    fun incrementLikesCountWhenProductLiked() {
        // given
        val product = productJpaRepository.save(
            Product(
                name = "테스트 상품",
                description = "설명",
                price = Money.of(10000L),
                stock = Stock.of(100),
                brandId = 1L
            )
        )
        val initialCount = product.likesCount

        // when: 이벤트 발행 (BEFORE_COMMIT이므로 동기 처리)
        eventPublisher.publishEvent(
            ProductLikedEvent(
                likeId = 1L,
                memberId = "member1",
                productId = product.id!!,
                likedAt = Instant.now()
            )
        )

        // then: BEFORE_COMMIT이므로 비동기 대기 불필요! 바로 확인 가능
        val updatedProduct = productJpaRepository.findById(product.id!!).get()
        assertThat(updatedProduct.likesCount).isEqualTo(initialCount + 1)
    }

    @DisplayName("ProductUnlikedEvent 발행 시 likesCount 감소 (BEFORE_COMMIT - 동기 처리)")
    @Test
    fun decrementLikesCountWhenProductUnliked() {
        // given: 좋아요 1개가 있는 상품
        val product = productJpaRepository.save(
            Product(
                name = "테스트 상품",
                description = "설명",
                price = Money.of(10000L),
                stock = Stock.of(100),
                brandId = 1L
            ).apply {
                increaseLikesCount()  // 초기값 1
            }
        )
        productJpaRepository.save(product)
        val initialCount = product.likesCount

        // when: 좋아요 취소 이벤트 발행
        eventPublisher.publishEvent(
            ProductUnlikedEvent(
                productId = product.id!!,
                memberId = "member1",
                unlikedAt = Instant.now()
            )
        )

        // then: BEFORE_COMMIT이므로 바로 확인 가능
        val updatedProduct = productJpaRepository.findById(product.id!!).get()
        assertThat(updatedProduct.likesCount).isEqualTo(initialCount - 1)
    }

    @DisplayName("이벤트 핸들러 실패 시 전체 트랜잭션 롤백 확인")
    @Test
    fun rollbackWhenEventHandlerFails() {
        // 이 테스트는 Mock을 사용하여 예외 발생 시켜야 정확한 테스트 가능
        // 여기서는 패턴만 제시
    }
}
```

**⚠️ 중요: Round 7 BEFORE_COMMIT 전환 후 변경 사항**
- ❌ **AS-IS (AFTER_COMMIT)**: `Thread.sleep()` + retry 로직으로 비동기 대기
- ✅ **TO-BE (BEFORE_COMMIT)**: 동기 처리이므로 바로 확인 가능!

---

#### 1. ~~PaymentRecoveryTransactionService 단위 테스트~~ (✅ 이미 존재)

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt`

**테스트해야 할 내용**:
```kotlin
class PaymentRecoveryTransactionServiceTest {

    private lateinit var service: PaymentRecoveryTransactionService
    private lateinit var paymentRepository: PaymentRepository
    private lateinit var orderService: OrderService

    @BeforeEach
    fun setUp() {
        paymentRepository = mockk()
        orderService = mockk()
        service = PaymentRecoveryTransactionService(
            orderService,
            paymentRepository
        )
    }

    @DisplayName("결제 성공 시 주문 완료 및 재고 차감")
    @Test
    fun handlePaymentSuccess() {
        // given
        val orderId = 1L
        val paymentId = 100L

        val payment = mockk<Payment>(relaxed = true) {
            every { status } returns PaymentStatus.PENDING
            every { markAsSuccess() } just Runs
        }

        every { paymentRepository.findByIdOrThrow(paymentId) } returns payment
        every { paymentRepository.save(payment) } returns payment
        every { orderService.completeOrderWithPayment(orderId) } just Runs

        // when
        service.handlePaymentSuccess(orderId, paymentId)

        // then
        verify(exactly = 1) { payment.markAsSuccess() }
        verify(exactly = 1) { paymentRepository.save(payment) }
        verify(exactly = 1) { orderService.completeOrderWithPayment(orderId) }
    }

    @DisplayName("결제 실패 시 주문 취소 및 상태 업데이트")
    @Test
    fun handlePaymentFailure() {
        // given
        val orderId = 1L
        val paymentId = 100L
        val failureReason = "카드 한도 초과"

        val payment = mockk<Payment>(relaxed = true) {
            every { status } returns PaymentStatus.PENDING
            every { markAsFailed(any()) } just Runs
        }

        every { paymentRepository.findByIdOrThrow(paymentId) } returns payment
        every { paymentRepository.save(payment) } returns payment
        every { orderService.failOrder(orderId) } just Runs

        // when
        service.handlePaymentFailure(orderId, paymentId, failureReason)

        // then
        verify(exactly = 1) { orderService.failOrder(orderId) }
        verify(exactly = 1) { payment.markAsFailed(failureReason) }
        verify(exactly = 1) { paymentRepository.save(payment) }
    }

    @DisplayName("멱등성 보장 - 이미 SUCCESS 처리된 결제는 재처리하지 않음")
    @Test
    fun ignoresDuplicatePaymentSuccess() {
        // given
        val orderId = 1L
        val paymentId = 100L

        val payment = mockk<Payment>(relaxed = true) {
            every { status } returns PaymentStatus.SUCCESS  // 이미 SUCCESS
        }

        every { paymentRepository.findByIdOrThrow(paymentId) } returns payment

        // when
        service.handlePaymentSuccess(orderId, paymentId)

        // then: 중복 처리 안함
        verify(exactly = 0) { payment.markAsSuccess() }
        verify(exactly = 0) { orderService.completeOrderWithPayment(any()) }
    }

    @DisplayName("멱등성 보장 - 이미 FAILED 처리된 결제는 재처리하지 않음")
    @Test
    fun ignoresDuplicatePaymentFailure() {
        // given
        val orderId = 1L
        val paymentId = 100L

        val payment = mockk<Payment>(relaxed = true) {
            every { status } returns PaymentStatus.FAILED  // 이미 FAILED
        }

        every { paymentRepository.findByIdOrThrow(paymentId) } returns payment

        // when
        service.handlePaymentFailure(orderId, paymentId, "실패 사유")

        // then: 중복 처리 안함
        verify(exactly = 0) { payment.markAsFailed(any()) }
        verify(exactly = 0) { orderService.failOrder(any()) }
    }

    @DisplayName("존재하지 않는 paymentId는 예외 발생")
    @Test
    fun throwsExceptionWhenPaymentNotFound() {
        // given
        every { paymentRepository.findByIdOrThrow(999L) } throws CoreException(
            ErrorType.PAYMENT_NOT_FOUND,
            "결제 정보를 찾을 수 없습니다"
        )

        // when & then
        val exception = assertThrows<CoreException> {
            service.handlePaymentSuccess(1L, 999L)
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.PAYMENT_NOT_FOUND)
    }
}
```

**중요도**: ⭐⭐⭐⭐⭐
**이유**: 결제 복구는 핵심 비즈니스 로직이며, 최근 개선되었으므로 테스트 필수

---

#### 2. CouponService 단위 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/coupon/CouponServiceTest.kt`

**테스트해야 할 내용**:
```kotlin
class CouponServiceTest {

    private lateinit var service: CouponService
    private lateinit var couponRepository: CouponRepository
    private lateinit var memberCouponRepository: MemberCouponRepository

    @BeforeEach
    fun setUp() {
        couponRepository = mockk()
        memberCouponRepository = mockk()
        service = CouponService(
            couponRepository,
            memberCouponRepository
        )
    }

    @DisplayName("쿠폰 할인 적용 - 고정액 할인")
    @Test
    fun applyFixedDiscountCoupon() {
        // given
        val memberCouponId = 1L
        val orderAmount = Money.of(20000L)

        val coupon = mockk<Coupon>(relaxed = true) {
            every { discountType } returns DiscountType.FIXED
            every { discountAmount } returns 5000L
        }
        val memberCoupon = mockk<MemberCoupon>(relaxed = true) {
            every { isUsed } returns false
            every { coupon } returns coupon
            every { use() } just Runs
        }

        every { memberCouponRepository.findByIdOrThrow(memberCouponId) } returns memberCoupon

        // when
        val discountAmount = service.applyAndUseCouponForOrder(memberCouponId, orderAmount, any(), any())

        // then
        assertThat(discountAmount.amount).isEqualTo(5000L)
        verify(exactly = 1) { memberCoupon.use() }
    }

    @DisplayName("쿠폰 할인 적용 - 비율 할인")
    @Test
    fun applyRateDiscountCoupon() {
        // given
        val memberCouponId = 1L
        val orderAmount = Money.of(20000L)

        val coupon = mockk<Coupon>(relaxed = true) {
            every { discountType } returns DiscountType.RATE
            every { discountRate } returns 10 // 10%
        }
        val memberCoupon = mockk<MemberCoupon>(relaxed = true) {
            every { isUsed } returns false
            every { coupon } returns coupon
        }

        every { memberCouponRepository.findByIdOrThrow(memberCouponId) } returns memberCoupon

        // when
        val discountAmount = service.applyAndUseCouponForOrder(memberCouponId, orderAmount, any(), any())

        // then
        assertThat(discountAmount.amount).isEqualTo(2000L) // 20000 * 0.1
    }

    @DisplayName("이미 사용된 쿠폰은 재사용 불가")
    @Test
    fun throwsExceptionWhenCouponAlreadyUsed() {
        // given
        val memberCouponId = 1L
        val memberCoupon = mockk<MemberCoupon>(relaxed = true) {
            every { isUsed } returns true
        }

        every { memberCouponRepository.findByIdOrThrow(memberCouponId) } returns memberCoupon

        // when & then
        val exception = assertThrows<CoreException> {
            service.applyAndUseCouponForOrder(memberCouponId, Money.of(10000L), any(), any())
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.COUPON_ALREADY_USED)
    }

    @DisplayName("만료된 쿠폰은 사용 불가")
    @Test
    fun throwsExceptionWhenCouponExpired() {
        // given
        val memberCouponId = 1L
        val expiredCoupon = mockk<Coupon>(relaxed = true) {
            every { expiresAt } returns LocalDateTime.now().minusDays(1)
        }
        val memberCoupon = mockk<MemberCoupon>(relaxed = true) {
            every { isUsed } returns false
            every { coupon } returns expiredCoupon
        }

        every { memberCouponRepository.findByIdOrThrow(memberCouponId) } returns memberCoupon

        // when & then
        val exception = assertThrows<CoreException> {
            service.applyAndUseCouponForOrder(memberCouponId, Money.of(10000L), any(), any())
        }

        assertThat(exception.errorType).isEqualTo(ErrorType.COUPON_EXPIRED)
    }
}
```

**중요도**: ⭐⭐⭐⭐⭐
**이유**: 할인 금액 계산 오류는 비즈니스에 직접적인 영향

---

### 🟠 Round 8 Kafka 관련 테스트 (중요!)

Round 8 과제를 진행한다면 다음 테스트들이 필수입니다:

#### R8-1. OutboxEventListener 통합 테스트

**중요도**: ⭐⭐⭐⭐⭐ (Round 8 핵심)
**예상 작업 시간**: 40분

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/infrastructure/event/OutboxEventListenerTest.kt`

```kotlin
@SpringBootTest
class OutboxEventListenerIntegrationTest @Autowired constructor(
    private val eventPublisher: ApplicationEventPublisher,
    private val eventOutboxRepository: EventOutboxJpaRepository,
    private val likeFacade: LikeFacade,
    private val memberJpaRepository: MemberJpaRepository,
    private val productJpaRepository: ProductJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp
) {

    @DisplayName("도메인 이벤트 발행 시 EventOutbox에 저장됨 (BEFORE_COMMIT)")
    @Test
    fun saveEventToOutbox() {
        // given
        val member = memberJpaRepository.save(createMember())
        val product = productJpaRepository.save(createProduct())

        // when: 좋아요 추가 (내부적으로 ProductLikedEvent 발행)
        likeFacade.addLike(member.memberId.value, product.id!!)

        // then: EventOutbox에 저장되었는지 확인
        val outboxEvents = eventOutboxRepository.findAll()
        assertThat(outboxEvents).hasSize(1)
        assertThat(outboxEvents[0].eventType).isEqualTo("PRODUCT_LIKED")
        assertThat(outboxEvents[0].processed).isFalse()
        assertThat(outboxEvents[0].aggregateId).isEqualTo(product.id)
    }

    @DisplayName("중복 이벤트는 무시됨 (멱등성)")
    @Test
    fun ignoresDuplicateEvent() {
        // given: 같은 eventId로 두 번 발행
        val event = ProductLikedEvent(
            eventId = "test-event-123",
            eventType = "PRODUCT_LIKED",
            aggregateId = 1L,
            occurredAt = Instant.now(),
            likeId = 1L,
            memberId = "member1",
            productId = 1L,
            likedAt = Instant.now()
        )

        // when
        eventPublisher.publishEvent(event)
        eventPublisher.publishEvent(event)  // 중복 발행

        // then: Outbox에는 1개만 저장
        val outboxEvents = eventOutboxRepository.findAll()
        assertThat(outboxEvents).hasSize(1)
    }
}
```

#### R8-2. OutboxEventPublisher (Kafka Producer) 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/infrastructure/event/OutboxEventPublisherTest.kt`

```kotlin
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = ["catalog-events"])
class OutboxEventPublisherIntegrationTest {

    @DisplayName("미처리 EventOutbox를 Kafka로 발행")
    @Test
    fun publishPendingEventsToKafka() {
        // Awaitility를 사용하여 비동기 스케줄러 대기
        await()
            .atMost(5, TimeUnit.SECONDS)
            .untilAsserted {
                val outbox = eventOutboxRepository.findAll()[0]
                assertThat(outbox.processed).isTrue()
                assertThat(outbox.kafkaPartition).isNotNull()
                assertThat(outbox.kafkaOffset).isNotNull()
            }
    }
}
```

#### R8-3. MetricsEventConsumer (Kafka Consumer) 테스트

**파일 위치**: `apps/commerce-streamer/src/test/kotlin/com/loopers/infrastructure/event/MetricsEventConsumerTest.kt`

```kotlin
@SpringBootTest
@EmbeddedKafka(partitions = 1, topics = ["catalog-events"])
class MetricsEventConsumerIntegrationTest {

    @DisplayName("Kafka 메시지 수신 시 ProductMetrics 업데이트")
    @Test
    fun updateMetricsOnKafkaMessage() {
        // given: Kafka로 ProductLikedEvent 발행
        val event = ProductLikedEvent(...)
        kafkaTemplate.send("catalog-events", event.aggregateId.toString(), objectMapper.writeValueAsString(event))

        // when: Consumer가 처리할 때까지 대기
        await()
            .atMost(10, TimeUnit.SECONDS)
            .untilAsserted {
                val metrics = productMetricsRepository.findByProductId(productId)
                assertThat(metrics).isNotNull
                assertThat(metrics!!.likesCount).isEqualTo(1)
            }
    }

    @DisplayName("중복 메시지는 한 번만 처리됨 (멱등성)")
    @Test
    fun handlesDuplicateMessagesIdempotently() {
        // event_handled 테이블 확인
    }
}
```

#### R8-4. DLQ (Dead Letter Queue) 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/infrastructure/event/DeadLetterQueueTest.kt`

```kotlin
@DisplayName("최대 재시도 초과 시 DLQ로 이동")
@Test
fun moveToDeadLetterQueueAfterMaxRetry() {
    // Kafka 다운 상태로 시뮬레이션
    // 재시도 3회 후 DLQ 이동 확인
}

@DisplayName("DLQ 이벤트 수동 재처리")
@Test
fun retryDeadLetterQueueEvent() {
    // 관리자가 DLQ 이벤트를 수동으로 재처리하는 시나리오
}
```

---

### 🟡 높음 (High) - 빠른 시일 내 작성

#### 3. MemberService 단위 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/member/MemberServiceTest.kt`

**테스트해야 할 내용**:
```kotlin
@ExtendWith(MockKExtension::class)
class MemberServiceTest {

    @InjectMockKs
    private lateinit var service: MemberService

    @MockK
    private lateinit var memberRepository: MemberRepository

    @Test
    fun `회원 가입 - 정상 케이스`() {
        // Given
        val memberId = "newUser"
        val email = "test@example.com"
        every { memberRepository.existsByMemberId(...) } returns false
        every { memberRepository.save(any()) } returns Member(...)

        // When
        val result = service.joinMember(memberId, email, birthDate, gender)

        // Then
        assertNotNull(result)
        verify(exactly = 1) { memberRepository.save(any()) }
    }

    @Test
    fun `중복된 회원 ID로 가입 시도 시 예외`() {
        // Given
        every { memberRepository.existsByMemberId(...) } returns true

        // When & Then
        assertThrows<CoreException> {
            service.joinMember(memberId, email, birthDate, gender)
        }
    }

    @Test
    fun `포인트 충전 - 정상 케이스`() {
        // Given
        val member = Member(...)
        val initialPoint = member.point.amount
        val chargeAmount = 10000L

        every { memberRepository.findByMemberIdOrThrow(...) } returns member

        // When
        service.chargePoint(memberId, chargeAmount)

        // Then
        assertEquals(initialPoint + chargeAmount, member.point.amount)
    }

    @Test
    fun `포인트 롤백 - 정상 케이스`() {
        // Given
        val member = Member(...).apply {
            chargePoint(10000L)
        }
        val rollbackAmount = 5000L

        every { memberRepository.findByMemberIdOrThrow(...) } returns member

        // When
        service.rollbackPoint(memberId, rollbackAmount)

        // Then
        assertEquals(5000L, member.point.amount)
    }

    @Test
    fun `포인트 부족 시 롤백 실패`() {
        // Given
        val member = Member(...) // point = 0

        every { memberRepository.findByMemberIdOrThrow(...) } returns member

        // When & Then
        assertThrows<CoreException> {
            service.rollbackPoint(memberId, 1000L)
        }
    }
}
```

**중요도**: ⭐⭐⭐⭐
**이유**: 회원 관리 및 포인트 로직은 핵심 기능

---

#### 4. ProductLikeEventHandler 통합 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/like/ProductLikeEventHandlerTest.kt`

**테스트해야 할 내용**:
```kotlin
@SpringBootTest
class ProductLikeEventHandlerIntegrationTest @Autowired constructor(
    private val eventPublisher: ApplicationEventPublisher,
    private val productJpaRepository: ProductJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("ProductLikedEvent 발행 시 좋아요 수 증가")
    @Test
    fun incrementLikesCountWhenProductLiked() {
        // given
        val product = productJpaRepository.save(
            Product("상품", "설명", Money.of(10000L), Stock.of(100), 1L)
        )
        val initialCount = product.likesCount

        // when
        eventPublisher.publishEvent(
            ProductLikedEvent(
                likeId = 1L,
                memberId = "member1",
                productId = product.id!!,
                likedAt = Instant.now()
            )
        )

        // then: 비동기 처리 대기
        var retryCount = 0
        var updatedProduct = productJpaRepository.findById(product.id!!).get()
        while (updatedProduct.likesCount != initialCount + 1 && retryCount < 30) {
            Thread.sleep(100)
            updatedProduct = productJpaRepository.findById(product.id!!).get()
            retryCount++
        }

        assertThat(updatedProduct.likesCount).isEqualTo(initialCount + 1)
    }

    @DisplayName("ProductUnlikedEvent 발행 시 좋아요 수 감소")
    @Test
    fun decrementLikesCountWhenProductUnliked() {
        // given
        val product = productJpaRepository.save(
            Product("상품", "설명", Money.of(10000L), Stock.of(100), 1L)
        ).apply {
            incrementLikesCount() // 초기 좋아요 1개
        }
        productJpaRepository.save(product)

        // when
        eventPublisher.publishEvent(
            ProductUnlikedEvent(
                productId = product.id!!,
                memberId = "member1",
                unlikedAt = Instant.now()
            )
        )

        // then: 비동기 처리 대기
        var retryCount = 0
        var updatedProduct = productJpaRepository.findById(product.id!!).get()
        while (updatedProduct.likesCount != 0 && retryCount < 30) {
            Thread.sleep(100)
            updatedProduct = productJpaRepository.findById(product.id!!).get()
            retryCount++
        }

        assertThat(updatedProduct.likesCount).isEqualTo(0)
    }
}
```

**참고**:
- 비동기 이벤트 처리는 `Thread.sleep(100)`과 retry 로직으로 대기 (기존 테스트 스타일과 동일)
- awaitility 라이브러리는 선택사항 (기존 테스트에서 사용하지 않음)

**중요도**: ⭐⭐⭐⭐
**이유**: 비동기 이벤트 처리 검증 필수

---

#### 5. ProductService 단위 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/product/ProductServiceTest.kt`

**테스트해야 할 내용**:
```kotlin
@ExtendWith(MockKExtension::class)
class ProductServiceTest {

    @InjectMockKs
    private lateinit var service: ProductService

    @MockK
    private lateinit var productRepository: ProductRepository

    @Test
    fun `상품 단건 조회`() {
        // Given
        val productId = 1L
        val product = Product(...)
        every { productRepository.findByIdOrThrow(productId) } returns product

        // When
        val result = service.getProduct(productId)

        // Then
        assertEquals(productId, result.id)
    }

    @Test
    fun `여러 상품 ID로 조회 - 배치 조회`() {
        // Given
        val productIds = listOf(1L, 2L, 3L)
        val products = listOf(
            Product(..., id = 1L),
            Product(..., id = 2L),
            Product(..., id = 3L)
        )
        every { productRepository.findAllByIdIn(productIds) } returns products

        // When
        val result = service.getProductsByIds(productIds)

        // Then
        assertEquals(3, result.size)
        verify(exactly = 1) { productRepository.findAllByIdIn(productIds) }
    }

    @Test
    fun `존재하지 않는 상품 조회 시 예외`() {
        // Given
        every { productRepository.findById(999L) } returns null

        // When & Then
        assertThrows<CoreException> {
            service.getProduct(999L)
        }
    }
}
```

**중요도**: ⭐⭐⭐
**이유**: 상품 조회 로직 검증

---

### 🟠 중간 (Medium) - 시간 날 때 작성

#### 6. LikeService 단위 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/like/LikeServiceTest.kt`

**테스트해야 할 내용**:
```kotlin
@ExtendWith(MockKExtension::class)
class LikeServiceTest {

    @InjectMockKs
    private lateinit var service: LikeService

    @MockK
    private lateinit var likeRepository: LikeRepository

    @MockK
    private lateinit var memberRepository: MemberRepository

    @MockK
    private lateinit var productRepository: ProductRepository

    @MockK
    private lateinit var eventPublisher: ApplicationEventPublisher

    @Test
    fun `좋아요 추가 - 정상 케이스`() {
        // Given
        val member = Member(...)
        val product = Product(...)

        every { memberRepository.findByMemberIdOrThrow(...) } returns member
        every { likeRepository.findByMemberIdAndProductId(...) } returns null
        every { productRepository.findByIdOrThrow(...) } returns product
        every { likeRepository.save(any()) } returns Like.of(member.id, product.id!!)
        every { eventPublisher.publishEvent(any<ProductLikedEvent>()) } just Runs

        // When
        val result = service.addLike("memberId", 1L)

        // Then
        assertNotNull(result)
        verify(exactly = 1) { eventPublisher.publishEvent(any<ProductLikedEvent>()) }
    }

    @Test
    fun `이미 좋아요한 상품은 중복 추가하지 않음 (멱등성)`() {
        // Given
        val member = Member(...)
        val existingLike = Like.of(member.id, 1L)
        val product = Product(...)

        every { memberRepository.findByMemberIdOrThrow(...) } returns member
        every { likeRepository.findByMemberIdAndProductId(...) } returns existingLike
        every { productRepository.findByIdOrThrow(...) } returns product

        // When
        val result = service.addLike("memberId", 1L)

        // Then
        assertNotNull(result)
        verify(exactly = 0) { likeRepository.save(any()) }
        verify(exactly = 0) { eventPublisher.publishEvent(any<ProductLikedEvent>()) }
    }

    @Test
    fun `존재하지 않는 상품에 좋아요 시도 시 예외`() {
        // Given
        val member = Member(...)

        every { memberRepository.findByMemberIdOrThrow(...) } returns member
        every { likeRepository.findByMemberIdAndProductId(...) } returns null
        every { productRepository.existsById(...) } returns false

        // When & Then
        assertThrows<CoreException> {
            service.addLike("memberId", 999L)
        }
    }

    @Test
    fun `DataIntegrityViolationException 발생 시 기존 데이터 반환 (동시성)`() {
        // Given
        val member = Member(...)
        val product = Product(...)
        val existingLike = Like.of(member.id, product.id!!)

        every { memberRepository.findByMemberIdOrThrow(...) } returns member
        every { likeRepository.findByMemberIdAndProductId(...) } returnsMany listOf(null, existingLike)
        every { productRepository.findByIdOrThrow(...) } returns product
        every { likeRepository.save(any()) } throws DataIntegrityViolationException("Duplicate")

        // When
        val result = service.addLike("memberId", 1L)

        // Then
        assertNotNull(result)
        verify(exactly = 0) { eventPublisher.publishEvent(any<ProductLikedEvent>()) }
    }
}
```

**중요도**: ⭐⭐⭐
**이유**: 최근 수정되었으므로 테스트 추가 권장

---

#### 7. UserActionTrackingEventHandler 통합 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/application/event/UserActionTrackingEventHandlerTest.kt`

**테스트해야 할 내용**:
```kotlin
@SpringBootTest
class UserActionTrackingEventHandlerIntegrationTest @Autowired constructor(
    private val eventPublisher: ApplicationEventPublisher,
    private val userActionEventRepository: UserActionEventRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @Test
    fun `ProductViewedEvent를 UserActionEvent로 변환하여 저장`() {
        // Given
        val productId = 1L
        val memberId = "member1"

        // When
        eventPublisher.publishEvent(
            ProductViewedEvent(productId, memberId, Instant.now())
        )

        // Then: 비동기 처리 대기
        await().atMost(3, TimeUnit.SECONDS).untilAsserted {
            val events = userActionEventRepository.findAll()
            assertTrue(events.any {
                it.eventType == "PRODUCT_VIEWED" &&
                it.productId == productId
            })
        }
    }

    @Test
    fun `OrderCreatedEvent를 UserActionEvent로 변환 - couponId null 처리`() {
        // Given
        val event = OrderCreatedEvent(
            orderNumber = "ORDER-001",
            memberId = "member1",
            productIds = listOf(1L, 2L),
            couponId = null, // null 처리 확인
            createdAt = Instant.now()
        )

        // When
        eventPublisher.publishEvent(event)

        // Then
        await().atMost(3, TimeUnit.SECONDS).untilAsserted {
            val events = userActionEventRepository.findAll()
            val actionEvent = events.find { it.eventType == "ORDER_CREATED" }
            assertNotNull(actionEvent)
            assertNull(actionEvent?.couponId)
        }
    }
}
```

**중요도**: ⭐⭐⭐
**이유**: 최근 couponId 처리 개선됨 (fix 커밋)

---

#### 8. BrandService 단위 테스트

**파일 위치**: `apps/commerce-api/src/test/kotlin/com/loopers/domain/brand/BrandServiceTest.kt`

**테스트해야 할 내용**:
```kotlin
@ExtendWith(MockKExtension::class)
class BrandServiceTest {

    @InjectMockKs
    private lateinit var service: BrandService

    @MockK
    private lateinit var brandRepository: BrandRepository

    @Test
    fun `브랜드 생성`() {
        // Given
        val name = "브랜드1"
        val description = "설명"
        every { brandRepository.save(any()) } returns Brand(name, description)

        // When
        val result = service.createBrand(name, description)

        // Then
        assertEquals(name, result.name)
    }

    @Test
    fun `브랜드 조회`() {
        // Given
        val brandId = 1L
        val brand = Brand("브랜드1", "설명")
        every { brandRepository.findByIdOrThrow(brandId) } returns brand

        // When
        val result = service.getBrand(brandId)

        // Then
        assertEquals(brandId, result.id)
    }
}
```

**중요도**: ⭐⭐
**이유**: 단순한 CRUD 로직

---

### 🔵 낮음 (Low) - 여유 있을 때

#### 9. Repository 통합 테스트

**예시**: `ProductRepositoryIntegrationTest.kt`

```kotlin
@SpringBootTest
class ProductRepositoryIntegrationTest @Autowired constructor(
    private val productRepository: ProductRepository,
    private val productJpaRepository: ProductJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @Test
    fun `findAllByIdIn - 여러 ID로 배치 조회`() {
        // Given
        val products = listOf(
            Product("상품1", "설명1", Money.of(10000L), Stock.of(100), 1L),
            Product("상품2", "설명2", Money.of(20000L), Stock.of(50), 1L),
            Product("상품3", "설명3", Money.of(30000L), Stock.of(30), 1L)
        )
        productJpaRepository.saveAll(products)

        val productIds = products.map { it.id!! }

        // When
        val result = productRepository.findAllByIdIn(productIds)

        // Then
        assertEquals(3, result.size)
    }

    @Test
    fun `findAll with sort - LIKES_DESC 정렬`() {
        // Given: 좋아요 수가 다른 상품들
        // When: LIKES_DESC로 정렬 조회
        // Then: 좋아요 많은 순으로 정렬되어 있는지 확인
    }
}
```

**중요도**: ⭐
**이유**: Facade 테스트로 간접 검증되고 있음

---

## 📋 테스트 작성 체크리스트

### 단위 테스트 작성 시
- [ ] MockK 사용하여 의존성 Mocking
- [ ] Given-When-Then 구조 명확히
- [ ] 정상 케이스 + 예외 케이스 모두 작성
- [ ] 경계값 테스트 (0, null, 빈 값 등)
- [ ] 비즈니스 규칙 검증

### 통합 테스트 작성 시
- [ ] `@SpringBootTest` 사용
- [ ] `@Transactional` 또는 DatabaseCleanUp 사용
- [ ] 실제 DB 연동 검증
- [ ] 비동기 처리는 `awaitility` 사용

### 이벤트 테스트 작성 시
- [ ] 이벤트 발행 검증
- [ ] 이벤트 핸들러 동작 검증
- [ ] 비동기 처리 타이밍 고려
- [ ] 이벤트 실패 시 격리성 검증

---

## 🛠 테스트 도구 및 라이브러리

### 이미 사용 중
- **JUnit 5**: 테스트 프레임워크
- **MockK**: Kotlin 전용 Mocking
- **AssertJ**: 풍부한 Assertion
- **SpringBootTest**: 통합 테스트

### 추가 권장
```kotlin
// build.gradle.kts
plugins {
    jacoco // 테스트 커버리지
}

// 비동기 테스트는 Thread.sleep + retry 로직 사용 (기존 스타일과 동일)
```

---

## 📈 테스트 커버리지 측정

### JaCoCo 설정 (권장)

**build.gradle.kts**:
```kotlin
plugins {
    jacoco
}

jacoco {
    toolVersion = "0.8.11"
}

tasks.jacocoTestReport {
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = "0.70".toBigDecimal() // 70% 커버리지 목표
            }
        }
    }
}
```

### 커버리지 확인 명령어
```bash
./gradlew test jacocoTestReport

# 리포트 확인
open build/reports/jacoco/test/html/index.html
```

---

## 🎯 단계별 실행 계획

### ⚡ 긴급 (Round 7 완료 전)
**목표**: Round 7 BEFORE_COMMIT 전환 검증
**소요 시간**: 1시간

1. ✅ ProductLikeEventHandler 통합 테스트 작성 (필수!)
   - BEFORE_COMMIT 동작 확인
   - 트랜잭션 롤백 확인
   - 비동기 대기 로직 제거

2. ✅ LikeFacadeIntegrationTest 수정
   - `Thread.sleep()` + retry 로직 제거
   - 동기 처리 검증으로 변경

**완료 기준**: `./gradlew :apps:commerce-api:test --tests "*ProductLikeEventHandler*"` 통과

---

### 🚀 Round 8 준비 (Kafka 구현 시)
**목표**: Outbox Pattern + Kafka 파이프라인 검증
**소요 시간**: 4-6시간

1. OutboxEventListener 테스트 (1시간)
   - EventOutbox 저장 확인
   - 멱등성 체크

2. OutboxEventPublisher 테스트 (1.5시간)
   - Kafka 발행 확인
   - 재시도 로직 테스트
   - DLQ 이동 테스트

3. MetricsEventConsumer 테스트 (1.5시간)
   - Kafka 메시지 수신 확인
   - ProductMetrics 업데이트 검증
   - 멱등성 체크

4. End-to-End 통합 테스트 (2시간)
   - 좋아요 추가 → Outbox → Kafka → Consumer → Metrics 전체 흐름
   - Kafka 장애 시나리오

**완료 기준**:
- `./gradlew :apps:commerce-api:test --tests "*Outbox*"` 통과
- `./gradlew :apps:commerce-streamer:test --tests "*Consumer*"` 통과

---

### Phase 1: Critical Service 테스트 (1주차)
**목표**: 핵심 비즈니스 로직 검증
**소요 시간**: 6-8시간

1. ~~PaymentRecoveryTransactionService~~ (✅ 이미 존재)
2. CouponService 테스트 작성 (2시간)
3. MemberService 테스트 작성 (2시간)
4. LikeService 테스트 작성 (1.5시간)

---

### Phase 2: High Priority (2주차)
**목표**: 주요 도메인 서비스 커버리지 확보
**소요 시간**: 4-6시간

5. ProductService 테스트 작성 (1.5시간)
6. UserActionTrackingEventHandler 테스트 (2시간)
7. PaymentService 테스트 작성 (2시간)

---

### Phase 3: Medium Priority (3주차)
**목표**: 나머지 서비스 테스트 완성
**소요 시간**: 3-4시간

8. BrandService 테스트 작성 (1시간)
9. PaymentRecoveryService 테스트 작성 (1.5시간)

---

### Phase 4: 마무리 (4주차)
**목표**: 커버리지 측정 및 보고서
**소요 시간**: 2-3시간

10. Repository 통합 테스트 추가 (선택)
11. JaCoCo 설정 및 커버리지 리포팅
12. 테스트 문서화

---

## 💡 테스트 작성 팁

### 1. 테스트 이름 작성
```kotlin
// ❌ 나쁜 예
@Test
fun test1() { }

// ✅ 좋은 예 (camelCase + @DisplayName)
@DisplayName("결제 성공 시 주문 완료 및 재고 차감")
@Test
fun handlePaymentSuccess() { }
```

### 2. Given-When-Then 구조 (소문자 주석)
```kotlin
@DisplayName("좋아요 추가 - 정상 케이스")
@Test
fun addLike() {
    // given: 테스트 준비
    val member = Member(...)

    // when: 테스트 실행
    val result = service.addLike(...)

    // then: 결과 검증
    assertThat(result).isNotNull
}
```

### 3. 테스트 격리
```kotlin
@AfterEach
fun tearDown() {
    databaseCleanUp.truncateAllTables()
}
```

### 4. 비동기 테스트 (기존 스타일)
```kotlin
// 비동기 이벤트 처리 대기
var retryCount = 0
var updatedProduct = productJpaRepository.findById(product.id!!).get()
while (updatedProduct.likesCount != expectedCount && retryCount < 30) {
    Thread.sleep(100) // 100ms 대기
    updatedProduct = productJpaRepository.findById(product.id!!).get()
    retryCount++
}

assertThat(updatedProduct.likesCount).isEqualTo(expectedCount)
```

---

## 📚 참고 자료

- [Kotest 공식 문서](https://kotest.io/)
- [MockK 공식 문서](https://mockk.io/)
- [Awaitility 공식 문서](https://github.com/awaitility/awaitility)
- [Spring Boot Testing Best Practices](https://spring.io/guides/gs/testing-web/)

---

## ✅ 최종 목표

**3개월 내 달성 목표**:
- Service 계층 커버리지: 30% → **80%**
- Event Handler 커버리지: 0% → **70%**
- Repository 커버리지: 0% → **50%**
- **전체 커버리지: 60% → 75%**
