USE EndlessSurvivorDB;
GO

/* =================================================================================
   1. NẠP ĐƯỜNG CONG EXP ĐẾN LEVEL 300 & THƯỞNG MỐC PHÒNG BOSS MỖI 20 LEVEL
   Công thức Mục 2.2: EXP(L) = FLOOR((8 + 6*L + 1.6 * L^1.75) * 4)
   ================================================================================= */
DELETE FROM ExpLevelCurves;

DECLARE @L INT = 1;
WHILE @L <= 300
BEGIN
    INSERT INTO ExpLevelCurves (InRunLevel, RequiredExp, BaseGoldReward)
    VALUES (
        @L,
        CAST(FLOOR((8.0 + (6.0 * @L) + (1.6 * POWER(CAST(@L AS FLOAT), 1.75))) * 4.0) AS INT),
        -- Cứ mỗi 20 Level (vào Phòng Boss) thưởng lớn (Level * 25 Vàng), mỗi 5 Level thưởng nhỏ
        CASE 
            WHEN @L % 20 = 0 THEN (@L * 25)
            WHEN @L % 5 = 0  THEN (@L * 5)
            ELSE 0 
        END
    );
    SET @L = @L + 1;
END
GO

/* =================================================================================
   2. BỔ SUNG MINI-BOSS (MỖI 5 PHÚT), BOSS PHÒNG 20 LV & FINAL BOSS (PHÚT 30)
   ================================================================================= */

-- 2.1. Thêm 3 Mini-Boss (để random mỗi 5 phút), 1 Boss Phòng 20Lv và 1 Final Boss Phút 30
IF NOT EXISTS (SELECT 1 FROM Enemies WHERE EnemyCode = 'DEATH_KNIGHT_MINIBOSS')
BEGIN
    INSERT INTO Enemies (EnemyCode, EnemyName, EnemyTier, AIBehavior, BaseHP, BaseDamage, MoveSpeed, PreferredRangePx, HitboxRadius, KnockbackResist, StunImmunity, SpriteKey) VALUES
    -- 3 Mini-Boss xuất hiện ngẫu nhiên mỗi 5 phút
    ('DEATH_KNIGHT_MINIBOSS', N'Kỵ Sĩ Tử Thần (Mini-Boss)',    'MINI_BOSS', 'CHARGE',       1200, 25, 80,   0, 24, 0.80, 0, 'miniboss_death_knight'),
    ('LICH_PRIEST_MINIBOSS',  N'Tư Tế Hắc Ám (Mini-Boss)',     'MINI_BOSS', 'RANGED_KITE',   950, 28, 65, 250, 22, 0.75, 0, 'miniboss_lich_priest'),
    ('GARGOYLE_MINIBOSS',     N'Quỷ Đá Cổ Đại (Mini-Boss)',    'MINI_BOSS', 'SEEK',         1500, 22, 70,   0, 26, 0.85, 1, 'miniboss_gargoyle'),
    -- Boss canh giữ Phòng Boss (Mỗi 20 Level)
    ('BLOOD_REAPER_BOSS',     N'Thần Gặt Huyết Ngục (Boss)',   'BOSS',      'BOSS_PATTERN', 5000, 42, 82,   0, 38, 0.95, 1, 'boss_blood_reaper'),
    -- Final Boss ở Phút 30 (Triệu hồi các Boss khác trong game)
    ('VOID_OVERLORD_FINAL',   N'Chúa Tể Hư Không (Final Boss)','BOSS',      'BOSS_PATTERN',25000, 65, 88,   0, 48, 1.00, 1, 'boss_void_overlord');
END
GO

-- 2.2. Cấu hình Giai đoạn (BossPhases) và Chiêu thức Triệu hồi Boss cho Final Boss
DECLARE @SkeletonBossId INT  = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'SKELETON_LORD_BOSS');
DECLARE @ReaperBossId INT    = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'BLOOD_REAPER_BOSS');
DECLARE @DeathKnightId INT   = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'DEATH_KNIGHT_MINIBOSS');
DECLARE @FinalBossId INT     = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'VOID_OVERLORD_FINAL');

-- Xóa cấu hình phase cũ của Reaper và Final Boss nếu chạy lại script
DELETE FROM BossPhases WHERE BossEnemyId IN (@ReaperBossId, @FinalBossId);

-- Phases cho Boss Phòng 20 Level (BLOOD_REAPER_BOSS)
INSERT INTO BossPhases (BossEnemyId, PhaseNo, TriggerHpPercent, SpeedMultiplier, DamageMultiplier, EnrageVfxKey) VALUES
(@ReaperBossId, 1, 100.00, 1.00, 1.00, NULL),
(@ReaperBossId, 2,  50.00, 1.30, 1.40, 'vfx_reaper_blood_aura');

-- 3 Phases cho Final Boss Phút 30 (VOID_OVERLORD_FINAL)
INSERT INTO BossPhases (BossEnemyId, PhaseNo, TriggerHpPercent, SpeedMultiplier, DamageMultiplier, EnrageVfxKey) VALUES
(@FinalBossId, 1, 100.00, 1.00, 1.00, 'vfx_void_aura_phase1'),
(@FinalBossId, 2,  70.00, 1.25, 1.35, 'vfx_void_aura_phase2'),
(@FinalBossId, 3,  35.00, 1.50, 1.80, 'vfx_void_enrage_max');

DECLARE @FinalPhase1Id INT = (SELECT PhaseId FROM BossPhases WHERE BossEnemyId = @FinalBossId AND PhaseNo = 1);
DECLARE @FinalPhase2Id INT = (SELECT PhaseId FROM BossPhases WHERE BossEnemyId = @FinalBossId AND PhaseNo = 2);
DECLARE @FinalPhase3Id INT = (SELECT PhaseId FROM BossPhases WHERE BossEnemyId = @FinalBossId AND PhaseNo = 3);

-- Chiêu thức của Final Boss: Triệu hồi trực tiếp Mini-Boss và các Boss trong game để vây đánh người chơi
INSERT INTO BossAttackPatterns (PhaseId, PatternCode, TelegraphDurationMs, CooldownMs, DamageMultiplier, SummonEnemyId, SummonCount) VALUES
(@FinalPhase1Id, 'RADIAL_BULLET_HELL', 1000,  5000, 1.50, NULL,            0),
(@FinalPhase1Id, 'SUMMON_MINIBOSS',    1500, 15000, 1.00, @DeathKnightId,  2), -- Phase 1: Gọi 2 Kỵ Sĩ Tử Thần (Mini-Boss)
(@FinalPhase2Id, 'SUMMON_BOSS_WAVE',   2000, 20000, 1.20, @SkeletonBossId, 1), -- Phase 2: Gọi Lãnh Chúa Xương Khô (Boss)
(@FinalPhase3Id, 'VOID_COLLAPSE_AOE',  1200,  4000, 2.20, NULL,            0),
(@FinalPhase3Id, 'SUMMON_DUAL_BOSSES', 2000, 18000, 1.50, @ReaperBossId,   2); -- Phase 3: Gọi 2 Thần Gặt Huyết Ngục (Boss)
GO

/* =================================================================================
   3. KỊCH BẢN WAVE QUÁI 30+ PHÚT & SỰ KIỆN PHÒNG BOSS (STAGEWAVES & STAGEEVENTS)
   ================================================================================= */
DELETE FROM StageWaves WHERE StageId = 1;

DECLARE @DeathKnightId INT = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'DEATH_KNIGHT_MINIBOSS');
DECLARE @LichPriestId INT  = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'LICH_PRIEST_MINIBOSS');
DECLARE @GargoyleId INT    = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'GARGOYLE_MINIBOSS');
DECLARE @FinalBossId INT   = (SELECT EnemyId FROM Enemies WHERE EnemyCode = 'VOID_OVERLORD_FINAL');

INSERT INTO StageWaves (StageId, StartMinute, EndMinute, EnemyId, SpawnIntervalMs, MinGroupSize, MaxActiveByType, HpScaleMultiplier) VALUES
-- Quái thường & Elite rải từ phút 0 đến phút 30
(1, 0,  10, 1, 1000, 3, 120, 1.00), -- Phút 0-10: Slime Xanh
(1, 3,  15, 2, 1200, 3, 150, 1.35), -- Phút 3-15: Bộ Xương Cầm Kiếm
(1, 8,  25, 3, 1500, 2, 100, 1.75), -- Phút 8-25: Bộ Xương Bắn Cung
(1, 12, 30, 4, 12000,1, 10,  2.50), -- Phút 12-30: Vua Slime Khổng Lồ (Elite)
-- Cứ mỗi 5 phút (Phút 5, 10, 15, 20, 25) sinh ngẫu nhiên Mini-Boss (Frontend random từ các dòng MINI_BOSS này)
(1, 5,  30, @DeathKnightId, 300000, 1, 2, 1.50),
(1, 5,  30, @LichPriestId,  300000, 1, 2, 1.50),
(1, 5,  30, @GargoyleId,    300000, 1, 2, 1.50),
-- Phút 30 -> Vô tận (999): Phòng Final Boss (Sinh tồn càng lâu điểm càng cao)
(1, 30, 999,@FinalBossId,   999999, 1, 1, 1.00);
GO

-- Cấu hình Sự kiện đặc biệt trong bảng StageEvents (Mỗi 20 Lv, Mỗi 5 Phút và Phút 30)
DELETE FROM StageEvents WHERE StageId = 1;
INSERT INTO StageEvents (StageId, EventCode, StartAtSec, DurationSec, RewardMultiplier, WarningMessage) VALUES
(1, 'RANDOM_MINIBOSS_5M',  300,  300,  1.25, N'Cảnh báo: Mini-Boss ngẫu nhiên xuất hiện mỗi 5 phút!'),
(1, 'BOSS_ROOM_EVERY_20LV',  0,  180,  2.00, N'Đạt mốc 20 Cấp độ: Cổng dịch chuyển vào Phòng Boss đã mở!'),
(1, 'FINAL_BOSS_ROOM_30M',1800, 99999, 3.00, N'PHÚT 30: Chạm trán Final Boss! Hãy sống sót trước quân đoàn Boss càng lâu càng tốt!');
GO

/* =================================================================================
   4. THÔNG SỐ CẤP ĐỘ KỸ NĂNG (SKILLLEVELS) & BỂ GACHA (GACHAPOOLITEMS)
   ================================================================================= */
DELETE FROM SkillLevels;
INSERT INTO SkillLevels (SkillId, LevelNum, BaseDamage, SkillMultiplier, CooldownMs, ProjectileCount, PierceCount, BounceCount, AreaScale, KnockbackForce, LevelDesc) VALUES
(1, 1, 25, 1.00, 1400, 1, 99, 0, 1.00, 15, N'Chém vòng cung phía trước'),
(1, 2, 35, 1.10, 1300, 1, 99, 0, 1.15, 15, N'+10 Sát thương, +15% Phạm vi'),
(1, 3, 45, 1.20, 1200, 2, 99, 0, 1.15, 20, N'+1 Đòn chém phía sau lưng'),
(1, 4, 60, 1.35, 1100, 2, 99, 0, 1.30, 20, N'+15 Sát thương, +15% Phạm vi'),
(1, 5, 80, 1.50, 950,  2, 99, 0, 1.50, 25, N'Tối đa hóa sát thương và tốc độ chém'),
(2, 1, 18, 1.00, 1000, 1, 1,  0, 1.00, 8,  N'Bắn 1 mũi tên vào kẻ địch gần nhất'),
(2, 2, 24, 1.10, 950,  2, 1,  0, 1.00, 8,  N'+1 Mũi tên'),
(2, 3, 30, 1.20, 900,  2, 2,  0, 1.00, 10, N'Xuyên thêm 1 mục tiêu'),
(2, 4, 38, 1.30, 850,  3, 2,  0, 1.00, 10, N'+1 Mũi tên, giảm hồi chiêu'),
(2, 5, 50, 1.45, 750,  4, 3,  0, 1.00, 12, N'Bắn 4 mũi tên xuyên 3 mục tiêu'),
(3, 1, 35, 1.10, 1800, 1, 1,  0, 1.00, 12, N'Bắn cầu lửa phát nổ diện nhỏ'),
(3, 2, 48, 1.20, 1700, 1, 1,  0, 1.25, 12, N'+25% Bán kính vụ nổ'),
(3, 3, 62, 1.35, 1550, 2, 1,  0, 1.25, 15, N'+1 Cầu lửa'),
(3, 4, 80, 1.50, 1400, 2, 1,  0, 1.50, 15, N'+25% Bán kính vụ nổ, giảm hồi chiêu'),
(3, 5, 105,1.70, 1200, 3, 1,  0, 1.75, 20, N'Bắn 3 cầu lửa đại diện rộng'),
(4, 1, 120,1.80, 600,  1, 999,0, 2.00, 30, N'[Tiến Hóa Lv6] Huyết Kiếm Xoáy'),
(5, 1, 75, 1.60, 400,  6, 5,  2, 1.20, 15, N'[Tiến Hóa Lv6] Mưa Tên Bão Tố'),
(6, 1, 220,2.20, 900,  4, 999,0, 2.50, 35, N'[Tiến Hóa Lv6] Thiên Thạch Dung Nham');

DELETE FROM GachaPoolItems;
INSERT INTO GachaPoolItems (BannerId, ItemCategory, EquipmentTemplateId, RarityTier, DropWeight, IsRateUp) VALUES
(1, 'EQUIPMENT', 5, 6, 20,   1),
(1, 'EQUIPMENT', 7, 6, 20,   0),
(1, 'EQUIPMENT', 6, 5, 130,  1),
(2, 'EQUIPMENT', 2, 6, 20,   1),
(2, 'EQUIPMENT', 1, 1, 5000, 0),
(2, 'EQUIPMENT', 3, 1, 3000, 0),
(2, 'EQUIPMENT', 4, 1, 1400, 0);
GO

/* =================================================================================
   5. CẬP NHẬT SP_FINISHRUN: TRẦN LEVEL 300, CHỈ KẾT THÚC KHI CHẾT & ĐIỂM FINAL BOSS
   ================================================================================= */
CREATE OR ALTER PROCEDURE sp_FinishRun
    @RunId BIGINT,
    @UserId INT,
    @RequestId VARCHAR(64),
    @EndState VARCHAR(20),            -- Game chỉ kết thúc thật sự khi 'DEAD' (hoặc 'QUIT'/'DISCONNECTED')
    @SurvivalTimeSec INT,
    @WavesCleared INT,
    @LevelReached INT,                -- Giới hạn tối đa Level 300
    @TotalKills INT,
    @BossesKilled INT,
    @TotalDamageDealt BIGINT,
    @GoldEarned INT,
    @SkillsJson NVARCHAR(MAX) = NULL,
    @PassivesJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @CurrentState VARCHAR(20), @StageId INT, @HeroId INT, @GameMode VARCHAR(15), @StartedAt DATETIME2;

        SELECT @CurrentState = RunState, @StageId = StageId, @HeroId = HeroId, @GameMode = GameMode, @StartedAt = StartedAt
        FROM GameRuns WITH (UPDLOCK)
        WHERE RunId = @RunId AND UserId = @UserId;

        IF @CurrentState IS NULL
            THROW 50102, N'Phiên trận đấu không tồn tại!', 1;

        IF @CurrentState <> 'IN_PROGRESS'
            THROW 50103, N'Trận đấu này đã được tổng kết trước đó!', 1;

        -- Khóa trần Level 300: Nếu Client gửi Level > 300 thì gắn cờ gian lận
        DECLARE @RealElapsedSec INT = DATEDIFF(SECOND, @StartedAt, GETDATE());
        DECLARE @IsValid BIT = 1, @CappedGold INT = @GoldEarned, @CappedLevel INT = @LevelReached;

        IF (@LevelReached > 300) OR (@SurvivalTimeSec > @RealElapsedSec + 120) OR (@TotalKills > @SurvivalTimeSec * 50)
        BEGIN
            SET @IsValid = 0;
            SET @CappedLevel = CASE WHEN @LevelReached > 300 THEN 300 ELSE @LevelReached END;
            INSERT INTO AuditLogs (UserId, ActionType, Severity, PayloadJson)
            VALUES (@User