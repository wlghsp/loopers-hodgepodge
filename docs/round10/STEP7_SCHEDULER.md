# Step 7: 스케줄러 설정

> 주간/월간 배치를 자동으로 실행하는 스케줄러

---

## 7.1 디렉토리 생성

```bash
mkdir -p apps/commerce-batch/src/main/kotlin/com/loopers/scheduler
```

---

## 7.2 스케줄러 클래스

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/scheduler/RankingBatchScheduler.kt`

```kotlin
package com.loopers.scheduler

import com.loopers.support.DateUtils
import org.slf4j.LoggerFactory
import org.springframework.batch.core.Job
import org.springframework.batch.core.JobParametersBuilder
import org.springframework.batch.core.launch.JobLauncher
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import java.time.LocalDate

@Component
class RankingBatchScheduler(
    private val jobLauncher: JobLauncher,
    private val weeklyRankingJob: Job,
    private val monthlyRankingJob: Job
) {

    private val log = LoggerFactory.getLogger(javaClass)

    /**
     * 매주 월요일 새벽 1시 (지난 주 집계)
     */
    @Scheduled(cron = "0 0 1 * * MON")
    fun runWeeklyRanking() {
        val lastWeek = LocalDate.now().minusWeeks(1)
        val yearWeek = DateUtils.toYearWeek(lastWeek)

        log.info("===== 주간 랭킹 스케줄 실행: $yearWeek =====")

        val params = JobParametersBuilder()
            .addString("yearWeek", yearWeek)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        try {
            val execution = jobLauncher.run(weeklyRankingJob, params)
            log.info("주간 랭킹 배치 성공: ${execution.status}")
        } catch (e: Exception) {
            log.error("주간 랭킹 배치 실패: $yearWeek", e)
        }
    }

    /**
     * 매월 1일 새벽 2시 (지난 달 집계)
     */
    @Scheduled(cron = "0 0 2 1 * *")
    fun runMonthlyRanking() {
        val lastMonth = LocalDate.now().minusMonths(1)
        val yearMonth = DateUtils.toYearMonth(lastMonth)

        log.info("===== 월간 랭킹 스케줄 실행: $yearMonth =====")

        val params = JobParametersBuilder()
            .addString("yearMonth", yearMonth)
            .addLong("timestamp", System.currentTimeMillis())
            .toJobParameters()

        try {
            val execution = jobLauncher.run(monthlyRankingJob, params)
            log.info("월간 랭킹 배치 성공: ${execution.status}")
        } catch (e: Exception) {
            log.error("월간 랭킹 배치 실패: $yearMonth", e)
        }
    }
}
```

---

## 7.3 Cron 표현식 설명

### 주간 랭킹: `0 0 1 * * MON`
- 매주 월요일 새벽 1시
- 지난 주(월~일) 데이터를 집계

### 월간 랭킹: `0 0 2 1 * *`
- 매월 1일 새벽 2시
- 지난 달 데이터를 집계

### Cron 형식
```
초 분 시 일 월 요일
0  0  1  *  *  MON  → 매주 월요일 01:00:00
0  0  2  1  *  *    → 매월 1일 02:00:00
```

---

## 7.4 테스트용 스케줄 (선택)

테스트를 위해 1분마다 실행하도록 임시 변경:

```kotlin
@Scheduled(cron = "0 */1 * * * *")  // 매 1분마다
fun testWeeklyRanking() {
    // ... 동일한 로직
}
```

**주의**: 테스트 후 원래 cron으로 되돌려야 함!

---

## 7.5 스케줄러 동작 확인

### 서버 시작
```bash
./gradlew :apps:commerce-batch:bootRun
```

### 로그 확인
```
...
2025-12-29 01:00:00.123 ... : ===== 주간 랭킹 스케줄 실행: 2025-W51 =====
2025-12-29 01:00:02.456 ... : 주간 랭킹 배치 성공: COMPLETED
```

---

## ✅ Step 7 완료 체크

- [ ] RankingBatchScheduler 작성
- [ ] @EnableScheduling 확인 (Application 클래스에 있음)
- [ ] 빌드 성공
- [ ] 스케줄러 로그 확인 (테스트용 cron으로 1분마다 실행 테스트)

---

**다음 단계**: [Step 8: Ranking API 확장](./STEP8_API_EXTENSION.md)
