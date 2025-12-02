# Redis 캐시 학습 가이드

## 목차

1. [Redis 캐시란?](#1-redis-캐시란)
2. [캐시 패턴](#2-캐시-패턴)
3. [RedisTemplate 사용법](#3-redistemplate-사용법)
4. [TTL 전략](#4-ttl-전략)
5. [캐시 키 설계](#5-캐시-키-설계)
6. [무효화 전략](#6-무효화-전략)
7. [실제 구현 예시](#7-실제-구현-예시)
8. [모니터링](#8-모니터링)
9. [장애 대응](#9-장애-대응)

---

## 1. Redis 캐시란?

### 개념

**Redis (Remote Dictionary Server)**
- 인메모리 데이터 저장소
- Key-Value 형태로 데이터 저장
- 매우 빠른 읽기/쓰기 성능 (메모리 기반)

**캐시의 목적:**
- 자주 조회되는 데이터를 메모리에 저장
- DB 접근 없이 빠른 응답
- DB 부하 감소

### 왜 필요한가?

**문제 상황:**
```
사용자 1000명이 동시에 인기 상품 조회
→ DB에 1000번 쿼리 발생
→ DB 부하 증가, 응답 시간 증가
```

**캐시 적용 후:**
```
첫 번째 사용자: DB 조회 (50ms) → Redis 저장
나머지 999명: Redis 조회 (5ms)
→ DB 쿼리 1번만 발생
→ 응답 시간 10배 향상
```

---

## 2. 캐시 패턴

### Look-Aside (Cache-Aside) 패턴 ⭐ 가장 일반적

**동작 방식:**
```
1. 캐시 조회
2. 캐시 히트 → 반환
3. 캐시 미스 → DB 조회 → 캐시 저장 → 반환
```

**장점:**
- 구현 간단
- 캐시 장애 시에도 서비스 정상 동작
- 캐시와 DB 독립적

**단점:**
- 캐시 미스 시 지연 발생
- 데이터 정합성 관리 필요

**구현 예시:**
```kotlin
fun getProduct(id: Long): ProductInfo {
    // 1. 캐시 조회
    val cached = cacheService.getProduct(id)
    if (cached != null) {
        return cached  // 캐시 히트
    }
    
    // 2. 캐시 미스 - DB 조회
    val product = productService.getProduct(id)
    val productInfo = ProductInfo.from(product)
    
    // 3. 캐시 저장
    cacheService.setProduct(id, productInfo)
    
    return productInfo
}
```

### Write-Through 패턴

**동작 방식:**
```
1. 데이터 수정 시
2. DB 저장 + 캐시 저장 (동시에)
```

**장점:**
- 캐시와 DB 항상 일치
- 캐시 미스 없음

**단점:**
- 쓰기 성능 저하 (두 번 저장)
- 불필요한 데이터도 캐시에 저장

### Write-Back 패턴

**동작 방식:**
```
1. 데이터 수정 시
2. 캐시에만 저장
3. 나중에 배치로 DB 저장
```

**장점:**
- 쓰기 성능 매우 빠름

**단점:**
- 데이터 손실 위험 (캐시 장애 시)
- 복잡한 구현

---

## 3. RedisTemplate 사용법

### 기본 설정

```kotlin
@Configuration
class RedisConfig {
    
    @Bean
    fun redisTemplate(
        redisConnectionFactory: RedisConnectionFactory
    ): StringRedisTemplate {
        return StringRedisTemplate(redisConnectionFactory)
    }
    
    @Bean
    fun objectMapper(): ObjectMapper {
        return ObjectMapper().apply {
            registerModule(JavaTimeModule())
            disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
        }
    }
}
```

### 기본 명령어

```kotlin
// SET (저장)
redisTemplate.opsForValue().set("key", "value")

// SET with TTL (TTL과 함께 저장)
redisTemplate.opsForValue().set("key", "value", 60, TimeUnit.SECONDS)

// GET (조회)
val value = redisTemplate.opsForValue().get("key")

// DELETE (삭제)
redisTemplate.delete("key")

// EXISTS (존재 확인)
val exists = redisTemplate.hasKey("key")

// TTL 확인
val ttl = redisTemplate.getExpire("key", TimeUnit.SECONDS)

// KEYS (패턴 매칭)
val keys = redisTemplate.keys("product:*")
```

### JSON 직렬화/역직렬화

```kotlin
@Component
class ProductCacheService(
    private val redisTemplate: StringRedisTemplate,
    private val objectMapper: ObjectMapper
) {
    // 저장 (객체 → JSON → String)
    fun setProduct(id: Long, product: ProductInfo) {
        val key = "product:$id"
        val json = objectMapper.writeValueAsString(product)
        redisTemplate.opsForValue().set(key, json, 600, TimeUnit.SECONDS)
    }
    
    // 조회 (String → JSON → 객체)
    fun getProduct(id: Long): ProductInfo? {
        val key = "product:$id"
        val json = redisTemplate.opsForValue().get(key) ?: return null
        return objectMapper.readValue(json, ProductInfo::class.java)
    }
}
```

---

## 4. TTL 전략

### TTL (Time To Live)이란?

캐시 데이터의 생존 시간. 시간이 지나면 자동으로 삭제됨.

### TTL 설정 기준

**1. 데이터 변경 빈도**
```
변경 빈도 높음 → TTL 짧게 (1-5분)
변경 빈도 낮음 → TTL 길게 (10-30분)
```

**2. 실시간성 요구사항**
```
실시간 중요 → TTL 짧게 (1-5분)
약간 지연 허용 → TTL 길게 (10-30분)
```

**3. 메모리 사용량**
```
메모리 부족 → TTL 짧게
메모리 여유 → TTL 길게
```

### 실제 적용 예시

```kotlin
companion object {
    // 상품 상세: 가격/설명 변경 빈도 낮음
    private const val PRODUCT_TTL_SECONDS = 600L // 10분
    
    // 상품 목록: 좋아요 수 변동 빠름
    private const val PRODUCT_LIST_TTL_SECONDS = 300L // 5분
    
    // 인기 상품: 자주 조회되지만 변동 적음
    private const val POPULAR_PRODUCT_TTL_SECONDS = 1800L // 30분
}
```

### TTL 갱신 전략

**Option 1: 고정 TTL**
```kotlin
// 항상 10분
redisTemplate.opsForValue().set(key, value, 600, TimeUnit.SECONDS)
```

**Option 2: 접근 시 TTL 갱신**
```kotlin
fun getProduct(id: Long): ProductInfo? {
    val key = "product:$id"
    val json = redisTemplate.opsForValue().get(key)
    
    if (json != null) {
        // 접근 시 TTL 갱신 (10분 연장)
        redisTemplate.expire(key, 600, TimeUnit.SECONDS)
    }
    
    return json?.let { objectMapper.readValue(it, ProductInfo::class.java) }
}
```

---

## 5. 캐시 키 설계

### 좋은 캐시 키의 조건

1. **명확한 의미**
   ```
   ✅ product:123
   ❌ p:123
   ```

2. **일관된 네이밍**
   ```
   ✅ product:123
   ✅ products:brand:1:page:0
   ❌ product:123, productList:brand:1
   ```

3. **Prefix 사용**
   ```
   ✅ product:123
   ✅ products:brand:1
   → 패턴 매칭으로 일괄 삭제 가능
   ```

4. **조건 포함**
   ```
   ✅ products:brand:1:sort:LIKES_DESC:page:0
   → 정확한 캐시 히트
   ```

### 실제 예시

```kotlin
companion object {
    private const val PRODUCT_PREFIX = "product:"
    private const val PRODUCT_LIST_PREFIX = "products:"
}

// 상품 상세
fun getProductKey(id: Long): String {
    return "$PRODUCT_PREFIX$id"
}
// 결과: product:123

// 상품 목록
fun getProductListKey(brandId: Long?, sort: ProductSortType, page: Int): String {
    val brand = brandId ?: "all"
    return "${PRODUCT_LIST_PREFIX}brand:$brand:sort:$sort:page:$page"
}
// 결과: products:brand:1:sort:LIKES_DESC:page:0
```

### 키 네이밍 규칙

```
{도메인}:{타입}:{조건1}:{조건2}:...

예시:
- product:123 (상품 상세)
- products:brand:1:sort:LIKES_DESC:page:0 (상품 목록)
- user:session:abc123 (사용자 세션)
- order:member:user123:page:0 (주문 목록)
```

---

## 6. 무효화 전략

### 무효화가 필요한 경우

1. **데이터 수정 시**
   ```
   상품 가격 변경 → 상품 상세 캐시 무효화
   ```

2. **데이터 삭제 시**
   ```
   상품 삭제 → 상품 상세 + 목록 캐시 무효화
   ```

3. **관련 데이터 변경 시**
   ```
   좋아요 추가 → 상품 상세 + 목록 캐시 무효화
   ```

### 무효화 방법

**1. 개별 삭제**
```kotlin
fun evictProduct(id: Long) {
    redisTemplate.delete("product:$id")
}
```

**2. 패턴 매칭 삭제**
```kotlin
fun evictProductLists() {
    val pattern = "products:*"
    val keys = redisTemplate.keys(pattern)
    if (keys.isNotEmpty()) {
        redisTemplate.delete(keys)
    }
}
```

**3. 전체 삭제 (비권장)**
```kotlin
fun evictAll() {
    redisTemplate.execute { connection ->
        connection.serverCommands().flushDb()
    }
}
```

### 무효화 전략 선택

**Option 1: 개별 무효화 (정교함)**
```kotlin
// 상품 수정 시
fun updateProduct(id: Long, request: UpdateProductRequest) {
    productService.updateProduct(id, request)
    
    // 해당 상품만 무효화
    cacheService.evictProduct(id)
    
    // 관련 목록만 무효화 (브랜드별, 정렬별)
    cacheService.evictProductListByBrand(product.brandId)
}
```

**장점:** 정확한 무효화, 캐시 히트율 높음  
**단점:** 복잡한 구현, 추적 어려움

**Option 2: 전체 무효화 (단순함) ⭐ 권장**
```kotlin
// 상품 수정 시
fun updateProduct(id: Long, request: UpdateProductRequest) {
    productService.updateProduct(id, request)
    
    // 해당 상품 무효화
    cacheService.evictProduct(id)
    
    // 모든 목록 캐시 무효화
    cacheService.evictProductLists()
}
```

**장점:** 구현 간단, 실수 없음  
**단점:** 캐시 히트율 일시 감소

**선택 기준:**
- 수정 빈도 낮음 → 전체 무효화
- 수정 빈도 높음 → 개별 무효화
- 초기 구현 → 전체 무효화 (나중에 개선)

---

## 7. 실제 구현 예시

### 전체 코드

```kotlin
@Component
class ProductCacheService(
    private val redisTemplate: StringRedisTemplate,
    private val objectMapper: ObjectMapper
) {
    companion object {
        private const val PRODUCT_PREFIX = "product:"
        private const val PRODUCT_LIST_PREFIX = "products:"
        private const val PRODUCT_TTL_SECONDS = 600L // 10분
        private const val PRODUCT_LIST_TTL_SECONDS = 300L // 5분
    }

    // 상품 상세 조회
    fun getProduct(id: Long): ProductInfo? {
        val key = "$PRODUCT_PREFIX$id"
        val json = redisTemplate.opsForValue().get(key) ?: return null
        return objectMapper.readValue(json, ProductInfo::class.java)
    }

    // 상품 상세 저장
    fun setProduct(id: Long, product: ProductInfo) {
        val key = "$PRODUCT_PREFIX$id"
        val json = objectMapper.writeValueAsString(product)
        redisTemplate.opsForValue().set(key, json, PRODUCT_TTL_SECONDS, TimeUnit.SECONDS)
    }

    // 상품 목록 조회
    fun getProductList(brandId: Long?, sort: ProductSortType, page: Int): String? {
        val key = buildListKey(brandId, sort, page)
        return redisTemplate.opsForValue().get(key)
    }

    // 상품 목록 저장
    fun setProductList(brandId: Long?, sort: ProductSortType, page: Int, data: String) {
        val key = buildListKey(brandId, sort, page)
        redisTemplate.opsForValue().set(key, data, PRODUCT_LIST_TTL_SECONDS, TimeUnit.SECONDS)
    }

    // 상품 캐시 무효화
    fun evictProduct(id: Long) {
        redisTemplate.delete("$PRODUCT_PREFIX$id")
    }

    // 상품 목록 캐시 전체 무효화
    fun evictProductLists() {
        val pattern = "$PRODUCT_LIST_PREFIX*"
        val keys = redisTemplate.keys(pattern)
        if (keys.isNotEmpty()) {
            redisTemplate.delete(keys)
        }
    }

    private fun buildListKey(brandId: Long?, sort: ProductSortType, page: Int): String {
        val brand = brandId ?: "all"
        return "${PRODUCT_LIST_PREFIX}brand:$brand:sort:$sort:page:$page"
    }
}
```

### Facade에서 사용

```kotlin
@Component
class ProductFacade(
    private val productService: ProductService,
    private val productCacheService: ProductCacheService,
    private val objectMapper: ObjectMapper
) {
    // 상품 상세 조회 (Look-Aside 패턴)
    fun getProduct(productId: Long): ProductInfo {
        // 1. 캐시 조회
        val cached = productCacheService.getProduct(productId)
        if (cached != null) {
            return cached
        }

        // 2. 캐시 미스 - DB 조회
        val product = productService.getProduct(productId)
        val productInfo = ProductInfo.from(product)

        // 3. 캐시 저장
        productCacheService.setProduct(productId, productInfo)

        return productInfo
    }

    // 상품 목록 조회
    fun getProducts(
        brandId: Long?,
        sort: ProductSortType,
        pageable: Pageable
    ): Page<ProductInfo> {
        // 1. 캐시 조회
        val cached = productCacheService.getProductList(brandId, sort, pageable.pageNumber)
        if (cached != null) {
            return objectMapper.readValue(cached, object : TypeReference<PageImpl<ProductInfo>>() {})
        }

        // 2. 캐시 미스 - DB 조회
        val products = productService.getProducts(brandId, sort, pageable)
        val productInfoPage = ProductInfo.fromPage(products)

        // 3. 캐시 저장
        val json = objectMapper.writeValueAsString(productInfoPage)
        productCacheService.setProductList(brandId, sort, pageable.pageNumber, json)

        return productInfoPage
    }

    // 상품 수정 시 캐시 무효화
    @Transactional
    fun updateProduct(id: Long, request: UpdateProductRequest): ProductInfo {
        val product = productService.updateProduct(id, request)
        
        // 캐시 무효화
        productCacheService.evictProduct(id)
        productCacheService.evictProductLists()
        
        return ProductInfo.from(product)
    }
}
```

---

## 8. 모니터링

### Redis CLI 명령어

```bash
# 캐시 키 목록 확인
redis-cli KEYS "product:*"
redis-cli KEYS "products:*"

# 특정 캐시 조회
redis-cli GET "product:123"

# TTL 확인
redis-cli TTL "product:123"
# -1: TTL 없음 (만료 안 됨)
# -2: 키 없음
# 양수: 남은 초

# 캐시 삭제
redis-cli DEL "product:123"

# 패턴 매칭 삭제
redis-cli KEYS "products:*" | xargs redis-cli DEL

# 전체 키 개수
redis-cli DBSIZE

# 메모리 사용량
redis-cli INFO memory
```

### 캐시 히트율 계산

```kotlin
@Component
class CacheMetrics(
    private val redisTemplate: StringRedisTemplate
) {
    private var hitCount = AtomicLong(0)
    private var missCount = AtomicLong(0)

    fun recordHit() {
        hitCount.incrementAndGet()
    }

    fun recordMiss() {
        missCount.incrementAndGet()
    }

    fun getHitRate(): Double {
        val total = hitCount.get() + missCount.get()
        if (total == 0L) return 0.0
        return hitCount.get().toDouble() / total * 100
    }
}
```

**사용 예시:**
```kotlin
fun getProduct(id: Long): ProductInfo {
    val cached = productCacheService.getProduct(id)
    if (cached != null) {
        cacheMetrics.recordHit()  // 히트
        return cached
    }
    
    cacheMetrics.recordMiss()  // 미스
    // DB 조회...
}
```

### 예상 캐시 히트율

- 인기 상품: 90% 이상
- 일반 상품: 50-70%
- 신규 상품: 10-30%

---

## 9. 장애 대응

### Redis 장애 시 동작

**현재 구현:**
```kotlin
fun getProduct(id: Long): ProductInfo {
    val cached = productCacheService.getProduct(id)
    if (cached != null) {
        return cached
    }
    // Redis 장애 시 null 반환 → 자동으로 DB 조회
    val product = productService.getProduct(id)
    // ...
}
```

**결과:**
- ✅ Redis 장애 시에도 서비스 정상 동작
- ⚠️ 응답 시간만 느려짐 (DB 조회)

### Circuit Breaker 패턴 (고급)

```kotlin
@Component
class ProductCacheService(
    private val redisTemplate: StringRedisTemplate,
    private val objectMapper: ObjectMapper
) {
    private var circuitOpen = false
    private var lastFailureTime = 0L

    fun getProduct(id: Long): ProductInfo? {
        // Circuit Breaker 체크
        if (circuitOpen) {
            if (System.currentTimeMillis() - lastFailureTime > 60000) {
                circuitOpen = false  // 1분 후 재시도
            } else {
                return null  // Circuit 열림 → 바로 DB 조회
            }
        }

        return try {
            val key = "product:$id"
            val json = redisTemplate.opsForValue().get(key)
            json?.let { objectMapper.readValue(it, ProductInfo::class.java) }
        } catch (e: Exception) {
            circuitOpen = true
            lastFailureTime = System.currentTimeMillis()
            null  // Redis 장애 → DB 조회
        }
    }
}
```

### 캐시 워밍업

**애플리케이션 시작 시 인기 상품 캐시 미리 로드:**

```kotlin
@Component
class CacheWarmupService(
    private val productService: ProductService,
    private val productCacheService: ProductCacheService
) {
    @PostConstruct
    fun warmupCache() {
        // 인기 상품 TOP 100 캐시 미리 로드
        val popularProducts = productService.getPopularProducts(100)
        popularProducts.forEach { product ->
            val productInfo = ProductInfo.from(product)
            productCacheService.setProduct(product.id!!, productInfo)
        }
    }
}
```

---

## 핵심 정리

### Redis 캐시 적용 체크리스트

- ✅ Redis 설정 (RedisConfig)
- ✅ 캐시 서비스 구현 (CacheService)
- ✅ Look-Aside 패턴 적용 (Facade)
- ✅ TTL 설정 (데이터 특성에 맞게)
- ✅ 캐시 키 설계 (명확하고 일관되게)
- ✅ 무효화 전략 (수정 시 삭제)
- ✅ 장애 대응 (null 체크로 안전하게)

### 성능 개선 효과

| 항목 | 캐시 미스 | 캐시 히트 | 개선 |
|------|----------|----------|------|
| 응답 시간 | 50ms | 5ms | 10배 |
| DB 쿼리 | 발생 | 미발생 | 100% 감소 |
| DB 부하 | 100% | 20% | 80% 감소 |

### 학습 포인트

1. **Look-Aside 패턴** - 가장 일반적이고 안전
2. **TTL 전략** - 데이터 특성에 맞게 설정
3. **캐시 키 설계** - 명확하고 일관되게
4. **무효화 전략** - 데이터 수정 시 반드시 삭제
5. **장애 대응** - Redis 장애 시에도 서비스 정상 동작

---

_참고: Spring Cache (`@Cacheable`)도 있지만, RedisTemplate을 직접 사용하면 Redis 동작 원리를 더 깊이 이해할 수 있습니다._



