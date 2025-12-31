# 🌟 Nice-to-Have: 콜드 스타트 방지 구현 가이드

> **목표**: 자정에 랭킹이 비어있는 콜드 스타트 문제를 Score Carry-Over로 해결합니다.

---

## 📌 콜드 스타트 문제란?

### 문제 상황

**시나리오**: 2025년 12월 26일 23:59:59 → 12월 27일 00:00:00

```
23:59:59 (12/26)
ranking:all:20251226 → 150개 상품, 1위 product:101 (점수 125.5)

00:00:01 (12/27)
ranking:all:20251227 → 0개 상품 (비어있음!)
```

**문제점**:
- ❌ 사용자가 00:10에 랭킹 조회 → 빈 결과 반환
- ❌ 전날 1위였던 상품도, 신상품도 모두 0점에서 시작
- ❌ 이벤트가 쌓일 때까지 랭킹 서비스 무용지물

### 해결 방안: Score Carry-Over

**전략**: 매일 **23:50**에 오늘 점수의 **10%**를 내일 키로 미리 복사

```
23:50:00 (12/26) - Scheduler 실행
ranking:all:20251226 → product:101 (점수 125.5)
ranking:all:20251227 → product:101 (점수 12.55)  # 125.5 * 0.1

00:00:01 (12/27) - 사용자 조회
ranking:all:20251227 → product:101 (1위, 점수 12.55)
→ 빈 결과가 아닌 전날 인기 상품 노출!

08:00:00 (12/27) - 이벤트 누적
ranking:all:20251227 → product:202 (1위, 점수 50.0)  # 역전!
                     → product:101 (2위, 점수 15.0)  # 12.55 + 추가 점수
```

**효과**:
- ✅ 새벽 시간대에도 랭킹 조회 가능
- ✅ 전날 인기 상품에 소량의 가산점 (공정성 유지)
- ✅ 오늘 이벤트가 쌓이면 금방 역전 가능 (가중치가 낮으므로)

---

## 🛠️ Step 1: RankingService에 carryOverScores 메서드 추가

### 파일 위치
`modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt`

### 구현 코드

기존 `RankingService` 클래스에 다음 메서드를 **추가**하세요:

```kotlin
/**
 * 전날 점수를 다음 날 키로 복사 (Cold Start 방지)
 *
 * 동작 방식:
 * 1. 원본 키(sourceDate)의 모든 상품 점수 조회
 * 2. 각 점수에 가중치(기본 10%) 곱하기
 * 3. 대상 키(targetDate)에 복사
 * 4. TTL 자동 설정 (2일)
 *
 * 주의사항:
 * - 대상 키가 이미 존재하면 건너뜀 (이벤트가 이미 발생한 경우)
 * - 원본 키가 비어있으면 건너뜀
 *
 * @param sourceDate 복사할 원본 날짜 (보통 오늘)
 * @param targetDate 복사 대상 날짜 (보통 내일)
 * @param weight 가중치 (0.0 ~ 1.0, 기본값 0.1 = 10%)
 * @return 복사된 상품 개수
 */
fun carryOverScores(
    sourceDate: LocalDate,
    targetDate: LocalDate,
    weight: Double = 0.1
): Long {
    val sourceKey = RankingKeyGenerator.generateDailyKey(sourceDate)
    val targetKey = RankingKeyGenerator.generateDailyKey(targetDate)

    logger.info("랭킹 Score Carry-Over 시작: $sourceKey → $targetKey (weight=$weight)")

    val zSetOps = redisTemplate.opsForZSet()

    // 1. 원본 키 존재 확인
    val sourceSize = zSetOps.size(sourceKey) ?: 0L
    if (sourceSize == 0L) {
        logger.warn("원본 랭킹 키가 비어있음: sourceKey=$sourceKey")
        return 0L
    }

    // 2. 대상 키 존재 확인 (이미 이벤트가 발생했을 수 있음)
    val targetExists = redisTemplate.hasKey(targetKey) ?: false
    if (targetExists) {
        logger.info("대상 랭킹 키가 이미 존재함: targetKey=$targetKey (Carry-Over 건너뜀)")
        return 0L
    }

    // 3. 모든 데이터 조회 후 가중치 적용하여 복사
    val allEntries = zSetOps.reverseRangeWithScores(sourceKey, 0, -1) ?: emptySet()

    var copiedCount = 0L
    allEntries.forEach { tuple ->
        val member = tuple.value ?: return@forEach
        val score = tuple.score ?: return@forEach
        val newScore = score * weight

        // 대상 키에 가중치 적용한 점수로 추가
        zSetOps.add(targetKey, member, newScore)
        copiedCount++
    }

    // 4. TTL 설정 (2일)
    ensureTtl(targetKey)

    logger.info(
        "✅ 랭킹 Score Carry-Over 완료: " +
        "$sourceKey → $targetKey, weight=$weight, copied=$copiedCount/$sourceSize"
    )

    return copiedCount
}
```

### 핵심 포인트

- **가중치 10%**: 전날 100점 → 오늘 10점으로 복사
- **대상 키 존재 체크**: 이미 이벤트가 발생했으면 건너뜀 (덮어쓰기 방지)
- **ZSET 범위 조회**: `reverseRangeWithScores(key, 0, -1)` = 모든 데이터
- **TTL 자동 설정**: 복사된 키도 2일 후 자동 만료

---

## 🛠️ Step 2: Scheduler 구현

### 파일 생성
`apps/commerce-streamer/src/main/kotlin/com/loopers/infrastructure/ranking/RankingColdStartScheduler.kt`

### 구현 코드

```kotlin
package com.loopers.infrastructure.ranking

import com.loopers.domain.ranking.RankingService
import org.slf4j.LoggerFactory
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import java.time.LocalDate

/**
 * 랭킹 콜드 스타트 방지 Scheduler
 *
 * 역할:
 * - 매일 23:50에 오늘 점수의 10%를 내일 키로 미리 복사
 * - 자정에 랭킹이 비어있는 문제 해결
 *
 * 실행 시각: 23:50 (cron: "0 50 23 * * *")
 *
 * 동작 흐름:
 * 1. 23:50에 자동 실행
 * 2. ranking:all:20251226 → ranking:all:20251227 복사 (10% 가중치)
 * 3. 00:00 이후 사용자가 조회해도 전날 인기 상품 표시
 * 4. 오늘 이벤트가 쌓이면 순위 자연스럽게 변경
 */
@Component
class RankingColdStartScheduler(
    private val rankingService: RankingService
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    companion object {
        private const val CARRY_OVER_WEIGHT = 0.1  // 10% 가중치
    }

    /**
     * 매일 23:50에 다음 날 랭킹 초기화
     *
     * Cron 표현식 설명:
     * "0 50 23 * * *"
     *  ↑  ↑  ↑ ↑ ↑ ↑
     *  초 분 시 일 월 요일
     *
     * - 0초 50분 23시 = 23:50:00
     * - * = 모든 일, 모든 월, 모든 요일
     *
     * 테스트용 (1분마다 실행):
     * "0 * * * * *"
     */
    @Scheduled(cron = "0 50 23 * * *")
    fun carryOverDailyScores() {
        try {
            val today = LocalDate.now()
            val tomorrow = today.plusDays(1)

            logger.info("🌙 랭킹 Score Carry-Over 시작: $today → $tomorrow")

            // 오늘 점수의 10%를 내일 키로 복사
            val copiedCount = rankingService.carryOverScores(
                sourceDate = today,
                targetDate = tomorrow,
                weight = CARRY_OVER_WEIGHT
            )

            if (copiedCount > 0) {
                logger.info(
                    "✅ 랭킹 Score Carry-Over 성공: " +
                    "$copiedCount개 상품 복사 ($today → $tomorrow, weight=$CARRY_OVER_WEIGHT)"
                )
            } else {
                logger.warn(
                    "⚠️ 랭킹 Score Carry-Over: copiedCount=0 " +
                    "(원본 키가 비어있거나 대상 키가 이미 존재함)"
                )
            }

        } catch (e: Exception) {
            logger.error("❌ 랭킹 Score Carry-Over 실패: ${e.message}", e)
            // 실패해도 서비스 중단되지 않도록 예외를 삼킴
            // 다음 날 다시 시도됨
        }
    }

    /**
     * 테스트용: 수동 실행 메서드
     *
     * 사용 방법:
     * - 테스트 코드에서 @Autowired로 주입 후 executeNow() 호출
     * - 또는 로컬 환경에서 API 엔드포인트로 노출하여 테스트
     */
    fun executeNow() {
        logger.info("🔧 수동 실행: 랭킹 Score Carry-Over")
        carryOverDailyScores()
    }
}
```

### Cron 표현식 이해하기

| 표현식 | 의미 | 예시 |
|--------|------|------|
| `0 50 23 * * *` | 매일 23:50:00 | 운영 환경 |
| `0 * * * * *` | 매 분 0초 (1분마다) | 로컬 테스트 |
| `0 0 0 * * *` | 매일 자정 00:00:00 | 일일 배치 |
| `0 0 6 * * MON` | 매주 월요일 06:00 | 주간 배치 |

---

## 🛠️ Step 3: @EnableScheduling 활성화

### 파일 수정
`apps/commerce-streamer/src/main/kotlin/com/loopers/CommerceStreamerApplication.kt`

### 수정 사항

**Before**:
```kotlin
package com.loopers

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.context.properties.ConfigurationPropertiesScan
import org.springframework.boot.runApplication

@ConfigurationPropertiesScan
@SpringBootApplication
class CommerceStreamerApplication

fun main(args: Array<String>) {
    runApplication<CommerceStreamerApplication>(*args)
}
```

**After**:
```kotlin
package com.loopers

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.context.properties.ConfigurationPropertiesScan
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling  // 추가

@EnableScheduling  // 스케줄링 활성화 (추가)
@ConfigurationPropertiesScan
@SpringBootApplication
class CommerceStreamerApplication

fun main(args: Array<String>) {
    runApplication<CommerceStreamerApplication>(*args)
}
```

### 핵심 포인트

- `@EnableScheduling`: Spring의 `@Scheduled` 어노테이션 활성화
- 이 어노테이션이 없으면 Scheduler가 동작하지 않음

---

## 🧪 Step 4: 테스트

### 4-1. 로컬 환경 즉시 테스트

Cron을 23:50까지 기다릴 수 없으므로, **수동 실행 또는 Cron 변경**으로 테스트합니다.

#### 방법 1: 수동 실행 (권장)

**테스트 코드 작성**:
`apps/commerce-streamer/src/test/kotlin/com/loopers/infrastructure/ranking/RankingColdStartSchedulerTest.kt`

```kotlin
package com.loopers.infrastructure.ranking

import com.loopers.domain.ranking.RankingKeyGenerator
import com.loopers.domain.ranking.RankingService
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.data.redis.core.RedisTemplate
import org.springframework.test.context.ActiveProfiles
import java.time.LocalDate

@SpringBootTest
@ActiveProfiles("test")
class RankingColdStartSchedulerTest {

    @Autowired
    private lateinit var scheduler: RankingColdStartScheduler

    @Autowired
    private lateinit var redisTemplate: RedisTemplate<String, String>

    @Autowired
    private lateinit var rankingService: RankingService

    @Test
    fun `콜드 스타트 방지 - 수동 실행 테스트`() {
        // given: 오늘 랭킹 데이터 준비
        val today = LocalDate.now()
        val todayKey = RankingKeyGenerator.generateDailyKey(today)

        // 테스트 데이터 삽입
        redisTemplate.opsForZSet().add(todayKey, "product:101", 100.0)
        redisTemplate.opsForZSet().add(todayKey, "product:202", 80.0)
        redisTemplate.opsForZSet().add(todayKey, "product:303", 60.0)

        println("✅ 오늘 랭킹 데이터 준비 완료: $todayKey")

        // when: 스케줄러 수동 실행
        scheduler.executeNow()

        // then: 내일 키 확인
        val tomorrow = today.plusDays(1)
        val tomorrowKey = RankingKeyGenerator.generateDailyKey(tomorrow)

        val tomorrowData = redisTemplate.opsForZSet()
            .reverseRangeWithScores(tomorrowKey, 0, -1)

        println("✅ 내일 랭킹 데이터:")
        tomorrowData?.forEach { tuple ->
            println("  - ${tuple.value}: ${tuple.score} (원본의 10%)")
        }

        // 검증
        assert(tomorrowData?.size == 3)
        assert(tomorrowData?.first()?.score == 10.0)  // 100 * 0.1
    }
}
```

**실행 방법**:
```bash
cd apps/commerce-streamer
./gradlew test --tests RankingColdStartSchedulerTest
```

#### 방법 2: Cron 변경 (1분마다 실행)

**Scheduler 임시 수정**:
```kotlin
// @Scheduled(cron = "0 50 23 * * *")  // 운영용
@Scheduled(cron = "0 * * * * *")  // 테스트용: 1분마다 실행
fun carryOverDailyScores() {
    // ...
}
```

**실행 후 로그 확인**:
```
2025-12-26 09:00:00 INFO  - 🌙 랭킹 Score Carry-Over 시작: 2025-12-26 → 2025-12-27
2025-12-26 09:00:00 INFO  - ✅ 랭킹 Score Carry-Over 성공: 150개 상품 복사 (2025-12-26 → 2025-12-27, weight=0.1)
```

---

### 4-2. Redis 데이터 검증

```bash
# Redis CLI 접속
docker exec -it redis-master redis-cli

# 1. 오늘 랭킹 확인
> ZREVRANGE ranking:all:20251226 0 4 WITHSCORES
1) "product:101"
2) "125.5"
3) "product:202"
4) "98.3"
5) "product:303"
6) "85.0"

# 2. 내일 랭킹 확인 (Scheduler 실행 후)
> ZREVRANGE ranking:all:20251227 0 4 WITHSCORES
1) "product:101"
2) "12.55"     # 125.5 * 0.1 = 12.55 ✅
3) "product:202"
4) "9.83"      # 98.3 * 0.1 = 9.83 ✅
5) "product:303"
6) "8.5"       # 85.0 * 0.1 = 8.5 ✅

# 3. TTL 확인 (2일 = 172800초)
> TTL ranking:all:20251227
(integer) 172750

# 4. 전체 개수 확인
> ZCARD ranking:all:20251227
(integer) 150  # 오늘과 동일한 개수
```

---

### 4-3. API로 검증

```bash
# 내일 날짜 랭킹 조회 (Scheduler 실행 후)
curl -X GET "http://localhost:8080/api/v1/rankings?date=20251227&page=0&size=10"
```

**예상 응답**:
```json
{
  "success": true,
  "data": {
    "content": [
      {
        "productId": 101,
        "productName": "나이키 에어맥스",
        "rank": 1,
        "score": 12.55  // 원본의 10%
      },
      {
        "productId": 202,
        "productName": "아디다스 슈퍼스타",
        "rank": 2,
        "score": 9.83
      }
    ],
    "totalElements": 150
  }
}
```

---

## 🎯 Step 5: 운영 환경 배포 전 체크리스트

### 필수 확인 사항

- [ ] `RankingService.carryOverScores()` 메서드 추가 완료
- [ ] `RankingColdStartScheduler` 클래스 생성 완료
- [ ] `@EnableScheduling` 어노테이션 추가 완료
- [ ] Cron 표현식이 **운영용** (`0 50 23 * * *`)으로 설정되어 있는지 확인
- [ ] 로컬 테스트 완료 (수동 실행 또는 1분 Cron)
- [ ] Redis에서 내일 키 생성 확인
- [ ] 가중치 10% 적용 확인 (원본 100점 → 복사본 10점)
- [ ] TTL 2일 설정 확인

### 운영 환경 모니터링

**로그 확인**:
```bash
# 매일 23:50 로그 확인
tail -f /var/log/commerce-streamer.log | grep "Score Carry-Over"

# 성공 로그
2025-12-26 23:50:00 INFO  - 🌙 랭킹 Score Carry-Over 시작: 2025-12-26 → 2025-12-27
2025-12-26 23:50:01 INFO  - ✅ 랭킹 Score Carry-Over 성공: 150개 상품 복사

# 실패 로그 (원본 키가 비어있는 경우)
2025-12-26 23:50:00 WARN  - 원본 랭킹 키가 비어있음: sourceKey=ranking:all:20251226
```

---

## 📊 기대 효과

### Before (콜드 스타트 방지 없음)

```
00:00 - 00:10 사이 사용자 조회
GET /api/v1/rankings

Response:
{
  "content": [],       // 빈 결과
  "totalElements": 0
}
→ 사용자 이탈 발생
```

### After (콜드 스타트 방지 적용)

```
00:00 - 00:10 사이 사용자 조회
GET /api/v1/rankings

Response:
{
  "content": [
    {"rank": 1, "score": 12.55},  // 전날 1위 상품 (10%)
    {"rank": 2, "score": 9.83}    // 전날 2위 상품 (10%)
  ],
  "totalElements": 150
}
→ 사용자 만족도 향상
```

---

## 🤔 추가 고려사항

### 1. 가중치 조정

현재 10%로 설정되어 있지만, 비즈니스 요구에 따라 조정 가능:

| 가중치 | 효과 | 권장 시나리오 |
|--------|------|---------------|
| 5% | 오늘 이벤트의 영향력 ↑ | 신상품 우대 전략 |
| 10% | 균형 잡힌 설정 | 일반적인 경우 |
| 20% | 전날 인기 상품 우대 ↑ | 안정적인 랭킹 선호 |

### 2. 실행 시각 조정

| 시각 | 장점 | 단점 |
|------|------|------|
| 23:50 | 자정 직전 준비 완료 | 트래픽이 많을 수 있음 |
| 23:30 | 여유 있는 준비 | 23:30~00:00 사이 이벤트 누락 |
| 00:05 | 자정 이후 즉시 생성 | 00:00~00:05 사이 빈 결과 |

### 3. 에러 처리 전략

**현재**: 예외 발생 시 로그만 남기고 계속 진행
```kotlin
catch (e: Exception) {
    logger.error("❌ 랭킹 Score Carry-Over 실패: ${e.message}", e)
    // 서비스 중단 없음, 다음 날 다시 시도
}
```

**개선안**: Slack/Discord 알림 추가
```kotlin
catch (e: Exception) {
    logger.error("❌ 랭킹 Score Carry-Over 실패: ${e.message}", e)
    slackNotifier.sendAlert("랭킹 콜드 스타트 방지 실패: ${e.message}")
}
```

---

## 🎉 완료!

축하합니다! 이제 콜드 스타트 방지 기능이 완성되었습니다.

**다음 단계**:
1. 로컬 테스트 완료 확인
2. 운영 환경 배포
3. 매일 23:50 로그 모니터링
4. Technical Writing에 구현 과정 기록

**궁금한 점**:
- 왜 10%인가? → 실험적 값, A/B 테스트로 최적화 가능
- ZUNIONSTORE는 왜 안 쓰나? → Spring Data Redis API 호환성
- Redis 장애 시? → 다음 날 다시 시도, 서비스는 정상 동작

화이팅! 🚀
