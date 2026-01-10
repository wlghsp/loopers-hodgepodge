# Step 3: Entity & Repository 생성

> MV 테이블 접근을 위한 JPA Entity와 Repository
>
> **중요**: Entity는 여러 모듈에서 재사용할 수 있도록 `modules/jpa`에 위치시킵니다.

---

## 3.1 디렉토리 생성

```bash
# Entity는 공통 모듈에 위치
mkdir -p modules/jpa/src/main/kotlin/com/loopers/domain/ranking

# Repository는 배치 모듈에 위치
mkdir -p apps/commerce-batch/src/main/kotlin/com/loopers/infrastructure/ranking
```

---

## 3.2 ProductRankWeekly Entity

**파일**: `modules/jpa/src/main/kotlin/com/loopers/domain/ranking/ProductRankWeekly.kt`

```kotlin
package com.loopers.domain.ranking

import com.loopers.domain.BaseEntity
import jakarta.persistence.*

@Entity
@Table(name = "mv_product_rank_weekly")
class ProductRankWeekly(
    val productId: Long,
    val yearWeek: String,
    val score: Double,
    val rankPosition: Int
) : BaseEntity()
```

---

## 3.3 ProductRankMonthly Entity

**파일**: `modules/jpa/src/main/kotlin/com/loopers/domain/ranking/ProductRankMonthly.kt`

```kotlin
package com.loopers.domain.ranking

import com.loopers.domain.BaseEntity
import jakarta.persistence.*

@Entity
@Table(name = "mv_product_rank_monthly")
class ProductRankMonthly(
    val productId: Long,
    val yearMonth: String,
    val score: Double,
    val rankPosition: Int
) : BaseEntity()
```

---

## 3.4 ProductRankWeeklyRepository

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/infrastructure/ranking/ProductRankWeeklyRepository.kt`

```kotlin
package com.loopers.infrastructure.ranking

import com.loopers.domain.ranking.ProductRankWeekly
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query

interface ProductRankWeeklyRepository : JpaRepository<ProductRankWeekly, Long> {

    @Modifying
    @Query("DELETE FROM ProductRankWeekly m WHERE m.yearWeek = :yearWeek")
    fun deleteByYearWeek(yearWeek: String): Int

    fun findByYearWeekOrderByRankPositionAsc(yearWeek: String): List<ProductRankWeekly>
}
```

**주요 개선:**
- `deleteByYearWeek()` 반환 타입 `Int` 추가 (삭제된 행 수 반환)
- PR #76 패턴 반영

---

## 3.5 ProductRankMonthlyRepository

**파일**: `apps/commerce-batch/src/main/kotlin/com/loopers/infrastructure/ranking/ProductRankMonthlyRepository.kt`

```kotlin
package com.loopers.infrastructure.ranking

import com.loopers.domain.ranking.ProductRankMonthly
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Modifying
import org.springframework.data.jpa.repository.Query

interface ProductRankMonthlyRepository : JpaRepository<ProductRankMonthly, Long> {

    @Modifying
    @Query("DELETE FROM ProductRankMonthly m WHERE m.yearMonth = :yearMonth")
    fun deleteByYearMonth(yearMonth: String): Int

    fun findByYearMonthOrderByRankPositionAsc(yearMonth: String): List<ProductRankMonthly>
}
```

---

## 3.6 빌드 확인

```bash
./gradlew :apps:commerce-batch:build
```

**에러 없이 빌드 성공 확인**

---

## ✅ Step 3 완료 체크

- [ ] ProductRankWeekly Entity 작성
- [ ] ProductRankMonthly Entity 작성
- [ ] ProductRankWeeklyRepository 작성
- [ ] ProductRankMonthlyRepository 작성
- [ ] 빌드 성공 확인

---

**다음 단계**: [Step 4: DateUtils 유틸리티](./STEP4_UTILS.md)
