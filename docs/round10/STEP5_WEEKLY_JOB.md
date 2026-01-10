# Step 5: 주간 랭킹 Batch Job 구현

> Redis ZSET에서 7일치 데이터를 읽어 주간 TOP 100 생성

---

## 5.1 디렉토리 생성

```bash
mkdir -p apps/commerce-batch/src/main/kotlin/com/loopers/batch/ranking
```

---

## 5.2 주간 랭킹 Job Config

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/batch/ranking/WeeklyRankingJobConfig.kt`

```kotlin
package com.loopers.batch.ranking

import com.loopers.domain.ranking.ProductRankWeekly
import com.loopers.infrastructure.ranking.ProductRankWeeklyRepository
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
class WeeklyRankingJobConfig(
    private val jobRepository: JobRepository,
    private val transactionManager: PlatformTransactionManager,
    private val redisTemplate: RedisTemplate<String, String>,
    private val productRankWeeklyRepository: ProductRankWeeklyRepository
) {

    private val log = LoggerFactory.getLogger(javaClass)

    @Bean
    fun weeklyRankingJob(): Job {
        return JobBuilder("weeklyRankingJob", jobRepository)
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

    @Bean
    @StepScope
    fun weeklyRankingReader(
        @Value("#{jobParameters['yearWeek']}") yearWeek: String
    ): ItemReader<WeeklyScoreData> {
        log.info("===== 주간 랭킹 배치 시작: $yearWeek =====")

        // 1. 기존 데이터 삭제 (멱등성 보장)
        val deletedCount = productRankWeeklyRepository.deleteByYearWeek(yearWeek)
        log.info("기존 주간 랭킹 데이터 삭제: $yearWeek (${deletedCount}건)")

        // 2. Redis에서 7일치 데이터 집계 및 TOP 100 선택
        val weeklyScores = aggregateWeeklyScores(yearWeek)
            .sortedByDescending { it.second }
            .take(100)
            .mapIndexed { index, (productId, score) ->
                WeeklyScoreData(productId, score, yearWeek, index + 1)
            }

        log.info("주간 집계 완료: ${weeklyScores.size}개 상품")

        // 3. Iterator 기반 ItemReader
        val iterator = weeklyScores.iterator()
        return ItemReader {
            if (iterator.hasNext()) iterator.next() else null
        }
    }

    @Bean
    @StepScope
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

    data class WeeklyScoreData(
        val productId: Long,
        val score: Double,
        val yearWeek: String,
        val rank: Int
    )

    @Bean
    fun weeklyRankingWriter(): ItemWriter<ProductRankWeekly> {
        return ItemWriter { items ->
            productRankWeeklyRepository.saveAll(items)
            log.info("주간 랭킹 ${items.size}개 저장 완료")
        }
    }

    /**
     * Redis에서 7일치 데이터 합산
     */
    private fun aggregateWeeklyScores(yearWeek: String): List<Pair<Long, Double>> {
        val weekDates = DateUtils.getWeekDates(yearWeek)
        val productScores = mutableMapOf<Long, Double>()

        weekDates.forEach { date ->
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

## 5.3 빌드 확인

```bash
./gradlew :apps:commerce-batch:build
```

---

## 5.4 수동 실행 Controller (테스트용)

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/interfaces/batch/BatchTestController.kt`

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
    private val weeklyRankingJob: Job
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
}
```

---

## 5.5 실행 테스트

### 서버 시작
```bash
./gradlew :apps:commerce-batch:bootRun
```

### 배치 실행 (다른 터미널)
```bash
curl -X POST "http://localhost:8085/batch/weekly?yearWeek=2025-W52"
```

### 로그 확인
```
===== 주간 랭킹 배치 시작: 2025-W52 =====
기존 주간 랭킹 데이터 삭제: 2025-W52
주간 집계 완료: 50개 상품
===== 주간 랭킹 배치 완료: 50개 저장 =====
```

### DB 확인
```bash
docker exec -it loopers-mysql mysql -uroot -ppassword loopers

SELECT * FROM mv_product_rank_weekly WHERE year_week = '2025-W52' LIMIT 10;
```

---

## ✅ Step 5 완료 체크

- [ ] WeeklyRankingJobConfig 작성
- [ ] BatchTestController 작성
- [ ] 빌드 성공
- [ ] 서버 실행 성공
- [ ] 배치 실행 성공
- [ ] DB에 데이터 저장 확인

---

**다음 단계**: [Step 6: 월간 랭킹 Job](./STEP6_MONTHLY_JOB.md)
