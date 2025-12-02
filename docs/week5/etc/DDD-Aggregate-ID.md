
# DDD Aggregate 경계: 왜 객체 참조 대신 ID 참조를 사용해야 할까? 🎯

> **TL;DR**: Aggregate 간 객체 참조를 ID 참조로 변경하여 **N+1 문제 원천 차단**, **트랜잭션 경계 명확화**, **도메인 독립성 확보**를 달성했습니다.

---

## 목차

1. [문제 상황](#1-문제-상황)
2. [DDD Aggregate란?](#2-ddd-aggregate란)
3. [잘못된 설계의 문제점](#3-잘못된-설계의-문제점)
4. [해결 방법: ID 참조 패턴](#4-해결-방법-id-참조-패턴)
5. [리팩토링 과정](#5-리팩토링-과정)
6. [개선 효과](#6-개선-효과)
7. [배운 점](#7-배운-점)

---

## 1. 문제 상황

### 🔴 발견한 문제

DTO Projection으로 Brand 조회 쿼리를 제거하는 작업을 하다가, 근본적인 설계 문제를 발견했습니다.

```kotlin
// ❌ Product가 Brand 엔티티를 직접 참조
@Entity
class Product(
    // ...
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "brand_id")
    var brand: Brand  // 다른 Aggregate를 직접 참조!
)

// ❌ OrderItem이 Product 엔티티를 직접 참조
@Entity
class OrderItem(
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "product_id")
    var product: Product  // 다른 Aggregate를 직접 참조!
)
```

### 🤔 무엇이 문제인가?

**1. N+1 문제의 근본 원인**
```kotlin
// Product를 조회하면 언제든 brand에 접근 가능
val product = productRepository.findById(1L)
println(product.brand.name)  // 🚨 LAZY 로딩 발생!
```

**2. 트랜잭션 경계 모호**
```kotlin
@Transactional
fun updateProduct(product: Product) {
    product.name = "변경"
    product.brand.name = "브랜드도 변경?"  // 🚨 다른 Aggregate 침범!
}
```

**3. Aggregate 간 결합도 증가**
```
Order → OrderItem → Product → Brand
(4개의 Aggregate가 객체 참조로 연결)
```

---

## 2. DDD Aggregate란?

### 📚 Aggregate 정의

**Aggregate**: 트랜잭션 일관성을 보장하는 경계

```
┌─────────────────────────────────────┐
│         Order Aggregate             │
│  ┌─────────────────────────────┐  │
│  │  Order (Aggregate Root)      │  │
│  │  - orderId                    │  │
│  │  - memberId (ID 참조) ✅     │  │
│  │  - totalAmount                │  │
│  │  └─┬─────────────────────────┘  │
│    │                                │
│    ▼                                │
│  ┌─────────────────────────────┐  │
│  │  OrderItem (Entity)          │  │
│  │  - productId (ID 참조) ✅    │  │
│  │  - productName (스냅샷) ✅   │  │
│  │  - price (스냅샷) ✅         │  │
│  │  - quantity                   │  │
│  └─────────────────────────────┘  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│       Product Aggregate             │
│  ┌─────────────────────────────┐  │
│  │  Product (Aggregate Root)    │  │
│  │  - productId                  │  │
│  │  - brandId (ID 참조) ✅      │  │
│  │  - name                       │  │
│  │  - price                      │  │
│  │  - stock                      │  │
│  └─────────────────────────────┘  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│        Brand Aggregate              │
│  ┌─────────────────────────────┐  │
│  │  Brand (Aggregate Root)      │  │
│  │  - brandId                    │  │
│  │  - name                       │  │
│  │  - description                │  │
│  └─────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 🎯 Aggregate 설계 원칙

1. **하나의 트랜잭션에서 하나의 Aggregate만 수정**
2. **Aggregate 간 참조는 ID로만**
3. **Aggregate Root를 통해서만 접근**
4. **불변식은 Aggregate 내부에서만 보장**
5. **결과적 일관성 수용**

---

## 3. 잘못된 설계의 문제점

### ❌ AS-IS: 객체 참조 방식

#### 문제 1: N+1 쿼리 위험

```kotlin
// Product 엔티티를 조회
val products = productRepository.findAll()

// ProductInfo로 변환 시 Brand 접근
products.forEach { product ->
    println(product.brand.name)  // 🚨 N+1 쿼리 발생!
}

// 실행된 쿼리:
// 1. SELECT * FROM products
// 2. SELECT * FROM brands WHERE id = 1  // Product 개수만큼 반복!
// 3. SELECT * FROM brands WHERE id = 2
// 4. SELECT * FROM brands WHERE id = 3
// ...
```

#### 문제 2: 데이터 일관성 문제

```kotlin
// 주문 생성 시 Product를 참조로 저장
val order = Order(
    items = listOf(
        OrderItem(product = product, quantity = 2)  // Product 참조
    )
)

// 나중에 Product 가격이 변경되면?
product.price = Money(2000)

// 🚨 과거 주문의 가격도 변경됨!
order.items[0].product.price  // 2000원 (원래는 1500원이었는데!)
```

#### 문제 3: 트랜잭션 경계 위반

```kotlin
@Transactional
fun updateProduct(productId: Long, newPrice: Money) {
    val product = productRepository.findById(productId)
    product.price = newPrice
    
    // 🚨 의도하지 않게 다른 Aggregate 수정 가능
    product.brand.description = "변경"  // Brand Aggregate 침범!
}
```

#### 문제 4: Cascade 부작용

```kotlin
@Entity
class Brand(
    @OneToMany(mappedBy = "brand", cascade = [CascadeType.ALL])
    protected val products: MutableList<Product> = mutableListOf()
)

// 🚨 Brand 삭제 시 모든 Product도 삭제됨!
brandRepository.delete(brand)  // Product 100개가 함께 삭제!
```

---

## 4. 해결 방법: ID 참조 패턴

### ✅ TO-BE: ID 참조 방식

#### 핵심 아이디어

```
AS-IS: Product → Brand (객체 참조)
       ❌ LAZY 로딩 가능
       ❌ 트랜잭션 경계 모호
       ❌ Aggregate 결합도 높음

TO-BE: Product → brandId: Long (ID만 보관)
       ✅ LAZY 로딩 불가능 (접근할 객체가 없음)
       ✅ 트랜잭션 경계 명확
       ✅ Aggregate 독립적
```

#### 개선 1: Product → Brand

```kotlin
// ✅ TO-BE: Brand ID만 보관
@Entity
@Table(name = "products")
class Product(
    name: String,
    description: String?,
    price: Money,
    stock: Stock,
    brandId: Long,  // ✅ ID만 저장
) : BaseEntity() {
    
    @Column(name = "brand_id", nullable = false)
    var brandId: Long = brandId
        protected set
    
    // brand 객체 참조 제거! ✅
}
```

**필요할 때만 Brand 조회:**
```kotlin
// Brand 정보가 필요한 경우에만 명시적으로 조회
val product = productRepository.findById(productId)
val brand = brandRepository.findById(product.brandId)

// 또는 DTO Projection으로 JOIN
@Query("""
    SELECT p.*, b.name as brandName
    FROM products p
    INNER JOIN brands b ON b.id = p.brand_id
    WHERE p.id = :productId
""")
fun findProductWithBrand(productId: Long): ProductWithBrandDto
```

#### 개선 2: OrderItem → Product (스냅샷 패턴)

```kotlin
// ✅ TO-BE: Product ID + 주문 시점 스냅샷
@Entity
@Table(name = "order_items")
class OrderItem(
    productId: Long,      // ✅ Product ID만 보관
    productName: String,  // ✅ 주문 시점 스냅샷
    price: Money,         // ✅ 주문 시점 가격
    quantity: Quantity,
) : BaseEntity() {
    
    @Column(name = "product_id", nullable = false)
    var productId: Long = productId
        protected set
    
    @Column(name = "product_name", nullable = false)
    var productName: String = productName
        protected set
    
    @Embedded
    var price: Money = price
        protected set
    
    // product 객체 참조 제거! ✅
    
    companion object {
        fun of(productId: Long, productName: String, price: Money, quantity: Quantity): OrderItem {
            return OrderItem(productId, productName, price, quantity)
        }
    }
}
```

**스냅샷 패턴의 장점:**
```kotlin
// 주문 생성 시 Product 정보를 스냅샷으로 저장
val order = Order.create(
    orderItems = listOf(
        OrderItemCommand(productId = 1L, quantity = 2)
    ),
    productMap = mapOf(
        1L to Product(name = "상품1", price = Money(1500), ...)
    )
)

// Order.create() 내부:
OrderItem.of(
    productId = product.id,
    productName = product.name,  // 주문 시점 이름 스냅샷
    price = product.price,        // 주문 시점 가격 스냅샷
    quantity = quantity
)

// 나중에 Product 가격이 변경되어도 주문 데이터는 유지됨 ✅
product.price = Money(2000)
orderItem.price  // 여전히 1500원 (주문 당시 가격)
```

#### 개선 3: Order → Member

```kotlin
// ✅ 이미 올바르게 구현됨
@Entity
class Order(
    memberId: String,  // ✅ Member ID만 보관
    // ...
) : BaseEntity() {
    
    @Column(name = "member_id", nullable = false)
    var memberId: String = memberId
        protected set
    
    // member 객체 참조 없음 ✅
}
```

---

## 5. 리팩토링 과정

### 📝 Step 1: Product 엔티티 수정

**변경 전:**
```kotlin
@Entity
class Product(
    // ...
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "brand_id")
    var brand: Brand
)
```

**변경 후:**
```kotlin
@Entity
class Product(
    // ...
    @Column(name = "brand_id", nullable = false)
    var brandId: Long
)
```

### 📝 Step 2: Brand 엔티티 수정

**변경 전:**
```kotlin
@Entity
class Brand(
    @OneToMany(mappedBy = "brand", cascade = [CascadeType.ALL])
    protected val products: MutableList<Product> = mutableListOf()
) {
    fun addProduct(product: Product) {
        products.add(product)
    }
}
```

**변경 후:**
```kotlin
@Entity
class Brand(
    name: String,
    description: String?,
) : BaseEntity() {
    // products 컬렉션 제거 ✅
    // 필요시 ProductRepository.findByBrandId()로 조회
}
```

### 📝 Step 3: OrderItem 엔티티 수정

**변경 전:**
```kotlin
@Entity
class OrderItem(
    product: Product,
    quantity: Quantity,
) {
    @ManyToOne(fetch = FetchType.LAZY)
    var product: Product = product
    
    var price: Money = product.price  // Product에서 가격 가져옴
}
```

**변경 후:**
```kotlin
@Entity
class OrderItem(
    productId: Long,
    productName: String,
    price: Money,         // 주문 시점 가격을 명시적으로 전달
    quantity: Quantity,
) {
    @Column(name = "product_id")
    var productId: Long = productId
    
    @Column(name = "product_name")
    var productName: String = productName
    
    @Embedded
    var price: Money = price  // 스냅샷
}
```

### 📝 Step 4: Order.create() 수정

**변경 전:**
```kotlin
companion object {
    fun create(/* ... */): Order {
        val items = orderItems.map { itemCommand ->
            val product = productMap[itemCommand.productId]!!
            product.validateStock(quantity)
            
            OrderItem.of(product, quantity)  // Product 전체 전달
        }
        return Order(memberId, items, discountAmount)
    }
}
```

**변경 후:**
```kotlin
companion object {
    fun create(/* ... */): Order {
        val items = orderItems.map { itemCommand ->
            val product = productMap[itemCommand.productId]!!
            product.validateStock(quantity)
            
            // 필요한 데이터만 추출하여 전달 ✅
            OrderItem.of(
                productId = product.id!!,
                productName = product.name,
                price = product.price,
                quantity = quantity
            )
        }
        return Order(memberId, items, discountAmount)
    }
}
```

### 📝 Step 5: OrderService 수정

**변경 전:**
```kotlin
val order = Order.create(/* ... */)
order.decreaseProductStocks()  // OrderItem → Product 참조
```

**변경 후:**
```kotlin
val order = Order.create(/* ... */)

// Aggregate 경계를 넘어 Product 직접 조작
order.items.forEach { item ->
    val product = productMap[item.productId]!!
    product.decreaseStock(item.quantity)
}
```

---

## 6. 개선 효과

### ✅ 1. N+1 문제 원천 차단

**AS-IS:**
```kotlin
val products = productRepository.findAll()
products.forEach { product ->
    println(product.brand.name)  // 🚨 N+1 쿼리 발생
}
```

**TO-BE:**
```kotlin
val products = productRepository.findAll()
products.forEach { product ->
    println(product.brandId)  // ✅ 추가 쿼리 없음
    // brand.name이 필요하면 명시적으로 조회
}
```

### ✅ 2. 데이터 일관성 보장

**AS-IS:**
```kotlin
// 주문 시점 가격: 1500원
val orderItem = OrderItem(product, quantity)

// Product 가격 변경
product.price = Money(2000)

// 🚨 주문 데이터도 변경됨
orderItem.product.price  // 2000원
```

**TO-BE:**
```kotlin
// 주문 시점 가격: 1500원 (스냅샷 저장)
val orderItem = OrderItem(productId, productName, Money(1500), quantity)

// Product 가격 변경
product.price = Money(2000)

// ✅ 주문 데이터는 유지됨
orderItem.price  // 여전히 1500원
```

### ✅ 3. 트랜잭션 경계 명확화

**AS-IS:**
```kotlin
@Transactional
fun updateProduct(product: Product) {
    product.name = "변경"
    product.brand.name = "브랜드도 변경"  // 🚨 다른 Aggregate 침범
}
```

**TO-BE:**
```kotlin
@Transactional
fun updateProduct(product: Product) {
    product.name = "변경"
    product.brandId = 2L  // ✅ ID만 변경, Brand는 독립적
}
```

### ✅ 4. Aggregate 독립성 확보

**AS-IS:**
```
Order → OrderItem → Product → Brand
(4개 Aggregate가 참조로 연결, 강한 결합)
```

**TO-BE:**
```
Order → OrderItem (productId만)
Product (brandId만)
Brand
(각 Aggregate 독립적, 약한 결합)
```

### 📊 성능 개선 효과

| 항목 | AS-IS | TO-BE | 개선 |
|------|-------|-------|------|
| **상품 목록 조회 쿼리** | 3개 (Product + Brand + COUNT) | 2개 (Projection + COUNT) | **33% 감소** |
| **LAZY 로딩 위험** | 항상 존재 | 원천 차단 | **100% 제거** |
| **트랜잭션 범위** | 모호 (여러 Aggregate) | 명확 (하나의 Aggregate) | **명확화** |
| **도메인 결합도** | 높음 (객체 참조) | 낮음 (ID 참조) | **독립성 ↑** |

---

## 7. 배운 점

### 💡 핵심 인사이트

#### 1️⃣ Aggregate 경계는 트랜잭션 경계

```kotlin
// ❌ 나쁜 예: 하나의 트랜잭션에서 여러 Aggregate 수정
@Transactional
fun placeOrder(command: CreateOrderCommand) {
    val order = Order.create(...)
    order.decreaseProductStocks()  // Product Aggregate 수정
    order.processPayment(member)    // Member Aggregate 수정
    
    // 🚨 3개의 Aggregate를 한 트랜잭션에서 수정!
}

// ✅ 좋은 예: 각 Aggregate는 독립적으로 수정
@Transactional
fun placeOrder(command: CreateOrderCommand) {
    val order = Order.create(...)
    
    // Product는 별도로 처리
    decreaseProductStocks(order.items)
    
    // Member는 별도로 처리  
    processPayment(member, order.finalAmount)
}
```

#### 2️⃣ ID 참조는 LAZY 로딩을 원천 차단

```kotlin
// ❌ 객체 참조: LAZY 로딩 가능
class Product(
    @ManyToOne(fetch = FetchType.LAZY)
    var brand: Brand  // 접근 가능 → LAZY 로딩 위험
)

// 🚨 실수로 접근하면 쿼리 발생
product.brand.name

// ✅ ID 참조: LAZY 로딩 불가능
class Product(
    @Column(name = "brand_id")
    var brandId: Long  // ID만 있음 → brand.name 접근 불가능
)

// ✅ 컴파일 에러 발생 (런타임 에러가 아님!)
product.brand.name  // 컴파일 에러: Unresolved reference: brand
```

#### 3️⃣ 스냅샷 패턴으로 데이터 일관성 보장

```kotlin
// ❌ 객체 참조: 원본 데이터 변경 시 영향받음
class OrderItem(
    @ManyToOne
    var product: Product  // Product 가격 변경되면 주문도 영향받음
)

// ✅ 스냅샷: 주문 시점 데이터 보관
class OrderItem(
    var productId: Long,
    var productName: String,  // 주문 시점 이름
    var price: Money,         // 주문 시점 가격
)
```

#### 4️⃣ 필요한 데이터만 명시적으로 조회

```kotlin
// ❌ 불필요한 JOIN
@Query("SELECT p FROM Product p LEFT JOIN p.brand")
fun findAll(): List<Product>

// ✅ 필요할 때만 JOIN
@Query("""
    SELECT p.*, b.name as brandName
    FROM products p
    INNER JOIN brands b ON b.id = p.brand_id
    WHERE p.id = :productId
""")
fun findProductWithBrand(productId: Long): ProductWithBrandDto
```

#### 5️⃣ Cascade는 신중하게

```kotlin
// ❌ CascadeType.ALL은 위험
@OneToMany(cascade = [CascadeType.ALL])
val products: List<Product>

// Brand 삭제 시 모든 Product도 삭제됨! 🚨

// ✅ Cascade 제거, 명시적 처리
@OneToMany
val products: List<Product>  // Cascade 없음

// 필요시 명시적으로 처리
fun deleteBrand(brandId: Long) {
    val products = productRepository.findByBrandId(brandId)
    productRepository.deleteAll(products)
    brandRepository.deleteById(brandId)
}
```

### 🎓 DDD 설계 원칙 정리

1. **Aggregate는 트랜잭션 일관성의 경계**
   - 하나의 트랜잭션에서 하나의 Aggregate만 수정
   
2. **Aggregate 간 참조는 ID로만**
   - Product.brand (X) → Product.brandId (O)
   - OrderItem.product (X) → OrderItem.productId (O)

3. **Aggregate Root를 통해서만 접근**
   - OrderItem은 Order를 통해서만 접근
   - 외부에서 OrderItem 직접 수정 불가

4. **불변식은 Aggregate 내부에서만 보장**
   - Product 재고 검증은 Product 내부에서
   - Order 금액 계산은 Order 내부에서

5. **결과적 일관성 수용**
   - Brand 삭제 시 Product는 이벤트로 비동기 처리
   - 즉시 일관성이 필요하지 않은 경우 이벤트 활용

---

## 8. 추가 개선 아이디어

### 🚀 더 나아가기

#### 1. Domain Event로 Aggregate 간 통신

```kotlin
// Brand 삭제 시 Product에 알림
@Entity
class Brand {
    fun delete() {
        // 도메인 이벤트 발행
        Events.raise(BrandDeletedEvent(id))
        this.deletedAt = LocalDateTime.now()
    }
}

// 이벤트 핸들러
@EventListener
class ProductEventHandler {
    fun handle(event: BrandDeletedEvent) {
        // Product들을 비동기로 처리
        productService.markProductsAsUnavailable(event.brandId)
    }
}
```

#### 2. Repository에서 필요한 Aggregate만 조회

```kotlin
// ❌ 불필요한 Aggregate 로드
val products = productRepository.findAll()  // Brand도 함께 로드 위험

// ✅ DTO Projection으로 필요한 데이터만
val productSummaries = productRepository.findAllSummaries()
```

#### 3. CQRS 패턴 적용

```
Command (쓰기): Aggregate 단위로 처리
Query (읽기): DTO Projection으로 최적화

- 쓰기: Product, Brand 각각 독립적으로 수정
- 읽기: ProductWithBrandDto로 JOIN 조회
```

---

## 9. 결론

### ✅ 달성한 것

| 항목 | 내용 |
|------|------|
| **문제 인식** | Aggregate 간 객체 참조의 문제점 파악 |
| **원인 분석** | N+1 쿼리, 트랜잭션 경계 모호, 높은 결합도 |
| **해결** | ID 참조 패턴 + 스냅샷 패턴 적용 |
| **성능 개선** | LAZY 로딩 원천 차단, 쿼리 수 33% 감소 |
| **설계 개선** | Aggregate 독립성 확보, 트랜잭션 경계 명확화 |

### 🎯 핵심 메시지

```
"Aggregate 간 참조는 ID로만 하라.
객체 참조의 편리함보다 도메인 독립성이 중요하다!"
```

### 📚 참고 자료

- [Domain-Driven Design (Eric Evans)](https://www.amazon.com/Domain-Driven-Design-Tackling-Complexity-Software/dp/0321125215)
- [Implementing Domain-Driven Design (Vaughn Vernon)](https://www.amazon.com/Implementing-Domain-Driven-Design-Vaughn-Vernon/dp/0321834577)
- [Microsoft - Designing Aggregates](https://docs.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/microservice-domain-model)

---

<div align="center">

**🎉 Aggregate 경계 리팩토링 완료! 🎉**

이제 각 도메인이 독립적으로 진화할 수 있습니다!

</div>

---

_작성일: 2025년 11월 26일_
_작성자: loopers-spring-kotlin-template_
_태그: #DDD #Aggregate #리팩토링 #성능최적화 #도메인주도설계_




