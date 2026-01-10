# Step 1: 데이터베이스 테이블 생성

> MV (Materialized View) 테이블 추가

---

## 1.1 MV 테이블 SQL 추가

**파일**: `docker/01-schema.sql`

파일 맨 아래(`-- 생성 결과 확인` 바로 위, 270번째 줄 근처)에 추가:

```sql
-- ================================================
-- 15. mv_product_rank_weekly 테이블
-- ================================================
CREATE TABLE IF NOT EXISTS mv_product_rank_weekly (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL COMMENT '상품 ID',
    year_week VARCHAR(10) NOT NULL COMMENT 'ISO Week: 2025-W52',
    score DOUBLE NOT NULL COMMENT '랭킹 점수',
    rank_position INT NOT NULL COMMENT '순위 (1~100)',
    created_at DATETIME(6) NOT NULL COMMENT '생성 시각',
    updated_at DATETIME(6) NOT NULL COMMENT '수정 시각',

    UNIQUE KEY uk_product_year_week (product_id, year_week),
    INDEX idx_year_week_rank (year_week, rank_position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='주간 상품 랭킹 MV';

-- ================================================
-- 16. mv_product_rank_monthly 테이블
-- ================================================
CREATE TABLE IF NOT EXISTS mv_product_rank_monthly (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL COMMENT '상품 ID',
    year_month VARCHAR(7) NOT NULL COMMENT '2025-12',
    score DOUBLE NOT NULL COMMENT '랭킹 점수',
    rank_position INT NOT NULL COMMENT '순위 (1~100)',
    created_at DATETIME(6) NOT NULL COMMENT '생성 시각',
    updated_at DATETIME(6) NOT NULL COMMENT '수정 시각',

    UNIQUE KEY uk_product_year_month (product_id, year_month),
    INDEX idx_year_month_rank (year_month, rank_position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='월간 상품 랭킹 MV';
```

---

## 1.2 테이블 적용 (택 1)

### 방법 1: 기존 데이터 유지 (권장)

```bash
docker exec -i loopers-mysql mysql -uroot -ppassword loopers < docker/01-schema.sql
```

### 방법 2: 컨테이너 재시작 (데이터 초기화)

```bash
docker-compose down -v && docker-compose up -d
```

### 방법 3: MySQL 직접 접속

```bash
docker exec -it loopers-mysql mysql -uroot -ppassword loopers

# 위의 SQL을 직접 복사해서 실행
```

---

## 1.3 테이블 생성 확인

```bash
docker exec -it loopers-mysql mysql -uroot -ppassword loopers

# MySQL 접속 후
SHOW TABLES LIKE 'mv_%';
DESC mv_product_rank_weekly;
DESC mv_product_rank_monthly;
```

**결과 예시:**
```
+----------------------------------+
| Tables_in_loopers (mv_%)         |
+----------------------------------+
| mv_product_rank_monthly          |
| mv_product_rank_weekly           |
+----------------------------------+
```

---

## ✅ Step 1 완료 체크

- [ ] `docker/01-schema.sql`에 테이블 SQL 추가
- [ ] 테이블 적용 명령어 실행
- [ ] `SHOW TABLES`로 테이블 생성 확인

---

**다음 단계**: [Step 2: commerce-batch 모듈 생성](./STEP2_MODULE_SETUP.md)
