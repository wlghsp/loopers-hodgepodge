# Round 10 작업 현황 (2025-12-31)

> Spring Batch 주간/월간 랭킹 시스템 구현

---

## ✅ 완료된 작업

### 1. 데이터베이스 스키마 (STEP1)
- [x] `docker/01-schema.sql`에 `product_rank_weekly`, `product_rank_monthly` 테이블 추가
- [x] 인덱스 설계 완료 (`idx_year_week`, `uk_product_week` 등)

### 2. 모듈 설정 (STEP2)
- [x] `apps/commerce-batch` 모듈 생성
- [x] `settings.gradle.kts`에 모듈 등록
- [x] `build.gradle.kts` 의존성 추가
  - Spring Batch
  - JPA, Redis 모듈 연동
  - 테스트 의존성 (spring-batch-test, mockk)
- [x] `CommerceBatchApplication.kt` 작성
  - `@EnableScheduling` 설정
  - TimeZone 설정 (`Asia/Seoul`)
  - exitProcess 처리

### 3. Entity & Repository (STEP3)
- [x] `ProductRankWeekly` 엔티티 (modules/jpa)
- [x] `ProductRankMonthly` 엔티티 (modules/jpa)
- [x] `ProductRankWeeklyRepository` (commerce-batch)
- [x] `ProductRankMonthlyRepository` (commerce-batch)
- [x] Custom delete 메서드 구현

### 4. Utilities (STEP4)
- [x] `DateUtils` 작성 (commerce-batch)
  - `toYearWeek()`: ISO Week 변환
  - `getWeekDates()`: 주차의 7일 날짜 리스트
  - `toYearMonth()`: 년-월 변환
  - `getMonthDates()`: 월의 모든 날짜 리스트
  - `formatDate()`: yyyyMMdd 포맷

### 5. Batch Job 구현 (STEP5, STEP6)
- [x] `WeeklyRankingJobConfig` (Chunk 방식)
  - Reader: Redis 7일치 ZSET 집계 → TOP 100 선택
  - Processor: `ProductRankWeekly` 엔티티 변환
  - Writer: DB 저장
  - 멱등성 보장 (기존 데이터 삭제)
- [x] `MonthlyRankingJobConfig` (Chunk 방식)
  - Reader: Redis 30일치 ZSET 집계 → TOP 100 선택
  - Processor: `ProductRankMonthly` 엔티티 변환
  - Writer: DB 저장

### 6. Batch Listener (멘토 코드 적용)
- [x] `JobListener` (시작/종료 시간, 총 소요 시간 로깅)
- [x] `StepMonitorListener` (Step 실패 모니터링)
- [x] Job/Step에 Listener 적용

### 7. Scheduler (STEP7)
- [x] `RankingBatchScheduler` 작성
  - 주간 랭킹: 매주 월요일 01:00 (`0 0 1 * * MON`)
  - 월간 랭킹: 매월 1일 02:00 (`0 0 2 1 * *`)
  - JobParameters 설정 (yearWeek, yearMonth, timestamp)

### 8. API 확장 (STEP8 - commerce-api)
- [x] `RankingPeriod` enum (DAILY, WEEKLY, MONTHLY)
- [x] `RankingFacade` 확장
  - `getWeeklyRankings()` 추가
  - `getMonthlyRankings()` 추가
  - 페이징 처리
- [x] `RankingV1Controller` 수정
  - `period` 파라미터 추가
  - API 응답 형식 통일
- [x] Repository 주입 (commerce-api에서 commerce-batch 모듈 참조 불가 → modules/jpa 활용)

### 9. Configuration
- [x] `application.yml` 설정
  - `spring.batch.job.enabled: false` (자동 실행 방지)
  - `spring.batch.jdbc.initialize-schema: never` (docker에서 관리)
- [x] `BatchConfig` (선택 사항)

### 10. 문서화
- [x] Step별 가이드 (STEP1~STEP10)
- [x] 테스트 코드 가이드 (STEP10_TEST_CODE.md)
- [x] PR 작성 템플릿 (PR_TEMPLATE.md)
- [x] 현황 문서 (CURRENT_STATUS.md)

---

## 🔧 멘토 제공 코드 적용 내역

### 외부 `/commerce-batch` → `apps/commerce-batch` 적용

| 파일 | 적용 여부 | 설명 |
|------|-----------|------|
| `CommerceBatchApplication.kt` | ✅ 적용 | TimeZone, exitProcess 추가 |
| `JobListener.kt` | ✅ 적용 | Job 시작/종료 시간 로깅 |
| `StepMonitorListener.kt` | ✅ 적용 | Step 실패 모니터링 |
| `build.gradle.kts` | ✅ 참고 | test-fixtures 추가 |
| `application.yml` | ✅ 참고 | 프로파일 구조 참고 |
| `DemoJobConfig.kt` | ❌ 미적용 | 데모용 코드 |
| `ChunkListener.kt` | ❌ 미적용 | 현재 필요 없음 |

---

## 🚧 남은 작업 (Step 9, 10)

### STEP9: 최종 테스트
- [ ] Docker 환경 실행 확인
- [ ] Redis에 테스트 데이터 적재
- [ ] 배치 수동 실행 테스트
  ```bash
  curl -X POST "http://localhost:8085/batch/weekly?yearWeek=2025-W52"
  curl -X POST "http://localhost:8085/batch/monthly?yearMonth=2025-12"
  ```
- [ ] MV 테이블 데이터 확인
- [ ] API 조회 테스트
  ```bash
  curl "http://localhost:8081/api/v1/rankings?period=weekly&date=2025-W52&size=10"
  curl "http://localhost:8081/api/v1/rankings?period=monthly&date=2025-12&size=10"
  ```
- [ ] 스케줄러 동작 확인
- [ ] 멱등성 테스트 (동일 파라미터 재실행)

### STEP10: 테스트 코드 작성
- [ ] `DateUtilsTest` (단위 테스트)
- [ ] `WeeklyRankingJobConfigTest` (통합 테스트)
- [ ] `MonthlyRankingJobConfigTest` (통합 테스트)
- [ ] `RankingFacadeTest` (Mock 테스트)
- [ ] `RankingFacadeIntegrationTest` (통합 테스트)
- [ ] 전체 테스트 실행 및 검증

---

## 📁 현재 프로젝트 구조

```
loopers-spring-kotlin-template/
├── apps/
│   ├── commerce-api/          # API 서버
│   │   └── src/main/kotlin/com/loopers/
│   │       └── application/ranking/
│   │           ├── RankingFacade.kt         (✅ STEP8 수정)
│   │           └── RankingPeriod.kt         (✅ STEP8 추가)
│   └── commerce-batch/        # Batch 서버 (✅ 신규 생성)
│       ├── build.gradle.kts   (✅ 멘토 코드 참고)
│       └── src/main/kotlin/com/loopers/
│           ├── CommerceBatchApplication.kt  (✅ 멘토 코드 적용)
│           ├── batch/
│           │   ├── listener/
│           │   │   ├── JobListener.kt       (✅ 멘토 코드 적용)
│           │   │   └── StepMonitorListener.kt (✅ 멘토 코드 적용)
│           │   └── ranking/
│           │       ├── WeeklyRankingJobConfig.kt  (✅ STEP5)
│           │       └── MonthlyRankingJobConfig.kt (✅ STEP6)
│           ├── infrastructure/
│           │   ├── ProductRankWeeklyRepository.kt  (✅ STEP3)
│           │   └── ProductRankMonthlyRepository.kt (✅ STEP3)
│           ├── scheduler/
│           │   └── RankingBatchScheduler.kt  (✅ STEP7)
│           ├── support/
│           │   └── DateUtils.kt              (✅ STEP4)
│           └── interfaces/batch/
│               └── BatchTestController.kt    (✅ STEP8)
│
├── modules/jpa/
│   └── src/main/kotlin/com/loopers/domain/ranking/
│       ├── ProductRankWeekly.kt   (✅ STEP3)
│       └── ProductRankMonthly.kt  (✅ STEP3)
│
├── docker/
│   └── 01-schema.sql              (✅ STEP1 - MV 테이블 추가)
│
└── .codeguide/round10/
    ├── README.md
    ├── STEP1_DATABASE.md ~ STEP10_TEST_CODE.md
    ├── PR_TEMPLATE.md
    └── CURRENT_STATUS.md (이 파일)
```

---

## 🔍 주요 기술 스택 & 패턴

### 기술 스택
- **Spring Batch 5.x** (Chunk 기반 처리)
- **Redis ZSET** (일간 랭킹 데이터 소스)
- **MySQL** (Materialized View 저장)
- **Kotlin** + **Spring Boot 3.x**

### 적용 패턴
1. **Materialized View Pattern**
   - Redis 집계 결과를 MySQL에 사전 저장
   - 읽기 성능 최적화 (O(N) → O(1))

2. **Chunk-oriented Processing**
   - Reader: Redis 집계 및 TOP 100 선택
   - Processor: 엔티티 변환
   - Writer: DB 일괄 저장

3. **Idempotency (멱등성)**
   - 배치 실행 시작 시 기존 데이터 삭제
   - 동일 파라미터 재실행 시 결과 동일 보장

4. **ISO Week Standard**
   - ISO 8601 기준 주차 계산
   - 월요일 시작, `yyyy-Www` 형식

---

## ⚠️ 알려진 이슈 & 개선 사항

### 현재 이슈
1. **Redis 키 형식 확인 필요**
   - 현재 코드: `productId.replace("product:", "")`
   - 실제 Redis 키가 `product:123` 형식인지 검증 필요

2. **Repository 반환 타입**
   - `deleteByYearWeek()` 반환 타입 확인
   - Weekly: `Unit` / Monthly: `Long` → 통일 필요

3. **Test 환경 설정**
   - `@TestPropertySource(properties = ["spring.task.scheduling.enabled=false"])`
   - Redis, MySQL 연결 설정 확인

### 향후 개선 사항
1. **과거 데이터 정리 정책**
   - 1년 이상 된 MV 데이터 아카이빙
   - 스케줄러 추가 고려

2. **배치 실패 시 재시도 전략**
   - 현재: 로깅만 (StepMonitorListener)
   - 개선: Slack 알림, 재시도 로직 추가

3. **성능 최적화**
   - Redis 파이프라인 사용 고려
   - Chunk Size 조정 (현재 100)

4. **모니터링 강화**
   - 배치 실행 시간 메트릭 수집
   - 실패율 모니터링

---

## 🎯 다음 단계

1. **즉시 작업**
   - [ ] STEP9 최종 테스트 진행
   - [ ] Redis 키 형식 확인 및 수정
   - [ ] Repository 반환 타입 통일

2. **테스트 작성**
   - [ ] STEP10 가이드 참고하여 테스트 코드 작성
   - [ ] 전체 테스트 실행 및 커버리지 확인

3. **PR 작성**
   - [ ] PR_TEMPLATE.md 참고하여 PR 작성
   - [ ] Review Points 작성 (5개 주요 의사결정)
   - [ ] 체크리스트 작성

---

**마지막 업데이트**: 2025-12-31
**작업자**: jihochoi
**진행률**: 80% (STEP8 완료, STEP9-10 남음)
