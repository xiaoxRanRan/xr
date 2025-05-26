#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2.4"

// 插件信息
public Plugin myinfo = {
    name = "L4D2 牛牛切换",
    author = "Silvers & renyi,", 
    description = "允许灵魂状态牛牛玩家使用右键切换高速牛牛/普通牛牛",
    version = PLUGIN_VERSION,
    url = ""
};

// 全局变量
bool g_bHighSpeedMode[MAXPLAYERS + 1] = {false, ...};
bool g_bIsCharging[MAXPLAYERS + 1] = {false, ...};
bool g_bRightClickPressed[MAXPLAYERS + 1] = {false, ...};
bool g_bIncapped[MAXPLAYERS + 1] = {false, ...};
float g_fCharge[MAXPLAYERS + 1];
float g_fThrown[MAXPLAYERS + 1];

// ConVar句柄
ConVar g_cvChargeStartSpeed;
ConVar g_cvChargeMaxSpeed;
ConVar g_cvChargeInterval;

// 高速模式功能ConVars
ConVar g_cvEnhancedDamage;
ConVar g_cvEnhancedFinish;
ConVar g_cvEnhancedMaxSpeed;
ConVar g_cvEnhancedStartSpeed;

// 存储原始值
float g_fOriginalStartSpeed;
float g_fOriginalMaxSpeed;

// 配置值
float g_fEnhancedStartSpeed = 200.0;
float g_fEnhancedMaxSpeed = 1000.0;
int g_iEnhancedDamage = 10;
int g_iEnhancedFinish = 1;
int g_iChargeInterval;

// SDK调用
Handle g_hSDK_OnPummelEnded;

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
    g_cvEnhancedFinish = CreateConVar("charger_enhanced_finish", "1", "Enhanced mode after charging. 0=Pummel. 1=Drop survivor. 2=Drop when incapped.", FCVAR_NOTIFY, true, 0.0, true, 2.0);
    g_cvEnhancedMaxSpeed = CreateConVar("charger_enhanced_max_speed", "1000.0", "Enhanced mode charger max speed", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
    g_cvEnhancedStartSpeed = CreateConVar("charger_enhanced_start_speed", "200.0", "Enhanced mode charger start speed", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
    
    // 创建版本ConVar
    CreateConVar("charger_enhanced_version", PLUGIN_VERSION, "Enhanced Charger Mode Switcher plugin version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    // 自动生成配置文件
    AutoExecConfig(true, "enhanced_charger_mode");
    
    // Hook ConVar changes
    g_cvEnhancedDamage.AddChangeHook(OnConVarChanged);
    g_cvEnhancedFinish.AddChangeHook(OnConVarChanged);
    g_cvEnhancedMaxSpeed.AddChangeHook(OnConVarChanged);
    g_cvEnhancedStartSpeed.AddChangeHook(OnConVarChanged);
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
    
    PrintToServer("[Enhanced Charger Mode] Plugin loaded successfully!");
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    GetConVarValues();
}

void GetConVarValues() {
    g_fEnhancedStartSpeed = g_cvEnhancedStartSpeed.FloatValue;
    g_fEnhancedMaxSpeed = g_cvEnhancedMaxSpeed.FloatValue;
    g_iEnhancedDamage = g_cvEnhancedDamage.IntValue;
    g_iEnhancedFinish = g_cvEnhancedFinish.IntValue;
    g_iChargeInterval = g_cvChargeInterval.IntValue;
}

public void OnAllPluginsLoaded() {
    SetupSDKCalls();
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
    
    delete hGameData;
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
    
    if (g_bHighSpeedMode[client]) {
        // 高速牛牛模式
        g_cvChargeStartSpeed.SetFloat(g_fEnhancedStartSpeed);
        g_cvChargeMaxSpeed.SetFloat(g_fEnhancedMaxSpeed);
        
        PrintToChat(client, "\x04[Charger Mode] \x05高速牛牛冲锋开始!");
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
    
    // 恢复原始速度设置
    g_cvChargeStartSpeed.SetFloat(g_fOriginalStartSpeed);
    g_cvChargeMaxSpeed.SetFloat(g_fOriginalMaxSpeed);
}

public void Event_CarryStart(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    
    if (g_bHighSpeedMode[client] && g_iEnhancedDamage && GetGameTime() > g_fThrown[victim]) {
        g_fThrown[victim] = GetGameTime() + 1.0;
        HurtEntity(victim, client, g_iEnhancedDamage);
    }
}

public void Event_PummelStart(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (g_bHighSpeedMode[client] && g_iEnhancedFinish == 1) {
        if (GetGameTime() > g_fThrown[client]) {
            int target = GetEntPropEnt(client, Prop_Send, "m_pummelVictim");
            if (IsValidSurvivor(target)) {
                DropVictim(client, target);
            }
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
    if (g_iEnhancedFinish == 2) {
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

// 修改的玩家生成事件 - 添加生命值设置
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    // 不要重置模式状态，只重置其他变量
    g_bIsCharging[client] = false;
    g_bRightClickPressed[client] = false;
    g_bIncapped[client] = false;
    g_fCharge[client] = 0.0;
    g_fThrown[client] = 0.0;
    
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
        // 高速牛牛设置450血量
        SetEntityHealth(client, 450);
        PrintToChat(client, "\x04[Charger Mode] \x05高速牛牛生成! \x01血量: \x05450");
    }
    // 普通牛牛保持原样，不修改血量
    
    return Plugin_Stop;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client)) return;
    
    // 死亡时重置所有状态
    g_bIsCharging[client] = false;
    g_bRightClickPressed[client] = false;
    g_bIncapped[client] = false;
    g_fCharge[client] = 0.0;
    g_fThrown[client] = 0.0;
    
    g_cvChargeStartSpeed.SetFloat(g_fOriginalStartSpeed);
    g_cvChargeMaxSpeed.SetFloat(g_fOriginalMaxSpeed);
}

// 定时器
public Action Timer_ShowModeOnSpawn(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (!IsGhostCharger(client)) return Plugin_Stop;
    
    PrintToChat(client, "\x04[Charger Mode] \x01当前模式: \x05%s", 
              g_bHighSpeedMode[client] ? "高速牛牛" : "普通牛牛");
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
    
    PrintToChat(client, "\x04[Charger Mode] \x01当前模式: \x05%s", 
              g_bHighSpeedMode[client] ? "高速牛牛" : "普通牛牛");
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
    g_fCharge[client] = 0.0;
    g_fThrown[client] = 0.0;
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

void HurtEntity(int victim, int client, int damage) {
    SDKHooks_TakeDamage(victim, client, client, float(damage), DMG_CLUB);
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