# 🎯 Step 2: Ranking Kafka Consumer 구현

> **목표**: Kafka 이벤트를 소비하여 Redis ZSET에 랭킹 점수를 실시간으로 적재합니다.

---

## 📌 왜 Kafka Consumer가 필요한가?

commerce-api에서 발행된 이벤트(`ProductViewedEvent`, `ProductLikedEvent` 등)를:
- ✅ **비동기로** 처리하여 API 응답 속도에 영향 없음
- ✅ **배치로** 처리하여 Redis 연산 횟수 최소화
- ✅ **멱등성 보장**으로 재처리 시에도 데이터 정합성 유지

---

## 2-1. RankingEventFacade (Application Layer)

### 💡 왜 Facade 패턴을 사용하는가?

Consumer는 인프라 레이어입니다. 비즈니스 로직을 직접 포함하면:
- ❌ 테스트가 어려움 (Kafka 모킹 필요)
- ❌ 로직 재사용 불가 (REST API로도 랭킹 업데이트 하고 싶다면?)
- ❌ 트랜잭션 관리가 복잡해짐

**해결책**: Application Layer에 Facade를 두어 오케스트레이션 로직을 분리합니다.

### 📂 파일 생성

**경로**: `apps/commerce-streamer/src/main/kotlin/com/loopers/application/ranking/RankingEventFacade.kt`

```kotlin
package com.loopers.application.ranking

import com.loopers.domain.event.DomainEvent
import com.loopers.domain.event.EventHandled
import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.product.event.ProductViewedEvent
import com.loopers.domain.ranking.RankingScoreCalculator
import com.loopers.domain.ranking.RankingService
import com.loopers.infrastructure.event.EventHandledRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * 랭킹 이벤트 처리 Facade (Application Layer)
 *
 * 역할:
 * 1. 멱등성 보장 (event_handled 테이블 활용)
 * 2. 날짜별/상품별 점수 그룹화
 * 3. Redis ZSET 업데이트 오케스트레이션
 *
 * 왜 멱등성이 필요한가?
 * - Kafka Consumer 재시작 시 이벤트 재처리 가능
 * - At-Least-Once 전달 보장으로 중복 이벤트 발생 가능
 * - 동일 이벤트로 점수가 중복 증가하면 랭킹 왜곡
 *
 * Round 8에서 배운 내용 적용:
 * - event_handled 테이블로 처리 이력 관리
 * - 배치 단위로 멱등성 체크하여 성능 최적화
 */
@Service
class RankingEventFacade(
    private val rankingService: RankingService,
    private val rankingScoreCalculator: RankingScoreCalculator,
    private val eventHandledRepository: EventHandledRepository
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * 배치 이벤트 처리 (멱등성 보장 + 그룹화 최적화)
     *
     * 처리 흐름:
     * 1. Insert First (PK 제약조건으로 멱등성 보장)
     * 2. 성공한 이벤트만 필터링
     * 3. 날짜별 그룹화
     * 4. 상품별 점수 합산
     * 5. Redis ZSET 배치 업데이트
     *
     * 왜 Insert First 패턴을 사용하는가?
     * - Check-then-act 패턴의 문제:
     *   1) 조회 후 저장 사이에 다른 트랜잭션이 끼어들 수 있음 (Race Condition)
     *   2) 동시에 같은 이벤트를 처리하면 중복 처리 가능
     *
     * - Insert First 패턴의 장점:
     *   1) PK 제약조건이 원자적으로 중복을 방지
     *   2) 데이터베이스가 동시성을 보장
     *   3) Round 8에서 검증된 패턴 재사용
     *
     * @param events 이벤트 리스트
     */
    @Transactional
    fun handleBatchEvents(events: List<DomainEvent>) {
        if (events.isEmpty()) {
            return
        }

        logger.info("랭킹 배치 이벤트 처리 시작: ${events.size}개")

        // 1. Insert First - PK 제약조건으로 멱등성 보장
        val savedEvents = events.mapNotNull { event ->
            try {
                eventHandledRepository.save(
                    EventHandled(
                        eventId = event.eventId,
                        eventType = event.eventType,
                        occurredAt = event.occurredAt,
                        handledAt = Instant.now()
                    )
                )
                event  // 저장 성공 → 처리 대상
            } catch (e: org.springframework.dao.DataIntegrityViolationException) {
                // PK 중복 = 이미 처리된 이벤트
                logger.debug("중복 이벤트 스킵: eventId=${event.eventId}")
                null  // 저장 실패 → 처리 제외
            }
        }

        if (savedEvents.isEmpty()) {
            logger.warn("모든 이벤트가 이미 처리됨 (${events.size}개)")
            return
        }

        // 2. 날짜별로 그룹화
        val eventsByDate = savedEvents.groupBy { event ->
            LocalDate.ofInstant(event.occurredAt, ZoneId.systemDefault())
        }

        // 3. 날짜별로 상품 점수 합산 및 Redis 업데이트
        eventsByDate.forEach { (date, dateEvents) ->
            processEventsForDate(date, dateEvents)
        }

        logger.info(
            "랭킹 배치 처리 완료: ${savedEvents.size}개 처리 " +
            "(중복 제외: ${events.size - savedEvents.size}개)"
        )
    }

    /**
     * 특정 날짜의 이벤트들을 처리
     *
     * 왜 상품별로 그룹화하는가?
     * - 동일 상품에 대한 여러 이벤트를 한 번의 Redis 연산으로 처리
     * - 예: 상품 A 조회 10회 → incrementScore(A, 1.0) 10번이 아닌 1번
     *
     * @param date 대상 날짜
     * @param events 해당 날짜의 이벤트 리스트
     */
    private fun processEventsForDate(date: LocalDate, events: List<DomainEvent>) {
        // 상품별로 점수 합산
        val scoresByProduct = mutableMapOf<Long, Double>()

        events.forEach { event ->
            when (event) {
                is ProductViewedEvent, is ProductLikedEvent, is ProductUnlikedEvent -> {
                    // 중복 코드 제거: 3가지 이벤트 모두 동일한 처리 로직
                    val score = rankingScoreCalculator.calculateScore(event)
                    val productId = when (event) {
                        is ProductViewedEvent -> event.productId
                        is ProductLikedEvent -> event.productId
                        is ProductUnlikedEvent -> event.productId
                        else -> return@forEach
                    }
                    scoresByProduct[productId] = (scoresByProduct[productId] ?: 0.0) + score
                }
                is OrderCreatedEvent -> {
                    // 주문은 여러 상품을 포함할 수 있음
                    event.orderItems.forEach { item ->
                        val score = rankingScoreCalculator.calculateOrderItemScore(item)
                        scoresByProduct[item.productId] = (scoresByProduct[item.productId] ?: 0.0) + score
                    }
                }
                else -> {
                    logger.debug("랭킹 처리 대상 아님: eventType=${event.eventType}")
                }
            }
        }

        // Redis ZSET에 배치 업데이트
        scoresByProduct.forEach { (productId, totalScore) ->
            rankingService.incrementScore(date, productId, totalScore)
        }

        logger.debug("날짜별 랭킹 처리 완료: date=$date, 상품수=${scoresByProduct.size}")
    }
}
```

### ✅ 핵심 포인트
- **멱등성 보장**: Insert First 패턴으로 Race Condition 방지 (Round 8에서 검증된 패턴)
- **PK 제약조건 활용**: DB가 원자적으로 중복을 차단하여 동시성 안전
- **배치 최적화**: 상품별로 점수를 합산 후 한 번에 Redis 업데이트
- **@Transactional**: DB 저장(event_handled)과 Redis 업데이트를 하나의 작업 단위로

---

## 2-2. RankingKafkaConsumer

### 💡 왜 별도의 Consumer를 만드는가?

이미 `BatchMetricsKafkaConsumer`가 있는데 왜 또 만드나요?

**이유 1: 관심사 분리**
- MetricsConsumer: DB에 집계 데이터 저장 (영구 저장)
- RankingConsumer: Redis에 실시간 랭킹 저장 (휘발성, TTL 2일)

**이유 2: 독립적인 장애 격리**
- RankingConsumer 장애 시 Metrics는 정상 동작
- 서로 다른 Consumer Group으로 Offset 독립 관리

**이유 3: 확장성**
- 나중에 "1시간 단위 랭킹"을 추가할 때 RankingConsumer만 수정

### 📂 파일 생성

**경로**: `apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/RankingKafkaConsumer.kt`

```kotlin
package com.loopers.interfaces.consumer

import com.fasterxml.jackson.databind.ObjectMapper
import com.loopers.application.ranking.RankingEventFacade
import com.loopers.domain.event.DomainEvent
import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.product.event.ProductViewedEvent
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.slf4j.LoggerFactory
import org.springframework.kafka.annotation.KafkaListener
import org.springframework.kafka.support.Acknowledgment
import org.springframework.stereotype.Component

/**
 * 랭킹 집계를 위한 Kafka Consumer
 *
 * Consumer 설정:
 * - Group ID: ranking-consumer-group (Metrics Consumer와 독립)
 * - Container Factory: batchKafkaListenerContainerFactory (배치 처리)
 * - Topics: catalog-events, order-events
 * - ACK Mode: Manual (처리 성공 시에만 Offset Commit)
 *
 * 왜 배치 리스너를 사용하는가?
 * - 단건 처리: 이벤트 1000개 = Redis 연산 1000번
 * - 배치 처리: 이벤트 1000개 → 상품 100개 = Redis 연산 100번
 * - 네트워크 왕복 횟수 감소 → 처리 속도 10배 향상 가능
 */
@Component
class RankingKafkaConsumer(
    private val rankingEventFacade: RankingEventFacade,
    private val objectMapper: ObjectMapper
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    @KafkaListener(
        topics = ["catalog-events", "order-events"],
        groupId = "ranking-consumer-group",  // Metrics Consumer와 다른 그룹
        containerFactory = "batchKafkaListenerContainerFactory"
    )
    fun consumeBatch(
        messages: List<ConsumerRecord<String, String>>,
        acknowledgment: Acknowledgment
    ) {
        logger.info("랭킹 배치 메시지 수신: ${messages.size}개")

        try {
            // 1. JSON 파싱
            val events = messages.map { record ->
                parseEvent(record.value())
            }

            // 2. Facade를 통한 비즈니스 로직 실행
            rankingEventFacade.handleBatchEvents(events)

            // 3. Offset Commit (성공 시에만)
            acknowledgment.acknowledge()
            logger.info("랭킹 배치 처리 완료: ${events.size}개")

        } catch (e: Exception) {
            logger.error("랭킹 배치 처리 실패: ${messages.size}개, error=${e.message}", e)
            // ACK하지 않음 → 다음번에 재처리됨 (멱등성 보장으로 안전)
        }
    }

    /**
     * JSON 메시지를 DomainEvent 객체로 파싱
     *
     * 왜 eventType 필드를 먼저 읽는가?
     * - Jackson은 다형성 역직렬화를 위해 타입 정보 필요
     * - eventType을 읽고 적절한 클래스로 변환
     *
     * @param message JSON 문자열
     * @return 파싱된 DomainEvent
     * @throws IllegalArgumentException eventType이 없거나 지원하지 않는 타입
     */
    private fun parseEvent(message: String): DomainEvent {
        val node = objectMapper.readTree(message)
        val eventType = node["eventType"]?.asText()
            ?: throw IllegalArgumentException("Missing eventType in message: $message")

        return when (eventType) {
            "PRODUCT_VIEWED" -> objectMapper.readValue(message, ProductViewedEvent::class.java)
            "PRODUCT_LIKED" -> objectMapper.readValue(message, ProductLikedEvent::class.java)
            "PRODUCT_UNLIKED" -> objectMapper.readValue(message, ProductUnlikedEvent::class.java)
            "ORDER_CREATED" -> objectMapper.readValue(message, OrderCreatedEvent::class.java)
            // 랭킹과 무관한 이벤트는 무시 (예: STOCK_DECREASED, PAYMENT_COMPLETED)
            else -> {
                logger.debug("랭킹 처리 대상 아님: eventType=$eventType")
                throw IllegalArgumentException("Unsupported event type for ranking: $eventType")
            }
        }
    }
}
```

### ✅ 핵심 포인트
- **독립적인 Consumer Group**: `ranking-consumer-group`으로 Metrics와 분리
- **Manual ACK**: 처리 성공 시에만 Offset Commit (실패 시 재처리)
- **에러 처리**: 예외 발생 시 ACK하지 않아 재처리 (멱등성 보장으로 안전)

---

## 🔍 동작 흐름 시각화

```
[commerce-api]
    ↓ 이벤트 발행
[Kafka Topic: catalog-events]
    ↓ 동시 소비 (독립적)
    ├─→ [MetricsConsumer] → DB (product_metrics 테이블)
    └─→ [RankingConsumer] → Redis (ranking:all:20251222 ZSET)

RankingConsumer 상세:
1. 배치 메시지 수신 (max 100개)
2. parseEvent() → DomainEvent 객체 변환
3. RankingEventFacade.handleBatchEvents()
   ├─ 멱등성 체크 (event_handled)
   ├─ 날짜별 그룹화
   ├─ 상품별 점수 합산
   └─ RankingService.incrementScore()
       └─ Redis ZINCRBY
4. event_handled 테이블 저장
5. ACK (Offset Commit)
```

---

## 🧪 Step 2 검증 방법

### 1. 컴파일 확인
```bash
cd apps/commerce-streamer
./gradlew compileKotlin
```

### 2. Redis에 랭킹 데이터 확인
```bash
# Redis CLI 접속
docker exec -it redis-master redis-cli

# 오늘 날짜 랭킹 확인
> ZREVRANGE ranking:all:20251222 0 9 WITHSCORES
1) "product:101"
2) "10.5"
3) "product:202"
4) "8.2"
...

# 특정 상품 순위 확인
> ZREVRANK ranking:all:20251222 product:101
(integer) 0  # 0위 = 1등

# 특정 상품 점수 확인
> ZSCORE ranking:all:20251222 product:101
"10.5"

# TTL 확인 (2일 = 172800초)
> TTL ranking:all:20251222
(integer) 172755
```

### 3. 멱등성 테스트
```sql
-- 같은 이벤트 2번 발행 → Redis 점수는 1번만 증가해야 함
SELECT * FROM event_handled
WHERE event_type = 'PRODUCT_VIEWED'
ORDER BY handled_at DESC
LIMIT 10;
```

---

## 🎯 Step 2 완료 체크리스트

- [ ] `RankingEventFacade.kt` 파일 생성 및 컴파일 확인
- [ ] `RankingKafkaConsumer.kt` 파일 생성 및 컴파일 확인
- [ ] Kafka Consumer가 메시지를 정상적으로 소비하는지 로그 확인
- [ ] Redis에 랭킹 데이터가 적재되는지 확인
- [ ] 멱등성이 보장되는지 확인 (같은 이벤트 재처리 시 점수 중복 증가 없음)

---

## 📚 다음 단계 미리보기

**Step 3**에서는:
- Ranking API 구현 (GET /api/v1/rankings)
- 상품 정보 Aggregation (ID만이 아닌 전체 정보)
- 페이지네이션 처리

Step 2 완료하셨으면 다음 단계로 넘어가겠습니다! 👍
