#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks> // 包含 sdkhooks 以获取 HITGROUP_* 定义
#include <left4dhooks>
#include <left4dhooks_stocks> // [5] // 包含 L4D2 相关的 stock 函数

// --- 手动定义 HITGROUP 常量 (以防 sdkhooks 未完全包含) ---
#if !defined HITGROUP_COUNT
#define HITGROUP_GENERIC	0
#define HITGROUP_HEAD		1
#define HITGROUP_CHEST		2
#define HITGROUP_STOMACH	3
#define HITGROUP_LEFTARM	4
#define HITGROUP_RIGHTARM	5
#define HITGROUP_LEFTLEG	6
#define HITGROUP_RIGHTLEG	7
#define HITGROUP_COUNT		8
#endif

// --- 全局变量 ---

float g_fTotalDamage[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_iTotalHits[MAXPLAYERS + 1][MAXPLAYERS + 1];
float g_fHitgroupDamage[MAXPLAYERS + 1][MAXPLAYERS + 1][HITGROUP_COUNT];
int g_iHitgroupHits[MAXPLAYERS + 1][MAXPLAYERS + 1][HITGROUP_COUNT];

// --- 插件信息 ---

public Plugin myinfo =
{
    name = "L4D2 详细击杀与受击提示 (无颜色-带序号)",
    author = "Gemini Pro",
    description = "在人类击杀特殊感染者后,向双方显示详细的伤害信息、武器、距离和命中部位 (无颜色，带序号)。",
    version = "2.0", // 版本号更新
    url = "https://github.com/gemini-pro"
};

// --- 事件钩子与函数 ---

public void OnPluginStart()
{
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            ResetPlayerData(i);
        }
    }
}


public void OnClientPutInServer(int client)
{
    ResetPlayerData(client);
}

public void OnClientDisconnect(int client)
{
    ResetPlayerData(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client))
    {
        ResetPlayerData(client);
    }
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int hitgroup = event.GetInt("hitgroup");
    float damage = event.GetFloat("damage_real");
    if (damage == 0.0) damage = event.GetFloat("dmg_health");
    if (damage == 0.0) damage = event.GetFloat("damage");

    if (attacker > 0 && victim > 0 && attacker != victim && IsClientInGame(attacker) && IsClientInGame(victim))
    {
        if (GetClientTeam(attacker) == L4DTeam_Survivor && GetClientTeam(victim) == L4DTeam_Infected)
        {
            L4D2ZombieClassType victimClass = L4D2_GetPlayerZombieClass(victim); // [5]
            if (victimClass >= L4D2ZombieClass_Smoker && victimClass <= L4D2ZombieClass_Tank)
            {
                g_fTotalDamage[attacker][victim] += damage;
                g_iTotalHits[attacker][victim]++;

                if (hitgroup >= HITGROUP_GENERIC && hitgroup < HITGROUP_COUNT)
                {
                    g_fHitgroupDamage[attacker][victim][hitgroup] += damage;
                    g_iHitgroupHits[attacker][victim][hitgroup]++;
                }
            }
        }
    }
    return Plugin_Continue;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    if (attacker > 0 && victim > 0 && attacker != victim && IsClientInGame(attacker) && IsClientInGame(victim))
    {
        if (GetClientTeam(attacker) == L4DTeam_Survivor && GetClientTeam(victim) == L4DTeam_Infected)
        {
            L4D2ZombieClassType victimClass = L4D2_GetPlayerZombieClass(victim); // [5]
            if (victimClass >= L4D2ZombieClass_Smoker && victimClass <= L4D2ZombieClass_Tank)
            {
                char attackerName[MAX_NAME_LENGTH];
                char victimName[MAX_NAME_LENGTH];
                GetClientName(attacker, attackerName, sizeof(attackerName));
                GetClientName(victim, victimName, sizeof(victimName));

                float attackerPos[3], victimPos[3];
                GetClientEyePosition(attacker, attackerPos);
                GetClientEyePosition(victim, victimPos);
                float distance = GetVectorDistance(attackerPos, victimPos);

                if(g_iTotalHits[attacker][victim] > 0)
                {
                    ShowKillDetailsMenu(attacker, victimName, weapon, distance, victim);
                    ShowVictimDetailsMenu(victim, attackerName, weapon, distance, attacker);
                    ResetVictimDamageData(attacker, victim);
                }
            }
        }
    }
}

// 显示击杀详情菜单给攻击者
void ShowKillDetailsMenu(int attacker, const char[] victimName, const char[] weapon, float distance, int victimId)
{
    Menu menu = new Menu(MenuHandler_KillDetails);
    menu.SetTitle(""); // 保持无标题

    char buffer[512];
    char weaponDisplayName[64];
    GetWeaponDisplayName(weapon, weaponDisplayName, sizeof(weaponDisplayName));

    // 第一行：击杀信息
    Format(buffer, sizeof(buffer), "你击杀了 %s", victimName);
    menu.AddItem("kill_info", buffer, ITEMDRAW_DEFAULT);

    // 第二行：武器和距离
    Format(buffer, sizeof(buffer), "武器: %s, 距离: %.1fm", weaponDisplayName, distance / 39.37);
    menu.AddItem("weapon_dist", buffer, ITEMDRAW_DISABLED);

    // 第三行：总伤害
    Format(buffer, sizeof(buffer), "造成对方的伤害: %.0f (%d次)", g_fTotalDamage[attacker][victimId], g_iTotalHits[attacker][victimId]);
    menu.AddItem("total_damage", buffer, ITEMDRAW_DEFAULT);

    AddHitgroupDamageToMenu(menu, "头部", HITGROUP_HEAD, attacker, victimId);
    AddHitgroupDamageToMenu(menu, "胸部", HITGROUP_CHEST, attacker, victimId);
    AddHitgroupDamageToMenu(menu, "腹部", HITGROUP_STOMACH, attacker, victimId);
    AddHitgroupDamageToMenu(menu, "左臂", HITGROUP_LEFTARM, attacker, victimId);
    AddHitgroupDamageToMenu(menu, "右臂", HITGROUP_RIGHTARM, attacker, victimId);
    AddHitgroupDamageToMenu(menu, "左腿", HITGROUP_LEFTLEG, attacker, victimId);
    AddHitgroupDamageToMenu(menu, "右腿", HITGROUP_RIGHTLEG, attacker, victimId);

    menu.ExitButton = true;
    menu.Display(attacker, 3);
}

// 显示受击详情菜单给受害者
void ShowVictimDetailsMenu(int victim, const char[] attackerName, const char[] weapon, float distance, int attackerId)
{
    Menu menu = new Menu(MenuHandler_VictimDetails);
    menu.SetTitle(""); // 保持无标题

    char buffer[512];
    char weaponDisplayName[64];
    GetWeaponDisplayName(weapon, weaponDisplayName, sizeof(weaponDisplayName));

    // 第一行：被击杀信息
    Format(buffer, sizeof(buffer), "你被 %s 击杀", attackerName);
    menu.AddItem("killed_by", buffer, ITEMDRAW_DEFAULT);

    // 第二行：武器和距离
    Format(buffer, sizeof(buffer), "武器: %s, 距离: %.1fm", weaponDisplayName, distance / 39.37);
    menu.AddItem("weapon_dist_v", buffer, ITEMDRAW_DISABLED);

    // 第三行：总伤害
    Format(buffer, sizeof(buffer), "承受来自对方的伤害: %.0f (%d次)", g_fTotalDamage[attackerId][victim], g_iTotalHits[attackerId][victim]);
    menu.AddItem("total_damage_v", buffer, ITEMDRAW_DEFAULT);

    AddHitgroupDamageToMenu(menu, "头部", HITGROUP_HEAD, attackerId, victim);
    AddHitgroupDamageToMenu(menu, "胸部", HITGROUP_CHEST, attackerId, victim);
    AddHitgroupDamageToMenu(menu, "腹部", HITGROUP_STOMACH, attackerId, victim);
    AddHitgroupDamageToMenu(menu, "左臂", HITGROUP_LEFTARM, attackerId, victim);
    AddHitgroupDamageToMenu(menu, "右臂", HITGROUP_RIGHTARM, attackerId, victim);
    AddHitgroupDamageToMenu(menu, "左腿", HITGROUP_LEFTLEG, attackerId, victim);
    AddHitgroupDamageToMenu(menu, "右腿", HITGROUP_RIGHTLEG, attackerId, victim);

    menu.ExitButton = true;
    menu.Display(victim, 3);
}

public int MenuHandler_KillDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        // delete menu;
    }
    return 0;
}

public int MenuHandler_VictimDetails(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        // delete menu;
    }
    return 0;
}

void AddHitgroupDamageToMenu(Menu menu, const char[] hitgroupName, int hitgroupIndex, int attacker, int victim)
{
    if (hitgroupIndex >= HITGROUP_GENERIC && hitgroupIndex < HITGROUP_COUNT && g_iHitgroupHits[attacker][victim][hitgroupIndex] > 0)
    {
        char itemInfo[128];
        char itemName[64];
        Format(itemName, sizeof(itemName), "hg_%d_%d_%d", attacker, victim, hitgroupIndex);
        if(hitgroupIndex >= HITGROUP_GENERIC && hitgroupIndex < HITGROUP_COUNT)
        {
            Format(itemInfo, sizeof(itemInfo), "%s: %.0f (%d次)",
                hitgroupName, g_fHitgroupDamage[attacker][victim][hitgroupIndex], g_iHitgroupHits[attacker][victim][hitgroupIndex]);
            menu.AddItem(itemName, itemInfo, ITEMDRAW_DISABLED);
        }
    }
}

void ResetPlayerData(int client)
{
    if (client <= 0 || client > MaxClients) return;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (i > 0 && i <= MaxClients)
        {
            g_fTotalDamage[client][i] = 0.0;
            g_iTotalHits[client][i] = 0;
            for (int j = 0; j < HITGROUP_COUNT; j++)
            {
                g_fHitgroupDamage[client][i][j] = 0.0;
                g_iHitgroupHits[client][i][j] = 0;
            }
        }

        if (i > 0 && i <= MaxClients)
        {
            g_fTotalDamage[i][client] = 0.0;
            g_iTotalHits[i][client] = 0;
            for (int j = 0; j < HITGROUP_COUNT; j++)
            {
                g_fHitgroupDamage[i][client][j] = 0.0;
                g_iHitgroupHits[i][client][j] = 0;
            }
        }
    }
}

void ResetVictimDamageData(int attacker, int victim)
{
    if (attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients) return;

    g_fTotalDamage[attacker][victim] = 0.0;
    g_iTotalHits[attacker][victim] = 0;
    for (int j = 0; j < HITGROUP_COUNT; j++)
    {
        g_fHitgroupDamage[attacker][victim][j] = 0.0;
        g_iHitgroupHits[attacker][victim][j] = 0;
    }
}

stock void GetWeaponDisplayName(const char[] weaponName, char[] displayName, int maxLen)
{
    if (StrEqual(weaponName, "rifle")) strcopy(displayName, maxLen, "M16步枪");
    else if (StrEqual(weaponName, "smg")) strcopy(displayName, maxLen, "乌兹冲锋枪");
    else if (StrEqual(weaponName, "hunting_rifle")) strcopy(displayName, maxLen, "猎枪");
    else if (StrEqual(weaponName, "autoshotgun")) strcopy(displayName, maxLen, "连发霰弹枪");
    else if (StrEqual(weaponName, "pumpshotgun")) strcopy(displayName, maxLen, "泵动霰弹枪");
    else if (StrEqual(weaponName, "pistol")) strcopy(displayName, maxLen, "手枪");
    else if (StrEqual(weaponName, "smg_silenced")) strcopy(displayName, maxLen, "消音冲锋枪");
    else if (StrEqual(weaponName, "shotgun_chrome")) strcopy(displayName, maxLen, "铁管霰弹枪");
    else if (StrEqual(weaponName, "rifle_desert")) strcopy(displayName, maxLen, "SCAR步枪");
    else if (StrEqual(weaponName, "sniper_military")) strcopy(displayName, maxLen, "军用狙击枪");
    else if (StrEqual(weaponName, "shotgun_spas")) strcopy(displayName, maxLen, "SPAS战斗霰弹枪");
    else if (StrEqual(weaponName, "rifle_ak47")) strcopy(displayName, maxLen, "AK47步枪");
    else if (StrEqual(weaponName, "pistol_magnum")) strcopy(displayName, maxLen, "马格南手枪");
    else if (StrEqual(weaponName, "smg_mp5")) strcopy(displayName, maxLen, "MP5冲锋枪");
    else if (StrEqual(weaponName, "rifle_sg552")) strcopy(displayName, maxLen, "SG552步枪");
    else if (StrEqual(weaponName, "sniper_awp")) strcopy(displayName, maxLen, "AWP狙击枪");
    else if (StrEqual(weaponName, "sniper_scout")) strcopy(displayName, maxLen, "Scout狙击枪");
    else if (StrEqual(weaponName, "rifle_m60")) strcopy(displayName, maxLen, "M60机枪");
    else if (StrEqual(weaponName, "grenade_launcher")) strcopy(displayName, maxLen, "榴弹发射器");
    else if (StrEqual(weaponName, "weapon_chainsaw")) strcopy(displayName, maxLen, "电锯");
    else if (StrContains(weaponName, "melee") != -1) strcopy(displayName, maxLen, "近战武器");
    else if (StrEqual(weaponName, "hunter_claw")) strcopy(displayName, maxLen, "Hunter爪击");
    else if (StrEqual(weaponName, "smoker_claw")) strcopy(displayName, maxLen, "Smoker爪击");
    else if (StrEqual(weaponName, "boomer_claw")) strcopy(displayName, maxLen, "Boomer爪击");
    else if (StrEqual(weaponName, "spitter_claw")) strcopy(displayName, maxLen, "Spitter爪击");
    else if (StrEqual(weaponName, "jockey_claw")) strcopy(displayName, maxLen, "Jockey爪击");
    else if (StrEqual(weaponName, "charger_claw")) strcopy(displayName, maxLen, "Charger爪击");
    else if (StrEqual(weaponName, "tank_claw")) strcopy(displayName, maxLen, "Tank拳击");
    else if (StrEqual(weaponName, "rock")) strcopy(displayName, maxLen, "Tank投石");
    else if (StrEqual(weaponName, "tongue")) strcopy(displayName, maxLen, "Smoker舌头");
    else if (StrEqual(weaponName, "vomit")) strcopy(displayName, maxLen, "Boomer呕吐");
    else strcopy(displayName, maxLen, weaponName);
}