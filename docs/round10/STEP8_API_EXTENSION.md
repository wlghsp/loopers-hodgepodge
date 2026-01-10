# Step 8: Ranking API 확장

> period 파라미터로 일간/주간/월간 랭킹 선택

---

## 8.1 RankingPeriod Enum 생성

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingPeriod.kt`

```kotlin
package com.loopers.application.ranking

import com.loopers.support.DateUtils
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import java.time.LocalDate
import java.time.format.DateTimeFormatter

enum class RankingPeriod {
    DAILY {
        override fun formatDate(date: String?): String =
            date ?: LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE)

        override fun getRankings(
            date: String?,
            pageable: Pageable,
            facade: RankingFacade
        ): Page<RankingInfo> =
            facade.getRankings(formatDate(date), pageable)
    },
    WEEKLY {
        override fun formatDate(date: String?): String =
            date ?: DateUtils.toYearWeek(LocalDate.now())

        override fun getRankings(
            date: String?,
            pageable: Pageable,
            facade: RankingFacade
        ): Page<RankingInfo> =
            facade.getWeeklyRankings(formatDate(date), pageable)
    },
    MONTHLY {
        override fun formatDate(date: String?): String =
            date ?: DateUtils.toYearMonth(LocalDate.now())

        override fun getRankings(
            date: String?,
            pageable: Pageable,
            facade: RankingFacade
        ): Page<RankingInfo> =
            facade.getMonthlyRankings(formatDate(date), pageable)
    };

    abstract fun formatDate(date: String?): String
    abstract fun getRankings(
        date: String?,
        pageable: Pageable,
        facade: RankingFacade
    ): Page<RankingInfo>

    companion object {
        fun from(period: String): RankingPeriod = try {
            valueOf(period.uppercase())
        } catch (e: IllegalArgumentException) {
            DAILY
        }
    }
}
```

**설명**:
- 각 enum 상수가 날짜 포맷팅과 Facade 호출 로직을 캡슐화
- Controller는 `period.getRankings(date, pageable, facade)` 한 줄로 처리
- Strategy Pattern 적용으로 when 분기 제거

---

## 8.2 공통 모듈 Entity 사용

**중요**: Entity는 이미 `modules/jpa`에 정의되어 있으므로 복사할 필요 없습니다!

- `ProductRankWeekly`: [modules/jpa/src/main/kotlin/com/loopers/domain/ranking/ProductRankWeekly.kt](modules/jpa/src/main/kotlin/com/loopers/domain/ranking/ProductRankWeekly.kt)
- `ProductRankMonthly`: [modules/jpa/src/main/kotlin/com/loopers/domain/ranking/ProductRankMonthly.kt](modules/jpa/src/main/kotlin/com/loopers/domain/ranking/ProductRankMonthly.kt)

`commerce-api`는 `modules/jpa`를 이미 의존하고 있으므로 바로 사용 가능합니다.

---

## 8.3 Repository 생성

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/ranking/ProductRankWeeklyRepository.kt`

```kotlin
package com.loopers.infrastructure.ranking

import com.loopers.domain.ranking.ProductRankWeekly
import org.springframework.data.jpa.repository.JpaRepository

interface ProductRankWeeklyRepository : JpaRepository<ProductRankWeekly, Long> {
    fun findByYearWeekOrderByRankPositionAsc(yearWeek: String): List<ProductRankWeekly>
}
```

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/ranking/ProductRankMonthlyRepository.kt`

```kotlin
package com.loopers.infrastructure.ranking

import com.loopers.domain.ranking.ProductRankMonthly
import org.springframework.data.jpa.repository.JpaRepository

interface ProductRankMonthlyRepository : JpaRepository<ProductRankMonthly, Long> {
    fun findByYearMonthOrderByRankPositionAsc(yearMonth: String): List<ProductRankMonthly>
}
```

**주의**: `commerce-batch`와 동일한 Repository이므로, 공통 모듈로 분리하는 것도 고려할 수 있습니다.

---

## 8.4 DateUtils 공통 모듈 사용

**중요**: DateUtils도 공통 모듈에 위치시키는 것이 좋습니다.

옵션 1: `commerce-api`에서 `commerce-batch`의 `DateUtils` 복사
옵션 2: `supports` 모듈 생성 또는 `modules/jpa`에 위치

**간단한 방법 (commerce-api에 복사)**:

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/support/DateUtils.kt`

```kotlin
package com.loopers.support

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields

object DateUtils {

    fun toYearWeek(date: LocalDate): String {
        val year = date.get(WeekFields.ISO.weekBasedYear())
        val week = date.get(WeekFields.ISO.weekOfWeekBasedYear())
        return String.format("%d-W%02d", year, week)
    }

    fun toYearMonth(date: LocalDate): String {
        return date.format(DateTimeFormatter.ofPattern("yyyy-MM"))
    }

    fun formatDate(date: LocalDate): String {
        return date.format(DateTimeFormatter.BASIC_ISO_DATE)
    }
}
```

---

## 8.5 RankingFacade 확장

기존 `RankingFacade`에 메서드 추가:

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingFacade.kt`

```kotlin
// 기존 코드 유지하고 아래 메서드 추가
// Repository 주입도 추가 필요

private val productRankWeeklyRepository: ProductRankWeeklyRepository
private val productRankMonthlyRepository: ProductRankMonthlyRepository

fun getWeeklyRankings(yearWeek: String, pageable: Pageable): Page<RankingInfo> {
    val allRankings = productRankWeeklyRepository.findByYearWeekOrderByRankPositionAsc(yearWeek)

    // 페이징 처리
    val start = pageable.offset.toInt()
    val end = minOf(start + pageable.pageSize, allRankings.size)

    if (start >= allRankings.size) {
        return PageImpl(emptyList(), pageable, allRankings.size.toLong())
    }

    val pageContent = allRankings.subList(start, end)

    // 상품 정보 조회
    val productIds = pageContent.map { it.productId }
    val products = productService.getProductsByIds(productIds)
        .associateBy { it.id }

    // 랭킹 정보 생성
    val rankings = pageContent.mapNotNull { mv ->
        products[mv.productId]?.let { product ->
            RankingInfo(
                product = ProductInfo.from(product),
                rank = mv.rankPosition,
                score = mv.score
            )
        }
    }

    return PageImpl(rankings, pageable, allRankings.size.toLong())
}

fun getMonthlyRankings(yearMonth: String, pageable: Pageable): Page<RankingInfo> {
    val allRankings = productRankMonthlyRepository.findByYearMonthOrderByRankPositionAsc(yearMonth)

    val start = pageable.offset.toInt()
    val end = minOf(start + pageable.pageSize, allRankings.size)

    if (start >= allRankings.size) {
        return PageImpl(emptyList(), pageable, allRankings.size.toLong())
    }

    val pageContent = allRankings.subList(start, end)

    val productIds = pageContent.map { it.productId }
    val products = productService.getProductsByIds(productIds)
        .associateBy { it.id }

    val rankings = pageContent.mapNotNull { mv ->
        products[mv.productId]?.let { product ->
            RankingInfo(
                product = ProductInfo.from(product),
                rank = mv.rankPosition,
                score = mv.score
            )
        }
    }

    return PageImpl(rankings, pageable, allRankings.size.toLong())
}
```

---

## 8.6 Controller 수정

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Controller.kt`

기존 Controller에 period 파라미터를 받는 메서드 추가:

```kotlin
@GetMapping
fun getRankings(
    @RequestParam(required = false, defaultValue = "daily") period: String,
    @RequestParam(required = false) date: String?,
    pageable: Pageable
): ApiResponse<Page<RankingInfo>> {
    val rankingPeriod = RankingPeriod.from(period)
    val rankings = rankingPeriod.getRankings(date, pageable, rankingFacade)
    return ApiResponse.success(rankings)
}
```

**설명**:
- `RankingPeriod.from()`으로 enum 변환 (잘못된 값은 DAILY로 기본값 처리)
- `period.getRankings()`로 날짜 포맷팅 + Facade 호출을 한 번에 처리
- when 분기 제거로 코드 간결화

---

## 8.7 API Spec 업데이트

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1ApiSpec.kt`

기존 Spec에 period 파라미터를 받는 메서드 추가 (오버로딩):

```kotlin
@Operation(
    summary = "기간별 랭킹 조회",
    description = "일간/주간/월간 상품 랭킹을 조회합니다. daily(Redis), weekly/monthly(DB MV)"
)
fun getRankings(
    @Parameter(
        description = "랭킹 기간 (daily, weekly, monthly)",
        example = "daily",
        schema = Schema(allowableValues = ["daily", "weekly", "monthly"], defaultValue = "daily")
    )
    period: String,

    @Parameter(
        description = "날짜 (daily: yyyyMMdd, weekly: yyyy-Www, monthly: yyyy-MM)",
        example = "20251231"
    )
    date: String?,

    @Parameter(hidden = true)
    pageable: Pageable
): ApiResponse<Page<RankingInfo>>
```

**주요 내용**:
- daily: Redis 기반 실시간 랭킹
- weekly/monthly: DB Materialized View (TOP 100)
- 날짜 형식은 period에 따라 다름

---

## 8.8 API 테스트

### commerce-api 서버 시작
```bash
./gradlew :apps:commerce-api:bootRun
```

### 일간 랭킹
```bash
curl "http://localhost:8080/api/v1/rankings?period=daily&date=20251226&size=10&page=0"
```

### 주간 랭킹
```bash
curl "http://localhost:8080/api/v1/rankings?period=weekly&date=2025-W52&size=10&page=0"
```

### 월간 랭킹
```bash
curl "http://localhost:8080/api/v1/rankings?period=monthly&date=2025-12&size=10&page=0"
```

---

## ✅ Step 8 완료 체크

- [ ] RankingPeriod Enum 생성
- [ ] ProductRank Entity 확인 (modules/jpa에 이미 존재)
- [ ] ProductRank Repository 생성 (commerce-api)
- [ ] DateUtils 추가 (support 패키지)
- [ ] RankingFacade에 메서드 추가
- [ ] Controller 수정
- [ ] 빌드 성공
- [ ] 일간 랭킹 API 테스트 성공
- [ ] 주간 랭킹 API 테스트 성공
- [ ] 월간 랭킹 API 테스트 성공

---

**다음 단계**: [Step 9: 최종 테스트](./STEP9_FINAL_TEST.md)
