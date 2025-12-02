# 상품 10만개 데이터 생성 가이드

> 5주차 과제 - 인덱스 성능 테스트를 위한 대량 데이터 생성

---

## ⭐ 추천: Docker Compose 자동 실행 (가장 간편)

Docker Compose로 인프라를 띄울 때 자동으로 데이터가 생성됩니다.

### 설정 완료됨
- `docker/init-data.sql`: 브랜드 100개 + 상품 10만개 생성 스크립트
- `docker/infra-compose.yml`: MySQL 컨테이너에 init-data.sql 마운트 설정

### 실행 방법
```bash
# 기존 MySQL 볼륨 삭제 (데이터 초기화)
docker-compose -f ./docker/infra-compose.yml down -v

# 인프라 재시작 (자동으로 데이터 생성됨)
docker-compose -f ./docker/infra-compose.yml up -d

# 로그 확인 (데이터 생성 확인)
docker-compose -f ./docker/infra-compose.yml logs mysql
```

### 주의사항
- **초기 생성 시에만** 실행됨 (MySQL 볼륨이 새로 생성될 때)
- 이미 데이터가 있으면 실행 안됨
- 데이터 재생성하려면 볼륨 삭제 후 재시작: `down -v`

### 실행 시간
- **3~10초** 내 완료

---

## 방법 1: SQL 스크립트 수동 실행

MySQL에서 직접 실행하는 방식입니다.

### 실행 방법
```bash
# MySQL 접속
mysql -u application -p -h localhost -P 3306 loopers

# 또는 Docker 컨테이너 접속
docker exec -it <container_name> mysql -u application -p loopers
```

### SQL 스크립트

```sql
-- ================================================
-- 1. 브랜드 100개 생성
-- ================================================
INSERT INTO brands (name, description, created_at, updated_at)
SELECT
    CONCAT('Brand_', LPAD(seq, 3, '0')),
    CONCAT('브랜드 ', seq, ' 설명'),
    NOW(),
    NOW()
FROM (
    SELECT @rownum := @rownum + 1 AS seq
    FROM information_schema.columns a,
         information_schema.columns b,
         (SELECT @rownum := 0) r
    LIMIT 100
) AS numbers;

-- 생성 확인
SELECT COUNT(*) FROM brands;

-- ================================================
-- 2. 상품 10만개 생성
-- ================================================
-- 브랜드 랜덤, 가격/좋아요 다양하게 분포
INSERT INTO products (name, description, price, stock, brand_id, likes_count, created_at, updated_at)
SELECT
    CONCAT('Product_', LPAD(seq, 6, '0')),
    CONCAT('상품 ', seq, ' 상세 설명'),
    FLOOR(1000 + RAND() * 99000),                    -- 가격: 1,000 ~ 100,000
    FLOOR(10 + RAND() * 990),                        -- 재고: 10 ~ 1,000
    FLOOR(1 + RAND() * 100),                         -- brand_id: 1 ~ 100
    FLOOR(RAND() * RAND() * 10000),                  -- 좋아요: 0 ~ 10,000 (편향 분포)
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY),
    NOW()
FROM (
    SELECT @rownum := @rownum + 1 AS seq
    FROM information_schema.columns a,
         information_schema.columns b,
         information_schema.columns c,
         (SELECT @rownum := 0) r
    LIMIT 100000
) AS numbers;

-- 생성 확인
SELECT COUNT(*) FROM products;

-- 데이터 분포 확인
SELECT
    brand_id,
    COUNT(*) as product_count,
    AVG(likes_count) as avg_likes,
    MAX(likes_count) as max_likes
FROM products
GROUP BY brand_id
ORDER BY brand_id
LIMIT 10;
```

### 장점/단점
- ✅ 가장 빠름 (수 초 내 완료)
- ❌ `ddl-auto: create` 설정 시 앱 재시작하면 데이터 유실

---

## 방법 2: Kotlin DataInitializer (추천)

애플리케이션 시작 시 자동으로 데이터를 생성합니다.

### 파일 생성 위치
```
apps/commerce-api/src/main/kotlin/com/loopers/config/DataInitializer.kt
```

### 코드

```kotlin
package com.loopers.config

import com.loopers.domain.brand.Brand
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component
import org.springframework.transaction.annotation.Transactional
import kotlin.random.Random

@Component
@Profile("local")  // local 프로필에서만 실행
class DataInitializer(
    private val brandJpaRepository: BrandJpaRepository,
    private val productJpaRepository: ProductJpaRepository,
) : ApplicationRunner {

    @Transactional
    override fun run(args: ApplicationArguments) {
        // 이미 데이터가 있으면 스킵
        if (productJpaRepository.count() > 0) {
            println("✅ 데이터가 이미 존재합니다. 초기화를 건너뜁니다.")
            return
        }

        println("=== 🚀 대량 데이터 생성 시작 ===")
        val startTime = System.currentTimeMillis()

        // 1. 브랜드 100개 생성
        val brands = createBrands()

        // 2. 상품 10만개 생성
        createProducts(brands)

        val elapsed = System.currentTimeMillis() - startTime
        println("=== ✅ 대량 데이터 생성 완료 (${elapsed}ms) ===")
    }

    private fun createBrands(): List<Brand> {
        val brands = (1..100).map { i ->
            Brand(
                name = "Brand_${i.toString().padStart(3, '0')}",
                description = "브랜드 $i 설명"
            )
        }
        brandJpaRepository.saveAll(brands)
        println("📦 브랜드 ${brands.size}개 생성 완료")
        return brands
    }

    private fun createProducts(brands: List<Brand>) {
        val batchSize = 1000
        val totalProducts = 100_000

        repeat(totalProducts / batchSize) { batch ->
            val products = (1..batchSize).map { i ->
                val seq = batch * batchSize + i
                val brand = brands[Random.nextInt(brands.size)]

                Product(
                    name = "Product_${seq.toString().padStart(6, '0')}",
                    description = "상품 $seq 상세 설명",
                    price = Money.of(Random.nextLong(1000, 100_000)),
                    stock = Stock.of(Random.nextInt(10, 1000)),
                    brand = brand
                ).apply {
                    // likesCount 설정 (리플렉션 사용)
                    setLikesCount(this, generateSkewedLikes())
                }
            }
            productJpaRepository.saveAll(products)

            if ((batch + 1) % 10 == 0) {
                println("📦 상품 ${(batch + 1) * batchSize}개 생성 완료...")
            }
        }

        println("📦 상품 총 $totalProducts개 생성 완료")
    }

    // 좋아요 수: 편향 분포 (대부분 낮고, 일부만 높음)
    private fun generateSkewedLikes(): Int {
        return (Random.nextDouble() * Random.nextDouble() * 10000).toInt()
    }

    private fun setLikesCount(product: Product, count: Int) {
        val field = Product::class.java.getDeclaredField("likesCount")
        field.isAccessible = true
        field.setInt(product, count)
    }
}
```

### 장점/단점
- ✅ 앱 시작 시 자동 생성
- ✅ 이미 데이터 있으면 스킵
- ❌ 첫 시작 시 1~2분 소요

---

## 방법 3: 별도 실행 스크립트

필요할 때만 실행하는 방식입니다.

### 파일 생성 위치
```
apps/commerce-api/src/test/kotlin/com/loopers/support/DataGeneratorTest.kt
```

### 코드

```kotlin
package com.loopers.support

import com.loopers.domain.brand.Brand
import com.loopers.domain.product.Product
import com.loopers.domain.product.Stock
import com.loopers.domain.shared.Money
import com.loopers.infrastructure.brand.BrandJpaRepository
import com.loopers.infrastructure.product.ProductJpaRepository
import org.junit.jupiter.api.Disabled
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import kotlin.random.Random

@SpringBootTest
@ActiveProfiles("local")
@Disabled("데이터 생성 시에만 수동 실행")
class DataGeneratorTest {

    @Autowired
    lateinit var brandJpaRepository: BrandJpaRepository

    @Autowired
    lateinit var productJpaRepository: ProductJpaRepository

    @Test
    fun `상품 10만개 데이터 생성`() {
        // 브랜드 100개 생성
        val brands = (1..100).map { i ->
            Brand(
                name = "Brand_${i.toString().padStart(3, '0')}",
                description = "브랜드 $i 설명"
            )
        }
        brandJpaRepository.saveAll(brands)
        println("브랜드 ${brands.size}개 생성 완료")

        // 상품 10만개 생성
        val batchSize = 1000
        repeat(100) { batch ->
            val products = (1..batchSize).map { i ->
                val seq = batch * batchSize + i
                Product(
                    name = "Product_${seq.toString().padStart(6, '0')}",
                    description = "상품 $seq 상세 설명",
                    price = Money.of(Random.nextLong(1000, 100_000)),
                    stock = Stock.of(Random.nextInt(10, 1000)),
                    brand = brands.random()
                ).apply {
                    val field = Product::class.java.getDeclaredField("likesCount")
                    field.isAccessible = true
                    field.setInt(this, (Random.nextDouble() * Random.nextDouble() * 10000).toInt())
                }
            }
            productJpaRepository.saveAll(products)
            println("상품 ${(batch + 1) * batchSize}개 생성 완료...")
        }

        println("=== 완료 ===")
    }
}
```

### 실행 방법
```bash
# @Disabled 주석 제거 후 실행
./gradlew :apps:commerce-api:test --tests "com.loopers.support.DataGeneratorTest"
```

### 장점/단점
- ✅ 필요할 때만 실행
- ✅ 테스트 환경에서 분리
- ❌ 수동 실행 필요

---

## 데이터 분포 확인 쿼리

생성 후 데이터가 잘 분포되었는지 확인합니다.

```sql
-- 전체 개수 확인
SELECT COUNT(*) as total_products FROM products;
SELECT COUNT(*) as total_brands FROM brands;

-- 브랜드별 상품 수
SELECT
    b.name as brand_name,
    COUNT(p.id) as product_count
FROM brands b
LEFT JOIN products p ON b.id = p.brand_id
GROUP BY b.id, b.name
ORDER BY product_count DESC
LIMIT 10;

-- 좋아요 분포 확인
SELECT
    CASE
        WHEN likes_count = 0 THEN '0'
        WHEN likes_count < 100 THEN '1-99'
        WHEN likes_count < 1000 THEN '100-999'
        WHEN likes_count < 5000 THEN '1000-4999'
        ELSE '5000+'
    END as likes_range,
    COUNT(*) as count
FROM products
GROUP BY likes_range
ORDER BY MIN(likes_count);

-- 가격 분포 확인
SELECT
    CASE
        WHEN price < 10000 THEN '~1만원'
        WHEN price < 30000 THEN '1~3만원'
        WHEN price < 50000 THEN '3~5만원'
        WHEN price < 70000 THEN '5~7만원'
        ELSE '7만원~'
    END as price_range,
    COUNT(*) as count
FROM products
GROUP BY price_range;
```

---

## 방법 비교

| 방법 | 속도 | 자동화 | 재사용성 | 추천 상황 |
|------|------|--------|----------|-----------|
| **SQL 스크립트** | ⭐⭐⭐ | ❌ | ⭐ | 빠르게 한 번만 생성 |
| **DataInitializer** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | 개발 환경 자동화 |
| **테스트 스크립트** | ⭐⭐ | ⭐⭐ | ⭐⭐ | 필요할 때 수동 실행 |

---

## 주의사항

1. **ddl-auto 설정 확인**
   - `local` 프로필: `ddl-auto: create` → 앱 재시작 시 테이블 재생성
   - 데이터 유지하려면 `ddl-auto: update` 또는 `none`으로 변경

2. **실행 시간**
   - SQL: 수 초
   - Kotlin: 1~2분

3. **메모리**
   - 배치 사이즈 1000개씩 처리하여 OOM 방지
