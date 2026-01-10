# 🚀 Round 10: Spring Batch로 주간/월간 랭킹 시스템 구축

> Redis ZSET 일간 랭킹을 활용한 주간/월간 집계 및 Materialized View 구축

---

## 📋 구현 가이드 목차

### [STEP 1: 데이터베이스 테이블 생성](./STEP1_DATABASE.md)
- MV 테이블 SQL 작성
- Docker MySQL에 테이블 추가
- 테이블 생성 확인

### [STEP 2: commerce-batch 모듈 생성](./STEP2_MODULE_SETUP.md)
- 디렉토리 구조 생성
- build.gradle.kts 작성
- Application 클래스 작성
- application.yml 설정

### [STEP 3: Entity & Repository](./STEP3_ENTITY_REPOSITORY.md)
- MaterializedViewWeekly/Monthly Entity
- Repository 인터페이스 작성

### [STEP 4: DateUtils 유틸리티](./STEP4_UTILS.md)
- ISO Week 계산
- Year-Month 변환
- 날짜 리스트 생성

### [STEP 5: 주간 랭킹 Job](./STEP5_WEEKLY_JOB.md)
- WeeklyRankingJobConfig 작성
- Redis 7일치 데이터 집계
- TOP 100 선택 및 저장

### [STEP 6: 월간 랭킹 Job](./STEP6_MONTHLY_JOB.md)
- MonthlyRankingJobConfig 작성
- Redis 30일치 데이터 집계
- TOP 100 선택 및 저장

### [STEP 7: 스케줄러 설정](./STEP7_SCHEDULER.md)
- RankingBatchScheduler 작성
- 주간: 매주 월요일 새벽 1시
- 월간: 매월 1일 새벽 2시

### [STEP 8: Ranking API 확장](./STEP8_API_EXTENSION.md)
- RankingPeriod Enum
- RankingFacade 메서드 추가
- Controller period 파라미터 추가

### [STEP 9: 최종 테스트](./STEP9_FINAL_TEST.md)
- 전체 시스템 통합 테스트
- 페이지네이션 테스트
- 최종 체크리스트

### [STEP 10: 테스트 코드 작성](./STEP10_TEST_CODE.md)
- DateUtils 단위 테스트
- Repository 테스트 (DataJpaTest)
- Batch Job 통합 테스트
- API Controller 테스트 (WebMvcTest)

---

## 🎯 구현 목표

1. **Spring Batch로 주간/월간 랭킹 집계**
2. **Materialized View 테이블에 TOP 100 저장**
3. **API에서 period로 일간/주간/월간 선택**

---

## 📊 시스템 구조

```
[Redis ZSET]                [Spring Batch]              [MySQL MV]
ranking:all:20251222  ──┐
ranking:all:20251223  ──┤
ranking:all:20251224  ──┤
ranking:all:20251225  ──┼──▶ WeeklyRankingJob  ──▶  mv_product_rank_weekly
ranking:all:20251226  ──┤    (7일 집계)              (TOP 100)
ranking:all:20251227  ──┤
ranking:all:20251228  ──┘

                             MonthlyRankingJob ──▶  mv_product_rank_monthly
                             (30일 집계)             (TOP 100)
```

---

## 🔗 API 스펙

### 일간 랭킹 (기존)
```
GET /api/v1/rankings?period=daily&date=20251226&size=10&page=0
```

### 주간 랭킹 (신규)
```
GET /api/v1/rankings?period=weekly&date=2025-W52&size=10&page=0
```

### 월간 랭킹 (신규)
```
GET /api/v1/rankings?period=monthly&date=2025-12&size=10&page=0
```

---

## ⏱️ 예상 소요 시간

- **STEP 1-2**: 30분 (모듈 셋업)
- **STEP 3-4**: 30분 (Entity, Utils)
- **STEP 5-6**: 1시간 (Batch Job)
- **STEP 7**: 30분 (스케줄러)
- **STEP 8**: 1시간 (API 확장)
- **STEP 9**: 30분 (통합 테스트)
- **STEP 10**: 1시간 (테스트 코드)

**총 예상 시간**: 5시간

---

## 🎓 학습 포인트

- **Spring Batch**: Job, Step, Tasklet
- **Materialized View**: 조회 성능 최적화
- **스케줄링**: @Scheduled, Cron 표현식
- **데이터 파이프라인**: Redis → Batch → MySQL → API

---

## ✅ 과제 체크리스트

### 📈 Ranking Consumer
- [x] 랭킹 ZSET의 TTL, 키 전략 구성
- [x] 날짜별로 적재할 키 계산 기능
- [x] 이벤트 발생 후, ZSET 점수 반영

### ⚾ Ranking API
- [x] 랭킹 Page 조회 시 정상 반환
- [x] 상품정보 Aggregation
- [x] 상품 상세 조회 시 순위 반환

### 🧱 Spring Batch (Round 10 신규)
- [ ] Spring Batch Job 작성 및 파라미터 기반 동작
- [ ] Chunk Oriented Processing (또는 Tasklet)
- [ ] Materialized View 구조 설계 및 적재

### 🧩 Ranking API 확장 (Round 10 신규)
- [ ] API가 일간/주간/월간 랭킹 제공
- [ ] period에 따라 적절한 데이터 기반 랭킹 제공

---

**준비되셨나요? [STEP 1부터 시작하세요!](./STEP1_DATABASE.md)**
