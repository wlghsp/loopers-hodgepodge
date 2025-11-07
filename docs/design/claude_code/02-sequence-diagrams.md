# 02. 시퀀스 다이어그램

## 1. 상품 좋아요 등록 (멱등 동작)

### 시나리오
사용자가 상품에 좋아요를 등록하는 흐름입니다.
멱등성을 보장하여 같은 요청이 여러 번 와도 동일한 결과를 반환합니다.

```mermaid
sequenceDiagram
    participant Client
    participant LikeV1Controller
    participant LikeFacade
    participant LikeService
    participant ProductService
    participant LikeRepository
    participant Product

    Client->>LikeV1Controller: POST /api/v1/like/products/{productId}
    Note over Client,LikeV1Controller: Header: X-USER-ID

    LikeV1Controller->>LikeV1Controller: X-USER-ID 헤더 검증

    alt X-USER-ID 헤더 누락
        LikeV1Controller-->>Client: ApiResponse(400, "X-USER-ID 헤더 정보 누락입니다.")
    else 정상 요청
        LikeV1Controller->>LikeFacade: toggleLike(command)

        LikeFacade->>ProductService: getProduct(productId)

        alt 상품이 존재하지 않음
            ProductService-->>LikeFacade: throw ProductNotFoundException
            LikeFacade-->>LikeV1Controller: Exception
            LikeV1Controller-->>Client: ApiResponse(404, "상품을 찾을 수 없습니다")
        else 상품 존재
            ProductService-->>LikeFacade: Product

            LikeFacade->>LikeService: toggleLike(memberId, productId)

            LikeService->>LikeRepository: findByMemberIdAndProductId(memberId, productId)

            alt 좋아요가 존재하지 않는 경우
                LikeRepository-->>LikeService: null
                LikeService->>LikeRepository: save(Like)
                LikeService->>Product: increaseLikeCount()
                Note over Product: 좋아요 수 증가
                LikeService-->>LikeFacade: LikeInfo
            else 좋아요가 이미 존재하는 경우 (멱등)
                LikeRepository-->>LikeService: Like
                Note over LikeService: 중복 등록 방지 (멱등성)
                LikeService-->>LikeFacade: LikeInfo
            end

            LikeFacade-->>LikeV1Controller: LikeInfo
            LikeV1Controller-->>Client: ApiResponse<LikeResponse>(200, success)
        end
    end
```

---

## 2. 상품 좋아요 취소 (멱등 동작)

```mermaid
sequenceDiagram
    participant Client
    participant LikeV1Controller
    participant LikeFacade
    participant LikeService
    participant ProductService
    participant LikeRepository
    participant Product

    Client->>LikeV1Controller: DELETE /api/v1/like/products/{productId}
    Note over Client,LikeV1Controller: Header: X-USER-ID

    LikeV1Controller->>LikeV1Controller: X-USER-ID 헤더 검증

    alt X-USER-ID 헤더 누락
        LikeV1Controller-->>Client: ApiResponse(400, "X-USER-ID 헤더 정보 누락입니다.")
    else 정상 요청
        LikeV1Controller->>LikeFacade: cancelLike(memberId, productId)

        LikeFacade->>ProductService: getProduct(productId)

        alt 상품이 존재하지 않음
            ProductService-->>LikeFacade: throw ProductNotFoundException
            LikeFacade-->>LikeV1Controller: Exception
            LikeV1Controller-->>Client: ApiResponse(404, "상품을 찾을 수 없습니다")
        else 상품 존재
            ProductService-->>LikeFacade: Product

            LikeFacade->>LikeService: cancelLike(memberId, productId)

            LikeService->>LikeRepository: findByMemberIdAndProductId(memberId, productId)

            alt 좋아요가 존재하는 경우
                LikeRepository-->>LikeService: Like
                LikeService->>LikeRepository: delete(like)
                LikeService->>Product: decreaseLikeCount()
                Note over Product: 좋아요 수 감소
                LikeService-->>LikeFacade: void
            else 좋아요가 존재하지 않는 경우 (멱등)
                LikeRepository-->>LikeService: null
                Note over LikeService: 이미 취소됨 (멱등성)
                LikeService-->>LikeFacade: void
            end

            LikeFacade-->>LikeV1Controller: void
            LikeV1Controller-->>Client: ApiResponse(200, success)
        end
    end
```

---

## 3. 주문 생성 및 결제 흐름

### 시나리오
사용자가 여러 상품을 주문하고, 재고 차감 → 포인트 차감 → 외부 시스템 연동을 거쳐 주문이 완료되는 전체 흐름입니다.

```mermaid
sequenceDiagram
    participant Client
    participant OrderV1Controller
    participant OrderFacade
    participant OrderService
    participant ProductService
    participant MemberService
    participant ExternalOrderClient
    participant OrderRepository
    participant Product
    participant Member

    Client->>OrderV1Controller: POST /api/v1/orders
    Note over Client,OrderV1Controller: Header: X-USER-ID<br/>Body: {items: [{productId, quantity}]}

    OrderV1Controller->>OrderV1Controller: X-USER-ID 헤더 & 요청 검증

    alt X-USER-ID 헤더 누락
        OrderV1Controller-->>Client: ApiResponse(400, "X-USER-ID 헤더 정보 누락입니다.")
    else 주문 아이템 비어있음
        OrderV1Controller-->>Client: ApiResponse(400, "Order items cannot be empty")
    else 수량이 0 이하
        OrderV1Controller-->>Client: ApiResponse(400, "Quantity must be positive")
    else 정상 요청
        OrderV1Controller->>OrderFacade: createOrder(command)

        Note over OrderFacade: 1. 상품 정보 조회 및 유효성 검증
        OrderFacade->>ProductService: getProducts(productIds)

        alt 존재하지 않는 상품 포함
            ProductService-->>OrderFacade: throw ProductNotFoundException
            OrderFacade-->>OrderV1Controller: Exception
            OrderV1Controller-->>Client: ApiResponse(404, "상품을 찾을 수 없습니다")
        else 모든 상품 존재
            ProductService-->>OrderFacade: List<Product>

            Note over OrderFacade: 2. 재고 확인
            loop 각 상품에 대해
                OrderFacade->>Product: hasEnoughStock(quantity)
                alt 재고 부족
                    Product-->>OrderFacade: throw InsufficientStockException
                    OrderFacade-->>OrderV1Controller: Exception
                    OrderV1Controller-->>Client: ApiResponse(400, "상품 '{name}'의 재고가 부족합니다")
                end
            end

            Note over OrderFacade: 3. 총 금액 계산
            OrderFacade->>OrderFacade: calculateTotalAmount(items)

            Note over OrderFacade: 4. 포인트 잔액 확인
            OrderFacade->>MemberService: getMember(memberId)
            MemberService-->>OrderFacade: Member
            OrderFacade->>Member: hasEnoughPoint(totalAmount)

            alt 포인트 부족
                Member-->>OrderFacade: throw InsufficientPointException
                OrderFacade-->>OrderV1Controller: Exception
                OrderV1Controller-->>Client: ApiResponse(400, "포인트가 부족합니다. 필요: {amount}, 보유: {balance}")
            else 포인트 충분
                Note over OrderFacade: 5. 트랜잭션 시작

                OrderFacade->>OrderService: createOrder(memberId, items, totalAmount)

                loop 각 상품에 대해
                    OrderService->>Product: decreaseStock(quantity)
                    Note over Product: 재고 차감 (비관적 락 또는 낙관적 락 적용)
                end

                OrderService->>Member: usePoint(totalAmount)
                Note over Member: 포인트 차감 (비관적 락 또는 낙관적 락 적용)

                OrderService->>OrderRepository: save(Order)
                Note over OrderRepository: 상태: PENDING
                OrderRepository-->>OrderService: Order

                Note over OrderService: 6. 외부 시스템 연동 (Mock)
                OrderService->>ExternalOrderClient: sendOrder(orderInfo)

                alt 외부 시스템 실패
                    ExternalOrderClient-->>OrderService: Exception
                    Note over OrderService: 트랜잭션 롤백<br/>(재고, 포인트 복원)
                    OrderService->>Order: fail()
                    Note over Order: 상태 → FAILED
                    OrderService-->>OrderFacade: throw ExternalSystemException
                    OrderFacade-->>OrderV1Controller: Exception
                    OrderV1Controller-->>Client: ApiResponse(500, "주문 처리 실패")
                else 외부 시스템 성공
                    ExternalOrderClient-->>OrderService: Success
                    Note over OrderService: 트랜잭션 커밋
                    OrderService->>Order: complete()
                    Note over Order: 상태 → COMPLETED
                    OrderService-->>OrderFacade: Order
                    OrderFacade-->>OrderV1Controller: OrderInfo
                    OrderV1Controller-->>Client: ApiResponse<OrderResponse>(200, success)
                end
            end
        end
    end
```

---

## 4. 상품 목록 조회 (필터링 및 정렬)

### 시나리오
사용자가 브랜드 필터링과 정렬 옵션을 적용하여 상품 목록을 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant ProductV1Controller
    participant ProductFacade
    participant ProductService
    participant ProductRepository

    Client->>ProductV1Controller: GET /api/v1/products?brandId=1&sort=latest&page=0&size=20

    ProductV1Controller->>ProductV1Controller: 요청 파라미터 검증

    alt 유효하지 않은 정렬 옵션
        ProductV1Controller-->>Client: ApiResponse(400, "유효하지 않은 정렬 옵션입니다.")
    else 유효하지 않은 페이지 파라미터 (음수)
        ProductV1Controller-->>Client: ApiResponse(400, "유효하지 않은 페이지 파라미터입니다.")
    else 정상 요청
        ProductV1Controller->>ProductFacade: getProducts(brandId, sort, pageable)

        ProductFacade->>ProductService: getProducts(brandId, sort, pageable)

        ProductService->>ProductRepository: findAll(brandId, sort, pageable)
        Note over ProductRepository: 브랜드 필터링 적용<br/>정렬 옵션 적용 (latest/price_asc/likes_desc)<br/>likes_count는 Product 엔티티에 비정규화

        ProductRepository-->>ProductService: Page<Product>

        ProductService-->>ProductFacade: Page<Product>

        ProductFacade-->>ProductV1Controller: Page<ProductInfo>
        ProductV1Controller-->>Client: ApiResponse<Page<ProductResponse>>(200, success)
    end
```

---

## 5. 내가 좋아요한 상품 목록 조회

### 시나리오
사용자가 자신이 좋아요한 상품 목록을 조회합니다.

```mermaid
sequenceDiagram
    participant Client
    participant LikeV1Controller
    participant LikeFacade
    participant LikeService
    participant LikeRepository

    Client->>LikeV1Controller: GET /api/v1/like/products?page=0&size=20
    Note over Client,LikeV1Controller: Header: X-USER-ID

    LikeV1Controller->>LikeV1Controller: X-USER-ID 헤더 검증

    alt X-USER-ID 헤더 누락
        LikeV1Controller-->>Client: ApiResponse(400, "X-USER-ID 헤더 정보 누락입니다.")
    else 정상 요청
        LikeV1Controller->>LikeFacade: getMyLikes(memberId, pageable)

        LikeFacade->>LikeService: getMyLikes(memberId, pageable)

        LikeService->>LikeRepository: findByMemberId(memberId, pageable)
        Note over LikeRepository: Member ID로 좋아요 목록 조회<br/>페이지네이션 적용
        LikeRepository-->>LikeService: Page<Like>

        Note over LikeService: Like 엔티티에서<br/>상품 정보, 브랜드명,<br/>좋아요 등록 시간 추출

        LikeService-->>LikeFacade: Page<LikeInfo>

        LikeFacade-->>LikeV1Controller: Page<LikeInfo>
        LikeV1Controller-->>Client: ApiResponse<Page<LikeResponse>>(200, success)
    end
```

---

## 6. 상품 상세 조회

### 시나리오
사용자가 특정 상품의 상세 정보를 조회합니다. 브랜드 정보와 좋아요 수가 포함됩니다.

```mermaid
sequenceDiagram
    participant Client
    participant ProductV1Controller
    participant ProductFacade
    participant ProductService
    participant BrandService
    participant ProductRepository

    Client->>ProductV1Controller: GET /api/v1/products/{productId}

    ProductV1Controller->>ProductFacade: getProductDetail(productId)

    ProductFacade->>ProductService: getProduct(productId)

    ProductService->>ProductRepository: findById(productId)

    alt 상품이 존재하지 않음
        ProductRepository-->>ProductService: null
        ProductService-->>ProductFacade: throw ProductNotFoundException
        ProductFacade-->>ProductV1Controller: Exception
        ProductV1Controller-->>Client: ApiResponse(404, "상품을 찾을 수 없습니다")
    else 상품이 존재함
        ProductRepository-->>ProductService: Product

        ProductService-->>ProductFacade: Product

        ProductFacade->>BrandService: getBrand(brandId)
        BrandService-->>ProductFacade: Brand

        Note over ProductFacade: Product와 Brand 조합하여<br/>ProductDetailInfo 생성<br/>(상품 상세 정보, 브랜드 정보, 좋아요 수 포함)

        ProductFacade-->>ProductV1Controller: ProductDetailInfo
        ProductV1Controller-->>Client: ApiResponse<ProductDetailResponse>(200, success)
    end
```

---

## 핵심 설계 포인트

### 1. 계층 구조 (실제 프로젝트 구조 반영)

```
interfaces/api (Controller)
    ↓
application (Facade)
    ↓
domain (Service, Entity, Repository)
    ↓
infrastructure (RepositoryImpl)
```

**각 계층의 책임:**
- **Controller (interfaces/api)**: HTTP 요청/응답 처리, DTO 변환, ApiResponse 생성
- **Facade (application)**: 여러 도메인 서비스 조율, 트랜잭션 경계, Command/Info 객체 변환
- **Service (domain)**: 도메인 로직 수행, 비즈니스 규칙 검증
- **Entity (domain)**: 비즈니스 규칙 (Product.decreaseStock(), Member.chargePoint())
- **Repository (domain, infrastructure)**: 영속성 인터페이스 및 구현

### 2. 좋아요 멱등성 보장
- **등록**: LikeRepository.findByMemberIdAndProductId()로 존재 여부 확인
- **취소**: 존재하지 않아도 예외 없이 성공 응답
- DB 제약조건 (UNIQUE INDEX on member_id, product_id)으로 중복 방지

### 3. 주문 트랜잭션 관리
- OrderService의 @Transactional로 원자성 보장
- 재고 차감(Product.decreaseStock()) → 포인트 차감(Member.usePoint()) → 주문 저장
- 외부 시스템(ExternalOrderClient) 실패 시 전체 롤백
- 동시성 제어: Product와 Member 엔티티 수정 시 JPA 낙관적 락 또는 비관적 락 고려
- 주문 상태: PENDING → COMPLETED (성공) 또는 FAILED (실패)

### 4. 조회 성능 최적화
- likes_count는 Product 엔티티에 비정규화하여 COUNT 쿼리 최소화
- 브랜드 필터링 및 정렬 시 ProductRepository에서 인덱스 활용
- 페이지네이션으로 대용량 데이터 처리

### 5. 도메인 주도 설계
- 비즈니스 로직은 도메인 엔티티에 배치
  - `Product.decreaseStock(quantity)`: 재고 차감 로직
  - `Product.increaseLikeCount()`: 좋아요 수 증가
  - `Product.decreaseLikeCount()`: 좋아요 수 감소
  - `Product.hasEnoughStock(quantity)`: 재고 확인
  - `Member.chargePoint(amount)`: 포인트 충전
  - `Member.usePoint(amount)`: 포인트 차감
  - `Member.hasEnoughPoint(amount)`: 포인트 잔액 확인
  - `Order.complete()`: 주문 완료 처리
  - `Order.fail()`: 주문 실패 처리
- Facade는 여러 도메인 서비스를 조율하는 역할만 수행

### 6. 예외 처리 전략
- **Controller Layer**: HTTP 요청 검증, X-USER-ID 헤더 검증
- **Facade Layer**: 비즈니스 로직 조율, 예외 전파
- **Service Layer**: 도메인 예외 발생 (ProductNotFoundException, InsufficientStockException 등)
- **GlobalExceptionHandler**: 일관된 ApiResponse 형식으로 예외 응답
- 모든 예외는 적절한 HTTP 상태 코드와 함께 사용자 친화적 메시지 반환
