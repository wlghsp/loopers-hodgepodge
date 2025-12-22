# CodeRabbit 4차 리뷰 수정 가이드

## 🔴 Critical (즉시 수정 필요)

### 1. UserActionEventHandler - 트랜잭션 밖 이벤트 수신 불가

**파일**: `UserActionEventHandler.kt`

**문제:**
- `UserActionTrackingEventHandler`가 `AFTER_COMMIT`에서 `UserActionEvent` 발행
- `UserActionEventHandler`도 `@TransactionalEventListener(AFTER_COMMIT)` 사용
- 트랜잭션 밖에서 발행된 이벤트는 기본적으로 무시됨 (`fallbackExecution=false`)
- **결과: USER_ACTION 로그가 전혀 기록되지 않을 수 있음**

**해결 방법:**

**옵션 1: @EventListener로 변경 (권장)**
```kotlin
@Component
class UserActionEventHandler(
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @EventListener  // @TransactionalEventListener 제거
    fun handleUserAction(event: UserActionEvent) {
        coroutineScope.launch {
            logger.info(...)
        }
    }
}
```

**옵션 2: fallbackExecution = true 추가**
```kotlin
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
fun handleUserAction(event: UserActionEvent) { ... }
```

**권장**: 옵션 1 (`@EventListener`) - 이미 AFTER_COMMIT 이후라 트랜잭션 경계가 불필요

---

## 🟠 Major (중요)

### 2. LikeService - DataIntegrityViolationException 처리 문제

**파일**: `LikeService.kt:26-50`

**문제:**
- `@Transactional` 내에서 `DataIntegrityViolationException`을 catch하면 트랜잭션이 rollback-only 상태가 됨
- 이후 쿼리 실행 또는 커밋 시 `UnexpectedRollbackException` 발생 가능

**현재 코드:**
```kotlin
@Transactional
fun addLike(memberId: String, productId: Long): Like {
    // ...
    try {
        val product = productRepository.findByIdOrThrow(productId)
        val like = Like.of(member, product)
        val savedLike = likeRepository.save(like)
        publishProductLikedEvent(savedLike, member, productId)
        return savedLike
    } catch (e: DataIntegrityViolationException) {
        // ❌ 이 catch 블록이 트랜잭션을 rollback-only로 만듦
        return likeRepository.findByMemberIdAndProductId(member.id, productId)
            ?: throw CoreException(...)
    }
}
```

**해결 방법: REQUIRES_NEW로 격리**

```kotlin
@Transactional
fun addLike(memberId: String, productId: Long): Like {
    val member = memberRepository.findByMemberIdOrThrow(memberId)
    val existingLike = likeRepository.findByMemberIdAndProductId(member.id, productId)
    if (existingLike != null) {
        return existingLike
    }

    return try {
        createLikeInNewTx(member, productId)  // REQUIRES_NEW로 격리
    } catch (e: DataIntegrityViolationException) {
        likeRepository.findByMemberIdAndProductId(member.id, productId)
            ?: throw CoreException(ErrorType.INTERNAL_ERROR, "동시 요청 처리 중 일시적 오류 발생")
    }
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
private fun createLikeInNewTx(member: Member, productId: Long): Like {
    val product = productRepository.findByIdOrThrow(productId)
    val like = Like.of(member, product)
    val savedLike = likeRepository.save(like)
    publishProductLikedEvent(savedLike, member, productId)
    return savedLike
}
```

**핵심:**
- 중복 insert 시도 구간만 `REQUIRES_NEW`로 격리
- 메인 트랜잭션은 rollback-only 상태가 되지 않음
- 동시 요청 시나리오 테스트 추가 권장

---

### 3. LikeService - cancelLike() 삭제 성공 여부 확인

**파일**: `LikeService.kt:70-89`

**문제:**
- `deleteByMemberIdAndProductId()`가 `Unit` 반환
- 실제 삭제 건수를 알 수 없어 경합 상황에서 잘못된 이벤트 발행 가능

**현재 코드:**
```kotlin
@Transactional
fun cancelLike(memberId: String, productId: Long) {
    val member = memberRepository.findByMemberIdOrThrow(memberId)
    val like = likeRepository.findByMemberIdAndProductId(member.id, productId)
        ?: return

    likeRepository.deleteByMemberIdAndProductId(member.id, productId)  // ❌ Unit 반환
    eventPublisher.publishEvent(...)  // 실제 삭제 여부와 관계없이 발행
}
```

**해결 방법:**

**Step 1: LikeRepository에 삭제 건수 반환 메서드 추가**
```kotlin
interface LikeRepository {
    fun deleteByMemberIdAndProductId(memberId: Long, productId: Long): Int  // 삭제된 건수 반환
}
```

**Step 2: LikeService에서 삭제 건수 확인**
```kotlin
@Transactional
fun cancelLike(memberId: String, productId: Long) {
    val member = memberRepository.findByMemberIdOrThrow(memberId)
    val like = likeRepository.findByMemberIdAndProductId(member.id, productId)
        ?: return

    val deletedCount = likeRepository.deleteByMemberIdAndProductId(member.id, productId)
    if (deletedCount > 0) {
        eventPublisher.publishEvent(
            ProductUnlikedEvent(
                productId = productId,
                memberId = member.memberId.value,
                unlikedAt = Instant.now()
            )
        )
    }
}
```

---

### 4. PaymentRecoveryTransactionService - 작업 순서 및 멱등성

**파일**: `PaymentRecoveryTransactionService.kt`

**문제:**
1. **작업 순서 불일치**
   - `handlePaymentSuccess`: 주문 완료 → 결제 상태 업데이트
   - `handlePaymentFailure`: 결제 실패 → 주문 실패
   - 순서가 다름

2. **부분 실패 시 불일치**
   - 주문 완료 성공 후 결제 상태 업데이트 실패 → 불일치 상태

3. **멱등성 부족**
   - 재시도 시 이미 처리된 경우 예외 발생

**현재 코드:**
```kotlin
@Transactional(propagation = Propagation.REQUIRES_NEW)
fun handlePaymentSuccess(orderId: Long, paymentId: Long) {
    val payment = paymentRepository.findByIdOrThrow(paymentId)
    
    orderService.completeOrderWithPayment(orderId)  // 주문 먼저
    payment.markAsSuccess()  // 결제 나중
    paymentRepository.save(payment)
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
fun handlePaymentFailure(orderId: Long, paymentId: Long, reason: String?) {
    val payment = paymentRepository.findByIdOrThrow(paymentId)
    
    payment.markAsFailed(reason ?: "PG에서 결제 실패")  // 결제 먼저
    paymentRepository.save(payment)
    orderService.failOrder(orderId)  // 주문 나중
}
```

**해결 방법:**

```kotlin
@Transactional(propagation = Propagation.REQUIRES_NEW)
fun handlePaymentSuccess(orderId: Long, paymentId: Long) {
    val payment = paymentRepository.findByIdOrThrow(paymentId)
    
    // 상태 확인 후 조건부 처리 (멱등성 보장)
    if (payment.status != PaymentStatus.PENDING) {
        logger.info("결제가 이미 처리됨: paymentId=$paymentId, status=${payment.status}")
        return
    }
    
    // 결제 상태 먼저 업데이트 (일관성)
    payment.markAsSuccess()
    paymentRepository.save(payment)
    
    // 주문 완료 처리
    orderService.completeOrderWithPayment(orderId)
    
    logger.info("결제 복구 완료: orderId=$orderId")
}

@Transactional(propagation = Propagation.REQUIRES_NEW)
fun handlePaymentFailure(orderId: Long, paymentId: Long, reason: String?) {
    val payment = paymentRepository.findByIdOrThrow(paymentId)
    
    // 상태 확인 후 조건부 처리 (멱등성 보장)
    if (payment.status != PaymentStatus.PENDING) {
        logger.info("결제가 이미 처리됨: paymentId=$paymentId, status=${payment.status}")
        return
    }
    
    // 주문 실패 먼저 처리 (일관성 - handlePaymentSuccess와 동일한 순서)
    orderService.failOrder(orderId)
    
    // 결제 상태 업데이트
    payment.markAsFailed(reason ?: "PG에서 결제 실패")
    paymentRepository.save(payment)
    
    logger.info("결제 실패 처리 완료: orderId={}, reason={}", orderId, reason ?: "PG에서 결제 실패")
}
```

**핵심 포인트:**
1. **멱등성 보장**: 상태 확인 후 이미 처리된 경우 early return
2. **일관된 순서**: 두 메서드 모두 주문 처리 → 결제 상태 업데이트 순서로 통일
3. **부분 실패 방지**: 결제 상태 업데이트 실패 시 주문 처리를 시도하지 않음

---

### 5. UserActionEventHandler - metadata 로깅 보안

**파일**: `UserActionEventHandler.kt`

**문제:**
- metadata를 그대로 로깅하면 PII/토큰 유출 및 로그 폭증 위험

**현재 코드:**
```kotlin
logger.info(
    "USER_ACTION: userId={}, action={}, entity={}:{}, metadata={}, at={}",
    event.userId,
    event.actionType,
    event.targetEntityType,
    event.targetEntityId ?: "N/A",
    event.metadata,  // ❌ 그대로 로깅
    event.occurredAt
)
```

**해결 방법:**

```kotlin
@Component
class UserActionEventHandler(
    @Qualifier("eventCoroutineScope")
    private val coroutineScope: CoroutineScope
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    
    private val allowedMetadataKeys = setOf("likeId", "orderAmount", "couponId", "brandId", "sortType", "page")

    private fun sanitizeMetadata(metadata: Map<String, String>): Map<String, String> =
        metadata
            .filterKeys { it in allowedMetadataKeys }
            .mapValues { (_, v) ->
                if (v.length <= 200) v else v.take(200) + "…"
            }

    @EventListener
    fun handleUserAction(event: UserActionEvent) {
        coroutineScope.launch {
            logger.info(
                "USER_ACTION: userId={}, action={}, entity={}:{}, metadata={}, at={}",
                event.userId,
                event.actionType,
                event.targetEntityType,
                event.targetEntityId ?: "N/A",
                sanitizeMetadata(event.metadata),  // ✅ sanitize 적용
                event.occurredAt
            )
        }
    }
}
```

**핵심:**
- 허용된 키만 필터링 (allowlist)
- 값 길이 제한 (200자)
- PII/토큰 유출 방지

---

## 🟡 Minor (선택 사항)

### 6. UserActionTrackingEventHandler - couponId 빈 문자열 처리

**파일**: `UserActionTrackingEventHandler.kt:87-101`

**문제:**
- `couponId`가 null일 때 빈 문자열(`""`) 사용
- 빈 문자열이 유효값으로 저장될 수 있음

**현재 코드:**
```kotlin
metadata = mapOf(
    "orderAmount" to event.orderAmount.toString(),
    "couponId" to (event.couponId?.toString() ?: "")  // ❌ 빈 문자열
)
```

**해결 방법:**

```kotlin
metadata = mapOf(
    "orderAmount" to event.orderAmount.toString()
).let { base ->
    event.couponId?.let { base + ("couponId" to it.toString()) } ?: base
}
```

---

### 7. UserActionEventHandler - MDC 컨텍스트 손실

**파일**: `UserActionEventHandler.kt`

**문제:**
- 코루틴 스레드 전환 시 MDC(traceId, spanId 등) 손실
- 분산 추적 및 요청 correlation이 끊어짐

**해결 방법:**

**Step 1: 의존성 추가 (build.gradle.kts)**
```kotlin
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-slf4j:1.7.3")
}
```

**Step 2: CoroutineConfig 수정**
```kotlin
@Configuration
class CoroutineConfig {
    @Bean("eventCoroutineScope")
    fun eventCoroutineScope(): CoroutineScope {
        return CoroutineScope(
            Dispatchers.IO.limitedParallelism(50) +
            SupervisorJob() +
            MDCContext() +  // ✅ MDC 컨텍스트 전파
            CoroutineExceptionHandler { _, e ->
                logger.error("이벤트 처리 중 예외 발생", e)
            }
        )
    }
}
```

---

### 8. 테스트 개선

**파일**: `OrderServiceTest.kt`

#### 8-1. findAllByIdIn 매칭 순서 독립적으로 변경

**현재:**
```kotlin
every { productRepository.findAllByIdIn(listOf(1L, 2L)) } returns listOf(product1, product2)
```

**개선:**
```kotlin
every {
    productRepository.findAllByIdIn(match { it.size == 2 && it.containsAll(listOf(1L, 2L)) })
} returns listOf(product1, product2)
```

#### 8-2. createdAt 검증 강화

**현재:**
```kotlin
assertThat(eventSlot.captured.createdAt).isNotNull()
```

**개선:**
```kotlin
val now = Instant.now()
assertThat(eventSlot.captured.createdAt).isNotNull()
assertThat(eventSlot.captured.createdAt)
    .isBetween(now.minusSeconds(1), now.plusSeconds(1))
```

#### 8-3. 예외 케이스에서 이벤트 미발행 검증 추가

**추가:**
```kotlin
verify(exactly = 0) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
verify(exactly = 0) { member.usePoint(any()) }
```

#### 8-4. 이벤트 검증 로직 헬퍼로 추출

```kotlin
private fun verifyOrderCreatedEvent(
    eventSlot: CapturingSlot<OrderCreatedEvent>,
    expectedOrderId: Long,
    expectedMemberId: String,
    expectedOrderAmount: Long,
    expectedCouponId: Long?
) {
    verify(exactly = 1) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
    assertThat(eventSlot.captured.orderId).isEqualTo(expectedOrderId)
    assertThat(eventSlot.captured.memberId).isEqualTo(expectedMemberId)
    assertThat(eventSlot.captured.orderAmount).isEqualTo(expectedOrderAmount)
    assertThat(eventSlot.captured.couponId).isEqualTo(expectedCouponId)
    
    val now = Instant.now()
    assertThat(eventSlot.captured.createdAt).isNotNull()
    assertThat(eventSlot.captured.createdAt)
        .isBetween(now.minusSeconds(1), now.plusSeconds(1))
}
```

---

## 📋 수정 우선순위

### 즉시 수정 (Critical)
1. ✅ UserActionEventHandler `@EventListener` 변경

### 중요 (Major)
2. ⚠️ LikeService `REQUIRES_NEW`로 격리
3. ⚠️ PaymentRecoveryTransactionService 멱등성 보장
4. ⚠️ UserActionEventHandler metadata sanitize
5. ⚠️ LikeService `cancelLike()` 삭제 건수 확인

### 선택 사항 (Minor)
6. UserActionTrackingEventHandler couponId 처리
7. MDC 컨텍스트 전파
8. 테스트 개선

---

## 🤔 논의 필요

### LikeService cancelLike() 삭제 건수 확인
- 현재: `deleteByMemberIdAndProductId()`가 `Unit` 반환
- 제안: 삭제 건수 반환하도록 변경
- **결정**: Repository 인터페이스 변경 필요하므로 팀과 논의 후 결정

### PaymentRecoveryTransactionService 작업 순서
- 현재: Success는 주문→결제, Failure는 결제→주문
- 제안: 둘 다 주문→결제 순서로 통일
- **결정**: 비즈니스 요구사항 확인 필요

---

## 📝 참고사항

### TransactionalEventListener fallbackExecution
- 기본값: `false` (트랜잭션 밖에서 발행된 이벤트 무시)
- `true`로 설정하면 트랜잭션 없이도 실행됨
- `@EventListener`는 항상 실행됨 (트랜잭션과 무관)

### REQUIRES_NEW와 rollback-only
- `REQUIRES_NEW`로 새 트랜잭션을 시작하면 메인 트랜잭션과 분리됨
- 새 트랜잭션에서 예외가 발생해도 메인 트랜잭션에 영향 없음
- 중복 insert 시도 구간만 격리하여 메인 트랜잭션 보호

