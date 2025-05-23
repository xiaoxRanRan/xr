#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>     // 需要 sdktools
#include <left4dhooks> // 需要 left4dhooks
#include <colors>      // <--- 添加 colors include

#define PLUGIN_VERSION "2.2-SIConfig-TotalComp-VarCooldown-NoTank-Colors" // 更新版本标记
#define TEAM_INFECTED 3
#define TEAM_SURVIVOR 2
#define SAFE_ROOM_CHECK_INTERVAL 1.0

// --- 全局变量 ---
ConVar g_cvEnabled;
bool g_bIsVersus;
bool g_bLeftSafeRoom[MAXPLAYERS + 1];
bool g_bRoundLive;
bool g_bHasShownInitialInfo;
float g_fLastCommandTime;
Handle g_hSafeRoomTimer = null;
ConVar g_cvCommandCooldown;
bool g_bL4DHooksAvailable = false;

public Plugin myinfo =
{
    name = "L4D2 Infected Info (Total SI Comp - Colors)", // 更新名称
    author = "Your Name & ChatGPT",
    description = "Shows total Special Infected (excluding Tank) composition with colors. Requires L4DHooks.", // 更新描述
    version = PLUGIN_VERSION,
    url = "https://example.com"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkPluginAsRequired("left4dhooks");
    return APLRes_Success;
}

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    // HookEvent("player_team", Event_PlayerTeam);

    RegConsoleCmd("sm_specs", Command_Specs, "显示当前特感队伍构成(不含Tank)");
    RegConsoleCmd("sm_si", Command_Specs, "显示当前特感队伍构成(不含Tank)");
    RegConsoleCmd("sm_specinfo", Command_Specs, "显示当前特感队伍构成(同!specs, 不含Tank)");

    g_cvEnabled = CreateConVar("l4d2_infected_info_enabled", "1", "启用/禁用插件", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvCommandCooldown = CreateConVar("l4d2_infected_info_cooldown", "60.0", "查询特感构成命令的冷却时间(秒)", FCVAR_NONE, true, 0.0, true, 300.0);

    AutoExecConfig(true, "l4d2_infected_info_simplified");
}

public void OnAllPluginsLoaded()
{
    if (LibraryExists("left4dhooks") && GetFeatureStatus(FeatureType_Native, "L4D_IsVersusMode") == FeatureStatus_Available)
    {
        g_bL4DHooksAvailable = true;
        LogMessage("L4D2 Infected Info Plugin (v%s). L4DHooks detected (Required).", PLUGIN_VERSION);
    }
    else
    {
        g_bL4DHooksAvailable = false;
        SetFailState("Required extension 'left4dhooks' is not available or key natives like L4D_IsVersusMode are missing. Plugin disabled.");
        LogError("Required extension 'left4dhooks' is not available or key natives like L4D_IsVersusMode are missing. Plugin disabled.");
    }
}

// --- Map/Round/Player 事件处理 (不变) ---
public void OnMapStart()
{
    if (!g_bL4DHooksAvailable) return;
    g_bIsVersus = IsVersusMode();
    g_bRoundLive = false;
    g_bHasShownInitialInfo = false;
    g_fLastCommandTime = 0.0;
    ResetSafeRoomStatus();
}

public void OnMapEnd()
{
    if (g_hSafeRoomTimer != null)
    {
        KillTimer(g_hSafeRoomTimer);
        g_hSafeRoomTimer = null;
    }
}

public void OnClientDisconnect(int client)
{
    if (client > 0 && client <= MaxClients) {
        g_bLeftSafeRoom[client] = false;
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bL4DHooksAvailable) return;
    if (!g_cvEnabled.BoolValue || !IsVersusMode())
        return;

    g_bRoundLive = false;
    g_bHasShownInitialInfo = false;
    ResetSafeRoomStatus();

    if (g_hSafeRoomTimer != null)
    {
        KillTimer(g_hSafeRoomTimer);
        g_hSafeRoomTimer = null;
    }
    g_hSafeRoomTimer = CreateTimer(SAFE_ROOM_CHECK_INTERVAL, Timer_CheckSafeRoom, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bRoundLive = false;
    g_bHasShownInitialInfo = false;
    if (g_hSafeRoomTimer != null)
    {
        KillTimer(g_hSafeRoomTimer);
        g_hSafeRoomTimer = null;
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    // 无特定逻辑
}

// --- Timer_CheckSafeRoom (不变) ---
public Action Timer_CheckSafeRoom(Handle timer, any data)
{
    if (timer != g_hSafeRoomTimer || g_hSafeRoomTimer == null)
    {
        return Plugin_Stop;
    }

    if (g_bRoundLive)
    {
        g_hSafeRoomTimer = null;
        return Plugin_Stop;
    }

    bool survivorLeft = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client) && GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client))
        {
            if (!g_bLeftSafeRoom[client])
            {
                if (!IsPlayerInSafeRoom(client))
                {
                    g_bLeftSafeRoom[client] = true;
                    survivorLeft = true;
                    break;
                }
            }
            else
            {
                 survivorLeft = true;
            }
        }
    }

    if (survivorLeft && !g_bHasShownInitialInfo)
    {
        g_bHasShownInitialInfo = true;
        g_bRoundLive = true;
        ShowInitialInfectedInfo();
        g_hSafeRoomTimer = null;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}


// --- Command_Specs (添加颜色) --- // <<<<<-------- 主要修改点 --------->>>>
public Action Command_Specs(int client, int args)
{
    if (!g_bL4DHooksAvailable)
    {
         CReplyToCommand(client, "{darkred}[错误]{default} 插件依赖的核心扩展未加载。"); // 使用 CReplyToCommand
         LogError("Command blocked because L4DHooks is not available.");
         return Plugin_Handled;
    }

    if (!g_cvEnabled.BoolValue) return Plugin_Handled;
    if (!IsVersusMode()) return Plugin_Handled;
    if (!IsValidClient(client)) return Plugin_Handled;

    if (GetClientTeam(client) != TEAM_SURVIVOR)
    {
        CReplyToCommand(client, "{green}[提示]{default} 只有生还者可以使用此指令。"); // 使用 CReplyToCommand
        return Plugin_Handled;
    }

    float currentTime = GetEngineTime();
    float cooldown = g_cvCommandCooldown.FloatValue;
    if (g_fLastCommandTime > 0.0 && currentTime - g_fLastCommandTime < cooldown)
    {
        float remaining = cooldown - (currentTime - g_fLastCommandTime);
        // 使用 CReplyToCommand 和颜色标记
        CReplyToCommand(client, "{green}[提示]{default} 命令冷却中，请等待 {lightblue}%.1f秒{default}。", remaining);
        return Plugin_Handled;
    }

    g_fLastCommandTime = currentTime;

    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));

    char infoBuffer[512];
    GetInfectedInfoString(infoBuffer, sizeof(infoBuffer)); // 信息颜色在 GetInfectedInfoString 中处理

    // 使用 CPrintToChat 和颜色标记广播
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && GetClientTeam(i) == TEAM_SURVIVOR && !IsFakeClient(i))
        {
            // {teamcolor} 会根据接收玩家的队伍显示颜色，这里我们希望显示触发者的队伍颜色，所以用 {lightblue} 代替或直接用名字颜色
            CPrintToChat(i, "{green}[特感信息] {lightblue}%s{default} 查询了特感队伍构成:", playerName);
            CPrintToChat(i, " {default}%s", infoBuffer); // infoBuffer 自带颜色
        }
    }

    return Plugin_Handled;
}

// --- ShowInitialInfectedInfo (添加颜色) --- // <<<<<-------- 主要修改点 --------->>>>
void ShowInitialInfectedInfo()
{
    char infoBuffer[512];
    GetInfectedInfoString(infoBuffer, sizeof(infoBuffer)); // 信息颜色在 GetInfectedInfoString 中处理

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            // 使用 CPrintToChat 和颜色标记
            CPrintToChat(i, "{green}[开局提示]{default} 回合开始!");
            CPrintToChat(i, "{default}特感队伍构成: %s", infoBuffer); // infoBuffer 自带颜色
        }
    }
}

// --- GetInfectedInfoString (添加颜色) --- // <<<<<-------- 主要修改点 --------->>>>
void GetInfectedInfoString(char[] buffer, int maxlength)
{
    int smokerCount = 0;
    int boomerCount = 0;
    int hunterCount = 0;
    int spitterCount = 0;
    int jockeyCount = 0;
    int chargerCount = 0;
    // int tankCount = 0; // Tank 不显示
    int totalInfectedPlayers = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && GetClientTeam(i) == TEAM_INFECTED)
        {
            totalInfectedPlayers++;
            int zombieClass = GetEntProp(i, Prop_Send, "m_zombieClass");
            switch (zombieClass)
            {
                case 1: smokerCount++;
                case 2: boomerCount++;
                case 3: hunterCount++;
                case 4: spitterCount++;
                case 5: jockeyCount++;
                case 6: chargerCount++;
                // case 8: tankCount++; // 不统计 Tank
            }
        }
    }

    // 使用颜色标记格式化
    // {darkred} 通常显示为深灰色或橙色，用于总数
    // {green} 用于各个特感的数量
    // {default} 用于标签和分隔符
    Format(buffer, maxlength, "{default}总人数: {darkred}%d{default}", totalInfectedPlayers);
    Format(buffer, maxlength, "%s | {default}Smoker: {green}%d{default}", buffer, smokerCount);
    Format(buffer, maxlength, "%s | {default}Boomer: {green}%d{default}", buffer, boomerCount);
    Format(buffer, maxlength, "%s | {default}Hunter: {green}%d{default}", buffer, hunterCount);
    Format(buffer, maxlength, "%s | {default}Spitter: {green}%d{default}", buffer, spitterCount);
    Format(buffer, maxlength, "%s | {default}Jockey: {green}%d{default}", buffer, jockeyCount);
    Format(buffer, maxlength, "%s | {default}Charger: {green}%d{default}", buffer, chargerCount);
    // Format(buffer, maxlength, "%s | Tank: {darkred}%d{default}", buffer, tankCount); // Tank 不显示
}


// --- 辅助函数 (IsPlayerInSafeRoom, ResetSafeRoomStatus, IsVersusMode, IsValidClient 不变) ---
bool IsPlayerInSafeRoom(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return false;

    int trigger = FindEntityByClassname(-1, "trigger_safe_area");
    while (trigger != -1)
    {
        if (!IsValidEntity(trigger))
        {
           trigger = FindEntityByClassname(trigger, "trigger_safe_area");
           continue;
        }

        float origin[3];
        GetClientAbsOrigin(client, origin);
        float triggerOrigin[3];
        GetEntPropVector(trigger, Prop_Data, "m_vecOrigin", triggerOrigin);
        float mins[3], maxs[3];
        if (GetEntPropVector(trigger, Prop_Send, "m_vecMins", mins) &&
            GetEntPropVector(trigger, Prop_Send, "m_vecMaxs", maxs))
        {
             float worldMins[3], worldMaxs[3];
             AddVectors(triggerOrigin, mins, worldMins);
             AddVectors(triggerOrigin, maxs, worldMaxs);

             if (origin[0] >= worldMins[0] && origin[0] <= worldMaxs[0] &&
                 origin[1] >= worldMins[1] && origin[1] <= worldMaxs[1] &&
                 origin[2] >= worldMins[2] && origin[2] <= worldMaxs[2])
             {
                 return true;
             }
        }
        trigger = FindEntityByClassname(trigger, "trigger_safe_area");
    }

    float clientOrigin[3];
    GetClientAbsOrigin(client, clientOrigin);
    int startSaferoom = FindEntityByClassname(-1, "info_survivor_position");
    while (startSaferoom != -1)
    {
        if (!IsValidEntity(startSaferoom))
        {
             startSaferoom = FindEntityByClassname(startSaferoom, "info_survivor_position");
             continue;
        }
        float saferoomOrigin[3];
        GetEntPropVector(startSaferoom, Prop_Data, "m_vecOrigin", saferoomOrigin);
        if (GetVectorDistance(clientOrigin, saferoomOrigin, true) < 250.0 * 250.0)
        {
            return true;
        }
        startSaferoom = FindEntityByClassname(startSaferoom, "info_survivor_position");
    }

    return false;
}

void ResetSafeRoomStatus()
{
    for (int i = 0; i <= MaxClients; i++)
    {
        g_bLeftSafeRoom[i] = false;
    }
}

bool IsVersusMode()
{
    if (!g_bL4DHooksAvailable) {
        char gameMode[32];
        ConVar cvGameMode = FindConVar("mp_gamemode");
        if (cvGameMode != null) {
            cvGameMode.GetString(gameMode, sizeof(gameMode));
            return StrContains(gameMode, "versus", false) != -1 || StrContains(gameMode, "scavenge", false) != -1 || StrContains(gameMode, "mutation12", false) != -1 || StrContains(gameMode, "mutation14", false) != -1 || StrContains(gameMode, "mutation18", false) != -1;
        }
        return false;
    }
    return L4D_IsVersusMode();
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}

// End of file