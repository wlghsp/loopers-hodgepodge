## 📌 Summary

브랜드별 상품 목록 조회 API 성능 개선
- Product-Brand Aggregate 분리하여 N+1 문제 해결
- 복합 인덱스 추가로 쿼리 성능 최적화
- Redis 캐시 적용으로 응답 속도 향상

## 💬 Review Points

**1. Aggregate 경계 설계**
- Product와 Brand의 양방향 연관관계를 단방향 ID 참조로 변경
- Brand 조인 쿼리가 완전히 제거되었는지 확인

**2. 인덱스 설계**
- `idx_products_brand_likes` (brand_id, likes_count DESC)
- `idx_products_deleted_likes` (deleted_at, likes_count DESC)
- 브랜드별/좋아요순 정렬 쿼리에 인덱스가 사용되는지 확인

**3. 캐시 설계**
- ProductCacheStore의 CachedPage 구조 (content + totalElements)
- Redis 장애 시에도 서비스가 정상 동작하는지 확인
- TTL 설정 (단건: 10분, 목록: 5분)

## ✅ Checklist

### 🔖 Index
- [x]  상품 목록 API에서 brandId 기반 검색, 좋아요 순 정렬 등을 처리했다
- [x]  조회 필터, 정렬 조건별 유즈케이스를 분석하여 인덱스를 적용하고 전 후 성능비교를 진행했다

### ❤️ Structure
- [x]  상품 목록/상세 조회 시 좋아요 수를 조회 및 좋아요 순 정렬이 가능하도록 구조 개선을 진행했다
- [x]  좋아요 적용/해제 진행 시 상품 좋아요 수 또한 정상적으로 동기화되도록 진행하였다

### ⚡ Cache
- [x]  Redis 캐시를 적용하고 TTL 또는 무효화 전략을 적용했다
- [x]  캐시 미스 상황에서도 서비스가 정상 동작하도록 처리했다.

## 📎 References
<!--
  (Optional: 참고 자료가 없는 작업 - 단순 버그 픽스 등 의 경우엔 해당 란을 제거해주세요 !)
  리뷰어가 참고할 수 있는 추가적인 정보나 문서, 링크 등을 작성해주세요.
  예시:
  - 관련 문서 링크
  - 관련 정책 링크
-->