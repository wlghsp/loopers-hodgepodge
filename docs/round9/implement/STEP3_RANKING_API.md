# 🎯 Step 3: Ranking API 구현 (commerce-api)

> **목표**: Redis ZSET에 저장된 랭킹 데이터를 조회하는 API를 구현하고, 상품 정보와 함께 반환합니다.

---

## 📌 왜 Ranking API가 필요한가?

Consumer가 Redis에 랭킹을 쌓아두는 것만으로는 의미가 없습니다:
- ✅ 사용자에게 "오늘의 인기 상품" 노출
- ✅ 상품 상세 페이지에 "현재 N위" 배지 표시
- ✅ 페이지네이션으로 대용량 랭킹 효율적 조회

---

## 3-1. 공통 모듈 설정 (중요!)

### 💡 왜 공통 모듈이 필요한가?

`RankingService`를 commerce-streamer와 commerce-api 양쪽에서 사용하려면:
- ❌ 코드 중복 (유지보수 어려움)
- ❌ 버전 불일치 (한쪽만 수정 시 버그)

**해결책**: `RankingService`를 **modules/redis**로 이동하여 공유합니다.

### 📂 파일 이동

**✅ 이동 완료**:
- `RankingService.kt` → `modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingService.kt`
  - API 조회용 메서드 추가: `getProductsInRange()`, `getProductRank()`
- `RankingKeyGenerator.kt` → `modules/redis/src/main/kotlin/com/loopers/domain/ranking/RankingKeyGenerator.kt`

**유지**:
- `RankingScoreCalculator.kt`는 **commerce-streamer에만 필요** (그대로 유지)

**왜 RankingScoreCalculator는 이동하지 않는가?**
- **의존성 문제**: RankingScoreCalculator는 DomainEvent(`ProductViewedEvent`, `ProductLikedEvent` 등)에 의존
- **이벤트 위치**: 이 이벤트들은 `commerce-api`와 `commerce-streamer`에 각각 존재
- **순환 참조 위험**: modules/redis가 commerce-api를 의존하면 순환 참조 발생
- **사용처**: RankingScoreCalculator는 오직 Consumer에서만 사용 (API에서는 불필요)
- **결론**: commerce-streamer에만 두어 명확한 의존성 방향 유지

모듈 의존성 방향:
```
commerce-api → modules/redis (RankingService 사용)
commerce-streamer → modules/redis (RankingService 사용)
commerce-streamer 내부에서만 RankingScoreCalculator 사용
```

### 📝 build.gradle 설정 확인

**✅ 의존성 확인 완료**:
- `modules/redis/build.gradle.kts`: Redis 의존성 존재
- `apps/commerce-api/build.gradle.kts`: `modules:redis` 의존성 존재
- `apps/commerce-streamer/build.gradle.kts`: `modules:redis` 의존성 존재

---

## 3-2. RankingFacade (Application Layer)

### 💡 왜 Facade가 필요한가?

Controller에서 직접 `RankingService`와 `ProductService`를 호출하면:
- ❌ Controller가 너무 복잡해짐 (비즈니스 로직 혼재)
- ❌ 여러 서비스 호출 순서가 Controller에 노출
- ❌ 트랜잭션 관리가 어려움

**해결책**: Application Layer에 Facade를 두어 오케스트레이션합니다.

### 📂 파일 생성

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingFacade.kt`

```kotlin
package com.loopers.application.ranking

import com.loopers.application.product.ProductFacade
import com.loopers.application.product.ProductInfo
import com.loopers.domain.ranking.RankingKeyGenerator
import com.loopers.domain.ranking.RankingService
import org.slf4j.LoggerFactory
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageImpl
import org.springframework.data.domain.Pageable
import org.springframework.stereotype.Component
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * 랭킹 조회 Facade (Application Layer)
 *
 * 역할:
 * 1. Redis에서 랭킹 데이터 조회
 * 2. 상품 정보 Aggregation (ID → 전체 정보)
 * 3. 페이지네이션 처리
 *
 * 왜 상품 정보를 함께 반환하는가?
 * - 프론트엔드가 productId만 받으면 N번의 추가 API 호출 필요
 * - Aggregation으로 1번의 요청으로 모든 정보 제공
 * - 사용자 경험 개선 (빠른 로딩)
 */
@Component
class RankingFacade(
    private val rankingService: RankingService,
    private val productFacade: ProductFacade
) {
    private val logger = LoggerFactory.getLogger(javaClass)
    private val dateFormatter = DateTimeFormatter.ofPattern("yyyyMMdd")

    /**
     * 랭킹 페이지 조회 (상품 정보 포함)
     *
     * @param dateStr 날짜 문자열 (yyyyMMdd, null이면 오늘)
     * @param pageable 페이지 정보 (page, size)
     * @return 상품 정보가 포함된 랭킹 페이지
     */
    fun getRankings(dateStr: String?, pageable: Pageable): Page<RankingInfo> {
        val date = dateStr?.let { LocalDate.parse(it, dateFormatter) } ?: LocalDate.now()

        // 페이지네이션 계산 (0-based)
        val start = pageable.offset  // page * size
        val end = start + pageable.pageSize - 1

        logger.debug("랭킹 조회: date=$date, start=$start, end=$end")

        // 1. Redis에서 랭킹 데이터 조회
        val rankings = rankingService.getProductsInRange(date, start, end)

        if (rankings.isEmpty()) {
            logger.info("랭킹 데이터 없음: date=$date")
            return Page.empty(pageable)
        }

        // 2. 상품 ID 추출
        val productIds = rankings.map { it.first }

        // 3. 상품 정보 조회 (ProductFacade 활용 - 캐시 적용됨)
        val products = productFacade.getProductsByIds(productIds)
            .associateBy { it.id }

        // 4. 랭킹 정보와 상품 정보 결합
        val rankingInfos = rankings.mapIndexedNotNull { index, (productId, score) ->
            val product = products[productId]
            if (product == null) {
                logger.warn("상품 정보 없음: productId=$productId (삭제된 상품일 수 있음)")
                null
            } else {
                RankingInfo(
                    product = product,
                    rank = start + index + 1,  // 0-based → 1-based
                    score = score
                )
            }
        }

        // 5. 전체 개수 조회 (ZCARD)
        val totalElements = rankingService.getRankingSize(date)

        return PageImpl(rankingInfos, pageable, totalElements)
    }

    /**
     * 특정 상품의 랭킹 정보 조회
     *
     * @param productId 상품 ID
     * @param dateStr 날짜 문자열 (yyyyMMdd, null이면 오늘)
     * @return 랭킹 정보 (순위권에 없으면 null)
     */
    fun getProductRank(productId: Long, dateStr: String?): RankingInfo? {
        val date = dateStr?.let { LocalDate.parse(it, dateFormatter) } ?: LocalDate.now()

        // 1. Redis에서 순위 조회 (0-based)
        val rank = rankingService.getProductRank(date, productId) ?: return null
        val score = rankingService.getProductScore(date, productId) ?: return null

        // 2. 상품 정보 조회
        val product = productFacade.getProduct(productId)

        return RankingInfo(
            product = product,
            rank = rank + 1,  // 0-based → 1-based
            score = score
        )
    }
}

/**
 * 랭킹 정보 (상품 정보 + 순위 + 점수)
 *
 * @property product 상품 정보
 * @property rank 순위 (1부터 시작)
 * @property score 랭킹 점수
 */
data class RankingInfo(
    val product: ProductInfo,
    val rank: Long,
    val score: Double
)
```

### ✅ 핵심 포인트
- **상품 정보 Aggregation**: `productService.getProductsByIds()`로 일괄 조회 (N+1 문제 방지)
- **ProductFacade 대신 ProductService 사용**: 순환 참조 방지를 위해 Service Layer를 직접 의존
- **Product → ProductInfo 변환**: Service에서 받은 엔티티를 DTO로 변환
- **삭제된 상품 처리**: 상품 정보가 없으면 `null`로 필터링 (랭킹에서 제외)
- **0-based → 1-based**: Redis는 0부터 시작, API는 1부터 반환

---

## 3-3. ~~ProductFacade 확장~~ (불필요 - ProductService 직접 사용)

### 💡 설계 변경

**원래 계획**: RankingFacade → ProductFacade → ProductService
- 문제: Step 4에서 ProductFacade → RankingFacade 의존성 추가 시 순환 참조 발생

**변경된 설계**: RankingFacade → ProductService (직접 의존)
- 해결: 순환 참조 없음, 깔끔한 단방향 의존성

**결론**: ProductFacade에 `getProductsByIds()` 추가는 필요 없음 (하지만 있어도 문제 없음)

### 📂 파일 수정

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/application/product/ProductFacade.kt`

```kotlin
// 기존 코드에 추가
package com.loopers.application.product

import com.loopers.domain.product.ProductService
import com.loopers.infrastructure.product.ProductCacheStore
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional

@Component
class ProductFacade(
    private val productService: ProductService,
    private val productCacheStore: ProductCacheStore
) {
    // 기존 메서드들...

    /**
     * 여러 상품 정보 일괄 조회
     *
     * 왜 캐시를 사용하지 않는가?
     * - 랭킹 조회는 매번 다른 상품 조합 (캐시 히트율 낮음)
     * - DB 일괄 조회(IN 절)가 더 효율적
     *
     * @param productIds 상품 ID 리스트
     * @return 상품 정보 리스트 (없는 ID는 제외됨)
     */
    @Transactional(readOnly = true)
    fun getProductsByIds(productIds: List<Long>): List<ProductInfo> {
        if (productIds.isEmpty()) {
            return emptyList()
        }

        return productService.getProductsByIds(productIds)
            .map { ProductInfo.from(it) }
    }
}
```

### 📂 ProductService 확장

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/domain/product/ProductService.kt`

**✅ 이미 구현되어 있음**:
```kotlin
@Transactional(readOnly = true)
fun getProductsByIds(productIds: List<Long>): List<Product> {
    return productRepository.findAllByIdIn(productIds)
}
```

---

## 3-4. RankingV1Controller

### 📂 파일 생성

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Controller.kt`

```kotlin
package com.loopers.interfaces.api.ranking

import com.loopers.application.ranking.RankingFacade
import com.loopers.interfaces.api.ApiResponse
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.Parameter
import io.swagger.v3.oas.annotations.tags.Tag
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.web.bind.annotation.*

/**
 * 랭킹 API (V1)
 *
 * 제공 기능:
 * 1. 일간 랭킹 조회 (페이지네이션)
 * 2. 특정 상품의 순위 조회
 */
@Tag(name = "Ranking V1 API", description = "상품 랭킹 관련 API")
@RestController
@RequestMapping("/api/v1/rankings")
class RankingV1Controller(
    private val rankingFacade: RankingFacade
) {

    /**
     * 일간 랭킹 조회
     *
     * 예시:
     * - GET /api/v1/rankings?date=20251222&page=0&size=20
     * - GET /api/v1/rankings (오늘 날짜, 첫 페이지)
     *
     * @param date 날짜 (yyyyMMdd 형식, 기본값: 오늘)
     * @param page 페이지 번호 (0부터 시작, 기본값: 0)
     * @param size 페이지 크기 (기본값: 20)
     * @return 랭킹 정보 페이지 (상품 정보 포함)
     */
    @Operation(
        summary = "일간 랭킹 조회",
        description = "특정 날짜의 상품 랭킹을 페이지 단위로 조회합니다. 상품 정보가 함께 반환됩니다."
    )
    @GetMapping
    fun getRankings(
        @Parameter(description = "날짜 (yyyyMMdd 형식), 미입력 시 오늘 날짜")
        @RequestParam(required = false) date: String?,

        @Parameter(description = "페이지 번호 (0부터 시작)")
        @RequestParam(defaultValue = "0") page: Int,

        @Parameter(description = "페이지 크기 (최대 100)")
        @RequestParam(defaultValue = "20") size: Int
    ): ApiResponse<Page<RankingV1Dto.RankingResponse>> {
        // 페이지 크기 제한 (DoS 방지)
        val validSize = size.coerceIn(1, 100)
        val pageable = PageRequest.of(page, validSize)

        val rankings = rankingFacade.getRankings(date, pageable)

        return ApiResponse.success(
            rankings.map { RankingV1Dto.RankingResponse.from(it) }
        )
    }
}
```

### ✅ 핵심 포인트
- **페이지 크기 제한**: 최대 100개로 제한 (DoS 공격 방지)
- **Swagger 문서화**: @Operation, @Parameter로 API 명세 자동 생성
- **기본값 설정**: date는 오늘, page는 0, size는 20

---

## 3-5. RankingV1Dto

### 📂 파일 생성

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/ranking/RankingV1Dto.kt`

```kotlin
package com.loopers.interfaces.api.ranking

import com.loopers.application.ranking.RankingInfo
import io.swagger.v3.oas.annotations.media.Schema

/**
 * Ranking API DTO
 */
object RankingV1Dto {

    /**
     * 랭킹 응답 DTO
     *
     * @property productId 상품 ID
     * @property productName 상품명
     * @property price 가격
     * @property stock 재고
     * @property likesCount 좋아요 수
     * @property rank 순위 (1부터 시작)
     * @property score 랭킹 점수
     */
    @Schema(description = "랭킹 정보")
    data class RankingResponse(
        @Schema(description = "상품 ID", example = "1")
        val productId: Long,

        @Schema(description = "상품명", example = "나이키 에어맥스")
        val productName: String,

        @Schema(description = "가격", example = "150000")
        val price: Long,

        @Schema(description = "재고", example = "50")
        val stock: Int,

        @Schema(description = "좋아요 수", example = "120")
        val likesCount: Int,

        @Schema(description = "순위 (1부터 시작)", example = "1")
        val rank: Long,

        @Schema(description = "랭킹 점수", example = "125.5")
        val score: Double
    ) {
        companion object {
            fun from(info: RankingInfo): RankingResponse {
                val product = info.product
                return RankingResponse(
                    productId = product.id,
                    productName = product.name,
                    price = product.price.amount,
                    stock = product.stock,
                    likesCount = product.likesCount,
                    rank = info.rank,
                    score = info.score
                )
            }
        }
    }
}
```

### ✅ 핵심 포인트
- **Swagger 문서화**: @Schema로 각 필드 설명 추가
- **ProductInfo 변환**: 필요한 필드만 노출 (캡슐화)

---

## 🧪 Step 3 검증 방법

### 1. API 테스트 (cURL)

```bash
# 오늘의 Top 20 조회
curl -X GET "http://localhost:8080/api/v1/rankings?page=0&size=20"

# 특정 날짜 랭킹 조회
curl -X GET "http://localhost:8080/api/v1/rankings?date=20251222&page=0&size=20"

# 2페이지 조회 (21위~40위)
curl -X GET "http://localhost:8080/api/v1/rankings?page=1&size=20"
```

### 2. 응답 예시

```json
{
  "success": true,
  "data": {
    "content": [
      {
        "productId": 101,
        "productName": "나이키 에어맥스",
        "price": 150000,
        "stock": 50,
        "likesCount": 120,
        "rank": 1,
        "score": 125.5
      },
      {
        "productId": 202,
        "productName": "아디다스 슈퍼스타",
        "price": 120000,
        "stock": 30,
        "likesCount": 95,
        "rank": 2,
        "score": 98.3
      }
    ],
    "pageable": {
      "pageNumber": 0,
      "pageSize": 20
    },
    "totalElements": 150,
    "totalPages": 8
  }
}
```

### 3. Swagger UI 확인

```
http://localhost:8080/swagger-ui/index.html
→ Ranking V1 API 섹션 확인
```

---

## 🎯 Step 3 완료 체크리스트

- [x] `RankingService`를 `modules/redis`로 이동 완료
  - [x] API 조회용 메서드 추가 (`getProductsInRange`, `getProductRank`)
- [x] `RankingKeyGenerator`를 `modules/redis`로 이동 완료
- [x] `RankingFacade.kt` 파일 생성 및 컴파일 확인
- [x] `ProductFacade` 확장 (`getProductsByIds` 추가)
- [x] `ProductService`의 `getProductsByIds` 확인 (이미 존재함)
- [x] `RankingV1ApiSpec.kt` 인터페이스 생성 (Swagger 문서화)
- [x] `RankingV1Dto.kt` 파일 생성
- [x] `RankingV1Controller.kt` 파일 생성
- [x] 컴파일 확인 완료
- [ ] API 호출 시 정상 응답 확인 (상품 정보 포함)
- [ ] Swagger UI에서 API 문서 확인
- [ ] 페이지네이션 동작 확인 (page=0, page=1)

---

## 🎓 Step 3 요약: 무엇을 배웠나?

### 핵심 개념

1. **공통 모듈 분리**:
   - `modules/redis`에 RankingService를 두어 commerce-api와 commerce-streamer가 공유
   - 코드 중복 방지, 유지보수 편리

2. **Facade 패턴**:
   - RankingFacade가 RankingService와 ProductFacade를 조율
   - Controller는 단순하게 유지

3. **N+1 문제 해결**:
   - `getProductsByIds()`로 일괄 조회 (IN 절 사용)
   - 20개 상품 → 1번 DB 쿼리

4. **Pagination**:
   - Redis ZREVRANGE로 범위 조회
   - 페이지 크기 제한으로 DoS 방지

### 아키텍처 흐름

```
GET /api/v1/rankings?page=0&size=20
    ↓
RankingV1Controller (Interface Layer)
    ↓
RankingFacade (Application Layer)
    ├→ RankingService.getProductsInRange() → Redis ZSET 조회
    └→ ProductFacade.getProductsByIds() → DB 일괄 조회
    ↓
두 정보를 병합하여 반환
```

### 구현한 파일들

- ✅ `modules/redis/RankingService.kt` - Redis 조회 메서드 추가
- ✅ `modules/redis/RankingKeyGenerator.kt` - 키 생성 로직 공유
- ✅ `RankingFacade.kt` - 랭킹 + 상품 정보 조합
- ✅ `RankingV1ApiSpec.kt` - Swagger 문서화
- ✅ `RankingV1Dto.kt` - API 응답 DTO
- ✅ `RankingV1Controller.kt` - REST API

---

## 📚 다음 단계 미리보기

**Step 4**에서는:
- 상품 상세 조회 API에 랭킹 정보 추가
- `ProductV1Dto` 확장 (rank 필드 추가)
- 순위권 밖 상품은 rank: null 처리
- **순환 참조 문제** 해결 (@Lazy 사용)

Step 3 완료하셨으면 다음 단계로 넘어가겠습니다! 👍
