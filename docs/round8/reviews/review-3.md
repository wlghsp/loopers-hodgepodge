@coderabbitai[bot] commented on this pull request.

Actionable comments posted: 4

🧹 Nitpick comments (3)
apps/commerce-streamer/src/main/kotlin/com/loopers/application/cache/CacheInvalidationFacade.kt (1)
55-62: 이벤트 처리 시각 기록 개선 고려

60라인에서 Instant.now()를 사용하고 있는데, 이벤트의 실제 발생 시각(event.occurredAt)과 괴리가 있을 수 있습니다. 디버깅이나 이벤트 순서 추적 시 혼란을 줄 수 있습니다.

처리 완료 시각과 이벤트 발생 시각을 모두 기록하는 것을 고려해보세요.

🔎 개선 제안
EventHandled 엔터티에 occurredAt 필드 추가:

 private fun markAsHandled(event: DomainEvent) {
     eventHandledRepository.save(
         EventHandled(
             eventId = event.eventId,
             eventType = event.eventType,
+            occurredAt = event.occurredAt,
             handledAt = Instant.now()
         )
     )
 }
apps/commerce-streamer/src/test/kotlin/com/loopers/application/cache/CacheInvalidationFacadeTest.kt (2)
47-47: EventHandled 저장 검증 강화 권장

현재 verify { eventHandledRepository.save(any()) }로만 검증하고 있어, 실제로 올바른 데이터가 저장되는지 확인하지 못합니다. 잘못된 eventId나 eventType이 저장되어도 테스트가 통과합니다.

🔎 개선된 검증 방법
ArgumentCaptor를 사용하거나 mockk의 slot을 활용하여 저장되는 엔터티를 검증:

+import io.mockk.slot

 @Test
 fun handleStockDecreasedEvent() {
     // given
     val event = StockDecreasedEvent(...)
+    val eventHandledSlot = slot<EventHandled>()

     every { eventHandledRepository.existsByEventId(any()) } returns false
     every { productCacheService.invalidateProductCache(any()) } just Runs
-    every { eventHandledRepository.save(any()) } returns mockk()
+    every { eventHandledRepository.save(capture(eventHandledSlot)) } returns mockk()

     // when
     cacheInvalidationFacade.handleEvent(event)

     // then
     verify(exactly = 1) { productCacheService.invalidateProductCache(1L) }
     verify(exactly = 0) { productCacheService.invalidateProductListCache() }
     verify(exactly = 1) { eventHandledRepository.save(any()) }
+    
+    // EventHandled 내용 검증
+    val savedEvent = eventHandledSlot.captured
+    assertEquals("event-123", savedEvent.eventId)
+    assertEquals("STOCK_DECREASED", savedEvent.eventType)
 }
Also applies to: 74-74, 82-82

1-108: 예외 시나리오 테스트 추가 권장

현재 테스트는 정상 흐름만 검증하고 있습니다. 다음 예외 시나리오에 대한 테스트 추가를 고려해보세요:

캐시 무효화 실패 시 동작 (ProductCacheService가 예외를 던지는 경우)
EventHandledRepository 저장 실패 시 동작
동시성 시나리오 (Race condition) - 통합 테스트에서 검증 필요할 수 있음
🔎 예외 테스트 예시
@DisplayName("캐시 무효화 실패 시에도 이벤트는 처리됨으로 표시된다")
@Test
fun handleEventWhenCacheInvalidationFails() {
    // given
    val event = StockDecreasedEvent(...)
    
    every { eventHandledRepository.existsByEventId(any()) } returns false
    every { productCacheService.invalidateProductCache(any()) } throws RuntimeException("Redis connection failed")
    every { eventHandledRepository.save(any()) } returns mockk()

    // when & then
    assertDoesNotThrow {
        cacheInvalidationFacade.handleEvent(event)
    }
    
    // 이벤트는 여전히 처리됨으로 표시되어야 함 (재시도 방지)
    verify(exactly = 1) { eventHandledRepository.save(any()) }
}
📜 Review details
Configuration used: Repository UI

Review profile: CHILL

Plan: Pro

📥 Commits
Reviewing files that changed from the base of the PR and between f52b24d and 129a06e.

📒 Files selected for processing (4)
apps/commerce-streamer/src/main/kotlin/com/loopers/application/cache/CacheInvalidationFacade.kt (1 hunks)
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/cache/ProductCacheService.kt (1 hunks)
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/CacheInvalidationKafkaConsumer.kt (1 hunks)
apps/commerce-streamer/src/test/kotlin/com/loopers/application/cache/CacheInvalidationFacadeTest.kt (1 hunks)
🔇 Additional comments (1)
apps/commerce-streamer/src/main/kotlin/com/loopers/domain/cache/ProductCacheService.kt (1)
25-37: 캐시 무효화 로직 확인 완료

단일 상품 캐시 무효화 로직이 정확하며, 예외 처리도 적절합니다. 캐시 작업의 특성상 실패를 로깅만 하는 것은 합리적인 선택입니다.

In apps/commerce-streamer/src/main/kotlin/com/loopers/application/cache/CacheInvalidationFacade.kt:

> +    fun handleEvent(event: DomainEvent) {
+        if (isAlreadyHandled(event)) {
+            logger.warn("중복 이벤트 무시: eventId=${event.eventId}, eventType=${event.eventType}")
+            return
+        }
+
+        routeAndProcess(event)
+        markAsHandled(event)
+    }
⚠️ Potential issue | 🔴 Critical

이벤트 중복 처리 방지 로직에 경쟁 조건(Race Condition) 존재

24라인의 isAlreadyHandled 체크와 30라인의 markAsHandled 호출 사이에 경쟁 조건이 존재합니다. 두 스레드가 동시에 같은 이벤트를 처리할 경우, 둘 다 중복 체크를 통과한 후 각각 캐시 무효화를 수행할 수 있습니다.

이는 PR 목표에서 명시한 At-Most-Once 보장을 위반합니다.

🔎 제안하는 해결 방법
방법 1: 데이터베이스 유니크 제약 조건 활용 (권장)

EventHandled 엔터티의 eventId에 유니크 제약을 추가하고, 중복 삽입 시도 시 예외를 처리:

 fun handleEvent(event: DomainEvent) {
-    if (isAlreadyHandled(event)) {
-        logger.warn("중복 이벤트 무시: eventId=${event.eventId}, eventType=${event.eventType}")
-        return
+    try {
+        markAsHandled(event)
+    } catch (e: DataIntegrityViolationException) {
+        logger.warn("중복 이벤트 무시: eventId=${event.eventId}, eventType=${event.eventType}")
+        return
     }

     routeAndProcess(event)
-    markAsHandled(event)
 }
EventHandled 엔터티에 유니크 제약 추가 필요:

@Table(
    name = "event_handled",
    uniqueConstraints = [UniqueConstraint(columnNames = ["event_id"])]
)
방법 2: 분산 락 사용

Redis 분산 락을 사용하여 동일 eventId에 대한 동시 처리 방지 (추가 Redis 왕복 필요)

📝 Committable suggestion
‼️ IMPORTANT
Carefully review the code before committing. Ensure that it accurately replaces the highlighted code, contains no missing lines, and has no issues with indentation. Thoroughly test & benchmark the code to ensure it meets the requirements.

⬇️ Suggested change
-    fun handleEvent(event: DomainEvent) {
-        if (isAlreadyHandled(event)) {
-            logger.warn("중복 이벤트 무시: eventId=${event.eventId}, eventType=${event.eventType}")
-            return
-        }
-
-        routeAndProcess(event)
-        markAsHandled(event)
-    }
+    fun handleEvent(event: DomainEvent) {
+        try {
+            markAsHandled(event)
+        } catch (e: DataIntegrityViolationException) {
+            logger.warn("중복 이벤트 무시: eventId=${event.eventId}, eventType=${event.eventType}")
+            return
+        }
+
+        routeAndProcess(event)
+    }
In apps/commerce-streamer/src/main/kotlin/com/loopers/domain/cache/ProductCacheService.kt:

> +    fun invalidateProductListCache() {
+        try {
+            val pattern = "$PRODUCT_LIST_CACHE_PREFIX*"
+            val keys = redisTemplate.keys(pattern)
+            if (!keys.isNullOrEmpty()) {
+                val deletedCount = redisTemplate.delete(keys)
+                logger.info("상품 목록 캐시 무효화 성공: ${deletedCount}개")
+            } else {
+                logger.debug("상품 목록 캐시 없음")
+            }
+        } catch (e: Exception) {
+            logger.error("상품 목록 캐시 무효화 실패", e)
+        }
+    }
⚠️ Potential issue | 🟠 Major

Redis KEYS 명령어로 인한 성능 문제

redisTemplate.keys(pattern) (46라인)은 Redis의 KEYS 명령어를 사용하는데, 이는 전체 키 공간을 스캔하는 동안 Redis 서버를 블로킹합니다. 프로덕션 환경에서는 심각한 성능 저하를 유발할 수 있습니다.

대신 SCAN 명령어를 사용하여 논블로킹 방식으로 키를 순회하세요.

🔎 SCAN 명령어를 사용한 개선안
 fun invalidateProductListCache() {
     try {
         val pattern = "$PRODUCT_LIST_CACHE_PREFIX*"
-        val keys = redisTemplate.keys(pattern)
-        if (!keys.isNullOrEmpty()) {
-            val deletedCount = redisTemplate.delete(keys)
-            logger.info("상품 목록 캐시 무효화 성공: ${deletedCount}개")
-        } else {
-            logger.debug("상품 목록 캐시 없음")
-        }
+        var deletedCount = 0L
+        redisTemplate.execute { connection ->
+            val cursor = connection.scan(
+                org.springframework.data.redis.core.ScanOptions.scanOptions()
+                    .match(pattern)
+                    .count(100)
+                    .build()
+            )
+            while (cursor.hasNext()) {
+                val key = cursor.next()
+                if (redisTemplate.delete(String(key))) {
+                    deletedCount++
+                }
+            }
+            cursor.close()
+        }
+        if (deletedCount > 0) {
+            logger.info("상품 목록 캐시 무효화 성공: ${deletedCount}개")
+        } else {
+            logger.debug("상품 목록 캐시 없음")
+        }
     } catch (e: Exception) {
         logger.error("상품 목록 캐시 무효화 실패", e)
     }
 }
Committable suggestion skipped: line range outside the PR's diff.

In apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/CacheInvalidationKafkaConsumer.kt:

> +    @Transactional
+    fun consume(
+        @Payload message: String,
+        @Header(KafkaHeaders.RECEIVED_KEY) key: String,
+        @Header(KafkaHeaders.RECEIVED_PARTITION) partition: Int,
+        @Header(KafkaHeaders.OFFSET) offset: Long,
+        acknowledgment: Acknowledgment
+    ) {
+        logger.info("캐시 무효화 메시지 수신: partition=$partition, offset=$offset, key=$key")
+
+        try {
+            val event = parseEvent(message)
+
+            // 캐시 무효화 처리
+            cacheInvalidationFacade.handleEvent(event)
+
+            // Manual Ack
+            acknowledgment.acknowledge()
+            logger.info("캐시 무효화 처리 완료: eventId=${event.eventId}, eventType=${event.eventType}")
+
+        } catch (e: Exception) {
+            logger.error("캐시 무효화 처리 실패: partition=$partition, offset=$offset, error=${e.message}", e)
+            // ACK 하지 않음 → 재처리됨
+        }
⚠️ Potential issue | 🟠 Major

트랜잭션 범위와 ACK 타이밍 불일치 가능성

33라인의 @Transactional 어노테이션이 JPA 트랜잭션을 시작하지만:

Redis 캐시 무효화는 트랜잭션 밖에서 수행됨
50라인의 Kafka ACK는 트랜잭션 커밋 이후 수행됨
이로 인해 다음 시나리오가 가능합니다:

이벤트가 event_handled 테이블에 저장됨 (트랜잭션 커밋)
Kafka ACK 전에 애플리케이션이 재시작됨
같은 메시지가 다시 수신되지만 이미 처리된 것으로 표시되어 캐시 무효화가 스킵됨
반대로, 캐시 무효화는 성공했지만 DB 저장이 실패할 수도 있습니다.

권장 사항:

CacheInvalidationFacade의 이벤트 저장을 ACK 이전에 완료하도록 트랜잭션 범위 조정
또는 캐시 무효화 실패를 치명적이지 않은 것으로 간주하고 로깅만 수행 (캐시는 TTL로 자연 만료되므로)
🤖 Prompt for AI Agents
In
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/CacheInvalidationKafkaConsumer.kt
around lines 33–56, the @Transactional on the consume method lets DB persistence
and ACK timing conflict with cache invalidation (ACK currently occurs inside the
transaction window), so change the flow to persist the event in a transactional
boundary before sending the Kafka ACK and treat cache invalidation as a
best-effort step: refactor CacheInvalidationFacade into two clear operations
(persistEvent(...) annotated @Transactional that only writes to the DB, and
invalidateCache(...) that performs Redis eviction), call persistEvent first,
then acknowledgment. After ACK, call invalidateCache in its own try/catch and
log failures as non-fatal (do not throw) so cache errors don’t block ACK/DB
commit; alternatively, if you must keep a single method, move @Transactional to
the DB-save method and ensure acknowledgment happens after that method returns.
In apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/CacheInvalidationKafkaConsumer.kt:

> +        return when (eventType) {
+            "STOCK_DECREASED" -> objectMapper.readValue(message, StockDecreasedEvent::class.java)
+            else -> {
+                // 다른 이벤트는 무시 (빈 이벤트 객체 반환하면 facade에서 필터링됨)
+                logger.debug("캐시 무효화 대상 아님: eventType=$eventType")
+                throw IllegalArgumentException("Not a cache invalidation event: $eventType")
+            }
⚠️ Potential issue | 🔴 Critical

비대상 이벤트 처리 시 무한 재시도 발생

73라인에서 STOCK_DECREASED가 아닌 이벤트에 대해 예외를 던지고 있습니다. 이 경우 메시지가 ACK되지 않아 Kafka가 해당 메시지를 무한히 재시도하게 되며, 컨슈머가 해당 파티션에서 멈추게 됩니다.

catalog-events 토픽에 다른 유형의 이벤트가 발행될 경우 컨슈머가 정상 작동하지 않습니다.

🔎 제안하는 수정
비대상 이벤트는 예외를 던지지 않고 null을 반환하거나, 처리를 건너뛰도록 변경:

 private fun parseEvent(message: String): DomainEvent? {
     val node = objectMapper.readTree(message)
     val eventType = node["eventType"]?.asText()
         ?: throw IllegalArgumentException("Missing eventType in message: $message")

     return when (eventType) {
         "STOCK_DECREASED" -> objectMapper.readValue(message, StockDecreasedEvent::class.java)
         else -> {
-            // 다른 이벤트는 무시 (빈 이벤트 객체 반환하면 facade에서 필터링됨)
             logger.debug("캐시 무효화 대상 아님: eventType=$eventType")
-            throw IllegalArgumentException("Not a cache invalidation event: $eventType")
+            null  // 비대상 이벤트는 null 반환
         }
     }
 }
그리고 consume 메서드에서 null 체크 추가:

 try {
     val event = parseEvent(message)
+    if (event == null) {
+        acknowledgment.acknowledge()
+        logger.debug("비대상 이벤트 스킵")
+        return
+    }

     // 캐시 무효화 처리
     cacheInvalidationFacade.handleEvent(event)
Committable suggestion skipped: line range outside the PR's diff.

🤖 Prompt for AI Agents
In
apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/CacheInvalidationKafkaConsumer.kt
around lines 68–74, change the non-target-event handling so it does NOT throw an
exception (which causes the message to remain un-acked and be infinitely
retried); instead return null (or an EmptyEvent marker) when eventType !=
"STOCK_DECREASED". Then update the consume method to null-check the parsed event
and simply skip processing/acknowledging logic for nulls (or treat the marker as
a no-op) so the consumer can commit the offset and continue processing other
messages.
—
Reply to this email directly, view it on GitHub, or unsubscribe.
You are receiving this because you were assigned.

