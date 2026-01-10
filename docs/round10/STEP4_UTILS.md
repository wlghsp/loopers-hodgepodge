# Step 4: DateUtils 유틸리티 생성

> 날짜 계산 및 변환 유틸리티

---

## 4.1 디렉토리 생성

```bash
mkdir -p apps/commerce-batch/src/main/kotlin/com/loopers/support
```

---

## 4.2 DateUtils 클래스

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/support/DateUtils.kt`

```kotlin
package com.loopers.support

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields

object DateUtils {

    /**
     * ISO Week 형식: "2025-W52"
     */
    fun toYearWeek(date: LocalDate): String {
        val year = date.get(WeekFields.ISO.weekBasedYear())
        val week = date.get(WeekFields.ISO.weekOfWeekBasedYear())
        return String.format("%d-W%02d", year, week)
    }

    /**
     * Year-Month 형식: "2025-12"
     */
    fun toYearMonth(date: LocalDate): String {
        return date.format(DateTimeFormatter.ofPattern("yyyy-MM"))
    }

    /**
     * ISO Week의 월요일~일요일 날짜 리스트
     *
     * 예: "2025-W52" → [2025-12-22(월), ..., 2025-12-28(일)]
     */
    fun getWeekDates(yearWeek: String): List<LocalDate> {
        val (year, week) = yearWeek.split("-W").let {
            it[0].toInt() to it[1].toInt()
        }

        val firstDayOfYear = LocalDate.of(year, 1, 1)
        val monday = firstDayOfYear
            .with(WeekFields.ISO.weekOfWeekBasedYear(), week.toLong())
            .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

        return (0..6).map { monday.plusDays(it.toLong()) }
    }

    /**
     * Year-Month의 모든 날짜 리스트
     *
     * 예: "2025-12" → [2025-12-01, ..., 2025-12-31]
     */
    fun getMonthDates(yearMonth: String): List<LocalDate> {
        val (year, month) = yearMonth.split("-").let {
            it[0].toInt() to it[1].toInt()
        }

        val firstDay = LocalDate.of(year, month, 1)
        val lastDay = firstDay.with(TemporalAdjusters.lastDayOfMonth())

        return (0 until lastDay.dayOfMonth).map { firstDay.plusDays(it.toLong()) }
    }

    /**
     * yyyyMMdd → LocalDate
     */
    fun parseDate(dateStr: String): LocalDate {
        return LocalDate.parse(dateStr, DateTimeFormatter.BASIC_ISO_DATE)
    }

    /**
     * LocalDate → yyyyMMdd
     */
    fun formatDate(date: LocalDate): String {
        return date.format(DateTimeFormatter.BASIC_ISO_DATE)
    }
}
```

---

## 4.3 유틸리티 테스트 (선택)

간단히 동작 확인:

```kotlin
import com.loopers.support.DateUtils
import java.time.LocalDate

fun main() {
    // 2025-12-25(목)
    val date = LocalDate.of(2025, 12, 25)

    println(DateUtils.toYearWeek(date))          // 2025-W52
    println(DateUtils.toYearMonth(date))         // 2025-12
    println(DateUtils.getWeekDates("2025-W52"))  // [2025-12-22, ..., 2025-12-28]
    println(DateUtils.getMonthDates("2025-12"))  // [2025-12-01, ..., 2025-12-31]
    println(DateUtils.formatDate(date))          // 20251225
}
```

---

## ✅ Step 4 완료 체크

- [ ] DateUtils 클래스 작성
- [ ] 빌드 성공 확인

---

**다음 단계**: [Step 5: 주간 랭킹 Job](./STEP5_WEEKLY_JOB.md)
