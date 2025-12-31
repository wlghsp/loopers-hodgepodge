# 🧪 Round 9 랭킹 시스템 테스트 코드 작성 가이드

> **목표**: 구현한 랭킹 시스템의 각 레이어별 테스트 코드 작성 방법을 제시합니다.

---

## 📋 목차

1. [테스트 전략 개요](#테스트-전략-개요)
2. [프로젝트 테스트 스타일 가이드](#프로젝트-테스트-스타일-가이드)
3. [Layer별 테스트 가이드](#layer별-테스트-가이드)
   - [Domain Layer: RankingService](#1-domain-layer-rankingservice)
   - [Domain Layer: RankingScoreCalculator](#2-domain-layer-rankingscorecalculator)
   - [Application Layer: RankingEventFacade](#3-application-layer-rankingeventfacade)
   - [Application Layer: RankingFacade](#4-application-layer-rankingfacade)
   - [Interface Layer: RankingKafkaConsumer](#5-interface-layer-rankingkafkaconsumer)
   - [Interface Layer: RankingV1Controller](#6-interface-layer-rankingv1controller)
4. [통합 테스트](#7-통합-테스트-e2e)
5. [테스트 유틸리티](#8-테스트-유틸리티)

---

## 🎯 테스트 전략 개요

### 테스트 피라미드

```
        /\
       /E2E\          ← 소수 (느리지만 전체 흐름 검증)
      /------\
     /Integration\   ← 중간 (주요 시나리오 검증)
    /------------\
   /  Unit Tests  \  ← 다수 (빠르고 정확한 검증)
  /----------------\
```

### 각 레이어별 테스트 목표

| 레이어 | 테스트 목표 | 주요 검증 사항 |
|--------|------------|--------------|
| **Domain** | 비즈니스 로직의 정확성 | Redis 연산, 점수 계산 |
| **Application** | 오케스트레이션 로직 | 멱등성, 트랜잭션, 그룹화 |
| **Interface** | 외부 연동 | Kafka Consumer, API 입출력 |
| **Integration** | 전체 흐름 | 이벤트 발행 → 랭킹 적재 → 조회 |

---

## 📐 프로젝트 테스트 스타일 가이드

### 1. 테스트 네이밍 규칙

- **한글 DisplayName 사용** (필수)
- **메서드명은 영문 camelCase**
- **given-when-then 주석 사용** (소문자)

```kotlin
@DisplayName("점수 증가 - 신규 상품")
@Test
fun incrementScoreForNewProduct() {
    // given
    val date = LocalDate.of(2025, 12, 25)

    // when
    rankingService.incrementScore(date, 101L, 10.0)

    // then
    assertThat(score).isEqualTo(10.0)
}
```

### 2. 테스트 어노테이션 사용

```kotlin
@SpringBootTest  // 통합 테스트
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])  // 스케줄러 비활성화
class RankingFacadeIntegrationTest @Autowired constructor(
    private val rankingFacade: RankingFacade,
    private val databaseCleanUp: DatabaseCleanUp
) {
    @MockBean
    private lateinit var kafkaTemplate: KafkaTemplate<String, String>  // Kafka 모킹

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()  // 테스트 격리
    }
}
```

### 3. Assertion 스타일

```kotlin
// ✅ AssertJ 사용 (프로젝트 표준)
assertThat(result.rank).isEqualTo(1)
assertThat(result.score).isCloseTo(10.5, within(0.01))

// ✅ assertAll 사용 (여러 검증)
assertAll(
    { assertThat(result.rank).isEqualTo(1) },
    { assertThat(result.product.id).isEqualTo(101L) },
    { assertThat(result.score).isGreaterThan(0.0) }
)
```

### 4. Mock 사용 규칙

```kotlin
// ✅ MockK 사용 (Kotlin 친화적)
private lateinit var productMetricsRepository: ProductMetricsRepository
private lateinit var productMetricsService: ProductMetricsService

@BeforeEach
fun setUp() {
    productMetricsRepository = mockk(relaxed = true)
    productMetricsService = ProductMetricsService(productMetricsRepository)
}

// Mock 동작 정의
every { productMetricsRepository.findByProductId(productId) } returns metrics
every { productMetricsRepository.save(any()) } answers { firstArg() }

// 검증
verify(exactly = 1) { productMetricsRepository.save(metrics) }
```

### 5. Redis TestContainer 설정 (이미 구현됨)

```kotlin
// ✅ modules/redis/src/testFixtures 사용
@SpringBootTest
@Import(RedisTestContainersConfig::class)  // Redis 자동 설정
class RankingServiceTest @Autowired constructor(
    private val rankingService: RankingService,
    private val redisTemplate: RedisTemplate<String, String>
) {
    @AfterEach
    fun tearDown() {
        // Redis 데이터 초기화
        redisTemplate.connectionFactory?.connection?.serverCommands()?.flushAll()
    }
}
```

---

## 🧪 Layer별 테스트 가이드

---

## 1. Domain Layer: RankingService

### 📌 테스트 대상

- `RankingService.kt` (modules/redis)
- Redis ZSET 연산의 정확성 검증

### 테스트 파일 위치

```
modules/redis/src/test/kotlin/com/loopers/domain/ranking/RankingServiceTest.kt
```

### 테스트 클래스 구조

```kotlin
package com.loopers.domain.ranking

import com.loopers.testcontainers.RedisTestContainersConfig
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.data.redis.core.RedisTemplate
import java.time.LocalDate
import java.util.concurrent.TimeUnit

@SpringBootTest
@Import(RedisTestContainersConfig::class)
@DisplayName("RankingService 테스트")
class RankingServiceTest @Autowired constructor(
    private val rankingService: RankingService,
    private val redisTemplate: RedisTemplate<String, String>
) {

    @AfterEach
    fun tearDown() {
        redisTemplate.connectionFactory?.connection?.serverCommands()?.flushAll()
    }

    @Nested
    @DisplayName("점수 증가")
    inner class IncrementScore {

        @DisplayName("신규 상품의 점수를 증가시킬 수 있다")
        @Test
        fun incrementScoreForNewProduct() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            val productId = 101L
            val score = 10.0

            // when
            rankingService.incrementScore(date, productId, score)

            // then
            val actualScore = rankingService.getProductScore(date, productId)
            assertThat(actualScore).isEqualTo(score)
        }

        @DisplayName("기존 상품의 점수에 누적할 수 있다")
        @Test
        fun incrementScoreForExistingProduct() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            val productId = 101L

            // when
            rankingService.incrementScore(date, productId, 5.0)
            rankingService.incrementScore(date, productId, 3.0)

            // then
            val actualScore = rankingService.getProductScore(date, productId)
            assertThat(actualScore).isEqualTo(8.0)
        }

        @DisplayName("음수 점수로 점수를 감소시킬 수 있다 (좋아요 취소)")
        @Test
        fun decrementScoreWithNegativeValue() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            val productId = 101L
            rankingService.incrementScore(date, productId, 10.0)

            // when (음수 점수로 감소)
            rankingService.incrementScore(date, productId, -2.0)

            // then
            val actualScore = rankingService.getProductScore(date, productId)
            assertThat(actualScore).isEqualTo(8.0)
        }
    }

    @Nested
    @DisplayName("순위 조회")
    inner class GetProductRank {

        @DisplayName("점수가 높은 순서대로 순위가 매겨진다")
        @Test
        fun rankOrderedByScoreDescending() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            rankingService.incrementScore(date, 101L, 10.0)  // 3등
            rankingService.incrementScore(date, 102L, 50.0)  // 1등
            rankingService.incrementScore(date, 103L, 30.0)  // 2등

            // when
            val rank101 = rankingService.getProductRank(date, 101L)
            val rank102 = rankingService.getProductRank(date, 102L)
            val rank103 = rankingService.getProductRank(date, 103L)

            // then
            assertAll(
                { assertThat(rank102).isEqualTo(0L) },  // 0-based: 0 = 1등
                { assertThat(rank103).isEqualTo(1L) },  // 1 = 2등
                { assertThat(rank101).isEqualTo(2L) }   // 2 = 3등
            )
        }

        @DisplayName("존재하지 않는 상품의 순위는 null을 반환한다")
        @Test
        fun returnNullForNonExistentProduct() {
            // given
            val date = LocalDate.of(2025, 12, 25)

            // when
            val rank = rankingService.getProductRank(date, 999L)

            // then
            assertThat(rank).isNull()
        }
    }

    @Nested
    @DisplayName("페이지네이션")
    inner class GetProductsInRange {

        @DisplayName("첫 페이지(Top 20)를 조회할 수 있다")
        @Test
        fun getFirstPage() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            (1L..50L).forEach { productId ->
                rankingService.incrementScore(date, productId, productId.toDouble())
            }

            // when (0-based: 0~19 = Top 20)
            val top20 = rankingService.getProductsInRange(date, 0, 19)

            // then
            assertAll(
                { assertThat(top20).hasSize(20) },
                { assertThat(top20.first().first).isEqualTo(50L) },  // 최고 점수
                { assertThat(top20.last().first).isEqualTo(31L) }    // 20번째
            )
        }

        @DisplayName("두 번째 페이지를 조회할 수 있다")
        @Test
        fun getSecondPage() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            (1L..50L).forEach { productId ->
                rankingService.incrementScore(date, productId, productId.toDouble())
            }

            // when (0-based: 20~39 = 21등~40등)
            val secondPage = rankingService.getProductsInRange(date, 20, 39)

            // then
            assertAll(
                { assertThat(secondPage).hasSize(20) },
                { assertThat(secondPage.first().first).isEqualTo(30L) },  // 21등
                { assertThat(secondPage.last().first).isEqualTo(11L) }    // 40등
            )
        }

        @DisplayName("빈 페이지를 요청하면 빈 리스트를 반환한다")
        @Test
        fun returnEmptyListForEmptyPage() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            (1L..10L).forEach { productId ->
                rankingService.incrementScore(date, productId, productId.toDouble())
            }

            // when (20~39 범위 요청, 하지만 10개만 있음)
            val result = rankingService.getProductsInRange(date, 20, 39)

            // then
            assertThat(result).isEmpty()
        }
    }

    @Nested
    @DisplayName("TTL 관리")
    inner class TtlManagement {

        @DisplayName("키 생성 시 2일 TTL이 자동으로 설정된다")
        @Test
        fun autoSetTtlOnKeyCreation() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            val productId = 101L
            val key = "ranking:all:20251225"

            // when
            rankingService.incrementScore(date, productId, 10.0)

            // then
            val ttl = redisTemplate.getExpire(key, TimeUnit.SECONDS)
            assertAll(
                { assertThat(ttl).isGreaterThan(0) },  // TTL 설정됨
                { assertThat(ttl).isLessThanOrEqualTo(2 * 24 * 60 * 60) }  // 2일 이하
            )
        }

        @DisplayName("기존 키에 점수 추가 시 TTL이 재설정되지 않는다")
        @Test
        fun doNotResetTtlOnUpdate() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            val key = "ranking:all:20251225"

            rankingService.incrementScore(date, 101L, 10.0)
            val ttlBefore = redisTemplate.getExpire(key, TimeUnit.SECONDS)

            Thread.sleep(1000) // 1초 대기

            // when
            rankingService.incrementScore(date, 102L, 20.0)

            // then
            val ttlAfter = redisTemplate.getExpire(key, TimeUnit.SECONDS)
            assertThat(ttlAfter).isLessThan(ttlBefore!!)  // TTL은 감소만 함 (재설정 안 됨)
        }
    }

    @Nested
    @DisplayName("랭킹 사이즈 조회")
    inner class GetRankingSize {

        @DisplayName("랭킹에 포함된 상품 수를 조회할 수 있다")
        @Test
        fun getRankingSize() {
            // given
            val date = LocalDate.of(2025, 12, 25)
            (1L..50L).forEach { productId ->
                rankingService.incrementScore(date, productId, 10.0)
            }

            // when
            val size = rankingService.getRankingSize(date)

            // then
            assertThat(size).isEqualTo(50L)
        }

        @DisplayName("빈 랭킹의 크기는 0을 반환한다")
        @Test
        fun returnZeroForEmptyRanking() {
            // given
            val date = LocalDate.of(2025, 12, 25)

            // when
            val size = rankingService.getRankingSize(date)

            // then
            assertThat(size).isEqualTo(0L)
        }
    }
}
```

---

## 2. Domain Layer: RankingScoreCalculator

### 📌 테스트 대상

- `RankingScoreCalculator.kt`
- 점수 계산 로직의 정확성 검증

### 테스트 파일 위치

```
apps/commerce-streamer/src/test/kotlin/com/loopers/domain/ranking/RankingScoreCalculatorTest.kt
```

### 테스트 코드

```kotlin
package com.loopers.domain.ranking

import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.order.event.OrderItem
import com.loopers.domain.product.event.ProductViewedEvent
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.within
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import java.time.Instant

@SpringBootTest
@DisplayName("RankingScoreCalculator 테스트")
class RankingScoreCalculatorTest @Autowired constructor(
    private val calculator: RankingScoreCalculator
) {

    @Nested
    @DisplayName("이벤트별 점수 계산")
    inner class CalculateScoreByEventType {

        @DisplayName("상품 조회 이벤트는 0.1점을 반환한다")
        @Test
        fun calculateScoreForProductViewed() {
            // given
            val event = ProductViewedEvent(
                aggregateId = 101L,
                productId = 101L,
                memberId = "user1",
                viewedAt = Instant.now()
            )

            // when
            val score = calculator.calculateScore(event)

            // then
            assertThat(score).isEqualTo(0.1)
        }

        @DisplayName("좋아요 이벤트는 0.2점을 반환한다")
        @Test
        fun calculateScoreForProductLiked() {
            // given
            val event = ProductLikedEvent(
                aggregateId = 101L,
                productId = 101L,
                memberId = "user1",
                likedAt = Instant.now()
            )

            // when
            val score = calculator.calculateScore(event)

            // then
            assertThat(score).isEqualTo(0.2)
        }

        @DisplayName("좋아요 취소 이벤트는 -0.2점을 반환한다")
        @Test
        fun calculateScoreForProductUnliked() {
            // given
            val event = ProductUnlikedEvent(
                aggregateId = 101L,
                productId = 101L,
                memberId = "user1",
                unlikedAt = Instant.now()
            )

            // when
            val score = calculator.calculateScore(event)

            // then
            assertThat(score).isEqualTo(-0.2)
        }
    }

    @Nested
    @DisplayName("주문 점수 계산 (로그 정규화)")
    inner class CalculateOrderItemScore {

        @DisplayName("주문 점수는 로그 정규화가 적용된다")
        @Test
        fun applyLogNormalization() {
            // given
            val orderItem = OrderItem(
                productId = 101L,
                quantity = 2,
                price = 100_000L
            )

            // when
            val score = calculator.calculateOrderItemScore(orderItem)

            // then
            // 기대값: 0.6 * ln(1 + 100,000 * 2) = 0.6 * ln(200,001) ≈ 7.33
            assertThat(score).isCloseTo(7.33, within(0.01))
        }

        @DisplayName("고가 상품과 저가 상품의 점수 차이가 로그 정규화로 압축된다")
        @Test
        fun compressScoreDifferenceWithLogNormalization() {
            // given
            val highPriceItem = OrderItem(productId = 101L, quantity = 1, price = 1_000_000L)
            val lowPriceItem = OrderItem(productId = 102L, quantity = 1, price = 10_000L)

            // when
            val highScore = calculator.calculateOrderItemScore(highPriceItem)
            val lowScore = calculator.calculateOrderItemScore(lowPriceItem)

            // then
            // 가격 100배 차이가 점수는 2배 이하로 압축
            assertAll(
                { assertThat(highScore).isGreaterThan(lowScore) },
                { assertThat(highScore / lowScore).isLessThan(2.0) }
            )
        }

        @DisplayName("수량이 많을수록 점수가 증가한다")
        @Test
        fun scoreIncreasesWithQuantity() {
            // given
            val item1 = OrderItem(productId = 101L, quantity = 1, price = 10_000L)
            val item5 = OrderItem(productId = 101L, quantity = 5, price = 10_000L)

            // when
            val score1 = calculator.calculateOrderItemScore(item1)
            val score5 = calculator.calculateOrderItemScore(item5)

            // then
            assertThat(score5).isGreaterThan(score1)
        }

        @DisplayName("수량이 0이면 점수는 0이다")
        @Test
        fun returnZeroForZeroQuantity() {
            // given
            val item = OrderItem(productId = 101L, quantity = 0, price = 10_000L)

            // when
            val score = calculator.calculateOrderItemScore(item)

            // then
            assertThat(score).isEqualTo(0.0)
        }
    }
}
```

---

## 3. Application Layer: RankingEventFacade

### 📌 테스트 대상

- `RankingEventFacade.kt`
- 멱등성, 트랜잭션, 그룹화 로직 검증

### 테스트 파일 위치

```
apps/commerce-streamer/src/test/kotlin/com/loopers/application/facade/RankingEventFacadeTest.kt
```

### 테스트 코드

```kotlin
package com.loopers.application.facade

import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.order.event.OrderItem
import com.loopers.domain.product.event.ProductViewedEvent
import com.loopers.domain.ranking.RankingService
import com.loopers.infrastructure.event.EventHandledRepository
import com.loopers.testcontainers.RedisTestContainersConfig
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.test.context.TestPropertySource
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

@SpringBootTest
@Import(RedisTestContainersConfig::class)
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("RankingEventFacade 테스트")
class RankingEventFacadeTest @Autowired constructor(
    private val rankingEventFacade: RankingEventFacade,
    private val rankingService: RankingService,
    private val eventHandledRepository: EventHandledRepository,
    private val databaseCleanUp: DatabaseCleanUp
) {

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @Nested
    @DisplayName("멱등성 보장 (Insert First 패턴)")
    inner class IdempotencyGuarantee {

        @DisplayName("동일 이벤트 중복 처리 시 점수는 한 번만 증가한다")
        @Test
        fun handleDuplicateEventOnlyOnce() {
            // given
            val event = ProductViewedEvent(
                aggregateId = 101L,
                productId = 101L,
                memberId = "user1",
                viewedAt = Instant.now()
            )
            val date = LocalDate.now()

            // when (동일 이벤트 2번 처리)
            rankingEventFacade.handleBatchEvents(listOf(event))
            rankingEventFacade.handleBatchEvents(listOf(event))  // 중복

            // then
            val score = rankingService.getProductScore(date, 101L)
            val handledCount = eventHandledRepository.count()

            assertAll(
                { assertThat(score).isEqualTo(0.1) },  // 한 번만 증가
                { assertThat(handledCount).isEqualTo(1) }  // 한 번만 저장
            )
        }

        @DisplayName("PK 충돌 시 중복 이벤트를 스킵한다")
        @Test
        fun skipDuplicateEventOnPkConflict() {
            // given
            val event1 = ProductViewedEvent(
                aggregateId = 101L,  // 같은 eventId
                productId = 101L,
                memberId = "user1",
                viewedAt = Instant.now()
            )
            val event2 = ProductViewedEvent(
                aggregateId = 101L,  // 같은 eventId
                productId = 101L,
                memberId = "user2",
                viewedAt = Instant.now()
            )

            // when
            rankingEventFacade.handleBatchEvents(listOf(event1, event2))

            // then
            val handledCount = eventHandledRepository.count()
            assertThat(handledCount).isEqualTo(1)  // event1만 처리
        }
    }

    @Nested
    @DisplayName("배치 그룹화")
    inner class BatchGrouping {

        @DisplayName("다른 날짜의 이벤트는 분리하여 처리한다")
        @Test
        fun groupEventsByDate() {
            // given
            val today = Instant.now()
            val yesterday = today.minus(1, ChronoUnit.DAYS)

            val event1 = ProductViewedEvent(
                aggregateId = 101L,
                productId = 101L,
                memberId = "user1",
                viewedAt = today
            )
            val event2 = ProductViewedEvent(
                aggregateId = 102L,
                productId = 101L,
                memberId = "user2",
                viewedAt = yesterday
            )

            // when
            rankingEventFacade.handleBatchEvents(listOf(event1, event2))

            // then
            val todayDate = LocalDate.ofInstant(today, ZoneId.systemDefault())
            val yesterdayDate = LocalDate.ofInstant(yesterday, ZoneId.systemDefault())

            val todayScore = rankingService.getProductScore(todayDate, 101L)
            val yesterdayScore = rankingService.getProductScore(yesterdayDate, 101L)

            assertAll(
                { assertThat(todayScore).isEqualTo(0.1) },
                { assertThat(yesterdayScore).isEqualTo(0.1) }
            )
        }

        @DisplayName("같은 상품의 점수를 합산하여 처리한다")
        @Test
        fun aggregateScoresBySameProduct() {
            // given
            val now = Instant.now()
            val events = listOf(
                ProductViewedEvent(aggregateId = 1L, productId = 101L, memberId = "user1", viewedAt = now),
                ProductViewedEvent(aggregateId = 2L, productId = 101L, memberId = "user2", viewedAt = now),
                ProductViewedEvent(aggregateId = 3L, productId = 101L, memberId = "user3", viewedAt = now)
            )

            // when
            rankingEventFacade.handleBatchEvents(events)

            // then
            val date = LocalDate.now()
            val score = rankingService.getProductScore(date, 101L)
            assertThat(score).isEqualTo(0.3)  // 0.1 * 3
        }
    }

    @Nested
    @DisplayName("주문 이벤트 처리")
    inner class OrderEventProcessing {

        @DisplayName("주문 이벤트는 여러 상품의 점수를 증가시킨다")
        @Test
        fun increaseScoresForMultipleProducts() {
            // given
            val orderEvent = OrderCreatedEvent(
                aggregateId = 1L,
                orderId = 1L,
                memberId = "user1",
                orderItems = listOf(
                    OrderItem(productId = 101L, quantity = 1, price = 10_000L),
                    OrderItem(productId = 102L, quantity = 2, price = 20_000L)
                ),
                createdAt = Instant.now()
            )

            // when
            rankingEventFacade.handleBatchEvents(listOf(orderEvent))

            // then
            val date = LocalDate.now()
            val score101 = rankingService.getProductScore(date, 101L)
            val score102 = rankingService.getProductScore(date, 102L)

            assertAll(
                { assertThat(score101).isGreaterThan(0.0) },
                { assertThat(score102).isGreaterThan(0.0) }
            )
        }
    }

    @Nested
    @DisplayName("빈 이벤트 처리")
    inner class EmptyEventHandling {

        @DisplayName("빈 이벤트 리스트는 아무 작업도 하지 않는다")
        @Test
        fun doNothingForEmptyEventList() {
            // given
            val emptyEvents = emptyList<ProductViewedEvent>()

            // when
            rankingEventFacade.handleBatchEvents(emptyEvents)

            // then
            val handledCount = eventHandledRepository.count()
            assertThat(handledCount).isEqualTo(0)
        }
    }
}
```

---

## 4. Application Layer: RankingFacade

### 📌 테스트 대상

- `RankingFacade.kt`
- 랭킹 조회 + 상품 정보 Aggregation

### 테스트 파일 위치

```
apps/commerce-api/src/test/kotlin/com/loopers/application/ranking/RankingFacadeIntegrationTest.kt
```

### 테스트 코드

```kotlin
package com.loopers.application.ranking

import com.loopers.domain.brand.Brand
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.ranking.RankingService
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
import com.loopers.testcontainers.RedisTestContainersConfig
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.context.annotation.Import
import org.springframework.data.domain.PageRequest
import org.springframework.kafka.core.KafkaTemplate
import org.springframework.test.context.TestPropertySource
import java.time.LocalDate

@SpringBootTest
@Import(RedisTestContainersConfig::class)
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("RankingFacade 통합 테스트")
class RankingFacadeIntegrationTest @Autowired constructor(
    private val rankingFacade: RankingFacade,
    private val rankingService: RankingService,
    private val productJpaRepository: ProductJpaRepository,
    private val brandJpaRepository: BrandJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp
) {

    @MockBean
    private lateinit var kafkaTemplate: KafkaTemplate<String, String>

    private lateinit var product1: Product
    private lateinit var product2: Product

    @BeforeEach
    fun setUp() {
        val brand = brandJpaRepository.save(Brand("테스트브랜드", "설명"))
        product1 = productJpaRepository.save(
            Product("상품1", "설명1", Money.of(10000L), Stock.of(100), brand.id)
        )
        product2 = productJpaRepository.save(
            Product("상품2", "설명2", Money.of(20000L), Stock.of(50), brand.id)
        )
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @Nested
    @DisplayName("랭킹 조회")
    inner class GetRankings {

        @DisplayName("랭킹 조회 시 상품 정보가 포함된다")
        @Test
        fun includeProductInfo() {
            // given
            val date = LocalDate.now()
            rankingService.incrementScore(date, product1.id, 100.0)
            rankingService.incrementScore(date, product2.id, 50.0)

            val pageable = PageRequest.of(0, 20)

            // when
            val result = rankingFacade.getRankings(null, pageable)

            // then
            assertAll(
                { assertThat(result.content).hasSize(2) },
                { assertThat(result.content[0].rank).isEqualTo(1) },
                { assertThat(result.content[0].product.id).isEqualTo(product1.id) },
                { assertThat(result.content[0].product.name).isEqualTo("상품1") },
                { assertThat(result.content[1].rank).isEqualTo(2) },
                { assertThat(result.content[1].product.id).isEqualTo(product2.id) }
            )
        }

        @DisplayName("삭제된 상품은 랭킹에서 제외된다")
        @Test
        fun excludeDeletedProducts() {
            // given
            val date = LocalDate.now()
            rankingService.incrementScore(date, product1.id, 100.0)
            rankingService.incrementScore(date, 999L, 50.0)  // 존재하지 않는 상품

            val pageable = PageRequest.of(0, 20)

            // when
            val result = rankingFacade.getRankings(null, pageable)

            // then
            assertAll(
                { assertThat(result.content).hasSize(1) },  // 999번 상품 제외
                { assertThat(result.content[0].product.id).isEqualTo(product1.id) }
            )
        }

        @DisplayName("빈 랭킹은 빈 페이지를 반환한다")
        @Test
        fun returnEmptyPageForEmptyRanking() {
            // given
            val pageable = PageRequest.of(0, 20)

            // when
            val result = rankingFacade.getRankings(null, pageable)

            // then
            assertThat(result.content).isEmpty()
        }
    }

    @Nested
    @DisplayName("특정 상품 랭킹 조회")
    inner class GetProductRank {

        @DisplayName("순위권 내 상품의 랭킹 정보를 조회할 수 있다")
        @Test
        fun getProductRankWithinRange() {
            // given
            val date = LocalDate.now()
            rankingService.incrementScore(date, product1.id, 100.0)
            rankingService.incrementScore(date, product2.id, 50.0)

            // when
            val result = rankingFacade.getProductRank(product2.id, null)

            // then
            assertAll(
                { assertThat(result).isNotNull },
                { assertThat(result!!.rank).isEqualTo(2) },
                { assertThat(result.product.id).isEqualTo(product2.id) },
                { assertThat(result.score).isEqualTo(50.0) }
            )
        }

        @DisplayName("순위권 밖 상품은 null을 반환한다")
        @Test
        fun returnNullForOutOfRangeProduct() {
            // given
            val date = LocalDate.now()

            // when
            val result = rankingFacade.getProductRank(999L, null)

            // then
            assertThat(result).isNull()
        }
    }
}
```

---

## 5. Interface Layer: RankingKafkaConsumer

### 📌 테스트 대상

- `RankingKafkaConsumer.kt`
- Kafka 메시지 파싱 및 Consumer 동작

### 테스트 파일 위치

```
apps/commerce-streamer/src/test/kotlin/com/loopers/interfaces/consumer/RankingKafkaConsumerTest.kt
```

### 테스트 코드

```kotlin
package com.loopers.interfaces.consumer

import com.loopers.domain.ranking.RankingService
import com.loopers.testcontainers.RedisTestContainersConfig
import org.assertj.core.api.Assertions.assertThat
import org.awaitility.Awaitility.await
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.kafka.core.KafkaTemplate
import org.springframework.kafka.test.context.EmbeddedKafka
import org.springframework.test.context.TestPropertySource
import java.time.LocalDate
import java.util.concurrent.TimeUnit

@SpringBootTest
@Import(RedisTestContainersConfig::class)
@EmbeddedKafka(
    partitions = 1,
    topics = ["catalog-events", "order-events"],
    brokerProperties = ["listeners=PLAINTEXT://localhost:9092"]
)
@TestPropertySource(properties = [
    "spring.task.scheduling.enabled=false",
    "spring.kafka.bootstrap-servers=\${spring.embedded.kafka.brokers}"
])
@DisplayName("RankingKafkaConsumer 테스트")
class RankingKafkaConsumerTest @Autowired constructor(
    private val kafkaTemplate: KafkaTemplate<String, String>,
    private val rankingService: RankingService
) {

    @Nested
    @DisplayName("메시지 소비 및 파싱")
    inner class MessageConsumption {

        @DisplayName("ProductViewedEvent 메시지를 소비하고 처리한다")
        @Test
        fun consumeProductViewedEvent() {
            // given
            val event = """
                {
                    "eventId": "test-event-1",
                    "eventType": "PRODUCT_VIEWED",
                    "aggregateId": 101,
                    "productId": 101,
                    "memberId": "user1",
                    "occurredAt": "2025-12-25T10:00:00Z"
                }
            """.trimIndent()

            // when
            kafkaTemplate.send("catalog-events", event).get()

            // then (Consumer 처리 대기)
            await().atMost(5, TimeUnit.SECONDS).untilAsserted {
                val score = rankingService.getProductScore(LocalDate.now(), 101L)
                assertThat(score).isEqualTo(0.1)
            }
        }

        @DisplayName("배치로 여러 메시지를 처리한다")
        @Test
        fun consumeBatchMessages() {
            // given
            val events = (1..10).map { id ->
                """
                {
                    "eventId": "test-event-$id",
                    "eventType": "PRODUCT_VIEWED",
                    "aggregateId": $id,
                    "productId": 101,
                    "memberId": "user$id",
                    "occurredAt": "2025-12-25T10:00:00Z"
                }
                """.trimIndent()
            }

            // when
            events.forEach { kafkaTemplate.send("catalog-events", it).get() }

            // then
            await().atMost(10, TimeUnit.SECONDS).untilAsserted {
                val score = rankingService.getProductScore(LocalDate.now(), 101L)
                assertThat(score).isEqualTo(1.0)  // 0.1 * 10
            }
        }

        @DisplayName("OrderCreatedEvent 메시지를 소비하고 처리한다")
        @Test
        fun consumeOrderCreatedEvent() {
            // given
            val event = """
                {
                    "eventId": "order-event-1",
                    "eventType": "ORDER_CREATED",
                    "aggregateId": 1,
                    "orderId": 1,
                    "memberId": "user1",
                    "orderItems": [
                        {
                            "productId": 101,
                            "quantity": 2,
                            "price": 100000
                        }
                    ],
                    "occurredAt": "2025-12-25T10:00:00Z"
                }
            """.trimIndent()

            // when
            kafkaTemplate.send("order-events", event).get()

            // then
            await().atMost(5, TimeUnit.SECONDS).untilAsserted {
                val score = rankingService.getProductScore(LocalDate.now(), 101L)
                assertThat(score).isGreaterThan(0.0)
            }
        }
    }
}
```

---

## 6. Interface Layer: RankingV1Controller

### 📌 테스트 대상

- `RankingV1Controller.kt`
- API 입출력 검증

### 테스트 파일 위치

```
apps/commerce-api/src/test/kotlin/com/loopers/interfaces/api/RankingV1ApiE2ETest.kt
```

### 테스트 코드

```kotlin
package com.loopers.interfaces.api

import com.loopers.domain.brand.Brand
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.ranking.RankingService
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
import com.loopers.interfaces.api.ranking.RankingV1Dto
import com.loopers.testcontainers.RedisTestContainersConfig
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.*
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.boot.test.web.client.TestRestTemplate
import org.springframework.context.annotation.Import
import org.springframework.core.ParameterizedTypeReference
import org.springframework.data.domain.Page
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.kafka.core.KafkaTemplate
import org.springframework.test.context.TestPropertySource
import java.time.LocalDate

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(RedisTestContainersConfig::class)
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("RankingV1Api E2E 테스트")
class RankingV1ApiE2ETest @Autowired constructor(
    private val testRestTemplate: TestRestTemplate,
    private val rankingService: RankingService,
    private val productJpaRepository: ProductJpaRepository,
    private val brandJpaRepository: BrandJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp
) {

    @MockBean
    private lateinit var kafkaTemplate: KafkaTemplate<String, String>

    private lateinit var product1: Product
    private lateinit var product2: Product

    @BeforeEach
    fun setUp() {
        val brand = brandJpaRepository.save(Brand("테스트브랜드", "설명"))
        product1 = productJpaRepository.save(
            Product("상품1", "설명1", Money.of(10000L), Stock.of(100), brand.id)
        )
        product2 = productJpaRepository.save(
            Product("상품2", "설명2", Money.of(20000L), Stock.of(50), brand.id)
        )

        // 랭킹 데이터 생성
        val date = LocalDate.now()
        rankingService.incrementScore(date, product1.id, 100.0)
        rankingService.incrementScore(date, product2.id, 50.0)
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @Nested
    @DisplayName("GET /api/v1/rankings")
    inner class GetRankings {

        @DisplayName("랭킹 목록을 정상적으로 조회한다")
        @Test
        fun getRankingsSuccessfully() {
            // when
            val responseType = object : ParameterizedTypeReference<ApiResponse<Page<RankingV1Dto.RankingResponse>>>() {}
            val response = testRestTemplate.exchange(
                "/api/v1/rankings?page=0&size=20",
                HttpMethod.GET,
                null,
                responseType
            )

            // then
            assertAll(
                { assertThat(response.statusCode).isEqualTo(HttpStatus.OK) },
                { assertThat(response.body?.success).isTrue() },
                { assertThat(response.body?.data?.content).hasSize(2) },
                { assertThat(response.body?.data?.content?.get(0)?.rank).isEqualTo(1) },
                { assertThat(response.body?.data?.content?.get(0)?.product?.id).isEqualTo(product1.id) }
            )
        }

        @DisplayName("날짜를 지정하여 랭킹을 조회한다")
        @Test
        fun getRankingsByDate() {
            // given
            val dateStr = LocalDate.now().format(java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd"))

            // when
            val responseType = object : ParameterizedTypeReference<ApiResponse<Page<RankingV1Dto.RankingResponse>>>() {}
            val response = testRestTemplate.exchange(
                "/api/v1/rankings?date=$dateStr&page=0&size=20",
                HttpMethod.GET,
                null,
                responseType
            )

            // then
            assertAll(
                { assertThat(response.statusCode).isEqualTo(HttpStatus.OK) },
                { assertThat(response.body?.data?.content?.get(0)?.product?.id).isEqualTo(product1.id) }
            )
        }

        @DisplayName("존재하지 않는 날짜의 랭킹은 빈 목록을 반환한다")
        @Test
        fun returnEmptyForNonExistentDate() {
            // when
            val responseType = object : ParameterizedTypeReference<ApiResponse<Page<RankingV1Dto.RankingResponse>>>() {}
            val response = testRestTemplate.exchange(
                "/api/v1/rankings?date=20200101&page=0&size=20",
                HttpMethod.GET,
                null,
                responseType
            )

            // then
            assertAll(
                { assertThat(response.statusCode).isEqualTo(HttpStatus.OK) },
                { assertThat(response.body?.data?.content).isEmpty() }
            )
        }
    }
}
```

---

## 7. 통합 테스트 (E2E)

### 📌 테스트 시나리오

전체 흐름: 이벤트 발행 → Kafka → Consumer → Redis → API 조회

### 테스트 파일 위치

```
apps/commerce-api/src/test/kotlin/com/loopers/integration/RankingSystemE2ETest.kt
```

### 테스트 코드

```kotlin
package com.loopers.integration

import com.loopers.domain.brand.Brand
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.order.event.OrderItem
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.product.event.ProductViewedEvent
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
import com.loopers.testcontainers.RedisTestContainersConfig
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.awaitility.Awaitility.await
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.ApplicationEventPublisher
import org.springframework.context.annotation.Import
import org.springframework.kafka.test.context.EmbeddedKafka
import org.springframework.test.context.TestPropertySource
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status
import java.time.Instant
import java.util.concurrent.TimeUnit

@SpringBootTest
@AutoConfigureMockMvc
@Import(RedisTestContainersConfig::class)
@EmbeddedKafka(
    partitions = 1,
    topics = ["catalog-events", "order-events"]
)
@TestPropertySource(properties = [
    "spring.task.scheduling.enabled=false",
    "spring.kafka.bootstrap-servers=\${spring.embedded.kafka.brokers}"
])
@DisplayName("랭킹 시스템 E2E 테스트")
class RankingSystemE2ETest @Autowired constructor(
    private val mockMvc: MockMvc,
    private val eventPublisher: ApplicationEventPublisher,
    private val productJpaRepository: ProductJpaRepository,
    private val brandJpaRepository: BrandJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp
) {

    private lateinit var product: Product

    @BeforeEach
    fun setUp() {
        val brand = brandJpaRepository.save(Brand("테스트브랜드", "설명"))
        product = productJpaRepository.save(
            Product("테스트상품", "설명", Money.of(100000L), Stock.of(100), brand.id)
        )
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("E2E - 상품 조회 이벤트 발행부터 랭킹 조회까지 전체 흐름이 동작한다")
    @Test
    fun fullFlowFromProductViewToRankingQuery() {
        // given & when
        eventPublisher.publishEvent(
            ProductViewedEvent(
                aggregateId = product.id,
                productId = product.id,
                memberId = "user1",
                viewedAt = Instant.now()
            )
        )

        // then
        await().atMost(10, TimeUnit.SECONDS).untilAsserted {
            mockMvc.perform(get("/api/v1/rankings"))
                .andExpect(status().isOk)
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.content[0].product.id").value(product.id))
                .andExpect(jsonPath("$.data.content[0].rank").value(1))
        }
    }

    @DisplayName("E2E - 주문 생성 이벤트 발행부터 상품 상세 조회까지 전체 흐름이 동작한다")
    @Test
    fun fullFlowFromOrderCreationToProductDetail() {
        // given & when
        val orderEvent = OrderCreatedEvent(
            aggregateId = 1L,
            orderId = 1L,
            memberId = "user1",
            orderItems = listOf(
                OrderItem(productId = product.id, quantity = 2, price = 100_000L)
            ),
            createdAt = Instant.now()
        )

        eventPublisher.publishEvent(orderEvent)

        // then
        await().atMost(10, TimeUnit.SECONDS).untilAsserted {
            mockMvc.perform(
                get("/api/v1/products/${product.id}")
                    .header("X-USER-ID", "user1")
            )
                .andExpect(status().isOk)
                .andExpect(jsonPath("$.data.rank").isNumber)
                .andExpect(jsonPath("$.data.score").isNumber)
        }
    }

    @DisplayName("E2E - 여러 이벤트를 발행하면 점수가 누적되어 랭킹에 반영된다")
    @Test
    fun accumulateScoresFromMultipleEvents() {
        // given & when
        repeat(10) { index ->
            eventPublisher.publishEvent(
                ProductViewedEvent(
                    aggregateId = product.id + index,
                    productId = product.id,
                    memberId = "user$index",
                    viewedAt = Instant.now()
                )
            )
        }

        eventPublisher.publishEvent(
            OrderCreatedEvent(
                aggregateId = 1L,
                orderId = 1L,
                memberId = "user1",
                orderItems = listOf(
                    OrderItem(productId = product.id, quantity = 1, price = 50_000L)
                ),
                createdAt = Instant.now()
            )
        )

        // then
        await().atMost(15, TimeUnit.SECONDS).untilAsserted {
            mockMvc.perform(get("/api/v1/rankings"))
                .andExpect(status().isOk)
                .andExpect(jsonPath("$.data.content[0].product.id").value(product.id))
                .andExpect(jsonPath("$.data.content[0].score").exists())
        }
    }
}
```

---

## 8. 테스트 유틸리티

### 8.1 이미 구현된 유틸리티 활용

#### DatabaseCleanUp (modules/jpa/testFixtures)

```kotlin
// ✅ 이미 구현되어 있음
@Autowired
private lateinit var databaseCleanUp: DatabaseCleanUp

@AfterEach
fun tearDown() {
    databaseCleanUp.truncateAllTables()  // 모든 테이블 초기화
}
```

#### RedisTestContainersConfig (modules/redis/testFixtures)

```kotlin
// ✅ 이미 구현되어 있음
@SpringBootTest
@Import(RedisTestContainersConfig::class)  // Redis 자동 시작
class RankingServiceTest { ... }
```

---

## 📊 테스트 커버리지 목표

| 레이어 | 목표 커버리지 | 우선순위 |
|--------|-------------|---------|
| Domain | 90% 이상 | 최우선 (비즈니스 로직) |
| Application | 80% 이상 | 높음 (오케스트레이션) |
| Interface | 70% 이상 | 중간 (입출력 검증) |
| Integration | 주요 시나리오 | 필수 (전체 흐름) |

---

## ✅ 테스트 작성 체크리스트

### Domain Layer
- [ ] RankingService 점수 증가/감소 테스트
- [ ] RankingService 순위 조회 테스트
- [ ] RankingService 페이지네이션 테스트
- [ ] RankingService TTL 검증 테스트
- [ ] RankingScoreCalculator 이벤트별 점수 계산
- [ ] RankingScoreCalculator 로그 정규화 검증

### Application Layer
- [ ] RankingEventFacade 멱등성 테스트
- [ ] RankingEventFacade 날짜별 그룹화 테스트
- [ ] RankingEventFacade 상품별 점수 합산 테스트
- [ ] RankingFacade 랭킹 조회 + Aggregation 테스트
- [ ] RankingFacade 삭제된 상품 제외 테스트

### Interface Layer
- [ ] RankingKafkaConsumer 메시지 파싱 테스트
- [ ] RankingKafkaConsumer 배치 처리 테스트
- [ ] RankingV1Controller API 입출력 테스트

### Integration
- [ ] E2E: 상품 조회 → 랭킹 반영 → API 조회
- [ ] E2E: 주문 생성 → 랭킹 반영 → 상품 상세 조회
- [ ] E2E: 여러 이벤트 누적 처리

---

## 🎯 다음 단계

1. **Unit Tests 우선 작성** (Domain Layer부터)
2. **Integration Tests** (주요 시나리오)
3. **테스트 커버리지 측정** (Jacoco)
4. **CI/CD 파이프라인에 통합**

축하합니다! 이제 프로젝트 스타일에 맞는 체계적인 테스트 코드로 랭킹 시스템의 안정성을 보장할 수 있습니다! 🚀
