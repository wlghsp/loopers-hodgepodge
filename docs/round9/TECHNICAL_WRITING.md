# Redis ZSET으로 실시간 랭킹 시스템 구현하기

> **TL;DR**: 카프카 이벤트 스트림을 Redis ZSET으로 집계하여 O(logN) 조회 성능의 실시간 랭킹 시스템을 구현했습니다. 시간 양자화로 롱테일 문제를 해결하고, 로그 정규화로 고가 상품의 점수 독점을 방지했습니다. 날짜별/상품별 그룹화 전략으로 Redis 연산을 최소화하여 성능을 최적화했습니다.

---

## 1. 문제 정의

단순히 조회수나 주문 건수만으로 랭킹을 매기면 다음과 같은 문제가 발생합니다:

- **조회만 많고 구매는 없는 상품**: 실제 인기 상품인지 불분명
- **가격이 비싼 상품 하나 vs 저렴한 상품 100개**: 어떤 게 더 인기있는지 판단 어려움
- **어제 인기였던 상품이 오늘도 계속 1위**: 롱테일 문제로 신상품 진입 불가

이를 해결하기 위해 **이벤트 가중치 기반의 실시간 랭킹 시스템**을 구현했습니다.

---

## 2. 기술 선택: MySQL이 아닌 Redis ZSET을 선택한 이유

처음엔 MySQL의 `product_metrics` 테이블로 집계하는 방법을 고려했습니다.

```sql
SELECT product_id, view_count + like_count + order_count AS score
FROM product_metrics
WHERE date = '2025-12-26'
ORDER BY score DESC
LIMIT 10;
```

하지만 몇 가지 문제가 있었습니다:

### 문제 1: 성능
- 매번 `ORDER BY`로 전체 스캔 필요
- 인덱스를 써도 `score` 계산이 런타임에 발생
- 사용자 요청마다 정렬 비용 발생

### 문제 2: 실시간성
- 이벤트 발생 → DB 업데이트 → 조회 시점에 정렬
- 캐싱을 하면 실시간성 저하
- TTL 관리도 수동으로 해야 함

### Redis ZSET의 장점

Redis ZSET은 **이미 정렬된 상태로 데이터를 유지**합니다.

```kotlin
// 점수 증가 (O(logN))
ZINCRBY ranking:all:20251226 0.1 "product:101"

// Top 10 조회 (O(logN + M), M=10)
ZREVRANGE ranking:all:20251226 0 9 WITHSCORES
```

**시간 복잡도 비교:**

| 작업 | MySQL | Redis ZSET |
|------|-------|------------|
| 점수 증가 | O(1) UPDATE | O(log(N)) ZINCRBY |
| Top N 조회 | O(N logN) 매번 정렬 | O(log(N) + M) 이미 정렬됨 |
| 순위 조회 | O(N logN) | O(log(N)) ZREVRANK |
| 실시간성 | 낮음 (쿼리 비용) | 높음 (인메모리) |

**결론**: 조회가 빈번한 랭킹 시스템에서는 Redis ZSET이 압도적으로 유리합니다.

---

## 3. 시간 양자화: "롱테일 문제"를 어떻게 해결했나?

### 문제: 누적 랭킹의 함정

처음엔 단순하게 생각했습니다. "상품별로 점수를 계속 누적하면 되지 않나?"

```kotlin
// 나쁜 예: 계속 누적
ZINCRBY ranking:all 0.1 "product:101"  // 키가 하나, 계속 쌓임
```

하지만 이렇게 하면 **롱테일 문제**가 발생합니다:
- 1개월 전에 인기였던 상품이 계속 1위
- 어제 출시된 신상품은 영원히 순위권 진입 불가
- 트렌드 변화를 반영할 수 없음

### 해결: 일 단위 키 분리

"시간을 쪼개서 독립적인 랭킹을 만들자."

```kotlin
object RankingKeyGenerator {
    fun generateDailyKey(date: LocalDate): String {
        val dateString = date.format(DateTimeFormatter.BASIC_ISO_DATE)
        return "ranking:all:$dateString"  // ranking:all:20251226
    }
}
```

**일 단위 키 전략의 장점:**
- 매일 새로운 랭킹판이 생성됨
- 어제의 1위가 오늘도 1위라는 보장 없음
- 신상품도 공정하게 경쟁 가능

**TTL 2일 설정:**
```kotlin
companion object {
    private const val TTL_DAYS = 2L  // 2일 TTL
}

private fun ensureTtl(key: String) {
    val ttl = redisTemplate.getExpire(key, TimeUnit.SECONDS)

    // TTL이 설정되지 않았을 때만 설정
    if (ttl == -1L) {
        redisTemplate.expire(key, TTL_SECONDS, TimeUnit.SECONDS)
    }
}
```

**왜 2일인가?**
- 오늘 랭킹 조회: `ranking:all:20251226`
- 어제 랭킹 비교: `ranking:all:20251225`
- 2일 이전 데이터는 불필요 → 자동 삭제로 메모리 절약

연속적인 시간을 일 단위로 **쪼개서(양자화)** 각각 독립적으로 관리하는 방식입니다.

---

## 4. 공정한 점수 계산: 고가 상품 독점을 막는 방법

### 문제: 100만원 상품 하나 vs 1만원 상품 100개

랭킹에 주문 금액을 반영하려고 했는데, 단순히 금액을 더하면 문제가 생깁니다.

**선형 계산의 문제:**
```kotlin
// 나쁜 예
주문 점수 = 0.6 × (price × quantity)

100만원 상품 1개 주문 = 600,000점
1만원 상품 100개 주문 = 600,000점  // 동일??
```

100명이 구매한 상품과 1명만 구매한 상품이 같은 점수? 이건 아닙니다.

### 해결: 로그 정규화

자연로그를 사용하면 큰 값의 영향력을 완화할 수 있습니다.

```kotlin
fun calculateOrderItemScore(orderItem: OrderItemDto): Double {
    val orderValue = orderItem.price * orderItem.quantity
    return WEIGHT_ORDER * ln(1.0 + orderValue)
}
```

**실제 계산 비교:**

| 시나리오 | 선형 점수 | 로그 정규화 점수 |
|---------|----------|----------------|
| 1만원 × 1개 | 6,000 | 0.6 × ln(10,001) ≈ 5.52 |
| 1만원 × 100개 | 600,000 | 0.6 × ln(1,000,001) ≈ 8.29 |
| 100만원 × 1개 | 600,000 | 0.6 × ln(1,000,001) ≈ 8.29 |
| 1만원 × 1000개 | 6,000,000 | 0.6 × ln(10,000,001) ≈ 9.63 |

**효과:**
- 구매 횟수가 많을수록 점수 증가 (1000개 > 100개)
- 고가 상품의 이점도 일부 반영 (100만원 = 1만원×100)
- 하지만 고가 상품이 점수를 독점하지는 못함

**ln(1 + x)를 사용하는 이유:**
1. **x=0일 때 안전**: ln(1) = 0 (에러 방지)
2. **큰 값 완화**: 가격이 10배 차이나도 점수는 2~3배 차이
3. **자연스러운 증가**: 구매가 늘수록 점수도 증가하지만, 체감은 감소

### 이벤트별 가중치 설정

```kotlin
companion object {
    private const val WEIGHT_VIEW = 0.1      // 조회: 관심의 시작
    private const val WEIGHT_LIKE = 0.2      // 좋아요: 적극적인 관심
    private const val WEIGHT_UNLIKE = -0.2   // 취소: 마이너스
    private const val WEIGHT_ORDER = 0.6     // 주문: 실질적 구매 (가장 중요)
}
```

**왜 이 비율인가?**

각 이벤트의 비즈니스 가치를 고려하여 가중치를 설정했습니다:

1. **조회 (0.1)**: 가장 빈번하게 발생하는 이벤트. 관심의 시작이지만 구매로 이어지는 비율이 낮음
2. **좋아요 (0.2)**: 조회보다 능동적인 행동. 재방문 의사를 나타냄
3. **주문 (0.6)**: 실제 매출과 직결되는 가장 중요한 지표
4. **좋아요 취소 (-0.2)**: 관심도 감소를 반영. 스팸 방지 효과

**비율의 의미**: 조회 10번 ≈ 주문 1번 + 좋아요 2번

처음엔 주문 가중치를 1.0으로 설정했으나, 테스트 결과 주문 1건이 조회 100번을 압도하여 0.6으로 조정했습니다. 이를 통해 조회와 주문 모두 의미 있게 반영되도록 균형을 맞췄습니다.

---

## 5. 날짜별/상품별 그룹화로 Redis 연산 최소화

배치로 받은 이벤트를 처리할 때, 날짜별/상품별로 그룹화하여 Redis 연산을 최소화했습니다.

```kotlin
// RankingEventFacade.kt
@Transactional
fun handleBatchEvents(events: List<DomainEvent>) {
    // 1. 멱등성 체크 (생략)

    // 2. 날짜별로 그룹화
    val eventsByDate = eventsToProcess.groupBy { event ->
        LocalDate.ofInstant(event.occurredAt, ZoneId.systemDefault())
    }

    // 3. 날짜별로 처리
    eventsByDate.forEach { (date, dateEvents) ->
        processEventsForDate(date, dateEvents)
    }
}

private fun processEventsForDate(date: LocalDate, events: List<DomainEvent>) {
    // 상품별로 점수 합산
    val scoresByProduct = mutableMapOf<Long, Double>()

    events.forEach { event ->
        val score = rankingScoreCalculator.calculateScore(event)
        scoresByProduct[event.productId] =
            scoresByProduct.getOrDefault(event.productId, 0.0) + score
    }

    // 한 번에 Redis 업데이트
    scoresByProduct.forEach { (productId, totalScore) ->
        rankingService.incrementScore(date, productId, totalScore)
    }
}
```

**그룹화 전략:**
1. 날짜별 그룹화: `ranking:all:20251226`, `ranking:all:20251225` 등
2. 상품별 점수 합산: 같은 상품의 이벤트를 먼저 합침
3. Redis에 한 번에 반영: 네트워크 왕복 최소화

**성능 개선:**

| 이벤트 수 | 그룹화 전 Redis 연산 | 그룹화 후 Redis 연산 |
|---------|-------------------|-------------------|
| 1000개 | 1000회 | ~100회 (상품 100개 가정) |


---

## 6. 실시간 Weight 조절: 설정 기반 가중치 관리

### 왜 필요한가?

처음엔 가중치를 코드에 하드코딩했습니다:

```kotlin
companion object {
    private const val WEIGHT_VIEW = 0.1
    private const val WEIGHT_LIKE = 0.2
    private const val WEIGHT_ORDER = 0.6
}
```

**문제:**
- 가중치 변경 시 코드 수정 필요
- 배포 없이 실시간 조정 불가
- A/B 테스트 어려움

### 해결: ConfigurationProperties

```kotlin
@Component
class RankingScoreCalculator(
    private val weights: RankingWeights
) {
    fun calculateScore(event: DomainEvent): Double {
        return when (event) {
            is ProductViewedEvent -> weights.view
            is ProductLikedEvent -> weights.like
            is OrderCreatedEvent -> weights.order * ln(1.0 + orderValue)
            else -> 0.0
        }
    }
}

@ConfigurationProperties(prefix = "ranking.weights")
data class RankingWeights(
    val view: Double = 0.1,
    val like: Double = 0.2,
    val unlike: Double = -0.2,
    val order: Double = 0.6
)
```

**application.yml:**
```yaml
ranking:
  weights:
    view: 0.1
    like: 0.2
    unlike: -0.2
    order: 0.6
```

**장점:**
1. **실시간 조정**: 서버 재시작만으로 가중치 변경
2. **환경별 설정**: 개발/운영 환경마다 다른 가중치 사용
3. **A/B 테스트**: 인스턴스별로 다른 가중치 적용 가능

---

## 7. 콜드 스타트 방지: 자정에도 랭킹이 비어있지 않게

### 문제: 일 단위 키의 부작용

일 단위 키 분리는 롱테일 문제를 해결했지만, 새로운 문제가 생겼습니다.

**자정 직후 문제:**
```
23:59 → ranking:all:20251226 (100개 상품, 점수 있음)
00:00 → ranking:all:20251227 (비어있음!)
```

사용자가 자정 직후에 랭킹을 조회하면 **빈 페이지**를 보게 됩니다.

### 해결: Score Carry-Over 스케줄러

매일 23:50에 오늘 점수의 10%를 내일 키로 미리 복사합니다.

```kotlin
// RankingColdStartScheduler.kt
@Component
class RankingColdStartScheduler(
    private val rankingService: RankingService
) {
    companion object {
        private const val CARRY_OVER_WEIGHT = 0.1  // 10% 가중치
    }

    @Scheduled(cron = "0 50 23 * * *")  // 매일 23:50 실행
    fun carryOverDailyScores() {
        try {
            val today = LocalDate.now()
            val tomorrow = today.plusDays(1)

            logger.info("랭킹 Score Carry-Over 시작: $today → $tomorrow")

            // 오늘 점수의 10%를 내일 키로 복사
            val copiedCount = rankingService.carryOverScores(
                today, tomorrow, CARRY_OVER_WEIGHT
            )

            if (copiedCount > 0) {
                logger.info("랭킹 Score Carry-Over 성공: ${copiedCount}개 상품")
            }
        } catch (e: Exception) {
            logger.error("랭킹 Score Carry-Over 실패: ${e.message}", e)
        }
    }
}

// RankingService.kt
fun carryOverScores(
    sourceDate: LocalDate,
    targetDate: LocalDate,
    weight: Double = 0.1
): Long {
    val sourceKey = RankingKeyGenerator.generateDailyKey(sourceDate)
    val targetKey = RankingKeyGenerator.generateDailyKey(targetDate)

    // 1. 원본 키 존재 확인
    val sourceSize = zSetOps.size(sourceKey) ?: 0L
    if (sourceSize == 0L) {
        logger.warn("원본 랭킹 키가 비어있음: $sourceKey")
        return 0L
    }

    // 2. 대상 키가 이미 존재하면 건너뜀
    if (redisTemplate.hasKey(targetKey) == true) {
        logger.info("대상 랭킹 키가 이미 존재함: $targetKey (건너뜀)")
        return 0L
    }

    // 3. 모든 데이터를 가중치 적용하여 복사
    val allEntries = zSetOps.reverseRangeWithScores(sourceKey, 0, sourceSize - 1)
    var copiedCount = 0L

    allEntries.forEach { tuple ->
        val member = tuple.value ?: return@forEach
        val score = tuple.score ?: return@forEach
        val newScore = score * weight  // 10% 점수

        // 대상 키에 member가 없을 때만 추가 (실시간 이벤트가 먼저 추가된 경우 보존)
        val currentScore = zSetOps.score(targetKey, member)
        if (currentScore == null) {
            zSetOps.add(targetKey, member, newScore)
            copiedCount++
        }
    }

    // 4. TTL 설정
    ensureTtl(targetKey)

    logger.info("$sourceKey → $targetKey, copied=$copiedCount")
    return copiedCount
}
```

### 동작 방식

```
23:50 실행 → ranking:all:20251226 (100점, 80점, 60점...)
            ↓ 10% 복사
            ranking:all:20251227 (10점, 8점, 6점...)

00:00 이후 → 내일 키에 이미 데이터 존재 (빈 페이지 X)
오전 중    → 새 이벤트 쌓이면서 순위 자연스럽게 변경
```

### 10% 가중치

50%로 하면 전날 순위가 너무 오래 유지되고, 1%로 하면 콜드 스타트 해결이 안됩니다. 10%는 초기 씨드로 적당하면서도 오전 중 실제 인기 상품으로 쉽게 역전됩니다.

---

## 8. 성과

### 구현 완료
- Redis ZSET 기반 랭킹 시스템
- 시간 양자화 (일 단위 키 분리)
- 로그 정규화 점수 계산
- 이벤트 가중치 시스템
- 콜드 스타트 방지 스케줄러
- Ranking API

### 성능
- Top 10 조회 O(logN)으로 빠른 조회
- 배치 처리 시 그룹화로 Redis 연산 최소화 (1000개 이벤트 → ~100회)
- TTL 자동 관리로 메모리 효율

---

## 9. 배운 점

1. **Redis ZSET**: 이미 정렬된 상태를 유지해서 조회 성능이 압도적으로 빠릅니다.
2. **시간 양자화**: 일 단위 키 분리로 롱테일 문제를 해결할 수 있습니다.
3. **로그 정규화**: 고가 상품이 너무 유리하지 않게 공정한 점수 계산이 가능합니다.
4. **콜드 스타트 해결**: 스케줄러로 자정에도 랭킹이 비지 않게 할 수 있습니다.

---

## 10. 마무리

롱테일 문제는 시간 양자화로, 공정성 문제는 로그 정규화로, 콜드 스타트 문제는 스케줄러로 해결했습니다. Redis ZSET을 활용해서 단순하면서도 빠른 랭킹 시스템을 구현할 수 있었습니다.

---

**작성자**: Jiho Choi
**작성일**: 2025-12-26
**프로젝트**: Loopers E-Commerce
