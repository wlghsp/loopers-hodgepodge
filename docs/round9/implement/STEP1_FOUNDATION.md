# 🎯 Step 1: 기반 인프라 및 유틸리티 구축

> **목표**: Redis ZSET 기반 랭킹 시스템의 핵심 도메인 로직을 구현합니다.

---

## 📌 왜 이 단계가 필요한가?

랭킹 시스템을 구축하기 전에 다음 질문에 답해야 합니다:

1. **시간의 양자화**: 랭킹 데이터를 어떻게 일별로 분리할 것인가?
2. **점수 계산 전략**: 조회/좋아요/주문의 가치를 어떻게 숫자로 표현할 것인가?
3. **고가 상품 독식 방지**: 100만원 상품이 1만원 상품보다 100배 유리하면 공정한가?

이 단계에서는 이러한 설계 결정을 코드로 구현합니다.

---

## 1-1. 랭킹 키 생성 전략

### 💡 왜 키 전략이 중요한가?

Redis ZSET은 Key-Value 저장소입니다. 만약 키를 `ranking:all`로만 사용하면:
- ❌ 모든 상품의 점수가 **누적**되어 오래된 상품이 계속 1위
- ❌ 신상품은 절대 순위권 진입 불가능 (롱테일 문제)
- ❌ "오늘의 인기 상품"과 "이번 달 인기 상품"을 구분할 수 없음

**해결책**: 날짜를 키에 포함시켜 시간 단위로 랭킹을 분리합니다.

### 📂 파일 생성

**경로**: `apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingKeyGenerator.kt`

```kotlin
package com.loopers.domain.ranking

import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * 랭킹 ZSET 키 생성 유틸리티
 *
 * 키 전략:
 * - 일간 랭킹: ranking:all:{yyyyMMdd}
 * - 예시: ranking:all:20251222
 *
 * 왜 이렇게 설계했나?
 * 1. 날짜별 분리로 시간의 양자화 구현
 * 2. 패턴 일관성으로 확장 가능 (주간/월간 랭킹 추가 시)
 * 3. TTL 관리 용이 (날짜별로 독립적인 만료)
 */
object RankingKeyGenerator {

    private const val RANKING_PREFIX = "ranking:all:"
    private val DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyyMMdd")

    /**
     * 일간 랭킹 키 생성
     *
     * @param date 대상 날짜
     * @return ranking:all:{yyyyMMdd} 형식의 키
     */
    fun generateDailyKey(date: LocalDate): String {
        return RANKING_PREFIX + date.format(DATE_FORMATTER)
    }

    /**
     * 오늘 날짜의 랭킹 키 생성
     */
    fun generateTodayKey(): String {
        return generateDailyKey(LocalDate.now())
    }

    /**
     * 문자열 날짜로부터 키 생성
     *
     * @param dateString yyyyMMdd 형식의 날짜 문자열
     * @return ranking:all:{yyyyMMdd} 형식의 키
     * @throws DateTimeParseException 날짜 형식이 잘못된 경우
     */
    fun generateKeyFromString(dateString: String): String {
        val date = LocalDate.parse(dateString, DATE_FORMATTER)
        return generateDailyKey(date)
    }

    /**
     * 키로부터 날짜 추출
     *
     * @param key ranking:all:{yyyyMMdd} 형식의 키
     * @return 추출된 날짜
     */
    fun extractDateFromKey(key: String): LocalDate {
        val dateString = key.removePrefix(RANKING_PREFIX)
        return LocalDate.parse(dateString, DATE_FORMATTER)
    }
}
```

### ✅ 핵심 포인트
- `object`로 선언하여 싱글톤 유틸리티로 사용
- 날짜 포맷은 `yyyyMMdd` (숫자만 사용하여 간결함)
- `extractDateFromKey()`로 양방향 변환 가능

---

## 1-2. 랭킹 점수 계산기

### 💡 왜 가중치가 필요한가?

이벤트를 그냥 카운트하면 문제가 발생합니다:

```
예시:
- 상품 A: 조회 1000회, 좋아요 10회, 주문 1회
- 상품 B: 조회 100회, 좋아요 5회, 주문 20회

단순 합산: A = 1011점, B = 125점 → A가 1위
실제 가치: B가 매출이 20배 높은데 랭킹은 낮음
```

**해결책**: 각 이벤트에 비즈니스 가치에 비례하는 가중치를 부여합니다.

### 가중치 설계 근거

| 이벤트 | 가중치 | 근거 |
|--------|--------|------|
| 조회 | 0.1 | 가장 빈번하지만 전환율이 낮음 |
| 좋아요 | 0.2 | 관심 표현이지만 구매로 이어지지 않을 수 있음 |
| 좋아요 취소 | -0.2 | 관심도 하락 반영 |
| 주문 | 0.6 × ln(1 + amount) | 매출 기여도가 가장 높음, 로그 정규화로 고가 상품 독식 방지 |

### 📂 파일 생성

**경로**: `apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingScoreCalculator.kt`

```kotlin
package com.loopers.domain.ranking

import com.loopers.domain.event.DomainEvent
import com.loopers.domain.event.like.ProductLikedEvent
import com.loopers.domain.event.like.ProductUnlikedEvent
import com.loopers.domain.order.event.OrderCreatedEvent
import com.loopers.domain.order.event.OrderItemDto
import com.loopers.domain.product.event.ProductViewedEvent
import org.springframework.stereotype.Component
import kotlin.math.ln

/**
 * 랭킹 점수 계산기
 *
 * 가중치 기반 점수 계산:
 * - 조회: 0.1점
 * - 좋아요: 0.2점
 * - 좋아요 취소: -0.2점
 * - 주문: 0.6 × ln(1 + price × quantity)
 *
 * 왜 주문 점수에 로그를 사용하는가?
 *
 * 문제: 100만원 상품 1개 = 1만원 상품 100개와 같은 가치인가?
 * - 선형 계산: 1,000,000 vs 1,000,000 (동일)
 * - 실제 의미: 100명이 구매한 상품이 1명만 구매한 상품보다 인기있음
 *
 * 해결: ln(1 + x) 정규화 (x = price × quantity)
 *
 * 예시 1: 동일 금액, 다른 구매 횟수
 * - 1만원 상품 100개 구매: 0.6 × ln(1 + 10,000 × 100) = 0.6 × ln(1,000,001) ≈ 8.29
 * - 100만원 상품 1개 구매: 0.6 × ln(1 + 1,000,000 × 1) = 0.6 × ln(1,000,001) ≈ 8.29
 *
 * 예시 2: 구매 횟수가 많으면 점수 상승
 * - 1만원 상품 1000개 구매: 0.6 × ln(1 + 10,000 × 1000) = 0.6 × ln(10,000,001) ≈ 9.63
 *
 * 예시 3: 저가 상품도 많이 팔리면 고가 상품보다 높은 점수
 * - 5천원 상품 5000개: 0.6 × ln(1 + 5,000 × 5000) = 0.6 × ln(25,000,001) ≈ 10.13
 * - 500만원 상품 1개: 0.6 × ln(1 + 5,000,000 × 1) = 0.6 × ln(5,000,001) ≈ 9.24
 *
 * 즉, 구매 횟수가 많을수록 점수가 높아지지만, 고가 상품의 이점도 일부 반영됨.
 *
 * 왜 @Component로 구현하는가?
 * - 현재는 상태가 없는 순수 함수들이지만, @Component를 유지하는 이유:
 *   1. 나중에 @ConfigurationProperties로 가중치를 외부화할 가능성
 *   2. 프로덕션 환경에서 A/B 테스트를 위한 가중치 동적 조정
 *   3. Spring Bean으로 관리하여 테스트 시 Mock 객체로 교체 용이
 * - object로 만들면 위 기능들을 구현하기 어려움
 * - 성능 차이는 미미 (싱글톤이므로 인스턴스 1개만 생성됨)
 */
@Component
class RankingScoreCalculator {

    companion object {
        // 가중치 설정 (프로덕션에서는 @ConfigurationProperties로 외부화 권장)
        private const val WEIGHT_VIEW = 0.1
        private const val WEIGHT_LIKE = 0.2
        private const val WEIGHT_UNLIKE = -0.2  // 좋아요 취소는 음수
        private const val WEIGHT_ORDER = 0.6
    }

    /**
     * 이벤트로부터 점수 계산
     *
     * @param event 도메인 이벤트
     * @return 계산된 점수
     * @throws IllegalArgumentException OrderCreatedEvent는 별도 메서드 사용 필요
     */
    fun calculateScore(event: DomainEvent): Double {
        return when (event) {
            is ProductViewedEvent -> WEIGHT_VIEW
            is ProductLikedEvent -> WEIGHT_LIKE
            is ProductUnlikedEvent -> WEIGHT_UNLIKE
            is OrderCreatedEvent -> throw IllegalArgumentException(
                "OrderCreatedEvent는 calculateOrderItemScore()를 사용해야 합니다. " +
                "이유: 한 주문에 여러 상품이 포함될 수 있어 상품별 개별 계산이 필요합니다."
            )
            else -> 0.0
        }
    }

    /**
     * 주문 아이템으로부터 점수 계산 (로그 정규화 적용)
     *
     * 점수 = WEIGHT_ORDER × ln(1 + price × quantity)
     *
     * 로그 정규화를 사용하는 이유:
     * - 고가 상품의 점수 독식 방지
     * - 가격 차이를 완화하면서도 주문 가치 반영
     * - 구매 횟수가 많은 상품에 가산점
     *
     * @param orderItem 주문 아이템 (productId, price, quantity 포함)
     * @return 계산된 점수
     */
    fun calculateOrderItemScore(orderItem: OrderItemDto): Double {
        val orderValue = orderItem.price * orderItem.quantity
        // ln(1 + x) 사용 이유:
        // 1. x=0일 때도 안전 (ln(1) = 0)
        // 2. 큰 값의 영향력 완화
        // 3. 자연스러운 증가 곡선
        return WEIGHT_ORDER * ln(1.0 + orderValue)
    }

    /**
     * 배치 이벤트의 총 점수 계산
     *
     * 주의: OrderCreatedEvent는 제외되므로 별도 처리 필요
     *
     * @param events 이벤트 리스트
     * @return 총 점수
     */
    fun calculateBatchScore(events: List<DomainEvent>): Double {
        return events.sumOf {
            try {
                calculateScore(it)
            } catch (e: IllegalArgumentException) {
                0.0 // OrderCreatedEvent는 스킵
            }
        }
    }
}
```

### ✅ 핵심 포인트
- 로그 정규화로 고가 상품 독식 방지 (과제 요구사항 반영)
- ProductUnlikedEvent는 음수 점수로 처리 (관심도 하락 반영)
- 왜 이렇게 설계했는지 주석으로 명확히 설명

---

## 1-3. RankingService (Redis ZSET 연산 캡슐화)

### 💡 왜 Service 레이어가 필요한가?

Redis 명령어를 직접 사용하면:
- ❌ 비즈니스 로직이 인프라 레이어에 의존
- ❌ TTL 관리 로직이 Consumer 곳곳에 흩어짐
- ❌ 테스트가 어려움 (Redis 모킹 필요)

**해결책**: Redis ZSET 연산을 도메인 서비스로 캡슐화합니다.

### 📂 파일 생성

**경로**: `apps/commerce-streamer/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt`

```kotlin
package com.loopers.domain.ranking

import org.slf4j.LoggerFactory
import org.springframework.data.redis.core.RedisTemplate
import org.springframework.stereotype.Service
import java.time.LocalDate
import java.util.concurrent.TimeUnit

/**
 * 랭킹 도메인 서비스
 *
 * 역할:
 * 1. Redis ZSET 연산 캡슐화
 * 2. TTL 자동 관리 (키 생성 시 2일 자동 설정)
 * 3. 비즈니스 로직과 인프라 분리
 *
 * Redis ZSET 명령어 매핑:
 * - incrementScore() → ZINCRBY
 * - getTopProducts() → ZREVRANGE ... WITHSCORES
 * - getProductRank() → ZREVRANK
 * - getProductScore() → ZSCORE
 * - getRankingSize() → ZCARD
 */
@Service
class RankingService(
    private val redisTemplate: RedisTemplate<String, String>
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    companion object {
        private const val TTL_DAYS = 2L  // 2일 TTL (과제 요구사항)
        private const val TTL_SECONDS = TTL_DAYS * 24 * 60 * 60
    }

    /**
     * 특정 상품의 랭킹 점수 증가
     *
     * Redis 명령어: ZINCRBY ranking:all:20251222 0.5 "product:101"
     *
     * @param date 대상 날짜
     * @param productId 상품 ID
     * @param score 증가시킬 점수 (음수 가능 - 좋아요 취소 시)
     */
    fun incrementScore(date: LocalDate, productId: Long, score: Double) {
        val key = RankingKeyGenerator.generateDailyKey(date)
        val member = "product:$productId"

        val zSetOps = redisTemplate.opsForZSet()

        // ZINCRBY: 점수 증가 (member가 없으면 자동 생성)
        val newScore = zSetOps.incrementScore(key, member, score)

        // TTL 설정 (키가 처음 생성될 때만)
        ensureTtl(key)

        logger.debug("랭킹 점수 증가: key=$key, member=$member, delta=$score, newScore=$newScore")
    }

    /**
     * Top-N 상품 ID 조회 (점수 포함)
     *
     * Redis 명령어: ZREVRANGE ranking:all:20251222 0 9 WITHSCORES
     *
     * @param date 대상 날짜
     * @param size 조회할 개수
     * @return List<Pair<productId, score>> (순위 순서대로 정렬됨)
     */
    fun getTopProducts(date: LocalDate, size: Int): List<Pair<Long, Double>> {
        val key = RankingKeyGenerator.generateDailyKey(date)
        val zSetOps = redisTemplate.opsForZSet()

        // ZREVRANGE 0 (size-1) WITHSCORES: 상위 N개 조회 (내림차순)
        val results = zSetOps.reverseRangeWithScores(key, 0, (size - 1).toLong())
            ?: return emptyList()

        return results.mapNotNull { typedTuple ->
            val member = typedTuple.value ?: return@mapNotNull null
            val score = typedTuple.score ?: return@mapNotNull null

            // "product:123" -> 123 추출
            val productId = member.removePrefix("product:").toLongOrNull()
                ?: return@mapNotNull null

            productId to score
        }
    }

    /**
     * 페이지네이션을 위한 범위 조회
     *
     * @param date 대상 날짜
     * @param start 시작 순위 (0-based)
     * @param end 종료 순위 (0-based, inclusive)
     * @return List<Pair<productId, score>>
     */
    fun getProductsInRange(date: LocalDate, start: Long, end: Long): List<Pair<Long, Double>> {
        val key = RankingKeyGenerator.generateDailyKey(date)
        val zSetOps = redisTemplate.opsForZSet()

        val results = zSetOps.reverseRangeWithScores(key, start, end)
            ?: return emptyList()

        return results.mapNotNull { typedTuple ->
            val member = typedTuple.value ?: return@mapNotNull null
            val score = typedTuple.score ?: return@mapNotNull null
            val productId = member.removePrefix("product:").toLongOrNull()
                ?: return@mapNotNull null

            productId to score
        }
    }

    /**
     * 특정 상품의 순위 조회 (0-based index)
     *
     * Redis 명령어: ZREVRANK ranking:all:20251222 "product:101"
     *
     * @param date 대상 날짜
     * @param productId 상품 ID
     * @return 순위 (0부터 시작, 없으면 null)
     */
    fun getProductRank(date: LocalDate, productId: Long): Long? {
        val key = RankingKeyGenerator.generateDailyKey(date)
        val member = "product:$productId"
        val zSetOps = redisTemplate.opsForZSet()

        // ZREVRANK: 내림차순 순위 조회 (0부터 시작)
        return zSetOps.reverseRank(key, member)
    }

    /**
     * 특정 상품의 점수 조회
     *
     * Redis 명령어: ZSCORE ranking:all:20251222 "product:101"
     *
     * @param date 대상 날짜
     * @param productId 상품 ID
     * @return 점수 (없으면 null)
     */
    fun getProductScore(date: LocalDate, productId: Long): Double? {
        val key = RankingKeyGenerator.**generateDailyKey**(date)
        val member = "product:$productId"
        val zSetOps = redisTemplate.opsForZSet()

        // ZSCORE: 점수 조회
        return zSetOps.score(key, member)
    }

    /**
     * 랭킹에 포함된 상품 수 조회
     *
     * Redis 명령어: ZCARD ranking:all:20251222
     *
     * @param date 대상 날짜
     * @return 상품 개수
     */
    fun getRankingSize(date: LocalDate): Long {
        val key = RankingKeyGenerator.generateDailyKey(date)
        val zSetOps = redisTemplate.opsForZSet()

        // ZCARD: 상품 개수 조회
        return zSetOps.size(key) ?: 0L
    }

    /**
     * TTL 설정 (키가 처음 생성될 때만)
     *
     * 왜 이렇게 구현했는가?
     * - 매번 TTL을 설정하면 불필요한 Redis 명령 실행
     * - GETEXPIRE로 TTL 확인 후 필요할 때만 설정
     *
     * 주의사항:
     * - TTL = -1: 키는 존재하지만 만료 시간 없음
     * - TTL = -2: 키가 존재하지 않음
     */
    private fun ensureTtl(key: String) {
        val ttl = redisTemplate.getExpire(key, TimeUnit.SECONDS)

        // TTL이 설정되지 않았을 때만 설정
        if (ttl == -1L) {
            redisTemplate.expire(key, TTL_SECONDS, TimeUnit.SECONDS)
            logger.info("TTL 설정: key=$key, ttl=${TTL_DAYS}일")
        }
    }
}
```

### ✅ 핵심 포인트
- **TTL 자동 관리**: `ensureTtl()`로 키 생성 시 자동 설정 (2일)
- **페이지네이션 지원**: `getProductsInRange()`로 API 페이징 구현 가능
- **명확한 메서드 네이밍**: Redis 명령어와 1:1 매핑으로 이해 쉬움
- **0-based 인덱스**: Redis ZREVRANK는 0부터 시작 (API에서 +1 변환 필요)

---

## 🎯 Step 1 완료 체크리스트

- [ ] `RankingKeyGenerator.kt` 파일 생성 및 컴파일 확인
- [ ] `RankingScoreCalculator.kt` 파일 생성 및 컴파일 확인
- [ ] `RankingService.kt` 파일 생성 및 컴파일 확인
- [ ] 각 클래스의 주석을 읽고 "왜 이렇게 설계했는지" 이해했는가?

---

## 📚 다음 단계 미리보기

**Step 2**에서는 이렇게 만든 도메인 로직을:
- Kafka Consumer에 연결
- 배치 처리로 성능 최적화
- **멱등성 보장** (Round 8 학습 내용 적용)

Step 1 완료하셨으면 다음 단계로 넘어가겠습니다! 👍
