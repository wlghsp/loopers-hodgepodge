# Round 9 구현 가이드

## 개요

Kafka Consumer를 통해 이벤트를 소비하고 Redis ZSET에 랭킹 점수를 적재한 후, Ranking API를 제공합니다.

## 구현 단계

### Step 1: Redis ZSET 서비스 구현

**목표**: Redis ZSET 연산을 추상화한 서비스 레이어 구현

**파일 위치**: `apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/`

#### 1-1. RankingKey 생성 유틸리티

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingKey.kt
package com.loopers.domain.ranking

import java.time.LocalDate
import java.time.format.DateTimeFormatter

object RankingKey {
    private const val KEY_PREFIX = "ranking:all:"
    private val DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyyMMdd")
    
    fun buildDailyKey(date: LocalDate = LocalDate.now()): String {
        return "$KEY_PREFIX${date.format(DATE_FORMATTER)}"
    }
    
    fun parseDate(key: String): LocalDate {
        val dateStr = key.removePrefix(KEY_PREFIX)
        return LocalDate.parse(dateStr, DATE_FORMATTER)
    }
}
```

#### 1-2. RankingScore 계산 로직

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingScore.kt
package com.loopers.domain.ranking

object RankingScore {
    const val WEIGHT_VIEW = 0.1
    const val WEIGHT_LIKE = 0.2
    const val WEIGHT_ORDER = 0.6
    
    fun calculateViewScore(): Double = WEIGHT_VIEW * 1.0
    
    fun calculateLikeScore(): Double = WEIGHT_LIKE * 1.0
    
    fun calculateOrderScore(price: Long, quantity: Int): Double {
        val totalAmount = price * quantity
        // 정규화: log 적용 (선택사항)
        return WEIGHT_ORDER * totalAmount
    }
}
```

#### 1-3. RankingStore 인터페이스

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingStore.kt
package com.loopers.domain.ranking

interface RankingStore {
    fun incrementScore(key: String, productId: Long, score: Double)
    fun getRank(key: String, productId: Long): Long?
    fun getScore(key: String, productId: Long): Double?
    fun getTopN(key: String, n: Long): List<RankingEntry>
    fun getRankingRange(key: String, start: Long, end: Long): List<RankingEntry>
    fun setTtl(key: String, seconds: Long)
    fun exists(key: String): Boolean
}

data class RankingEntry(
    val productId: Long,
    val score: Double,
    val rank: Long
)
```

#### 1-4. RankingStore 구현체 (Redis)

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/ranking/RedisRankingStore.kt
package com.loopers.infrastructure.ranking

import com.loopers.config.redis.RedisConfig
import com.loopers.domain.ranking.RankingEntry
import com.loopers.domain.ranking.RankingStore
import org.springframework.beans.factory.annotation.Qualifier
import org.springframework.data.redis.core.RedisTemplate
import org.springframework.data.redis.core.ZSetOperations
import org.springframework.stereotype.Component
import java.util.concurrent.TimeUnit

@Component
class RedisRankingStore(
    @Qualifier(RedisConfig.REDIS_TEMPLATE_MASTER) 
    private val redisTemplate: RedisTemplate<String, String>
) : RankingStore {
    
    override fun incrementScore(key: String, productId: Long, score: Double) {
        redisTemplate.opsForZSet().incrementScore(key, productId.toString(), score)
    }
    
    override fun getRank(key: String, productId: Long): Long? {
        val rank = redisTemplate.opsForZSet().reverseRank(key, productId.toString())
        return rank?.let { it + 1 } // 0-based → 1-based
    }
    
    override fun getScore(key: String, productId: Long): Double? {
        return redisTemplate.opsForZSet().score(key, productId.toString())
    }
    
    override fun getTopN(key: String, n: Long): List<RankingEntry> {
        val range = redisTemplate.opsForZSet().reverseRangeWithScores(key, 0, n - 1)
            ?: return emptyList()
        
        return range.mapIndexed { index, tuple ->
            RankingEntry(
                productId = tuple.value!!.toLong(),
                score = tuple.score!!,
                rank = index + 1L
            )
        }
    }
    
    override fun getRankingRange(key: String, start: Long, end: Long): List<RankingEntry> {
        val range = redisTemplate.opsForZSet().reverseRangeWithScores(key, start - 1, end - 1)
            ?: return emptyList()
        
        return range.mapIndexed { index, tuple ->
            RankingEntry(
                productId = tuple.value!!.toLong(),
                score = tuple.score!!,
                rank = start + index
            )
        }
    }
    
    override fun setTtl(key: String, seconds: Long) {
        redisTemplate.expire(key, seconds, TimeUnit.SECONDS)
    }
    
    override fun exists(key: String): Boolean {
        return redisTemplate.hasKey(key) ?: false
    }
}
```

### Step 2: 랭킹 Consumer 구현

**목표**: Kafka 이벤트를 소비하여 Redis ZSET에 점수 적재

#### 2-1. RankingEventFacade

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/application/ranking/RankingEventFacade.kt
package com.loopers.application.ranking

import com.loopers.domain.event.DomainEvent
import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.product.event.ProductViewedEvent
import com.loopers.domain.ranking.RankingKey
import com.loopers.domain.ranking.RankingScore
import com.loopers.domain.ranking.RankingService
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@Service
class RankingEventFacade(
    private val rankingService: RankingService
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    
    fun handleEvent(event: DomainEvent) {
        val date = LocalDate.ofInstant(event.occurredAt, ZoneId.systemDefault())
        val key = RankingKey.buildDailyKey(date)
        
        when (event) {
            is ProductViewedEvent -> {
                val score = RankingScore.calculateViewScore()
                rankingService.incrementScore(key, event.productId, score)
            }
            is ProductLikedEvent -> {
                val score = RankingScore.calculateLikeScore()
                rankingService.incrementScore(key, event.productId, score)
            }
            is ProductUnlikedEvent -> {
                val score = -RankingScore.calculateLikeScore()
                rankingService.incrementScore(key, event.productId, score)
            }
            is OrderCreatedEvent -> {
                event.orderItems.forEach { item ->
                    val score = RankingScore.calculateOrderScore(item.price, item.quantity)
                    rankingService.incrementScore(key, item.productId, score)
                }
            }
            else -> {
                logger.debug("랭킹 처리 대상 아님: eventType=${event.eventType}")
            }
        }
    }
    
    fun handleBatchEvents(events: List<DomainEvent>) {
        if (events.isEmpty()) return
        
        // 날짜별로 그룹화
        val eventsByDate = events.groupBy { event ->
            LocalDate.ofInstant(event.occurredAt, ZoneId.systemDefault())
        }
        
        eventsByDate.forEach { (date, dateEvents) ->
            val key = RankingKey.buildDailyKey(date)
            
            // 상품별로 그룹화하여 점수 합산
            val scoresByProduct = mutableMapOf<Long, Double>()
            
            dateEvents.forEach { event ->
                when (event) {
                    is ProductViewedEvent -> {
                        scoresByProduct[event.productId] = 
                            scoresByProduct.getOrDefault(event.productId, 0.0) + RankingScore.calculateViewScore()
                    }
                    is ProductLikedEvent -> {
                        scoresByProduct[event.productId] = 
                            scoresByProduct.getOrDefault(event.productId, 0.0) + RankingScore.calculateLikeScore()
                    }
                    is ProductUnlikedEvent -> {
                        scoresByProduct[event.productId] = 
                            scoresByProduct.getOrDefault(event.productId, 0.0) - RankingScore.calculateLikeScore()
                    }
                    is OrderCreatedEvent -> {
                        event.orderItems.forEach { item ->
                            scoresByProduct[item.productId] = 
                                scoresByProduct.getOrDefault(item.productId, 0.0) + 
                                RankingScore.calculateOrderScore(item.price, item.quantity)
                        }
                    }
                }
            }
            
            // 배치로 점수 업데이트
            scoresByProduct.forEach { (productId, score) ->
                rankingService.incrementScore(key, productId, score)
            }
            
            // TTL 설정 (2일)
            rankingService.ensureTtl(key, 2 * 24 * 60 * 60)
        }
        
        logger.info("배치 랭킹 처리 완료: ${events.size}개 이벤트")
    }
}
```

#### 2-2. RankingService

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt
package com.loopers.domain.ranking

import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service

@Service
class RankingService(
    private val rankingStore: RankingStore
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    private val TTL_SECONDS = 2L * 24 * 60 * 60 // 2일
    
    fun incrementScore(key: String, productId: Long, score: Double) {
        rankingStore.incrementScore(key, productId, score)
        
        // 키가 새로 생성된 경우 TTL 설정
        if (!rankingStore.exists(key)) {
            rankingStore.setTtl(key, TTL_SECONDS)
        }
        
        logger.debug("랭킹 점수 업데이트: key=$key, productId=$productId, score=$score")
    }
    
    fun ensureTtl(key: String, seconds: Long) {
        if (rankingStore.exists(key)) {
            rankingStore.setTtl(key, seconds)
        }
    }
    
    fun getRank(key: String, productId: Long): Long? {
        return rankingStore.getRank(key, productId)
    }
    
    fun getTopN(key: String, n: Long): List<RankingEntry> {
        return rankingStore.getTopN(key, n)
    }
    
    fun getRankingRange(key: String, start: Long, end: Long): List<RankingEntry> {
        return rankingStore.getRankingRange(key, start, end)
    }
}
```

#### 2-3. RankingKafkaConsumer

```kotlin
// apps/commerce-streamer/src/main/kotlin/com/loopers/interfaces/consumer/RankingKafkaConsumer.kt
package com.loopers.interfaces.consumer

import com.fasterxml.jackson.databind.ObjectMapper
import com.loopers.application.ranking.RankingEventFacade
import com.loopers.domain.event.DomainEvent
import com.loopers.domain.event.coupon.CouponUsedEvent
import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.event.payment.PaymentCompletedEvent
import com.loopers.domain.event.payment.PaymentFailedEvent
import com.loopers.domain.event.product.StockDecreasedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.product.event.ProductViewedEvent
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.slf4j.LoggerFactory
import org.springframework.kafka.annotation.KafkaListener
import org.springframework.kafka.support.Acknowledgment
import org.springframework.stereotype.Component

@Component
class RankingKafkaConsumer(
    private val rankingEventFacade: RankingEventFacade,
    private val objectMapper: ObjectMapper
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    
    @KafkaListener(
        topics = ["catalog-events", "order-events"],
        groupId = "ranking-consumer-group",
        containerFactory = "batchKafkaListenerContainerFactory"
    )
    fun consumeBatch(
        messages: List<ConsumerRecord<String, String>>,
        acknowledgment: Acknowledgment
    ) {
        logger.info("랭킹 배치 메시지 수신: ${messages.size}개")
        
        try {
            val events = messages.map { record ->
                parseEvent(record.value())
            }
            
            rankingEventFacade.handleBatchEvents(events)
            
            acknowledgment.acknowledge()
            logger.info("랭킹 배치 처리 완료: ${events.size}개")
        } catch (e: Exception) {
            logger.error("랭킹 배치 처리 실패: ${messages.size}개, error=${e.message}", e)
        }
    }
    
    private fun parseEvent(message: String): DomainEvent {
        val node = objectMapper.readTree(message)
        val eventType = node["eventType"]?.asText()
            ?: throw IllegalArgumentException("Missing eventType in message: $message")
        
        return when (eventType) {
            "PRODUCT_LIKED" -> objectMapper.readValue(message, ProductLikedEvent::class.java)
            "PRODUCT_UNLIKED" -> objectMapper.readValue(message, ProductUnlikedEvent::class.java)
            "PRODUCT_VIEWED" -> objectMapper.readValue(message, ProductViewedEvent::class.java)
            "ORDER_CREATED" -> objectMapper.readValue(message, OrderCreatedEvent::class.java)
            else -> throw IllegalArgumentException("Unknown event type: $eventType")
        }
    }
}
```

### Step 3: Ranking API 구현

**목표**: 랭킹 조회 API 및 상품 상세 조회에 랭킹 정보 추가

#### 3-1. RankingFacade

```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingFacade.kt
package com.loopers.application.ranking

import com.loopers.application.product.ProductFacade
import com.loopers.application.product.ProductInfo
import com.loopers.domain.ranking.RankingKey
import com.loopers.domain.ranking.RankingService
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageImpl
import org.springframework.data.domain.Pageable
import org.springframework.stereotype.Component
import java.time.LocalDate
import java.time.format.DateTimeFormatter

@Component
class RankingFacade(
    private val rankingService: RankingService,
    private val productFacade: ProductFacade
) {
    private val dateFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")
    
    fun getRankings(dateStr: String?, pageable: Pageable): Page<RankingInfo> {
        val date = dateStr?.let { LocalDate.parse(it, dateFormatter) } ?: LocalDate.now()
        val key = RankingKey.buildDailyKey(date)
        
        val start = pageable.offset
        val end = start + pageable.pageSize - 1
        
        val rankingEntries = rankingService.getRankingRange(key, start, end)
        
        // 상품 정보 조회
        val productIds = rankingEntries.map { it.productId }
        val products = productIds.mapNotNull { productFacade.getProduct(it) }
            .associateBy { it.id }
        
        val rankingInfos = rankingEntries.mapNotNull { entry ->
            products[entry.productId]?.let { product ->
                RankingInfo(
                    product = product,
                    rank = entry.rank,
                    score = entry.score
                )
            }
        }
        
        // 전체 개수는 ZSET 크기로 대체 (정확도는 낮지만 성능 고려)
        val totalElements = rankingService.getTotalCount(key)
        
        return PageImpl(rankingInfos, pageable, totalElements)
    }
    
    fun getProductRank(productId: Long, dateStr: String?): RankingInfo? {
        val date = dateStr?.let { LocalDate.parse(it, dateFormatter) } ?: LocalDate.now()
        val key = RankingKey.buildDailyKey(date)
        
        val rank = rankingService.getRank(key, productId) ?: return null
        val score = rankingService.getScore(key, productId) ?: return null
        val product = productFacade.getProduct(productId)
        
        return RankingInfo(
            product = product,
            rank = rank,
            score = score
        )
    }
}

data class RankingInfo(
    val product: ProductInfo,
    val rank: Long,
    val score: Double
)
```

#### 3-2. RankingService (API용)

```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt
package com.loopers.domain.ranking

import com.loopers.infrastructure.ranking.RedisRankingStore
import org.springframework.stereotype.Service

@Service
class RankingService(
    private val rankingStore: RankingStore
) {
    fun getRank(key: String, productId: Long): Long? {
        return rankingStore.getRank(key, productId)
    }
    
    fun getScore(key: String, productId: Long): Double? {
        return rankingStore.getScore(key, productId)
    }
    
    fun getRankingRange(key: String, start: Long, end: Long): List<RankingEntry> {
        return rankingStore.getRankingRange(key, start, end)
    }
    
    fun getTotalCount(key: String): Long {
        return rankingStore.getTotalCount(key)
    }
}
```

#### 3-3. RankingStore 인터페이스에 getTotalCount 추가

```kotlin
// RankingStore.kt에 추가
fun getTotalCount(key: String): Long
```

```kotlin
// RedisRankingStore.kt에 구현 추가
override fun getTotalCount(key: String): Long {
    return redisTemplate.opsForZSet().zCard(key) ?: 0L
}
```

#### 3-4. Ranking API Controller

```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Api.kt
package com.loopers.interfaces.api.ranking

import com.loopers.application.ranking.RankingFacade
import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.media.Schema
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.data.domain.Pageable
import org.springframework.web.bind.annotation.*

@Tag(name = "Ranking V1 API", description = "랭킹 관련 API 입니다.")
@RestController
@RequestMapping("/api/v1/rankings")
class RankingV1Api(
    private val rankingFacade: RankingFacade
) {
    @Operation(
        summary = "랭킹 조회",
        description = "일간 상품 랭킹을 조회합니다."
    )
    @GetMapping
    fun getRankings(
        @Schema(description = "날짜 (yyyyMMdd 형식, 기본값: 오늘")
        @RequestParam(required = false) date: String?,
        @Schema(description = "페이지 번호 (0부터 시작)")
        @RequestParam(defaultValue = "0") page: Int,
        @Schema(description = "페이지 크기")
        @RequestParam(defaultValue = "20") size: Int
    ): ApiResponse<Page<RankingV1Dto.RankingResponse>> {
        val pageable: Pageable = PageRequest.of(page, size)
        val rankings = rankingFacade.getRankings(date, pageable)
        
        return ApiResponse.success(
            rankings.map { RankingV1Dto.RankingResponse.from(it) }
        )
    }
}
```

#### 3-5. Ranking DTO

```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Dto.kt
package com.loopers.interfaces.api.ranking

import com.loopers.application.ranking.RankingInfo

object RankingV1Dto {
    data class RankingResponse(
        val productId: Long,
        val productName: String,
        val brandName: String,
        val price: Long,
        val imageUrl: String?,
        val rank: Long,
        val score: Double
    ) {
        companion object {
            fun from(info: RankingInfo): RankingResponse {
                val product = info.product
                return RankingResponse(
                    productId = product.id,
                    productName = product.name,
                    brandName = product.brandName,
                    price = product.price,
                    imageUrl = product.imageUrl,
                    rank = info.rank,
                    score = info.score
                )
            }
        }
    }
}
```

#### 3-6. 상품 상세 조회에 랭킹 정보 추가

```kotlin
// ProductFacade.kt 수정
fun getProduct(productId: Long, includeRanking: Boolean = false): ProductInfo {
    // ... 기존 코드 ...
    
    // 랭킹 정보 추가 (선택사항)
    // rankingFacade.getProductRank(productId) 사용
}
```

또는 별도 메서드로:

```kotlin
// ProductFacade.kt에 추가
fun getProductWithRanking(productId: Long): ProductWithRankingInfo {
    val product = getProduct(productId)
    val ranking = rankingFacade.getProductRank(productId, null)
    
    return ProductWithRankingInfo(
        product = product,
        rank = ranking?.rank
    )
}
```

### Step 4: 공통 모듈 설정

**목표**: commerce-api와 commerce-streamer에서 공통 사용할 Ranking 도메인 모듈 생성

#### 4-1. RankingStore 인터페이스를 공통 모듈로 이동

`modules/ranking` 모듈을 생성하거나, 기존 `modules/redis`에 추가

#### 4-2. RedisRankingStore는 commerce-streamer에만 존재

commerce-api는 RankingService를 통해 조회만 수행

## 체크리스트

### Ranking Consumer
- [ ] 랭킹 ZSET의 TTL, 키 전략 구성
- [ ] 날짜별 키 계산 기능 구현
- [ ] 이벤트 발생 후 ZSET 점수 반영
- [ ] 배치 리스너로 처리

### Ranking API
- [ ] 랭킹 Page 조회 정상 동작
- [ ] 랭킹 조회 시 상품 정보 Aggregation 제공
- [ ] 상품 상세 조회 시 순위 정보 반환 (없으면 null)

## 테스트 방법

1. 이벤트 발행 후 Redis 확인
```bash
redis-cli
> ZREVRANGE ranking:all:20250101 0 9 WITHSCORES
> ZRANK ranking:all:20250101 1
```

2. API 호출 테스트
```http
GET /api/v1/rankings?date=20250101&page=0&size=20
```

3. 상품 상세 조회에 랭킹 정보 포함 확인

