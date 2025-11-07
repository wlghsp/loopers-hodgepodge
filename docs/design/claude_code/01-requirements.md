# 01. 요구사항 명세서

## 1. 유저 스토리

### [US-1] 상품 탐색 및 브랜드 필터링
**As a** 사용자
**I want to** 다양한 브랜드의 상품을 탐색하고 필터링하고 싶다
**So that** 원하는 상품을 쉽게 찾을 수 있다

**Main Flow:**
1. 사용자가 상품 목록 조회 API 호출 (GET `/api/v1/products`)
2. 시스템이 브랜드 필터링 조건 확인 (brandId 파라미터)
3. 시스템이 정렬 옵션 적용 (latest/price_asc/likes_desc)
4. 시스템이 페이지네이션 처리 (page, size)
5. 시스템이 각 상품의 좋아요 수 조회
6. 상품 목록과 페이지네이션 정보를 응답으로 반환
7. 사용자가 관심 상품 클릭하여 상세 정보 조회

**Alternate Flow:**
- 2a. 브랜드 필터링 조건이 없는 경우 → 전체 상품 조회
- 3a. 정렬 옵션이 없는 경우 → 기본 정렬 적용 (최신순)
- 4a. 페이지 정보가 없는 경우 → 기본값 적용 (page=0, size=20)

**Exception Flow:**
- 2e. 존재하지 않는 brandId 입력 → 빈 결과 반환 (200 OK, empty content)
- 3e. 잘못된 정렬 옵션 입력 → 400 Bad Request 반환
- 4e. 잘못된 페이지 파라미터 입력 (음수) → 400 Bad Request 반환

**Acceptance Criteria:**
- 페이지네이션이 적용된 상품 목록이 반환된다
- 브랜드별 필터링이 동작한다
- 각 상품에 총 좋아요 수가 표시된다
- 잘못된 입력에 대해 적절한 오류 메시지를 반환한다

---

### [US-2] 상품 좋아요 관리
**As a** 사용자
**I want to** 마음에 드는 상품에 좋아요를 등록/취소하고 싶다
**So that** 나중에 관심 상품을 다시 볼 수 있다

**Main Flow (좋아요 등록):**
1. 사용자가 상품 페이지에서 좋아요 버튼 클릭 (POST `/api/v1/like/products/{productId}`)
2. 시스템이 상품 존재 여부 확인
3. 시스템이 해당 사용자의 좋아요 존재 여부 확인
4. 좋아요가 없으면 새로운 좋아요 생성
5. 상품의 좋아요 수 증가
6. 성공 응답과 함께 현재 좋아요 수 반환

**Main Flow (좋아요 취소):**
1. 사용자가 좋아요 버튼 다시 클릭 (DELETE `/api/v1/like/products/{productId}`)
2. 시스템이 상품 존재 여부 확인
3. 시스템이 해당 사용자의 좋아요 존재 여부 확인
4. 좋아요가 있으면 삭제
5. 상품의 좋아요 수 감소
6. 성공 응답과 함께 현재 좋아요 수 반환

**Alternate Flow:**
- 1a. 사용자가 내가 좋아요한 상품 목록 조회 (GET `/api/v1/like/products`)
  - 시스템이 사용자의 좋아요 목록을 페이지네이션하여 반환
  - 각 상품의 기본 정보와 좋아요 등록 시간 포함

**Exception Flow:**
- 2e. 존재하지 않는 상품에 좋아요 시도 → 404 Not Found 반환
- 4e. 이미 좋아요가 존재하는 경우 (등록) → 멱등성 보장, 200 OK 반환 (중복 생성 없음)
- 3e. 좋아요가 존재하지 않는 경우 (취소) → 멱등성 보장, 200 OK 반환 (오류 없음)
- *e. X-USER-ID 헤더 누락 → 400 Bad Request 반환

**Acceptance Criteria:**
- 좋아요 등록/취소가 멱등하게 동작한다
- 동시 요청 시에도 정합성이 유지된다 (DB Unique 제약조건)
- 같은 요청을 여러 번 보내도 동일한 결과를 반환한다

---

### [US-3] 주문 생성 및 결제
**As a** 사용자
**I want to** 여러 상품을 한 번에 주문하고 포인트로 결제하고 싶다
**So that** 원하는 상품을 구매할 수 있다

**Main Flow:**
1. 사용자가 여러 상품과 수량을 선택하여 주문 요청 (POST `/api/v1/orders`)
2. 시스템이 요청된 모든 상품의 존재 여부 확인
3. 시스템이 각 상품의 재고 확인 (요청 수량 ≤ 재고)
4. 시스템이 총 주문 금액 계산 (상품 가격 × 수량의 합계)
5. 시스템이 사용자의 포인트 잔액 확인 (총 금액 ≤ 보유 포인트)
6. 트랜잭션 시작:
   - 6.1. 각 상품의 재고 차감 (비관적 락 적용)
   - 6.2. 사용자 포인트 차감 (비관적 락 적용)
   - 6.3. 주문 및 주문 아이템 생성 (상태: PENDING)
7. 주문 정보를 외부 시스템에 전송 (Mock API)
8. 외부 시스템 응답 성공 시 주문 상태를 COMPLETED로 변경
9. 트랜잭션 커밋
10. 주문 완료 응답 반환 (orderId, status, items, totalAmount)

**Alternate Flow:**
- 1a. 단일 상품 주문 → Main Flow 동일하게 진행
- 6a. 외부 시스템 Mock이 아닌 실제 API 연동 시 → Async 처리 고려

**Exception Flow:**
- 2e. 존재하지 않는 상품 포함 시 → 404 Not Found 반환
- 3e. 재고 부족 시 → 400 Bad Request 반환 ("상품 '{상품명}'의 재고가 부족합니다")
- 5e. 포인트 부족 시 → 400 Bad Request 반환 ("포인트가 부족합니다. 필요: {금액}, 보유: {잔액}")
- 7e. 외부 시스템 연동 실패 시 → 트랜잭션 롤백 (재고, 포인트 복원), 주문 상태: FAILED, 500 Internal Server Error 반환
- *e. 주문 아이템이 비어있는 경우 → 400 Bad Request 반환
- *e. 수량이 0 이하인 경우 → 400 Bad Request 반환
- *e. X-USER-ID 헤더 누락 → 400 Bad Request 반환

**Acceptance Criteria:**
- 재고와 포인트가 원자적으로 차감된다 (트랜잭션 보장)
- 동시 주문 시 정합성이 보장된다 (비관적 락)
- 외부 시스템 실패 시 모든 변경사항이 롤백된다
- 주문 처리 중 어떤 단계에서든 실패 시 일관성이 유지된다

## 2. 유비쿼터스 언어

| 한글 | 영문 | 설명 |
|------|------|------|
| 회원 | Member | 서비스에 가입한 사용자 |
| 상품 | Product | 판매되는 개별 상품 |
| 브랜드 | Brand | 상품을 제공하는 브랜드 |
| 좋아요 | Like | 사용자가 상품에 표시하는 관심 표현 |
| 주문 | Order | 사용자가 상품을 구매하기 위해 생성하는 거래 |
| 주문 아이템 | OrderItem | 주문에 포함된 상품과 수량 |
| 포인트 | Point | 사용자가 보유한 결제 수단 |
| 재고 | Stock | 상품의 판매 가능 수량 |

**주문 상태 (OrderStatus)**
- `PENDING`: 주문 생성, 결제 대기
- `COMPLETED`: 결제 완료
- `FAILED`: 주문 실패
- `CANCELLED`: 사용자 취소

---

## 3. API 명세

### 3.1 상품 & 브랜드

#### GET `/api/v1/products`
상품 목록 조회

**Query Parameters:**
- `brandId` (Long, optional): 브랜드 필터링
- `sort` (String, optional): 정렬 기준 (latest, price_asc, likes_desc)
- `page` (Integer, optional, default=0)
- `size` (Integer, optional, default=20)

**Response:**
```json
{
  "content": [
    {
      "id": 1,
      "name": "감성 티셔츠",
      "price": 29000,
      "stock": 50,
      "brandId": 1,
      "brandName": "감성브랜드",
      "likesCount": 42
    }
  ],
  "pageable": { "pageNumber": 0, "pageSize": 20, "totalPages": 5, "totalElements": 100 }
}
```

---

#### GET `/api/v1/products/{productId}`
상품 상세 조회

**Response:**
```json
{
  "id": 1,
  "name": "감성 티셔츠",
  "description": "편안한 착용감의 감성 티셔츠",
  "price": 29000,
  "stock": 50,
  "brand": { "id": 1, "name": "감성브랜드" },
  "likesCount": 42
}
```

---

#### GET `/api/v1/brands/{brandId}`
브랜드 조회

**Response:**
```json
{
  "id": 1,
  "name": "감성브랜드",
  "description": "감성을 담은 브랜드"
}
```

---

### 3.2 좋아요

#### POST `/api/v1/like/products/{productId}`
상품 좋아요 등록 (멱등)

**Headers:** `X-USER-ID` (required)

**Response:**
```json
{
  "success": true,
  "message": "좋아요가 등록되었습니다.",
  "likesCount": 43
}
```

---

#### DELETE `/api/v1/like/products/{productId}`
상품 좋아요 취소 (멱등)

**Headers:** `X-USER-ID` (required)

**Response:**
```json
{
  "success": true,
  "message": "좋아요가 취소되었습니다.",
  "likesCount": 42
}
```

---

#### GET `/api/v1/like/products`
내가 좋아요한 상품 목록 조회

**Headers:** `X-USER-ID` (required)
**Query Parameters:** `page`, `size`

**Response:**
```json
{
  "content": [
    {
      "productId": 1,
      "productName": "감성 티셔츠",
      "price": 29000,
      "brandName": "감성브랜드",
      "likesCount": 42,
      "likedAt": "2025-01-02T14:30:00"
    }
  ],
  "pageable": { ... }
}
```

---

### 3.3 주문

#### POST `/api/v1/orders`
주문 생성

**Headers:** `X-USER-ID` (required)

**Request:**
```json
{
  "items": [
    { "productId": 1, "quantity": 2 },
    { "productId": 3, "quantity": 1 }
  ]
}
```

**Response:**
```json
{
  "orderId": 1001,
  "userId": "user123",
  "status": "COMPLETED",
  "totalAmount": 87000,
  "usedPoints": 87000,
  "items": [
    { "productId": 1, "productName": "감성 티셔츠", "quantity": 2, "price": 29000, "subtotal": 58000 }
  ],
  "orderedAt": "2025-01-05T16:45:00"
}
```

**처리 흐름:**
1. 재고 확인 → 2. 포인트 확인 → 3. 재고 차감 → 4. 포인트 차감 → 5. 외부 시스템 전송(Mock) → 6. 주문 저장

**예외:**
- 재고 부족: `400 Bad Request`
- 포인트 부족: `400 Bad Request`
- 외부 시스템 실패: 트랜잭션 롤백

---

#### GET `/api/v1/orders`
주문 목록 조회

**Headers:** `X-USER-ID` (required)

---

#### GET `/api/v1/orders/{orderId}`
주문 상세 조회

**Headers:** `X-USER-ID` (required)

---

## 4. 비기능 요구사항

- **성능**: 상품 목록 조회 200ms, 주문 생성 500ms, 좋아요 100ms 이하
- **정합성**: 재고/포인트 차감 시 동시성 제어 (락 적용)
- **멱등성**: 좋아요 등록/취소는 멱등하게 동작
- **트랜잭션**: 주문 처리는 ACID 보장, 실패 시 롤백

---

## 5. 제약사항

- 인증/인가 없음 (`X-USER-ID` 헤더로 사용자 식별)
- 외부 결제(PG) 연동 없음
- 1주차 완료 기능: 회원가입, 포인트 충전
- 제외: 쿠폰, 배송, 주문 취소/환불, 리뷰
