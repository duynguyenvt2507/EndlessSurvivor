/* =================================================================================
   PROJECT: ENDLESS SURVIVOR - 2D WEB SURVIVAL GAME
   DATABASE ENGINE: MICROSOFT SQL SERVER (T-SQL)
   ARCHITECTURE: FULL PRODUCTION & ANTI-CHEAT READY SCHEMA
   ================================================================================= */

USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = N'EndlessSurvivorDB')
BEGIN
    ALTER DATABASE EndlessSurvivorDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE EndlessSurvivorDB;
END
GO

CREATE DATABASE EndlessSurvivorDB;
GO

USE EndlessSurvivorDB;
GO

/* =================================================================================
   MODULE 1: VẬN HÀNH, PHIÊN BẢN CÂN BẰNG & CẤU HÌNH CỐT LÕI (OPS & CORE BALANCE)
   ================================================================================= */

-- 1. Phiên bản cân bằng game (Đảm bảo tính toàn vẹn khi đối chiếu Run & Leaderboard)
CREATE TABLE GameBalanceVersions (
    VersionId INT IDENTITY(1,1) PRIMARY KEY,
    VersionCode VARCHAR(20) UNIQUE NOT NULL,     -- VD: 'v1.0.0-MVP', 'v1.1.0-BETA'
    ConfigHash VARCHAR(64) NOT NULL,             -- Mã băm kiểm tra thông số Client/Server
    MaxActiveSkillSlots TINYINT NOT NULL DEFAULT 6,
    MaxPassiveItemSlots TINYINT NOT NULL DEFAULT 6,
    CritDamageMultiplier DECIMAL(4,2) NOT NULL DEFAULT 1.50,
    MaxCooldownReductionCap DECIMAL(5,2) NOT NULL DEFAULT 60.00, -- Cap tối đa 60% CDR
    MaxDamageReductionCap DECIMAL(5,2) NOT NULL DEFAULT 75.00,   -- Cap tối đa 75% Armor DR
    MaxCritRateCap DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    IsActive BIT NOT NULL DEFAULT 1,
    ReleasedAt DATETIME2 DEFAULT GETDATE()
);

-- 2. Đường cong EXP lên cấp trong trận (EXP Level Curve)
CREATE TABLE ExpLevelCurves (
    InRunLevel INT PRIMARY KEY,                  -- Level 1 -> 100+
    RequiredExp INT NOT NULL,                    -- EXP cần để lên cấp tiếp theo
    BaseGoldReward INT NOT NULL DEFAULT 0        -- Thưởng vàng khi đạt mốc cấp độ hoặc khi đã max build
);

-- 3. Hệ thống Hiệu ứng Trạng thái (Status Effects: BURN, POISON, SLOW, STUN, FREEZE, BLEED, SHIELD)
CREATE TABLE StatusEffects (
    EffectCode VARCHAR(20) PRIMARY KEY,
    EffectName NVARCHAR(50) NOT NULL,
    BaseDurationMs INT NOT NULL DEFAULT 3000,
    TickIntervalMs INT NULL,                     -- Mili-giây mỗi lần nhảy sát thương (DoT)
    MaxStacks TINYINT NOT NULL DEFAULT 1,
    StackRule VARCHAR(20) NOT NULL DEFAULT 'REFRESH', -- 'REFRESH', 'ADD_STACK', 'INDEPENDENT'
    AffectsBoss BIT NOT NULL DEFAULT 1           -- Boss có thể miễn nhiễm STUN/FREEZE nhưng dính BURN/POISON
);

-- 4. Bảng 6 Bậc Phẩm Chất (Trắng -> Lục -> Lam -> Tím -> Cam -> Đỏ)
CREATE TABLE Rarities (
    RarityTier INT PRIMARY KEY,                  -- 1: WHITE, 2: GREEN, 3: BLUE, 4: PURPLE, 5: ORANGE, 6: RED
    RarityCode VARCHAR(15) UNIQUE NOT NULL,
    RarityName NVARCHAR(50) NOT NULL,
    ColorHex VARCHAR(10) NOT NULL,
    StatMultiplier DECIMAL(4,2) NOT NULL,
    MaxEnhanceLevel INT NOT NULL,
    BaseGachaWeight INT NOT NULL
);

/* =================================================================================
   MODULE 2: TÀI KHOẢN, HỒ SƠ, CÀI ĐẶT & VÍ TIỀN TỆ (ACCOUNT, PROFILE & WALLET LEDGER)
   ================================================================================= */

-- 5. Tài khoản người chơi
CREATE TABLE Users (
    UserId INT IDENTITY(1,1) PRIMARY KEY,
    Username VARCHAR(50) UNIQUE NOT NULL,
    Email VARCHAR(100) UNIQUE NULL,              -- NULL nếu là Guest Account chưa liên kết
    PasswordHash VARCHAR(255) NULL,
    AccountType VARCHAR(15) NOT NULL DEFAULT 'REGISTERED', -- 'GUEST', 'REGISTERED', 'ADMIN'
    AccountStatus VARCHAR(15) NOT NULL DEFAULT 'ACTIVE',   -- 'ACTIVE', 'SUSPENDED', 'BANNED'
    FailedLoginAttempts TINYINT NOT NULL DEFAULT 0,
    LastLoginAt DATETIME2 NULL,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT CK_AccountStatus CHECK (AccountStatus IN ('ACTIVE', 'SUSPENDED', 'BANNED'))
);

-- 6. Hồ sơ cá nhân & Thống kê tổng
CREATE TABLE UserProfiles (
    UserId INT PRIMARY KEY FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    DisplayName NVARCHAR(50) NOT NULL,
    AvatarKey VARCHAR(50) NOT NULL DEFAULT 'avatar_default',
    TotalRuns INT NOT NULL DEFAULT 0,
    TotalKills BIGINT NOT NULL DEFAULT 0,
    TotalBossKills INT NOT NULL DEFAULT 0,
    BestSurvivalTimeSec INT NOT NULL DEFAULT 0,
    IsPublicBuildAllowed BIT NOT NULL DEFAULT 1, -- Quyền riêng tư: Cho phép người khác xem Build trên BXH
    TutorialCompleted BIT NOT NULL DEFAULT 0,
    UpdatedAt DATETIME2 DEFAULT GETDATE()
);

-- 7. Cài đặt người chơi (UI/UX & Khả năng tiếp cận)
CREATE TABLE UserSettings (
    UserId INT PRIMARY KEY FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    BgmVolume TINYINT NOT NULL DEFAULT 80,
    SfxVolume TINYINT NOT NULL DEFAULT 100,
    ShowDamageNumbers BIT NOT NULL DEFAULT 1,
    ScreenShakeEnabled BIT NOT NULL DEFAULT 1,
    AutoAimEnabled BIT NOT NULL DEFAULT 1,
    FpsLimit SMALLINT NOT NULL DEFAULT 60,
    ColorblindMode VARCHAR(20) NOT NULL DEFAULT 'NONE', -- 'NONE', 'PROTANOPIA', 'DEUTERANOPIA', 'TRITANOPIA'
    LowVfxQuality BIT NOT NULL DEFAULT 0,               -- Giảm hiệu ứng đạn/hạt trên máy yếu
    KeybindingsJson NVARCHAR(500) NULL
);

-- 8. Ví tiền tệ người chơi (Tách theo loại tiền để khóa dòng an toàn)
CREATE TABLE UserWallets (
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    CurrencyType VARCHAR(20) NOT NULL,           -- 'GOLD', 'GEMS', 'EQUIP_TICKET', 'SKIN_TICKET', 'ENHANCE_STONE'
    Balance BIGINT NOT NULL DEFAULT 0,
    TotalEarned BIGINT NOT NULL DEFAULT 0,
    TotalSpent BIGINT NOT NULL DEFAULT 0,
    UpdatedAt DATETIME2 DEFAULT GETDATE(),
    PRIMARY KEY (UserId, CurrencyType),
    CONSTRAINT CK_WalletBalance_NonNegative CHECK (Balance >= 0),
    CONSTRAINT CK_CurrencyType CHECK (CurrencyType IN ('GOLD', 'GEMS', 'EQUIP_TICKET', 'SKIN_TICKET', 'ENHANCE_STONE'))
);

-- 9. Sổ cái biến động tiền tệ (Chống nhân đôi giao dịch bằng RequestId)
CREATE TABLE CurrencyTransactions (
    TransactionId BIGINT IDENTITY(1,1) PRIMARY KEY,
    RequestId VARCHAR(64) UNIQUE NOT NULL,       -- Idempotency Key từ Client/Backend
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId),
    CurrencyType VARCHAR(20) NOT NULL,
    AmountChange BIGINT NOT NULL,                -- Dương (+) là cộng, Âm (-) là trừ
    BalanceAfter BIGINT NOT NULL,
    ReasonCode VARCHAR(30) NOT NULL,             -- 'RUN_REWARD', 'HERO_UPGRADE', 'EQUIP_ENHANCE', 'GACHA_ROLL', 'QUEST_CLAIM', 'SHOP_BUY'
    ReferenceId VARCHAR(64) NULL,                -- RunId, BannerId, QuestId...
    CreatedAt DATETIME2 DEFAULT GETDATE()
);

-- 10. Nhật ký kiểm toán hệ thống (Audit Logs cho Admin & Anti-cheat)
CREATE TABLE AuditLogs (
    AuditId BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserId INT NULL FOREIGN KEY REFERENCES Users(UserId),
    ActionType VARCHAR(40) NOT NULL,             -- 'SUSPICIOUS_RUN', 'GACHA_PITY_RESET', 'ADMIN_GRANT'
    Severity VARCHAR(15) NOT NULL DEFAULT 'INFO',-- 'INFO', 'WARNING', 'CRITICAL'
    PayloadJson NVARCHAR(MAX) NULL,
    IpAddress VARCHAR(45) NULL,
    CreatedAt DATETIME2 DEFAULT GETDATE()
);
GO

/* =================================================================================
   MODULE 3: KỸ NĂNG CHIẾN ĐẤU, BỊ ĐỘNG & CÔNG THỨC TIẾN HÓA (SKILLS & EVOLUTIONS)
   ================================================================================= */

-- 11. Trang bị Bị động trong trận (6 Passive Slots)
CREATE TABLE PassiveItems (
    PassiveId INT IDENTITY(1,1) PRIMARY KEY,
    PassiveCode VARCHAR(30) UNIQUE NOT NULL,
    PassiveName NVARCHAR(100) NOT NULL,
    StatTarget VARCHAR(30) NOT NULL,             -- 'MIGHT', 'COOLDOWN', 'PROJ_SPEED', 'MOVE_SPEED', 'MAX_HP', 'MAGNET', 'ARMOR', 'CRIT'
    BonusPerLevel DECIMAL(6,2) NOT NULL,
    MaxLevel TINYINT NOT NULL DEFAULT 5,
    SpriteKey VARCHAR(50) NOT NULL
);

-- 12. Kỹ năng Chủ động trong trận (6 Active Slots & Liên kết Tiến Hóa rõ ràng)
CREATE TABLE Skills (
    SkillId INT IDENTITY(1,1) PRIMARY KEY,
    SkillCode VARCHAR(30) UNIQUE NOT NULL,
    SkillName NVARCHAR(100) NOT NULL,
    ClassTag VARCHAR(20) NOT NULL DEFAULT 'ANY', -- 'WARRIOR', 'ARCHER', 'MAGE', 'ANY'
    AttackPattern VARCHAR(20) NOT NULL,          -- 'PROJECTILE', 'MELEE', 'AREA', 'ORBITAL', 'CHAIN', 'SUMMON', 'BEAM'
    TargetingStrategy VARCHAR(20) NOT NULL DEFAULT 'NEAREST', -- 'NEAREST', 'FACING', 'RANDOM', 'SELF_AURA', 'HIGHEST_HP'
    MaxLevel TINYINT NOT NULL DEFAULT 5,
    IsEvolvedForm BIT NOT NULL DEFAULT 0,        -- 0 = Kỹ năng gốc (Lv 1-5), 1 = Kỹ năng Tiến hóa (Lv 6)
    EvolutionFromSkillId INT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    EvolutionToSkillId INT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    RequiredPassiveId INT NULL FOREIGN KEY REFERENCES PassiveItems(PassiveId),
    AppliedEffectCode VARCHAR(20) NULL FOREIGN KEY REFERENCES StatusEffects(EffectCode),
    EffectChance DECIMAL(4,2) NOT NULL DEFAULT 0.00,
    MaxHitsPerTargetPerSec TINYINT NOT NULL DEFAULT 3, -- Giới hạn số lần trúng 1 mục tiêu/giây
    SpriteKey VARCHAR(50) NOT NULL
);

-- 13. Thông số Kỹ năng theo từng cấp độ
CREATE TABLE SkillLevels (
    SkillLevelId INT IDENTITY(1,1) PRIMARY KEY,
    SkillId INT NOT NULL FOREIGN KEY REFERENCES Skills(SkillId) ON DELETE CASCADE,
    LevelNum TINYINT NOT NULL,                   -- 1..5 (hoặc 1 cho kỹ năng đã Tiến hóa)
    BaseDamage INT NOT NULL,
    SkillMultiplier DECIMAL(5,2) NOT NULL DEFAULT 1.00,
    CooldownMs INT NOT NULL,
    ProjectileCount TINYINT NOT NULL DEFAULT 1,
    PierceCount SMALLINT NOT NULL DEFAULT 1,
    BounceCount TINYINT NOT NULL DEFAULT 0,
    AreaScale DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    KnockbackForce INT NOT NULL DEFAULT 10,
    LevelDesc NVARCHAR(255) NULL,
    CONSTRAINT UQ_SkillLevels UNIQUE (SkillId, LevelNum)
);
GO

/* =================================================================================
   MODULE 4: NHÂN VẬT, SKIN, 15 Ô NÂNG CẤP & BAN/PICK (HEROES & META UPGRADES)
   ================================================================================= */

-- 14. Danh mục Nhân vật (Warrior, Archer, Mage...)
CREATE TABLE Heroes (
    HeroId INT IDENTITY(1,1) PRIMARY KEY,
    HeroCode VARCHAR(30) UNIQUE NOT NULL,
    HeroName NVARCHAR(100) NOT NULL,
    ClassRole NVARCHAR(50) NOT NULL,
    DefaultStartingSkillId INT NOT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    BaseHP INT NOT NULL DEFAULT 100,
    BaseArmor DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    BaseMoveSpeed INT NOT NULL DEFAULT 100,
    BaseMight DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    BaseCritRate DECIMAL(5,2) NOT NULL DEFAULT 5.00, -- Đơn vị % (5.00 = 5%)
    PickupRadius INT NOT NULL DEFAULT 60,
    HitboxRadius INT NOT NULL DEFAULT 12,
    IFrameDurationMs INT NOT NULL DEFAULT 300,       -- Thời gian bất tử ngắn sau khi nhận sát thương
    UnlockCostGold INT NOT NULL DEFAULT 0,
    SpriteKey VARCHAR(50) NOT NULL,
    PassiveDesc NVARCHAR(255) NULL
);

-- 15. Danh mục Skin Nhân vật (Tách rời trang bị 5 ô)
CREATE TABLE HeroSkins (
    SkinId INT IDENTITY(1,1) PRIMARY KEY,
    HeroId INT NOT NULL FOREIGN KEY REFERENCES Heroes(HeroId) ON DELETE CASCADE,
    SkinCode VARCHAR(40) UNIQUE NOT NULL,
    SkinName NVARCHAR(100) NOT NULL,
    RarityTier INT NOT NULL FOREIGN KEY REFERENCES Rarities(RarityTier),
    SpriteKey VARCHAR(50) NOT NULL,
    SkillEffectPrefix VARCHAR(30) NULL,
    BonusHpPercent DECIMAL(4,2) NOT NULL DEFAULT 0.00,
    BonusAtkPercent DECIMAL(4,2) NOT NULL DEFAULT 0.00,
    IsAvailableInGacha BIT NOT NULL DEFAULT 0
);

-- 16. Cấu hình 15 Ô Nâng Cấp & Ban/Pick theo Hero (10 Chỉ số + 2 Tiện ích + 3 Ban/Pick)
CREATE TABLE HeroUpgradeConfigs (
    UpgradeCode VARCHAR(30) PRIMARY KEY,
    UpgradeCategory VARCHAR(20) NOT NULL,        -- 'STAT' (10 ô), 'UTILITY' (2 ô), 'BAN_PICK' (3 ô)
    UpgradeName NVARCHAR(100) NOT NULL,
    MaxLevel INT NOT NULL,
    BonusPerLevel DECIMAL(6,2) NOT NULL,
    StatUnit VARCHAR(20) NOT NULL,               -- 'FLAT_HP', 'PERCENT', 'HP_PER_SEC', 'SLOT_COUNT', 'UNLOCK'
    HardCapValue DECIMAL(6,2) NULL,              -- Trần tối đa của chỉ số từ nhánh nâng cấp này
    BaseGoldCost INT NOT NULL DEFAULT 100,
    CostScale DECIMAL(4,2) NOT NULL DEFAULT 1.35,
    Description NVARCHAR(255) NOT NULL,
    IconKey VARCHAR(50) NOT NULL
);

-- 17. Nhân vật người chơi sở hữu (Có HeroInstanceId riêng theo mục 6.1)
CREATE TABLE UserHeroes (
    HeroInstanceId BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    HeroId INT NOT NULL FOREIGN KEY REFERENCES Heroes(HeroId),
    HeroRank INT NOT NULL DEFAULT 1,
    ActiveSkinId INT NULL FOREIGN KEY REFERENCES HeroSkins(SkinId),
    PickedStartingSkill1Id INT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    PickedStartingSkill2Id INT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    UnlockedAt DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT UQ_User_Hero UNIQUE (UserId, HeroId)
);

-- 18. Cấp độ 15 Ô Nâng cấp của từng Nhân vật
CREATE TABLE UserHeroUpgradeLevels (
    HeroInstanceId BIGINT NOT NULL FOREIGN KEY REFERENCES UserHeroes(HeroInstanceId) ON DELETE CASCADE,
    UpgradeCode VARCHAR(30) NOT NULL FOREIGN KEY REFERENCES HeroUpgradeConfigs(UpgradeCode),
    CurrentLevel INT NOT NULL DEFAULT 0,
    PRIMARY KEY (HeroInstanceId, UpgradeCode)
);

-- 19. Danh sách Kỹ năng bị Cấm (Ban List: Tối đa 3 slot mỗi Hero)
CREATE TABLE UserHeroBannedSkills (
    HeroInstanceId BIGINT NOT NULL FOREIGN KEY REFERENCES UserHeroes(HeroInstanceId) ON DELETE CASCADE,
    SlotNumber TINYINT NOT NULL,                 -- 1, 2, 3
    BannedSkillId INT NOT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    PRIMARY KEY (HeroInstanceId, SlotNumber),
    CONSTRAINT CK_BanSlot_Range CHECK (SlotNumber BETWEEN 1 AND 3),
    CONSTRAINT UQ_Hero_BannedSkill UNIQUE (HeroInstanceId, BannedSkillId)
);

-- 20. Skin người chơi sở hữu
CREATE TABLE UserSkins (
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    SkinId INT NOT NULL FOREIGN KEY REFERENCES HeroSkins(SkinId),
    ObtainedAt DATETIME2 DEFAULT GETDATE(),
    PRIMARY KEY (UserId, SkinId)
);
GO

/* =================================================================================
   MODULE 5: TRANG BỊ 5 Ô, CƯỜNG HÓA & PHÂN RÃ (EQUIPMENT, ENHANCE & DISMANTLE)
   ================================================================================= */

-- 21. Mẫu Trang bị 5 Ô (HEAD, ARMOR, PANTS, BOOTS, WEAPON - Không đổi ngoại hình)
CREATE TABLE EquipmentTemplates (
    TemplateId INT IDENTITY(1,1) PRIMARY KEY,
    ItemCode VARCHAR(40) UNIQUE NOT NULL,
    ItemName NVARCHAR(100) NOT NULL,
    EquipSlot VARCHAR(15) NOT NULL,
    ClassRestriction VARCHAR(20) NOT NULL DEFAULT 'ANY', -- 'ANY', 'WARRIOR', 'ARCHER', 'MAGE'
    BaseRarityTier INT NOT NULL FOREIGN KEY REFERENCES Rarities(RarityTier),
    BaseHP INT NOT NULL DEFAULT 0,
    BaseATK INT NOT NULL DEFAULT 0,
    BaseArmor DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    BaseMoveSpeed INT NOT NULL DEFAULT 0,
    BaseCritRate DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    BaseCooldownRed DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    SpecialEffectDesc NVARCHAR(255) NULL,
    IconKey VARCHAR(50) NOT NULL,
    CONSTRAINT CK_EquipmentSlot CHECK (EquipSlot IN ('HEAD', 'ARMOR', 'PANTS', 'BOOTS', 'WEAPON'))
);

-- 22. Bảng chi phí Cường hóa & Tỉ lệ thành công (Không rớt cấp khi thất bại)
CREATE TABLE EquipmentEnhanceCosts (
    RarityTier INT NOT NULL FOREIGN KEY REFERENCES Rarities(RarityTier),
    TargetLevel INT NOT NULL,
    GoldCost INT NOT NULL,
    StoneCost INT NOT NULL DEFAULT 0,
    SuccessRate DECIMAL(5,2) NOT NULL DEFAULT 100.00, -- % thành công (100.00 = 100%)
    PRIMARY KEY (RarityTier, TargetLevel)
);

-- 23. Quy tắc Bán / Phân rã Trang bị (Dismantle Rules)
CREATE TABLE EquipmentDismantleRules (
    RarityTier INT PRIMARY KEY FOREIGN KEY REFERENCES Rarities(RarityTier),
    BaseGoldRefund INT NOT NULL,
    BaseStoneRefund INT NOT NULL,
    RefundEnhanceCostPercent DECIMAL(5,2) NOT NULL DEFAULT 80.00 -- Hoàn lại 80% tài nguyên đã cường hóa
);

-- 24. Kho Trang bị cá nhân (Inventory)
CREATE TABLE UserEquipments (
    UserEquipId BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    TemplateId INT NOT NULL FOREIGN KEY REFERENCES EquipmentTemplates(TemplateId),
    CurrentRarityTier INT NOT NULL FOREIGN KEY REFERENCES Rarities(RarityTier),
    EnhanceLevel INT NOT NULL DEFAULT 1,
    IsLocked BIT NOT NULL DEFAULT 0,
    ObtainedAt DATETIME2 DEFAULT GETDATE()
);

-- 25. Bảng 5 Ô Trang bị đang mặc của từng Nhân vật (Đảm bảo 1 món không mặc cho 2 Hero)
CREATE TABLE HeroEquippedItems (
    HeroInstanceId BIGINT NOT NULL FOREIGN KEY REFERENCES UserHeroes(HeroInstanceId) ON DELETE CASCADE,
    EquipSlot VARCHAR(15) NOT NULL,
    UserEquipId BIGINT NOT NULL UNIQUE FOREIGN KEY REFERENCES UserEquipments(UserEquipId),
    PRIMARY KEY (HeroInstanceId, EquipSlot),
    CONSTRAINT CK_HeroEquippedSlot CHECK (EquipSlot IN ('HEAD', 'ARMOR', 'PANTS', 'BOOTS', 'WEAPON'))
);
GO

/* =================================================================================
   MODULE 6: BẢN ĐỒ, QUÁI, BOSS PHASES, SỰ KIỆN & RƠI ĐỒ (WORLD, BOSS & DROPS)
   ================================================================================= */

-- 26. Cấu hình Bản đồ (MapConfigs / Stages)
CREATE TABLE Stages (
    StageId INT IDENTITY(1,1) PRIMARY KEY,
    StageCode VARCHAR(30) UNIQUE NOT NULL,
    StageName NVARCHAR(100) NOT NULL,
    TilemapKey VARCHAR(50) NOT NULL DEFAULT 'map_graveyard',
    MaxEnemiesGlobalCap INT NOT NULL DEFAULT 300, -- Giới hạn tổng quái trên màn hình chống lag
    DespawnDistancePx INT NOT NULL DEFAULT 1200,  -- Khoảng cách tự thu hồi/tái chế quái quá xa
    DifficultyMultiplier DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    EndlessHpGrowthPerMin DECIMAL(4,2) NOT NULL DEFAULT 1.25,
    EndlessDmgGrowthPerMin DECIMAL(4,2) NOT NULL DEFAULT 1.10,
    IsEndlessMode BIT NOT NULL DEFAULT 1
);

-- 27. Danh mục Quái vật & Boss
CREATE TABLE Enemies (
    EnemyId INT IDENTITY(1,1) PRIMARY KEY,
    EnemyCode VARCHAR(30) UNIQUE NOT NULL,
    EnemyName NVARCHAR(100) NOT NULL,
    EnemyTier VARCHAR(20) NOT NULL DEFAULT 'NORMAL', -- 'SWARM', 'NORMAL', 'ELITE', 'MINI_BOSS', 'BOSS'
    AIBehavior VARCHAR(20) NOT NULL DEFAULT 'SEEK',  -- 'SEEK', 'RANGED_KITE', 'CHARGE', 'BOSS_PATTERN'
    BaseHP INT NOT NULL,
    BaseDamage INT NOT NULL,
    MoveSpeed INT NOT NULL,
    PreferredRangePx INT NOT NULL DEFAULT 0,         -- Khoảng cách giữ vị trí của quái bắn xa
    HitboxRadius INT NOT NULL DEFAULT 14,
    KnockbackResist DECIMAL(3,2) NOT NULL DEFAULT 0.00,
    StunImmunity BIT NOT NULL DEFAULT 0,
    SpriteKey VARCHAR(50) NOT NULL
);

-- 28. Kịch bản Đợt quái theo phút (StageWaves)
CREATE TABLE StageWaves (
    WaveId INT IDENTITY(1,1) PRIMARY KEY,
    StageId INT NOT NULL FOREIGN KEY REFERENCES Stages(StageId) ON DELETE CASCADE,
    StartMinute INT NOT NULL,
    EndMinute INT NOT NULL,
    EnemyId INT NOT NULL FOREIGN KEY REFERENCES Enemies(EnemyId),
    SpawnIntervalMs INT NOT NULL DEFAULT 1000,
    MinGroupSize INT NOT NULL DEFAULT 1,
    MaxActiveByType INT NOT NULL DEFAULT 100,        -- Cap theo từng loại quái
    HpScaleMultiplier DECIMAL(5,2) NOT NULL DEFAULT 1.00
);

-- 29. Giai đoạn Boss & Chiêu thức Boss (BossPhases & BossAttackPatterns)
CREATE TABLE BossPhases (
    PhaseId INT IDENTITY(1,1) PRIMARY KEY,
    BossEnemyId INT NOT NULL FOREIGN KEY REFERENCES Enemies(EnemyId) ON DELETE CASCADE,
    PhaseNo TINYINT NOT NULL,                        -- Phase 1 (100% HP), Phase 2 (<50% HP)...
    TriggerHpPercent DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    SpeedMultiplier DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    DamageMultiplier DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    EnrageVfxKey VARCHAR(50) NULL,
    CONSTRAINT UQ_Boss_Phase UNIQUE (BossEnemyId, PhaseNo)
);

CREATE TABLE BossAttackPatterns (
    AttackId INT IDENTITY(1,1) PRIMARY KEY,
    PhaseId INT NOT NULL FOREIGN KEY REFERENCES BossPhases(PhaseId) ON DELETE CASCADE,
    PatternCode VARCHAR(30) NOT NULL,                -- 'TELEGRAPH_CHARGE', 'RADIAL_BULLET_HELL', 'SUMMON_MINIONS'
    TelegraphDurationMs INT NOT NULL DEFAULT 1000,   -- Thời gian hiện vùng cảnh báo đỏ trước khi đánh
    CooldownMs INT NOT NULL DEFAULT 5000,
    DamageMultiplier DECIMAL(4,2) NOT NULL DEFAULT 1.50,
    SummonEnemyId INT NULL FOREIGN KEY REFERENCES Enemies(EnemyId),
    SummonCount TINYINT NOT NULL DEFAULT 0
);

-- 30. Vật phẩm rơi trong trận & Bảng tỉ lệ rơi theo Quái (DropItems & EnemyDropTables)
CREATE TABLE DropItems (
    DropItemId INT IDENTITY(1,1) PRIMARY KEY,
    DropCode VARCHAR(30) UNIQUE NOT NULL,            -- 'EXP_SMALL', 'EXP_LARGE', 'GOLD_COIN', 'MEAT_HEAL', 'MAGNET_ORB', 'BOMB_ALL', 'BOSS_CHEST'
    DropName NVARCHAR(100) NOT NULL,
    DropType VARCHAR(20) NOT NULL,                   -- 'EXP', 'GOLD', 'HEAL', 'MAGNET', 'BOMB', 'SHIELD', 'CHEST'
    EffectValue INT NOT NULL DEFAULT 1,
    IsPermanentReward BIT NOT NULL DEFAULT 0,        -- 0 = Chỉ tồn tại trong Run, 1 = Cộng vào tài khoản sau khi xác thực
    SpriteKey VARCHAR(50) NOT NULL
);

CREATE TABLE EnemyDropTables (
    EnemyId INT NOT NULL FOREIGN KEY REFERENCES Enemies(EnemyId) ON DELETE CASCADE,
    DropItemId INT NOT NULL FOREIGN KEY REFERENCES DropItems(DropItemId),
    DropChancePercent DECIMAL(5,2) NOT NULL,         -- Tỉ lệ rơi (0.01% -> 100.00%)
    MinQuantity SMALLINT NOT NULL DEFAULT 1,
    MaxQuantity SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (EnemyId, DropItemId)
);

-- 31. Chướng ngại vật & Sự kiện Bản đồ (MapHazards & StageEvents)
CREATE TABLE MapHazards (
    HazardId INT IDENTITY(1,1) PRIMARY KEY,
    StageId INT NOT NULL FOREIGN KEY REFERENCES Stages(StageId) ON DELETE CASCADE,
    HazardCode VARCHAR(30) NOT NULL,                 -- 'SPIKE_TRAP', 'POISON_SWAMP', 'LAVA_ZONE'
    TickDamage INT NOT NULL DEFAULT 5,
    AppliedEffectCode VARCHAR(20) NULL FOREIGN KEY REFERENCES StatusEffects(EffectCode)
);

CREATE TABLE StageEvents (
    EventId INT IDENTITY(1,1) PRIMARY KEY,
    StageId INT NOT NULL FOREIGN KEY REFERENCES Stages(StageId) ON DELETE CASCADE,
    EventCode VARCHAR(30) NOT NULL,                  -- 'BLOOD_MOON', 'CHALLENGE_PORTAL', 'SKELETON_SIEGE'
    StartAtSec INT NOT NULL,
    DurationSec INT NOT NULL DEFAULT 60,
    RewardMultiplier DECIMAL(4,2) NOT NULL DEFAULT 1.50,
    WarningMessage NVARCHAR(200) NOT NULL
);
GO

/* =================================================================================
   MODULE 7: CỬA HÀNG, NHIỆM VỤ, THÀNH TỰU & GACHA (ECONOMY, QUESTS & GACHA)
   ================================================================================= */

-- 32. Cửa hàng Vật phẩm (ShopOffers & UserOfferPurchases)
CREATE TABLE ShopOffers (
    OfferId INT IDENTITY(1,1) PRIMARY KEY,
    OfferCode VARCHAR(30) UNIQUE NOT NULL,
    OfferName NVARCHAR(100) NOT NULL,
    RewardType VARCHAR(20) NOT NULL,                 -- 'CURRENCY', 'EQUIPMENT'
    RewardCurrencyType VARCHAR(20) NULL,
    RewardTemplateId INT NULL FOREIGN KEY REFERENCES EquipmentTemplates(TemplateId),
    RewardQuantity INT NOT NULL DEFAULT 1,
    CostCurrencyType VARCHAR(20) NOT NULL,           -- 'GOLD', 'GEMS'
    CostAmount INT NOT NULL,
    LimitPerPeriod SMALLINT NULL,                    -- Giới hạn mua theo ngày/tuần (NULL = Không giới hạn)
    ResetPeriod VARCHAR(15) NOT NULL DEFAULT 'DAILY',-- 'DAILY', 'WEEKLY', 'PERMANENT', 'NONE'
    IsActive BIT NOT NULL DEFAULT 1
);

CREATE TABLE UserOfferPurchases (
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    OfferId INT NOT NULL FOREIGN KEY REFERENCES ShopOffers(OfferId),
    PeriodKey VARCHAR(20) NOT NULL,                  -- VD: '2026-10-25' (Daily), '2026-W43' (Weekly), 'ALL_TIME'
    PurchasedCount SMALLINT NOT NULL DEFAULT 1,
    LastPurchasedAt DATETIME2 DEFAULT GETDATE(),
    PRIMARY KEY (UserId, OfferId, PeriodKey)
);

-- 33. Hệ thống Nhiệm vụ & Thành tựu (Quests & Achievements)
CREATE TABLE Quests (
    QuestId INT IDENTITY(1,1) PRIMARY KEY,
    QuestCode VARCHAR(30) UNIQUE NOT NULL,
    QuestName NVARCHAR(100) NOT NULL,
    QuestScope VARCHAR(15) NOT NULL DEFAULT 'DAILY', -- 'DAILY', 'WEEKLY', 'PERMANENT'
    TargetMetric VARCHAR(30) NOT NULL,               -- 'KILL_ENEMIES', 'SURVIVE_SECONDS', 'KILL_BOSS', 'ROLL_GACHA'
    TargetValue INT NOT NULL,
    RewardCurrencyType VARCHAR(20) NOT NULL,
    RewardAmount INT NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1
);

CREATE TABLE UserQuestProgress (
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    QuestId INT NOT NULL FOREIGN KEY REFERENCES Quests(QuestId),
    PeriodKey VARCHAR(20) NOT NULL,                  -- '2026-10-25', '2026-W43', 'PERMANENT'
    CurrentProgress INT NOT NULL DEFAULT 0,
    IsClaimed BIT NOT NULL DEFAULT 0,
    ClaimRequestId VARCHAR(64) NULL,
    ClaimedAt DATETIME2 NULL,
    PRIMARY KEY (UserId, QuestId, PeriodKey)
);

CREATE TABLE Achievements (
    AchievementId INT IDENTITY(1,1) PRIMARY KEY,
    AchievementCode VARCHAR(30) UNIQUE NOT NULL,
    Title NVARCHAR(100) NOT NULL,
    MetricType VARCHAR(30) NOT NULL,
    RequiredValue BIGINT NOT NULL,
    RewardGems INT NOT NULL DEFAULT 50
);

CREATE TABLE UserAchievements (
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    AchievementId INT NOT NULL FOREIGN KEY REFERENCES Achievements(AchievementId),
    UnlockedAt DATETIME2 DEFAULT GETDATE(),
    IsClaimed BIT NOT NULL DEFAULT 0,
    PRIMARY KEY (UserId, AchievementId)
);

-- 34. Hệ thống Gacha, Pity 10/50/100 & Giao dịch Tối thiểu (GachaTransactions)
CREATE TABLE GachaBanners (
    BannerId INT IDENTITY(1,1) PRIMARY KEY,
    BannerCode VARCHAR(40) UNIQUE NOT NULL,
    BannerName NVARCHAR(100) NOT NULL,
    BannerType VARCHAR(20) NOT NULL,                 -- 'WEAPON', 'EQUIPMENT', 'SKIN'
    CurrencyType VARCHAR(20) NOT NULL,               -- 'GEMS', 'EQUIP_TICKET', 'SKIN_TICKET'
    CostSinglePull INT NOT NULL DEFAULT 160,
    CostTenPull INT NOT NULL DEFAULT 1500,
    PityPurpleThreshold INT NOT NULL DEFAULT 10,     -- Bảo hiểm Tím (Tier 4) mỗi 10 lượt
    PityOrangeThreshold INT NOT NULL DEFAULT 50,     -- Bảo hiểm Cam (Tier 5) mỗi 50 lượt
    PityRedThreshold INT NOT NULL DEFAULT 100,       -- Bảo hiểm Đỏ (Tier 6) mỗi 100 lượt
    IsActive BIT NOT NULL DEFAULT 1
);

CREATE TABLE GachaPoolItems (
    PoolItemId INT IDENTITY(1,1) PRIMARY KEY,
    BannerId INT NOT NULL FOREIGN KEY REFERENCES GachaBanners(BannerId) ON DELETE CASCADE,
    ItemCategory VARCHAR(15) NOT NULL,               -- 'EQUIPMENT', 'SKIN'
    EquipmentTemplateId INT NULL FOREIGN KEY REFERENCES EquipmentTemplates(TemplateId),
    SkinId INT NULL FOREIGN KEY REFERENCES HeroSkins(SkinId),
    RarityTier INT NOT NULL FOREIGN KEY REFERENCES Rarities(RarityTier),
    DropWeight INT NOT NULL DEFAULT 100,
    IsRateUp BIT NOT NULL DEFAULT 0
);

CREATE TABLE UserBannerPity (
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    BannerId INT NOT NULL FOREIGN KEY REFERENCES GachaBanners(BannerId) ON DELETE CASCADE,
    PullsSinceLastPurple INT NOT NULL DEFAULT 0,
    PullsSinceLastOrange INT NOT NULL DEFAULT 0,
    PullsSinceLastRed INT NOT NULL DEFAULT 0,
    TotalPulls INT NOT NULL DEFAULT 0,
    PRIMARY KEY (UserId, BannerId)
);

-- Bảng giao dịch Gacha tối thiểu theo mục 4.4 & 6 (Lưu theo Request quay để chống retry & audit)
CREATE TABLE GachaTransactions (
    RollId BIGINT IDENTITY(1,1) PRIMARY KEY,
    RequestId VARCHAR(64) UNIQUE NOT NULL,           -- Idempotency Key
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId),
    BannerId INT NOT NULL FOREIGN KEY REFERENCES GachaBanners(BannerId),
    PullCount TINYINT NOT NULL,                      -- 1 hoặc 10
    CurrencySpent VARCHAR(20) NOT NULL,
    CostAmount INT NOT NULL,
    PityStateBefore VARCHAR(50) NOT NULL,            -- VD: 'P:8|O:42|R:92'
    PityStateAfter VARCHAR(50) NOT NULL,
    ResultsJson NVARCHAR(MAX) NOT NULL,              -- Danh sách vật phẩm quay ra
    CreatedAt DATETIME2 DEFAULT GETDATE()
);
GO

/* =================================================================================
   MODULE 8: PHIÊN CHƠI, BUILD TRONG TRẬN & BẢNG XẾP HẠNG (RUNS, BUILDS & LEADERBOARDS)
   ================================================================================= */

-- 35. Phiên trận đấu (GameRuns - Hỗ trợ Solo & Co-op, lưu Snapshot và Anti-cheat)
CREATE TABLE GameRuns (
    RunId BIGINT IDENTITY(1,1) PRIMARY KEY,
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId),
    HeroInstanceId BIGINT NOT NULL FOREIGN KEY REFERENCES UserHeroes(HeroInstanceId),
    HeroId INT NOT NULL FOREIGN KEY REFERENCES Heroes(HeroId),
    StageId INT NOT NULL FOREIGN KEY REFERENCES Stages(StageId),
    BalanceVersionId INT NOT NULL FOREIGN KEY REFERENCES GameBalanceVersions(VersionId),
    GameMode VARCHAR(15) NOT NULL DEFAULT 'SOLO',    -- 'SOLO', 'COOP'
    PartyRoomCode VARCHAR(20) NULL,
    RandomSeed INT NOT NULL,                         -- Seed khởi tạo trận
    RunState VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS', -- 'IN_PROGRESS', 'DEAD', 'CLEARED', 'QUIT', 'DISCONNECTED'
    FinishRequestId VARCHAR(64) NULL UNIQUE,         -- Chống gửi FinishRun 2 lần
    SurvivalTimeSec INT NOT NULL DEFAULT 0,
    WavesCleared INT NOT NULL DEFAULT 0,
    LevelReached INT NOT NULL DEFAULT 1,
    TotalKills INT NOT NULL DEFAULT 0,
    BossesKilled INT NOT NULL DEFAULT 0,
    TotalDamageDealt BIGINT NOT NULL DEFAULT 0,
    RevivesUsed TINYINT NOT NULL DEFAULT 0,
    RerollsUsed TINYINT NOT NULL DEFAULT 0,
    GoldEarned INT NOT NULL DEFAULT 0,
    Score INT NOT NULL DEFAULT 0,                    -- Điểm tổng để xét Tie-break
    StatSnapshotJson NVARCHAR(MAX) NULL,             -- Snapshot chỉ số lúc StartRun
    IsValidForLeaderboard BIT NOT NULL DEFAULT 1,    -- 0 nếu hệ thống phát hiện thông số bất thường
    StartedAt DATETIME2 DEFAULT GETDATE(),
    EndedAt DATETIME2 NULL,
    CONSTRAINT CK_RunState CHECK (RunState IN ('IN_PROGRESS', 'DEAD', 'CLEARED', 'QUIT', 'DISCONNECTED'))
);

-- 36. Kỹ năng Chủ động trong trận (RunSkills - Tối đa 6 Slots)
CREATE TABLE RunSkills (
    RunId BIGINT NOT NULL FOREIGN KEY REFERENCES GameRuns(RunId) ON DELETE CASCADE,
    SkillId INT NOT NULL FOREIGN KEY REFERENCES Skills(SkillId),
    FinalLevel TINYINT NOT NULL DEFAULT 1,
    IsEvolved BIT NOT NULL DEFAULT 0,
    TotalDamageDealt BIGINT NOT NULL DEFAULT 0,
    DPS DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    PRIMARY KEY (RunId, SkillId)
);

-- 37. Trang bị Bị động trong trận (RunPassives - Tối đa 6 Slots)
CREATE TABLE RunPassives (
    RunId BIGINT NOT NULL FOREIGN KEY REFERENCES GameRuns(RunId) ON DELETE CASCADE,
    PassiveId INT NOT NULL FOREIGN KEY REFERENCES PassiveItems(PassiveId),
    FinalLevel TINYINT NOT NULL DEFAULT 1,
    PRIMARY KEY (RunId, PassiveId)
);

-- 38. Sự kiện Checkpoint trong trận (RunEvents - Phục vụ xác thực Boss Kill / Chest Open)
CREATE TABLE RunEvents (
    RunEventId BIGINT IDENTITY(1,1) PRIMARY KEY,
    RunId BIGINT NOT NULL FOREIGN KEY REFERENCES GameRuns(RunId) ON DELETE CASCADE,
    RunSecond INT NOT NULL,
    EventType VARCHAR(30) NOT NULL,                  -- 'BOSS_SPAWN', 'BOSS_KILL', 'EVOLUTION', 'REVIVE', 'CHEST_OPEN'
    EventDataJson NVARCHAR(500) NULL
);

-- 39. Bảng Xếp Hạng Sinh Tồn (SurvivalLeaderboards - Chỉ lưu Kỷ lục hợp lệ cao nhất)
CREATE TABLE SurvivalLeaderboards (
    LeaderboardId BIGINT IDENTITY(1,1) PRIMARY KEY,
    StageId INT NOT NULL FOREIGN KEY REFERENCES Stages(StageId),
    GameMode VARCHAR(15) NOT NULL DEFAULT 'SOLO',
    UserId INT NOT NULL FOREIGN KEY REFERENCES Users(UserId) ON DELETE CASCADE,
    HeroId INT NOT NULL FOREIGN KEY REFERENCES Heroes(HeroId),
    ActiveSkinId INT NULL FOREIGN KEY REFERENCES HeroSkins(SkinId),
    BestSurvivalTimeSec INT NOT NULL,
    WavesCleared INT NOT NULL DEFAULT 0,
    TotalKillsInBestRun INT NOT NULL DEFAULT 0,
    BestScore INT NOT NULL DEFAULT 0,
    TotalDamageInBestRun BIGINT NOT NULL DEFAULT 0,
    LevelReached INT NOT NULL DEFAULT 1,
    BestRunId BIGINT NOT NULL FOREIGN KEY REFERENCES GameRuns(RunId),
    AchievedAt DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT UQ_Leaderboard_Best UNIQUE (StageId, GameMode, UserId, HeroId)
);
GO

/* =================================================================================
   MODULE 9: INDEXES TỐI ƯU HÓA TRUY VẤN
   ================================================================================= */

-- Index cho Bảng xếp hạng theo đúng tiêu chí Tie-break (Giây sống -> Wave -> Kill -> Điểm)
CREATE NONCLUSTERED INDEX IX_SurvivalLeaderboards_RankOrder
ON SurvivalLeaderboards (StageId ASC, GameMode ASC, BestSurvivalTimeSec DESC, WavesCleared DESC, TotalKillsInBestRun DESC, BestScore DESC)
INCLUDE (UserId, HeroId, ActiveSkinId, LevelReached, BestRunId, AchievedAt);

CREATE NONCLUSTERED INDEX IX_GameRuns_User_State
ON GameRuns (UserId ASC, RunState ASC) INCLUDE (StageId, HeroId, StartedAt);

CREATE NONCLUSTERED INDEX IX_UserEquipments_InventoryFilter
ON UserEquipments (UserId ASC, CurrentRarityTier DESC) INCLUDE (TemplateId, EnhanceLevel, IsLocked);
GO

/* =================================================================================
   MODULE 10: STORED PROCEDURES CỐT LÕI (THEO MỤC 6.2 TRONG BẢN PHÂN TÍCH)
   ================================================================================= */

-- 1. SP_STARTRUN: Xác thực sở hữu Hero, Ban/Pick, 5 ô trang bị, áp dụng Cap và khởi tạo RunId
CREATE OR ALTER PROCEDURE sp_StartRun
    @UserId INT,
    @HeroId INT,
    @StageId INT,
    @GameMode VARCHAR(15) = 'SOLO'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @HeroInstanceId BIGINT, @VersionId INT, @MaxCDR DECIMAL(5,2), @MaxDR DECIMAL(5,2), @MaxCrit DECIMAL(5,2);

        -- Kiểm tra sở hữu nhân vật
        SELECT @HeroInstanceId = HeroInstanceId FROM UserHeroes WHERE UserId = @UserId AND HeroId = @HeroId;
        IF @HeroInstanceId IS NULL
            THROW 50101, N'Người chơi chưa sở hữu nhân vật này!', 1;

        -- Lấy phiên bản cân bằng đang hoạt động và các mức trần (Caps)
        SELECT TOP 1 
            @VersionId = VersionId, 
            @MaxCDR = MaxCooldownReductionCap, 
            @MaxDR = MaxDamageReductionCap, 
            @MaxCrit = MaxCritRateCap
        FROM GameBalanceVersions WHERE IsActive = 1 ORDER BY VersionId DESC;

        -- Đọc cấp độ 12 ô nâng cấp chỉ số/tiện ích của Hero
        DECLARE @VitalityLv INT = 0, @StrengthLv INT = 0, @StrideLv INT = 0, @ReflexesLv INT = 0,
                @ArmorLv INT = 0, @SynthesisLv INT = 0, @MagnetLv INT = 0, @WisdomLv INT = 0,
                @FortuneLv INT = 0, @RepertoireLv INT = 0, @CritLv INT = 0, @RerollLv INT = 0;

        SELECT 
            @VitalityLv   = MAX(CASE WHEN UpgradeCode = 'VITALITY'     THEN CurrentLevel ELSE 0 END),
            @StrengthLv   = MAX(CASE WHEN UpgradeCode = 'STRENGTH'     THEN CurrentLevel ELSE 0 END),
            @StrideLv     = MAX(CASE WHEN UpgradeCode = 'STRIDE'       THEN CurrentLevel ELSE 0 END),
            @ReflexesLv   = MAX(CASE WHEN UpgradeCode = 'REFLEXES'     THEN CurrentLevel ELSE 0 END),
            @ArmorLv      = MAX(CASE WHEN UpgradeCode = 'ARMOR'        THEN CurrentLevel ELSE 0 END),
            @SynthesisLv  = MAX(CASE WHEN UpgradeCode = 'SYNTHESIS'    THEN CurrentLevel ELSE 0 END),
            @MagnetLv     = MAX(CASE WHEN UpgradeCode = 'MAGNET'       THEN CurrentLevel ELSE 0 END),
            @WisdomLv     = MAX(CASE WHEN UpgradeCode = 'WISDOM'       THEN CurrentLevel ELSE 0 END),
            @FortuneLv    = MAX(CASE WHEN UpgradeCode = 'FORTUNE'      THEN CurrentLevel ELSE 0 END),
            @RepertoireLv = MAX(CASE WHEN UpgradeCode = 'REPERTOIRE'   THEN CurrentLevel ELSE 0 END),
            @CritLv       = MAX(CASE WHEN UpgradeCode = 'CRITICAL_HIT' THEN CurrentLevel ELSE 0 END),
            @RerollLv     = MAX(CASE WHEN UpgradeCode = 'CARD_REROLL'  THEN CurrentLevel ELSE 0 END)
        FROM UserHeroUpgradeLevels WHERE HeroInstanceId = @HeroInstanceId;

        -- Tổng hợp chỉ số từ 5 ô trang bị đang mặc
        DECLARE @EqHP INT = 0, @EqATK INT = 0, @EqArmor DECIMAL(5,2) = 0, @EqSpd INT = 0, @EqCrit DECIMAL(5,2) = 0, @EqCDR DECIMAL(5,2) = 0;

        SELECT 
            @EqHP    = ISNULL(SUM(CAST(et.BaseHP * r.StatMultiplier * (1 + (ue.EnhanceLevel - 1) * 0.05) AS INT)), 0),
            @EqATK   = ISNULL(SUM(CAST(et.BaseATK * r.StatMultiplier * (1 + (ue.EnhanceLevel - 1) * 0.05) AS INT)), 0),
            @EqArmor = ISNULL(SUM(et.BaseArmor * r.StatMultiplier), 0),
            @EqSpd   = ISNULL(SUM(et.BaseMoveSpeed), 0),
            @EqCrit  = ISNULL(SUM(et.BaseCritRate), 0),
            @EqCDR   = ISNULL(SUM(et.BaseCooldownRed), 0)
        FROM HeroEquippedItems hei
        JOIN UserEquipments ue ON hei.UserEquipId = ue.UserEquipId
        JOIN EquipmentTemplates et ON ue.TemplateId = et.TemplateId
        JOIN Rarities r ON ue.CurrentRarityTier = r.RarityTier
        WHERE hei.HeroInstanceId = @HeroInstanceId;

        -- Tạo bản ghi GameRuns mới ở trạng thái IN_PROGRESS
        DECLARE @NewRunId BIGINT, @Seed INT = ABS(CHECKSUM(NEWID()));
        INSERT INTO GameRuns (UserId, HeroInstanceId, HeroId, StageId, BalanceVersionId, GameMode, RandomSeed, RunState)
        VALUES (@UserId, @HeroInstanceId, @HeroId, @StageId, @VersionId, @GameMode, @Seed, 'IN_PROGRESS');
        SET @NewRunId = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        -- Bảng 1: Trả về RunId và Snapshot chỉ số đã áp dụng Cap (Trần)
        SELECT 
            @NewRunId AS RunId,
            @Seed AS RandomSeed,
            h.HeroId,
            h.HeroCode,
            ISNULL(sk.SpriteKey, h.SpriteKey) AS ActiveSpriteKey,
            ISNULL(uh.PickedStartingSkill1Id, h.DefaultStartingSkillId) AS StartingSkill1Id,
            CASE WHEN @RepertoireLv >= 1 THEN uh.PickedStartingSkill2Id ELSE NULL END AS StartingSkill2Id,
            @RerollLv AS MaxRerollsPerRun,
            (h.BaseHP + (@VitalityLv * 8) + @EqHP) AS FinalMaxHP,
            CAST((@SynthesisLv * 0.20) AS DECIMAL(4,2)) AS HpRegenPerSec,
            (h.BaseMight + (@StrengthLv * 0.04)) AS BonusDamageMultiplier,
            @EqATK AS FlatWeaponDamage,
            CAST(h.BaseMoveSpeed * (1.00 + (@StrideLv * 0.03)) + @EqSpd AS INT) AS FinalMoveSpeed,
            -- Áp dụng Cap cho Giảm hồi chiêu, Giảm sát thương và Chí mạng
            CASE WHEN ((@ReflexesLv * 3.00) + @EqCDR) > @MaxCDR THEN @MaxCDR ELSE ((@ReflexesLv * 3.00) + @EqCDR) END AS CappedCooldownReductionPct,
            CASE WHEN (h.BaseArmor + (@ArmorLv * 2.00) + @EqArmor) > @MaxDR THEN @MaxDR ELSE (h.BaseArmor + (@ArmorLv * 2.00) + @EqArmor) END AS CappedDamageReductionPct,
            CASE WHEN (h.BaseCritRate + (@CritLv * 3.00) + @EqCrit) > @MaxCrit THEN @MaxCrit ELSE (h.BaseCritRate + (@CritLv * 3.00) + @EqCrit) END AS CappedCritRatePct,
            CAST(h.PickupRadius * (1.00 + (@MagnetLv * 0.12)) AS INT) AS FinalPickupRadius,
            CAST((1.00 + (@WisdomLv * 0.05)) AS DECIMAL(4,2)) AS ExpMultiplier,
            CAST((1.00 + (@FortuneLv * 0.08)) AS DECIMAL(4,2)) AS GoldMultiplier
        FROM UserHeroes uh
        JOIN Heroes h ON uh.HeroId = h.HeroId
        LEFT JOIN HeroSkins sk ON uh.ActiveSkinId = sk.SkinId
        WHERE uh.HeroInstanceId = @HeroInstanceId;

        -- Bảng 2: Trả về Bể kỹ năng hợp lệ (Loại bỏ các kỹ năng nằm trong Ban List và kỹ năng cấp 6)
        DECLARE @HeroClass VARCHAR(20) = (SELECT HeroCode FROM Heroes WHERE HeroId = @HeroId);
        SELECT s.*
        FROM Skills s
        WHERE s.IsEvolvedForm = 0
          AND (s.ClassTag = 'ANY' OR s.ClassTag = @HeroClass)
          AND s.SkillId NOT IN (SELECT BannedSkillId FROM UserHeroBannedSkills WHERE HeroInstanceId = @HeroInstanceId);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 2. SP_FINISHRUN: Xác thực kết quả, chống gửi trùng (Idempotent), cộng Vàng qua Sổ cái và cập nhật BXH
CREATE OR ALTER PROCEDURE sp_FinishRun
    @RunId BIGINT,
    @UserId INT,
    @RequestId VARCHAR(64),
    @EndState VARCHAR(20),            -- 'DEAD', 'CLEARED', 'QUIT', 'DISCONNECTED'
    @SurvivalTimeSec INT,
    @WavesCleared INT,
    @LevelReached INT,
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

        -- Idempotency: Nếu trận đấu đã kết thúc trước đó, không cộng thưởng lần 2
        IF @CurrentState <> 'IN_PROGRESS'
            THROW 50103, N'Trận đấu này đã được tổng kết trước đó!', 1;

        -- Kiểm tra chống gian lận cơ bản (Thời gian báo cáo lớn hơn thời gian thực tế trôi qua + dung sai 30s, hoặc Vàng vượt trần)
        DECLARE @RealElapsedSec INT = DATEDIFF(SECOND, @StartedAt, GETDATE());
        DECLARE @IsValid BIT = 1, @CappedGold INT = @GoldEarned;
        IF (@SurvivalTimeSec > @RealElapsedSec + 60) OR (@TotalKills > @SurvivalTimeSec * 40)
        BEGIN
            SET @IsValid = 0;
            INSERT INTO AuditLogs (UserId, ActionType, Severity, PayloadJson)
            VALUES (@UserId, 'SUSPICIOUS_RUN', 'WARNING', CONCAT('{"runId":', @RunId, ',"reportedSec":', @SurvivalTimeSec, ',"realSec":', @RealElapsedSec, '}'));
        END

        -- Tính Điểm tổng (Score) để phục vụ Tie-break trên Bảng xếp hạng
        DECLARE @Score INT = (@SurvivalTimeSec * 10) + (@WavesCleared * 100) + @TotalKills + (@BossesKilled * 500);

        UPDATE GameRuns
        SET RunState = @EndState,
            FinishRequestId = @RequestId,
            SurvivalTimeSec = @SurvivalTimeSec,
            WavesCleared = @WavesCleared,
            LevelReached = @LevelReached,
            TotalKills = @TotalKills,
            BossesKilled = @BossesKilled,
            TotalDamageDealt = @TotalDamageDealt,
            GoldEarned = @CappedGold,
            Score = @Score,
            IsValidForLeaderboard = @IsValid,
            EndedAt = GETDATE()
        WHERE RunId = @RunId;

        -- Lưu danh sách Active Skills (Tối đa 6)
        IF @SkillsJson IS NOT NULL AND ISJSON(@SkillsJson) = 1
        BEGIN
            INSERT INTO RunSkills (RunId, SkillId, FinalLevel, IsEvolved, TotalDamageDealt, DPS)
            SELECT @RunId, SkillId, FinalLevel, IsEvolved, TotalDamageDealt, DPS
            FROM OPENJSON(@SkillsJson)
            WITH (SkillId INT '$.skillId', FinalLevel TINYINT '$.finalLevel', IsEvolved BIT '$.isEvolved', TotalDamageDealt BIGINT '$.damageDealt', DPS DECIMAL(12,2) '$.dps');
        END

        -- Lưu danh sách Passive Items (Tối đa 6)
        IF @PassivesJson IS NOT NULL AND ISJSON(@PassivesJson) = 1
        BEGIN
            INSERT INTO RunPassives (RunId, PassiveId, FinalLevel)
            SELECT @RunId, PassiveId, FinalLevel
            FROM OPENJSON(@PassivesJson)
            WITH (PassiveId INT '$.passiveId', FinalLevel TINYINT '$.finalLevel');
        END

        -- Cộng Vàng vào Ví (UserWallets) và ghi Sổ cái (CurrencyTransactions)
        IF @CappedGold > 0 AND @IsValid = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM UserWallets WHERE UserId = @UserId AND CurrencyType = 'GOLD')
                INSERT INTO UserWallets (UserId, CurrencyType, Balance, TotalEarned) VALUES (@UserId, 'GOLD', 0, 0);

            DECLARE @NewGoldBalance BIGINT;
            UPDATE UserWallets
            SET Balance = Balance + @CappedGold,
                TotalEarned = TotalEarned + @CappedGold,
                @NewGoldBalance = Balance + @CappedGold,
                UpdatedAt = GETDATE()
            WHERE UserId = @UserId AND CurrencyType = 'GOLD';

            INSERT INTO CurrencyTransactions (RequestId, UserId, CurrencyType, AmountChange, BalanceAfter, ReasonCode, ReferenceId)
            VALUES (@RequestId, @UserId, 'GOLD', @CappedGold, @NewGoldBalance, 'RUN_REWARD', CAST(@RunId AS VARCHAR(64)));
        END

        -- Cập nhật thống kê UserProfiles
        UPDATE UserProfiles
        SET TotalRuns = TotalRuns + 1,
            TotalKills = TotalKills + @TotalKills,
            TotalBossKills = TotalBossKills + @BossesKilled,
            BestSurvivalTimeSec = CASE WHEN @SurvivalTimeSec > BestSurvivalTimeSec AND @IsValid = 1 THEN @SurvivalTimeSec ELSE BestSurvivalTimeSec END,
            UpdatedAt = GETDATE()
        WHERE UserId = @UserId;

        -- Đồng bộ Bảng xếp hạng (Chỉ khi Run hợp lệ)
        DECLARE @IsNewRecord BIT = 0, @ActiveSkinId INT;
        SELECT @ActiveSkinId = ActiveSkinId FROM UserHeroes WHERE UserId = @UserId AND HeroId = @HeroId;

        IF @IsValid = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM SurvivalLeaderboards WHERE StageId = @StageId AND GameMode = @GameMode AND UserId = @UserId AND HeroId = @HeroId)
            BEGIN
                INSERT INTO SurvivalLeaderboards (StageId, GameMode, UserId, HeroId, ActiveSkinId, BestSurvivalTimeSec, WavesCleared, TotalKillsInBestRun, BestScore, TotalDamageInBestRun, LevelReached, BestRunId)
                VALUES (@StageId, @GameMode, @UserId, @HeroId, @ActiveSkinId, @SurvivalTimeSec, @WavesCleared, @TotalKills, @Score, @TotalDamageDealt, @LevelReached, @RunId);
                SET @IsNewRecord = 1;
            END
            ELSE
            BEGIN
                UPDATE SurvivalLeaderboards
                SET BestSurvivalTimeSec = @SurvivalTimeSec,
                    WavesCleared = @WavesCleared,
                    TotalKillsInBestRun = @TotalKills,
                    BestScore = @Score,
                    TotalDamageInBestRun = @TotalDamageDealt,
                    LevelReached = @LevelReached,
                    ActiveSkinId = @ActiveSkinId,
                    BestRunId = @RunId,
                    AchievedAt = GETDATE(),
                    @IsNewRecord = 1
                WHERE StageId = @StageId AND GameMode = @GameMode AND UserId = @UserId AND HeroId = @HeroId
                  AND (
                      @SurvivalTimeSec > BestSurvivalTimeSec
                      OR (@SurvivalTimeSec = BestSurvivalTimeSec AND @Score > BestScore)
                  );
            END
        END

        COMMIT TRANSACTION;
        SELECT @RunId AS RunId, @CappedGold AS GoldAdded, @Score AS FinalScore, @IsNewRecord AS IsNewRecord;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3. SP_EQUIPITEM: Kiểm tra quyền sở hữu, đúng Slot, đúng Class và không mặc trùng 2 Hero
CREATE OR ALTER PROCEDURE sp_EquipItem
    @UserId INT,
    @HeroId INT,
    @UserEquipId BIGINT,
    @TargetSlot VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @HeroInstanceId BIGINT, @HeroClass VARCHAR(20), @ItemOwnerId INT, @ItemSlot VARCHAR(15), @ClassRestr VARCHAR(20);

        SELECT @HeroInstanceId = uh.HeroInstanceId, @HeroClass = h.HeroCode
        FROM UserHeroes uh JOIN Heroes h ON uh.HeroId = h.HeroId
        WHERE uh.UserId = @UserId AND uh.HeroId = @HeroId;

        IF @HeroInstanceId IS NULL
            THROW 50201, N'Bạn chưa sở hữu nhân vật này!', 1;

        SELECT @ItemOwnerId = ue.UserId, @ItemSlot = et.EquipSlot, @ClassRestr = et.ClassRestriction
        FROM UserEquipments ue JOIN EquipmentTemplates et ON ue.TemplateId = et.TemplateId
        WHERE ue.UserEquipId = @UserEquipId;

        IF @ItemOwnerId IS NULL OR @ItemOwnerId <> @UserId
            THROW 50202, N'Trang bị không thuộc quyền sở hữu của bạn!', 1;

        IF @ItemSlot <> @TargetSlot
            THROW 50203, N'Trang bị không khớp với ô (Slot) yêu cầu!', 1;

        IF @ClassRestr <> 'ANY' AND @ClassRestr <> @HeroClass
            THROW 50204, N'Hệ phái của nhân vật không thể sử dụng vũ khí/trang bị này!', 1;

        -- Tự động tháo trang bị này nếu đang mặc ở Hero khác và tháo món cũ trong cùng Slot
        DELETE FROM HeroEquippedItems WHERE UserEquipId = @UserEquipId;
        DELETE FROM HeroEquippedItems WHERE HeroInstanceId = @HeroInstanceId AND EquipSlot = @TargetSlot;

        INSERT INTO HeroEquippedItems (HeroInstanceId, EquipSlot, UserEquipId)
        VALUES (@HeroInstanceId, @TargetSlot, @UserEquipId);

        COMMIT TRANSACTION;
        SELECT N'Mặc trang bị thành công!' AS Message, @TargetSlot AS EquipSlot, @UserEquipId AS EquippedItemId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 4. SP_ENHANCEEQUIPMENT: Cường hóa trang bị an toàn, trừ tiền Atomic và kiểm tra Cap phẩm chất
CREATE OR ALTER PROCEDURE sp_EnhanceEquipment
    @UserId INT,
    @UserEquipId BIGINT,
    @RequestId VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @OwnerId INT, @RarityTier INT, @CurLevel INT, @MaxLevel INT, @GoldCost INT, @CurGold BIGINT;

        SELECT @OwnerId = ue.UserId, @RarityTier = ue.CurrentRarityTier, @CurLevel = ue.EnhanceLevel, @MaxLevel = r.MaxEnhanceLevel
        FROM UserEquipments ue WITH (UPDLOCK)
        JOIN Rarities r ON ue.CurrentRarityTier = r.RarityTier
        WHERE ue.UserEquipId = @UserEquipId;

        IF @OwnerId IS NULL OR @OwnerId <> @UserId
            THROW 50301, N'Không tìm thấy trang bị hợp lệ!', 1;

        IF @CurLevel >= @MaxLevel
            THROW 50302, N'Trang bị đã đạt cấp cường hóa tối đa của phẩm chất hiện tại!', 1;

        -- Tính chi phí cường hóa (Nếu bảng cấu hình chưa khai báo chi tiết từng cấp thì dùng công thức mặc định)
        SELECT @GoldCost = GoldCost FROM EquipmentEnhanceCosts WHERE RarityTier = @RarityTier AND TargetLevel = (@CurLevel + 1);
        IF @GoldCost IS NULL
            SET @GoldCost = (@CurLevel * 100 * @RarityTier);

        SELECT @CurGold = Balance FROM UserWallets WITH (UPDLOCK) WHERE UserId = @UserId AND CurrencyType = 'GOLD';
        IF ISNULL(@CurGold, 0) < @GoldCost
            THROW 50303, N'Không đủ Vàng để cường hóa!', 1;

        UPDATE UserWallets
        SET Balance = Balance - @GoldCost, TotalSpent = TotalSpent + @GoldCost, UpdatedAt = GETDATE()
        WHERE UserId = @UserId AND CurrencyType = 'GOLD';

        INSERT INTO CurrencyTransactions (RequestId, UserId, CurrencyType, AmountChange, BalanceAfter, ReasonCode, ReferenceId)
        VALUES (@RequestId, @UserId, 'GOLD', -@GoldCost, (@CurGold - @GoldCost), 'EQUIP_ENHANCE', CAST(@UserEquipId AS VARCHAR(64)));

        UPDATE UserEquipments SET EnhanceLevel = EnhanceLevel + 1 WHERE UserEquipId = @UserEquipId;

        COMMIT TRANSACTION;
        SELECT @UserEquipId AS UserEquipId, (@CurLevel + 1) AS NewEnhanceLevel, (@CurGold - @GoldCost) AS RemainingGold;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 5. SP_ROLLGACHA: Quay Gacha x1 / x10 phía Server, tính Pity 10/50/100 từng lượt và ghi GachaTransactions
CREATE OR ALTER PROCEDURE sp_RollGacha
    @UserId INT,
    @BannerId INT,
    @PullCount TINYINT,              -- 1 hoặc 10
    @RequestId VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        IF @PullCount NOT IN (1, 10)
            THROW 50401, N'Số lần quay chỉ chấp nhận 1 hoặc 10!', 1;

        DECLARE @Currency VARCHAR(20), @Cost INT, @PityPurple INT, @PityOrange INT, @PityRed INT, @IsActive BIT;
        SELECT 
            @Currency = CurrencyType,
            @Cost = CASE WHEN @PullCount = 10 THEN CostTenPull ELSE CostSinglePull END,
            @PityPurple = PityPurpleThreshold,
            @PityOrange = PityOrangeThreshold,
            @PityRed = PityRedThreshold,
            @IsActive = IsActive
        FROM GachaBanners WHERE BannerId = @BannerId;

        IF @IsActive IS NULL OR @IsActive = 0
            THROW 50402, N'Banner Gacha hiện không mở!', 1;

        -- Khóa và trừ tiền/vé trong Ví
        DECLARE @CurBalance BIGINT;
        SELECT @CurBalance = Balance FROM UserWallets WITH (UPDLOCK) WHERE UserId = @UserId AND CurrencyType = @Currency;
        IF ISNULL(@CurBalance, 0) < @Cost
            THROW 50403, N'Không đủ Kim cương hoặc Vé quay!', 1;

        UPDATE UserWallets
        SET Balance = Balance - @Cost, TotalSpent = TotalSpent + @Cost, UpdatedAt = GETDATE()
        WHERE UserId = @UserId AND CurrencyType = @Currency;

        INSERT INTO CurrencyTransactions (RequestId, UserId, CurrencyType, AmountChange, BalanceAfter, ReasonCode, ReferenceId)
        VALUES (@RequestId, @UserId, @Currency, -@Cost, (@CurBalance - @Cost), 'GACHA_ROLL', CAST(@BannerId AS VARCHAR(64)));

        -- Lấy bộ đếm Pity hiện tại của người chơi
        IF NOT EXISTS (SELECT 1 FROM UserBannerPity WHERE UserId = @UserId AND BannerId = @BannerId)
            INSERT INTO UserBannerPity (UserId, BannerId) VALUES (@UserId, @BannerId);

        DECLARE @P4 INT, @P5 INT, @P6 INT, @TotalPulls INT;
        SELECT @P4 = PullsSinceLastPurple, @P5 = PullsSinceLastOrange, @P6 = PullsSinceLastRed, @TotalPulls = TotalPulls
        FROM UserBannerPity WITH (UPDLOCK) WHERE UserId = @UserId AND BannerId = @BannerId;

        DECLARE @PityBefore VARCHAR(50) = CONCAT('P:', @P4, '|O:', @P5, '|R:', @P6);
        DECLARE @Results TABLE (PullIndex TINYINT, TemplateId INT, RarityTier INT, NewUserEquipId BIGINT);

        -- Vòng lặp từng lượt rút (kể cả khi quay x10) để tính Pity chính xác
        DECLARE @i TINYINT = 1;
        WHILE @i <= @PullCount
        BEGIN
            SET @P4 = @P4 + 1;
            SET @P5 = @P5 + 1;
            SET @P6 = @P6 + 1;
            SET @TotalPulls = @TotalPulls + 1;

            DECLARE @RolledTier INT = 1;

            -- Kiểm tra Hard Pity theo thứ tự ưu tiên: Đỏ (100) -> Cam (50) -> Tím (10)
            IF @P6 >= @PityRed
                SET @RolledTier = 6;
            ELSE IF @P5 >= @PityOrange
                SET @RolledTier = 5;
            ELSE IF @P4 >= @PityPurple
                SET @RolledTier = 4;
            ELSE
            BEGIN
                -- Random theo trọng số BaseGachaWeight (Tổng = 10000)
                DECLARE @Rand INT = ABS(CHECKSUM(NEWID())) % 10000;
                SET @RolledTier = CASE 
                    WHEN @Rand < 20   THEN 6 -- 0.2% Đỏ
                    WHEN @Rand < 150  THEN 5 -- 1.3% Cam
                    WHEN @Rand < 600  THEN 4 -- 4.5% Tím
                    WHEN @Rand < 2000 THEN 3 -- 14.0% Lam
                    WHEN @Rand < 5000 THEN 2 -- 30.0% Lục
                    ELSE 1                   -- 50.0% Trắng
                END;
            END

            -- Quy tắc Reset Pity: Trúng Đỏ reset P6/P5/P4; Trúng Cam reset P5/P4; Trúng Tím reset P4
            IF @RolledTier = 6 BEGIN SET @P6 = 0; SET @P5 = 0; SET @P4 = 0; END
            ELSE IF @RolledTier = 5 BEGIN SET @P5 = 0; SET @P4 = 0; END
            ELSE IF @RolledTier = 4 BEGIN SET @P4 = 0; END

            -- Chọn ngẫu nhiên 1 vật phẩm trong Pool của Banner khớp Rarity (hoặc fallback lấy Template phù hợp)
            DECLARE @ChosenTemplateId INT = NULL;
            SELECT TOP 1 @ChosenTemplateId = EquipmentTemplateId
            FROM GachaPoolItems WHERE BannerId = @BannerId AND RarityTier = @RolledTier ORDER BY NEWID();

            IF @ChosenTemplateId IS NULL
                SELECT TOP 1 @ChosenTemplateId = TemplateId FROM EquipmentTemplates ORDER BY NEWID();

            INSERT INTO UserEquipments (UserId, TemplateId, CurrentRarityTier, EnhanceLevel)
            VALUES (@UserId, @ChosenTemplateId, @RolledTier, 1);

            INSERT INTO @Results (PullIndex, TemplateId, RarityTier, NewUserEquipId)
            VALUES (@i, @ChosenTemplateId, @RolledTier, SCOPE_IDENTITY());

            SET @i = @i + 1;
        END

        -- Cập nhật lại bộ đếm Pity
        UPDATE UserBannerPity
        SET PullsSinceLastPurple = @P4, PullsSinceLastOrange = @P5, PullsSinceLastRed = @P6, TotalPulls = @TotalPulls
        WHERE UserId = @UserId AND BannerId = @BannerId;

        DECLARE @PityAfter VARCHAR(50) = CONCAT('P:', @P4, '|O:', @P5, '|R:', @P6);
        DECLARE @ResultsJson NVARCHAR(MAX) = (SELECT PullIndex, TemplateId, RarityTier, NewUserEquipId FROM @Results FOR JSON PATH);

        INSERT INTO GachaTransactions (RequestId, UserId, BannerId, PullCount, CurrencySpent, CostAmount, PityStateBefore, PityStateAfter, ResultsJson)
        VALUES (@RequestId, @UserId, @BannerId, @PullCount, @Currency, @Cost, @PityBefore, @PityAfter, @ResultsJson);

        COMMIT TRANSACTION;
        SELECT * FROM @Results;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 6. SP_CLAIMQUEST: Nhận thưởng Nhiệm vụ, chống nhận trùng (Unique Claim) và ghi Sổ cái
CREATE OR ALTER PROCEDURE sp_ClaimQuest
    @UserId INT,
    @QuestId INT,
    @PeriodKey VARCHAR(20),
    @RequestId VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;

    BEGIN TRY
        DECLARE @TargetVal INT, @RewardCurrency VARCHAR(20), @RewardAmt INT, @CurProg INT, @IsClaimed BIT;

        SELECT @TargetVal = TargetValue, @RewardCurrency = RewardCurrencyType, @RewardAmt = RewardAmount
        FROM Quests WHERE QuestId = @QuestId AND IsActive = 1;

        SELECT @CurProg = CurrentProgress, @IsClaimed = IsClaimed
        FROM UserQuestProgress WITH (UPDLOCK)
        WHERE UserId = @UserId AND QuestId = @QuestId AND PeriodKey = @PeriodKey;

        IF @CurProg IS NULL OR @CurProg < @TargetVal
            THROW 50501, N'Bạn chưa hoàn thành điều kiện nhiệm vụ này!', 1;

        IF @IsClaimed = 1
            THROW 50502, N'Phần thưởng nhiệm vụ này đã được nhận trước đó!', 1;

        UPDATE UserQuestProgress
        SET IsClaimed = 1, ClaimRequestId = @RequestId, ClaimedAt = GETDATE()
        WHERE UserId = @UserId AND QuestId = @QuestId AND PeriodKey = @PeriodKey;

        IF NOT EXISTS (SELECT 1 FROM UserWallets WHERE UserId = @UserId AND CurrencyType = @RewardCurrency)
            INSERT INTO UserWallets (UserId, CurrencyType, Balance, TotalEarned) VALUES (@UserId, @RewardCurrency, 0, 0);

        DECLARE @NewBal BIGINT;
        UPDATE UserWallets
        SET Balance = Balance + @RewardAmt, TotalEarned = TotalEarned + @RewardAmt, @NewBal = Balance + @RewardAmt, UpdatedAt = GETDATE()
        WHERE UserId = @UserId AND CurrencyType = @RewardCurrency;

        INSERT INTO CurrencyTransactions (RequestId, UserId, CurrencyType, AmountChange, BalanceAfter, ReasonCode, ReferenceId)
        VALUES (@RequestId, @UserId, @RewardCurrency, @RewardAmt, @NewBal, 'QUEST_CLAIM', CONCAT(@QuestId, ':', @PeriodKey));

        COMMIT TRANSACTION;
        SELECT @QuestId AS QuestId, @RewardCurrency AS CurrencyType, @RewardAmt AS RewardGranted, @NewBal AS NewBalance;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 7. SP_GETLEADERBOARD: Phân trang Bảng xếp hạng (Tie-break: Giây sống -> Wave -> Kill -> Điểm)
CREATE OR ALTER PROCEDURE sp_GetLeaderboard
    @StageId INT = 1,
    @GameMode VARCHAR(15) = 'SOLO',
    @HeroId INT = NULL,
    @PageNumber INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    WITH UserBest AS (
        SELECT 
            lb.UserId, up.DisplayName, up.AvatarKey, up.IsPublicBuildAllowed,
            lb.HeroId, h.HeroCode, h.HeroName,
            ISNULL(sk.SpriteKey, h.SpriteKey) AS DisplaySpriteKey,
            lb.BestSurvivalTimeSec, lb.WavesCleared, lb.TotalKillsInBestRun, lb.BestScore,
            lb.TotalDamageInBestRun, lb.LevelReached, lb.BestRunId, lb.AchievedAt,
            ROW_NUMBER() OVER (
                PARTITION BY lb.UserId 
                ORDER BY lb.BestSurvivalTimeSec DESC, lb.WavesCleared DESC, lb.TotalKillsInBestRun DESC, lb.BestScore DESC
            ) AS UserRunRank
        FROM SurvivalLeaderboards lb
        JOIN UserProfiles up ON lb.UserId = up.UserId
        JOIN Heroes h ON lb.HeroId = h.HeroId
        LEFT JOIN HeroSkins sk ON lb.ActiveSkinId = sk.SkinId
        WHERE lb.StageId = @StageId AND lb.GameMode = @GameMode AND (@HeroId IS NULL OR lb.HeroId = @HeroId)
    ),
    RankedAll AS (
        SELECT 
            DENSE_RANK() OVER (
                ORDER BY BestSurvivalTimeSec DESC, WavesCleared DESC, TotalKillsInBestRun DESC, BestScore DESC
            ) AS RankNumber,
            UserId, DisplayName, AvatarKey, HeroId, HeroCode, HeroName, DisplaySpriteKey,
            BestSurvivalTimeSec,
            RIGHT('00' + CAST(BestSurvivalTimeSec / 60 AS VARCHAR(10)), 2) + ':' + 
            RIGHT('00' + CAST(BestSurvivalTimeSec % 60 AS VARCHAR(2)), 2) AS FormattedTime,
            WavesCleared, TotalKillsInBestRun, BestScore, TotalDamageInBestRun, LevelReached,
            CASE WHEN IsPublicBuildAllowed = 1 THEN BestRunId ELSE NULL END AS InspectableRunId,
            AchievedAt
        FROM UserBest WHERE UserRunRank = 1
    )
    SELECT * FROM RankedAll
    ORDER BY RankNumber ASC
    OFFSET ((@PageNumber - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO

/* =================================================================================
   MODULE 11: DỮ LIỆU KHỞI TẠO MẪU (INITIAL SEED DATA)
   ================================================================================= */

-- 1. Phiên bản cân bằng mặc định
INSERT INTO GameBalanceVersions (VersionCode, ConfigHash, MaxActiveSkillSlots, MaxPassiveItemSlots, CritDamageMultiplier, MaxCooldownReductionCap, MaxDamageReductionCap, MaxCritRateCap, IsActive)
VALUES ('v1.0.0-MVP', 'SHA256_INIT_BALANCE_2026', 6, 6, 1.50, 60.00, 75.00, 100.00, 1);

-- 2. Hiệu ứng trạng thái
INSERT INTO StatusEffects (EffectCode, EffectName, BaseDurationMs, TickIntervalMs, MaxStacks, StackRule, AffectsBoss) VALUES
('BURN',   N'Thiêu Đốt', 3000, 500,  3, 'ADD_STACK', 1),
('POISON', N'Trúng Độc', 4000, 1000, 5, 'ADD_STACK', 1),
('SLOW',   N'Làm Chậm',  2500, NULL, 1, 'REFRESH',   1),
('STUN',   N'Choáng',    1000, NULL, 1, 'REFRESH',   0),
('FREEZE', N'Đóng Băng', 1500, NULL, 1, 'REFRESH',   0),
('BLEED',  N'Chảy Máu',  3000, 500,  5, 'ADD_STACK', 1),
('SHIELD', N'Khiên Chắn',5000, NULL, 1, 'REFRESH',   1);

-- 3. 6 Bậc Phẩm chất
INSERT INTO Rarities (RarityTier, RarityCode, RarityName, ColorHex, StatMultiplier, MaxEnhanceLevel, BaseGachaWeight) VALUES
(1, 'WHITE',  N'Trắng (Thường)',    '#CCCCCC', 1.00, 10,  5000),
(2, 'GREEN',  N'Lục (Tinh Nhuệ)',   '#2ECC71', 1.30, 20,  3000),
(3, 'BLUE',   N'Lam (Hiếm)',        '#3498DB', 1.70, 30,  1400),
(4, 'PURPLE', N'Tím (Sử Thi)',      '#9B59B6', 2.30, 50,   450),
(5, 'ORANGE', N'Cam (Huyền Thoại)', '#E67E22', 3.20, 80,   130),
(6, 'RED',    N'Đỏ (Thần Thoại)',   '#E74C3C', 4.50, 100,   20);

-- 4. Trang bị bị động trong trận
INSERT INTO PassiveItems (PassiveCode, PassiveName, StatTarget, BonusPerLevel, MaxLevel, SpriteKey) VALUES
('WARRIOR_GAUNTLET', N'Găng Tay Chiến Binh', 'MIGHT',      10.00, 5, 'icon_gauntlet'),
('HUNTER_QUIVER',    N'Ống Tên Thợ Săn',     'PROJ_SPEED', 15.00, 5, 'icon_quiver'),
('ARCANE_TOME',      N'Sách Cổ Ma Pháp',     'COOLDOWN',    8.00, 5, 'icon_tome'),
('DRAGON_HEART',     N'Trái Tim Rồng',       'MAX_HP',     20.00, 5, 'icon_heart'),
('HERMES_BOOTS',     N'Giày Gió',             'MOVE_SPEED', 10.00, 5, 'icon_boots'),
('MAGNET_RING',      N'Nhẫn Nam Châm',       'MAGNET',     25.00, 5, 'icon_magnet');

-- 5. Kỹ năng gốc (Lv 1-5) & Kỹ năng Tiến hóa (Lv 6)
INSERT INTO Skills (SkillCode, SkillName, ClassTag, AttackPattern, TargetingStrategy, MaxLevel, IsEvolvedForm, RequiredPassiveId, AppliedEffectCode, EffectChance, SpriteKey) VALUES
('CLEAVE_SWORD',   N'Trảm Kiếm',            'WARRIOR', 'MELEE',      'FACING',  5, 0, 1, 'BLEED', 0.25, 'skill_sword'),
('MULTISHOT_BOW',  N'Cung Tên Xuyên Phá',   'ARCHER',  'PROJECTILE', 'NEAREST', 5, 0, 2, 'SLOW',  0.20, 'skill_bow'),
('FIREBALL_STAFF', N'Cầu Lửa Hủy Diệt',     'MAGE',    'PROJECTILE', 'NEAREST', 5, 0, 3, 'BURN',  0.50, 'skill_fireball'),
('EVO_WHIRLWIND',  N'Huyết Kiếm Xoáy',      'WARRIOR', 'AREA',       'SELF_AURA',1,1, 1, 'BLEED', 0.50, 'skill_evo_sword'),
('EVO_TEMPEST',    N'Mưa Tên Bão Tố',        'ARCHER',  'PROJECTILE', 'NEAREST', 1, 1, 2, 'SLOW',  0.40, 'skill_evo_bow'),
('EVO_METEOR',     N'Thiên Thạch Dung Nham', 'MAGE',    'AREA',       'RANDOM',  1, 1, 3, 'BURN',  1.00, 'skill_evo_meteor');

-- Cập nhật liên kết Tiến hóa 2 chiều giữa chiêu gốc và chiêu tiến hóa
UPDATE Skills SET EvolutionToSkillId = 4 WHERE SkillId = 1;
UPDATE Skills SET EvolutionFromSkillId = 1 WHERE SkillId = 4;
UPDATE Skills SET EvolutionToSkillId = 5 WHERE SkillId = 2;
UPDATE Skills SET EvolutionFromSkillId = 2 WHERE SkillId = 5;
UPDATE Skills SET EvolutionToSkillId = 6 WHERE SkillId = 3;
UPDATE Skills SET EvolutionFromSkillId = 3 WHERE SkillId = 6;

-- 6. 3 Nhân vật cơ bản (Warrior, Archer, Mage)
INSERT INTO Heroes (HeroCode, HeroName, ClassRole, DefaultStartingSkillId, BaseHP, BaseArmor, BaseMoveSpeed, BaseMight, BaseCritRate, UnlockCostGold, SpriteKey, PassiveDesc) VALUES
('WARRIOR', N'Chiến Binh (Warrior)', 'Tank / Melee',   1, 130, 5.00, 100, 1.10,  5.00, 0, 'hero_warrior', N'+5% Giảm sát thương và +10% Sát thương vật lý'),
('ARCHER',  N'Cung Thủ (Archer)',    'Ranged / Speed', 2,  95, 0.00, 120, 1.00, 20.00, 0, 'hero_archer',  N'+20% Tốc độ chạy và +20% Tỉ lệ chí mạng'),
('MAGE',    N'Pháp Sư (Mage)',       'AoE Caster',     3,  85, 0.00, 105, 1.15,  5.00, 0, 'hero_mage',    N'+15% Sát thương phép và +25% tầm hút EXP');

-- 7. Cấu hình 15 Ô Nâng Cấp & Ban/Pick (Tách rõ STAT, UTILITY, BAN_PICK và có HardCapValue)
INSERT INTO HeroUpgradeConfigs (UpgradeCode, UpgradeCategory, UpgradeName, MaxLevel, BonusPerLevel, StatUnit, HardCapValue, BaseGoldCost, CostScale, Description, IconKey) VALUES
('VITALITY',     'STAT',     N'Vitality',             10,  8.00, 'FLAT_HP',    80.00,  100, 1.30, N'+8 HP mỗi cấp', 'ui_upg_vitality'),
('STRENGTH',     'STAT',     N'Strength',             10,  4.00, 'PERCENT',    40.00,  120, 1.35, N'+4% sát thương mỗi cấp', 'ui_upg_strength'),
('STRIDE',       'STAT',     N'Stride',                8,  3.00, 'PERCENT',    24.00,  100, 1.30, N'+3% tốc độ di chuyển mỗi cấp', 'ui_upg_stride'),
('REFLEXES',     'STAT',     N'Reflexes',              8,  3.00, 'PERCENT',    24.00,  150, 1.40, N'-3% thời gian hồi chiêu mỗi cấp', 'ui_upg_reflexes'),
('ARMOR',        'STAT',     N'Armor',                 8,  2.00, 'PERCENT',    16.00,  120, 1.35, N'+2% giảm sát thương nhận vào', 'ui_upg_armor'),
('SYNTHESIS',    'STAT',     N'Synthesis',             5,  0.20, 'HP_PER_SEC',  1.00,  200, 1.50, N'+0.2 máu hồi mỗi giây', 'ui_upg_synthesis'),
('MAGNET',       'STAT',     N'Magnet',                6, 12.00, 'PERCENT',    72.00,  100, 1.30, N'+12% phạm vi nhặt vật phẩm', 'ui_upg_magnet'),
('WISDOM',       'STAT',     N'Wisdom',                8,  5.00, 'PERCENT',    40.00,  120, 1.35, N'+5% kinh nghiệm nhận được', 'ui_upg_wisdom'),
('FORTUNE',      'STAT',     N'Fortune',               8,  8.00, 'PERCENT',    64.00,  150, 1.40, N'+8% Vàng nhận được', 'ui_upg_fortune'),
('CRITICAL_HIT', 'STAT',     N'Critical Hit',         10,  3.00, 'PERCENT',    30.00,  150, 1.35, N'+3% tỉ lệ chí mạng (x1.5 sát thương)', 'ui_upg_crit'),
('REPERTOIRE',   'UTILITY',  N'Repertoire',            1,  1.00, 'SLOT_COUNT',  1.00, 2500, 1.00, N'Bắt đầu trận đấu với 2 kỹ năng (Chiếm 2/6 ô Active)', 'ui_upg_repertoire'),
('CARD_REROLL',  'UTILITY',  N'Card Reroll',           5,  1.00, 'SLOT_COUNT',  5.00,  300, 1.60, N'+1 lượt đổi bài (Reroll) khi lên cấp', 'ui_upg_reroll'),
('BAN_SLOTS',    'BAN_PICK', N'Ban',                   3,  1.00, 'SLOT_COUNT',  3.00,  500, 2.00, N'Cấm 1 kỹ năng xuất hiện trong trận (Tối đa 3)', 'ui_upg_ban'),
('START_MOVE_1', 'BAN_PICK', N'Starting Move',         1,  1.00, 'UNLOCK',      1.00, 1000, 1.00, N'Mở khóa quyền tự chọn Kỹ năng khởi đầu 1', 'ui_upg_start1'),
('START_MOVE_2', 'BAN_PICK', N'Second Starting Move',  1,  1.00, 'UNLOCK',      1.00, 1500, 1.00, N'Mở khóa quyền tự chọn Kỹ năng khởi đầu 2', 'ui_upg_start2');

-- 8. Bản đồ, Quái vật, Boss Phases & Vật phẩm rơi
INSERT INTO Stages (StageCode, StageName, TilemapKey, MaxEnemiesGlobalCap, DespawnDistancePx, DifficultyMultiplier, IsEndlessMode)
VALUES ('CURSED_GRAVEYARD', N'Nghĩa Địa Cổ Nguyền Rủa', 'map_graveyard', 300, 1200, 1.00, 1);

INSERT INTO Enemies (EnemyCode, EnemyName, EnemyTier, AIBehavior, BaseHP, BaseDamage, MoveSpeed, PreferredRangePx, HitboxRadius, KnockbackResist, StunImmunity, SpriteKey) VALUES
('SLIME_GREEN',        N'Slime Xanh',          'NORMAL', 'SEEK',         20,  5, 45,   0, 12, 0.00, 0, 'mob_slime_green'),
('SKELETON_WARRIOR',   N'Bộ Xương Cầm Kiếm',   'NORMAL', 'SEEK',         45, 10, 60,   0, 14, 0.20, 0, 'mob_skeleton_warrior'),
('SKELETON_ARCHER',    N'Bộ Xương Bắn Cung',   'NORMAL', 'RANGED_KITE',  30, 12, 50, 220, 14, 0.10, 0, 'mob_skeleton_archer'),
('SLIME_KING_ELITE',   N'Vua Slime Khổng Lồ',  'ELITE',  'SEEK',        600, 20, 55,   0, 28, 0.70, 0, 'mob_slime_king'),
('SKELETON_LORD_BOSS', N'Lãnh Chúa Xương Khô', 'BOSS',   'BOSS_PATTERN',3500,35, 75,   0, 36, 0.95, 1, 'boss_skeleton_lord');

INSERT INTO BossPhases (BossEnemyId, PhaseNo, TriggerHpPercent, SpeedMultiplier, DamageMultiplier, EnrageVfxKey) VALUES
(5, 1, 100.00, 1.00, 1.00, NULL),
(5, 2,  50.00, 1.35, 1.50, 'vfx_boss_enrage_red');

INSERT INTO BossAttackPatterns (PhaseId, PatternCode, TelegraphDurationMs, CooldownMs, DamageMultiplier, SummonEnemyId, SummonCount) VALUES
(1, 'TELEGRAPH_CHARGE',   1200, 6000, 1.50, NULL, 0),
(2, 'RADIAL_BULLET_HELL', 1000, 5000, 1.80, NULL, 0),
(2, 'SUMMON_MINIONS',     1500, 12000,1.00, 2,    4);

INSERT INTO DropItems (DropCode, DropName, DropType, EffectValue, IsPermanentReward, SpriteKey) VALUES
('EXP_GEM_BLUE',  N'Ngọc EXP Lam',      'EXP',    5,   0, 'drop_exp_blue'),
('GOLD_POUCH',    N'Túi Vàng',          'GOLD',   10,  1, 'drop_gold_pouch'),
('ROAST_MEAT',    N'Thịt Nướng Hồi Phục','HEAL',  30,  0, 'drop_meat'),
('MAGNET_ORB',    N'Ngọc Từ Trường',    'MAGNET', 999, 0, 'drop_magnet'),
('BOSS_CHEST',    N'Rương Tiến Hóa Boss','CHEST', 1,   0, 'drop_boss_chest');

INSERT INTO EnemyDropTables (EnemyId, DropItemId, DropChancePercent, MinQuantity, MaxQuantity) VALUES
(1, 1, 100.00, 1, 1),
(2, 1, 100.00, 1, 2),
(2, 2,   8.00, 1, 1),
(4, 5, 100.00, 1, 1),
(5, 5, 100.00, 1, 1);

-- 9. Mẫu Trang bị 5 ô & 3 Banner Gacha
INSERT INTO EquipmentTemplates (ItemCode, ItemName, EquipSlot, ClassRestriction, BaseRarityTier, BaseHP, BaseATK, BaseArmor, BaseMoveSpeed, BaseCritRate, SpecialEffectDesc, IconKey) VALUES
('HELM_IRON',       N'Nón Sắt Tân Binh',  'HEAD',   'ANY',     1,  30,   0, 2.00, 0,  0.00, NULL, 'icon_helm_iron'),
('ARMOR_DRAGON',    N'Giáp Vảy Rồng Đỏ',  'ARMOR',  'ANY',     6, 300,  25,15.00, 0,  0.00, N'[Thần Thoại] Phản sát thương xung quanh', 'icon_armor_dragon'),
('PANTS_CLOTH',     N'Quần Vải Thô',      'PANTS',  'ANY',     1,  25,   0, 1.00, 2,  0.00, NULL, 'icon_pants_cloth'),
('BOOTS_TRAVELER',  N'Giày Hành Giả',     'BOOTS',  'ANY',     1,  10,   0, 1.00, 8,  0.00, NULL, 'icon_boots_traveler'),
('WPN_DEMON_BLADE', N'Huyết Quỷ Kiếm',    'WEAPON', 'WARRIOR', 6,  50,  95, 0.00, 0, 15.00, N'[Thần Thoại] Đòn chém thứ 5 tạo sóng kiếm', 'icon_wpn_demon_blade'),
('WPN_ELVEN_BOW',   N'Cung Tinh Linh',    'WEAPON', 'ARCHER',  5,   0,  65, 0.00, 5, 20.00, N'[Huyền Thoại] Bắn thêm tên đuổi theo Boss', 'icon_wpn_elven_bow'),
('WPN_VOID_STAFF',  N'Trượng Hư Không',   'WEAPON', 'MAGE',    6,   0, 105, 0.00, 0, 10.00, N'[Thần Thoại] Cầu lửa tạo hố đen hút quái', 'icon_wpn_void_staff');

INSERT INTO GachaBanners (BannerCode, BannerName, BannerType, CurrencyType, CostSinglePull, CostTenPull, PityPurpleThreshold, PityOrangeThreshold, PityRedThreshold, IsActive) VALUES
('BANNER_WEAPON_01', N'Hồ Cầu Nguyện Thần Binh (Vũ Khí)',    'WEAPON',    'GEMS',        160, 1500, 10, 50, 100, 1),
('BANNER_ARMOR_01',  N'Rương Quân Nhu Hoàng Gia (Trang Bị)', 'EQUIPMENT', 'GEMS',        120, 1080, 10, 50, 100, 1),
('BANNER_SKIN_01',   N'Vòng Quay Thời Trang (Chờ Ra Mắt)',   'SKIN',      'SKIN_TICKET',   1,   10, 10, 30,  60, 0);
GO