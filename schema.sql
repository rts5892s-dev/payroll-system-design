-- ============================================================
-- 군포공장 급여·근태관리 시스템 — 데이터베이스 스키마 (MySQL 8.0 기준)
-- ============================================================

-- 1. 부서/부문 마스터
CREATE TABLE departments (
  dept_id       INT AUTO_INCREMENT PRIMARY KEY,
  division_name VARCHAR(50) NOT NULL,   -- 부문 (예: 관리, 생산)
  dept_name     VARCHAR(50) NOT NULL,   -- 부서 (예: 관리부, 생산1팀)
  UNIQUE KEY uq_dept (division_name, dept_name)
);

-- 2. 직원 마스터
CREATE TABLE employees (
  emp_id            BIGINT AUTO_INCREMENT PRIMARY KEY,
  emp_no            VARCHAR(20) NOT NULL UNIQUE,       -- 사번
  name              VARCHAR(50) NOT NULL,               -- 성명
  gender            ENUM('남','여') NOT NULL,
  dept_id           INT NOT NULL,
  position          VARCHAR(30) NOT NULL,               -- 직책
  dependents        TINYINT NOT NULL DEFAULT 0,         -- 부양가족수
  std_monthly_hours DECIMAL(6,2) NOT NULL DEFAULT 209.00, -- 월소정근로시간
  hire_date         DATE NOT NULL,
  resign_date       DATE NULL,
  status            ENUM('재직','휴직','퇴직') NOT NULL DEFAULT '재직',
  created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

-- 3. 연봉계약 이력 (연봉/기본급/직무수당은 변경 시점마다 이력 관리)
CREATE TABLE salary_contracts (
  contract_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
  emp_id          BIGINT NOT NULL,
  annual_salary   DECIMAL(12,0) NOT NULL,   -- 연봉
  base_salary     DECIMAL(12,0) NOT NULL,   -- 기본급
  job_allowance   DECIMAL(12,0) NOT NULL DEFAULT 0,  -- 직무수당
  effective_from  DATE NOT NULL,
  effective_to    DATE NULL,                -- NULL = 현재 유효
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id),
  INDEX idx_contract_emp_period (emp_id, effective_from, effective_to)
);

-- 4. 근무캘린더 (공휴일/휴일 판정 기준 — 세콤 등 외부연동 시 휴일근로 자동판별에 사용)
CREATE TABLE work_calendar (
  calendar_date DATE PRIMARY KEY,
  day_type      ENUM('평일','토요일','일요일','공휴일') NOT NULL,
  is_holiday    BOOLEAN NOT NULL DEFAULT FALSE,
  note          VARCHAR(100)
);

-- 5. 휴가 유형 마스터
CREATE TABLE leave_types (
  leave_type_id INT AUTO_INCREMENT PRIMARY KEY,
  type_name     VARCHAR(30) NOT NULL,   -- 연차/병가/경조사/공가 등
  is_paid       BOOLEAN NOT NULL DEFAULT TRUE
);

-- 6. 연차 잔여현황
CREATE TABLE leave_balances (
  emp_id        BIGINT NOT NULL,
  year          SMALLINT NOT NULL,
  granted_days  DECIMAL(5,1) NOT NULL DEFAULT 15,
  used_days     DECIMAL(5,1) NOT NULL DEFAULT 0,
  PRIMARY KEY (emp_id, year),
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id)
);

-- 7. 휴가 신청 (승인 워크플로)
CREATE TABLE leave_requests (
  request_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
  emp_id        BIGINT NOT NULL,
  leave_type_id INT NOT NULL,
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  days          DECIMAL(5,1) NOT NULL,
  status        ENUM('신청','승인','반려') NOT NULL DEFAULT '신청',
  approved_by   BIGINT NULL,
  approved_at   TIMESTAMP NULL,
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id),
  FOREIGN KEY (leave_type_id) REFERENCES leave_types(leave_type_id),
  FOREIGN KEY (approved_by) REFERENCES employees(emp_id)
);

-- 8. 일별 근태기록 (출퇴근 원장 — 지금은 담당자 입력, 향후 세콤 SQL DB 실시간 적재 대상)
CREATE TABLE attendance_daily (
  attendance_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
  emp_id          BIGINT NOT NULL,
  work_date       DATE NOT NULL,
  clock_in        TIME NULL,
  clock_out       TIME NULL,
  work_type       ENUM('정상','연장','야간연장','주간특근','야간특근','휴일','공제','연차','기타') NOT NULL DEFAULT '정상',
  hours           DECIMAL(4,1) NOT NULL DEFAULT 0,   -- work_type에 해당하는 시간
  leave_type_id   INT NULL,
  source          ENUM('수기입력','세콤연동') NOT NULL DEFAULT '수기입력',
  note            VARCHAR(100),
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id),
  FOREIGN KEY (leave_type_id) REFERENCES leave_types(leave_type_id),
  INDEX idx_att_emp_date (emp_id, work_date)
);

-- 9. 월별 근태 집계 (일별 기록을 월 단위로 합산 — 급여 상세(13번)의 입력값이 됨)
CREATE TABLE attendance_monthly_summary (
  emp_id            BIGINT NOT NULL,
  year_month        CHAR(7) NOT NULL,                 -- 'YYYY-MM'
  retention_hours   DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 보전시간
  sat_day_hours     DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 주간토요
  sat_night_hours   DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 야간토요
  night_ot_hours    DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 야간연장
  ot_hours          DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 연장시간
  holiday_hours     DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 휴일근로시간
  deduct_hours      DECIMAL(6,1) NOT NULL DEFAULT 0,   -- 공제시간(지각·조퇴·결근)
  is_confirmed      BOOLEAN NOT NULL DEFAULT FALSE,    -- 근태 확정 여부 (급여계산 게이트)
  confirmed_by      BIGINT NULL,
  confirmed_at      TIMESTAMP NULL,
  PRIMARY KEY (emp_id, year_month),
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id)
);

-- 10. 소득세 간이세액표 (연도별 개정)
CREATE TABLE statutory_income_tax (
  year          SMALLINT NOT NULL,
  salary_from   DECIMAL(12,0) NOT NULL,
  salary_to     DECIMAL(12,0) NOT NULL,
  dependents    TINYINT NOT NULL,
  tax_amount    DECIMAL(12,0) NOT NULL,
  PRIMARY KEY (year, salary_from, dependents)
);

-- 11. 4대보험 요율 (연도별 개정)
CREATE TABLE statutory_insurance_rates (
  year            SMALLINT NOT NULL,
  insurance_type  ENUM('국민연금','건강보험','장기요양보험','고용보험') NOT NULL,
  rate_employee   DECIMAL(6,4) NOT NULL,   -- 근로자 부담률(%)
  effective_from  DATE NOT NULL,
  PRIMARY KEY (year, insurance_type)
);

-- 12. 급여 회차 (매월 1회 생성)
CREATE TABLE payroll_runs (
  run_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
  year_month    CHAR(7) NOT NULL UNIQUE,
  status        ENUM('작성중','확정','지급완료') NOT NULL DEFAULT '작성중',
  created_by    BIGINT NULL,
  confirmed_at  TIMESTAMP NULL
);

-- 13. 급여 상세 (원본 엑셀의 직원별 1행에 대응 — 엑셀형/카드형 화면이 다루는 데이터)
CREATE TABLE payroll_details (
  detail_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
  run_id           BIGINT NOT NULL,
  emp_id           BIGINT NOT NULL,
  -- 기본급여 (연봉계약 스냅샷)
  base_salary      DECIMAL(12,0) NOT NULL,
  job_allowance    DECIMAL(12,0) NOT NULL DEFAULT 0,
  -- 근태 연동 입력값 (attendance_monthly_summary에서 자동 반영, 수정 가능)
  retention_allow  DECIMAL(12,0) NOT NULL DEFAULT 0,
  sat_allow        DECIMAL(12,0) NOT NULL DEFAULT 0,
  etc_allow        DECIMAL(12,0) NOT NULL DEFAULT 0,
  ot_pay           DECIMAL(12,0) NOT NULL DEFAULT 0,
  holiday_hours    DECIMAL(6,1) NOT NULL DEFAULT 0,
  deduct_hours     DECIMAL(6,1) NOT NULL DEFAULT 0,
  -- 상여 · 기타지급
  bonus_cash       DECIMAL(12,0) NOT NULL DEFAULT 0,
  bonus_kind       DECIMAL(12,0) NOT NULL DEFAULT 0,
  tuition          DECIMAL(12,0) NOT NULL DEFAULT 0,
  annual_leave_pay DECIMAL(12,0) NOT NULL DEFAULT 0,
  -- 공제 입력값
  year_end_tax     DECIMAL(12,0) NOT NULL DEFAULT 0,
  club_fee         DECIMAL(12,0) NOT NULL DEFAULT 0,
  advance          DECIMAL(12,0) NOT NULL DEFAULT 0,
  advance_meal     DECIMAL(12,0) NOT NULL DEFAULT 0,
  income_tax       DECIMAL(12,0) NOT NULL DEFAULT 0,
  pension          DECIMAL(12,0) NOT NULL DEFAULT 0,
  health_ins       DECIMAL(12,0) NOT NULL DEFAULT 0,
  ltc_ins          DECIMAL(12,0) NOT NULL DEFAULT 0,
  -- 계산값 스냅샷 (확정 시점에 저장 — 감사/이력용, 원본 수식 그대로)
  hourly_wage      DECIMAL(12,2) NULL,
  gross_pay        DECIMAL(12,0) NULL,
  total_deduct     DECIMAL(12,0) NULL,
  net_pay          DECIMAL(12,0) NULL,
  hourly_check     DECIMAL(12,2) NULL,
  wage_check       DECIMAL(12,0) NULL,
  UNIQUE KEY uq_run_emp (run_id, emp_id),
  FOREIGN KEY (run_id) REFERENCES payroll_runs(run_id),
  FOREIGN KEY (emp_id) REFERENCES employees(emp_id)
);
