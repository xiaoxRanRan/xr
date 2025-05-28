#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "2.7"

// 插件信息
public Plugin myinfo = {
    name = "L4D2 牛牛切换",
    author = "染一", 
    description = "允许灵魂状态牛牛玩家使用右键切换高速牛牛/普通牛牛",
    version = PLUGIN_VERSION,
    url = ""
};

// 全局变量
bool g_bHighSpeedMode[MAXPLAYERS + 1] = {false, ...};
bool g_bIsCharging[MAXPLAYERS + 1] = {false, ...};
bool g_bRightClickPressed[MAXPLAYERS + 1] = {false, ...};
bool g_bIncapped[MAXPLAYERS + 1] = {false, ...};
bool g_bGettingUp[MAXPLAYERS + 1] = {false, ...}; // 新增：标记是否正在起身
float g_fCharge[MAXPLAYERS + 1];
float g_fThrown[MAXPLAYERS + 1];
float g_fLandPosition[MAXPLAYERS + 1][3]; // 新增：记录落地位置
float g_fChargerInitialDirection[MAXPLAYERS + 1][3]; // 记录牛牛初始冲锋方向
float g_fChargerInitialAngles[MAXPLAYERS + 1][3];    // 记录牛牛初始角度
bool g_bPositionLocked[MAXPLAYERS + 1] = {false, ...}; // 标记位置是否被锁定
Handle g_hPositionTimer[MAXPLAYERS + 1] = {null, ...}; // 位置监控定时器句柄
float g_fAnimEndTime[MAXPLAYERS + 1] = {0.0, ...}; // 记录动画结束时间
bool g_bAnimEnded[MAXPLAYERS + 1] = {false, ...};   // 标记动画是否已结束

// ConVar句柄
ConVar g_cvChargeStartSpeed;
ConVar g_cvChargeMaxSpeed;
ConVar g_cvChargeInterval;

// 高速模式功能ConVars
ConVar g_cvEnhancedDamage;
ConVar g_cvEnhancedFinish;
ConVar g_cvEnhancedMaxSpeed;
ConVar g_cvEnhancedStartSpeed;
ConVar g_cvEnhancedKnockHeight; // 新增：击飞高度

// 存储原始值
float g_fOriginalStartSpeed;
float g_fOriginalMaxSpeed;

// 配置值
float g_fEnhancedStartSpeed = 200.0;
float g_fEnhancedMaxSpeed = 1000.0;
int g_iEnhancedDamage = 25;
int g_iEnhancedFinish = 1;
int g_iChargeInterval;
float g_fEnhancedKnockHeight = 250.0; // 新增：击飞高度

// SDK调用
Handle g_hSDK_OnPummelEnded;
Handle g_hSDK_OnStartCarryingVictim;

public void OnPluginStart() {
    // 获取游戏ConVars
    g_cvChargeStartSpeed = FindConVar("z_charge_start_speed");
    g_cvChargeMaxSpeed = FindConVar("z_charge_max_speed");
    g_cvChargeInterval = FindConVar("z_charge_interval");
    
    if (g_cvChargeStartSpeed == null || g_cvChargeMaxSpeed == null || g_cvChargeInterval == null) {
        SetFailState("Could not find required ConVars");
    }
    
    // 存储原始值
    g_fOriginalStartSpeed = g_cvChargeStartSpeed.FloatValue;
    g_fOriginalMaxSpeed = g_cvChargeMaxSpeed.FloatValue;
    g_iChargeInterval = g_cvChargeInterval.IntValue;
    
    // 创建高速模式ConVars
    g_cvEnhancedDamage = CreateConVar("charger_enhanced_damage", "10", "Enhanced mode damage on collision", FCVAR_NOTIFY, true, 0.0, true, 1000.0);
    g_cvEnhancedFinish = CreateConVar("charger_enhanced_finish", "1", "Enhanced mode after charging. 0=Pummel. 1=Drop survivor. 2=Drop when incapped. 3=Both. 4=Continue carry", FCVAR_NOTIFY, true, 0.0, true, 4.0);
    g_cvEnhancedMaxSpeed = CreateConVar("charger_enhanced_max_speed", "1000.0", "Enhanced mode charger max speed", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
    g_cvEnhancedStartSpeed = CreateConVar("charger_enhanced_start_speed", "200.0", "Enhanced mode charger start speed", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
    g_cvEnhancedKnockHeight = CreateConVar("charger_enhanced_knock_height", "300.0", "Enhanced mode knock up height", FCVAR_NOTIFY, true, 50.0, true, 800.0); // 新增
    // 创建版本ConVar
    CreateConVar("charger_enhanced_version", PLUGIN_VERSION, "Enhanced Charger Mode Switcher plugin version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    // 自动生成配置文件
    AutoExecConfig(true, "enhanced_charger_mode");
    
    // Hook ConVar changes
    g_cvEnhancedDamage.AddChangeHook(OnConVarChanged);
    g_cvEnhancedFinish.AddChangeHook(OnConVarChanged);
    g_cvEnhancedMaxSpeed.AddChangeHook(OnConVarChanged);
    g_cvEnhancedStartSpeed.AddChangeHook(OnConVarChanged);
    g_cvEnhancedKnockHeight.AddChangeHook(OnConVarChanged); // 新增
    g_cvChargeInterval.AddChangeHook(OnConVarChanged);
    
    GetConVarValues();
    
    // 注册事件
    HookEvent("charger_charge_start", Event_ChargeStart);
    HookEvent("charger_charge_end", Event_ChargeEnd);
    HookEvent("charger_pummel_start", Event_PummelStart);
    HookEvent("charger_pummel_end", Event_PummelEnd);
    HookEvent("charger_carry_start", Event_CarryStart);
    HookEvent("charger_carry_end", Event_CarryEnd);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_incapacitated", Event_PlayerIncap);
    HookEvent("revive_success", Event_PlayerRevive);
    HookEvent("round_start", Event_RoundStart);
    
    // 注册命令
    RegConsoleCmd("sm_chargermode", Command_ChargerMode, "切换Charger模式");
    
    PrintToServer("[Enhanced Charger Mode] Plugin loaded successfully with Left4DHooks support!");
}

public void OnAllPluginsLoaded() {
    SetupSDKCalls();
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    GetConVarValues();
}

void GetConVarValues() {
    g_fEnhancedStartSpeed = g_cvEnhancedStartSpeed.FloatValue;
    g_fEnhancedMaxSpeed = g_cvEnhancedMaxSpeed.FloatValue;
    g_iEnhancedDamage = g_cvEnhancedDamage.IntValue;
    g_iEnhancedFinish = g_cvEnhancedFinish.IntValue;
    g_fEnhancedKnockHeight = g_cvEnhancedKnockHeight.FloatValue; // 新增
    g_iChargeInterval = g_cvChargeInterval.IntValue;
}

void SetupSDKCalls() {
    Handle hGameData = LoadGameConfigFile("l4d2_charger_action");
    if (hGameData == null) {
        LogError("Failed to load gamedata file: l4d2_charger_action");
        return;
    }
    
    // OnPummelEnded SDK调用
    StartPrepSDKCall(SDKCall_Player);
    if (PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTerrorPlayer::OnPummelEnded")) {
        PrepSDKCall_AddParameter(SDKType_String, SDKPass_ByRef);
        PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
        g_hSDK_OnPummelEnded = EndPrepSDKCall();
    }
    
    // OnStartCarryingVictim SDK调用
    StartPrepSDKCall(SDKCall_Player);
    if (PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTerrorPlayer::OnStartCarryingVictim")) {
        PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
        g_hSDK_OnStartCarryingVictim = EndPrepSDKCall();
    }
    
    delete hGameData;
}

// Left4DHooks前置钩子 - 阻止高速牛牛搬运并保持方向
public Action L4D2_OnStartCarryingVictim(int victim, int attacker) {
    if (!IsValidCharger(attacker) || !IsValidSurvivor(victim)) {
        return Plugin_Continue;
    }
    
    // 如果是高速牛牛模式,阻止搬运并产生保龄球效果
    if (g_bHighSpeedMode[attacker]) {
        // 恢复牛牛的冲锋方向(防止撞击改变方向)
        if (g_bIsCharging[attacker]) {
            float currentAngles[3];
            GetVectorAngles(g_fChargerInitialDirection[attacker], currentAngles);
            currentAngles[0] = g_fChargerInitialAngles[attacker][0]; // 保持俯仰角
            TeleportEntity(attacker, NULL_VECTOR, currentAngles, NULL_VECTOR);
        }
        
        // 造成撞击伤害
        if (g_iEnhancedDamage > 0) {
            SDKHooks_TakeDamage(victim, attacker, attacker, float(g_iEnhancedDamage), DMG_CLUB);
        }
        
        // 创建保龄球击飞效果
        CreateBowlingEffect(attacker, victim);
        
        return Plugin_Handled; // 阻止搬运
    }
    
    return Plugin_Continue;
}

// Left4DHooks前置钩子 - 修复撞墙致命BUG
public Action L4D2_OnSlammedSurvivor(int victim, int attacker, bool &bWallSlam, bool &bDeadlyCharge) {
    if (!IsValidCharger(attacker) || !IsValidSurvivor(victim)) {
        return Plugin_Continue;
    }
    
    // 如果是高速牛牛模式，防止致命伤害
    if (g_bHighSpeedMode[attacker]) {
        // 关键修复：阻止致命标记，防止瞬间倒地
        bDeadlyCharge = false; // 强制设为false，防止瞬间倒地
        
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

// Left4DHooks前置钩子 - 增强击飞效果并使用初始方向
public Action L4D2_OnPlayerFling(int client, int attacker, float vecDir[3]) {
    if (!IsValidCharger(attacker) || !IsValidSurvivor(client)) {
        return Plugin_Continue;
    }
    
    // 如果是高速牛牛造成的击飞,使用记录的初始方向
    if (g_bHighSpeedMode[attacker] && g_bIsCharging[attacker]) {
        // 使用记录的初始冲锋方向
        vecDir[0] = g_fChargerInitialDirection[attacker][0] * 1.5;
        vecDir[1] = g_fChargerInitialDirection[attacker][1] * 1.5;
        vecDir[2] = 50.0; // 适当的向上力
        
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

// 创建保龄球效果 - 使用初始方向
void CreateBowlingEffect(int attacker, int victim) {
    float attackerPos[3], victimPos[3], velocity[3];
    
    // 获取位置
    GetClientAbsOrigin(attacker, attackerPos);
    GetClientAbsOrigin(victim, victimPos);
    
    // 使用记录的初始冲锋方向,而不是当前方向
    float direction[3];
    direction[0] = g_fChargerInitialDirection[attacker][0];
    direction[1] = g_fChargerInitialDirection[attacker][1];
    direction[2] = 0.0;
    
    // 设置击飞速度
    velocity[0] = direction[0] * 500.0;
    velocity[1] = direction[1] * 500.0;
    velocity[2] = g_fEnhancedKnockHeight;
    
    // 应用击飞效果
    TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, velocity);
    
    // 使用Left4DHooks的Fling函数,也使用初始方向
    L4D2_CTerrorPlayer_Fling(victim, attacker, direction);
    
    // 开始精确的位置监控系统
    StartPositionLockSystem(victim);
    
    // 延迟应用眩晕效果
    CreateTimer(0.3, Timer_ApplyStagger, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

// 新的位置锁定系统
void StartPositionLockSystem(int client) {
    if (!IsValidSurvivor(client)) return;
    
    // 清理旧的定时器
    if (g_hPositionTimer[client] != null) {
        KillTimer(g_hPositionTimer[client]);
        g_hPositionTimer[client] = null;
    }
    
    g_bPositionLocked[client] = false;
    g_bGettingUp[client] = false;
    
    // 开始监控落地
    g_hPositionTimer[client] = CreateTimer(0.02, Timer_MonitorLanding_New, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}
// 新的落地监控 - 更精确
public Action Timer_MonitorLanding_New(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (!IsValidSurvivor(client)) {
        g_hPositionTimer[client] = null;
        return Plugin_Stop;
    }
    
    float velocity[3], position[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
    GetClientAbsOrigin(client, position);
    
    // 更严格的着地检测
    bool isOnGround = (GetEntityFlags(client) & FL_ONGROUND) != 0;
    float verticalVel = FloatAbs(velocity[2]);
    float horizontalVel = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    
    // 当垂直速度很小且在地面上时认为已落地
    if (isOnGround && verticalVel < 20.0 && horizontalVel < 150.0) {
        // 等待一小段时间确保完全稳定
        CreateTimer(0.05, Timer_LockPosition, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
        g_hPositionTimer[client] = null;
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}
// 锁定位置并开始起身监控
public Action Timer_LockPosition(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (!IsValidSurvivor(client)) {
        return Plugin_Stop;
    }
    
    float position[3];
    GetClientAbsOrigin(client, position);
    
    // 记录锁定位置
    g_fLandPosition[client] = position;
    g_bPositionLocked[client] = true;
    g_bGettingUp[client] = true;
    g_bAnimEnded[client] = false;        // 初始化动画结束标记
    g_fAnimEndTime[client] = 0.0;        // 初始化动画结束时间
    
    // 开始严格的起身位置监控
    g_hPositionTimer[client] = CreateTimer(0.02, Timer_StrictPositionControl, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    
    return Plugin_Stop;
}
// 严格的位置控制 - 修改解除锁定条件
public Action Timer_StrictPositionControl(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (!IsValidSurvivor(client) || !g_bPositionLocked[client]) {
        g_bPositionLocked[client] = false;
        g_bGettingUp[client] = false;
        g_bAnimEnded[client] = false;
        g_fAnimEndTime[client] = 0.0;
        g_hPositionTimer[client] = null;
        return Plugin_Stop;
    }
    
    // 检查是否还在地面上
    bool isOnGround = (GetEntityFlags(client) & FL_ONGROUND) != 0;
    if (!isOnGround) {
        g_bPositionLocked[client] = false;
        g_bGettingUp[client] = false;
        g_bAnimEnded[client] = false;
        g_fAnimEndTime[client] = 0.0;
        g_hPositionTimer[client] = null;
        return Plugin_Stop;
    }
    
    // 获取当前动画序列
    int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
    
    // 扩展的起身动画检测
    bool isGettingUpAnim = (
        sequence == 650 || sequence == 665 || sequence == 661 || 
        sequence == 651 || sequence == 554 || sequence == 551 ||
        sequence == 620 || sequence == 625 || sequence == 630 ||
        sequence == 635 || sequence == 640 || sequence == 645 ||
        sequence == 655 || sequence == 660 || sequence == 670 ||
        (sequence >= 620 && sequence <= 680) ||
        (sequence >= 540 && sequence <= 570) // 额外的动画范围
    );
    
    // 检查玩家输入
    int buttons = GetEntProp(client, Prop_Data, "m_nButtons");
    bool hasMovementInput = (buttons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)) != 0;
    
    float currentPos[3], velocity[3];
    GetClientAbsOrigin(client, currentPos);
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
    
    float distance = GetVectorDistance(currentPos, g_fLandPosition[client]);
    float horizontalSpeed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    float currentTime = GetGameTime();
    
    // 动画状态检测和时间记录
    if (isGettingUpAnim) {
        // 还在起身动画中，重置动画结束标记
        g_bAnimEnded[client] = false;
        g_fAnimEndTime[client] = 0.0;
    } else {
        // 不在起身动画中
        if (!g_bAnimEnded[client]) {
            // 第一次检测到动画结束，记录时间
            g_bAnimEnded[client] = true;
            g_fAnimEndTime[client] = currentTime;
        }
    }
    
    // 检查解除锁定的条件
    bool shouldUnlock = false;
    
    // 条件1：玩家主动移动（优先级最高）
    if (hasMovementInput && distance < 15.0) {
        shouldUnlock = true;
    }
    // 条件2：动画结束后0.5秒
    else if (g_bAnimEnded[client] && (currentTime - g_fAnimEndTime[client]) >= 0.5) {
        shouldUnlock = true;
    }
    
    // 如果满足解锁条件，解除位置锁定
    if (shouldUnlock) {
        g_bPositionLocked[client] = false;
        g_bGettingUp[client] = false;
        g_bAnimEnded[client] = false;
        g_fAnimEndTime[client] = 0.0;
        g_hPositionTimer[client] = null;
        return Plugin_Stop;
    }
    
    // 如果还需要保持锁定，继续位置控制
    if (isGettingUpAnim || distance > 5.0 || horizontalSpeed > 30.0) {
        // 只有在没有玩家输入或位置偏移过大时才强制锁定
        if (!hasMovementInput || distance > 15.0) {
            // 强制传送回锁定位置
            float lockPos[3];
            lockPos[0] = g_fLandPosition[client][0];
            lockPos[1] = g_fLandPosition[client][1];
            lockPos[2] = g_fLandPosition[client][2];
            
            // 完全停止移动
            float zeroVel[3] = {0.0, 0.0, 0.0};
            TeleportEntity(client, lockPos, NULL_VECTOR, zeroVel);
        }
    }
    
    return Plugin_Continue;
}
// 延迟的保龄球效果
public Action Timer_DelayedBowlingEffect(Handle timer, int userid) {
    int victim = GetClientOfUserId(userid);
    if (!IsValidSurvivor(victim)) {
        return Plugin_Stop;
    }
    
    // 额外的击飞效果
    float velocity[3];
    GetEntPropVector(victim, Prop_Data, "m_vecVelocity", velocity);
    
    // 如果速度太小，再次施加力
    if (GetVectorLength(velocity) < 200.0) {
        velocity[0] += GetRandomFloat(-100.0, 100.0);
        velocity[1] += GetRandomFloat(-100.0, 100.0);
        velocity[2] += 150.0;
        
        TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, velocity);
    }
    
    return Plugin_Stop;
}

// 应用眩晕效果
public Action Timer_ApplyStagger(Handle timer, int userid) {
    int victim = GetClientOfUserId(userid);
    if (!IsValidSurvivor(victim)) {
        return Plugin_Stop;
    }
    
    // 使用Left4DHooks的眩晕函数
    L4D_StaggerPlayer(victim, victim, NULL_VECTOR);
    
    return Plugin_Stop;
}


// 玩家按键处理
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
    if (!IsValidCharger(client) || IsFakeClient(client)) {
        return Plugin_Continue;
    }
    
    // 灵魂状态下的模式切换
    if (IsGhostCharger(client)) {
        bool rightClickNow = (buttons & IN_ATTACK2) ? true : false;
        if (rightClickNow && !g_bRightClickPressed[client]) {
            ToggleChargerMode(client);
        }
        g_bRightClickPressed[client] = rightClickNow;
    }
    
    return Plugin_Continue;
}

// 事件处理
public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    ResetAllPlayers();
}

public void Event_ChargeStart(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidCharger(client)) return;
    
    g_bIsCharging[client] = true;
    g_fCharge[client] = GetGameTime();
    
    // 记录牛牛的初始冲锋方向和角度
    GetClientEyeAngles(client, g_fChargerInitialAngles[client]);
    GetAngleVectors(g_fChargerInitialAngles[client], g_fChargerInitialDirection[client], NULL_VECTOR, NULL_VECTOR);
    g_fChargerInitialDirection[client][2] = 0.0; // 保持水平方向
    NormalizeVector(g_fChargerInitialDirection[client], g_fChargerInitialDirection[client]);
    
    if (g_bHighSpeedMode[client]) {
        // 高速牛牛模式
        g_cvChargeStartSpeed.SetFloat(g_fEnhancedStartSpeed);
        g_cvChargeMaxSpeed.SetFloat(g_fEnhancedMaxSpeed);
    } else {
        // 普通模式
        g_cvChargeStartSpeed.SetFloat(g_fOriginalStartSpeed);
        g_cvChargeMaxSpeed.SetFloat(g_fOriginalMaxSpeed);
    }
}

public void Event_ChargeEnd(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    g_fThrown[client] = GetGameTime() + 0.5;
    g_bIsCharging[client] = false;
    
    // 清理方向记录
    g_fChargerInitialDirection[client][0] = 0.0;
    g_fChargerInitialDirection[client][1] = 0.0;
    g_fChargerInitialDirection[client][2] = 0.0;
    
    // 恢复原始速度设置
    g_cvChargeStartSpeed.SetFloat(g_fOriginalStartSpeed);
    g_cvChargeMaxSpeed.SetFloat(g_fOriginalMaxSpeed);
}

public void Event_CarryStart(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    
    // 这个事件在高速模式下应该被阻止，但以防万一还是处理伤害
    if (g_bHighSpeedMode[client] && g_iEnhancedDamage && GetGameTime() > g_fThrown[victim]) {
        g_fThrown[victim] = GetGameTime() + 1.0;
        SDKHooks_TakeDamage(victim, client, client, float(g_iEnhancedDamage), DMG_CLUB);
    }
}

public void Event_PummelStart(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (g_bHighSpeedMode[client] && g_iEnhancedFinish & (1<<0)) {
        if (GetGameTime() > g_fThrown[client]) {
            int target = GetEntPropEnt(client, Prop_Send, "m_pummelVictim");
            if (IsValidSurvivor(target)) {
                DropVictim(client, target);
            }
        }
    } else if (g_bHighSpeedMode[client] && g_iEnhancedFinish == 4) {
        // 继续携带模式 - 但在高速模式下不应该发生
        int target = GetEntPropEnt(client, Prop_Send, "m_pummelVictim");
        if (IsValidSurvivor(target) && GetGameTime() > g_fThrown[client]) {
            SetEntPropEnt(client, Prop_Send, "m_carryVictim", -1);
            SetEntPropEnt(target, Prop_Send, "m_carryAttacker", -1);
            if (g_hSDK_OnPummelEnded != null) {
                SDKCall(g_hSDK_OnPummelEnded, client, "", target);
            }
            
            g_bIncapped[target] = GetEntProp(target, Prop_Send, "m_isIncapacitated", 1) == 1;
            if (g_bIncapped[target]) {
                SetEntProp(target, Prop_Send, "m_isIncapacitated", 0, 1);
            }
            
            g_fThrown[client] = GetGameTime() + 0.8;
            if (g_hSDK_OnStartCarryingVictim != null) {
                SDKCall(g_hSDK_OnStartCarryingVictim, client, target);
            }
            
            float time = g_iChargeInterval - (GetGameTime() - g_fCharge[client]);
            if (time < 1.0) time = 1.0;
            SetWeaponAttack(client, true, time);
            SetWeaponAttack(client, false, 0.6);
        }
    }
}

public void Event_PummelEnd(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("victim"));
    if (g_bIncapped[client]) {
        SetEntProp(client, Prop_Send, "m_isIncapacitated", 1, 1);
    }
}

public void Event_CarryEnd(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("victim"));
    if (g_bIncapped[client]) {
        SetEntProp(client, Prop_Send, "m_isIncapacitated", 1, 1);
    }
}

public void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast) {
    if (g_iEnhancedFinish & (1<<1)) {
        int target = GetClientOfUserId(event.GetInt("userid"));
        int client = GetClientOfUserId(event.GetInt("attacker"));
        
        if (IsValidCharger(client) && g_bHighSpeedMode[client] && IsValidSurvivor(target)) {
            DropVictim(client, target);
        }
    }
}

public void Event_PlayerRevive(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("subject"));
    g_bIncapped[client] = false;
}

// 修改的玩家生成事件
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    // 重置状态
    g_bIsCharging[client] = false;
    g_bRightClickPressed[client] = false;
    g_bIncapped[client] = false;
    g_bGettingUp[client] = false;
    g_bPositionLocked[client] = false;
    g_bAnimEnded[client] = false;        // 重置动画结束标记
    g_fAnimEndTime[client] = 0.0;        // 重置动画结束时间
    g_fCharge[client] = 0.0;
    g_fThrown[client] = 0.0;
    
    // 清理定时器
    if (g_hPositionTimer[client] != null) {
        KillTimer(g_hPositionTimer[client]);
        g_hPositionTimer[client] = null;
    }
    
    if (IsGhostCharger(client)) {
        CreateTimer(2.0, Timer_ShowModeOnSpawn, GetClientUserId(client));
    }
    
    // 设置Charger生命值
    if (IsValidCharger(client) && !GetEntProp(client, Prop_Send, "m_isGhost")) {
        CreateTimer(0.1, Timer_SetChargerHealth, GetClientUserId(client));
    }
}

// 设置Charger生命值
public Action Timer_SetChargerHealth(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (!IsValidCharger(client) || GetEntProp(client, Prop_Send, "m_isGhost")) {
        return Plugin_Stop;
    }
    
    if (g_bHighSpeedMode[client]) {
        // 高速牛牛设置400血量
        SetEntityHealth(client, 400);
    } 
    
    return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    // 死亡时重置所有状态
    ResetPlayerVars(client);
    
    g_cvChargeStartSpeed.SetFloat(g_fOriginalStartSpeed);
    g_cvChargeMaxSpeed.SetFloat(g_fOriginalMaxSpeed);
}

// 定时器
public Action Timer_ShowModeOnSpawn(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (!IsGhostCharger(client)) return Plugin_Stop;
    
    if (g_bHighSpeedMode[client]) {
        PrintToChat(client, "\x04[Charger Mode] \x01当前模式: \x05高速牛牛");
    } else {
        PrintToChat(client, "\x04[Charger Mode] \x01当前模式: \x05普通牛牛");
    }
    PrintToChat(client, "\x04[Charger Mode] \x01按右键或输入 \x03!chargermode \x01切换模式");
    
    return Plugin_Stop;
}

// 命令处理
public Action Command_ChargerMode(int client, int args) {
    if (!IsGhostCharger(client)) {
        if (IsValidClient(client)) {
            PrintToChat(client, "\x04[Charger Mode] \x01只有灵魂状态的Charger可以使用此命令!");
        }
        return Plugin_Handled;
    }
    
    ToggleChargerMode(client);
    return Plugin_Handled;
}

void ToggleChargerMode(int client) {
    if (!IsGhostCharger(client)) return;
    
    g_bHighSpeedMode[client] = !g_bHighSpeedMode[client];
    
    if (g_bHighSpeedMode[client]) {
        PrintToChat(client, "\x04[Charger Mode] \x01切换到: \x05高速牛牛");
    } else {
        PrintToChat(client, "\x04[Charger Mode] \x01切换到: \x05普通牛牛");
    }
}

// 客户端管理
public void OnClientPostAdminCheck(int client) {
    ResetPlayerVars(client);
}

public void OnClientDisconnect(int client) {
    ResetPlayerVars(client);
}

// 辅助函数
void ResetAllPlayers() {
    for (int i = 1; i <= MaxClients; i++) {
        ResetPlayerVars(i);
    }
}

void ResetPlayerVars(int client) {
    g_bHighSpeedMode[client] = false;
    g_bIsCharging[client] = false;
    g_bRightClickPressed[client] = false;
    g_bIncapped[client] = false;
    g_bGettingUp[client] = false;
    g_bPositionLocked[client] = false;
    g_bAnimEnded[client] = false;        // 重置动画结束标记
    g_fAnimEndTime[client] = 0.0;        // 重置动画结束时间
    g_fCharge[client] = 0.0;
    g_fThrown[client] = 0.0;
    
    // 清理方向记录
    g_fChargerInitialDirection[client][0] = 0.0;
    g_fChargerInitialDirection[client][1] = 0.0;
    g_fChargerInitialDirection[client][2] = 0.0;
    g_fChargerInitialAngles[client][0] = 0.0;
    g_fChargerInitialAngles[client][1] = 0.0;
    g_fChargerInitialAngles[client][2] = 0.0;
    
    // 清理定时器
    if (g_hPositionTimer[client] != null) {
        KillTimer(g_hPositionTimer[client]);
        g_hPositionTimer[client] = null;
    }
}

void DropVictim(int client, int target) {
    if (g_hSDK_OnPummelEnded != null) {
        SDKCall(g_hSDK_OnPummelEnded, client, "", target);
    }
    
    float time = g_iChargeInterval - (GetGameTime() - g_fCharge[client]);
    if (time < 1.0) time = 1.0;
    
    SetWeaponAttack(client, true, time);
    SetWeaponAttack(client, false, 0.6);
    
    SetEntPropEnt(client, Prop_Send, "m_carryVictim", -1);
    SetEntPropEnt(target, Prop_Send, "m_carryAttacker", -1);
    
    bool incap = GetEntProp(target, Prop_Send, "m_isIncapacitated", 1) == 1;
    
    if (g_bIncapped[target] && !incap) {
        SetEntProp(target, Prop_Send, "m_isIncapacitated", 1, 1);
    }
    
    // 位置处理
    float vPos[3];
    vPos[0] = incap ? 20.0 : 50.0;
    SetVariantString("!activator");
    AcceptEntityInput(target, "SetParent", client);
    TeleportEntity(target, vPos, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(target, "ClearParent");
    
    CreateTimer(0.3, Timer_FixAnim, GetClientUserId(target));
    
    // 触发事件
    Event hEvent = CreateEvent("charger_carry_end");
    if (hEvent) {
        hEvent.SetInt("userid", GetClientUserId(client));
        hEvent.SetInt("victim", GetClientUserId(target));
        hEvent.Fire();
    }
    
    SetEntityMoveType(client, MOVETYPE_WALK);
    SetEntityMoveType(target, MOVETYPE_WALK);
    
    g_fThrown[target] = GetGameTime() + 0.5;
}

public Action Timer_FixAnim(Handle timer, int target) {
    target = GetClientOfUserId(target);
    if (!IsValidClient(target) || !IsPlayerAlive(target)) return Plugin_Continue;
    
    int seq = GetEntProp(target, Prop_Send, "m_nSequence");
    if (seq == 650 || seq == 665 || seq == 661 || seq == 651 || seq == 554 || seq == 551) {
        float vPos[3];
        GetClientAbsOrigin(target, vPos);
        SetEntityMoveType(target, MOVETYPE_WALK);
        TeleportEntity(target, vPos, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
    }
    
    return Plugin_Continue;
}

void SetWeaponAttack(int client, bool primary, float time) {
    if (primary) {
        int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
        if (ability != -1) {
            if (GetEntPropFloat(ability, Prop_Send, "m_timestamp") < GetGameTime() + time)
                SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + time);
        }
    }
    
    int weapon = GetPlayerWeaponSlot(client, 0);
    if (weapon != -1) {
        if (primary) SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + time);
        if (!primary) SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", GetGameTime() + time);
    }
}

bool IsValidClient(int client) {
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsValidCharger(int client) {
    return (IsValidClient(client) && 
            GetClientTeam(client) == 3 && 
            GetEntProp(client, Prop_Send, "m_zombieClass") == 6);
}

bool IsGhostCharger(int client) {
    return (IsValidClient(client) && 
            GetClientTeam(client) == 3 && 
            GetEntProp(client, Prop_Send, "m_zombieClass") == 6 &&
            GetEntProp(client, Prop_Send, "m_isGhost") == 1);
}

bool IsValidSurvivor(int client) {
    return (IsValidClient(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client));
}