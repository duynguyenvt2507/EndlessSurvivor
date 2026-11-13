require('dotenv').config();
const express = require('express');
const sql = require('mssql');
const cors = require('cors');
const bcrypt = require('bcrypt');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const dbConfig = {
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD || 'EndlessSurvivor@2026!',
  server: process.env.DB_SERVER || 'localhost',
  port: parseInt(process.env.DB_PORT, 10) || 1433,
  database: process.env.DB_NAME || 'EndlessSurvivorDB',
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
  pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
};

const poolPromise = sql.connect(dbConfig).then((pool) => {
  console.log('Đã kết nối thành công SQL Server: EndlessSurvivorDB');
  return pool;
});

const asyncHandler = (fn) => async (req, res, next) => {
  try {
    await fn(req, res, next);
  } catch (err) {
    const errorCode = err.number || 500;
    res.status(errorCode >= 50000 ? 400 : 500).json({
      success: false,
      errorCode,
      message: err.message || 'Lỗi máy chủ nội bộ',
    });
  }
};

// 1. Lấy dữ liệu cấu hình tĩnh đầu game (Bootstrap Catalog: Level 300, Phòng Boss 20Lv, Final Boss 30p)
app.get('/api/game/bootstrap', asyncHandler(async (req, res) => {
  const pool = await poolPromise;
  const [
    heroes, skills, skillLevels, passives, enemies,
    bossPhases, bossPatterns, stages, waves, stageEvents, expCurves, upgradeConfigs
  ] = await Promise.all([
    pool.request().query('SELECT * FROM Heroes'),
    pool.request().query('SELECT * FROM Skills'),
    pool.request().query('SELECT * FROM SkillLevels ORDER BY SkillId, LevelNum'),
    pool.request().query('SELECT * FROM PassiveItems'),
    pool.request().query('SELECT * FROM Enemies'),
    pool.request().query('SELECT * FROM BossPhases ORDER BY BossEnemyId, PhaseNo'),
    pool.request().query('SELECT * FROM BossAttackPatterns'),
    pool.request().query('SELECT * FROM Stages'),
    pool.request().query('SELECT * FROM StageWaves ORDER BY StageId, StartMinute'),
    pool.request().query('SELECT * FROM StageEvents ORDER BY StageId, StartAtSec'),
    pool.request().query('SELECT * FROM ExpLevelCurves ORDER BY InRunLevel'),
    pool.request().query('SELECT * FROM HeroUpgradeConfigs'),
  ]);

  res.json({
    maxLevelCap: 300,
    bossRoomLevelInterval: 20,
    miniBossIntervalSec: 300,
    finalBossRoomTriggerSec: 1800,
    heroes: heroes.recordset,
    skills: skills.recordset,
    skillLevels: skillLevels.recordset,
    passives: passives.recordset,
    enemies: enemies.recordset,
    bossPhases: bossPhases.recordset,
    bossPatterns: bossPatterns.recordset,
    stages: stages.recordset,
    waves: waves.recordset,
    stageEvents: stageEvents.recordset,
    expCurves: expCurves.recordset,
    upgradeConfigs: upgradeConfigs.recordset,
  });
}));

// 2. Đăng ký tài khoản mới
app.post('/api/users/register', asyncHandler(async (req, res) => {
  const { username, password, displayName, email } = req.body;
  const pool = await poolPromise;

  const check = await pool.request()
    .input('Username', sql.VarChar(50), username)
    .query('SELECT UserId FROM Users WHERE Username = @Username');
  if (check.recordset.length > 0) {
    return res.status(409).json({ success: false, message: 'Tên đăng nhập đã tồn tại!' });
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const transaction = new sql.Transaction(pool);
  await transaction.begin();

  try {
    const userRes = await new sql.Request(transaction)
      .input('Username', sql.VarChar(50), username)
      .input('Email', sql.VarChar(100), email || null)
      .input('PasswordHash', sql.VarChar(255), passwordHash)
      .query(`
        INSERT INTO Users (Username, Email, PasswordHash, AccountType, AccountStatus)
        OUTPUT INSERTED.UserId, INSERTED.Username
        VALUES (@Username, @Email, @PasswordHash, 'REGISTERED', 'ACTIVE')
      `);
    const userId = userRes.recordset[0].UserId;

    await new sql.Request(transaction)
      .input('UserId', sql.Int, userId)
      .input('DisplayName', sql.NVarChar(50), displayName || username)
      .query(`
        INSERT INTO UserProfiles (UserId, DisplayName, AvatarKey) VALUES (@UserId, @DisplayName, 'avatar_default');
        INSERT INTO UserSettings (UserId) VALUES (@UserId);
        INSERT INTO UserWallets (UserId, CurrencyType, Balance, TotalEarned) VALUES
          (@UserId, 'GOLD', 1000, 1000),
          (@UserId, 'GEMS', 300, 300);
        INSERT INTO UserHeroes (UserId, HeroId, PickedStartingSkill1Id) VALUES (@UserId, 1, 1);
      `);

    await transaction.commit();
    res.json({ success: true, userId, username, displayName: displayName || username });
  } catch (err) {
    await transaction.rollback();
    throw err;
  }
}));

// 3. Đăng nhập
app.post('/api/users/login', asyncHandler(async (req, res) => {
  const { username, password } = req.body;
  const pool = await poolPromise;
  const result = await pool.request()
    .input('Username', sql.VarChar(50), username)
    .query('SELECT UserId, Username, PasswordHash, AccountStatus FROM Users WHERE Username = @Username');

  const user = result.recordset[0];
  if (!user || !(await bcrypt.compare(password, user.PasswordHash))) {
    return res.status(401).json({ success: false, message: 'Sai tài khoản hoặc mật khẩu!' });
  }
  res.json({ success: true, userId: user.UserId, username: user.Username });
}));

// 4. Lấy hồ sơ Sảnh chờ (Lobby Profile)
app.get('/api/users/:userId/lobby', asyncHandler(async (req, res) => {
  const userId = parseInt(req.params.userId, 10);
  const pool = await poolPromise;

  const [profile, wallets, heroes, upgrades, inventory, equipped] = await Promise.all([
    pool.request().input('UserId', sql.Int, userId).query('SELECT u.UserId, u.Username, up.* FROM Users u JOIN UserProfiles up ON u.UserId = up.UserId WHERE u.UserId = @UserId'),
    pool.request().input('UserId', sql.Int, userId).query('SELECT CurrencyType, Balance FROM UserWallets WHERE UserId = @UserId'),
    pool.request().input('UserId', sql.Int, userId).query('SELECT uh.*, h.HeroCode, h.HeroName FROM UserHeroes uh JOIN Heroes h ON uh.HeroId = h.HeroId WHERE uh.UserId = @UserId'),
    pool.request().input('UserId', sql.Int, userId).query('SELECT uhl.* FROM UserHeroUpgradeLevels uhl JOIN UserHeroes uh ON uhl.HeroInstanceId = uh.HeroInstanceId WHERE uh.UserId = @UserId'),
    pool.request().input('UserId', sql.Int, userId).query('SELECT ue.*, et.ItemCode, et.ItemName, et.EquipSlot FROM UserEquipments ue JOIN EquipmentTemplates et ON ue.TemplateId = et.TemplateId WHERE ue.UserId = @UserId'),
    pool.request().input('UserId', sql.Int, userId).query('SELECT hei.* FROM HeroEquippedItems hei JOIN UserHeroes uh ON hei.HeroInstanceId = uh.HeroInstanceId WHERE uh.UserId = @UserId'),
  ]);

  res.json({
    profile: profile.recordset[0],
    wallets: wallets.recordset,
    heroes: heroes.recordset,
    upgrades: upgrades.recordset,
    inventory: inventory.recordset,
    equipped: equipped.recordset,
  });
}));

// 5. Nâng cấp 15 ô chỉ số Hero (sp_UpgradeHeroStat)
app.post('/api/heroes/upgrade', asyncHandler(async (req, res) => {
  const { userId, heroId, upgradeCode, requestId } = req.body;
  const pool = await poolPromise;
  const result = await pool.request()
    .input('UserId', sql.Int, userId)
    .input('HeroId', sql.Int, heroId)
    .input('UpgradeCode', sql.VarChar(30), upgradeCode)
    .input('RequestId', sql.VarChar(64), requestId || `upg_${Date.now()}`)
    .execute('sp_UpgradeHeroStat');
  res.json(result.recordset[0]);
}));

// 6. Bắt đầu ván chơi (sp_StartRun)
app.post('/api/game/runs/start', asyncHandler(async (req, res) => {
  const { userId, heroId, stageId, gameMode } = req.body;
  const pool = await poolPromise;
  const result = await pool.request()
    .input('UserId', sql.Int, userId)
    .input('HeroId', sql.Int, heroId)
    .input('StageId', sql.Int, stageId || 1)
    .input('GameMode', sql.VarChar(15), gameMode || 'SOLO')
    .execute('sp_StartRun');

  const runSnapshot = result.recordsets[0][0];
  const validSkillPool = result.recordsets[1];

  if (runSnapshot && runSnapshot.RunId) {
    await pool.request()
      .input('RunId', sql.BigInt, runSnapshot.RunId)
      .input('Snapshot', sql.NVarChar(sql.MAX), JSON.stringify(runSnapshot))
      .query('UPDATE GameRuns SET StatSnapshotJson = @Snapshot WHERE RunId = @RunId');
  }

  res.json({ runSnapshot, validSkillPool });
}));

// 7. Kết thúc ván chơi khi nhân vật chết (sp_FinishRun)
app.post('/api/game/runs/finish', asyncHandler(async (req, res) => {
  const {
    runId, userId, requestId, endState, survivalTimeSec, wavesCleared,
    levelReached, totalKills, bossesKilled, totalDamageDealt, goldEarned, skills, passives
  } = req.body;

  const pool = await poolPromise;
  const result = await pool.request()
    .input('RunId', sql.BigInt, runId)
    .input('UserId', sql.Int, userId)
    .input('RequestId', sql.VarChar(64), requestId || `fin_${Date.now()}`)
    .input('EndState', sql.VarChar(20), endState || 'DEAD')
    .input('SurvivalTimeSec', sql.Int, survivalTimeSec)
    .input('WavesCleared', sql.Int, wavesCleared)
    .input('LevelReached', sql.Int, levelReached)
    .input('TotalKills', sql.Int, totalKills)
    .input('BossesKilled', sql.Int, bossesKilled)
    .input('TotalDamageDealt', sql.BigInt, totalDamageDealt)
    .input('GoldEarned', sql.Int, goldEarned)
    .input('SkillsJson', sql.NVarChar(sql.MAX), JSON.stringify(skills || []))
    .input('PassivesJson', sql.NVarChar(sql.MAX), JSON.stringify(passives || []))
    .execute('sp_FinishRun');

  res.json(result.recordset[0]);
}));

// 8. Lấy Bảng xếp hạng (sp_GetLeaderboard)
app.get('/api/leaderboard', asyncHandler(async (req, res) => {
  const { stageId = 1, gameMode = 'SOLO', heroId = null, page = 1, limit = 50 } = req.query;
  const pool = await poolPromise;
  const result = await pool.request()
    .input('StageId', sql.Int, Number(stageId))
    .input('GameMode', sql.VarChar(15), String(gameMode))
    .input('HeroId', sql.Int, heroId ? Number(heroId) : null)
    .input('PageNumber', sql.Int, Number(page))
    .input('PageSize', sql.Int, Number(limit))
    .execute('sp_GetLeaderboard');

  res.json(result.recordset);
}));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server đang chạy tại: http://localhost:${PORT}`);
});