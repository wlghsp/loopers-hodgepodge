@coderabbitai[bot] commented on this pull request.

Actionable comments posted: 16

Caution

Some comments are outside the diff and can’t be posted inline due to platform limitations.

⚠️ Outside diff range comments (1)
apps/commerce-api/src/test/kotlin/com/loopers/application/like/LikeFacadeIntegrationTest.kt (1)
55-57: 사용되지 않는 brand 변수

brand 변수가 생성되지만 Product 생성 시 brandId가 하드코딩된 1L로 설정됩니다. brand.id!!를 사용하거나 불필요한 경우 brand 생성을 제거하세요.

🔎 제안된 수정사항
         val brand = brandJpaRepository.save(Brand("브랜드1", "설명"))
         val product = productJpaRepository.save(
-            Product("상품1", "설명", Money.of(10000L), Stock.of(100), 1L)
+            Product("상품1", "설명", Money.of(10000L), Stock.of(100), brand.id!!)
         )
🧹 Nitpick comments (43)
apps/commerce-api/src/test/kotlin/com/loopers/domain/like/event/ProductLikeEventHandlerRollbackTest.kt (2)
33-34: Kafka 목킹에 대한 명시적 설정을 고려해보세요.

KafkaTemplate이 목킹되어 있지만 명시적인 동작이 설정되지 않았습니다. 현재 구현은 롤백 테스트에는 충분하지만, 향후 Kafka 호출의 성공/실패 시나리오를 검증하려면 Mockito의 given() 또는 verify()를 사용하여 더 명확한 동작을 정의하는 것을 고려해보세요.

🔎 명시적 목 설정 예시
import org.mockito.kotlin.any
import org.mockito.kotlin.given

// 테스트 메서드 내에서:
given(kafkaTemplate.send(any(), any())).willReturn(/* mock result */)
41-63: 테스트 로직은 정확하나 몇 가지 개선을 고려해보세요.

트랜잭션 롤백을 검증하는 테스트 로직은 올바르게 구현되어 있습니다. 다음 사항들을 선택적으로 개선할 수 있습니다:

매직 넘버 (Line 53): 9999999L은 존재하지 않는 상품 ID로 가정하고 있습니다. 향후 이 ID가 실제로 생성될 가능성은 낮지만, 더 명확한 의도 표현을 위해 상수로 추출하거나 주석을 추가하는 것을 고려해보세요.

예외 검증 (Lines 56-58): 현재는 CoreException 타입만 검증하고 있습니다. 예외 메시지나 에러 코드를 함께 검증하면 테스트가 더 정확해집니다.

🔎 개선 예시
-        val invalidProductId = 9999999L // 존재하지 않는 상품
+        val NONEXISTENT_PRODUCT_ID = 9999999L // 존재하지 않는 상품 ID
 
         // when & then
-        assertThrows<CoreException> {
-            likeFacade.addLike(member.memberId.value, invalidProductId)
+        val exception = assertThrows<CoreException> {
+            likeFacade.addLike(member.memberId.value, NONEXISTENT_PRODUCT_ID)
         }
+        // 선택적: 예외 메시지나 에러 코드 검증
+        // assertThat(exception.errorCode).isEqualTo(ExpectedErrorCode.PRODUCT_NOT_FOUND)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt (1)
13-15: MockK과 MockitoExtension 혼용 문제

모든 mock 생성 및 검증에 MockK를 사용하고 있으므로, MockitoExtension 대신 MockKExtension을 사용해야 합니다.

🔎 수정 제안
-import org.junit.jupiter.api.extension.ExtendWith
-import org.mockito.junit.jupiter.MockitoExtension
+import io.mockk.junit5.MockKExtension

-@ExtendWith(MockitoExtension::class)
+@ExtendWith(MockKExtension::class)
apps/commerce-api/src/test/kotlin/com/loopers/interfaces/api/MemberV1ApiE2ETest.kt (1)
31-31: 스케줄링 비활성화가 적절합니다.

E2E 테스트에서 스케줄링을 비활성화하여 백그라운드 작업(예: 아웃박스 프로세서)이 테스트에 간섭하지 않도록 하는 것은 올바른 접근입니다.

💡 선택적 개선: 비활성화 이유를 명시하는 주석 추가
테스트 유지보수를 위해 스케줄링을 비활성화하는 이유를 주석으로 명시하는 것을 고려해보세요:

+// Kafka 아웃박스 프로세서 등 스케줄된 작업이 E2E 테스트에 간섭하지 않도록 비활성화
 @TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
apps/commerce-streamer/src/main/resources/application.yml (1)
37-39: 추가 Consumer 속성 고려를 권장합니다.

현재 설정은 기본적으로 동작하지만, 프로덕션 환경에서의 안정성을 위해 다음 속성들을 추가로 고려해보세요:

max.poll.interval.ms: Consumer가 poll 사이의 최대 시간 (기본 300000ms = 5분)
heartbeat.interval.ms: 하트비트 전송 간격 (일반적으로 session.timeout.ms의 1/3)
fetch.min.bytes: 최소 fetch 크기로 네트워크 효율성 개선
fetch.max.wait.ms: fetch 대기 시간
🔎 권장 추가 설정 예시
       properties:
         "[session.timeout.ms]": 30000
         "[max.poll.records]": 100
+        "[max.poll.interval.ms]": 300000
+        "[heartbeat.interval.ms]": 10000
+        "[fetch.min.bytes]": 1
+        "[fetch.max.wait.ms]": 500
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/AggregateType.kt (1)
14-26: 이벤트 타입 추론에 문자열 프리픽스 매칭 사용을 재고해주세요.

fromEventType 메서드가 문자열 프리픽스 매칭(startsWith)을 사용하여 Aggregate 타입을 추론합니다. 이 접근 방식은:

이벤트 타입 네이밍 컨벤션에 강하게 결합되어 있습니다
이벤트 타입 이름이 변경되면 런타임 오류 발생 위험이 있습니다
컴파일 타임 안전성이 부족합니다
🔎 더 견고한 접근 방식 제안
옵션 1: DomainEvent 인터페이스에 aggregateType 추가

interface DomainEvent {
    val eventId: String
    val eventType: String
    val aggregateType: AggregateType  // 추가
    val aggregateId: String
    val occurredAt: Instant
}
각 이벤트 구현체에서 명시적으로 지정:

data class OrderCreatedEvent(...) : DomainEvent {
    override val aggregateType = AggregateType.ORDER
    // ...
}
옵션 2: 이벤트 타입을 enum으로 관리

enum class EventType(val aggregateType: AggregateType) {
    PRODUCT_LIKED(AggregateType.PRODUCT),
    ORDER_CREATED(AggregateType.ORDER),
    MEMBER_JOINED(AggregateType.MEMBER)
}
apps/commerce-api/src/main/kotlin/com/loopers/domain/event/AggregateType.kt (1)
14-26: 이벤트 타입 추론의 문자열 매칭 방식을 개선해주세요.

commerce-streamer 모듈의 동일 파일에서 제기한 것과 같은 우려사항이 있습니다. 문자열 프리픽스 기반 추론은 타입 안전성이 부족하고 네이밍 컨벤션 변경에 취약합니다.

앞서 제안한 개선 방안(DomainEvent 인터페이스에 aggregateType 추가 또는 EventType enum 사용)을 고려해주세요.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/product/StockDecreasedEvent.kt (1)
12-23: 여러 Instant.now() 호출로 인한 타임스탬프 불일치 가능성

occurredAt과 decreasedAt에서 각각 Instant.now()를 호출하면 미세한 시간 차이가 발생할 수 있습니다. 두 타임스탬프가 동일한 시점을 나타내야 한다면, 단일 타임스탬프를 재사용하는 것이 일관성을 보장합니다.

🔎 제안된 개선안
 data class StockDecreasedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "STOCK_DECREASED",
     override val aggregateId: Long, // productId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),
+    override val occurredAt: Instant = Instant.now(),
 
     val productId: Long,
     val orderId: Long,
     val quantity: Int, // 차감된 수량
     val remainingStock: Int, // 남은 재고
-    val decreasedAt: Instant = Instant.now()
+    val decreasedAt: Instant = occurredAt
 ) : DomainEvent {
 }
또는 생성 시점에 명시적으로 전달:

// 호출 시
val now = Instant.now()
StockDecreasedEvent(
    occurredAt = now,
    decreasedAt = now,
    // ... 기타 필드
)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/event/PaymentFailedEvent.kt (1)
11-21: 여러 Instant.now() 호출로 인한 타임스탬프 불일치 가능성

occurredAt과 failedAt에서 각각 Instant.now()를 호출하면 미세한 시간 차이가 발생할 수 있습니다. 결제 실패 시점을 정확히 기록하려면 단일 타임스탬프를 재사용하는 것이 좋습니다.

🔎 제안된 개선안
 data class PaymentFailedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "PAYMENT_FAILED",
     override val aggregateId: Long, // orderId (partitionKey)
     override val occurredAt: Instant = Instant.now(),
 
     val paymentId: Long,
     val orderId: Long,
     val reason: String,
-    val failedAt: Instant = Instant.now(),
+    val failedAt: Instant = occurredAt,
 ) : DomainEvent
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/product/ProductViewedEvent.kt (1)
11-11: occurredAt과 viewedAt 필드의 중복을 고려하세요.

occurredAt과 viewedAt 모두 Instant.now()를 기본값으로 사용합니다. 의미상 같은 시점을 나타내므로 혼동을 줄이기 위해 하나의 값을 재사용하거나 명확한 차이가 있다면 문서화를 추가하는 것을 권장합니다.

🔎 제안하는 개선안
옵션 1: viewedAt을 occurredAt과 동일하게 사용

 data class ProductViewedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "PRODUCT_VIEWED",
     override val aggregateId: Long, // productId (partitionKey)
     override val occurredAt: Instant = Instant.now(),
 
     val productId: Long,
     val memberId: String?,  // 비로그인 사용자는 null
-    val viewedAt: Instant = Instant.now(),
+    val viewedAt: Instant = occurredAt,
 ) : DomainEvent
옵션 2: 두 필드의 차이점을 명확히 문서화

 data class ProductViewedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "PRODUCT_VIEWED",
     override val aggregateId: Long, // productId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),
+    override val occurredAt: Instant = Instant.now(), // 이벤트가 시스템에 기록된 시각
 
     val productId: Long,
     val memberId: String?,  // 비로그인 사용자는 null
-    val viewedAt: Instant = Instant.now(),
+    val viewedAt: Instant = Instant.now(), // 사용자가 실제로 상품을 조회한 시각
 ) : DomainEvent
Also applies to: 15-15

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/like/ProductUnlikedEvent.kt (1)
10-15: aggregateId와 productId 간의 중복 및 타임스탬프 불일치 가능성

aggregateId와 productId가 동일한 값을 나타내지만 별도 필드로 존재합니다. 생성 시 불일치가 발생할 수 있습니다.
occurredAt과 unlikedAt 모두 Instant.now() 기본값을 가지므로, 생성 시점에 미세한 시간 차이가 발생할 수 있습니다.
🔎 제안된 수정
 data class ProductUnlikedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "PRODUCT_UNLIKED",
-    override val aggregateId: Long,  // productId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),
-
-    val productId: Long,
+    val productId: Long,
     val memberId: String,
-    val unlikedAt: Instant = Instant.now(),
-) : DomainEvent
+    val unlikedAt: Instant = Instant.now(),
+) : DomainEvent {
+    override val aggregateId: Long get() = productId
+    override val occurredAt: Instant get() = unlikedAt
+}
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventListener.kt (1)
53-66: getAggregateType의 확장성 및 "UNKNOWN" 폴백 처리 검토 필요

CouponUsedEvent가 "order" aggregate로 매핑되어 있습니다. 쿠폰 도메인에 따라 "coupon"이 더 적절할 수 있습니다.
else -> "UNKNOWN" 폴백은 새로운 이벤트 타입 추가 시 런타임에 잘못된 aggregate 매핑을 유발할 수 있습니다. 컴파일 타임에 누락을 감지할 수 있도록 sealed class/interface 사용을 고려하세요.
🔎 sealed class 활용 예시
DomainEvent를 sealed interface로 정의하고, aggregate type을 인터페이스 레벨에서 정의하면 when 표현식에서 else 분기 없이 컴파일 타임 완전성 검사가 가능합니다:

sealed interface DomainEvent {
    val eventId: String
    val eventType: String
    val aggregateId: Long
    val occurredAt: Instant
    val aggregateType: String // 각 이벤트에서 직접 정의
}
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/metrics/ProductMetrics.kt (2)
51-54: incrementSales에 음수 quantity 방어 로직 추가 권장

decrementLikes()처럼 incrementSales()에도 유효성 검사를 추가하여 음수 수량이 전달될 경우를 방어하는 것이 좋습니다.

🔎 제안된 수정
 fun incrementSales(quantity: Int = 1) {
+    require(quantity > 0) { "quantity must be positive" }
     salesCount += quantity
     updatedAt = Instant.now()
 }
19-26: 고트래픽 환경에서 Int 오버플로우 가능성 검토

likesCount, viewCount, salesCount가 Int 타입입니다. 대부분의 경우 충분하지만, 매우 인기 있는 상품의 경우 Int.MAX_VALUE(~21억)를 초과할 가능성이 있습니다. 비즈니스 요구사항에 따라 Long 타입 사용을 고려해 보세요.

apps/commerce-api/src/main/kotlin/com/loopers/domain/product/event/StockDecreasedEvent.kt (1)
12-23: ProductUnlikedEvent와 동일한 패턴 일관성 유지 권장

aggregateId와 productId, 그리고 occurredAt과 decreasedAt 간의 중복 문제가 ProductUnlikedEvent와 동일하게 존재합니다. 두 이벤트 간 일관된 패턴을 적용하는 것을 권장합니다.

또한, 빈 클래스 본문 { }는 Kotlin에서 생략 가능합니다.

🔎 제안된 수정
 data class StockDecreasedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "STOCK_DECREASED",
-    override val aggregateId: Long, // productId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),
-
     val productId: Long,
     val orderId: Long,
     val quantity: Int, // 차감된 수량
     val remainingStock: Int, // 남은 재고
     val decreasedAt: Instant = Instant.now()
-) : DomainEvent {
-}
+) : DomainEvent {
+    override val aggregateId: Long get() = productId
+    override val occurredAt: Instant get() = decreasedAt
+}
apps/commerce-api/src/main/kotlin/com/loopers/domain/order/event/OrderCreatedEvent.kt (1)
10-18: aggregateId와 orderId, occurredAt과 createdAt 간의 중복 및 잠재적 불일치 확인 필요

aggregateId와 orderId가 동일한 값을 나타내므로 중복입니다. 의도적인 설계라면 괜찮지만, 혼란을 줄이기 위해 하나로 통일하는 것을 고려해 보세요.
occurredAt과 createdAt 모두 Instant.now()를 기본값으로 사용하여 객체 생성 시점에 약간의 시간 차이가 발생할 수 있습니다. 일관성을 위해 하나의 타임스탬프를 참조하거나 명확히 용도를 구분하는 것이 좋습니다.
🔎 제안: createdAt을 occurredAt으로 참조
     override val occurredAt: Instant = Instant.now(),

     val orderId: Long,
     val memberId: String,
     val orderAmount: Long,
     val couponId: Long?,
     val orderItems: List<OrderItemDto>, // 상품별 수량 정보 (판매량 집계용)
-    val createdAt: Instant = Instant.now(),
+    val createdAt: Instant = occurredAt,
 ) : DomainEvent
apps/commerce-api/src/test/kotlin/com/loopers/domain/order/OrderServiceTest.kt (2)
21-21: 사용되지 않는 import 제거

verifyOrder가 import 되어 있지만 테스트 코드에서 사용되지 않습니다.

🔎 수정 제안
-import io.mockk.verifyOrder
54-114: 쿠폰 사용 주문 테스트에서 이벤트 발행 검증 누락

createOrderWithCouponAndPoint 테스트에서 eventPublisher가 relaxed = true로 설정되어 이벤트 발행이 자동 허용되지만, OrderCreatedEvent 발행 여부를 검증하지 않습니다. 반면 createOrderWithoutCouponAndPublishEvent 테스트(Line 188-231)에서는 이벤트를 명시적으로 캡처하고 검증합니다.

테스트 일관성을 위해 쿠폰 사용 시에도 이벤트 발행을 검증하거나, 두 테스트에서 동일한 검증 전략을 사용하는 것이 좋습니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/payment/PaymentCompletedEvent.kt (1)
11-21: aggregateId/orderId 및 occurredAt/completedAt 중복 패턴

OrderCreatedEvent와 동일한 패턴으로, aggregateId와 orderId가 중복되고 occurredAt과 completedAt이 각각 Instant.now()를 호출합니다.

전체 이벤트에서 일관성을 유지하려면 completedAt = occurredAt으로 참조하거나, 도메인 이벤트 생성 시 타임스탬프를 한 번만 계산하는 팩토리 메서드 도입을 고려해 보세요.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxJpaRepository.kt (2)
10-11: 불필요한 @Component 어노테이션 제거

Spring Data JPA 리포지토리는 JpaRepository를 확장하면 자동으로 빈으로 등록되므로 @Component 어노테이션이 필요하지 않습니다.

🔎 수정 제안
-@Component
 interface EventOutboxJpaRepository : JpaRepository<EventOutbox, Long> {
16-18: @Modifying 쿼리에 clearAutomatically 옵션 고려

삭제 쿼리 실행 후 영속성 컨텍스트와 실제 DB 상태가 불일치할 수 있습니다. 같은 트랜잭션 내에서 삭제된 엔티티에 접근할 가능성이 있다면 clearAutomatically = true를 추가하세요.

🔎 수정 제안
-    @Modifying
+    @Modifying(clearAutomatically = true)
     @Query("DELETE FROM EventOutbox e WHERE e.processed = true AND e.processedAt < :threshold")
     fun deleteByProcessedTrueAndProcessedAtBefore(threshold: Instant) : Int
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/coupon/CouponUsedEvent.kt (2)
15-23: aggregateId와 orderId 중복 및 타임스탬프 드리프트 가능성

aggregateId와 orderId가 동일한 값을 저장하고 있어 중복됩니다. aggregateId를 생성자에서 직접 받지 않고 orderId로부터 파생하도록 변경하는 것을 고려하세요.

또한 occurredAt과 usedAt 모두 Instant.now()를 기본값으로 사용하여 객체 생성 시 미세한 시간 차이가 발생할 수 있습니다.

🔎 제안된 수정사항
 data class CouponUsedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "COUPON_USED",
-    override val aggregateId: Long, // orderId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),
-
     val orderId: Long,
     val memberId: String,
     val couponId: Long,
     val memberCouponId: Long, // 사용된 MemberCoupon ID
     val discountAmount: Long, // 할인 금액
     val usedAt: Instant = Instant.now(),
-) : DomainEvent
+) : DomainEvent {
+    override val aggregateId: Long get() = orderId
+    override val occurredAt: Instant get() = usedAt
+}
1-24: commerce-api 모듈과 이벤트 클래스 중복

이 CouponUsedEvent는 apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/event/CouponUsedEvent.kt와 중복됩니다. 두 모듈 간에 동일한 이벤트 클래스를 유지하면 유지보수 부담이 증가하고 정의가 서로 달라질 수 있습니다.

공통 도메인 이벤트를 공유 모듈로 추출하는 것을 고려하세요.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt (1)
13-19: eventId에 대한 중복 인덱스

eventId가 @Id로 지정되어 이미 primary key로서 unique constraint가 적용됩니다. 별도의 unique 인덱스(idx_event_handled_event_id)는 중복됩니다.

🔎 제안된 수정사항
 @Entity
 @Table(
-    name = "event_handled",
-    indexes = [
-        Index(name = "idx_event_handled_event_id", columnList = "eventId", unique = true)
-    ]
+    name = "event_handled"
 )
 class EventHandled(
     @Id
     val eventId: String,
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/product/ProductBrowsedEvent.kt (1)
11-17: occurredAt과 browsedAt 타임스탬프 중복

두 필드 모두 Instant.now()를 기본값으로 사용하여 미세한 시간 차이가 발생할 수 있습니다. 일관성을 위해 하나의 타임스탬프를 다른 필드에서 파생하거나 동일한 값을 공유하는 것을 고려하세요.

apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/event/CouponUsedEvent.kt (1)
12-24: 이벤트 구조 확인 - commerce-streamer 모듈과 동일한 개선점 적용 가능

DomainEvent 계약을 올바르게 구현하고 있습니다. commerce-streamer 모듈의 동일 이벤트에서 언급된 것과 같이 aggregateId/orderId 중복 및 occurredAt/usedAt 타임스탬프 드리프트 개선을 고려하세요.

이벤트 클래스 중복 해소를 위해 공유 모듈 추출을 권장합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/event/EventOutbox.kt (1)
84-85: 재시도 최대 횟수 상수 정의 고려

retryCount 필드가 있지만 최대 재시도 횟수에 대한 상수가 엔티티나 컴패니언 오브젝트에 정의되어 있지 않습니다. OutboxEventPublisher에서 사용하는 최대값과 일치하는 상수를 정의하면 유지보수성이 향상됩니다.

🔎 제안된 수정사항
class EventOutbox(
    // ... existing fields
) : BaseEntity() {
    companion object {
        const val MAX_RETRY_COUNT = 5
    }
    
    fun isRetryExhausted(): Boolean = retryCount >= MAX_RETRY_COUNT
}
apps/commerce-api/src/test/kotlin/com/loopers/application/like/LikeFacadeIntegrationTest.kt (1)
66-78: Thread.sleep 폴링 대신 Awaitility 사용 권장

awaitility-kotlin 라이브러리가 프로젝트에 이미 포함되어 있습니다. Thread.sleep 기반 폴링보다 Awaitility를 사용하면 테스트가 더 안정적이고 가독성이 좋아집니다.

🔎 제안된 수정사항
+import org.awaitility.kotlin.await
+import org.awaitility.kotlin.untilAsserted
+import java.util.concurrent.TimeUnit

-        // EventOutbox에 저장되었는지 확인 (Kafka 발행은 별도 프로세스)
-        var retryCount = 0
-        var outboxEvents = eventOutboxRepository.findAll()
-        while (outboxEvents.isEmpty() && retryCount < 30) {
-            Thread.sleep(100)
-            outboxEvents = eventOutboxRepository.findAll()
-            retryCount++
-        }
-
-        // EventOutbox에 ProductLikedEvent가 저장되었는지 확인
-        assertThat(outboxEvents).hasSize(1)
-        assertThat(outboxEvents[0].eventType).isEqualTo("PRODUCT_LIKED")
-        assertThat(outboxEvents[0].aggregateId).isEqualTo(product.id)
+        // EventOutbox에 저장되었는지 확인 (Kafka 발행은 별도 프로세스)
+        await.atMost(3, TimeUnit.SECONDS).untilAsserted {
+            val outboxEvents = eventOutboxRepository.findAll()
+            assertThat(outboxEvents).hasSize(1)
+            assertThat(outboxEvents[0].eventType).isEqualTo("PRODUCT_LIKED")
+            assertThat(outboxEvents[0].aggregateId).isEqualTo(product.id)
+        }
동일한 패턴이 addLikeWhenAlreadyExists, cancelLike 테스트에서도 반복됩니다. 모든 폴링 로직에 Awaitility를 적용하세요.

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt (1)
69-76: !! 연산자 사용에 대한 제안

productMap은 loadProductsWithoutLock에서 유효성 검증 후 생성되므로 현재 코드가 안전합니다. 하지만 방어적 코딩을 위해 명시적인 예외 처리를 고려해 볼 수 있습니다.

🔎 방어적 코딩 예시
 private fun calculateTotalAmount(
     orderItems: List<OrderItemCommand>,
     productMap: Map<Long, Product>
 ): Money {
     return orderItems.sumOf { item ->
-        productMap[item.productId]!!.price.amount * item.quantity
+        val product = productMap[item.productId]
+            ?: throw CoreException(ErrorType.PRODUCT_NOT_FOUND, "상품을 찾을 수 없습니다: ${item.productId}")
+        product.price.amount * item.quantity
     }.let { Money(it) }
 }
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/BatchMetricsEventConsumer.kt (2)
40-51: 배치 처리 실패 시 재처리 전략을 명확히 하세요.

현재 예외 발생 시 acknowledgment.acknowledge()가 호출되지 않아 메시지가 재처리됩니다. 그러나 배치 내 일부 메시지만 실패할 경우, 성공한 메시지도 함께 재처리됩니다. 또한, 파싱 단계(parseEvent)에서 예외가 발생하면 전체 배치가 실패합니다.

부분 성공/실패 처리 또는 개별 메시지 단위 에러 핸들링을 고려해 보세요.

🔎 개별 메시지 에러 핸들링 예시
 try {
-    val events = messages.map { record ->
-        parseEvent(record.value())
-    }
+    val events = messages.mapNotNull { record ->
+        try {
+            parseEvent(record.value())
+        } catch (e: Exception) {
+            logger.error("메시지 파싱 실패: ${record.value()}, error=${e.message}", e)
+            null
+        }
+    }
+
+    if (events.isEmpty()) {
+        acknowledgment.acknowledge()
+        return
+    }

     batchMetricsEventFacade.handleBatchEvents(events)
54-70: parseEvent 로직이 MetricsKafkaConsumer와 중복됩니다.

동일한 이벤트 파싱 로직이 MetricsKafkaConsumer.parseEvent에도 존재합니다. 공통 유틸리티 클래스로 추출하거나, Jackson의 polymorphic deserialization(@JsonTypeInfo)을 사용하여 중복을 제거하는 것을 권장합니다.

또한 node["eventType"]이 null일 경우 asText()에서 예외가 발생할 수 있습니다.

🔎 NPE 방지를 위한 수정
 private fun parseEvent(message: String): DomainEvent {
     val node = objectMapper.readTree(message)
-    val eventType = node["eventType"].asText()
+    val eventType = node["eventType"]?.asText()
+        ?: throw IllegalArgumentException("Missing eventType in message: $message")
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1)
72-91: eventType null 체크를 추가하세요.

node["eventType"]이 존재하지 않거나 null인 경우 asText()에서 예외가 발생하거나 "null" 문자열이 반환될 수 있습니다. 명시적인 null 체크를 권장합니다.

🔎 Null 체크 추가
 private fun parseEvent(message: String): DomainEvent {
     val node = objectMapper.readTree(message)
-    val eventType = node["eventType"].asText()
+    val eventType = node["eventType"]?.asText()
+        ?: throw IllegalArgumentException("Missing eventType in message")
apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductUnlikedEvent.kt (1)
7-16: aggregateId와 productId의 중복 및 타임스탬프 일관성을 확인하세요.

aggregateId가 productId와 동일한 값을 갖도록 설계되어 있으나, 호출 시 별도로 전달해야 합니다. 또한 occurredAt과 unlikedAt이 각각 Instant.now()를 호출하여 미세한 시간 차이가 발생할 수 있습니다.

일관성을 위해 aggregateId를 productId에서 파생하거나, 타임스탬프를 통일하는 것을 고려하세요.

🔎 타임스탬프 통일 예시
 data class ProductUnlikedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "PRODUCT_UNLIKED",
     override val aggregateId: Long,  // productId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),
+    override val occurredAt: Instant = Instant.now(),

     val productId: Long,
     val memberId: String,
-    val unlikedAt: Instant = Instant.now(),
+    val unlikedAt: Instant = occurredAt,
 ) : DomainEvent
참고: data class에서는 이 방식이 동작하지 않으므로, 팩토리 함수나 생성 시점에서 동일한 Instant를 전달하는 방식을 권장합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/config/KafkaConsumerConfig.kt (1)
22-33: consumerFactory의 groupId 설정이 @KafkaListener의 groupId와 충돌할 수 있습니다.

consumerFactory에서 GROUP_ID_CONFIG를 설정하지만, MetricsKafkaConsumer는 groupId = "metrics-consumer-group", BatchMetricsKafkaConsumer는 groupId = "metrics-consumer-group-batch"를 사용합니다. @KafkaListener의 groupId가 우선 적용되므로 동작에는 문제가 없지만, 혼란을 피하기 위해 factory에서 groupId를 제거하거나 주석으로 명시하는 것을 고려하세요.

apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikedEvent.kt (1)
7-17: ProductUnlikedEvent와 동일한 타임스탬프 이슈가 있습니다.

occurredAt과 likedAt이 각각 Instant.now()를 호출하여 미세한 시간 차이가 발생할 수 있습니다. ProductUnlikedEvent에서 언급한 것과 같이, 이벤트 생성 시점에 동일한 타임스탬프를 사용하는 것을 권장합니다.

전체적으로 DomainEvent 구현 및 필드 구조는 적절합니다.

apps/commerce-api/src/test/kotlin/com/loopers/infrastructure/event/OutboxEventPublisherTest.kt (1)
158-193: 테스트의 MAX_RETRY 상수 의존성을 명시하세요.

retryCount = 2로 설정하여 3번째 실패 시 DLQ로 이동하는 테스트는 OutboxEventPublisher.MAX_RETRY = 3이라는 가정에 의존합니다. 이 상수 값이 변경되면 테스트는 자동으로 실패합니다. OutboxEventPublisher.MAX_RETRY를 상수로 참조하거나 테스트 내에서 명시적으로 주석으로 상수 값을 문서화하여 의도를 더 명확하게 하세요.

apps/commerce-api/src/test/kotlin/com/loopers/concurrency/ConcurrencyIntegrationTest.kt (3)
52-53: @MockBean 사용에 대한 참고사항

@MockBean은 현재 deprecation 경고가 있으며, Spring Boot 3.4+에서는 @MockitoBean으로 마이그레이션이 권장됩니다. 현재 버전에서는 동작하지만, 향후 업그레이드 시 참고하세요.

91-102: 이벤트 검증 로직 개선 제안

현재 폴링 로직은 100개의 이벤트가 저장될 때까지 대기합니다. 그러나 폴링 조건(outboxEvents.size < 100)이 필터링 전 전체 이벤트 수를 체크하고 있어, 다른 테스트나 이벤트 타입이 섞일 경우 조기 종료될 수 있습니다.

🔎 필터링된 이벤트 수 기준으로 폴링하도록 수정 제안
         // EventOutbox에 100개의 ProductLikedEvent가 저장되었는지 확인
         var retryCount = 0
-        var outboxEvents = eventOutboxRepository.findAll()
-        while (outboxEvents.size < 100 && retryCount < 50) {
+        var likedEvents = eventOutboxRepository.findAll()
+            .filter { it.eventType == "PRODUCT_LIKED" && it.aggregateId == product.id }
+        while (likedEvents.size < 100 && retryCount < 50) {
             Thread.sleep(100)
-            outboxEvents = eventOutboxRepository.findAll()
+            likedEvents = eventOutboxRepository.findAll()
+                .filter { it.eventType == "PRODUCT_LIKED" && it.aggregateId == product.id }
             retryCount++
         }

-        // EventOutbox에 100개의 ProductLikedEvent가 저장되었는지 확인
-        val likedEvents = outboxEvents.filter { it.eventType == "PRODUCT_LIKED" && it.aggregateId == product.id }
         assertThat(likedEvents).hasSize(100)
88-89: awaitTermination 사용 권장

while (!executor.isTerminated) 패턴 대신 executor.awaitTermination()을 사용하는 것이 더 명확하고 관용적입니다.

🔎 개선 제안
         executor.shutdown()
-        while (!executor.isTerminated) Thread.sleep(50)
+        executor.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt (3)
3-3: 사용되지 않는 import 제거

ObjectMapper가 import되었지만 사용되지 않습니다.

🔎 수정 제안
 package com.loopers.infrastructure.event

-import com.fasterxml.jackson.databind.ObjectMapper
 import com.loopers.domain.event.EventOutbox
71-90: 중복 저장 최적화 가능

retryCount >= MAX_RETRY 조건에서 eventOutboxRepository.save(outbox)가 두 번 호출됩니다 (라인 74, 84). 최대 재시도 초과 시 한 번만 저장하도록 최적화할 수 있습니다.

🔎 수정 제안
     private fun handlePublishFailure(outbox: EventOutbox, e: Exception) {
         outbox.retryCount++
         outbox.lastError = e.message?.take(500)
-        eventOutboxRepository.save(outbox)

         if (outbox.retryCount >= MAX_RETRY) {
             logger.error(
                 "Kafka 발행 실패 (최대 재시도 초과): eventId=${outbox.eventId}, retryCount=${outbox.retryCount}", e
             )
             deadLetterQueueService.moveToDeadLetterQueue(outbox, e)

             outbox.processed = true
             outbox.processedAt = Instant.now()
-            eventOutboxRepository.save(outbox)
         } else {
             logger.warn(
                 "Kafka 발행 실패 (재시도 ${outbox.retryCount}회): eventId=${outbox.eventId}", e
             )
         }
+        eventOutboxRepository.save(outbox)
     }
64-65: Kafka 전송에 타임아웃 추가 권장

.get() 호출이 무한정 블로킹될 수 있습니다. Kafka 브로커 장애 시 스케줄러가 오랫동안 블록될 수 있으므로 타임아웃을 설정하는 것이 좋습니다.

🔎 타임아웃 추가 예시
+import java.util.concurrent.TimeUnit
+
         val partitionKey = outbox.aggregateId.toString()
-        val result = kafkaTemplate.send(topic, partitionKey, outbox.payload).get()
+        val result = kafkaTemplate.send(topic, partitionKey, outbox.payload).get(30, TimeUnit.SECONDS)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt (1)
32-56: 예외 처리 및 타임아웃 개선 제안

findById().orElseThrow()에 의미 있는 예외 메시지 추가를 권장합니다.
kafkaTemplate.send().get() 호출에 타임아웃이 없어 무한 대기 가능성이 있습니다.
🔎 개선 제안
+import java.util.concurrent.TimeUnit
+
     @Transactional
     fun retryDeadLetterEvent(dlqId: Long, resolvedBy: String) : Boolean {
-        val dlq = deadLetterQueueRepository.findById(dlqId).orElseThrow()
+        val dlq = deadLetterQueueRepository.findById(dlqId)
+            .orElseThrow { NoSuchElementException("DLQ not found: id=$dlqId") }

         if (dlq.processed) {
             logger.warn("이미 처리된 DLQ: id=$dlqId")
             return false
         }

         return try {
             val topic = getTopicForEventType(dlq.eventType)
-            kafkaTemplate.send(topic, dlq.eventId, dlq.payload).get()
+            kafkaTemplate.send(topic, dlq.eventId, dlq.payload).get(30, TimeUnit.SECONDS)
📜 Review details
Configuration used: Repository UI

Review profile: CHILL

Plan: Pro

💤 Files with no reviewable changes (8)
apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/Coupon.kt
apps/commerce-api/src/main/kotlin/com/loopers/application/order/OrderEventHandler.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/UserActionEventHandler.kt
apps/commerce-api/src/main/kotlin/com/loopers/domain/like/event/ProductLikeEventHandler.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/UserActionTrackingEventHandler.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DataPlatformEventHandler.kt
apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/CouponService.kt
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/DemoKafkaConsumer.kt
🧰 Additional context used 🧠 Learnings (3) 📚 Learning: 2025-12-18T01:01:55.894Z
Learnt from: jikimee64
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 65
File: modules/kafka/src/main/resources/kafka.yml:25-32
Timestamp: 2025-12-18T01:01:55.894Z
Learning: In Spring Boot Kafka configuration YAML, properties inside spring.kafka.producer.properties and spring.kafka.consumer.properties maps must use exact Kafka client property names with dot notation, and must be quoted with bracket notation like "[enable.idempotence]": true and "[enable.auto.commit]": false to prevent YAML from parsing dots as nested keys. Spring Boot's relaxed binding only applies to top-level Spring Kafka properties, not to the properties map.
Applied to files:

apps/commerce-streamer/src/main/resources/application.yml
apps/commerce-api/src/main/kotlin/com/loopers/config/KafkaProducerConfig.kt
apps/commerce-api/src/main/resources/application.yml
apps/commerce-streamer/src/main/kotlin/com/loopers/config/KafkaConsumerConfig.kt
📚 Learning: 2025-12-16T09:44:15.945Z
Learnt from: toongri
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 58
File: apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt:157-183
Timestamp: 2025-12-16T09:44:15.945Z
Learning: In PaymentService.requestPgPayment (apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentService.kt), PG payment requests are idempotent using paymentId as the idempotency key, so Retryable covering the entire method including the pgClient.requestPayment call is safe and will not cause duplicate charges even if retries occur due to ObjectOptimisticLockingFailureException.
Applied to files:

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt
apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt
📚 Learning: 2025-12-07T12:45:45.556Z
Learnt from: toongri
Repo: Loopers-dev-lab/loopers-spring-kotlin-template PR: 52
File: apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt:160-181
Timestamp: 2025-12-07T12:45:45.556Z
Learning: In the Payment.confirmPayment method in com.loopers.domain.payment.Payment, the when-branch order is intentionally designed with business logic checks before timeout: (1) check SUCCESS/FAILED status first, (2) check for null match (business failure), (3) check timeout only as last resort for PENDING transactions. If matched transaction is PENDING and not timed out, no branch matches and payment stays IN_PROGRESS for scheduler retry. This design prioritizes business outcome determination over time-based fallback.
Applied to files:

apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt
🧬 Code graph analysis (2) apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/BatchMetricsEventConsumer.kt (1)
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1)
parseEvent (72-91)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt (1)
apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/Payment.kt (2)
markAsSuccess (61-66)
markAsFailed (68-74)
🪛 detekt (1.23.8) apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/product/StockDecreasedEvent.kt
[warning] 23-24: The class or object StockDecreasedEvent is empty.

(detekt.empty-blocks.EmptyClassBlock)

🔇 Additional comments (71)
.gitignore (1)
41-43: 좋은 추가입니다.

macOS 시스템 파일(.DS_Store)을 무시 대상에 추가하는 것은 표준 관례입니다. 기존 섹션 형식과 일치하며, 적절한 위치에 배치되었습니다.

apps/commerce-api/src/test/kotlin/com/loopers/domain/like/event/ProductLikeEventHandlerRollbackTest.kt (2)
1-31: 테스트 설정이 잘 구성되어 있습니다.

통합 테스트에 필요한 의존성들이 생성자 주입으로 잘 구성되어 있고, 스케줄링을 비활성화하여 테스트 격리를 보장하는 점이 좋습니다.

36-39: LGTM!

각 테스트 후 데이터베이스를 정리하는 로직이 적절하게 구현되어 있습니다.

apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt (2)
32-55: LGTM!

결제 성공 시나리오에 대한 테스트가 올바르게 구현되어 있습니다. markAsSuccess(), save(), completeOrderWithPayment() 호출이 적절히 검증되고 있습니다.

57-81: LGTM!

결제 실패 시나리오 테스트가 적절하게 구현되어 있습니다.

apps/commerce-api/src/test/kotlin/com/loopers/application/product/ProductFacadeIntegrationTest.kt (2)
26-26: 테스트 격리를 위한 스케줄링 비활성화 적용

통합 테스트에서 Spring 스케줄링을 비활성화하여 백그라운드 작업의 간섭을 방지합니다. Kafka 기반 이벤트 처리와 메트릭 수집을 위한 스케줄러가 테스트 실행에 영향을 주지 않도록 하는 적절한 접근입니다.

34-36: MockBean을 사용하여 실제 Kafka와의 상호작용 격리

ProductFacade가 도메인 이벤트를 발행할 때 실제 Kafka 브로커와의 상호작용을 방지하기 위해 KafkaTemplate을 모킹합니다. 테스트에서 Kafka 기능을 직접 검증하지 않으므로 Mockito의 기본 mock 동작만으로 충분합니다.

apps/commerce-api/src/test/kotlin/com/loopers/interfaces/api/MemberV1ApiE2ETest.kt (1)
26-28: LGTM! 임포트가 적절하게 추가되었습니다.

테스트 구성에 필요한 Spring 테스트 라이브러리들이 올바르게 임포트되었습니다.

apps/commerce-streamer/src/main/resources/application.yml (5)
17-17: 애플리케이션 이름 변경이 적절합니다.

commerce-streamer로의 이름 변경이 새로운 Kafka 스트리밍 서비스의 역할과 일치합니다.

23-24: 데이터소스 설정이 적절합니다.

환경 변수를 통한 설정과 로컬 개발을 위한 기본값이 적절하게 구성되어 있습니다.

41-44: 로깅 설정이 적절합니다.

애플리케이션과 Kafka 관련 로깅 레벨이 적절하게 설정되어 있어, 운영 환경에서 중요한 이벤트를 추적하면서도 과도한 로그를 방지할 수 있습니다.

21-22: 제거된 redis.yml, kafka.yml, logging.yml, monitoring.yml 파일들은 실제로 저장소에 존재하지만, commerce-streamer 서비스에서는 Redis와 모니터링 기능을 사용하지 않으므로 이 import들을 제거하는 것이 적절합니다. Kafka와 로깅 설정은 인라인으로 정의되어 있습니다.

26-36: 그룹 ID와 Deserializer 설정이 실제로는 적절하게 구성됨을 확인했습니다.

현재 설정은 다음과 같이 작동합니다:

Consumer 그룹 ID: metrics-consumer-group (일반 리스너)와 metrics-consumer-group-batch (배치 리스너)는 모두 catalog-events, order-events 토픽을 구독하는데, 이는 올바른 설계입니다. 그룹 ID는 서비스/도메인을 식별하는 것이지 토픽을 제한하지 않으므로, 여러 이벤트 타입을 처리하는 것이 정상입니다.

Deserializer: StringDeserializer를 사용하고 ObjectMapper로 수동 파싱하는 방식은 유효합니다. 이벤트 타입 기반 switch/when 로직으로 명시적 타입 매핑을 하고 있어 기능상 문제가 없습니다.

다만, 미래 유지보수를 위해 다음을 검토할 수 있습니다:

JsonDeserializer로 전환하여 타입 매핑을 application.yml에서 선언적으로 관리할 수도 있으나, 현재 구현도 명확하고 작동합니다.
apps/commerce-api/src/test/kotlin/com/loopers/interfaces/api/Point1V1ApiE2ETest.kt (1)
24-29: 테스트 격리 설정이 올바르게 구현되었습니다.

Kafka 통합 테스트를 위한 적절한 격리 패턴을 적용했습니다:

KafkaTemplate을 MockBean으로 설정하여 실제 Kafka 메시지 발행을 방지
스케줄링 비활성화로 백그라운드 작업의 간섭 방지
Also applies to: 36-37

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueRepository.kt (1)
6-7: 리포지토리 구현이 적절합니다.

Spring Data JPA 네이밍 컨벤션을 올바르게 따르고 있으며, Top100 제한으로 배치 처리 시 메모리 문제를 방지합니다. 가장 오래된 미처리 이벤트부터 처리하는 FIFO 순서도 적절합니다.

apps/commerce-api/src/test/kotlin/com/loopers/application/member/MemberFacadeIntegrationTest.kt (1)
21-27: 테스트 격리 설정이 올바르게 적용되었습니다.

Point1V1ApiE2ETest와 동일한 Kafka 테스트 격리 패턴을 적용하여 일관성 있는 테스트 환경을 구성했습니다.

Also applies to: 35-36

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/Order.kt (1)
99-109: 포인트 사용 검증 로직이 올바르게 구현되고 통합되었습니다.

validatePointUsage 메서드는 최종 금액을 초과하는 포인트 사용을 방지하며, OrderService.applyPointDiscount 메서드(81번 줄)에서 포인트 적용 전에 적절히 호출됩니다. 명확한 에러 메시지로 사용자에게 유용한 정보를 제공합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/event/EventHandledRepository.kt (1)
6-8: 구현이 깔끔합니다

이벤트 중복 처리 방지를 위한 리포지토리 구조가 적절합니다. Spring Data JPA의 파생 쿼리 메서드를 잘 활용하고 있습니다.

apps/commerce-streamer/src/test/kotlin/com/loopers/domain/metrics/ProductMetricsServiceTest.kt (1)
23-250: 테스트 커버리지가 훌륭합니다

메트릭 서비스의 핵심 동작들을 포괄적으로 검증하고 있습니다:

증가/감소 연산 및 경계 조건 (0 이하 방지)
이벤트 시간 순서 보장 로직
배치 처리 및 정렬
메트릭 초기화
특히 이벤트 순서 역전 처리 테스트(lines 157-176, 222-250)는 분산 환경에서 중요한 시나리오를 다루고 있어 좋습니다.

apps/commerce-api/src/test/kotlin/com/loopers/CommerceApiContextTest.kt (1)
5-14: 테스트 격리 설정이 적절합니다

Kafka와 스케줄링 태스크를 모킹하여 컨텍스트 테스트를 외부 의존성으로부터 격리시켰습니다. 이는 테스트 안정성을 높이는 표준 패턴입니다.

apps/commerce-api/src/main/resources/application.yml (1)
27-35: Kafka 기본 설정과 토픽 매핑이 적절합니다

acks: all로 모든 replica 확인을 통해 At Least Once 보장
토픽 매핑이 명확하게 정의됨
Graceful shutdown timeout 설정으로 안전한 종료 지원
Also applies to: 41-47

apps/commerce-api/src/main/kotlin/com/loopers/domain/like/LikeService.kt (1)
45-53: DomainEvent 인터페이스 통합이 올바릅니다

좋아요/취소 이벤트에 aggregateId 필드가 추가되어 DomainEvent 계약을 준수합니다. aggregateId = productId로 설정하여 Kafka 파티셔닝 키로 활용할 수 있습니다.

Also applies to: 78-85

apps/commerce-api/src/test/kotlin/com/loopers/application/brand/BrandFacadeIntegrationTest.kt (1)
15-29: 일관된 테스트 격리 패턴 적용

다른 테스트 파일들과 동일한 패턴으로 Kafka와 스케줄링을 격리하여 통합 테스트의 안정성을 확보했습니다.

apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/product/ProductV1Controller.kt (2)
39-47: LGTM! Enum을 String으로 변환하는 로직이 정확합니다.

sort.name을 사용하여 enum을 문자열로 변환하는 것은 Kafka 직렬화 요구사항에 부합하며, 이벤트 스키마의 일관성을 유지합니다.

61-68: LGTM! aggregateId 추가가 적절합니다.

aggregateId를 추가하여 Kafka 파티셔닝 키로 사용할 수 있도록 하였고, DomainEvent 인터페이스 계약을 준수합니다.

apps/commerce-api/src/test/kotlin/com/loopers/application/order/OrderFacadeIntegrationTest.kt (1)
27-29: LGTM! 테스트 격리 전략이 적절합니다.

KafkaTemplate을 MockBean으로 처리하고 스케줄링을 비활성화하여 통합 테스트에서 Kafka 인프라와 스케줄된 작업으로부터 격리시켰습니다. 이는 테스트의 신뢰성과 속도를 향상시킵니다.

Also applies to: 32-32, 41-42

apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/metrics/ProductMetricsRepository.kt (1)
1-8: LGTM! 표준 Spring Data JPA 패턴입니다.

리포지토리 인터페이스가 간결하고 정확하게 구현되었으며, nullable 반환 타입이 적절합니다.

apps/commerce-api/src/main/kotlin/com/loopers/config/KafkaProducerConfig.kt (1)
22-24: LGTM! 신뢰성 있는 프로듀서 설정입니다.

acks=all, 멱등성 활성화, 재시도 설정이 적절하게 구성되어 메시지 손실 및 중복 전송을 방지합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/PaymentCallbackService.kt (2)
48-57: LGTM! aggregateId로 orderId를 사용하는 것이 적절합니다.

결제 완료 이벤트에 aggregateId = payment.orderId를 추가하여 동일 주문의 이벤트들이 같은 Kafka 파티션으로 전송되어 순서가 보장됩니다.

65-73: LGTM! 결제 실패 이벤트도 일관성 있게 구성되었습니다.

결제 실패 이벤트에도 aggregateId가 추가되어 결제 완료 이벤트와 동일한 파티셔닝 전략을 사용합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/DomainEvent.kt (1)
1-32: LGTM! 잘 설계된 도메인 이벤트 인터페이스입니다.

이벤트 표준화를 위한 명확한 계약을 정의했습니다:

eventId: 멱등성 체크용
eventType: 이벤트 타입 식별
aggregateId: Kafka 파티션 키로 사용하여 순서 보장
occurredAt: 이벤트 발생 시각
문서화도 명확하게 작성되었습니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/product/ProductViewedEvent.kt (1)
7-16: DomainEvent 구현이 올바르게 작성되었습니다.

DomainEvent 인터페이스를 구현하고 적절한 기본값을 제공합니다. aggregateId로 productId를 사용하여 동일 상품의 조회 이벤트들이 순서대로 처리됩니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/event/DomainEvent.kt (1)
9-32: 잘 설계된 DomainEvent 인터페이스

Kafka 파이프라인을 위한 도메인 이벤트 계약이 명확하게 정의되어 있습니다. eventId를 통한 멱등성 체크, aggregateId를 통한 파티션 키 활용, occurredAt을 통한 이벤트 순서 추적이 가능합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/event/OrderCreatedEvent.kt (1)
21-25: LGTM!

OrderItemDto가 필요한 필드들로 잘 정의되어 있습니다.

apps/commerce-api/src/test/kotlin/com/loopers/domain/order/OrderServiceTest.kt (1)
102-104: LGTM!

쿠폰 관련 mock 호출 검증이 새로운 3단계 흐름(getMemberCoupon → calculateDiscount → use)에 맞게 잘 작성되었습니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/like/ProductLikedEvent.kt (1)
7-17: LGTM!

다른 도메인 이벤트들과 일관된 구조로 잘 구현되었습니다. aggregateId/productId 및 occurredAt/likedAt 중복은 다른 이벤트들과 동일한 패턴이므로 전체 이벤트 구조 리팩토링 시 함께 고려하면 됩니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/payment/PaymentFailedEvent.kt (1)
11-21: LGTM!

PaymentCompletedEvent와 대칭적으로 잘 구현되었습니다. 결제 실패 사유(reason)가 포함되어 디버깅 및 모니터링에 유용합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/application/metrics/MetricsEventFacade.kt (3)
32-56: LGTM!

이벤트 라우팅 로직이 when 표현식으로 깔끔하게 구현되었습니다. 처리 대상이 아닌 이벤트는 debug 레벨로 로깅하여 불필요한 로그 노이즈를 방지한 점이 좋습니다.

62-70: markAsHandled에서 예외 발생 시 동작 확인 필요

routeAndProcess가 성공한 후 markAsHandled에서 DB 저장 실패 시, 메트릭은 이미 업데이트되었지만 이벤트가 처리됨으로 표시되지 않습니다. 재시도 시 메트릭이 중복 반영될 수 있습니다.

handleEvent 메서드가 @Transactional로 감싸져 있고 메트릭 업데이트도 같은 트랜잭션 내에서 롤백된다면 문제없지만, 메트릭 서비스가 별도 트랜잭션이거나 외부 시스템 호출이라면 보상 로직이 필요할 수 있습니다.

22-30: 데이터베이스 레벨의 고유 제약으로 동시성 안전성 확보됨

isAlreadyHandled 확인과 markAsHandled 저장 사이의 시간 간격에서 동일 이벤트가 여러 컨슈머에서 동시 처리될 가능성이 있습니다. 그러나 현재 구현에서는 다음 메커니즘으로 중복 처리가 방지됩니다:

EventHandled.eventId가 기본키이면서 고유 제약으로 보호됨
중복 삽입 시도 시 데이터베이스 제약 위반으로 예외 발생
MetricsKafkaConsumer.consume()의 @Transactional 래퍼로 원자성 보장
예외 발생 시 수동 ACK 미전송으로 메시지 재처리 보장
추가 변경 불필요.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt (1)
17-26: 전반적인 엔티티 구조 확인

이벤트 멱등성 처리를 위한 엔티티 구조가 적절합니다. eventId를 primary key로 사용하고, eventType과 handledAt을 기록하여 처리된 이벤트를 추적합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/product/ProductBrowsedEvent.kt (1)
10-11: aggregateId = 0L 사용 시 Kafka 파티셔닝 고려

목록 조회 이벤트의 aggregateId를 0L로 고정하면 모든 PRODUCT_BROWSED 이벤트가 동일한 Kafka 파티션으로 전송되어 특정 파티션에 핫스팟이 발생할 수 있습니다.

memberId의 해시값이나 다른 분산 키를 사용하는 것을 고려하세요.

apps/commerce-api/src/main/kotlin/com/loopers/domain/event/EventOutbox.kt (1)
15-92: Transactional Outbox 패턴 엔티티 구조 적절함

At-Least-Once 보장을 위한 아웃박스 패턴 구현이 잘 되어 있습니다:

처리 상태 추적을 위한 적절한 인덱스 구성
Kafka 메타데이터(partition, offset) 기록
재시도 횟수 및 에러 추적
apps/commerce-api/src/main/kotlin/com/loopers/domain/product/event/ProductViewedEvent.kt (1)
7-16: DomainEvent 구현 및 일관성 확인

DomainEvent 인터페이스 구현이 올바르게 되어 있습니다. 다른 이벤트 클래스들과 동일하게 aggregateId/productId 중복 및 occurredAt/viewedAt 타임스탬프 개선을 고려하세요.

🔎 선택적 개선안
 data class ProductViewedEvent(
     override val eventId: String = UUID.randomUUID().toString(),
     override val eventType: String = "PRODUCT_VIEWED",
-    override val aggregateId: Long, // productId (partitionKey)
-    override val occurredAt: Instant = Instant.now(),

     val productId: Long,
     val memberId: String?,  // 비로그인 사용자는 null
     val viewedAt: Instant = Instant.now(),
-) : DomainEvent
+) : DomainEvent {
+    override val aggregateId: Long get() = productId
+    override val occurredAt: Instant get() = viewedAt
+}
apps/commerce-api/src/test/kotlin/com/loopers/application/like/LikeFacadeIntegrationTest.kt (1)
29-42: 테스트 설정 및 Mock 구성 확인

스케줄링 비활성화(spring.task.scheduling.enabled=false)와 KafkaTemplate Mock 설정이 적절합니다. 이를 통해 비동기 이벤트 발행 없이 EventOutbox 기반 검증에 집중할 수 있습니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/order/OrderCreatedEvent.kt (2)
7-19: LGTM! 도메인 이벤트 구현이 적절합니다.

DomainEvent 인터페이스를 올바르게 구현하고 있으며, 메타데이터와 페이로드가 잘 분리되어 있습니다.

참고: occurredAt과 createdAt이 각각 Instant.now()를 기본값으로 사용하므로, 객체 생성 시 미세한 시간 차이가 발생할 수 있습니다. 의도된 설계라면 무시하셔도 됩니다.

21-25: LGTM!

주문 상품 정보를 전달하기 위한 간결한 DTO입니다.

apps/commerce-streamer/src/test/kotlin/com/loopers/application/metrics/MetricsEventFacadeTest.kt (5)
33-43: LGTM! 테스트 설정이 적절합니다.

relaxed = true를 사용하면서도 save() 메서드에 대해 명시적으로 스텁을 설정한 것이 좋습니다.

45-71: LGTM!

이벤트 처리와 EventHandled 저장을 모두 검증하는 완전한 테스트입니다.

117-147: LGTM! OrderCreatedEvent 테스트가 잘 작성되었습니다.

주문 상품별로 incrementSales가 올바른 수량으로 호출되는지 검증하고 있습니다.

149-173: LGTM! 멱등성 테스트가 적절합니다.

중복 이벤트 처리 시 서비스 호출과 저장이 발생하지 않음을 정확히 검증합니다.

175-203: LGTM!

returnsMany를 사용하여 동일 이벤트의 연속 호출 시나리오를 효과적으로 테스트합니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/order/OrderService.kt (4)
50-67: 쿠폰 적용 로직이 명확합니다.

단, coupon.use() 호출이 트랜잭션 내에서 이루어지므로, 이후 로직에서 예외 발생 시 자동으로 롤백됩니다.

121-141: LGTM! OrderCreatedEvent 발행 로직이 적절합니다.

OrderItemDto 매핑이 올바르게 구현되어 있습니다. 위에서 언급한 savedOrder.id nullable 확인만 해주세요.

159-173: 재고 차감 및 이벤트 발행 로직이 적절합니다.

각 주문 상품별로 재고 차감 후 StockDecreasedEvent를 발행하는 패턴이 일관성 있습니다. 단, 위에서 언급한 nullable ID 확인이 product.id와 order.id에도 적용됩니다.

95-106: 이 우려사항은 적용되지 않습니다.

Order 엔티티의 id 필드는 BaseEntity에서 val id: Long = 0으로 정의되어 있으므로 non-nullable Long 타입입니다. 따라서 savedOrder.id를 CouponUsedEvent의 aggregateId와 orderId에 전달하는 것은 완전히 안전하며 컴파일 오류나 NPE 위험이 없습니다.

Likely an incorrect or invalid review comment.

apps/commerce-api/src/main/kotlin/com/loopers/domain/payment/event/PaymentCompletedEvent.kt (1)
11-21: LGTM! DomainEvent 인터페이스를 올바르게 구현했습니다.

OrderCreatedEvent와 동일하게 occurredAt과 completedAt이 별도의 Instant.now() 호출을 사용합니다. 일관된 패턴이므로 의도된 설계로 보입니다.

apps/commerce-api/src/main/kotlin/com/loopers/domain/product/event/ProductBrowsedEvent.kt (1)
7-18: LGTM! 목록 조회 이벤트에 적합한 구현입니다.

aggregateId = 0L 기본값은 특정 상품이 없는 목록 조회 컨텍스트에 적절합니다. sortType을 String으로 변경한 것은 직렬화 유연성을 높여줍니다.

apps/commerce-api/src/test/kotlin/com/loopers/infrastructure/event/OutboxEventPublisherTest.kt (3)
29-58: 테스트 설정 및 라이프사이클 구조가 적절합니다.

@SpringBootTest와 함께 Kafka 및 스케줄링을 비활성화하여 격리된 테스트 환경을 구성했습니다. @BeforeEach에서 MockK를 통한 KafkaTemplate 모킹과 @AfterEach에서 데이터베이스 정리 및 모킹 초기화가 잘 구현되어 있습니다.

60-96: 성공 시나리오 테스트가 잘 구현되어 있습니다.

Kafka 발행 성공 시 processed, processedAt, kafkaPartition, kafkaOffset 필드가 올바르게 업데이트되는지 검증합니다. 토픽 라우팅(catalog-events)과 파티션 키(100)도 함께 확인하고 있습니다.

195-235: 다중 이벤트 발행 테스트가 잘 구현되어 있습니다.

두 개의 서로 다른 aggregateType 이벤트(product, order)가 각각 올바른 토픽(catalog-events, order-events)으로 발행되고, 모든 이벤트가 processed = true로 업데이트되는지 검증합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1)
36-66: 단일 메시지 소비 구조가 적절합니다.

Manual acknowledgment와 트랜잭션 경계 설정, 예외 시 재처리 전략이 at-least-once 의미론에 맞게 구현되어 있습니다. 로깅도 적절히 포함되어 있습니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/application/metrics/BatchMetricsEventFacade.kt (2)
35-92: 배치 이벤트 처리 로직이 잘 구현되어 있습니다.

멱등성 체크, 이벤트 타입별 분류, 상품별 그룹화, 처리 완료 기록 등 배치 처리에 필요한 핵심 로직이 체계적으로 구현되어 있습니다. 로깅도 적절히 포함되어 있어 디버깅에 유용합니다.

69-83: 주문 이벤트 처리 중 부분 실패 시 동작을 검토하세요.

orderEvents.forEach 내에서 productMetricsService.incrementSales 호출 시 예외가 발생하면, 이후 이벤트는 처리되지 않지만 이전에 처리된 이벤트들은 markAllAsHandled에서 모두 처리 완료로 기록됩니다.

현재 구조에서는 예외 발생 시 트랜잭션 롤백이 필요하거나, 개별 이벤트 단위 에러 핸들링이 필요할 수 있습니다. @Transactional이 호출자(Consumer)에 있으므로 롤백은 동작하지만, 이 동작이 의도된 것인지 확인하세요.

apps/commerce-streamer/src/main/kotlin/com/loopers/config/KafkaConsumerConfig.kt (1)
35-51: 리스너 컨테이너 팩토리 설정이 적절합니다.

manualAckKafkaListenerContainerFactory와 batchKafkaListenerContainerFactory 모두 MANUAL ack 모드를 사용하고, 배치 리스너는 isBatchListener = true로 설정되어 있습니다. 소비자 구현체와 잘 연동됩니다.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt (1)
57-69: 토픽 매핑 로직 확인

토픽 이름이 하드코딩되어 있습니다. 환경별로 토픽명이 다를 수 있으므로, 향후 application.yml 등으로 외부화하는 것을 고려해 주세요. 현재 구현은 동작에 문제가 없습니다.

apps/commerce-api/src/test/kotlin/com/loopers/infrastructure/event/OutboxEventListenerTest.kt (3)
1-51: 테스트 구성 LGTM

@TestPropertySource로 스케줄링을 비활성화하고, KafkaTemplate을 모킹하여 테스트 격리를 잘 구성했습니다. TransactionTemplate을 사용한 트랜잭션 컨텍스트 내 이벤트 발행 테스트도 적절합니다.

176-216: 멱등성 테스트 구현 우수

동일한 eventId로 중복 발행 시 outbox에 중복 저장되지 않는 것을 검증하는 테스트가 잘 구현되었습니다. 이벤트 기반 시스템에서 중요한 요구사항입니다.

297-327: JSON 직렬화 검증 테스트 적절

payload에 모든 필수 필드가 JSON으로 직렬화되는지 검증하고 있습니다. 문자열 contains 검증은 간단하지만 효과적입니다. 필요시 Jackson ObjectMapper로 역직렬화 후 객체 비교도 고려할 수 있습니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/domain/metrics/ProductMetricsService.kt (2)
72-79: 이벤트 타입 매핑 검토

applyEvent에서 ProductLikedEvent, ProductUnlikedEvent, ProductViewedEvent를 처리합니다. processBatchEvents가 product 이벤트만 받도록 상위 레이어에서 필터링되는지 확인하세요. 그렇지 않으면 OrderCreatedEvent 등이 전달될 경우 경고 로그만 남고 무시됩니다.

81-105: 이벤트 순서 보장 로직 적절

metrics.updatedAt.isAfter(eventOccurredAt) 체크로 순서가 뒤바뀐 이벤트를 무시하는 방어 로직이 잘 구현되었습니다. ProductMetrics 엔티티의 모든 변경 메서드(incrementLikes(), decrementLikes(), incrementViews(), incrementSales())에서 updatedAt = Instant.now()로 명시적으로 갱신되고 있으므로, 이벤트 순서 보장 메커니즘이 정상 작동합니다.

