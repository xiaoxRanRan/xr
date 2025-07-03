#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.2"

public Plugin myinfo = 
{
    name = "Hunter Ceiling Pitch Lock & Damage",
    author = "染一", 
    description = "锁定Hunter在天花板时的俯仰角并控制高扑伤害",
    version = PLUGIN_VERSION,
    url = ""
};

// 全局变量
ConVar g_hCvarEnabled;
ConVar g_hCvarMinPitch;
ConVar g_hCvarMaxPitch;
ConVar g_hCvarCheckDistance;

// 游戏ConVar句柄
ConVar g_hCvarHunterMaxPounceBonus;
ConVar g_hCvarPounceRangeMin;
ConVar g_hCvarPounceRangeMax;

bool g_bEnabled = true;
float g_fMinPitch = 11.55;
float g_fMaxPitch = 13.5;
float g_fCheckDistance = 80.0;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    CreateNative("IsHunterPitchLockEnabled", Native_IsEnabled);
    CreateNative("SetHunterPitchLockEnabled", Native_SetEnabled);
    RegPluginLibrary("hunter_pitch_lock");
    return APLRes_Success;
}

public void OnPluginStart()
{
    // 创建ConVar
    g_hCvarEnabled = CreateConVar("hunter_ceiling_enabled", "1", "启用或禁用Hunter天花板俯仰角锁定和伤害调整", FCVAR_NOTIFY);
    g_hCvarMinPitch = CreateConVar("hunter_ceiling_min_pitch", "11.55", "Hunter接触天花板时的最小俯仰角", FCVAR_NOTIFY);
    g_hCvarMaxPitch = CreateConVar("hunter_ceiling_max_pitch", "13.5", "Hunter接触天花板时的最大俯仰角", FCVAR_NOTIFY);
    g_hCvarCheckDistance = CreateConVar("hunter_ceiling_distance", "80.0", "检测天花板的最大距离", FCVAR_NOTIFY);
    
    // 监听ConVar变化
    g_hCvarEnabled.AddChangeHook(OnConVarChanged);
    g_hCvarMinPitch.AddChangeHook(OnConVarChanged);
    g_hCvarMaxPitch.AddChangeHook(OnConVarChanged);
    g_hCvarCheckDistance.AddChangeHook(OnConVarChanged);
    
    // Hook伤害事件
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
    
    // 获取初始值
    GetConVarValues();
    
    // 延迟设置ConVar以确保游戏完全加载
    CreateTimer(3.0, Timer_SetDamageValues);
    
    AutoExecConfig(true, "hunter_pitch_lock");
    PrintToServer("[Hunter Pitch Lock & Damage] Plugin loaded successfully");
}

public void OnMapStart()
{
    // 地图开始时重新设置伤害值
    CreateTimer(5.0, Timer_SetDamageValues);
}

public Action Timer_SetDamageValues(Handle timer)
{
    SetHunterDamageValues();
    return Plugin_Stop;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetConVarValues();
    
    if (convar == g_hCvarEnabled)
    {
        CreateTimer(0.1, Timer_SetDamageValues);
    }
}

void GetConVarValues()
{
    g_bEnabled = g_hCvarEnabled.BoolValue;
    g_fMinPitch = g_hCvarMinPitch.FloatValue;
    g_fMaxPitch = g_hCvarMaxPitch.FloatValue;
    g_fCheckDistance = g_hCvarCheckDistance.FloatValue;
}

void SetHunterDamageValues()
{
    // 获取ConVar句柄
    g_hCvarHunterMaxPounceBonus = FindConVar("z_hunter_max_pounce_bonus_damage");
    g_hCvarPounceRangeMin = FindConVar("z_pounce_damage_range_min");
    g_hCvarPounceRangeMax = FindConVar("z_pounce_damage_range_max");
    
    if (g_hCvarHunterMaxPounceBonus == null || 
        g_hCvarPounceRangeMin == null || 
        g_hCvarPounceRangeMax == null)
    {
        PrintToServer("[Hunter Damage] Warning: Could not find required ConVars, trying server commands");
        
        // 如果找不到ConVar，尝试使用服务器命令
        if (g_bEnabled)
        {
            ServerCommand("z_hunter_max_pounce_bonus_damage 14");
            ServerCommand("z_pounce_damage_range_min 300");
            ServerCommand("z_pounce_damage_range_max 708");
            PrintToServer("[Hunter Damage] Set via ServerCommand: Max damage = 15");
        }
        else
        {
            ServerCommand("z_hunter_max_pounce_bonus_damage 24");
            ServerCommand("z_pounce_damage_range_min 300");
            ServerCommand("z_pounce_damage_range_max 1000");
            PrintToServer("[Hunter Damage] Set via ServerCommand: Max damage = 25");
        }
        return;
    }
    
    if (g_bEnabled)
    {
        g_hCvarHunterMaxPounceBonus.SetInt(14, true, true);
        g_hCvarPounceRangeMin.SetInt(300, true, true);
        g_hCvarPounceRangeMax.SetInt(708, true, true);
        PrintToServer("[Hunter Damage] ConVar Set: Max damage = 15 (Bonus: %d, Min: %d, Max: %d)", 
                     g_hCvarHunterMaxPounceBonus.IntValue,
                     g_hCvarPounceRangeMin.IntValue,
                     g_hCvarPounceRangeMax.IntValue);
    }
    else
    {
        g_hCvarHunterMaxPounceBonus.SetInt(24, true, true);
        g_hCvarPounceRangeMin.SetInt(300, true, true);
        g_hCvarPounceRangeMax.SetInt(1000, true, true);
        PrintToServer("[Hunter Damage] ConVar Set: Max damage = 25 (Bonus: %d, Min: %d, Max: %d)",
                     g_hCvarHunterMaxPounceBonus.IntValue,
                     g_hCvarPounceRangeMin.IntValue,
                     g_hCvarPounceRangeMax.IntValue);
    }
}

// Hook伤害事件进行额外控制
public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("attacker"));
    
    if (!IsValidClient(attacker) || !IsValidClient(victim))
        return Plugin_Continue;
    
    if (!IsPlayerHunter(attacker))
        return Plugin_Continue;
    
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    
    // 检查是否为Hunter扑击伤害
    if (!StrEqual(weapon, "hunter_claw"))
        return Plugin_Continue;
    
    int damage = event.GetInt("dmg_health");
    int maxDamage = g_bEnabled ? 15 : 25;
    
    // 如果伤害超过限制，调整伤害
    if (damage > maxDamage)
    {
        event.SetInt("dmg_health", maxDamage);
        PrintToServer("[Hunter Damage] Limited damage from %d to %d", damage, maxDamage);
        return Plugin_Changed;
    }
    
    return Plugin_Continue;
}

// 原有的角度控制逻辑
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon)
{
    if (!g_bEnabled)
        return Plugin_Continue;
    
    if (!IsValidClient(client))
        return Plugin_Continue;
    
    if (!IsPlayerHunter(client))
        return Plugin_Continue;
    
    if (!IsNearCeiling(client))
        return Plugin_Continue;
    
    bool angleChanged = false;
    
    if (angles[0] < g_fMinPitch)
    {
        angles[0] = g_fMinPitch;
        angleChanged = true;
    }
    else if (angles[0] > g_fMaxPitch)
    {
        angles[0] = g_fMaxPitch;
        angleChanged = true;
    }
    
    return angleChanged ? Plugin_Changed : Plugin_Continue;
}

bool IsPlayerHunter(int client)
{
    if (GetClientTeam(client) != 3)
        return false;
    
    int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    return (zombieClass == 3);
}

bool IsNearCeiling(int client)
{
    float clientPos[3];
    GetClientAbsOrigin(client, clientPos);
    
    float endPos[3];
    endPos[0] = clientPos[0];
    endPos[1] = clientPos[1];
    endPos[2] = clientPos[2] + g_fCheckDistance;
    
    Handle trace = TR_TraceRayFilterEx(
        clientPos,
        endPos,
        MASK_SOLID,
        RayType_EndPoint,
        TraceFilter_IgnorePlayers,
        client
    );
    
    bool hitCeiling = false;
    
    if (TR_DidHit(trace))
    {
        // 添加表面标志检测
        int iSurf = TR_GetSurfaceFlags(trace);
        if((iSurf & SURF_NODRAW) || !(iSurf & SURF_SKY))
        {
            // 如果是不可见表面或不是天空，不触发锁定
            delete trace;
            return false;
        }
        
        float hitPos[3];
        TR_GetEndPosition(hitPos, trace);
        float distance = GetVectorDistance(clientPos, hitPos);
        
        if (distance < g_fCheckDistance)
        {
            float normal[3];
            TR_GetPlaneNormal(trace, normal);
            
            if (normal[2] < -0.7)
            {
                hitCeiling = true;
            }
        }
    }
    
    delete trace;
    return hitCeiling;
}

public bool TraceFilter_IgnorePlayers(int entity, int contentsMask, int client)
{
    return (entity > MaxClients || entity == 0);
}

bool IsValidClient(int client)
{
    return (client > 0 && 
            client <= MaxClients && 
            IsClientInGame(client) && 
            IsPlayerAlive(client) && 
            !IsFakeClient(client));
}

public int Native_IsEnabled(Handle plugin, int numParams)
{
    return g_bEnabled;
}

public int Native_SetEnabled(Handle plugin, int numParams)
{
    bool enabled = GetNativeCell(1);
    g_hCvarEnabled.SetBool(enabled);
    return 0;
}

public void OnPluginEnd()
{
    if (g_hCvarHunterMaxPounceBonus != null)
        g_hCvarHunterMaxPounceBonus.SetInt(24);
    if (g_hCvarPounceRangeMin != null)
        g_hCvarPounceRangeMin.SetInt(300);
    if (g_hCvarPounceRangeMax != null)
        g_hCvarPounceRangeMax.SetInt(1000);
}