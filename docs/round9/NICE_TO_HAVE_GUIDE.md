# Round 9 Nice-To-Have 기능 구현 가이드

## 개요

이 문서는 Round 9의 Nice-To-Have 요구사항을 구현하기 위한 상세 가이드입니다.

**Nice-To-Have 요구사항:**
1. 초 실시간 (시간 단위) 랭킹 만들기
2. 콜드 스타트 문제 해결

**현재 시스템 상태:**
- ✅ 일 단위 랭킹 시스템 (키: `ranking:all:yyyyMMdd`)
- ✅ Kafka Consumer → Redis 파이프라인
- ✅ 멱등성 보장 (Insert First Pattern)
- ✅ 로그 정규화 점수 계산

---

## 1. 시간 단위 실시간 랭킹

### 1.1 현재 시스템의 한계

**현재 구조:**
```
키: ranking:all:20251225
- 하루 전체 데이터를 하나의 ZSET에 저장
- 00:00 ~ 23:59까지 모든 이벤트가 동일 키에 누적
- 오전 10시에 구매한 상품과 오후 3시에 구매한 상품이 같은 랭킹
```

**문제점:**
- 실시간성 부족: 최근 1시간의 트렌드를 파악할 수 없음
- 시간대별 분석 불가: "지금 이 순간 인기 있는 상품"을 알 수 없음

### 1.2 시간 단위 랭킹 설계

#### 핵심 전략: Time Quantization 단위 변경

**기존:** 일 단위 (`yyyyMMdd`)
**변경:** 시간 단위 (`yyyyMMddHH`)

**새로운 키 구조:**
```
ranking:all:2025122514  # 2025년 12월 25일 14시
ranking:all:2025122515  # 2025년 12월 25일 15시
ranking:all:2025122516  # 2025년 12월 25일 16시
```

#### 1.2.1 RankingKeyGenerator 수정

**파일:** `modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingKeyGenerator.kt`

**현재 코드:**
```kotlin
fun generateRankingKey(date: LocalDate): String {
    val dateString = date.format(DateTimeFormatter.BASIC_ISO_DATE)
    return "ranking:all:$dateString"
}
```

**변경 후:**
```kotlin
object RankingKeyGenerator {
    private val DAILY_FORMATTER = DateTimeFormatter.BASIC_ISO_DATE  // yyyyMMdd
    private val HOURLY_FORMATTER = DateTimeFormatter.ofPattern("yyyyMMddHH")  // yyyyMMddHH

    /**
     * 일 단위 랭킹 키 생성
     * 예: ranking:all:20251225
     */
    fun generateDailyRankingKey(date: LocalDate): String {
        return "ranking:all:${date.format(DAILY_FORMATTER)}"
    }

    /**
     * 시간 단위 랭킹 키 생성
     * 예: ranking:all:2025122514
     */
    fun generateHourlyRankingKey(dateTime: LocalDateTime): String {
        return "ranking:all:${dateTime.format(HOURLY_FORMATTER)}"
    }

    /**
     * 시간 범위의 모든 키 생성 (다중 시간대 조회용)
     * 예: 최근 3시간 = [2025122514, 2025122515, 2025122516]
     */
    fun generateHourlyRankingKeys(from: LocalDateTime, to: LocalDateTime): List<String> {
        val keys = mutableListOf<String>()
        var current = from.truncatedTo(ChronoUnit.HOURS)
        val end = to.truncatedTo(ChronoUnit.HOURS)

        while (!current.isAfter(end)) {
            keys.add(generateHourlyRankingKey(current))
            current = current.plusHours(1)
        }
        return keys
    }
}
```

**왜 두 가지 메서드를 모두 제공하는가?**
- 일 단위: 전체 일간 랭킹 (기존 요구사항 유지)
- 시간 단위: 실시간 트렌드 (Nice-To-Have)
- 유연성: API에서 시간 범위를 선택할 수 있게 함

#### 1.2.2 RankingService 수정

**파일:** `modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt`

**새로운 메서드 추가:**
```kotlin
@Service
class RankingService(
    @Qualifier("rankingRedisTemplate")
    private val redisTemplate: RedisTemplate<String, String>
) {
    // 기존 메서드 유지
    fun incrementScore(date: LocalDate, productId: Long, score: Double) {
        val key = RankingKeyGenerator.generateDailyRankingKey(date)
        // ...
    }

    // ========== 새로운 시간 단위 메서드 ==========

    /**
     * 시간 단위 점수 증가
     */
    fun incrementScoreHourly(dateTime: LocalDateTime, productId: Long, score: Double) {
        val key = RankingKeyGenerator.generateHourlyRankingKey(dateTime)

        redisTemplate.opsForZSet().incrementScore(key, productId.toString(), score)

        // TTL 설정: 48시간 (2일치 시간별 데이터 보관)
        redisTemplate.expire(key, Duration.ofHours(48))
    }

    /**
     * 시간 단위 Top N 조회
     */
    fun getTopProductsHourly(dateTime: LocalDateTime, limit: Int): List<ProductRanking> {
        val key = RankingKeyGenerator.generateHourlyRankingKey(dateTime)

        val rankings = redisTemplate.opsForZSet()
            .reverseRangeWithScores(key, 0, (limit - 1).toLong())
            ?: return emptyList()

        return rankings.mapIndexed { index, tuple ->
            ProductRanking(
                rank = index + 1,
                productId = tuple.value!!.toLong(),
                score = tuple.score!!
            )
        }
    }

    /**
     * 시간 범위 Top N 조회 (여러 시간대 집계)
     * 예: 최근 3시간 인기 상품
     */
    fun getTopProductsHourlyRange(from: LocalDateTime, to: LocalDateTime, limit: Int): List<ProductRanking> {
        val keys = RankingKeyGenerator.generateHourlyRankingKeys(from, to)

        if (keys.isEmpty()) return emptyList()

        // ZUNIONSTORE: 여러 ZSET을 합산
        val tempKey = "ranking:temp:${System.currentTimeMillis()}"
        redisTemplate.opsForZSet().unionAndStore(keys[0], keys.drop(1), tempKey)

        // TTL 설정: 임시 키는 1분 후 자동 삭제
        redisTemplate.expire(tempKey, Duration.ofMinutes(1))

        val rankings = redisTemplate.opsForZSet()
            .reverseRangeWithScores(tempKey, 0, (limit - 1).toLong())
            ?: return emptyList()

        return rankings.mapIndexed { index, tuple ->
            ProductRanking(
                rank = index + 1,
                productId = tuple.value!!.toLong(),
                score = tuple.score!!
            )
        }
    }
}
```

**핵심 기술:**
1. **ZUNIONSTORE**: 여러 시간대의 ZSET을 합산하여 "최근 N시간" 랭킹 계산
2. **임시 키 사용**: 합산 결과를 임시 키에 저장 후 1분 TTL
3. **TTL 48시간**: 2일치 시간별 데이터 보관

#### 1.2.3 RankingEventFacade 수정

**파일:** `apps/commerce-streamer/src/main/kotlin/com/loopers/application/facade/RankingEventFacade.kt`

**현재 코드 (일 단위):**
```kotlin
private fun aggregateByDate(events: List<DomainEvent>): Map<LocalDate, Map<Long, Double>> {
    return events.groupBy { it.occurredAt.toLocalDate() }
        .mapValues { (_, dateEvents) ->
            aggregateByProduct(dateEvents)
        }
}
```

**변경 후 (시간 단위 옵션 추가):**
```kotlin
@Service
class RankingEventFacade(
    private val rankingService: RankingService,
    private val rankingScoreCalculator: RankingScoreCalculator,
    @Value("\${ranking.time-unit:DAILY}") private val timeUnit: TimeUnit  // 설정값으로 제어
) {
    enum class TimeUnit {
        DAILY,   // 일 단위 (기본값)
        HOURLY   // 시간 단위
    }

    fun handleBatchEvents(events: List<DomainEvent>) {
        if (events.isEmpty()) return

        logger.info("랭킹 이벤트 배치 처리 시작: ${events.size}개")

        // 시간 단위 설정에 따라 다른 집계 로직 사용
        when (timeUnit) {
            TimeUnit.DAILY -> processDailyRanking(events)
            TimeUnit.HOURLY -> processHourlyRanking(events)
        }

        logger.info("랭킹 이벤트 배치 처리 완료")
    }

    private fun processDailyRanking(events: List<DomainEvent>) {
        val aggregated = aggregateByDate(events)

        aggregated.forEach { (date, productScores) ->
            productScores.forEach { (productId, score) ->
                rankingService.incrementScore(date, productId, score)
            }
        }
    }

    private fun processHourlyRanking(events: List<DomainEvent>) {
        val aggregated = aggregateByHour(events)

        aggregated.forEach { (dateTimeHour, productScores) ->
            productScores.forEach { (productId, score) ->
                rankingService.incrementScoreHourly(dateTimeHour, productId, score)
            }
        }
    }

    // 기존 메서드
    private fun aggregateByDate(events: List<DomainEvent>): Map<LocalDate, Map<Long, Double>> {
        return events.groupBy { it.occurredAt.toLocalDate() }
            .mapValues { (_, dateEvents) -> aggregateByProduct(dateEvents) }
    }

    // 새로운 메서드
    private fun aggregateByHour(events: List<DomainEvent>): Map<LocalDateTime, Map<Long, Double>> {
        return events.groupBy {
            it.occurredAt.truncatedTo(ChronoUnit.HOURS)  // 시간 단위로 절삭
        }.mapValues { (_, hourEvents) -> aggregateByProduct(hourEvents) }
    }

    private fun aggregateByProduct(events: List<DomainEvent>): Map<Long, Double> {
        // 기존 로직 유지
        return events.groupBy { event ->
            when (event) {
                is ProductViewedEvent -> event.productId
                is ProductLikedEvent -> event.productId
                is ProductUnlikedEvent -> event.productId
                is OrderCreatedEvent -> event.items.first().productId
                else -> throw IllegalArgumentException("Unknown event type")
            }
        }.mapValues { (_, productEvents) ->
            productEvents.sumOf { rankingScoreCalculator.calculate(it) }
        }
    }
}
```

**설정 파일 추가:**

**파일:** `apps/commerce-streamer/src/main/resources/application.yml`

```yaml
ranking:
  time-unit: HOURLY  # DAILY 또는 HOURLY

# DAILY: 기존 일 단위 랭킹 (안정성 우선)
# HOURLY: 시간 단위 실시간 랭킹 (실시간성 우선)
```

#### 1.2.4 RankingFacade 수정

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingFacade.kt`

**새로운 메서드 추가:**
```kotlin
@Service
class RankingFacade(
    private val rankingService: RankingService
) {
    // 기존 메서드 유지
    fun getTopProducts(date: LocalDate?, limit: Int): RankingV1Response {
        val targetDate = date ?: LocalDate.now()
        val rankings = rankingService.getTopProducts(targetDate, limit)
        return RankingV1Response(rankings)
    }

    // ========== 새로운 시간 단위 메서드 ==========

    /**
     * 특정 시간의 Top N 조회
     */
    fun getTopProductsHourly(dateTime: LocalDateTime?, limit: Int): RankingV1Response {
        val targetDateTime = dateTime ?: LocalDateTime.now()
        val rankings = rankingService.getTopProductsHourly(targetDateTime, limit)
        return RankingV1Response(rankings)
    }

    /**
     * 시간 범위의 Top N 조회 (최근 N시간)
     */
    fun getTopProductsRecentHours(hours: Int, limit: Int): RankingV1Response {
        val to = LocalDateTime.now()
        val from = to.minusHours(hours.toLong() - 1)  // 현재 시간 포함
        val rankings = rankingService.getTopProductsHourlyRange(from, to, limit)
        return RankingV1Response(rankings)
    }
}
```

#### 1.2.5 API 추가

**파일:** `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Controller.kt`

**새로운 엔드포인트 추가:**
```kotlin
@RestController
@RequestMapping("/api/v1")
class RankingV1Controller(
    private val rankingFacade: RankingFacade
) {
    // 기존 엔드포인트 유지
    @GetMapping("/rankings/daily")
    @Operation(summary = "일간 상위 N개 상품 랭킹 조회")
    fun getTopProducts(
        @RequestParam(required = false) date: LocalDate?,
        @RequestParam(defaultValue = "10") limit: Int
    ): ApiResponse<RankingV1Response> {
        val response = rankingFacade.getTopProducts(date, limit)
        return ApiResponse.success(response)
    }

    // ========== 새로운 엔드포인트 ==========

    /**
     * 시간 단위 랭킹 조회
     *
     * GET /api/v1/rankings/hourly?dateTime=2025-12-25T14:00:00&limit=10
     * GET /api/v1/rankings/hourly?limit=10  (dateTime 생략 시 현재 시간)
     */
    @GetMapping("/rankings/hourly")
    @Operation(summary = "시간 단위 상위 N개 상품 랭킹 조회")
    fun getTopProductsHourly(
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) dateTime: LocalDateTime?,
        @RequestParam(defaultValue = "10") limit: Int
    ): ApiResponse<RankingV1Response> {
        val response = rankingFacade.getTopProductsHourly(dateTime, limit)
        return ApiResponse.success(response)
    }

    /**
     * 최근 N시간 랭킹 조회 (여러 시간대 집계)
     *
     * GET /api/v1/rankings/recent?hours=3&limit=10
     * → 최근 3시간 동안의 인기 상품
     */
    @GetMapping("/rankings/recent")
    @Operation(summary = "최근 N시간 상위 상품 랭킹 조회")
    fun getTopProductsRecent(
        @RequestParam(defaultValue = "3") hours: Int,
        @RequestParam(defaultValue = "10") limit: Int
    ): ApiResponse<RankingV1Response> {
        require(hours in 1..24) { "hours는 1~24 사이여야 합니다" }
        val response = rankingFacade.getTopProductsRecentHours(hours, limit)
        return ApiResponse.success(response)
    }
}
```

**API 사용 예시:**
```bash
# 1. 2025-12-25 14시 Top 10
curl "http://localhost:8080/api/v1/rankings/hourly?dateTime=2025-12-25T14:00:00&limit=10"

# 2. 현재 시간 Top 10
curl "http://localhost:8080/api/v1/rankings/hourly?limit=10"

# 3. 최근 3시간 Top 10 (현재 시간 기준 -3시간 ~ 현재)
curl "http://localhost:8080/api/v1/rankings/recent?hours=3&limit=10"
```

#### 1.2.6 TTL 전략

**일 단위 vs 시간 단위 TTL 비교:**

| 구분 | 일 단위 | 시간 단위 |
|-----|--------|----------|
| 키 예시 | `ranking:all:20251225` | `ranking:all:2025122514` |
| TTL | 2일 (48시간) | 2일 (48시간) |
| 키 개수/일 | 1개 | 24개 |
| 총 키 개수 | 2개 (2일치) | 48개 (2일 × 24시간) |
| 메모리 사용량 | 낮음 | 중간 (약 24배) |
| 실시간성 | 낮음 | 높음 |

**메모리 최적화 팁:**
```kotlin
// TTL을 더 짧게 설정 (최근 24시간만 보관)
redisTemplate.expire(key, Duration.ofHours(24))

// 또는 이전 시간대 데이터 즉시 삭제
fun cleanupOldHourlyKeys(before: LocalDateTime) {
    val cutoff = before.truncatedTo(ChronoUnit.HOURS)
    val oldKey = RankingKeyGenerator.generateHourlyRankingKey(cutoff)
    redisTemplate.delete(oldKey)
}
```

---

## 2. 콜드 스타트 문제 해결

### 2.1 콜드 스타트 문제란?

**문제 상황:**
```
12월 25일 23:59:59 → 상위 10개 상품: [101, 102, 103, ...]
12월 26일 00:00:00 → 새로운 키 생성: ranking:all:20251226
                    → 데이터 없음 (빈 랭킹)
12월 26일 00:00:01 ~ 06:00:00 → 데이터 누적 중 (불완전한 랭킹)
```

**왜 문제인가?**
- 새벽 시간대 랭킹 조회 시 빈 결과 또는 부정확한 랭킹 반환
- 사용자 경험 저하 (랭킹이 갑자기 사라짐)
- 추천 시스템과 연동 시 품질 저하

### 2.2 해결 전략: Previous Day Top N Initialization

**핵심 아이디어:**
- 전날 23:50에 Top N 상품을 추출
- 다음날 00:00에 이 상품들을 초기값으로 설정
- 실제 이벤트가 쌓이면서 점수가 자연스럽게 업데이트됨

**예시:**
```
12월 25일 23:50:
  - Top 10 추출: [101, 102, 103, ...]
  - 각 상품의 점수 × 0.3을 다음날 초기값으로 설정

12월 26일 00:00:
  - ranking:all:20251226 키 생성
  - 초기값: {101: 45.0, 102: 38.5, 103: 32.1, ...}
  - 실제 이벤트: 상품 105 조회 → 105: 0.1 추가

12월 26일 06:00:
  - 초기값 + 실제 데이터 혼합
  - 자연스러운 전환 완료
```

### 2.3 구현 방법

#### 2.3.1 Scheduler 추가

**파일:** `apps/commerce-streamer/src/main/kotlin/com/loopers/application/scheduler/RankingColdStartScheduler.kt`

**새로 생성:**
```kotlin
package com.loopers.application.scheduler

import com.loopers.domain.ranking.RankingService
import org.slf4j.LoggerFactory
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import java.time.LocalDate

/**
 * 랭킹 콜드 스타트 방지 스케줄러
 *
 * 실행 시간: 매일 23:50
 * 목적: 다음날 랭킹의 초기값 설정
 *
 * 왜 23:50인가?
 * - 23:59까지 실시간 이벤트 처리 계속됨
 * - 10분은 스케줄러 실행 + Redis 연산 완료에 충분한 시간
 * - 00:00 정각에는 새로운 키로 자동 전환
 */
@Component
@ConditionalOnProperty(
    name = ["ranking.cold-start.enabled"],
    havingValue = "true",
    matchIfMissing = false
)
class RankingColdStartScheduler(
    private val rankingService: RankingService
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    /**
     * 매일 23:50에 실행
     * cron: 초(0) 분(50) 시(23) 일(*) 월(*) 요일(*)
     */
    @Scheduled(cron = "0 50 23 * * *")
    fun initializeNextDayRanking() {
        logger.info("콜드 스타트 방지: 다음날 랭킹 초기화 시작")

        try {
            val today = LocalDate.now()
            val tomorrow = today.plusDays(1)

            // 1. 오늘의 Top 50 추출 (여유있게 많이 가져오기)
            val topProducts = rankingService.getTopProducts(today, limit = 50)

            if (topProducts.isEmpty()) {
                logger.warn("오늘 랭킹이 비어있음: 초기화 건너뜀")
                return
            }

            // 2. 다음날 키에 초기값 설정 (점수 × 30%)
            topProducts.forEach { ranking ->
                val initialScore = ranking.score * 0.3  // 30%로 감소
                rankingService.initializeScore(tomorrow, ranking.productId, initialScore)
            }

            logger.info("콜드 스타트 방지 완료: ${topProducts.size}개 상품 초기화 (다음날: $tomorrow)")

        } catch (e: Exception) {
            logger.error("콜드 스타트 방지 실패", e)
        }
    }
}
```

**왜 30%인가?**
- 너무 높으면 (예: 90%) → 전날 상품이 계속 상위권 독점
- 너무 낮으면 (예: 5%) → 콜드 스타트 효과 미미
- 30% → 새로운 상품도 충분히 경쟁 가능하면서도 빈 랭킹 방지

#### 2.3.2 RankingService 메서드 추가

**파일:** `modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt`

**새로운 메서드 추가:**
```kotlin
/**
 * 초기 점수 설정 (콜드 스타트 방지용)
 *
 * incrementScore와의 차이:
 * - incrementScore: 기존 점수에 더하기 (ZINCRBY)
 * - initializeScore: 초기값 설정 (ZADD NX - Not eXists)
 *
 * ZADD NX: 키가 없을 때만 설정 (이미 있으면 무시)
 * → 실제 이벤트가 이미 들어온 경우 덮어쓰지 않음
 */
fun initializeScore(date: LocalDate, productId: Long, initialScore: Double) {
    val key = RankingKeyGenerator.generateDailyRankingKey(date)

    // ZADD NX (Not eXists): 키가 없을 때만 설정
    val result = redisTemplate.execute { connection ->
        connection.zSetCommands().zAdd(
            key.toByteArray(),
            initialScore,
            productId.toString().toByteArray(),
            RedisZSetCommands.ZAddArgs.ifNotExists()  // NX 옵션
        )
    }

    // TTL 설정
    redisTemplate.expire(key, Duration.ofDays(2))

    logger.debug("초기값 설정: key=$key, productId=$productId, score=$initialScore, added=$result")
}
```

**ZADD NX의 동작:**
```
# 시나리오 1: 다음날 00:00 이전 (이벤트 없음)
ZADD ranking:all:20251226 NX 45.0 "101"  → 성공 (1 반환)

# 시나리오 2: 다음날 00:00 이후 (이미 실제 이벤트 존재)
ZADD ranking:all:20251226 NX 45.0 "101"  → 무시 (0 반환)
→ 실제 이벤트 데이터 보존
```

#### 2.3.3 설정 추가

**파일:** `apps/commerce-streamer/src/main/resources/application.yml`

```yaml
spring:
  task:
    scheduling:
      pool:
        size: 2  # 스케줄러 스레드 풀 크기

ranking:
  cold-start:
    enabled: true      # 콜드 스타트 방지 활성화
    carry-over-ratio: 0.3  # 전날 점수의 30%를 다음날 초기값으로 사용
    top-n: 50          # 상위 50개 상품 초기화

# 프로필별 설정
---
spring.config.activate.on-profile: local
ranking:
  cold-start:
    enabled: false  # 로컬에서는 비활성화 (테스트 편의성)

---
spring.config.activate.on-profile: prd
ranking:
  cold-start:
    enabled: true   # 운영환경에서만 활성화
```

#### 2.3.4 Scheduler 활성화

**파일:** `apps/commerce-streamer/src/main/kotlin/com/loopers/CommerceStreamerApplication.kt`

```kotlin
package com.loopers

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@SpringBootApplication
@EnableScheduling  // 스케줄링 활성화
class CommerceStreamerApplication

fun main(args: Array<String>) {
    runApplication<CommerceStreamerApplication>(*args)
}
```

### 2.4 개선된 Scheduler (설정값 활용)

**더 유연한 구현:**

```kotlin
@Component
@ConditionalOnProperty(
    name = ["ranking.cold-start.enabled"],
    havingValue = "true",
    matchIfMissing = false
)
class RankingColdStartScheduler(
    private val rankingService: RankingService,
    @Value("\${ranking.cold-start.carry-over-ratio:0.3}")
    private val carryOverRatio: Double,
    @Value("\${ranking.cold-start.top-n:50}")
    private val topN: Int
) {
    @Scheduled(cron = "0 50 23 * * *")
    fun initializeNextDayRanking() {
        logger.info("콜드 스타트 방지 시작: carryOverRatio=$carryOverRatio, topN=$topN")

        val today = LocalDate.now()
        val tomorrow = today.plusDays(1)

        val topProducts = rankingService.getTopProducts(today, limit = topN)

        if (topProducts.isEmpty()) {
            logger.warn("오늘 랭킹이 비어있음: 초기화 건너뜀")
            return
        }

        topProducts.forEach { ranking ->
            val initialScore = ranking.score * carryOverRatio
            rankingService.initializeScore(tomorrow, ranking.productId, initialScore)
        }

        logger.info("콜드 스타트 방지 완료: ${topProducts.size}개 상품 초기화")
    }
}
```

### 2.5 시간 단위 랭킹의 콜드 스타트

**시간 단위에서도 동일한 문제 발생:**
```
14:59:59 → ranking:all:2025122514 (데이터 많음)
15:00:00 → ranking:all:2025122515 (데이터 없음)
```

**해결 방법:**

```kotlin
/**
 * 시간 단위 콜드 스타트 방지
 * 실행: 매시 55분 (예: 14:55, 15:55, ...)
 */
@Scheduled(cron = "0 55 * * * *")
fun initializeNextHourRanking() {
    logger.info("시간 단위 콜드 스타트 방지 시작")

    val currentHour = LocalDateTime.now().truncatedTo(ChronoUnit.HOURS)
    val nextHour = currentHour.plusHours(1)

    val topProducts = rankingService.getTopProductsHourly(currentHour, limit = topN)

    if (topProducts.isEmpty()) {
        logger.warn("현재 시간 랭킹이 비어있음: 초기화 건너뜀")
        return
    }

    topProducts.forEach { ranking ->
        val initialScore = ranking.score * carryOverRatio
        rankingService.initializeScoreHourly(nextHour, ranking.productId, initialScore)
    }

    logger.info("시간 단위 콜드 스타트 방지 완료: ${topProducts.size}개 상품 초기화")
}
```

---

## 3. 테스트 전략

### 3.1 시간 단위 랭킹 테스트

**파일:** `modules/redis/src/test/kotlin/com/loopers/domain/ranking/RankingServiceTest.kt`

```kotlin
@Nested
@DisplayName("시간 단위 랭킹")
inner class HourlyRanking {
    @DisplayName("시간 단위로 점수를 증가시킬 수 있다")
    @Test
    fun incrementScoreHourly() {
        // given
        val dateTime = LocalDateTime.of(2025, 12, 25, 14, 0)
        val productId = 101L

        // when
        rankingService.incrementScoreHourly(dateTime, productId, 10.0)
        rankingService.incrementScoreHourly(dateTime, productId, 5.0)

        // then
        val rankings = rankingService.getTopProductsHourly(dateTime, 10)
        assertThat(rankings).hasSize(1)
        assertThat(rankings[0].productId).isEqualTo(101L)
        assertThat(rankings[0].score).isEqualTo(15.0)
    }

    @DisplayName("시간 범위의 랭킹을 집계할 수 있다")
    @Test
    fun getTopProductsHourlyRange() {
        // given
        val hour1 = LocalDateTime.of(2025, 12, 25, 14, 0)
        val hour2 = LocalDateTime.of(2025, 12, 25, 15, 0)
        val hour3 = LocalDateTime.of(2025, 12, 25, 16, 0)

        rankingService.incrementScoreHourly(hour1, 101L, 10.0)
        rankingService.incrementScoreHourly(hour2, 101L, 5.0)
        rankingService.incrementScoreHourly(hour3, 102L, 20.0)

        // when
        val rankings = rankingService.getTopProductsHourlyRange(hour1, hour3, 10)

        // then
        assertThat(rankings).hasSize(2)
        assertThat(rankings[0].productId).isEqualTo(102L)  // 20.0
        assertThat(rankings[1].productId).isEqualTo(101L)  // 15.0 (10 + 5)
    }
}
```

### 3.2 콜드 스타트 테스트

```kotlin
@Nested
@DisplayName("콜드 스타트 방지")
inner class ColdStart {
    @DisplayName("초기값을 설정할 수 있다")
    @Test
    fun initializeScore() {
        // given
        val date = LocalDate.of(2025, 12, 26)

        // when
        rankingService.initializeScore(date, 101L, 30.0)
        rankingService.initializeScore(date, 102L, 20.0)

        // then
        val rankings = rankingService.getTopProducts(date, 10)
        assertThat(rankings).hasSize(2)
        assertThat(rankings[0].score).isEqualTo(30.0)
    }

    @DisplayName("초기값이 있어도 실제 이벤트가 우선된다")
    @Test
    fun actualEventOverridesInitialValue() {
        // given
        val date = LocalDate.of(2025, 12, 26)

        // 실제 이벤트가 먼저 들어옴
        rankingService.incrementScore(date, 101L, 50.0)

        // when: 스케줄러가 초기값 설정 시도 (ZADD NX)
        rankingService.initializeScore(date, 101L, 30.0)

        // then: 실제 이벤트 점수 유지
        val rankings = rankingService.getTopProducts(date, 10)
        assertThat(rankings[0].score).isEqualTo(50.0)  // 초기값(30.0)이 아님
    }
}
```

### 3.3 Scheduler 테스트

```kotlin
@SpringBootTest
@Import(RedisTestContainersConfig::class)
@DisplayName("RankingColdStartScheduler 테스트")
class RankingColdStartSchedulerTest @Autowired constructor(
    private val scheduler: RankingColdStartScheduler,
    private val rankingService: RankingService,
    private val redisTemplate: RedisTemplate<String, String>
) {
    @AfterEach
    fun tearDown() {
        redisTemplate.connectionFactory?.connection?.serverCommands()?.flushAll()
    }

    @DisplayName("오늘의 Top N을 다음날 초기값으로 설정한다")
    @Test
    fun initializeNextDayRanking() {
        // given: 오늘 랭킹 데이터 준비
        val today = LocalDate.now()
        rankingService.incrementScore(today, 101L, 100.0)
        rankingService.incrementScore(today, 102L, 80.0)
        rankingService.incrementScore(today, 103L, 60.0)

        // when: 스케줄러 실행
        scheduler.initializeNextDayRanking()

        // then: 다음날 초기값 확인
        val tomorrow = today.plusDays(1)
        val rankings = rankingService.getTopProducts(tomorrow, 10)

        assertThat(rankings).hasSize(3)
        assertThat(rankings[0].productId).isEqualTo(101L)
        assertThat(rankings[0].score).isEqualTo(30.0)  // 100 × 0.3
        assertThat(rankings[1].score).isEqualTo(24.0)  // 80 × 0.3
        assertThat(rankings[2].score).isEqualTo(18.0)  // 60 × 0.3
    }
}
```

---

## 4. 배포 및 모니터링

### 4.1 배포 전 체크리스트

- [ ] **설정값 확인**
  - `ranking.time-unit`: DAILY 또는 HOURLY 선택
  - `ranking.cold-start.enabled`: 운영환경 true
  - `ranking.cold-start.carry-over-ratio`: 0.2 ~ 0.4 권장
  - `ranking.cold-start.top-n`: 50 ~ 100 권장

- [ ] **Redis 메모리 예측**
  - 일 단위: 키 2개 (2일치)
  - 시간 단위: 키 48개 (2일 × 24시간)
  - 상품 1000개 × 48키 = 약 48,000개 엔트리
  - 예상 메모리: 약 5~10MB (ZSET 효율적)

- [ ] **스케줄러 로그 확인**
  - 23:50 실행 로그
  - 초기화된 상품 개수
  - 에러 발생 시 알림 설정

### 4.2 모니터링 메트릭

**Redis 명령어:**
```bash
# 1. 현재 시간 랭킹 키 확인
redis-cli KEYS "ranking:all:*"

# 2. 특정 키의 엔트리 개수
redis-cli ZCARD "ranking:all:20251225"

# 3. 특정 키의 Top 10
redis-cli ZREVRANGE "ranking:all:20251225" 0 9 WITHSCORES

# 4. TTL 확인 (초 단위)
redis-cli TTL "ranking:all:20251225"

# 5. 메모리 사용량 (특정 키)
redis-cli MEMORY USAGE "ranking:all:20251225"
```

**애플리케이션 로그:**
```
# 정상 로그 예시
2025-12-25 23:50:00 INFO  - 콜드 스타트 방지: 다음날 랭킹 초기화 시작
2025-12-25 23:50:01 INFO  - 콜드 스타트 방지 완료: 50개 상품 초기화 (다음날: 2025-12-26)

2025-12-26 00:00:05 INFO  - 랭킹 배치 메시지 수신: 120개
2025-12-26 00:00:06 INFO  - 랭킹 배치 처리 완료: 120개
```

### 4.3 A/B 테스트 전략

**단계적 배포:**
1. **Phase 1**: DAILY 모드 + 콜드 스타트 ON (안정성 확인)
2. **Phase 2**: HOURLY 모드 10% 트래픽 (성능 측정)
3. **Phase 3**: HOURLY 모드 100% 전환

**비교 지표:**
- Redis 메모리 사용량
- API 응답 시간
- 랭킹 변화 빈도
- 사용자 클릭률 (랭킹 품질)

---

## 5. FAQ

### Q1: 시간 단위 랭킹이 일 단위보다 무조건 좋은가?

**A:** 아니다. 트레이드오프가 있다.

| 항목 | 일 단위 | 시간 단위 |
|-----|--------|----------|
| 메모리 | ⭐⭐⭐⭐⭐ (낮음) | ⭐⭐⭐ (24배) |
| 실시간성 | ⭐⭐ (느림) | ⭐⭐⭐⭐⭐ (빠름) |
| 안정성 | ⭐⭐⭐⭐⭐ (높음) | ⭐⭐⭐⭐ (중간) |
| 구현 복잡도 | ⭐⭐⭐⭐⭐ (단순) | ⭐⭐⭐ (복잡) |

**권장:**
- **B2C 이커머스, 패션**: 시간 단위 (트렌드 중요)
- **B2B, 산업재**: 일 단위 (안정성 중요)

### Q2: 콜드 스타트 없이 빈 랭킹을 보여주면 안되나?

**A:** 사용자 경험 관점에서 나쁘다.

```
시나리오: 사용자가 새벽 2시에 앱 접속
- 콜드 스타트 미적용: "랭킹이 없습니다"
- 콜드 스타트 적용: 전날 인기 상품 + 새벽 구매 상품 혼합
```

**대안:**
- Fallback: 랭킹 없으면 "추천 상품" 또는 "카테고리 베스트" 표시
- 하지만 콜드 스타트가 더 자연스럽고 일관된 경험 제공

### Q3: carry-over-ratio를 어떻게 정해야 하나?

**A:** 비즈니스 특성에 따라 다르다.

| Ratio | 의미 | 적합한 경우 |
|-------|------|-----------|
| 0.1 ~ 0.2 | 전날 영향 최소 | 트렌드 변화가 빠른 패션, 유행 상품 |
| 0.3 ~ 0.4 | 균형 | 일반적인 이커머스 |
| 0.5 ~ 0.7 | 전날 영향 높음 | 안정적인 카테고리 (가전, 가구) |

**실험 방법:**
```yaml
# 1주일간 비교 실험
ranking:
  cold-start:
    carry-over-ratio: 0.3  # A 그룹
    carry-over-ratio: 0.5  # B 그룹

# 측정 지표:
# - 새벽 시간대 랭킹 클릭률
# - 랭킹 상품 전환율
# - 사용자 체류 시간
```

### Q4: 시간 단위 랭킹에서 ZUNIONSTORE가 느리지 않나?

**A:** Redis ZUNIONSTORE는 매우 빠르다.

**성능 측정 (상품 1000개, 3시간 합산):**
```
ZUNIONSTORE ranking:temp:xxx 3
  ranking:all:2025122514
  ranking:all:2025122515
  ranking:all:2025122516

실행 시간: 약 5~10ms
```

**최적화 팁:**
```kotlin
// 임시 키 재사용 (동일 사용자 요청 캐싱)
val tempKey = "ranking:temp:user:${userId}:recent3h"
if (!redisTemplate.hasKey(tempKey)) {
    redisTemplate.opsForZSet().unionAndStore(...)
    redisTemplate.expire(tempKey, Duration.ofMinutes(5))  // 5분 캐싱
}
```

### Q5: 스케줄러가 실패하면 어떻게 되나?

**A:** 다음날 콜드 스타트가 발생하지만, 시스템은 정상 동작한다.

**대응 방안:**
1. **알림 설정**: 스케줄러 실패 시 Slack/Email 알림
2. **재시도 로직**: Spring Retry 사용
3. **수동 실행 API**: 긴급 시 수동 초기화

```kotlin
@RestController
class RankingAdminController(
    private val scheduler: RankingColdStartScheduler
) {
    @PostMapping("/admin/ranking/initialize-tomorrow")
    fun initializeTomorrow() {
        scheduler.initializeNextDayRanking()
        return "OK"
    }
}
```

---

## 6. 요약

### 시간 단위 랭킹 핵심 체크리스트

- [ ] RankingKeyGenerator: `generateHourlyRankingKey()` 추가
- [ ] RankingService: `incrementScoreHourly()`, `getTopProductsHourlyRange()` 추가
- [ ] RankingEventFacade: `aggregateByHour()` 추가
- [ ] RankingFacade: `getTopProductsHourly()` 추가
- [ ] API: `/api/v1/rankings/hourly`, `/api/v1/rankings/recent` 추가
- [ ] 설정: `ranking.time-unit=HOURLY`
- [ ] TTL: 48시간 설정

### 콜드 스타트 핵심 체크리스트

- [ ] RankingColdStartScheduler 생성 (cron: `0 50 23 * * *`)
- [ ] RankingService: `initializeScore()` 추가 (ZADD NX)
- [ ] @EnableScheduling 추가
- [ ] 설정: `ranking.cold-start.enabled=true`
- [ ] 설정: `ranking.cold-start.carry-over-ratio=0.3`
- [ ] 설정: `ranking.cold-start.top-n=50`
- [ ] 테스트: 스케줄러 단위 테스트
- [ ] 모니터링: 23:50 로그 확인

### 최종 확인 사항

1. **메모리**: Redis 메모리 사용량 모니터링 (시간 단위 시 24배 증가)
2. **성능**: ZUNIONSTORE 응답 시간 측정
3. **정확성**: 콜드 스타트 초기값이 실제 이벤트를 덮어쓰지 않는지 확인
4. **로그**: 스케줄러 실행 로그 및 에러 알림 설정
5. **테스트**: 자정 전후 랭킹 연속성 테스트

---

## 부록: 전체 아키텍처 비교

### Before (일 단위)
```
Kafka → RankingEventFacade → aggregateByDate() → RankingService.incrementScore()
                                                   ↓
                                        Redis: ranking:all:20251225
                                               (TTL: 2일)
```

### After (시간 단위 + 콜드 스타트)
```
Kafka → RankingEventFacade → aggregateByHour() → RankingService.incrementScoreHourly()
                                                   ↓
                                        Redis: ranking:all:2025122514
                                               ranking:all:2025122515
                                               ... (48개 키)
                                               (TTL: 48시간)

Scheduler (23:50) → RankingService.initializeScore()
                    ↓
                    Redis: ranking:all:20251226 (ZADD NX)
                    (다음날 초기값 설정)
```

**구현 완료 시:**
- ✅ 초 실시간 (시간 단위) 랭킹
- ✅ 콜드 스타트 문제 해결
- ✅ 설정 기반 유연한 전환 (DAILY ↔ HOURLY)
- ✅ 테스트 커버리지 확보
- ✅ 운영 모니터링 준비
