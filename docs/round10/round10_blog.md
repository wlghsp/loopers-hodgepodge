# Spring Batch로 주간/월간 랭킹 시스템 구축하기 - Materialized View 패턴 적용기

> **TL;DR**: Redis에서 매번 7~30일치 데이터를 집계하는 대신, Spring Batch로 주기적으로 Materialized View를 갱신하여 랭킹 조회 성능을 O(N)에서 O(1)로 개선했습니다. 이 과정에서 Chunk-oriented Processing, 멱등성 보장, ISO Week 기준 주차 계산 등의 실전 문제를 다뤘습니다.

---

## 들어가며

이번 Round 10에서는 Spring Batch를 활용한 주간/월간 랭킹 시스템을 구축했습니다. 처음에는 "배치라니, 그냥 스케줄러로 집계하면 되는 거 아닌가?"라고 생각했지만, 직접 구현하면서 배치 프레임워크가 왜 필요한지 체감하게 되었습니다.

일간 랭킹은 Redis ZSET으로 실시간 조회가 가능하지만, 주간/월간은 이야기가 달랐습니다. 7일치 ZSET을 매 요청마다 집계하면 O(7N) 시간 복잡도가 발생하고, 30일이면 더 심각해집니다. "이건 미리 계산해두는 게 낫겠다"는 판단에서 Materialized View 패턴을 도입하게 되었습니다.

---

## 1. Materialized View vs Real-time Aggregation: 첫 번째 선택

### 문제 인식

일간 랭킹 API는 Redis에서 단순히 `ZREVRANGE`로 조회하면 끝이었습니다. 하지만 주간 랭킹을 구현하려면:

```kotlin
// 매 요청마다 이런 로직이 실행됨
fun getWeeklyRankings(yearWeek: String): List<Ranking> {
    val weekDates = getWeekDates(yearWeek)  // 7개 날짜
    val aggregated = mutableMapOf<Long, Double>()

    weekDates.forEach { date ->
        val dailyRankings = redis.zRevRangeWithScores("ranking:all:$date", 0, -1)
        dailyRankings.forEach { (productId, score) ->
            aggregated[productId] = aggregated.getOrDefault(productId, 0.0) + score
        }
    }

    return aggregated.sortedByDescending { it.value }.take(100)
}
```

이 코드의 문제점:
- 7번의 Redis 조회 (네트워크 I/O)
- 매번 전체 상품 집계 후 정렬
- 월간이면 30번 조회...

### 선택의 순간

두 가지 선택지가 있었습니다:

1. **Real-time Aggregation**: 매 요청마다 집계
   - 장점: 항상 최신 데이터
   - 단점: 높은 부하, 느린 응답

2. **Materialized View**: 주기적으로 사전 계산
   - 장점: 빠른 조회 (단순 SELECT)
   - 단점: 데이터 지연 (최대 1주일)

"주간 랭킹은 어제와 오늘이 크게 다르지 않다"는 판단에 MV를 선택했습니다. 실시간성보다 성능과 일관성이 중요하다고 생각했기 때문입니다.

### 구현 결과

```sql
-- MV 테이블 (TOP 100만 저장)
CREATE TABLE mv_product_rank_weekly (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    year_week VARCHAR(10) NOT NULL,  -- '2025-W01'
    score DOUBLE NOT NULL,
    rank_position BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_year_week_rank (year_week, rank_position)
);
```

API 조회는 단순 SELECT로 변경:

```kotlin
fun getWeeklyRankings(yearWeek: String, pageable: Pageable): Page<RankingInfo> {
    val rankings = repository.findByYearWeekOrderByRankPositionAsc(yearWeek)
    // 페이징 + 상품 정보 조합
    return PageImpl(...)
}
```

**Trade-off**: 실시간성을 포기하고 성능을 얻었습니다. 하지만 "지난주 랭킹"은 고정된 값이므로 이 Trade-off는 합리적이었습니다.

---

## 2. Spring Batch를 써야 했던 이유

### 처음의 착각

솔직히 처음에는 "그냥 `@Scheduled`로 집계하면 되지 않나?"라고 생각했습니다:

```kotlin
@Scheduled(cron = "0 0 1 * * MON")
fun aggregateWeeklyRanking() {
    val weekDates = getWeekDates(previousWeek)
    val aggregated = mutableMapOf<Long, Double>()

    // Redis 집계
    weekDates.forEach { ... }

    // DB 저장
    repository.saveAll(...)
}
```

하지만 이 방식의 문제점을 곧 깨달았습니다:

1. **실패 시 재시도?** 수동으로 구현해야 함
2. **실행 이력 관리?** 별도 테이블 필요
3. **부분 실패 시 롤백?** 트랜잭션 경계 설정 복잡
4. **모니터링?** 로그 파싱?

### Spring Batch가 제공하는 것들

Spring Batch를 도입하니 이 모든 게 해결되었습니다:

```kotlin
@Bean
fun weeklyRankingJob(): Job {
    return JobBuilder("weeklyRankingJob", jobRepository)
        .listener(jobListener)  // 자동 모니터링
        .start(weeklyRankingStep())
        .build()
}

@Bean
fun weeklyRankingStep(): Step {
    return StepBuilder("weeklyRankingStep", jobRepository)
        .chunk<WeeklyScoreData, ProductRankWeekly>(100, transactionManager)
        .reader(weeklyRankingReader(""))
        .processor(weeklyRankingProcessor())
        .writer(weeklyRankingWriter())
        .build()
}
```

무료로 얻은 것들:
- `BATCH_JOB_EXECUTION` 테이블에 실행 이력 자동 저장
- 실패 시 재시작 지점 자동 관리
- Chunk 단위 트랜잭션 자동 처리
- JobListener, StepListener로 모니터링

**깨달음**: "배치 프레임워크는 단순 스케줄러가 아니라, 안정적인 대용량 처리를 위한 인프라였구나"

---

## 3. Chunk vs Tasklet: 두 번째 선택

### 고민의 시작

Spring Batch는 두 가지 실행 방식을 제공합니다:

**Tasklet**: 한 번에 모든 처리
```kotlin
fun execute(): RepeatStatus {
    // 전체 로직
    deleteOldData()
    val data = aggregateFromRedis()
    saveToDatabase(data)
    return RepeatStatus.FINISHED
}
```

**Chunk**: Reader/Processor/Writer 분리
```kotlin
Reader  -> [item1, item2, ..., item100]
Processor -> [processed1, processed2, ..., processed100]
Writer -> DB.saveAll()
```

### 선택 기준

처음에는 "TOP 100만 저장하는데 Chunk가 필요할까?"라고 생각했습니다. 하지만 Chunk를 선택한 이유:

1. **확장성**: 향후 TOP 1000으로 늘어나도 대응 가능
2. **명확한 책임 분리**: Read/Transform/Write 각각의 역할이 명확
3. **트랜잭션 제어**: Chunk 단위로 자동 커밋

### 실제 구현

```kotlin
// Reader: Redis 집계 후 Iterator 반환
@Bean
@StepScope
fun weeklyRankingReader(
    @Value("#{jobParameters['yearWeek']}") yearWeek: String
): ItemReader<WeeklyScoreData> {
    // 1. 기존 데이터 삭제 (멱등성)
    repository.deleteByYearWeek(yearWeek)

    // 2. Redis 집계
    val weeklyScores = aggregateWeeklyScores(yearWeek)
        .sortedByDescending { it.second }
        .take(100)

    // 3. Iterator 반환
    val iterator = weeklyScores.iterator()
    return ItemReader { if (iterator.hasNext()) iterator.next() else null }
}

// Processor: 단순 변환
@Bean
fun weeklyRankingProcessor(): ItemProcessor<WeeklyScoreData, ProductRankWeekly> {
    return ItemProcessor { data ->
        ProductRankWeekly(
            productId = data.productId,
            yearWeek = data.yearWeek,
            score = data.score,
            rankPosition = data.rank
        )
    }
}

// Writer: 배치 저장
@Bean
fun weeklyRankingWriter(): ItemWriter<ProductRankWeekly> {
    return ItemWriter { items ->
        repository.saveAll(items)
        log.info("주간 랭킹 ${items.size()}개 저장 완료")
    }
}
```

**문제점 발견**: Reader에서 삭제 로직이 실행되는 게 마음에 걸렸습니다. "순수한 Read 책임이 아닌데?" 하지만 멱등성을 보장하려면 집계 전에 삭제가 필요했고, 이는 향후 개선 포인트로 남겨뒀습니다.

---

## 4. 멱등성: 가장 중요했던 요구사항

### 왜 멱등성인가?

배치는 실패할 수 있습니다. 네트워크 장애, DB 락, 메모리 부족 등 다양한 이유로요. 그럼 재실행하면 되는데, **같은 주차를 2번 실행하면?**

```
1차 실행: 2025-W01 → TOP 100 저장 ✅
2차 실행: 2025-W01 → 중복 저장? 덮어쓰기? 🤔
```

### 해결 방법: Delete & Insert

가장 단순하고 확실한 방법을 선택했습니다:

```kotlin
// Reader 시작 시 삭제
repository.deleteByYearWeek(yearWeek)

// 이후 새로 계산해서 저장
repository.saveAll(newRankings)
```

**장점**:
- 구현 단순
- 확실한 멱등성 보장
- 디버깅 쉬움

**단점**:
- 삭제와 삽입 사이에 데이터가 비어있음
- API 조회 시 빈 결과 가능 (수 초간)

### 테스트로 검증

```kotlin
@Test
fun idempotency() {
    // Given: 동일 주차
    val yearWeek = "2025-W01"
    prepareRedisData(yearWeek)

    // When: 2번 실행
    runBatch(yearWeek)
    val firstResult = repository.findByYearWeek(yearWeek)

    runBatch(yearWeek)
    val secondResult = repository.findByYearWeek(yearWeek)

    // Then: 결과 동일
    assertThat(firstResult).isEqualTo(secondResult)
}
```

**배운 점**: 멱등성은 "여러 번 실행해도 안전"이 아니라 "여러 번 실행해도 같은 결과"를 의미합니다. 이를 테스트로 명확히 증명할 수 있어야 합니다.

---

## 5. ISO Week: 예상치 못한 함정

### 주차 계산의 늪

"주간 랭킹"을 만든다는데, 주차를 어떻게 정의할까요?

- 일요일부터? 월요일부터?
- 2025년 1월 1일은 몇 주차?
- 연말/연초 경계는?

처음엔 단순하게 생각했습니다:

```kotlin
// 위험한 코드
val weekNumber = LocalDate.now().get(ChronoField.WEEK_OF_YEAR)  // ⚠️
```

하지만 이 방식은 ISO 8601 표준과 다릅니다. ISO Week는 "첫 목요일이 속한 주가 1주차"라는 복잡한 규칙이 있습니다.

### ISO Week 채택

국제 표준을 따르기로 결정:

```kotlin
object DateUtils {
    private val ISO_WEEK_FORMATTER = DateTimeFormatter.ofPattern("YYYY-'W'ww")

    fun toYearWeek(date: LocalDate): String {
        return date.format(ISO_WEEK_FORMATTER)  // "2025-W01"
    }

    fun getWeekDates(yearWeek: String): List<LocalDate> {
        val (year, week) = yearWeek.split("-W").map { it.toInt() }
        val firstDayOfWeek = LocalDate.ofYearDay(year, 1)
            .with(IsoFields.WEEK_OF_WEEK_BASED_YEAR, week.toLong())
            .with(DayOfWeek.MONDAY)

        return (0..6).map { firstDayOfWeek.plusDays(it.toLong()) }
    }
}
```

### 함정 발견

```kotlin
// 2024-12-30 (월요일)은?
DateUtils.toYearWeek(LocalDate.of(2024, 12, 30))
// 결과: "2025-W01"  ⚠️

// 이유: ISO Week는 "첫 목요일이 속한 주"가 기준
// 12/30(월) ~ 1/5(일) 주의 목요일은 1/2(목)이므로 2025년 주차
```

**깨달음**: 날짜/시간 처리는 생각보다 복잡합니다. 표준을 따르되, 경계값을 꼼꼼히 테스트해야 합니다.

---

## 6. Strategy Pattern: Controller를 깔끔하게

### if-else의 늪을 피하다

처음 생각한 Controller:

```kotlin
@GetMapping
fun getRankings(
    @RequestParam period: String,
    @RequestParam date: String?,
    pageable: Pageable
): ApiResponse<Page<RankingInfo>> {
    return when (period) {
        "daily" -> {
            val formattedDate = date ?: LocalDate.now().format(...)
            rankingFacade.getRankings(formattedDate, pageable)
        }
        "weekly" -> {
            val formattedDate = date ?: DateUtils.toYearWeek(LocalDate.now())
            rankingFacade.getWeeklyRankings(formattedDate, pageable)
        }
        "monthly" -> {
            val formattedDate = date ?: DateUtils.toYearMonth(LocalDate.now())
            rankingFacade.getMonthlyRankings(formattedDate, pageable)
        }
        else -> throw IllegalArgumentException("Unknown period: $period")
    }
}
```

코드가 길고 중복이 많습니다. "날짜 형식 변환 + Facade 호출"이 반복되는 구조였죠.

### enum으로 전략 패턴

```kotlin
enum class RankingPeriod {
    DAILY {
        override fun formatDate(date: String?): String =
            date ?: LocalDate.now().format(DateTimeFormatter.BASIC_ISO_DATE)

        override fun getRankings(
            date: String?,
            pageable: Pageable,
            facade: RankingFacade
        ) = facade.getRankings(formatDate(date), pageable)
    },
    WEEKLY {
        override fun formatDate(date: String?): String =
            date ?: DateUtils.toYearWeek(LocalDate.now())

        override fun getRankings(
            date: String?,
            pageable: Pageable,
            facade: RankingFacade
        ) = facade.getWeeklyRankings(formatDate(date), pageable)
    },
    MONTHLY {
        override fun formatDate(date: String?): String =
            date ?: DateUtils.toYearMonth(LocalDate.now())

        override fun getRankings(
            date: String?,
            pageable: Pageable,
            facade: RankingFacade
        ) = facade.getMonthlyRankings(formatDate(date), pageable)
    };

    abstract fun formatDate(date: String?): String
    abstract fun getRankings(
        date: String?,
        pageable: Pageable,
        facade: RankingFacade
    ): Page<RankingInfo>
}
```

Controller는 단 3줄:

```kotlin
@GetMapping
fun getRankings(
    @RequestParam(defaultValue = "daily") period: String,
    @RequestParam(required = false) date: String?,
    pageable: Pageable
): ApiResponse<Page<RankingInfo>> {
    val rankingPeriod = RankingPeriod.from(period)
    return ApiResponse.success(rankingPeriod.getRankings(date, pageable, rankingFacade))
}
```

**Trade-off**: enum에 비즈니스 로직이 들어가는 게 부담스러웠지만, 3가지 타입만 있는 현재는 충분히 관리 가능하다고 판단했습니다. 향후 타입이 늘어나면 별도 인터페이스로 분리할 수 있습니다.

---

## 7. Testcontainers: 통합 테스트의 현실

### 초기 테스트 실패

배치 테스트를 작성하고 실행하니 에러:

```
Table 'loopers.BATCH_JOB_INSTANCE' doesn't exist
```

"어? Spring Batch 테이블이 없네?" H2로 테스트하려니 MySQL 전용 DDL 때문에 문제가 발생했습니다.

### Testcontainers 도입

실제 MySQL 8.0 컨테이너를 띄워서 테스트:

```kotlin
@Configuration
class MySqlTestContainersConfig {
    companion object {
        private val mySqlContainer: MySQLContainer<*> =
            MySQLContainer(DockerImageName.parse("mysql:8.0"))
                .apply {
                    withDatabaseName("loopers")
                    withUsername("test")
                    withPassword("test")
                    withInitScript("db/init-batch-tables.sql")  // ⭐️
                    start()
                }
    }
}
```

`init-batch-tables.sql`에 Spring Batch 메타데이터 테이블 DDL을 모두 넣었습니다:

```sql
CREATE TABLE BATCH_JOB_INSTANCE (
    JOB_INSTANCE_ID BIGINT NOT NULL PRIMARY KEY,
    VERSION BIGINT,
    JOB_NAME VARCHAR(100) NOT NULL,
    JOB_KEY VARCHAR(32) NOT NULL,
    UNIQUE KEY JOB_INST_UN (JOB_NAME, JOB_KEY)
);
-- ... 나머지 테이블들
```

**배운 점**: 통합 테스트는 실제 환경과 최대한 가깝게 해야 합니다. Testcontainers 덕분에 로컬 개발 환경에서도 프로덕션과 동일한 MySQL로 테스트할 수 있었습니다.

---

## 회고: Spring Batch를 써본 소감

### Before: 배치는 그냥 스케줄러 아닌가?

```kotlin
@Scheduled(cron = "...")
fun doSomething() {
    // 그냥 로직 실행
}
```

### After: 배치는 안정적인 대용량 처리 인프라

```kotlin
Job -> Step -> Chunk(Reader/Processor/Writer)
```

Spring Batch를 써보니 알게 된 것들:

1. **실행 이력 관리**: `BATCH_JOB_EXECUTION` 테이블로 모든 실행 기록 추적
2. **재시작 전략**: 실패 지점부터 재실행 가능
3. **트랜잭션 제어**: Chunk 단위로 자동 커밋/롤백
4. **모니터링**: Listener로 각 단계 모니터링
5. **멱등성 강제**: JobParameters로 동일 실행 방지

단순 스케줄러였다면 이 모든 걸 직접 구현해야 했을 겁니다.

### 아쉬운 점

1. **Reader의 책임 비대화**: 삭제 로직이 Reader에 있는 게 마음에 걸림
   - 향후 별도 Tasklet으로 분리 고려

2. **MV 갱신 시 데이터 공백**: 삭제 후 삽입 사이 빈 데이터
   - 임시 테이블 + RENAME TABLE 패턴 고려

3. **배치 실패 시 알림**: 현재는 로그만
   - Slack/Email 연동 필요

### 실전 적용 포인트

이번에 배운 내용을 실무에서 어떻게 쓸까 고민했습니다:

1. **정산 배치**: 일일/월간 매출 집계
   - MV 패턴으로 대시보드 조회 성능 개선

2. **리포트 생성**: 주간/월간 리포트
   - Chunk Processing으로 수만 건 데이터 안정적 처리

3. **데이터 마이그레이션**: 대량 데이터 이관
   - 멱등성 보장으로 재실행 안전

---

## 마치며

Spring Batch를 처음 접했을 때는 "왜 이렇게 복잡하지?"라고 생각했습니다. JobRepository, StepExecution, Chunk... 개념도 많고 설정도 복잡했습니다.

하지만 직접 구현해보니 알았습니다. 이 복잡함은 **안정성을 위한 필수 장치**였다는 것을요. 실패 재시작, 트랜잭션 제어, 실행 이력 관리 등을 직접 구현했다면 훨씬 더 복잡했을 겁니다.

특히 멱등성 보장, Testcontainers 기반 통합 테스트, ISO Week 처리 등은 "실전에서 만날 수 있는 진짜 문제"였습니다. 이런 경험이 쌓여 더 나은 개발자가 되는 거겠죠.

다음에는 더 복잡한 배치를 만들어보고 싶습니다. Skip/Retry 전략, Partitioning, 병렬 처리 등... 배울 게 아직 많네요.



