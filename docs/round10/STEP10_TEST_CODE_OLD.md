# Step 10: 테스트 코드 작성

> 단위 테스트, 통합 테스트, Batch 테스트 작성

---

## 10.1 테스트 환경 이해

### 프로젝트 테스트 스타일
- **테스트 프레임워크**: JUnit 5
- **Assertion**: AssertJ (`assertThat`)
- **Mock 라이브러리**: MockK (Kotlin 친화적)
- **통합 테스트**: `@SpringBootTest` + `@TestPropertySource`
- **한글 DisplayName**: 테스트 의도를 명확히 설명

### 테스트 파일 위치
```
apps/commerce-batch/src/test/kotlin/com/loopers/
  ├── batch/
  │   └── ranking/
  │       ├── WeeklyRankingJobConfigTest.kt
  │       └── MonthlyRankingJobConfigTest.kt
  ├── support/
  │   └── DateUtilsTest.kt
  └── CommerceBatchContextTest.kt
```

---

## 10.2 DateUtils 단위 테스트

**파일**: `apps/commerce-batch/src/test/kotlin/com/loopers/support/DateUtilsTest.kt`

```kotlin
package com.loopers.support

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import java.time.LocalDate

@DisplayName("DateUtils 테스트")
class DateUtilsTest {

    @DisplayName("날짜를 ISO Week 형식으로 변환한다")
    @Test
    fun toYearWeek() {
        // given
        val date = LocalDate.of(2025, 12, 29) // 월요일

        // when
        val yearWeek = DateUtils.toYearWeek(date)

        // then
        assertThat(yearWeek).isEqualTo("2026-W01")
    }

    @DisplayName("ISO Week 문자열에서 해당 주의 7일 날짜 리스트를 생성한다")
    @Test
    fun getWeekDates() {
        // given
        val yearWeek = "2025-W52"

        // when
        val dates = DateUtils.getWeekDates(yearWeek)

        // then
        assertThat(dates).hasSize(7)
        assertThat(dates[0]).isEqualTo(LocalDate.of(2025, 12, 22)) // 월요일
        assertThat(dates[6]).isEqualTo(LocalDate.of(2025, 12, 28)) // 일요일
    }

    @DisplayName("월의 모든 날짜 리스트를 생성한다")
    @Test
    fun getMonthDates() {
        // given
        val yearMonth = "2025-02"

        // when
        val dates = DateUtils.getMonthDates(yearMonth)

        // then
        assertThat(dates).hasSize(28) // 2025년 2월은 28일
        assertThat(dates.first()).isEqualTo(LocalDate.of(2025, 2, 1))
        assertThat(dates.last()).isEqualTo(LocalDate.of(2025, 2, 28))
    }

    @DisplayName("날짜를 년-월 형식으로 변환한다")
    @Test
    fun toYearMonth() {
        // given
        val date = LocalDate.of(2025, 12, 29)

        // when
        val yearMonth = DateUtils.toYearMonth(date)

        // then
        assertThat(yearMonth).isEqualTo("2025-12")
    }

    @DisplayName("날짜를 yyyyMMdd 형식으로 변환한다")
    @Test
    fun formatDate() {
        // given
        val date = LocalDate.of(2025, 12, 29)

        // when
        val formatted = DateUtils.formatDate(date)

        // then
        assertThat(formatted).isEqualTo("20251229")
    }
}
```

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
@DisplayName("주간 랭킹 Batch Job 테스트")
class WeeklyRankingJobConfigTest @Autowired constructor(
    private val jobLauncher: JobLauncher,
    private val weeklyRankingJob: Job,
    private val productRankWeeklyRepository: ProductRankWeeklyRepository,
    private val redisTemplate: StringRedisTemplate,
) {

    @BeforeEach
    fun setUp() {
        // Redis에 테스트 데이터 적재
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
        // given
        val yearWeek = "2025-W52"
        val params = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        // when
        val execution = jobLauncher.run(weeklyRankingJob, params)

        // then
        assertThat(execution.status.isUnsuccessful).isFalse()

        val rankings = productRankWeeklyRepository.findByYearWeekOrderByRankPositionAsc(yearWeek)
        assertThat(rankings).hasSize(3)
        assertThat(rankings[0].productId).isEqualTo(102L)
        assertThat(rankings[0].score).isEqualTo(140.0) // 20.0 * 7일
        assertThat(rankings[0].rankPosition).isEqualTo(1)
        assertThat(rankings[1].productId).isEqualTo(103L)
        assertThat(rankings[1].score).isEqualTo(105.0) // 15.0 * 7일
        assertThat(rankings[2].productId).isEqualTo(101L)
        assertThat(rankings[2].score).isEqualTo(70.0) // 10.0 * 7일
    }

    @DisplayName("동일한 주간 랭킹을 재실행하면 기존 데이터를 덮어쓴다")
    @Test
    fun weeklyRankingJobIsIdempotent() {
        // given
        val yearWeek = "2025-W52"
        val params = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        // when: 첫 실행
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

        // then: 덮어쓰기 확인
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
@DisplayName("월간 랭킹 Batch Job 테스트")
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
        // given
        val yearMonth = "2025-12"
        val params = JobParametersBuilder()
            .addString("yearMonth", yearMonth)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        // when
        val execution = jobLauncher.run(monthlyRankingJob, params)

        // then
        assertThat(execution.status.isUnsuccessful).isFalse()

        val rankings = productRankMonthlyRepository.findByYearMonthOrderByRankPositionAsc(yearMonth)
        assertThat(rankings).hasSize(3)
        assertThat(rankings[0].productId).isEqualTo(202L)
        assertThat(rankings[0].score).isEqualTo(70.0) // 10.0 * 7일
        assertThat(rankings[1].productId).isEqualTo(203L)
        assertThat(rankings[1].score).isEqualTo(56.0) // 8.0 * 7일
        assertThat(rankings[2].productId).isEqualTo(201L)
        assertThat(rankings[2].score).isEqualTo(35.0) // 5.0 * 7일
    }
}
```

---

## 10.4 API Controller 테스트 (commerce-api)

### 10.4.1 MV Repository Mock Test

**파일**: `apps/commerce-api/src/test/kotlin/com/loopers/application/ranking/RankingFacadeTest.kt`

```kotlin
package com.loopers.application.ranking

import com.loopers.application.product.ProductService
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.shared.Money
import io.mockk.every
import io.mockk.mockk
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.DisplayName
import org.junit.jupiter.api.Test
import org.springframework.data.domain.PageRequest
import java.time.LocalDateTime

@DisplayName("RankingFacade 테스트")
class RankingFacadeTest {

    private lateinit var rankingFacade: RankingFacade
    private lateinit var productRankWeeklyRepository: ProductRankWeeklyRepository
    private lateinit var productRankMonthlyRepository: ProductRankMonthlyRepository
    private lateinit var productService: ProductService
    private lateinit var rankingService: RankingService

    @BeforeEach
    fun setUp() {
        productRankWeeklyRepository = mockk()
        productRankMonthlyRepository = mockk()
        productService = mockk()
        rankingService = mockk()
        rankingFacade = RankingFacade(
            rankingService,
            productService,
            productRankWeeklyRepository,
            productRankMonthlyRepository,
        )
    }

    @DisplayName("주간 랭킹을 페이징 조회하면 상품 정보가 포함된다")
    @Test
    fun getWeeklyRankings() {
        // given
        val yearWeek = "2025-W52"
        val mvList = listOf(
            ProductRankWeekly(
                productId = 101L,
                yearWeek = yearWeek,
                score = 150.0,
                rankPosition = 1,
            ),
            ProductRankWeekly(
                productId = 102L,
                yearWeek = yearWeek,
                score = 120.0,
                rankPosition = 2,
            ),
        )

        val product101 = Product(
            name = "상품101",
            description = "설명101",
            price = Money.of(10000L),
            stock = Stock.of(100),
            brandId = 1L
        ).apply { id = 101L }

        val product102 = Product(
            name = "상품102",
            description = "설명102",
            price = Money.of(20000L),
            stock = Stock.of(50),
            brandId = 1L
        ).apply { id = 102L }

        every { productRankWeeklyRepository.findByYearWeekOrderByRankPositionAsc(yearWeek) } returns mvList
        every { productService.getProductsByIds(listOf(101L, 102L)) } returns listOf(product101, product102)

        // when
        val pageable = PageRequest.of(0, 10)
        val result = rankingFacade.getWeeklyRankings(yearWeek, pageable)

        // then
        assertThat(result.content).hasSize(2)
        assertThat(result.content[0].product.id).isEqualTo(101L)
        assertThat(result.content[0].product.name).isEqualTo("상품101")
        assertThat(result.content[0].rank).isEqualTo(1)
        assertThat(result.content[0].score).isEqualTo(150.0)
    }

    @DisplayName("월간 랭킹 페이징에서 범위를 벗어나면 빈 페이지를 반환한다")
    @Test
    fun getMonthlyRankingsOutOfBounds() {
        // given
        val yearMonth = "2025-12"
        val mvList = (1..100).map {
            ProductRankMonthly(
                productId = it.toLong(),
                yearMonth = yearMonth,
                score = (100 - it).toDouble(),
                rankPosition = it,
            )
        }

        every { productRankMonthlyRepository.findByYearMonthOrderByRankPositionAsc(yearMonth) } returns mvList

        // when: 11페이지 요청 (100개를 넘음)
        val pageable = PageRequest.of(10, 10)
        val result = rankingFacade.getMonthlyRankings(yearMonth, pageable)

        // then
        assertThat(result.content).isEmpty()
        assertThat(result.totalElements).isEqualTo(100)
    }
}
```

### 10.4.2 통합 테스트 (실제 DB)

**파일**: `apps/commerce-api/src/test/kotlin/com/loopers/application/ranking/RankingFacadeIntegrationTest.kt`

```kotlin
package com.loopers.application.ranking

import com.loopers.domain.brand.Brand
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
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
import java.time.LocalDateTime

@SpringBootTest
@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])
@DisplayName("RankingFacade 통합 테스트")
class RankingFacadeIntegrationTest @Autowired constructor(
    private val rankingFacade: RankingFacade,
    private val productRankWeeklyRepository: ProductRankWeeklyRepository,
    private val productRankMonthlyRepository: ProductRankMonthlyRepository,
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
                rankPosition = index + 1,
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
        // given
        val yearWeek = "2025-W52"
        val pageable = PageRequest.of(0, 5)

        // when
        val result = rankingFacade.getWeeklyRankings(yearWeek, pageable)

        // then
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
        // given
        val yearWeek = "2025-W52"
        val pageable = PageRequest.of(1, 5)

        // when
        val result = rankingFacade.getWeeklyRankings(yearWeek, pageable)

        // then
        assertThat(result.content).hasSize(5)
        assertThat(result.number).isEqualTo(1) // 페이지 번호

        val firstRankingInPage = result.content[0]
        assertThat(firstRankingInPage.rank).isEqualTo(6) // 6~10위
    }
}
```

---

## 10.5 빌드 설정 (테스트 의존성)

### commerce-batch의 build.gradle.kts에 추가

```kotlin
dependencies {
    // ... 기존 의존성 ...

    // 테스트 의존성
    testImplementation("org.springframework.boot:spring-boot-starter-test") {
        exclude(group = "org.junit.vintage", module = "junit-vintage-engine")
    }
    testImplementation("org.springframework.batch:spring-batch-test")
    testImplementation("io.mockk:mockk:1.13.8")
}
```

### commerce-api의 build.gradle.kts 확인

이미 다음 의존성이 포함되어 있는지 확인:
```kotlin
testImplementation("org.springframework.boot:spring-boot-starter-test")
testImplementation("io.mockk:mockk:1.13.8")
testImplementation("org.awaitility:awaitility-kotlin:4.2.0")
testImplementation(testFixtures(project(":modules:jpa")))
testImplementation(testFixtures(project(":modules:redis")))
```

---

## 10.6 테스트 실행

### 전체 테스트 실행
```bash
./gradlew :apps:commerce-batch:test
./gradlew :apps:commerce-api:test
```

### 특정 테스트 클래스 실행
```bash
./gradlew :apps:commerce-batch:test --tests DateUtilsTest
./gradlew :apps:commerce-batch:test --tests WeeklyRankingJobConfigTest
```

### 테스트 결과 확인
```bash
open apps/commerce-batch/build/reports/tests/test/index.html
open apps/commerce-api/build/reports/tests/test/index.html
```

---

## ✅ Step 10 완료 체크

- [ ] DateUtils 단위 테스트 작성 및 통과
- [ ] WeeklyRankingJobConfig 통합 테스트 작성 및 통과
- [ ] MonthlyRankingJobConfig 통합 테스트 작성 및 통과
- [ ] RankingFacade Mock 테스트 작성 및 통과
- [ ] RankingFacade 통합 테스트 작성 및 통과
- [ ] 전체 테스트 실행 성공

---

## 10.7 테스트 작성 팁

### 1. Given-When-Then 패턴 사용
```kotlin
@Test
fun testName() {
    // given: 테스트 준비
    val input = "test"

    // when: 실행
    val result = someFunction(input)

    // then: 검증
    assertThat(result).isEqualTo(expected)
}
```

### 2. DisplayName은 한글로 명확하게
```kotlin
@DisplayName("주문 생성 시 재고가 감소한다")
@Test
fun createOrderReducesStock() {
    // ...
}
```

### 3. MockK 사용 예시
```kotlin
// Mock 생성
val repository = mockk<SomeRepository>()

// Stub 설정
every { repository.findById(any()) } returns someEntity

// 검증
verify(exactly = 1) { repository.save(any()) }
```

### 4. 통합 테스트 정리
```kotlin
@AfterEach
fun tearDown() {
    databaseCleanUp.truncateAllTables()
}
```

---

**축하합니다! Round 10 전체 구현 및 테스트가 완료되었습니다! 🎉**
