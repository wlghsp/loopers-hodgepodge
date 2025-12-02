# 5주차 성능 개선 작업 체크리스트 ✅

## ✅ 완료된 작업

- [x] Aggregate 참조 관계 제거 (Product, Brand, OrderItem)
- [x] 테스트 코드 수정
- [x] DTO Projection 제거 (불필요)
- [x] 인덱스 설정 (Product Entity에 정의됨 - 자동 생성)
- [x] 성능 개선 문서 작성

---

## 🔥 남은 작업

### 1. Redis 캐시 구현 (RedisTemplate 사용)

#### 1-1. RedisConfig 작성
```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/infrastructure/config/RedisConfig.kt
@Configuration
class RedisConfig {
    @Bean
    fun redisTemplate(factory: RedisConnectionFactory): StringRedisTemplate {
        return StringRedisTemplate(factory)
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

#### 1-2. ProductCacheService 구현
```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/application/product/ProductCacheService.kt
@Component
class ProductCacheService(
    private val redisTemplate: StringRedisTemplate,
    private val objectMapper: ObjectMapper
) {
    companion object {
        private const val PRODUCT_CACHE_PREFIX = "product:"
        private const val PRODUCT_LIST_CACHE_PREFIX = "products:"
        private const val PRODUCT_TTL_SECONDS = 600L // 10분
        private const val PRODUCT_LIST_TTL_SECONDS = 300L // 5분
    }

    fun getProduct(id: Long): ProductInfo? {
        val key = "$PRODUCT_CACHE_PREFIX$id"
        val cached = redisTemplate.opsForValue().get(key) ?: return null
        return objectMapper.readValue(cached, ProductInfo::class.java)
    }

    fun setProduct(id: Long, product: ProductInfo) {
        val key = "$PRODUCT_CACHE_PREFIX$id"
        val json = objectMapper.writeValueAsString(product)
        redisTemplate.opsForValue().set(key, json, PRODUCT_TTL_SECONDS, TimeUnit.SECONDS)
    }

    fun getProductList(brandId: Long?, sort: ProductSortType, page: Int): String? {
        val key = buildListCacheKey(brandId, sort, page)
        return redisTemplate.opsForValue().get(key)
    }

    fun setProductList(brandId: Long?, sort: ProductSortType, page: Int, data: String) {
        val key = buildListCacheKey(brandId, sort, page)
        redisTemplate.opsForValue().set(key, data, PRODUCT_LIST_TTL_SECONDS, TimeUnit.SECONDS)
    }

    fun evictProduct(id: Long) {
        redisTemplate.delete("$PRODUCT_CACHE_PREFIX$id")
    }

    fun evictProductLists() {
        val pattern = "$PRODUCT_LIST_CACHE_PREFIX*"
        val keys = redisTemplate.keys(pattern)
        if (keys.isNotEmpty()) {
            redisTemplate.delete(keys)
        }
    }

    private fun buildListCacheKey(brandId: Long?, sort: ProductSortType, page: Int): String {
        val brand = brandId ?: "all"
        return "${PRODUCT_LIST_CACHE_PREFIX}brand:${brand}:sort:${sort}:page:${page}"
    }
}
```

#### 1-3. ProductFacade 캐시 적용
```kotlin
// apps/commerce-api/src/main/kotlin/com/loopers/application/product/ProductFacade.kt
@Component
class ProductFacade(
    private val productService: ProductService,
    private val productCacheService: ProductCacheService,
    private val objectMapper: ObjectMapper
) {
    
    // 상품 상세 조회 - 캐시 적용
    fun getProduct(productId: Long): ProductInfo {
        val cached = productCacheService.getProduct(productId)
        if (cached != null) return cached
        
        val product = productService.getProduct(productId)
        val productInfo = ProductInfo.from(product)
        productCacheService.setProduct(productId, productInfo)
        return productInfo
    }
    
    // 상품 목록 조회 - 캐시 적용
    fun getProducts(
        brandId: Long?,
        sort: ProductSortType,
        pageable: Pageable
    ): Page<ProductInfo> {
        val cached = productCacheService.getProductList(brandId, sort, pageable.pageNumber)
        if (cached != null) {
            return objectMapper.readValue(cached, object : TypeReference<PageImpl<ProductInfo>>() {})
        }
        
        val products = productService.getProducts(brandId, sort, pageable)
        val productInfoPage = ProductInfo.fromPage(products)
        val json = objectMapper.writeValueAsString(productInfoPage)
        productCacheService.setProductList(brandId, sort, pageable.pageNumber, json)
        return productInfoPage
    }
    
    // 상품 수정 시 캐시 무효화
    @Transactional
    fun updateProduct(id: Long, request: UpdateProductRequest): ProductInfo {
        val product = productService.updateProduct(id, request)
        productCacheService.evictProduct(id)
        productCacheService.evictProductLists()
        return ProductInfo.from(product)
    }
}
```

---

### 2. 테스트 및 측정

#### 2-1. Redis 실행 확인
```bash
docker ps | grep redis
# 없으면 docker-compose up -d redis
```

#### 2-2. 애플리케이션 실행
```bash
./gradlew :apps:commerce-api:bootRun
```

#### 2-3. API 테스트
```bash
# 캐시 미스 (첫 조회)
GET http://localhost:8080/api/v1/products?brandId=1&sort=LIKES_DESC&page=0&size=20

# 캐시 히트 (재조회)
GET http://localhost:8080/api/v1/products?brandId=1&sort=LIKES_DESC&page=0&size=20
```

#### 2-4. Redis 캐시 확인
```bash
# 캐시 키 목록
redis-cli KEYS "product*"

# 특정 캐시 내용
redis-cli GET "product:1"

# TTL 확인
redis-cli TTL "product:1"
```

---

## 📸 캡처 필요 항목

### 캐시 적용 후
- [ ] 캐시 미스 시 응답 시간 (첫 조회)
- [ ] 캐시 히트 시 응답 시간 (재조회)
- [ ] Redis 캐시 키 목록 (`redis-cli KEYS "product*"`)
- [ ] Redis TTL 확인 (`redis-cli TTL "product:1"`)

---

## 🎯 최종 확인

- [ ] Redis 캐시 구현 완료
- [ ] API 테스트 성공 (캐시 히트/미스 확인)
- [ ] 성능 측정 완료 (캐시 미스/히트 응답 시간)
- [ ] Redis 캐시 확인 (키 목록, TTL)
- [ ] 필요한 캡처 완료
- [ ] 문서에 캡처 추가

---

**작업 순서:**
1. Redis 캐시 구현 (30분)
2. 테스트 및 측정 (10분)
3. 캡처 및 문서 마무리 (10분)

**예상 소요 시간: 약 50분**

