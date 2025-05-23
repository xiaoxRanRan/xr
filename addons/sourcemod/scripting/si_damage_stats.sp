#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0" 

public Plugin myinfo =
{
    name = "Special Infected Damage Statistics",
    author = "AI",
    description = "显示特感玩家造成的伤害统计",
    version = PLUGIN_VERSION,
    url = ""
};

// 特感类型枚举
enum ZombieClass
{
    Smoker = 1,
    Boomer,
    Hunter,
    Spitter,
    Jockey,
    Charger,
    Tank,
    ZombieClass_Size
};

// 存储玩家伤害数据的结构
enum struct PlayerDamageStats
{
    int totalDamage;                       // 总伤害
    int damageByClass[ZombieClass_Size];   // 按特感类型分类的伤害
}

// 玩家数据存储
PlayerDamageStats g_PlayerStats[MAXPLAYERS + 1];
bool g_RoundEnded = false;
int g_LastBoomerAttacker = 0;               // 记录最后产生胆汁效果的Boomer玩家ID
float g_LastBoomerVomitTime[MAXPLAYERS+1];  // 记录每个生还者最后被该Boomer喷吐的时间

public void OnPluginStart()
{
    CreateConVar("sm_si_damage_stats_version", PLUGIN_VERSION, "Special Infected Damage Statistics Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);

    RegConsoleCmd("sm_simvp", Command_SiMVP, "显示当前回合特感伤害统计");

    HookEvent("round_end", Event_RoundEnd);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("player_death", Event_PlayerDeath);

    HookEventEx("player_now_it", Event_PlayerVomited);

    HookEventEx("hunter_pounce", Event_HunterPounce);
    HookEventEx("tongue_pull_stopped", Event_SmokerPullStopped);

    g_RoundEnded = false;
    ResetAllStats();
}

public Action Command_SiMVP(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        return Plugin_Handled;
    }
    PrintToChat(client, "\x04====== \x05特感伤害统计 \x04======");
    bool hasDamage = false;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            if (g_PlayerStats[i].totalDamage > 0) {
                hasDamage = true;
                char playerName[MAX_NAME_LENGTH];
                GetClientName(i, playerName, sizeof(playerName));
                char damageMessage[512] = "";
                Format(damageMessage, sizeof(damageMessage), "\x03%s\x01: ", playerName);
                bool firstClass = true;
                for (int class_idx = 1; class_idx < view_as<int>(ZombieClass_Size); class_idx++) {
                    if (g_PlayerStats[i].damageByClass[class_idx] > 0) {
                        char className[32];
                        GetInfectedClassName(view_as<ZombieClass>(class_idx), className, sizeof(className));
                        if (!firstClass) Format(damageMessage, sizeof(damageMessage), "%s \x01‖ ", damageMessage);
                        Format(damageMessage, sizeof(damageMessage), "%s\x05%s\x01: \x04%d", damageMessage, className, g_PlayerStats[i].damageByClass[class_idx]);
                        firstClass = false;
                    }
                }
                Format(damageMessage, sizeof(damageMessage), "%s \x01‖ \x01总伤害: \x04%d", damageMessage, g_PlayerStats[i].totalDamage);
                PrintToChat(client, damageMessage);
            }
        }
    }
    if (!hasDamage) PrintToChat(client, "\x01本回合特感未造成任何伤害!");
    PrintToChat(client, "\x04==============================");
    return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
    ResetClientStats(client);
}

public void OnMapStart()
{
    g_RoundEnded = false;
    ResetAllStats();
}

public void ResetAllStats()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        ResetClientStats(i);
        g_LastBoomerVomitTime[i] = 0.0;
    }
    g_LastBoomerAttacker = 0;
}

public void ResetClientStats(int client)
{
    if (client > 0 && client <= MaxClients)
    {
        g_PlayerStats[client].totalDamage = 0;
        for (int i = 0; i < view_as<int>(ZombieClass_Size); i++)
        {
            g_PlayerStats[client].damageByClass[i] = 0;
        }
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_RoundEnded = false;
    ResetAllStats();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (g_RoundEnded) return;
    g_RoundEnded = true;
    CreateTimer(2.0, Timer_DisplayStats);
}

public Action Timer_DisplayStats(Handle timer)
{
    PrintToChatAll("\x04====== \x05特感伤害统计 \x04======");
    bool hasDamage = false;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            if (g_PlayerStats[i].totalDamage > 0) {
                hasDamage = true;
                char playerName[MAX_NAME_LENGTH];
                GetClientName(i, playerName, sizeof(playerName));
                char damageMessage[512] = "";
                Format(damageMessage, sizeof(damageMessage), "\x03%s\x01: ", playerName);
                bool firstClass = true;
                for (int class_idx = 1; class_idx < view_as<int>(ZombieClass_Size); class_idx++) {
                    if (g_PlayerStats[i].damageByClass[class_idx] > 0) {
                        char className[32];
                        GetInfectedClassName(view_as<ZombieClass>(class_idx), className, sizeof(className));
                        if (!firstClass) Format(damageMessage, sizeof(damageMessage), "%s \x01‖ ", damageMessage);
                        Format(damageMessage, sizeof(damageMessage), "%s\x05%s\x01: \x04%d", damageMessage, className, g_PlayerStats[i].damageByClass[class_idx]);
                        firstClass = false;
                    }
                }
                Format(damageMessage, sizeof(damageMessage), "%s \x01‖ \x01总伤害: \x04%d", damageMessage, g_PlayerStats[i].totalDamage);
                PrintToChatAll(damageMessage);
            }
        }
    }
    if (!hasDamage) PrintToChatAll("\x01本回合特感未造成任何伤害!");
    PrintToChatAll("\x04==============================");
    return Plugin_Stop;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker_userid = event.GetInt("attacker");
    int victim_client = GetClientOfUserId(event.GetInt("userid"));
    int attacker_client = GetClientOfUserId(attacker_userid);
    int damage = event.GetInt("dmg_health");
    char damageType[32];
    event.GetString("type", damageType, sizeof(damageType));

    if (IsValidInfectedPlayer(attacker_client) && IsValidSurvivorPlayer(victim_client))
    {
        ZombieClass zombieClass = GetInfectedClass(attacker_client);
        if (zombieClass != view_as<ZombieClass>(0))
        {
            g_PlayerStats[attacker_client].totalDamage += damage;
            g_PlayerStats[attacker_client].damageByClass[zombieClass] += damage;
        }
    }

    if (IsValidSurvivorPlayer(victim_client) && (StrEqual(damageType, "infected") || StrEqual(damageType, "128")) && attacker_client == 0)
    {
        float currentTime = GetGameTime();
        if (g_LastBoomerVomitTime[victim_client] > 0.0 && (currentTime - g_LastBoomerVomitTime[victim_client]) <= 21.0)
        {
            if (g_LastBoomerAttacker > 0 && IsClientInGame(g_LastBoomerAttacker))
            {
                g_PlayerStats[g_LastBoomerAttacker].totalDamage += damage;
                g_PlayerStats[g_LastBoomerAttacker].damageByClass[Boomer] += damage;
            }
        }
    }

    if (IsValidSurvivorPlayer(victim_client) && StrEqual(damageType, "acid"))
    {
        int spitterAttacker = FindLastSpitter();
        if (spitterAttacker > 0)
        {
            g_PlayerStats[spitterAttacker].totalDamage += damage;
            g_PlayerStats[spitterAttacker].damageByClass[Spitter] += damage;
        }
    }
}

int FindLastSpitter()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
        {
            if (GetInfectedClass(i) == Spitter)
            {
                return i;
            }
        }
    }
    return 0;
}

public void Event_PlayerVomited(Event event, const char[] name, bool dontBroadcast)
{
    int victim_client = GetClientOfUserId(event.GetInt("userid"));
    int attacker_client = GetClientOfUserId(event.GetInt("attacker"));

    if (IsValidSurvivorPlayer(victim_client) && IsValidInfectedPlayer(attacker_client) && GetInfectedClass(attacker_client) == Boomer)
    {
        g_LastBoomerVomitTime[victim_client] = GetGameTime();
        g_LastBoomerAttacker = attacker_client;
    }
}

public void Event_HunterPounce(Event event, const char[] name, bool dontBroadcast)
{
    // Hunter扑咬造成的初始伤害由Event_PlayerHurt统计
}

public void Event_SmokerPullStopped(Event event, const char[] name, bool dontBroadcast)
{
    int smoker_client = GetClientOfUserId(event.GetInt("userid"));
    int reason = event.GetInt("release_type");

    if (IsValidInfectedPlayer(smoker_client))
    {
        if (reason == 1) // 右键攻击 (或被近战攻击打断舌头)
        {
            int damage = 4;
            g_PlayerStats[smoker_client].totalDamage += damage;
            g_PlayerStats[smoker_client].damageByClass[Smoker] += damage;
        }
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    // No action needed here for now
}

ZombieClass GetInfectedClass(int client)
{
    if (!IsValidInfectedPlayer(client))
        return view_as<ZombieClass>(0);
    return view_as<ZombieClass>(GetEntProp(client, Prop_Send, "m_zombieClass"));
}

bool IsValidInfectedPlayer(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 3);
}

bool IsValidSurvivorPlayer(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}

void GetInfectedClassName(ZombieClass class_idx, char[] buffer, int maxlen)
{
    switch (class_idx)
    {
        case Smoker:   strcopy(buffer, maxlen, "舌头");
        case Boomer:   strcopy(buffer, maxlen, "胖子");
        case Hunter:   strcopy(buffer, maxlen, "猎人");
        case Spitter:  strcopy(buffer, maxlen, "口水");
        case Jockey:   strcopy(buffer, maxlen, "猴子");
        case Charger:  strcopy(buffer, maxlen, "牛");
        case Tank:     strcopy(buffer, maxlen, "坦克");
        default:       strcopy(buffer, maxlen, "未知");
    }
}