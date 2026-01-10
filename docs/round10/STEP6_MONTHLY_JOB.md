# Step 6: 월간 랭킹 Batch Job 구현

> Redis ZSET에서 30일치 데이터를 읽어 월간 TOP 100 생성

---

## 6.1 월간 랭킹 Job Config

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/batch/ranking/MonthlyRankingJobConfig.kt`

```kotlin
package com.loopers.batch.ranking

import com.loopers.domain.ranking.ProductRankMonthly
import com.loopers.infrastructure.ranking.ProductRankMonthlyRepository
import com.loopers.support.DateUtils
import org.slf4j.LoggerFactory
import org.springframework.batch.core.Job
import org.springframework.batch.core.Step
import org.springframework.batch.core.configuration.annotation.StepScope
import org.springframework.batch.core.job.builder.JobBuilder
import org.springframework.batch.core.repository.JobRepository
import org.springframework.batch.core.step.builder.StepBuilder
import org.springframework.batch.item.ItemProcessor
import org.springframework.batch.item.ItemReader
import org.springframework.batch.item.ItemWriter
import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.data.redis.core.RedisTemplate
import org.springframework.transaction.PlatformTransactionManager

@Configuration
class MonthlyRankingJobConfig(
    private val jobRepository: JobRepository,
    private val transactionManager: PlatformTransactionManager,
    private val redisTemplate: RedisTemplate<String, String>,
    private val productRankMonthlyRepository: ProductRankMonthlyRepository,
) {

    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    fun monthlyRankingJob(): Job {
        return JobBuilder("monthlyRankingJob", jobRepository)
            .start(monthlyRankingStep())
            .build()
    }

    @Bean
    fun monthlyRankingStep(): Step {
        return StepBuilder("monthlyRankingStep", jobRepository)
            .chunk<MonthlyScoreData, ProductRankMonthly>(100, transactionManager)
            .reader(monthlyRankingReader(""))
            .processor(monthlyRankingProcessor())
            .writer(monthlyRankingWriter())
            .build()
    }

    @Bean
    @StepScope
    fun monthlyRankingReader(
        @Value("#{jobParameters['yearMonth']}") yearMonth: String,
    ): ItemReader<MonthlyScoreData> {
        log.info("===== 월간 랭킹 배치 시작: $yearMonth =====")

        // 1. 기존 데이터 삭제 (멱등성 보장)
        val deletedCount = productRankMonthlyRepository.deleteByYearMonth(yearMonth)
        log.info("기존 월간 랭킹 데이터 삭제: $yearMonth (${deletedCount}건)")

        // 2. Redis에서 30일치 데이터 집계 및 TOP 100 선택
        val monthlyScores = aggregateMonthlyScores(yearMonth)
            .sortedByDescending { it.second }
            .take(100)
            .mapIndexed { index, (productId, score) ->
                MonthlyScoreData(productId, score, yearMonth, index + 1)
            }

        log.info("월간 집계 완료: ${monthlyScores.size}개 상품")

        // 3. Iterator 기반 ItemReader
        val iterator = monthlyScores.iterator()
        return ItemReader {
            if (iterator.hasNext()) iterator.next() else null
        }
    }

    @Bean
    @StepScope
    fun monthlyRankingProcessor(): ItemProcessor<MonthlyScoreData, ProductRankMonthly> {
        return ItemProcessor { data ->
            ProductRankMonthly(
                productId = data.productId,
                yearMonth = data.yearMonth,
                score = data.score,
                rankPosition = data.rank,
            )
        }
    }

    data class MonthlyScoreData(
        val productId: Long,
        val score: Double,
        val yearMonth: String,
        val rank: Int,
    )

    @Bean
    fun monthlyRankingWriter(): ItemWriter<ProductRankMonthly> {
        return ItemWriter { items ->
            productRankMonthlyRepository.saveAll(items)
            log.info("월간 랭킹 ${items.size}개 저장 완료")
        }
    }

    /**
     * Redis에서 30일치 데이터 합산
     */
    private fun aggregateMonthlyScores(yearMonth: String): List<Pair<Long, Double>> {
        val monthDates = DateUtils.getMonthDates(yearMonth)
        val productScores = mutableMapOf<Long, Double>()

        monthDates.forEach { date ->
            val key = "ranking:all:${DateUtils.formatDate(date)}"
            log.debug("Redis 키 조회: $key")

            val dailyRankings = redisTemplate.opsForZSet()
                .reverseRangeWithScores(key, 0, -1) // 전체 조회

            dailyRankings?.forEach { typedTuple ->
                val productIdStr = typedTuple.value ?: return@forEach
                val productId = productIdStr.replace("product:", "").toLongOrNull() ?: return@forEach
                val score = typedTuple.score ?: 0.0

                productScores[productId] = productScores.getOrDefault(productId, 0.0) + score
            }
        }

        return productScores.toList()
    }
}
```

---

## 6.2 BatchTestController 수정

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/interfaces/batch/BatchTestController.kt`

기존 파일에 `monthlyRankingJob` 추가:

```kotlin
package com.loopers.interfaces.batch

import org.springframework.batch.core.Job
import org.springframework.batch.core.JobParametersBuilder
import org.springframework.batch.core.launch.JobLauncher
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/batch")
class BatchTestController(
    private val jobLauncher: JobLauncher,
    private val weeklyRankingJob: Job,
    private val monthlyRankingJob: Job,  // 추가
) {

    @PostMapping("/weekly")
    fun runWeekly(@RequestParam yearWeek: String): String {
        val params = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        val execution = jobLauncher.run(weeklyRankingJob, params)
        return "주간 랭킹 배치: ${execution.status}"
    }

    @PostMapping("/monthly")  // 추가
    fun runMonthly(@RequestParam yearMonth: String): String {
        val params = JobParametersBuilder()
            .addString("yearMonth", yearMonth)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        val execution = jobLauncher.run(monthlyRankingJob, params)
        return "월간 랭킹 배치: ${execution.status}"
    }
}
```

---

## 6.3 실행 테스트

### 서버 재시작 (이미 실행 중이면 재시작)
```bash
./gradlew :apps:commerce-batch:bootRun
```

### 월간 배치 실행
```bash
curl -X POST "http://localhost:8085/batch/monthly?yearMonth=2025-12"
```

### DB 확인
```bash
docker exec -it loopers-mysql mysql -uroot -ppassword loopers

SELECT * FROM mv_product_rank_monthly WHERE year_month = '2025-12' LIMIT 10;
```

---

## ✅ Step 6 완료 체크

- [ ] MonthlyRankingJobConfig 작성
- [ ] BatchTestController에 monthly 엔드포인트 추가
- [ ] 빌드 성공
- [ ] 배치 실행 성공
- [ ] DB에 데이터 저장 확인

---

**다음 단계**: [Step 7: 스케줄러 설정](./STEP7_SCHEDULER.md)
