Actionable comments posted: 7

♻️ Duplicate comments (2)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt (2)
60-66: 토픽 이름 불일치 문제

과거 리뷰에서 지적된 대로, 이 메서드는 단수형 토픽 이름("catalog-event", "order-event")을 반환하지만, OutboxEventPublisher는 복수형("catalog-events", "order-events")을 사용합니다. DLQ 재시도 시 잘못된 토픽으로 발행되어 메시지가 소실될 수 있습니다.

토픽 이름을 복수형으로 통일하고, ignoreCase = true를 추가하여 대소문자 불일치도 방지하세요.

🔎 토픽 이름 통일 제안
     private fun getTopicForEventType(eventType: String): String {
         return when {
-            eventType.startsWith("product") -> "catalog-event"
-            eventType.startsWith("order") -> "order-event"
+            eventType.startsWith("product", ignoreCase = true) -> "catalog-events"
+            eventType.startsWith("order", ignoreCase = true) -> "order-events"
             else -> "general-events"
         }
     }
69-71: 미사용 파라미터

과거 리뷰에서 지적된 대로, limit 파라미터가 선언되었지만 실제 쿼리에서는 사용되지 않습니다. 항상 100개를 조회합니다. 파라미터를 제거하거나 동적 limit을 지원하도록 수정하세요.

🔎 수정 제안 (파라미터 제거)
-    fun getUnprocessedDeadLetters(limit: Int = 100): List<DeadLetterQueue> {
+    fun getUnprocessedDeadLetters(): List<DeadLetterQueue> {
         return deadLetterQueueRepository.findTop100ByProcessedFalseOrderByCreatedAtAsc()
     }
🧹 Nitpick comments (4)
apps/commerce-api/src/test/kotlin/com/loopers/domain/order/OrderServiceTest.kt (2)
7-7: 사용하지 않는 import 제거 필요

CouponUsedEvent가 import되었으나 이 테스트 파일에서 사용되지 않습니다.

🔎 수정 제안
-import com.loopers.domain.coupon.event.CouponUsedEvent
42-42: 이벤트 발행 검증 누락 검토 필요

eventPublisher를 relaxed = true로 설정하여 이벤트 발행을 자동으로 허용하고 있습니다. 그러나 createOrderWithCouponAndPoint 테스트에서 OrderCreatedEvent 발행 여부를 더 이상 검증하지 않습니다.

다른 테스트(createOrderWithoutCouponAndPublishEvent)에서는 여전히 이벤트 발행을 검증하고 있어 일관성이 없습니다. 쿠폰 사용 시에도 OrderCreatedEvent가 정상적으로 발행되는지 검증하는 것이 좋습니다.

🔎 이벤트 검증 추가 제안
         verify(exactly = 1) { memberCoupon.use() } // OrderService에서 coupon.use() 직접 호출
         verify(exactly = 1) { member.usePoint(3000L) }
         
+        // 주문 생성 이벤트 발행 검증
+        verify(exactly = 1) { eventPublisher.publishEvent(any<OrderCreatedEvent>()) }
+        
         // 주문 생성 결과 검증
Also applies to: 101-112

apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1)
72-76: 로그 메시지에 전체 페이로드 포함 시 로그 오염 가능성.

75번 라인의 에러 메시지에 전체 message 문자열을 포함하고 있습니다. 이벤트 페이로드가 큰 경우 로그가 지나치게 길어질 수 있습니다.

메시지를 truncate하거나 에러 메시지에서 제외하는 것을 고려하세요.

🔎 에러 메시지 개선 제안
     private fun parseEvent(message: String): DomainEvent {
         val node = objectMapper.readTree(message)
         val eventType = node["eventType"]?.asText()
-            ?: throw IllegalArgumentException("Missing eventType in message: $message")
+            ?: throw IllegalArgumentException("Missing eventType in message (length=${message.length})")
 
         return when (eventType) {
             // ...
             else -> throw IllegalArgumentException("Unknown event type: $eventType")
         }
     }
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt (1)
33-34: 메서드 시그니처의 스타일 불일치

Line 34의 ) : Boolean에서 콜론 앞 공백은 Kotlin 컨벤션에 어긋납니다. 공백을 제거하세요.

🔎 스타일 수정 제안
-    fun retryDeadLetterEvent(dlqId: Long, resolvedBy: String) : Boolean {
+    fun retryDeadLetterEvent(dlqId: Long, resolvedBy: String): Boolean {
📜 Review details
Configuration used: Repository UI

Review profile: CHILL

Plan: Pro

📥 Commits
Reviewing files that changed from the base of the PR and between 2cbc6c8 and f52b24d.

📒 Files selected for processing (9)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxJpaRepository.kt (1 hunks)
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt (1 hunks)
apps/commerce-api/src/test/kotlin/com/loopers/application/like/LikeFacadeIntegrationTest.kt (11 hunks)
apps/commerce-api/src/test/kotlin/com/loopers/domain/order/OrderServiceTest.kt (5 hunks)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt (1 hunks)
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt (1 hunks)
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/BatchMetricsEventConsumer.kt (1 hunks)
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1 hunks)
🚧 Files skipped from review as they are similar to previous changes (4)
apps/commerce-api/src/test/kotlin/com/loopers/domain/payment/PaymentRecoveryTransactionServiceTest.kt
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxJpaRepository.kt
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/BatchMetricsEventConsumer.kt
apps/commerce-api/src/test/kotlin/com/loopers/application/like/LikeFacadeIntegrationTest.kt
🧰 Additional context used 🧬 Code graph analysis (1) apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1)
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/BatchMetricsEventConsumer.kt (1)
parseEvent (54-71)
🔇 Additional comments (5)
apps/commerce-api/src/test/kotlin/com/loopers/domain/order/OrderServiceTest.kt (2)
75-88: 쿠폰 서비스 API 분리 적용 LGTM

getMemberCoupon, calculateDiscount, memberCoupon.use()로 분리된 새로운 API 패턴이 테스트에 올바르게 반영되었습니다. mock 설정과 검증이 일관성 있게 구성되어 있습니다.

107-112: 주문 금액 계산 검증 LGTM

금액 계산이 올바릅니다:

totalAmount: 10,000 × 2 + 20,000 × 1 = 40,000원
discountAmount: 쿠폰 할인 5,000원
finalAmount: 40,000 - 5,000 = 35,000원
포인트가 Order가 아닌 Member에서 차감된다는 주석이 명확합니다.

apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt (1)
36-47: 매뉴얼 ACK 설정이 올바르게 구성되었습니다.

전용 manualAckKafkaListenerContainerFactory를 사용하고 Acknowledgment 파라미터를 포함하여 수동 커밋을 정확하게 구현했습니다. 토픽 구성과 컨슈머 그룹 설정도 적절합니다.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt (1)
26-28: 재시도 횟수 설정이 적절함

최대 재시도 횟수 3회는 합리적인 설정입니다.

apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt (1)
19-31: DLQ 저장 로직이 적절함

EventOutbox를 DeadLetterQueue로 변환하여 저장하는 로직이 올바르게 구현되어 있으며, 에러 정보를 충분히 저장합니다.

In apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/DeadLetterQueueService.kt:

> +        return try {
+            val topic = getTopicForEventType(dlq.eventType)
+            kafkaTemplate.send(topic, dlq.eventId, dlq.payload).get(30, TimeUnit.SECONDS)
⚠️ Potential issue | 🔴 Critical

파티션 키 불일치로 인한 순서 보장 위반

Line 44에서 dlq.eventId를 파티션 키로 사용하는데, OutboxEventPublisher는 aggregateId를 파티션 키로 사용합니다. DLQ 재시도 시 원본 이벤트와 다른 파티션으로 전송되어 동일 제품의 이벤트 순서가 보장되지 않을 수 있습니다.

파티션 키를 일관되게 유지하려면 DeadLetterQueue 엔티티에 aggregateId를 추가로 저장하고, 재시도 시 이를 파티션 키로 사용하세요.

🔎 파티션 키 수정 제안
DeadLetterQueue 엔티티에 aggregateId 필드를 추가한 후:

         return try {
             val topic = getTopicForEventType(dlq.eventType)
-            kafkaTemplate.send(topic, dlq.eventId, dlq.payload).get(30, TimeUnit.SECONDS)
+            kafkaTemplate.send(topic, dlq.aggregateId ?: dlq.eventId, dlq.payload).get(30, TimeUnit.SECONDS)
 
             dlq.processed = true
Committable suggestion skipped: line range outside the PR's diff.

In apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt:

> +    @Scheduled(fixedDelay = 1000)
+    @Transactional
+    fun publishPendingEvents() {
⚠️ Potential issue | 🔴 Critical

@scheduled와 @transactional 조합으로 인한 트랜잭션 타임아웃 위험

단일 트랜잭션으로 최대 100개 이벤트를 순차 처리하면서 각 Kafka 발행마다 최대 30초 대기가 가능하므로, 전체 트랜잭션이 수십 분간 유지될 수 있습니다. 이는 다음 문제를 야기합니다:

DB 커넥션 장시간 점유로 인한 커넥션 풀 고갈
트랜잭션 타임아웃 초과 시 전체 배치 롤백
일부 이벤트만 실패해도 성공한 이벤트까지 모두 롤백
각 이벤트를 개별 트랜잭션으로 처리하거나, @Transactional을 제거하고 각 save 호출을 별도 트랜잭션으로 실행하도록 수정하세요.

🔎 개별 트랜잭션 처리 제안
     @Scheduled(fixedDelay = 1000)
-    @Transactional
     fun publishPendingEvents() {
         val pendingEvents = eventOutboxRepository
             .findTop100ByProcessedFalseOrderByCreatedAtAsc()
그리고 각 이벤트 처리를 별도 메서드로 분리하여 @Transactional 적용:

@Transactional
private fun processEvent(outbox: EventOutbox) {
    try {
        publishToKafka(outbox)
        outbox.processed = true
        outbox.processedAt = Instant.now()
        eventOutboxRepository.save(outbox)
        logger.info("Kafka 발행 성공: eventId=${outbox.eventId}")
    } catch (e: Exception) {
        handlePublishFailure(outbox, e)
    }
}
Committable suggestion skipped: line range outside the PR's diff.

In apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt:

> +    private fun publishToKafka(outbox: EventOutbox) {
+        val topic = when (outbox.aggregateType.lowercase()) {
+            "product" -> "catalog-events"
+            "order" -> "order-events"
+            else -> "general-events"
+        }
+
+        val partitionKey = outbox.aggregateId.toString()
+        val result = kafkaTemplate.send(topic, partitionKey, outbox.payload).get(30, TimeUnit.SECONDS)
+
+        outbox.kafkaPartition = result.recordMetadata.partition()
+        outbox.kafkaOffset = result.recordMetadata.offset()
+    }
⚠️ Potential issue | 🟠 Major

동기 Kafka 발행의 타임아웃이 과도함

각 이벤트마다 최대 30초 동기 대기는 배치 처리 성능을 크게 저하시킵니다. 100개 이벤트 처리 시 일부만 느려도 전체 배치가 지연되며, 최악의 경우 수십 분이 소요될 수 있습니다.

타임아웃을 5~10초로 단축하거나, 비동기 발행 후 CompletableFuture 목록을 관리하는 방식으로 개선을 권장합니다.

🔎 타임아웃 단축 제안
     private fun publishToKafka(outbox: EventOutbox) {
         val topic = when (outbox.aggregateType.lowercase()) {
             "product" -> "catalog-events"
             "order" -> "order-events"
             else -> "general-events"
         }
 
         val partitionKey = outbox.aggregateId.toString()
-        val result = kafkaTemplate.send(topic, partitionKey, outbox.payload).get(30, TimeUnit.SECONDS)
+        val result = kafkaTemplate.send(topic, partitionKey, outbox.payload).get(5, TimeUnit.SECONDS)
 
         outbox.kafkaPartition = result.recordMetadata.partition()
         outbox.kafkaOffset = result.recordMetadata.offset()
     }
🤖 Prompt for AI Agents
In
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt
around lines 57-69, the code blocks waiting synchronously on each Kafka send
with .get(30, TimeUnit.SECONDS), which is too long and will degrade batch
throughput; change this to either reduce the per-send timeout to 5-10 seconds
(e.g., .get(5, TimeUnit.SECONDS)) or refactor to asynchronous sends: call
kafkaTemplate.send(...) without .get to collect the returned
ListenableFuture/CompletableFuture for each event, then wait for all futures
with a combined timeout (5–10s) using CompletableFuture.allOf(...) and on each
future completion extract and set kafkaPartition and kafkaOffset; ensure
failures/timeouts are handled and recorded back to the outbox accordingly.
In apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt:

> +    private fun handlePublishFailure(outbox: EventOutbox, e: Exception) {
+        outbox.retryCount++
+        outbox.lastError = e.message?.take(500)
+
+        if (outbox.retryCount >= MAX_RETRY) {
+            logger.error(
+                "Kafka 발행 실패 (최대 재시도 초과): eventId=${outbox.eventId}, retryCount=${outbox.retryCount}", e
+            )
+            deadLetterQueueService.moveToDeadLetterQueue(outbox, e)
+
+            outbox.processed = true
+            outbox.processedAt = Instant.now()
+        } else {
+            logger.warn(
+                "Kafka 발행 실패 (재시도 ${outbox.retryCount}회): eventId=${outbox.eventId}", e
+            )
+        }
+        eventOutboxRepository.save(outbox)
+    }
⚠️ Potential issue | 🟠 Major

DLQ 이동 실패 시 이벤트 손실 위험

Line 79에서 moveToDeadLetterQueue 호출이 실패할 경우 예외 처리가 없어, 이벤트가 DLQ로 이동되지 못한 채 processed=true로 표시되어 영구 손실될 수 있습니다.

DLQ 저장 실패 시 processed=true 설정을 건너뛰거나, DLQ 저장을 try-catch로 감싸서 실패 시 로그를 남기고 재시도 가능 상태로 유지하세요.

🔎 DLQ 이동 실패 처리 제안
     private fun handlePublishFailure(outbox: EventOutbox, e: Exception) {
         outbox.retryCount++
         outbox.lastError = e.message?.take(500)
 
         if (outbox.retryCount >= MAX_RETRY) {
             logger.error(
                 "Kafka 발행 실패 (최대 재시도 초과): eventId=${outbox.eventId}, retryCount=${outbox.retryCount}", e
             )
-            deadLetterQueueService.moveToDeadLetterQueue(outbox, e)
-
-            outbox.processed = true
-            outbox.processedAt = Instant.now()
+            try {
+                deadLetterQueueService.moveToDeadLetterQueue(outbox, e)
+                outbox.processed = true
+                outbox.processedAt = Instant.now()
+            } catch (dlqError: Exception) {
+                logger.error("DLQ 이동 실패: eventId=${outbox.eventId}", dlqError)
+                // processed=true 설정 안 함 -> 다음 배치에서 재시도
+            }
         } else {
             logger.warn(
                 "Kafka 발행 실패 (재시도 ${outbox.retryCount}회): eventId=${outbox.eventId}", e
             )
         }
         eventOutboxRepository.save(outbox)
     }
📝 Committable suggestion
‼️ IMPORTANT
Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

⬇️ Suggested change
-    private fun handlePublishFailure(outbox: EventOutbox, e: Exception) {
-        outbox.retryCount++
-        outbox.lastError = e.message?.take(500)
-
-        if (outbox.retryCount >= MAX_RETRY) {
-            logger.error(
-                "Kafka 발행 실패 (최대 재시도 초과): eventId=${outbox.eventId}, retryCount=${outbox.retryCount}", e
-            )
-            deadLetterQueueService.moveToDeadLetterQueue(outbox, e)
-
-            outbox.processed = true
-            outbox.processedAt = Instant.now()
-        } else {
-            logger.warn(
-                "Kafka 발행 실패 (재시도 ${outbox.retryCount}회): eventId=${outbox.eventId}", e
-            )
-        }
-        eventOutboxRepository.save(outbox)
-    }
+    private fun handlePublishFailure(outbox: EventOutbox, e: Exception) {
+        outbox.retryCount++
+        outbox.lastError = e.message?.take(500)
+
+        if (outbox.retryCount >= MAX_RETRY) {
+            logger.error(
+                "Kafka 발행 실패 (최대 재시도 초과): eventId=${outbox.eventId}, retryCount=${outbox.retryCount}", e
+            )
+            try {
+                deadLetterQueueService.moveToDeadLetterQueue(outbox, e)
+                outbox.processed = true
+                outbox.processedAt = Instant.now()
+            } catch (dlqError: Exception) {
+                logger.error("DLQ 이동 실패: eventId=${outbox.eventId}", dlqError)
+                // processed=true 설정 안 함 -> 다음 배치에서 재시도
+            }
+        } else {
+            logger.warn(
+                "Kafka 발행 실패 (재시도 ${outbox.retryCount}회): eventId=${outbox.eventId}", e
+            )
+        }
+        eventOutboxRepository.save(outbox)
+    }
🤖 Prompt for AI Agents
In
apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/OutboxEventPublisher.kt
around lines 71 to 89, the call to
deadLetterQueueService.moveToDeadLetterQueue(outbox, e) is not protected so any
failure will still mark the outbox as processed and cause data loss; wrap the
DLQ move in a try-catch, log the DLQ error (including exception) if it fails,
and do NOT set outbox.processed = true or processedAt when the DLQ move throws
so the record remains eligible for retry; ensure
eventOutboxRepository.save(outbox) reflects the failure path (incremented
retryCount/lastError but not processed), and only mark
processed=true/processedAt after a successful DLQ move.
In apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt:

> +@Entity
+@Table(name = "event_handled")
+class EventHandled(
+    @Id
+    val eventId: String,
+
+    @Column(nullable = false, length = 50)
+    val eventType: String,
+
+    @Column(nullable = false)
+    val handledAt: Instant = Instant.now()
+)
⚠️ Potential issue | 🟠 Major

🧩 Analysis chain
🏁 Script executed:

#!/bin/bash
# Find and examine the EventHandled.kt file and related entities

# First, locate the EventHandled.kt file
echo "=== Locating EventHandled.kt ===" 
find . -name "EventHandled.kt" -type f

echo -e "\n=== Locating EventOutbox.kt for comparison ===" 
find . -name "EventOutbox.kt" -type f 2>/dev/null

echo -e "\n=== Searching for DomainEvent implementations ===" 
find . -path ./node_modules -prune -o -name "*.kt" -type f -exec grep -l "DomainEvent" {} \; | head -20

echo -e "\n=== Searching for cleanup or retention policies ===" 
grep -r "cleanup\|retention\|purge\|delete.*event\|archive" --include="*.kt" --include="*.java" . 2>/dev/null | grep -i "handled\|outbox" | head -20
Repository: Loopers-dev-lab/loopers-spring-kotlin-template

Length of output: 2492

🏁 Script executed:

#!/bin/bash
# Read the actual EventHandled and EventOutbox files

echo "=== EventHandled.kt content ===" 
cat -n ./apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt

echo -e "\n=== EventOutbox.kt content ===" 
cat -n ./apps/commerce-api/src/main/kotlin/com/loopers/domain/event/EventOutbox.kt

echo -e "\n=== DomainEvent interface definition ===" 
cat -n ./apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/DomainEvent.kt
Repository: Loopers-dev-lab/loopers-spring-kotlin-template

Length of output: 4004

🏁 Script executed:

#!/bin/bash
# Check for scheduled jobs, cleanup logic, and actual event type values

echo "=== Searching for scheduled cleanup jobs ===" 
grep -r "@Scheduled\|@Async\|schedule\|cleanup\|purge\|archive" --include="*.kt" . 2>/dev/null | grep -i "event\|outbox\|handled" | head -20

echo -e "\n=== Check one example event implementation ===" 
cat -n ./apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/order/OrderCreatedEvent.kt 2>/dev/null || \
cat -n ./apps/commerce-api/src/main/kotlin/com/loopers/domain/order/event/OrderCreatedEvent.kt

echo -e "\n=== Check another event type ===" 
cat -n ./apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/coupon/CouponUsedEvent.kt 2>/dev/null || \
cat -n ./apps/commerce-api/src/main/kotlin/com/loopers/domain/coupon/event/CouponUsedEvent.kt

echo -e "\n=== Search for EventHandled repository/queries ===" 
find . -name "*EventHandled*" -o -name "*Handled*Repository*" | head -10

echo -e "\n=== Check if BaseEntity has lifecycle annotations ===" 
find . -name "BaseEntity.kt" -exec cat -n {} \;
Repository: Loopers-dev-lab/loopers-spring-kotlin-template

Length of output: 5019

🏁 Script executed:

#!/bin/bash
# Check the EventHandled repository and the cleanup scheduler details

echo "=== EventHandledRepository ===" 
cat -n ./apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/event/EventHandledRepository.kt

echo -e "\n=== EventOutboxCleanupScheduler (to see if there's a pattern) ===" 
cat -n ./apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxCleanupScheduler.kt

echo -e "\n=== Check for all event type strings (sample from different event files) ===" 
for file in $(find ./apps -name "*Event.kt" -path "*/event/*" | head -5); do
  echo "File: $file"
  grep "eventType.*=" "$file" | head -1
done
Repository: Loopers-dev-lab/loopers-spring-kotlin-template

Length of output: 1999

🏁 Script executed:

#!/bin/bash
# Final verification - check all event types to be thorough

echo "=== All eventType values in the codebase ===" 
grep -r "eventType.*String.*=" --include="*.kt" ./apps/commerce-api/src/main/kotlin/com/loopers/domain/*/event/ \
  ./apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/ 2>/dev/null | \
  grep -o '"[A-Z_]*"' | sort -u

echo -e "\n=== Check if EventHandled extends BaseEntity or has lifecycle methods ===" 
grep -E "class EventHandled|BaseEntity|@PrePersist|@PreUpdate" ./apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt

echo -e "\n=== Verify if EventOutbox cleanup is actually active ===" 
grep -A 2 "@Scheduled" ./apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/event/EventOutboxCleanupScheduler.kt
Repository: Loopers-dev-lab/loopers-spring-kotlin-template

Length of output: 482

데이터 보관 정책과 타임스탬프 정확성을 개선하세요.

이 엔티티는 몇 가지 운영상 고려사항이 있습니다:

데이터 보관 정책 누락 (주요 이슈): EventOutbox는 7일 후 자동 정리되지만, EventHandled 테이블에는 정리 전략이 없습니다. 이 테이블은 무한정 증가하게 됩니다. 데이터 아카이빙 또는 정리 스케줄러를 추가하세요.

타임스탬프 정확성 (경미한 이슈): handledAt의 기본값 Instant.now()는 객체 생성 시점에 평가되며, 실제 DB 저장 시점이 아닙니다. 정확한 저장 시각이 중요하다면 @PrePersist 콜백을 사용하거나 DB의 CURRENT_TIMESTAMP를 활용하는 것을 고려하세요.

향후 인덱스 고려사항 (선택사항): 정리 쿼리를 추가할 경우 handledAt에 인덱스가 필요할 수 있습니다. 현재는 주로 eventId(PK)로만 조회하므로 필수는 아니지만, 데이터 보관 정책을 구현할 때 함께 고려하세요.

🤖 Prompt for AI Agents
In
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/event/EventHandled.kt
around lines 9-20, the entity lacks a data retention strategy and uses
Instant.now() evaluated at object construction for handledAt; change handledAt
to be set at persist time (use a @PrePersist method to assign Instant.now() or
map the column to use DB CURRENT_TIMESTAMP) and add an application-level
cleanup/archiving mechanism (scheduled job or TTL process) to purge or archive
rows older than your retention period (e.g., 7 days); optionally add an index on
handledAt to support efficient cleanup queries when you implement the retention
job.
In apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt:

> +    @Transactional
+    fun consume(
+        @Payload message: String,
+        @Header(KafkaHeaders.RECEIVED_KEY) key: String,
+        @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
+        @Header(KafkaHeaders.OFFSET) offset: Long,
+        acknowledgment: Acknowledgment,
+    ) {
+        logger.info("메세지 수신: partition=$partition, offset=$offset, key=$key")
+
+        try {
+            // 1. JSON 파싱
+            val event = parseEvent(message)
+
+            // 2. Facade 에 위임 (멱등성 체크  + 이벤트 처리 + 동기화)
+            metricsEventFacade.handleEvent(event)
+
+            // 3. Manual Ack
+            acknowledgment.acknowledge()
+            logger.info("이벤트 처리 완료: eventId=${event.eventId}, eventType=${event.eventType}")
+
+        } catch (e: Exception) {
+            logger.error("이벤트 처리 실패: partition=$partition, offset=$offset, error=${e.message}", e)
+            // ACK 하지 않음 → 재처리됨
+        }
⚠️ Potential issue | 🔴 Critical

트랜잭션 경계와 ACK 타이밍 문제로 인한 메시지 손실 위험.

consume 메서드에 @Transactional이 적용되어 있고, 59번 라인에서 acknowledgment.acknowledge()가 트랜잭션 내부에서 호출됩니다. 이 경우 다음과 같은 위험이 있습니다:

ACK가 먼저 실행되고 이후 트랜잭션이 롤백되면 메시지는 acknowledged 되었지만 데이터는 저장되지 않아 메시지가 영구적으로 손실됩니다.
PR 목표에서 언급한 멱등성 기반 At-Most-Once 보장이 깨질 수 있습니다.
권장 해결 방법: consume 메서드에서 @Transactional을 제거하고, MetricsEventFacade.handleEvent()가 자체 트랜잭션을 관리하도록 한 뒤, facade 호출이 성공적으로 완료된 후에만 ACK를 수행하세요.

🔎 트랜잭션 경계 수정 제안
-    @Transactional
     fun consume(
         @Payload message: String,
         @Header(KafkaHeaders.RECEIVED_KEY) key: String,
         @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
         @Header(KafkaHeaders.OFFSET) offset: Long,
         acknowledgment: Acknowledgment,
     ) {
         logger.info("메세지 수신: partition=$partition, offset=$offset, key=$key")
 
         try {
             // 1. JSON 파싱
             val event = parseEvent(message)
 
-            // 2. Facade 에 위임 (멱등성 체크  + 이벤트 처리 + 동기화)
+            // 2. Facade 에 위임 (자체 트랜잭션 내에서 멱등성 체크 + 이벤트 처리 + 동기화)
             metricsEventFacade.handleEvent(event)
 
-            // 3. Manual Ack
+            // 3. Facade 성공 후 Manual Ack
             acknowledgment.acknowledge()
             logger.info("이벤트 처리 완료: eventId=${event.eventId}, eventType=${event.eventType}")
 
         } catch (e: Exception) {
             logger.error("이벤트 처리 실패: partition=$partition, offset=$offset, error=${e.message}", e)
             // ACK 하지 않음 → 재처리됨
         }
     }
MetricsEventFacade.handleEvent() 메서드에 @Transactional이 있는지 확인하고, 없다면 추가해야 합니다.

📝 Committable suggestion
‼️ IMPORTANT
Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

⬇️ Suggested change
-    @Transactional
-    fun consume(
-        @Payload message: String,
-        @Header(KafkaHeaders.RECEIVED_KEY) key: String,
-        @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
-        @Header(KafkaHeaders.OFFSET) offset: Long,
-        acknowledgment: Acknowledgment,
-    ) {
-        logger.info("메세지 수신: partition=$partition, offset=$offset, key=$key")
-
-        try {
-            // 1. JSON 파싱
-            val event = parseEvent(message)
-
-            // 2. Facade 에 위임 (멱등성 체크  + 이벤트 처리 + 동기화)
-            metricsEventFacade.handleEvent(event)
-
-            // 3. Manual Ack
-            acknowledgment.acknowledge()
-            logger.info("이벤트 처리 완료: eventId=${event.eventId}, eventType=${event.eventType}")
-
-        } catch (e: Exception) {
-            logger.error("이벤트 처리 실패: partition=$partition, offset=$offset, error=${e.message}", e)
-            // ACK 하지 않음 → 재처리됨
-        }
+    fun consume(
+        @Payload message: String,
+        @Header(KafkaHeaders.RECEIVED_KEY) key: String,
+        @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
+        @Header(KafkaHeaders.OFFSET) offset: Long,
+        acknowledgment: Acknowledgment,
+    ) {
+        logger.info("메세지 수신: partition=$partition, offset=$offset, key=$key")
+
+        try {
+            // 1. JSON 파싱
+            val event = parseEvent(message)
+
+            // 2. Facade 에 위임 (자체 트랜잭션 내에서 멱등성 체크 + 이벤트 처리 + 동기화)
+            metricsEventFacade.handleEvent(event)
+
+            // 3. Facade 성공 후 Manual Ack
+            acknowledgment.acknowledge()
+            logger.info("이벤트 처리 완료: eventId=${event.eventId}, eventType=${event.eventType}")
+
+        } catch (e: Exception) {
+            logger.error("이벤트 처리 실패: partition=$partition, offset=$offset, error=${e.message}", e)
+            // ACK 하지 않음 → 재처리됨
+        }
+    }
🤖 Prompt for AI Agents
In
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt
around lines 41-65, remove the @Transactional annotation from the consume method
and move transaction boundaries into the MetricsEventFacade: ensure
MetricsEventFacade.handleEvent() is annotated with @Transactional (or otherwise
manages its own transaction) and performs all DB/side-effect work inside that
transaction; call acknowledgment.acknowledge() only after handleEvent() returns
successfully (i.e., outside the transactional facade call) and keep the
try/catch so exceptions prevent ACK and allow reprocessing.
In apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt:

> +    private fun parseEvent(message: String): DomainEvent {
+        val node = objectMapper.readTree(message)
+        val eventType = node["eventType"]?.asText()
+            ?: throw IllegalArgumentException("Missing eventType in message: $message")
+
+        return when (eventType) {
+            // catalog-events
+            "PRODUCT_LIKED" -> objectMapper.readValue(message, ProductLikedEvent::class.java)
+            "PRODUCT_UNLIKED" -> objectMapper.readValue(message, ProductUnlikedEvent::class.java)
+            "PRODUCT_VIEWED" -> objectMapper.readValue(message, ProductViewedEvent::class.java)
+            "STOCK_DECREASED" -> objectMapper.readValue(message, StockDecreasedEvent::class.java)
+
+            // order-events
+            "ORDER_CREATED" -> objectMapper.readValue(message, OrderCreatedEvent::class.java)
+            "PAYMENT_COMPLETED" -> objectMapper.readValue(message, PaymentCompletedEvent::class.java)
+            "PAYMENT_FAILED" -> objectMapper.readValue(message, PaymentFailedEvent::class.java)
+            "COUPON_USED" -> objectMapper.readValue(message, CouponUsedEvent::class.java)
+
+            else -> throw IllegalArgumentException("Unknown event type: $eventType")
+        }
+    }
🛠️ Refactor suggestion | 🟠 Major

코드 중복: parseEvent 메서드를 공통 유틸리티로 추출 필요.

이 parseEvent 메서드는 BatchMetricsEventConsumer.kt 파일에 동일하게 구현되어 있습니다 (관련 코드 스니펫 참조). 코드 중복은 유지보수성을 저하시키고 두 구현 간 불일치 위험을 증가시킵니다.

공통 유틸리티 클래스 또는 확장 함수로 추출하여 재사용하는 것을 권장합니다.

🔎 공통 유틸리티 추출 예시
새 파일 생성: apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/kafka/EventParser.kt

package com.loopers.infrastructure.kafka

import com.fasterxml.jackson.databind.ObjectMapper
import com.loopers.domain.event.DomainEvent
import com.loopers.domain.event.coupon.CouponUsedEvent
import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.event.payment.PaymentCompletedEvent
import com.loopers.domain.event.payment.PaymentFailedEvent
import com.loopers.domain.event.product.StockDecreasedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.product.event.ProductViewedEvent
import org.springframework.stereotype.Component

@Component
class EventParser(private val objectMapper: ObjectMapper) {
    
    fun parseEvent(message: String): DomainEvent {
        val node = objectMapper.readTree(message)
        val eventType = node["eventType"]?.asText()
            ?: throw IllegalArgumentException("Missing eventType in message")

        return when (eventType) {
            "PRODUCT_LIKED" -> objectMapper.readValue(message, ProductLikedEvent::class.java)
            "PRODUCT_UNLIKED" -> objectMapper.readValue(message, ProductUnlikedEvent::class.java)
            "PRODUCT_VIEWED" -> objectMapper.readValue(message, ProductViewedEvent::class.java)
            "STOCK_DECREASED" -> objectMapper.readValue(message, StockDecreasedEvent::class.java)
            "ORDER_CREATED" -> objectMapper.readValue(message, OrderCreatedEvent::class.java)
            "PAYMENT_COMPLETED" -> objectMapper.readValue(message, PaymentCompletedEvent::class.java)
            "PAYMENT_FAILED" -> objectMapper.readValue(message, PaymentFailedEvent::class.java)
            "COUPON_USED" -> objectMapper.readValue(message, CouponUsedEvent::class.java)
            else -> throw IllegalArgumentException("Unknown event type: $eventType")
        }
    }
}
그 후 두 컨슈머 클래스에서 EventParser를 주입받아 사용:

 class MetricsKafkaConsumer(
     private val metricsEventFacade: MetricsEventFacade,
-    private val objectMapper: ObjectMapper
+    private val eventParser: EventParser
 ) {
     ...
     try {
         // 1. JSON 파싱
-        val event = parseEvent(message)
+        val event = eventParser.parseEvent(message)
         ...
     }
-    
-    private fun parseEvent(message: String): DomainEvent {
-        ...
-    }
 }
Committable suggestion skipped: line range outside the PR's diff.

🤖 Prompt for AI Agents
In
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/MetricsKafkaConsumer.kt
around lines 72-92, duplicate parseEvent logic exists and should be extracted to
a shared utility to avoid duplication with BatchMetricsEventConsumer; create a
new EventParser (or extension function) in a common package (e.g.,
apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/kafka/EventParser.kt)
that accepts ObjectMapper via constructor, moves the parseEvent implementation
there, and returns DomainEvent; then inject/instantiate this EventParser in both
MetricsKafkaConsumer and BatchMetricsEventConsumer and replace their parseEvent
implementations with calls to the shared parser, keeping error messages and
event mappings intact.
—
Reply to this email directly, view it on GitHub, or unsubscribe.
You are receiving this because you were assigned.

