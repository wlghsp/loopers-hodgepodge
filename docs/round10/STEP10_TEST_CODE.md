# Step 10: 테스트 코드 작성

> 멘토 코드 스타일에 맞춘 Batch 통합 테스트

---

## 10.1 테스트 전략

### 프로젝트 테스트 스타일 (멘토 코드 기준)
- **Mock 테스트 최소화**: 단순 조합 로직은 Mock 테스트 불필요
- **통합 테스트 중심**: `@SpringBootTest`로 실제 동작 검증
- **Given-When-Then**: 명확한 테스트 구조
- **한글 DisplayName**: 테스트 의도를 명확히 표현
- **DatabaseCleanUp**: `@AfterEach`에서 테이블 정리

### 테스트 범위
1. **Context Load 테스트** - 애플리케이션 구동 확인
2. **Batch Job 통합 테스트** - 실제 Redis → MySQL 플로우
3. **API 통합 테스트** - RankingFacade 실제 동작 확인

---

## 10.2 Context Load 테스트

### commerce-batch Context Test

**파일**: `apps/commerce-batch/src/test/kotlin/com/loopers/CommerceBatchContextTest.kt`

```kotlin
package com.loopers

import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.TestPropertySource

@SpringBootTest
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
class CommerceBatchContextTest {

    @Test
    fun contextLoads() {
        // Spring Boot 애플리케이션 컨텍스트가 로드되는지 확인
        // 모든 빈이 올바르게 로드되었는지 확인
    }
}
```

**설명**:
- `spring.task.scheduling.enabled=false`: 스케줄러 비활성화 (테스트 중 자동 실행 방지)
- Context Load만으로도 Bean 설정 오류를 잡을 수 있음

---

## 10.3 Batch Job 통합 테스트

### 10.3.1 주간 랭킹 Job 테스트

**파일**: `apps/commerce-batch/src/test/kotlin/com/loopers/batch/ranking/WeeklyRankingJobConfigTest.kt`

```kotlin
package com.loopers.batch.ranking

import com.loopers.infrastructure.ranking.ProductRankWeeklyRepository
import com.loopers.support.DateUtils
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.batch.core.Job
import org.springframework.batch.core.JobParametersBuilder
import org.springframework.batch.core.launch.JobLauncher
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.test.context.TestPropertySource

@SpringBootTest
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("주간 랭킹 Batch Job 통합 테스트")
class WeeklyRankingJobConfigTest @Autowired constructor(
    private val jobLauncher: JobLauncher,
    private val weeklyRankingJob: Job,
    private val productRankWeeklyRepository: ProductRankWeeklyRepository,
    private val redisTemplate: StringRedisTemplate,
) {

    @BeforeEach
    fun setUp() {
        // Redis에 테스트 데이터 적재 (2025-W52: 12/22 ~ 12/28)
        val dates = DateUtils.getWeekDates("2025-W52")
        dates.forEach { date ->
            val key = "ranking:all:${DateUtils.formatDate(date)}"
            redisTemplate.opsForZSet().add(key, "101", 10.0)
            redisTemplate.opsForZSet().add(key, "102", 20.0)
            redisTemplate.opsForZSet().add(key, "103", 15.0)
        }
    }

    @AfterEach
    fun tearDown() {
        // MV 테이블 정리
        productRankWeeklyRepository.deleteAll()

        // Redis 키 정리
        val dates = DateUtils.getWeekDates("2025-W52")
        dates.forEach { date ->
            val key = "ranking:all:${DateUtils.formatDate(date)}"
            redisTemplate.delete(key)
        }
    }

    @DisplayName("주간 랭킹 배치를 실행하면 TOP 100이 MV 테이블에 저장된다")
    @Test
    fun runWeeklyRankingJob() {
        // Given
        val yearWeek = "2025-W52"
        val params = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        // When
        val execution = jobLauncher.run(weeklyRankingJob, params)

        // Then
        assertThat(execution.status.isUnsuccessful).isFalse()

        val rankings = productRankWeeklyRepository.findByYearWeekOrderByRankPositionAsc(yearWeek)
        assertThat(rankings).hasSize(3)
        assertThat(rankings[0].productId).isEqualTo(102L)
        assertThat(rankings[0].score).isEqualTo(140.0) // 20.0 * 7일
        assertThat(rankings[0].rankPosition).isEqualTo(1)
    }

    @DisplayName("동일한 주간 랭킹을 재실행하면 기존 데이터를 덮어쓴다 (멱등성)")
    @Test
    fun weeklyRankingJobIsIdempotent() {
        // Given
        val yearWeek = "2025-W52"
        val params = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        // When: 첫 실행
        jobLauncher.run(weeklyRankingJob, params)

        // Redis 데이터 변경
        val dates = DateUtils.getWeekDates(yearWeek)
        dates.forEach { date ->
            val key = "ranking:all:${DateUtils.formatDate(date)}"
            redisTemplate.opsForZSet().add(key, "101", 50.0) // 점수 변경
        }

        // 두 번째 실행 (timestamp 변경하여 재실행 허용)
        val params2 = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis() + 1000)
            .toJobParameters()
        jobLauncher.run(weeklyRankingJob, params2)

        // Then: 덮어쓰기 확인
        val rankings = productRankWeeklyRepository.findByYearWeekOrderByRankPositionAsc(yearWeek)
        assertThat(rankings).hasSize(3)
        // 101번 상품이 1위로 변경되어야 함
        assertThat(rankings[0].productId).isEqualTo(101L)
        assertThat(rankings[0].score).isEqualTo(350.0) // 50.0 * 7일
    }
}
```

### 10.3.2 월간 랭킹 Job 테스트

**파일**: `apps/commerce-batch/src/test/kotlin/com/loopers/batch/ranking/MonthlyRankingJobConfigTest.kt`

```kotlin
package com.loopers.batch.ranking

import com.loopers.infrastructure.ranking.ProductRankMonthlyRepository
import com.loopers.support.DateUtils
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.batch.core.Job
import org.springframework.batch.core.JobParametersBuilder
import org.springframework.batch.core.launch.JobLauncher
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.data.redis.core.StringRedisTemplate
import org.springframework.test.context.TestPropertySource

@SpringBootTest
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("월간 랭킹 Batch Job 통합 테스트")
class MonthlyRankingJobConfigTest @Autowired constructor(
    private val jobLauncher: JobLauncher,
    private val monthlyRankingJob: Job,
    private val productRankMonthlyRepository: ProductRankMonthlyRepository,
    private val redisTemplate: StringRedisTemplate,
) {

    @BeforeEach
    fun setUp() {
        // Redis에 테스트 데이터 적재 (12월 1일~7일)
        val dates = DateUtils.getMonthDates("2025-12").take(7)
        dates.forEach { date ->
            val key = "ranking:all:${DateUtils.formatDate(date)}"
            redisTemplate.opsForZSet().add(key, "201", 5.0)
            redisTemplate.opsForZSet().add(key, "202", 10.0)
            redisTemplate.opsForZSet().add(key, "203", 8.0)
        }
    }

    @AfterEach
    fun tearDown() {
        productRankMonthlyRepository.deleteAll()

        val dates = DateUtils.getMonthDates("2025-12").take(7)
        dates.forEach { date ->
            val key = "ranking:all:${DateUtils.formatDate(date)}"
            redisTemplate.delete(key)
        }
    }

    @DisplayName("월간 랭킹 배치를 실행하면 TOP 100이 MV 테이블에 저장된다")
    @Test
    fun runMonthlyRankingJob() {
        // Given
        val yearMonth = "2025-12"
        val params = JobParametersBuilder()
            .addString("yearMonth", yearMonth)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        // When
        val execution = jobLauncher.run(monthlyRankingJob, params)

        // Then
        assertThat(execution.status.isUnsuccessful).isFalse()

        val rankings = productRankMonthlyRepository.findByYearMonthOrderByRankPositionAsc(yearMonth)
        assertThat(rankings).hasSize(3)
        assertThat(rankings[0].productId).isEqualTo(202L)
        assertThat(rankings[0].score).isEqualTo(70.0) // 10.0 * 7일
        assertThat(rankings[0].rankPosition).isEqualTo(1)
    }
}
```

---

## 10.4 RankingFacade 통합 테스트 (commerce-api)

**파일**: `apps/commerce-api/src/test/kotlin/com/loopers/application/ranking/RankingFacadeIntegrationTest.kt`

```kotlin
package com.loopers.application.ranking

import com.loopers.domain.brand.Brand
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
import com.loopers.infrastructure.ranking.ProductRankWeeklyRepository
import com.loopers.utils.DatabaseCleanUp
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.data.domain.PageRequest
import org.springframework.kafka.core.KafkaTemplate
import org.springframework.test.context.TestPropertySource
import com.loopers.domain.ranking.ProductRankWeekly

@SpringBootTest
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("RankingFacade 통합 테스트")
class RankingFacadeIntegrationTest @Autowired constructor(
    private val rankingFacade: RankingFacade,
    private val productRankWeeklyRepository: ProductRankWeeklyRepository,
    private val productJpaRepository: ProductJpaRepository,
    private val brandJpaRepository: BrandJpaRepository,
    private val databaseCleanUp: DatabaseCleanUp,
) {

    @MockBean
    private lateinit var kafkaTemplate: KafkaTemplate<String, String>

    private lateinit var brand: Brand
    private lateinit var products: List<Product>

    @BeforeEach
    fun setUp() {
        brand = brandJpaRepository.save(Brand(name = "테스트브랜드", description = "설명"))
        products = (1..10).map { i ->
            productJpaRepository.save(
                Product(
                    name = "상품$i",
                    description = "설명$i",
                    price = Money.of(10000L),
                    stock = Stock.of(100),
                    brandId = brand.id
                )
            )
        }

        // MV Weekly 테이블에 데이터 저장
        val weeklyData = products.mapIndexed { index, product ->
            ProductRankWeekly(
                productId = product.id,
                yearWeek = "2025-W52",
                score = (100 - index * 10).toDouble(),
                rankPosition = (index + 1).toLong(),
            )
        }
        productRankWeeklyRepository.saveAll(weeklyData)
    }

    @AfterEach
    fun tearDown() {
        databaseCleanUp.truncateAllTables()
    }

    @DisplayName("주간 랭킹 1페이지 조회 시 상품 정보가 포함되어 반환된다")
    @Test
    fun getWeeklyRankingsWithProductInfo() {
        // Given
        val yearWeek = "2025-W52"
        val pageable = PageRequest.of(0, 5)

        // When
        val result = rankingFacade.getWeeklyRankings(yearWeek, pageable)

        // Then
        assertThat(result.content).hasSize(5)
        assertThat(result.totalElements).isEqualTo(10)
        assertThat(result.totalPages).isEqualTo(2)

        val firstRanking = result.content[0]
        assertThat(firstRanking.rank).isEqualTo(1)
        assertThat(firstRanking.score).isEqualTo(100.0)
        assertThat(firstRanking.product.name).isEqualTo("상품1")
    }

    @DisplayName("주간 랭킹 2페이지 조회가 정상 동작한다")
    @Test
    fun getWeeklyRankingsSecondPage() {
        // Given
        val yearWeek = "2025-W52"
        val pageable = PageRequest.of(1, 5)

        // When
        val result = rankingFacade.getWeeklyRankings(yearWeek, pageable)

        // Then
        assertThat(result.content).hasSize(5)
        assertThat(result.number).isEqualTo(1) // 페이지 번호

        val firstRankingInPage = result.content[0]
        assertThat(firstRankingInPage.rank).isEqualTo(6) // 6~10위
    }
}
```

**주요 차이점**:
- Mock 없음 - 실제 DB 사용
- `DatabaseCleanUp` 사용 - 멘토 코드 스타일
- `@MockBean KafkaTemplate` - Kafka 비활성화
- 실제 Product/Brand 엔티티 저장 - 상품 정보 aggregation 테스트

---

## 10.5 테스트 실행

### 전체 테스트 실행
```bash
./gradlew :apps:commerce-batch:test
./gradlew :apps:commerce-api:test
```

### 특정 테스트 클래스 실행
```bash
./gradlew :apps:commerce-batch:test --tests WeeklyRankingJobConfigTest
./gradlew :apps:commerce-api:test --tests RankingFacadeIntegrationTest
```

### 테스트 결과 확인
```bash
open apps/commerce-batch/build/reports/tests/test/index.html
open apps/commerce-api/build/reports/tests/test/index.html
```

---

## ✅ Step 10 완료 체크

- [ ] CommerceBatchContextTest 작성 및 통과
- [ ] WeeklyRankingJobConfigTest 작성 및 통과
- [ ] MonthlyRankingJobConfigTest 작성 및 통과
- [ ] RankingFacadeIntegrationTest 작성 및 통과
- [ ] 전체 테스트 실행 성공

---

## 10.6 멘토 코드 스타일 요약

### ✅ DO (권장)
- `@SpringBootTest` 통합 테스트 중심
- `DatabaseCleanUp` + `@AfterEach`
- Given-When-Then 구조
- 한글 DisplayName
- `@MockBean KafkaTemplate` (Kafka 비활성화)
- `spring.task.scheduling.enabled=false` (스케줄러 비활성화)

### ❌ DON'T (비권장)
- 단순 조합 로직의 Mock 테스트
- `@MockK` 과도한 사용 (통합 테스트로 대체)
- 복잡한 Stub 설정

---

**축하합니다! Round 10 테스트 코드 작성이 완료되었습니다! 🎉**
