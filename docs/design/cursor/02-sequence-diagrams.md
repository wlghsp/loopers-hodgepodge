# 02. 시퀀스 다이어그램

## 개요

이 문서는 감성 이커머스의 주요 기능에 대한 시퀀스 다이어그램을 정리합니다.
객체 간 메시지 흐름을 통해 책임과 협력 구조를 시각화합니다.

**설계 범위:**
- 상품 조회 (목록, 상세)
- 브랜드 조회
- 좋아요 등록/취소 (멱등성)
- 주문 생성 및 결제

---

## 1. 상품 목록 조회 (브랜드 필터링 및 정렬)

### 시나리오
사용자가 브랜드 필터링과 정렬 옵션을 적용하여 상품 목록을 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant ProductController
    participant ProductFacade
    participant ProductService
    participant ProductRepository
    
    Client->>ProductController: GET /api/v1/products?brandId=1&sort=latest&page=0&size=20
    
    ProductController->>ProductFacade: getProducts(brandId, sort, pageable)
    
    ProductFacade->>ProductService: findProducts(brandId, sort, pageable)
    
    ProductService->>ProductRepository: findAll(brandId, sort, pageable)
    Note over ProductRepository: 브랜드 필터링 적용<br/>정렬 옵션 적용 (latest/price_asc/likes_desc)<br/>페이지네이션 적용
    
    ProductRepository-->>ProductService: Page<Product>
    
    Note over ProductService: 각 상품의 좋아요 수는<br/>Product 엔티티에 비정규화되어 있음
    
    ProductService-->>ProductFacade: Page<Product>
    
    ProductFacade-->>ProductController: Page<ProductInfo>
    Note over ProductFacade: Domain → DTO 변환
    
    ProductController-->>Client: 200 OK<br/>Page<ProductResponse>
```

**핵심 포인트:**
- 브랜드 필터링은 Query Parameter로 선택적으로 적용
- 정렬 기준: `latest` (필수), `price_asc`, `likes_desc` (선택)
- 좋아요 수는 Product 테이블에 비정규화하여 COUNT 쿼리 최소화
- Facade 계층에서 Domain 객체를 DTO로 변환

---

## 2. 상품 상세 조회

### 시나리오
사용자가 특정 상품의 상세 정보를 조회합니다. 브랜드 정보와 좋아요 수가 포함됩니다.

```mermaid
sequenceDiagram
    participant Client
    participant ProductController
    participant ProductFacade
    participant ProductService
    participant ProductRepository
    participant BrandService
    participant BrandRepository
    
    Client->>ProductController: GET /api/v1/products/{productId}
    
    ProductController->>ProductFacade: getProductDetail(productId)
    
    ProductFacade->>ProductService: getProduct(productId)
    
    ProductService->>ProductRepository: findById(productId)
    
    alt 상품이 존재하지 않음
        ProductRepository-->>ProductService: Optional.empty()
        ProductService-->>ProductFacade: ProductNotFoundException
        ProductFacade-->>ProductController: Exception
        ProductController-->>Client: 404 Not Found
    else 상품이 존재함
        ProductRepository-->>ProductService: Product
        ProductService-->>ProductFacade: Product
        
        Note over ProductFacade: 브랜드 정보 조회
        ProductFacade->>BrandService: getBrand(brandId)
        BrandService->>BrandRepository: findById(brandId)
        BrandRepository-->>BrandService: Brand
        BrandService-->>ProductFacade: Brand
        
        Note over ProductFacade: Product + Brand 정보를<br/>ProductDetailInfo로 변환
        
        ProductFacade-->>ProductController: ProductDetailInfo
        ProductController-->>Client: 200 OK<br/>ProductDetailResponse
    end
```

**핵심 포인트:**
- 상품이 없으면 404 Not Found 반환
- 브랜드 정보는 별도 Service를 통해 조회
- Facade에서 Product와 Brand를 조합하여 상세 정보 생성

---

## 3. 브랜드 조회

### 시나리오
사용자가 특정 브랜드의 정보를 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant BrandController
    participant BrandFacade
    participant BrandService
    participant BrandRepository
    
    Client->>BrandController: GET /api/v1/brands/{brandId}
    
    BrandController->>BrandFacade: getBrand(brandId)
    
    BrandFacade->>BrandService: getBrand(brandId)
    
    BrandService->>BrandRepository: findById(brandId)
    
    alt 브랜드가 존재하지 않음
        BrandRepository-->>BrandService: Optional.empty()
        BrandService-->>BrandFacade: BrandNotFoundException
        BrandFacade-->>BrandController: Exception
        BrandController-->>Client: 404 Not Found
    else 브랜드가 존재함
        BrandRepository-->>BrandService: Brand
        BrandService-->>BrandFacade: Brand
        BrandFacade-->>BrandController: BrandInfo
        BrandController-->>Client: 200 OK<br/>BrandResponse
    end
```

**핵심 포인트:**
- 단순 조회 흐름
- 브랜드가 없으면 404 반환

---

## 4. 상품 좋아요 등록 (멱등성 보장)

### 시나리오
사용자가 상품에 좋아요를 등록합니다. 이미 좋아요가 있으면 추가 등록하지 않습니다 (멱등성).

```mermaid
sequenceDiagram
    participant Client
    participant LikeController
    participant LikeFacade
    participant LikeService
    participant ProductService
    participant LikeRepository
    participant Product
    
    Client->>LikeController: POST /api/v1/like/products/{productId}
    Note over Client,LikeController: Header: X-USER-ID
    
    LikeController->>LikeFacade: registerLike(userId, productId)
    
    Note over LikeFacade: 1. 상품 존재 확인
    LikeFacade->>ProductService: getProduct(productId)
    ProductService-->>LikeFacade: Product
    
    Note over LikeFacade: 2. 좋아요 등록 시도
    LikeFacade->>LikeService: registerLike(userId, productId)
    
    LikeService->>LikeRepository: existsByUserIdAndProductId(userId, productId)
    
    alt 좋아요가 이미 존재하는 경우 (멱등성)
        LikeRepository-->>LikeService: true
        Note over LikeService: 추가 등록하지 않음<br/>멱등성 보장
        LikeService-->>LikeFacade: Like (기존)
        
    else 좋아요가 존재하지 않는 경우
        LikeRepository-->>LikeService: false
        
        Note over LikeService: 좋아요 생성 및 저장
        LikeService->>LikeRepository: save(Like)
        LikeRepository-->>LikeService: Like (새로 생성)
        
        Note over LikeService: 상품의 좋아요 수 증가
        LikeService->>Product: increaseLikesCount()
        Product-->>LikeService: updated
    end
    
    LikeService-->>LikeFacade: Like
    
    Note over LikeFacade: 현재 좋아요 수 조회
    LikeFacade->>ProductService: getProduct(productId)
    ProductService-->>LikeFacade: Product (with likesCount)
    
    LikeFacade-->>LikeController: LikeInfo
    LikeController-->>Client: 200 OK<br/>{success: true, likesCount: 43}
```

**핵심 포인트:**
- **멱등성**: 이미 좋아요가 있으면 추가 등록하지 않음
- DB 제약조건: UNIQUE INDEX (user_id, product_id)로 중복 방지
- 좋아요 수는 Product 엔티티에서 관리
- 동일한 요청을 여러 번 보내도 동일한 결과

---

## 5. 상품 좋아요 취소 (멱등성 보장)

### 시나리오
사용자가 상품의 좋아요를 취소합니다. 좋아요가 없어도 성공 응답을 반환합니다 (멱등성).

```mermaid
sequenceDiagram
    participant Client
    participant LikeController
    participant LikeFacade
    participant LikeService
    participant ProductService
    participant LikeRepository
    participant Product
    
    Client->>LikeController: DELETE /api/v1/like/products/{productId}
    Note over Client,LikeController: Header: X-USER-ID
    
    LikeController->>LikeFacade: cancelLike(userId, productId)
    
    Note over LikeFacade: 1. 좋아요 취소 시도
    LikeFacade->>LikeService: cancelLike(userId, productId)
    
    LikeService->>LikeRepository: findByUserIdAndProductId(userId, productId)
    
    alt 좋아요가 존재하는 경우
        LikeRepository-->>LikeService: Optional<Like>
        
        Note over LikeService: 좋아요 삭제
        LikeService->>LikeRepository: delete(Like)
        
        Note over LikeService: 상품의 좋아요 수 감소
        LikeService->>Product: decreaseLikesCount()
        Product-->>LikeService: updated
        
    else 좋아요가 존재하지 않는 경우 (멱등성)
        LikeRepository-->>LikeService: Optional.empty()
        Note over LikeService: 이미 취소됨<br/>멱등성 보장
    end
    
    LikeService-->>LikeFacade: void
    
    Note over LikeFacade: 현재 좋아요 수 조회
    LikeFacade->>ProductService: getProduct(productId)
    ProductService-->>LikeFacade: Product (with likesCount)
    
    LikeFacade-->>LikeController: LikeInfo
    LikeController-->>Client: 200 OK<br/>{success: true, likesCount: 42}
```

**핵심 포인트:**
- **멱등성**: 좋아요가 없어도 성공 응답
- 중복 취소 요청에도 동일한 결과
- 좋아요 수 감소는 실제 삭제된 경우만 수행

---

## 6. 내가 좋아요한 상품 목록 조회

### 시나리오
사용자가 자신이 좋아요한 상품 목록을 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant LikeController
    participant LikeFacade
    participant LikeService
    participant LikeRepository
    
    Client->>LikeController: GET /api/v1/like/products?page=0&size=20
    Note over Client,LikeController: Header: X-USER-ID
    
    LikeController->>LikeFacade: getMyLikes(userId, pageable)
    
    LikeFacade->>LikeService: findLikesByUserId(userId, pageable)
    
    LikeService->>LikeRepository: findByUserId(userId, pageable)
    Note over LikeRepository: Product Join<br/>페이지네이션 적용
    
    LikeRepository-->>LikeService: Page<Like>
    
    LikeService-->>LikeFacade: Page<Like>
    
    Note over LikeFacade: Like → LikeProductInfo 변환<br/>(상품 정보 + 좋아요 일시)
    
    LikeFacade-->>LikeController: Page<LikeProductInfo>
    
    LikeController-->>Client: 200 OK<br/>Page<LikeProductResponse>
```

**핵심 포인트:**
- 페이지네이션 적용
- Product와 Join하여 상품 정보도 함께 반환
- 좋아요 누른 일시 포함

---

## 7. 주문 생성 및 결제 (핵심 시퀀스)

### 시나리오
사용자가 여러 상품을 주문하고, 재고 차감 → 포인트 차감 → 외부 시스템 연동을 거쳐 주문이 완료되는 전체 흐름입니다.

```mermaid
sequenceDiagram
    participant Client
    participant OrderController
    participant OrderFacade
    participant OrderService
    participant ProductService
    participant PointService
    participant ExternalOrderClient
    participant OrderRepository
    participant ProductRepository
    participant PointRepository
    
    Client->>OrderController: POST /api/v1/orders
    Note over Client,OrderController: Header: X-USER-ID<br/>Body: {items: [{productId, quantity}]}
    
    OrderController->>OrderFacade: createOrder(userId, orderCommand)
    
    Note over OrderFacade: 1. 상품 정보 조회 및 검증
    loop 각 주문 상품에 대해
        OrderFacade->>ProductService: getProduct(productId)
        ProductService->>ProductRepository: findById(productId)
        
        alt 상품이 존재하지 않음
            ProductRepository-->>ProductService: Optional.empty()
            ProductService-->>OrderFacade: ProductNotFoundException
            OrderFacade-->>OrderController: Exception
            OrderController-->>Client: 404 Not Found
        end
        
        ProductRepository-->>ProductService: Product
        ProductService-->>OrderFacade: Product
        
        Note over OrderFacade: 재고 확인
        alt 재고 부족
            OrderFacade-->>OrderController: InsufficientStockException
            OrderController-->>Client: 400 Bad Request<br/>"재고가 부족합니다"
        end
    end
    
    Note over OrderFacade: 2. 총 금액 계산
    Note over OrderFacade: totalAmount = Σ(price × quantity)
    
    Note over OrderFacade: 3. 포인트 잔액 확인
    OrderFacade->>PointService: getPoint(userId)
    PointService->>PointRepository: findByUserId(userId)
    PointRepository-->>PointService: Point
    PointService-->>OrderFacade: Point
    
    alt 포인트 부족
        OrderFacade-->>OrderController: InsufficientPointException
        OrderController-->>Client: 400 Bad Request<br/>"포인트가 부족합니다"
    end
    
    Note over OrderFacade: 4. 트랜잭션 시작
    OrderFacade->>OrderService: createOrder(orderCommand)
    
    Note over OrderService: @Transactional
    
    loop 각 주문 상품에 대해
        Note over OrderService: 재고 차감 (비관적 락)
        OrderService->>ProductService: decreaseStock(productId, quantity)
        ProductService->>ProductRepository: findByIdWithLock(productId)
        Note over ProductRepository: SELECT ... FOR UPDATE
        ProductRepository-->>ProductService: Product (locked)
        
        ProductService->>Product: decreaseStock(quantity)
        Note over Product: stock.decrease(quantity)
        Product-->>ProductService: updated
        
        ProductService->>ProductRepository: save(Product)
    end
    
    Note over OrderService: 포인트 차감 (비관적 락)
    OrderService->>PointService: usePoint(userId, totalAmount)
    PointService->>PointRepository: findByUserIdWithLock(userId)
    Note over PointRepository: SELECT ... FOR UPDATE
    PointRepository-->>PointService: Point (locked)
    
    PointService->>Point: use(totalAmount)
    Note over Point: balance.decrease(amount)
    Point-->>PointService: updated
    
    PointService->>PointRepository: save(Point)
    
    Note over OrderService: 주문 정보 저장
    OrderService->>OrderRepository: save(Order)
    OrderRepository-->>OrderService: Order (PENDING)
    
    Note over OrderService: 5. 외부 시스템 연동
    OrderService->>ExternalOrderClient: sendOrder(orderInfo)
    
    alt 외부 시스템 실패
        ExternalOrderClient-->>OrderService: Exception
        Note over OrderService: 트랜잭션 롤백<br/>재고/포인트 복구
        OrderService-->>OrderFacade: ExternalSystemException
        OrderFacade-->>OrderController: Exception
        OrderController-->>Client: 500 Internal Server Error<br/>"주문 처리 실패"
        
    else 외부 시스템 성공
        ExternalOrderClient-->>OrderService: Success
        
        Note over OrderService: 주문 상태 변경
        OrderService->>Order: complete()
        Note over Order: status = COMPLETED
        
        Note over OrderService: 트랜잭션 커밋
        
        OrderService-->>OrderFacade: Order (COMPLETED)
        OrderFacade-->>OrderController: OrderInfo
        OrderController-->>Client: 200 OK<br/>{orderId, status: COMPLETED, totalAmount}
    end
```

**핵심 포인트:**
1. **상품 검증**: 모든 상품이 존재하고 재고가 충분한지 확인
2. **포인트 검증**: 잔액이 충분한지 확인
3. **트랜잭션**: 재고 차감 → 포인트 차감 → 주문 저장이 하나의 트랜잭션
4. **동시성 제어**: 재고/포인트 차감 시 비관적 락 (`SELECT FOR UPDATE`)
5. **외부 시스템**: 실패 시 전체 롤백
6. **주문 상태**: `PENDING` → `COMPLETED` or `FAILED`

---

## 8. 주문 목록 조회

### 시나리오
사용자가 자신의 주문 내역을 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant OrderController
    participant OrderFacade
    participant OrderService
    participant OrderRepository
    
    Client->>OrderController: GET /api/v1/orders?page=0&size=20
    Note over Client,OrderController: Header: X-USER-ID
    
    OrderController->>OrderFacade: getOrders(userId, pageable)
    
    OrderFacade->>OrderService: findOrdersByUserId(userId, pageable)
    
    OrderService->>OrderRepository: findByUserId(userId, pageable)
    Note over OrderRepository: 페이지네이션 적용<br/>최신 주문순 정렬
    
    OrderRepository-->>OrderService: Page<Order>
    
    OrderService-->>OrderFacade: Page<Order>
    
    Note over OrderFacade: Order → OrderSummaryInfo 변환<br/>(주문ID, 상태, 총액, 상품개수)
    
    OrderFacade-->>OrderController: Page<OrderSummaryInfo>
    
    OrderController-->>Client: 200 OK<br/>Page<OrderSummaryResponse>
```

**핵심 포인트:**
- 본인의 주문만 조회 (userId로 필터링)
- 페이지네이션 적용
- 요약 정보만 반환 (상세는 별도 API)

---

## 9. 주문 상세 조회

### 시나리오
사용자가 특정 주문의 상세 정보를 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant OrderController
    participant OrderFacade
    participant OrderService
    participant OrderRepository
    
    Client->>OrderController: GET /api/v1/orders/{orderId}
    Note over Client,OrderController: Header: X-USER-ID
    
    OrderController->>OrderFacade: getOrderDetail(userId, orderId)
    
    OrderFacade->>OrderService: getOrder(orderId)
    
    OrderService->>OrderRepository: findById(orderId)
    
    alt 주문이 존재하지 않음
        OrderRepository-->>OrderService: Optional.empty()
        OrderService-->>OrderFacade: OrderNotFoundException
        OrderFacade-->>OrderController: Exception
        OrderController-->>Client: 404 Not Found
        
    else 주문이 존재함
        OrderRepository-->>OrderService: Order
        OrderService-->>OrderFacade: Order
        
        Note over OrderFacade: 본인 주문 확인
        alt 본인의 주문이 아님
            OrderFacade-->>OrderController: ForbiddenException
            OrderController-->>Client: 403 Forbidden
        end
        
        Note over OrderFacade: Order → OrderDetailInfo 변환<br/>(주문 상품, 수량, 가격, 상태)
        
        OrderFacade-->>OrderController: OrderDetailInfo
        OrderController-->>Client: 200 OK<br/>OrderDetailResponse
    end
```

**핵심 포인트:**
- 본인의 주문만 조회 가능 (권한 검증)
- 주문 상품 상세 정보 포함
- 주문이 없거나 권한이 없으면 에러 반환

---

## 설계 원칙 정리

### 1. 계층별 책임 분리
- **Controller**: HTTP 요청/응답 처리, 헤더 파싱
- **Facade**: 여러 Service 조율, Domain → DTO 변환
- **Service**: 비즈니스 로직, 트랜잭션 관리
- **Domain**: 핵심 비즈니스 규칙 (재고 차감, 좋아요 카운트)
- **Repository**: 데이터 접근

### 2. 멱등성 보장
- 좋아요 등록: 이미 존재하면 추가 등록하지 않음
- 좋아요 취소: 존재하지 않아도 성공 응답
- DB 제약조건으로 중복 방지

### 3. 트랜잭션 관리
- 주문 생성은 하나의 트랜잭션
- 재고/포인트 차감 → 주문 저장 → 외부 시스템
- 실패 시 전체 롤백

### 4. 동시성 제어
- 재고 차감: 비관적 락 (`SELECT FOR UPDATE`)
- 포인트 차감: 비관적 락 (`SELECT FOR UPDATE`)
- 동시 주문 시 정합성 보장

### 5. 성능 최적화
- 좋아요 수 비정규화 (Product 테이블에 저장)
- 페이지네이션으로 대용량 데이터 처리
- 인덱스 활용 (브랜드 필터링, 정렬)

---

## 다음 단계

이 시퀀스 다이어그램을 기반으로:
1. **클래스 다이어그램**: 객체 구조와 책임 정의
2. **ERD**: 데이터베이스 테이블 설계
3. **구현**: 실제 코드 작성



