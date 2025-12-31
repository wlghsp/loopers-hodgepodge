# 🎯 Step 4: 상품 상세 조회에 랭킹 정보 추가

> **목표**: 기존 상품 상세 조회 API에 해당 상품의 현재 순위를 함께 반환합니다.

---

## 🧠 이해하기: 지금까지 만든 것 복습

### Step 1-3에서 만든 흐름

```
[사용자가 상품 조회]
    ↓
[ProductViewedEvent 발행] ← commerce-api
    ↓
[Kafka로 전송]
    ↓
[RankingKafkaConsumer 수신] ← commerce-streamer
    ↓
[RankingService.incrementScore()] ← modules/redis
    ↓
[Redis ZSET에 점수 저장]
    예: ranking:all:20251223 → {product:101: 125.5}
```

### Step 3에서 만든 랭킹 조회 API

```
GET /api/v1/rankings?page=0&size=20
    ↓
[RankingFacade.getRankings()]
    ↓
[RankingService.getProductsInRange()] → Redis에서 랭킹 ID 리스트 조회
    ↓
[ProductFacade.getProductsByIds()] → DB에서 상품 정보 조회
    ↓
[두 정보를 합쳐서 반환]
    → [{id:101, name:"나이키", rank:1, score:125.5}, ...]
```

**Step 3의 한계**: 랭킹 **목록**만 볼 수 있음. 개별 상품 페이지에는 순위가 없음.

---

## 📌 왜 상품 상세에 랭킹을 추가하는가?

### 현재 상황 (Step 3까지)
```
사용자가 "나이키 에어맥스" 상품 상세 페이지를 봄
GET /api/v1/products/101
→ {id: 101, name: "나이키 에어맥스", price: 150000, stock: 50}
```
❌ 문제: **"지금 몇 위인지"를 모름** → 구매 욕구 낮음

### 개선 후 (Step 4)
```
GET /api/v1/products/101
→ {id: 101, name: "나이키 에어맥스", price: 150000, stock: 50, rank: 3, score: 98.5}
```
✅ 해결: "지금 3위!" 배지 표시 → 구매 욕구 증가 (사회적 증거)

### 설계 고려사항

**Q1: 목록 조회(getProducts)에도 랭킹을 넣어야 하나?**
```kotlin
GET /api/v1/products?page=0&size=20
→ 20개 상품 리스트
```
**답**: ❌ 안 넣는다
- 이유: 20개 상품 × 각각 Redis 조회 = 20번 호출 → 느림
- 대안: 랭킹이 필요하면 `/api/v1/rankings` API 사용

**Q2: null의 의미는?**
```kotlin
{rank: 3}      // 3위!
{rank: null}   // 무슨 뜻?
```
**답**: 순위권 밖 (인기 없는 상품)
- Redis에 해당 상품 데이터가 없음
- 프론트엔드에서는 순위 배지를 표시하지 않음

**Q3: Redis 조회가 항상 일어나면 느리지 않나?**
**답**: ✅ Redis는 매우 빠름 (평균 <1ms)
- DB 조회 (10-50ms)에 비하면 무시할 수준
- 사용자 경험을 위해 trade-off

---

## 4-1. ProductV1Dto 확장

### 💡 설계 결정: 필드 추가 vs 별도 API?

**선택지 1**: 기존 DTO에 `rank` 필드 추가
- 장점: 클라이언트가 1번의 API 호출로 모든 정보 획득
- 단점: 항상 랭킹 조회 → Redis 호출 증가

**선택지 2**: 별도 API 생성 (`GET /api/v1/products/{id}/rank`)
- 장점: 필요할 때만 랭킹 조회
- 단점: 클라이언트가 2번 호출 필요

**우리의 선택**: **선택지 1** (필드 추가)
- Redis 조회는 매우 빠름 (<1ms)
- 사용자 경험 우선 (빠른 로딩)
- 순위권 밖이면 null 반환 (불필요한 연산 최소화)

### 📂 파일 수정

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/product/ProductV1Dto.kt`

```kotlin
package com.loopers.interfaces.api.product

import com.loopers.application.product.ProductInfo
import io.swagger.v3.oas.annotations.media.Schema

class ProductV1Dto {

    /**
     * 상품 응답 DTO (랭킹 정보 포함)
     *
     * @property id 상품 ID
     * @property name 상품명
     * @property description 상품 설명
     * @property price 가격
     * @property stock 재고
     * @property likesCount 좋아요 수
     * @property rank 현재 순위 (순위권 밖이면 null)
     * @property score 랭킹 점수 (순위권 밖이면 null)
     */
    @Schema(description = "상품 정보")
    data class ProductResponse(
        @Schema(description = "상품 ID", example = "1")
        val id: Long,

        @Schema(description = "상품명", example = "나이키 에어맥스")
        val name: String,

        @Schema(description = "상품 설명")
        val description: String?,

        @Schema(description = "가격", example = "150000")
        val price: Long,

        @Schema(description = "재고", example = "50")
        val stock: Int,

        @Schema(description = "좋아요 수", example = "120")
        val likesCount: Int,

        @Schema(description = "현재 순위 (1부터 시작, 순위권 밖이면 null)", example = "3")
        val rank: Long? = null,  // 기존 API 호환성을 위해 기본값 null

        @Schema(description = "랭킹 점수 (순위권 밖이면 null)", example = "98.5")
        val score: Double? = null
    ) {
        companion object {
            /**
             * ProductInfo로부터 변환 (랭킹 정보 없음)
             */
            fun from(info: ProductInfo): ProductResponse {
                return ProductResponse(
                    id = info.id,
                    name = info.name,
                    description = info.description,
                    price = info.price.amount,
                    stock = info.stock,
                    likesCount = info.likesCount,
                    rank = null,
                    score = null
                )
            }

            /**
             * ProductInfo와 랭킹 정보로부터 변환
             */
            fun fromWithRanking(info: ProductInfo, rank: Long?, score: Double?): ProductResponse {
                return ProductResponse(
                    id = info.id,
                    name = info.name,
                    description = info.description,
                    price = info.price.amount,
                    stock = info.stock,
                    likesCount = info.likesCount,
                    rank = rank,
                    score = score
                )
            }
        }
    }
}
```

### ✅ 핵심 포인트
- **하위 호환성**: 기존 API는 `rank=null`로 동작 (기존 클라이언트 영향 없음)
- **선택적 랭킹**: `fromWithRanking()` 메서드로 랭킹 포함 여부 선택
- **Nullable 타입**: 순위권 밖이면 null (명확한 의미 전달)

---

## 4-2. ProductFacade 확장

### 🧠 이해하기: Controller에서 직접 호출하면 안 되나?

**나쁜 예시** (Controller에서 직접 두 Facade 호출):
```kotlin
@GetMapping("/{productId}")
fun getProduct(@PathVariable productId: Long): ProductResponse {
    // Controller에서 2개 Facade 호출
    val product = productFacade.getProduct(productId)  // 1. 상품 정보
    val ranking = rankingFacade.getProductRank(productId, null)  // 2. 랭킹 정보

    // Controller에서 병합 로직
    return ProductResponse.fromWithRanking(product, ranking?.rank, ranking?.score)
}
```

**문제점**:
- ❌ Controller가 비즈니스 로직을 알아야 함 (어떤 Facade를 어떻게 호출?)
- ❌ 트랜잭션 관리 어려움
- ❌ 테스트 복잡함 (2개 Facade를 Mocking)

**좋은 예시** (Facade에 통합):
```kotlin
@GetMapping("/{productId}")
fun getProduct(@PathVariable productId: Long): ProductResponse {
    // Controller는 단순히 Facade 호출
    val result = productFacade.getProductWithRanking(productId)
    return ProductResponse.fromWithRanking(result.product, result.rank, result.score)
}
```

**장점**:
- ✅ Controller는 단순해짐 (1개 Facade만 호출)
- ✅ 비즈니스 로직은 Facade에 캡슐화
- ✅ 테스트 쉬움

---

### ⚠️ 순환 참조(Circular Dependency) 문제

### 문제 발생 상황

Step 3에서 이미 이렇게 만들었습니다:
```kotlin
// RankingFacade.kt (Step 3)
@Component
class RankingFacade(
    private val rankingService: RankingService,
    private val productFacade: ProductFacade  // 👈 ProductFacade 의존!
) {
    fun getRankings(...) {
        val productIds = rankingService.getProductsInRange(...)
        val products = productFacade.getProductsByIds(productIds)  // 상품 정보 조회
        // ...
    }
}
```

이제 Step 4에서 이렇게 하려고 합니다:
```kotlin
// ProductFacade.kt (Step 4)
@Component
class ProductFacade(
    private val productService: ProductService,
    private val rankingFacade: RankingFacade  // 👈 RankingFacade 의존!
) {
    fun getProductWithRanking(id: Long) {
        val product = getProduct(id)
        val ranking = rankingFacade.getProductRank(id, null)  // 랭킹 조회
        // ...
    }
}
```

**문제**: 순환 참조!
```
ProductFacade → RankingFacade
     ↑              ↓
     └──────────────┘
```

Spring이 Bean을 생성할 때:
1. ProductFacade를 만들려면 → RankingFacade가 필요
2. RankingFacade를 만들려면 → ProductFacade가 필요
3. 🔄 무한 루프! → 애플리케이션 시작 실패

### 해결 방법 비교

#### 방법 1: `@Lazy` 사용 (빠른 해결)
```kotlin
@Component
class ProductFacade(
    private val productService: ProductService,
    @Lazy private val rankingFacade: RankingFacade  // 👈 @Lazy 추가!
) {
    // ...
}
```

**동작 원리**:
```
1. Spring이 ProductFacade를 생성할 때
   → RankingFacade의 Proxy(가짜 객체)를 주입

2. 실제로 rankingFacade.getProductRank()를 호출할 때
   → 그때 진짜 RankingFacade를 가져옴
```

**장점**:
- ✅ 코드 수정 최소 (한 줄만 추가)
- ✅ 빠르게 해결 가능

**단점**:
- ⚠️ 순환 참조 자체는 여전히 존재 (설계 문제)
- ⚠️ 나중에 더 복잡해질 수 있음

---

#### 방법 2: 의존성 방향 재설계 ✅ (채택!)

**핵심 아이디어**: RankingFacade가 ProductFacade 대신 **ProductService**를 직접 의존

```
변경 전:
RankingFacade → ProductFacade → ProductService
                      ↑
                ProductFacade → RankingFacade (순환!)

변경 후:
RankingFacade → ProductService (직접 의존)
ProductFacade → RankingFacade (단방향!)
```

**장점**:
- ✅ 순환 참조 자체가 없어짐 (깔끔한 설계)
- ✅ 장기적으로 유지보수 좋음
- ✅ Facade 계층 의존성이 명확해짐

**단점**:
- ⚠️ Step 3 코드를 수정해야 함 (이미 수정 완료!)
- ⚠️ ProductFacade의 캐시를 사용하지 못함 (하지만 랭킹 조회는 캐시 히트율이 낮아서 괜찮음)

**Q: 캐시는 어떻게 되나요?**
- `getRankings()`는 매번 다른 productId 조합이므로 캐시 히트율이 낮음
- DB 일괄 조회 (IN 절)가 오히려 효율적
- 개별 상품 조회 시 ProductFacade의 캐시를 사용 (Step 4에서)

---

### 🔧 Step 3 코드 수정 (이미 완료됨!)

**파일**: `apps/commerce-api/src/main/kotlin/com/loopers/application/ranking/RankingFacade.kt`

```kotlin
// 변경 전
@Component
class RankingFacade(
    private val rankingService: RankingService,
    private val productFacade: ProductFacade  // ❌ Facade 의존
) {
    fun getRankings(...) {
        val products = productFacade.getProductsByIds(productIds)
        // ...
    }
}

// ✅ 변경 후 (순환 참조 제거)
@Component
class RankingFacade(
    private val rankingService: RankingService,
    private val productService: ProductService  // ✅ Service 직접 의존
) {
    fun getRankings(...) {
        // Product → ProductInfo 변환 필요
        val products = productService.getProductsByIds(productIds)
            .map { ProductInfo.from(it) }
            .associateBy { it.id }
        // ...
    }

    fun getProductRank(productId: Long, dateStr: String?): RankingInfo? {
        // ...
        val product = productService.getProduct(productId)
        val productInfo = ProductInfo.from(product)
        return RankingInfo(product = productInfo, ...)
    }
}
```

**변경 사항**:
1. `ProductFacade` → `ProductService` 의존성 변경
2. `Product` 엔티티를 `ProductInfo`로 변환하는 코드 추가
3. import 정리: `ProductFacade` 제거

---

### 🤔 스스로 생각해보기

**Q1**: 왜 ProductService를 직접 쓰는 게 나은가?
- 정답: Facade는 Application Layer의 오케스트레이션 역할. Service는 Domain Layer. Facade끼리 의존하면 복잡해짐.

**Q2**: 캐시를 못 쓰는 게 문제가 아닐까?
- 정답: 랭킹 조회는 매번 다른 조합(20위, 21위...)이라 캐시 효과가 적음. DB IN 절이 더 효율적.

**Q3**: `@Lazy` 대신 이 방법을 선택한 이유는?
- 정답: 순환 참조는 설계 문제를 숨기는 것. 근본 원인을 해결하는 게 장기적으로 좋음.

### 📂 파일 수정

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/application/product/ProductFacade.kt`

```kotlin
package com.loopers.application.product

import com.loopers.application.ranking.RankingFacade
import com.loopers.domain.product.ProductService
import com.loopers.domain.product.ProductSortType
import com.loopers.infrastructure.product.ProductCacheStore
import org.springframework.context.annotation.Lazy
import org.springframework.data.domain.Page
import org.springframework.data.domain.Pageable
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional

@Component
class ProductFacade(
    private val productService: ProductService,
    private val productCacheStore: ProductCacheStore,
    @Lazy private val rankingFacade: RankingFacade  // @Lazy로 순환 참조 해결
) {
    // 기존 메서드들...

    /**
     * 상품 상세 조회 (랭킹 정보 포함)
     *
     * 왜 랭킹 조회를 선택적으로 하지 않는가?
     * - Redis 조회는 매우 빠름 (평균 <1ms)
     * - 사용자는 항상 "몇 위인지" 궁금해함
     * - 순위권 밖이면 null 반환 (성능 영향 없음)
     *
     * @param id 상품 ID
     * @param includeRanking 랭킹 정보 포함 여부 (기본값: true)
     * @return 상품 정보 + 랭킹 정보
     */
    @Transactional(readOnly = true)
    fun getProductWithRanking(id: Long, includeRanking: Boolean = true): ProductInfoWithRanking {
        val product = getProduct(id)  // 기존 메서드 재사용 (캐시 적용됨)

        if (!includeRanking) {
            return ProductInfoWithRanking(
                product = product,
                rank = null,
                score = null
            )
        }

        // 랭킹 정보 조회 (순위권 밖이면 null)
        val rankingInfo = rankingFacade.getProductRank(id, null)

        return ProductInfoWithRanking(
            product = product,
            rank = rankingInfo?.rank,
            score = rankingInfo?.score
        )
    }

    // 기존 메서드는 그대로 유지 (하위 호환성)
    @Transactional(readOnly = true)
    fun getProduct(id: Long): ProductInfo {
        // 1. 캐시 조회
        productCacheStore.getProduct(id)?.let {
            return it
        }

        // 2. DB 조회
        val product = productService.getProduct(id)
        val productInfo = ProductInfo.from(product)

        // 3. 캐시 저장
        productCacheStore.setProduct(id, productInfo)

        return productInfo
    }

    @Transactional(readOnly = true)
    fun getProductsByIds(productIds: List<Long>): List<ProductInfo> {
        if (productIds.isEmpty()) {
            return emptyList()
        }

        return productService.getProductsByIds(productIds)
            .map { ProductInfo.from(it) }
    }

    @Transactional(readOnly = true)
    fun getProducts(
        brandId: Long?,
        sort: ProductSortType,
        pageable: Pageable
    ): Page<ProductInfo> {
        // 기존 로직...
        return productService.getProducts(brandId, sort, pageable)
            .map { ProductInfo.from(it) }
    }
}

/**
 * 랭킹 정보가 포함된 상품 정보
 *
 * @property product 상품 정보
 * @property rank 현재 순위 (순위권 밖이면 null)
 * @property score 랭킹 점수 (순위권 밖이면 null)
 */
data class ProductInfoWithRanking(
    val product: ProductInfo,
    val rank: Long?,
    val score: Double?
)
```

### ✅ 핵심 포인트
- **@Lazy 주입**: 순환 참조 해결을 위해 RankingFacade를 지연 초기화
- **기존 메서드 유지**: `getProduct()`는 그대로 (다른 곳에서 사용 중일 수 있음)
- **새 메서드 추가**: `getProductWithRanking()`으로 확장
- **선택적 랭킹**: `includeRanking` 파라미터로 제어 가능 (기본값 true)

---

## 4-3. ProductV1Controller 수정

### 📂 파일 수정

**경로**: `apps/commerce-api/src/main/kotlin/com/loopers/interfaces/api/product/ProductV1Controller.kt`

```kotlin
package com.loopers.interfaces.api.product

import com.loopers.application.product.ProductFacade
import com.loopers.domain.product.ProductSortType
import com.loopers.domain.product.event.ProductBrowsedEvent
import com.loopers.domain.product.event.ProductViewedEvent
import com.loopers.interfaces.api.ApiResponse
import org.springframework.context.ApplicationEventPublisher
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.time.Instant

@RestController
@RequestMapping("/api/v1/products")
class ProductV1Controller(
    private val productFacade: ProductFacade,
    private val eventPublisher: ApplicationEventPublisher,
) : ProductV1ApiSpec {

    /**
     * 상품 목록 조회 (랭킹 정보 없음)
     */
    @GetMapping
    override fun getProducts(
        @RequestHeader(value = "X-USER-ID", required = false) memberId: String?,
        @RequestParam(required = false) brandId: Long?,
        @RequestParam(required = false, defaultValue = "LATEST") sort: ProductSortType,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int,
    ): ApiResponse<Page<ProductV1Dto.ProductResponse>> {
        val pageable = PageRequest.of(page, size)

        val result = productFacade.getProducts(brandId, sort, pageable)
            .map { ProductV1Dto.ProductResponse.from(it) }  // 랭킹 없음
            .let { ApiResponse.success(it) }

        eventPublisher.publishEvent(
            ProductBrowsedEvent(
                memberId = memberId,
                brandId = brandId,
                sortType = sort.name,
                page = page,
                browsedAt = Instant.now()
            )
        )

        return result
    }

    /**
     * 상품 상세 조회 (랭킹 정보 포함)
     *
     * 변경 사항:
     * - getProduct() → getProductWithRanking()
     * - ProductResponse.from() → fromWithRanking()
     */
    @GetMapping("/{productId}")
    override fun getProduct(
        @RequestHeader(value = "X-USER-ID", required = false) memberId: String?,
        @PathVariable productId: Long,
    ): ApiResponse<ProductV1Dto.ProductResponse> {
        // 상품 정보 + 랭킹 정보 조회
        val productWithRanking = productFacade.getProductWithRanking(productId)

        val result = ProductV1Dto.ProductResponse.fromWithRanking(
            info = productWithRanking.product,
            rank = productWithRanking.rank,
            score = productWithRanking.score
        ).let { ApiResponse.success(it) }

        eventPublisher.publishEvent(
            ProductViewedEvent(
                aggregateId = productId,
                productId = productId,
                memberId = memberId,
                viewedAt = Instant.now()
            )
        )

        return result
    }
}
```

### ✅ 핵심 포인트
- **목록 조회**: 랭킹 정보 없음 (성능 고려)
- **상세 조회**: 랭킹 정보 포함 (사용자 관심사)
- **이벤트 발행**: 기존과 동일 (ProductViewedEvent)

---

## 🧪 Step 4 검증 방법

### 1. API 테스트 (cURL)

```bash
# 상품 상세 조회 (랭킹 정보 포함)
curl -X GET "http://localhost:8080/api/v1/products/101"
```

### 2. 응답 예시 (순위권 내 상품)

```json
{
  "success": true,
  "data": {
    "id": 101,
    "name": "나이키 에어맥스",
    "description": "편안한 운동화",
    "price": 150000,
    "stock": 50,
    "likesCount": 120,
    "rank": 3,           // 추가됨
    "score": 98.5        // 추가됨
  }
}
```

### 3. 응답 예시 (순위권 밖 상품)

```json
{
  "success": true,
  "data": {
    "id": 999,
    "name": "잘 안팔리는 상품",
    "description": "설명",
    "price": 50000,
    "stock": 100,
    "likesCount": 2,
    "rank": null,        // 순위권 밖
    "score": null        // 점수 없음
  }
}
```

---

## 🎯 Step 4 구현 순서 (단계별로 진행하세요!)

### Phase 1: DTO 확장 (난이도: ⭐)
**목표**: API 응답에 rank, score 필드 추가

1. [ ] `ProductV1Dto.kt` 파일 열기
2. [ ] `ProductResponse` data class에 필드 2개 추가:
   - `val rank: Long? = null`
   - `val score: Double? = null`
3. [ ] `fromWithRanking()` 메서드 추가 (companion object 안에)
4. [ ] 컴파일 확인: `./gradlew :apps:commerce-api:compileKotlin`

**검증**: 컴파일 에러 없으면 성공!

---

### Phase 2: Facade 확장 - 준비 (난이도: ⭐⭐)
**목표**: 랭킹 정보를 담을 데이터 클래스 만들기

5. [ ] `ProductFacade.kt` 파일 맨 아래에 `ProductInfoWithRanking` data class 추가:
```kotlin
data class ProductInfoWithRanking(
    val product: ProductInfo,
    val rank: Long?,
    val score: Double?
)
```
6. [ ] 컴파일 확인

**검증**: 컴파일 에러 없으면 성공!

---

### Phase 3: Facade 확장 - 메서드 껍데기 (난이도: ⭐⭐)
**목표**: `getProductWithRanking()` 메서드 만들기 (일단 랭킹은 null)

7. [ ] `ProductFacade` 클래스 안에 새 메서드 추가:
```kotlin
@Transactional(readOnly = true)
fun getProductWithRanking(id: Long): ProductInfoWithRanking {
    val product = getProduct(id)  // 기존 메서드 재사용

    // TODO: 나중에 랭킹 조회 추가
    return ProductInfoWithRanking(
        product = product,
        rank = null,  // 일단 null
        score = null
    )
}
```
8. [ ] 컴파일 확인

**검증**: 컴파일 에러 없으면 성공! (아직 랭킹은 항상 null)

---

### Phase 4: 랭킹 조회 구현 (난이도: ⭐⭐)
**목표**: 실제로 랭킹을 조회하도록 수정 (순환 참조 걱정 없음!)

9. [ ] `ProductFacade` 클래스 상단에 import 추가:
```kotlin
import com.loopers.application.ranking.RankingFacade
```

10. [ ] 생성자에 `RankingFacade` 주입:
```kotlin
@Component
class ProductFacade(
    private val productService: ProductService,
    private val productCacheStore: ProductCacheStore,
    private val rankingFacade: RankingFacade  // 👈 이거 추가! (@Lazy 불필요)
) {
```

**중요**: `@Lazy`가 필요 없는 이유?
- Step 3에서 RankingFacade를 이미 수정해서 ProductFacade를 의존하지 않음
- 단방향 의존성이므로 순환 참조 발생 안 함!

11. [ ] `getProductWithRanking()` 메서드에서 실제 랭킹 조회:
```kotlin
@Transactional(readOnly = true)
fun getProductWithRanking(id: Long): ProductInfoWithRanking {
    val product = getProduct(id)  // 캐시 적용됨

    // 랭킹 정보 조회 (순위권 밖이면 null)
    val rankingInfo = rankingFacade.getProductRank(id, null)

    return ProductInfoWithRanking(
        product = product,
        rank = rankingInfo?.rank,
        score = rankingInfo?.score
    )
}
```

12. [ ] 컴파일 확인

**검증**:
- 컴파일 에러 없으면 성공!
- 애플리케이션 시작 시 순환 참조 에러 발생하지 않음 ✅

---

### Phase 5: Controller 수정 (난이도: ⭐⭐)
**목표**: 상품 상세 조회 시 랭킹 정보 포함

13. [ ] `ProductV1Controller.kt` 파일 열기

14. [ ] `getProduct()` 메서드 수정:
```kotlin
@GetMapping("/{productId}")
override fun getProduct(
    @RequestHeader(value = "X-USER-ID", required = false) memberId: String?,
    @PathVariable productId: Long,
): ApiResponse<ProductV1Dto.ProductResponse> {
    // 변경: getProduct() → getProductWithRanking()
    val productWithRanking = productFacade.getProductWithRanking(productId)

    // 변경: from() → fromWithRanking()
    val result = ProductV1Dto.ProductResponse.fromWithRanking(
        info = productWithRanking.product,
        rank = productWithRanking.rank,
        score = productWithRanking.score
    ).let { ApiResponse.success(it) }

    // 이벤트 발행은 그대로
    eventPublisher.publishEvent(
        ProductViewedEvent(
            aggregateId = productId,
            productId = productId,
            memberId = memberId,
            viewedAt = Instant.now()
        )
    )

    return result
}
```

15. [ ] 컴파일 확인: `./gradlew :apps:commerce-api:compileKotlin`

**검증**: 컴파일 성공하면 완료!

---

## ✅ Step 4 완료 체크리스트

### 구현 완료
- [x] Phase 1: DTO 확장 (`rank`, `score` 필드 추가)
- [x] Phase 2: ProductInfoWithRanking 생성
- [x] Phase 3: getProductWithRanking 메서드 추가
- [x] Phase 4: RankingFacade 의존성 주입 (순환 참조 없음!)
- [x] Phase 5: Controller 수정 (getProduct → getProductWithRanking)
- [x] 최종 컴파일 확인 (`BUILD SUCCESSFUL`)

### 보너스 구현
- [x] `includeRanking` 파라미터 추가 (선택적 랭킹 조회)

### 테스트 (선택)
- [ ] 애플리케이션 시작 시 순환 참조 에러 없는지 확인
- [ ] API 호출 시 랭킹 정보가 포함되는지 확인
- [ ] 순위권 밖 상품은 `rank: null`로 반환되는지 확인
- [ ] Swagger UI에서 API 문서 업데이트 확인

---

## 📚 다음 단계 미리보기

**Step 5**에서는:
- 전체 시스템 통합 테스트
- Redis 데이터 검증
- 성능 테스트 방법
- 트러블슈팅 가이드

Step 4 완료하셨으면 마지막 단계로 넘어가겠습니다! 🎉
