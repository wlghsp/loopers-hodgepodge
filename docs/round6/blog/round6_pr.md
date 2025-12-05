## 📌 Summary

PG 통합 및 Resilience 패턴 적용

## 💬 Review Points

**1. PG 통합**
- Feign Client + 전략 패턴으로 PG 연동
- Circuit Breaker로 장애 전파 방지
- Fallback으로 결제 실패 시 주문 PENDING 처리

**2. 스케줄러 복구**
- 10분 이상 PENDING 주문을 PG에 직접 상태 조회
- 콜백 누락 시 복구

**3. 멱등성 처리**
- 중복 콜백 처리 방어

**4. 재고 차감 타이밍**
- PG 콜백 수신 후 재고 차감
- transactionKey 발급 ≠ 결제 완료

## ✅ Checklist

- [x] Payment 도메인 구현
- [x] PG Client (Feign) 구현
- [x] Circuit Breaker + Fallback 적용
- [x] Payment Recovery Scheduler
- [x] 멱등성 처리
- [x] Order API 구현
- [x] 스키마 및 초기 데이터 설정

## 📎 References

- CodeRabbit 리뷰 반영: Email pattern companion object 이동
