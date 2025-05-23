#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <left4dhooks>
#include <sdktools>
#include <l4d2lib>
#include <l4d2util_stocks>

#define PLUGIN_TAG "" // \x04[Hybrid Bonus]

#define SM2_DEBUG    0

/**
    Bibliography:
    'l4d2_scoremod' by CanadaRox, ProdigySim
    'damage_bonus' by CanadaRox, Stabby
    'l4d2_scoringwip' by ProdigySim
    'srs.scoringsystem' by AtomicStryker
**/

new Handle:hCvarBonusPerSurvivorMultiplier;
new Handle:hCvarPermanentHealthProportion;
new Handle:hCvarPillsHpFactor;
new Handle:hCvarPillsMaxBonus;
new Handle:hCvarMedkitHpFactor;
new Handle:hCvarMedkitMaxBonus;
// 新增: 肾上腺素相关控制变量的句柄
new Handle:hCvarAdrenalineHpFactor; // 肾上腺素生命值因子控制变量句柄
new Handle:hCvarAdrenalineMaxBonus; // 肾上腺素最大奖励控制变量句柄

new Handle:hCvarValveSurvivalBonus;
new Handle:hCvarValveTieBreaker;

new Float:fMapBonus;
new Float:fMapHealthBonus;
new Float:fMapDamageBonus;
new Float:fMapTempHealthBonus;
new Float:fPermHpWorth;
new Float:fTempHpWorth;
new Float:fSurvivorBonus[2];

new iMapDistance;
new iTeamSize;
new iPillWorth;
new iMedkitWorth;
// 新增: 肾上腺素价值变量
new iAdrenalineWorth; // 单个肾上腺素的奖励分数
new iLostTempHealth[2];
new iTempHealth[MAXPLAYERS + 1];
new iSiDamage[2];

new String:sSurvivorState[2][32];

new bool:bLateLoad;
new bool:bRoundOver;
new bool:bTiebreakerEligibility[2];
new Float:g_fAccumulatedPermHPLossBonus[2]; 

new g_iPreDamagePermanentHealth[MAXPLAYERS + 1];


public Plugin:myinfo =
{
    name = "L4D2 Scoremod+",
    author = "Visor, Sir (Medkit & Adrenaline Bonus Mod by Gemini)", 
    description = "The next generation scoring mod with Medkit and Adrenaline bonus", 
    version = "2.2.8-medkit-adrenaline", 
    url = "https://github.com/Attano/L4D2-Competitive-Framework"
};

public APLRes:AskPluginLoad2(Handle:plugin, bool:late, String:error[], errMax)
{
    CreateNative("SMPlus_GetHealthBonus", Native_GetHealthBonus);
    CreateNative("SMPlus_GetDamageBonus", Native_GetDamageBonus);
    CreateNative("SMPlus_GetPillsBonus", Native_GetPillsBonus);
    CreateNative("SMPlus_GetMedkitBonus", Native_GetMedkitBonus);
    CreateNative("SMPlus_GetAdrenalineBonus", Native_GetAdrenalineBonus); 
    CreateNative("SMPlus_GetMaxHealthBonus", Native_GetMaxHealthBonus);
    CreateNative("SMPlus_GetMaxDamageBonus", Native_GetMaxDamageBonus);
    CreateNative("SMPlus_GetMaxPillsBonus", Native_GetMaxPillsBonus);
    CreateNative("SMPlus_GetMaxMedkitBonus", Native_GetMaxMedkitBonus);
    CreateNative("SMPlus_GetMaxAdrenalineBonus", Native_GetMaxAdrenalineBonus); 

    RegPluginLibrary("l4d2_hybrid_scoremod");
    bLateLoad = late;
    return APLRes_Success;
}

public OnPluginStart()
{
    hCvarBonusPerSurvivorMultiplier = CreateConVar("sm2_bonus_per_survivor_multiplier", "0.5", "Total Survivor Bonus = this * Number of Survivors * Map Distance");
    hCvarPermanentHealthProportion = CreateConVar("sm2_permament_health_proportion", "0.75", "Permanent Health Bonus = this * Map Bonus; rest goes for Temporary Health Bonus");
    hCvarPillsHpFactor = CreateConVar("sm2_pills_hp_factor", "6.0", "Unused pills HP worth = map bonus HP value / this");
    hCvarPillsMaxBonus = CreateConVar("sm2_pills_max_bonus", "30", "Unused pills cannot be worth more than this");
    hCvarMedkitHpFactor = CreateConVar("sm2_medkit_hp_factor", "3.0", "Unused medkit HP worth = map bonus HP value / this (Medkits are generally more valuable)");
    hCvarMedkitMaxBonus = CreateConVar("sm2_medkit_max_bonus", "60", "Unused medkits cannot be worth more than this");
    hCvarAdrenalineHpFactor = CreateConVar("sm2_adrenaline_hp_factor", "12.0", "Unused adrenaline HP worth = map bonus HP value / this (Adrenaline gives less direct HP but provides speed)"); 
    hCvarAdrenalineMaxBonus = CreateConVar("sm2_adrenaline_max_bonus", "15", "Unused adrenaline cannot be worth more than this"); 

    hCvarValveSurvivalBonus = FindConVar("vs_survival_bonus");
    hCvarValveTieBreaker = FindConVar("vs_tiebreak_bonus");

    HookConVarChange(hCvarBonusPerSurvivorMultiplier, CvarChanged);
    HookConVarChange(hCvarPermanentHealthProportion, CvarChanged);
    HookConVarChange(hCvarPillsHpFactor, CvarChanged);
    HookConVarChange(hCvarPillsMaxBonus, CvarChanged);
    HookConVarChange(hCvarMedkitHpFactor, CvarChanged);
    HookConVarChange(hCvarMedkitMaxBonus, CvarChanged);
    HookConVarChange(hCvarAdrenalineHpFactor, CvarChanged);
    HookConVarChange(hCvarAdrenalineMaxBonus, CvarChanged);

    HookEvent("round_start", RoundStartEvent, EventHookMode_PostNoCopy);
    HookEvent("player_ledge_grab", OnPlayerLedgeGrab);
    HookEvent("player_incapacitated", OnPlayerIncapped);
    HookEvent("player_hurt", OnPlayerHurt);
    HookEvent("revive_success", OnPlayerRevived, EventHookMode_Post);
    HookEvent("player_death", OnPlayerDeath);

    RegConsoleCmd("sm_health", CmdBonus);
    RegConsoleCmd("sm_damage", CmdBonus);
    RegConsoleCmd("sm_pills", CmdBonus);
    RegConsoleCmd("sm_medkits", CmdBonus);
    RegConsoleCmd("sm_adrenaline", CmdBonus);
    RegConsoleCmd("sm_bonus", CmdBonus);
    RegConsoleCmd("sm_mapinfo", CmdMapInfo);

    if (bLateLoad)
    {
        for (new i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i))
                continue;
            OnClientPutInServer(i);
        }
    }
}

public OnPluginEnd()
{
    ResetConVar(hCvarValveSurvivalBonus);
    ResetConVar(hCvarValveTieBreaker);
}

public OnConfigsExecuted()
{
    iTeamSize = GetConVarInt(FindConVar("survivor_limit"));
    SetConVarInt(hCvarValveTieBreaker, 0); 

    iMapDistance = L4D2_GetMapValueInt("max_distance", L4D_GetVersusMaxCompletionScore());
    L4D_SetVersusMaxCompletionScore(iMapDistance);

    new Float:fPermHealthProportion = GetConVarFloat(hCvarPermanentHealthProportion);
    new Float:fTempHealthProportion = 1.0 - fPermHealthProportion;
    fMapBonus = iMapDistance * (GetConVarFloat(hCvarBonusPerSurvivorMultiplier) * iTeamSize);
    fMapHealthBonus = fMapBonus * fPermHealthProportion;
    fMapDamageBonus = fMapBonus * fTempHealthProportion;
    fMapTempHealthBonus = iTeamSize * 100.0 / fPermHealthProportion * fTempHealthProportion; 
    fPermHpWorth = fMapBonus / iTeamSize / 100.0 * fPermHealthProportion; 
    fTempHpWorth = (fMapTempHealthBonus > 0.0) ? (fMapBonus * fTempHealthProportion / fMapTempHealthBonus) : 0.0;

    iPillWorth = L4D2Util_Clamp(RoundToNearest(50.0 * (fPermHpWorth / GetConVarFloat(hCvarPillsHpFactor)) / 5.0) * 5, 5, GetConVarInt(hCvarPillsMaxBonus));
    iMedkitWorth = L4D2Util_Clamp(RoundToNearest(80.0 * (fPermHpWorth / GetConVarFloat(hCvarMedkitHpFactor)) / 5.0) * 5, 10, GetConVarInt(hCvarMedkitMaxBonus));
    iAdrenalineWorth = L4D2Util_Clamp(RoundToNearest(25.0 * (fPermHpWorth / GetConVarFloat(hCvarAdrenalineHpFactor)) / 5.0) * 5, 5, GetConVarInt(hCvarAdrenalineMaxBonus)); 

#if SM2_DEBUG
    PrintToChatAll("\x01Map health bonus: \x05%.1f\x01, temp health bonus: \x05%.1f\x01, perm hp worth: \x03%.3f\x01, temp hp worth: \x03%.3f\x01, pill worth: \x03%i\x01, medkit worth: \x03%i\x01, adrenaline worth: \x03%i\x01", fMapBonus, fMapTempHealthBonus, fPermHpWorth, fTempHpWorth, iPillWorth, iMedkitWorth, iAdrenalineWorth);
#endif
}

public OnMapStart()
{
    OnConfigsExecuted();

    iLostTempHealth[0] = 0;
    iLostTempHealth[1] = 0;
    iSiDamage[0] = 0;
    iSiDamage[1] = 0;
    bTiebreakerEligibility[0] = false;
    bTiebreakerEligibility[1] = false;

    g_fAccumulatedPermHPLossBonus[0] = 0.0;
    g_fAccumulatedPermHPLossBonus[1] = 0.0;

    for (new i = 1; i <= MaxClients; i++)
    {
        g_iPreDamagePermanentHealth[i] = 0; 
    }
}

void CvarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
    OnConfigsExecuted();
}

public OnClientPutInServer(client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);

    if (IsClientInGame(client) && IsSurvivor(client))
    {
        g_iPreDamagePermanentHealth[client] = GetSurvivorPermanentHealth(client);
        iTempHealth[client] = GetSurvivorTemporaryHealth(client); 
    }
    else
    {
        g_iPreDamagePermanentHealth[client] = 0;
        iTempHealth[client] = 0;
    }
}

public OnClientDisconnect(client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

void RoundStartEvent(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
    g_fAccumulatedPermHPLossBonus[InSecondHalfOfRound()] = 0.0;
    for (new i = 1; i <= MaxClients; i++) 
    {
        if (IsClientInGame(i) && IsSurvivor(i)) 
        {
            iTempHealth[i] = GetSurvivorTemporaryHealth(i); 
            g_iPreDamagePermanentHealth[i] = GetSurvivorPermanentHealth(i); 
        }
        else 
        {
            iTempHealth[i] = 0;
            g_iPreDamagePermanentHealth[i] = 0;
        }
    }
    bRoundOver = false; 
    g_fAccumulatedPermHPLossBonus[InSecondHalfOfRound()] = 0.0;
}

// 原生函数实现
int Native_GetHealthBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorHealthBonus());
}

int Native_GetMaxHealthBonus(Handle:plugin, numParams)
{
    return RoundToFloor(fMapHealthBonus);
}

int Native_GetDamageBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorDamageBonus());
}

int Native_GetMaxDamageBonus(Handle:plugin, numParams)
{
    return RoundToFloor(fMapDamageBonus);
}

int Native_GetPillsBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorPillBonus());
}

int Native_GetMaxPillsBonus(Handle:plugin, numParams)
{
    return iPillWorth * iTeamSize;
}

int Native_GetMedkitBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorMedkitBonus()); 
}

int Native_GetMaxMedkitBonus(Handle:plugin, numParams)
{
    return iMedkitWorth * iTeamSize; 
}

// 新增: 肾上腺素原生函数的实现
int Native_GetAdrenalineBonus(Handle:plugin, numParams)
{
    return RoundToFloor(GetSurvivorAdrenalineBonus());
}

int Native_GetMaxAdrenalineBonus(Handle:plugin, numParams)
{
    return iAdrenalineWorth * iTeamSize; 
}


Action:CmdBonus(client, args)
{
    if (bRoundOver || !client)
        return Plugin_Handled;

    decl String:sCmdType[64];
    GetCmdArg(0, sCmdType, sizeof(sCmdType)); 
    decl String:sArg1[64];
    GetCmdArg(1, sArg1, sizeof(sArg1)); 


    new Float:fHealthBonus = GetSurvivorHealthBonus();
    new Float:fDamageBonus = GetSurvivorDamageBonus();
    new Float:fPillsBonus = GetSurvivorPillBonus();
    new Float:fMedkitBonus = GetSurvivorMedkitBonus();
    new Float:fAdrenalineBonus = GetSurvivorAdrenalineBonus();
    new Float:fMaxPillsBonus = float(iPillWorth * iTeamSize);
    new Float:fMaxMedkitBonus = float(iMedkitWorth * iTeamSize);
    new Float:fMaxAdrenalineBonus = float(iAdrenalineWorth * iTeamSize);

    new Float:fCurrentTotalBonus = fHealthBonus + fDamageBonus + fPillsBonus + fMedkitBonus + fAdrenalineBonus;
    new Float:fMaxTotalMapBonus = fMapHealthBonus + fMapDamageBonus + fMaxPillsBonus + fMaxMedkitBonus + fMaxAdrenalineBonus;


    if (StrEqual(sArg1, "full") || StrEqual(sCmdType, "sm_bonus_full")) 
    {
        if (InSecondHalfOfRound())
        {
            new Float:fOldMaxTotalBonus = fMapBonus + float(iPillWorth * iTeamSize) + float(iMedkitWorth * iTeamSize) + float(iAdrenalineWorth * iTeamSize);
            PrintToChat(client, "%s\x01R\x04#1\x01 Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01> [%s]", PLUGIN_TAG, RoundToFloor(fSurvivorBonus[0]), RoundToFloor(fOldMaxTotalBonus), CalculateBonusPercent(fSurvivorBonus[0], fOldMaxTotalBonus), sSurvivorState[0]);
        }
        PrintToChat(client, "%s\x01R\x04#%i\x01 Bonus: \x05%d\x01 <\x03%.1f%%\x01> [HB: \x05%d\x01 <\x03%.1f%%\x01> | DB: \x05%d\x01 <\x03%.1f%%\x01> | 药: \x05%d\x01 <\x03%.1f%%\x01> | 包: \x05%d\x01 <\x03%.1f%%\x01> | 针: \x05%d\x01 <\x03%.1f%%\x01>]",
            PLUGIN_TAG, InSecondHalfOfRound() + 1,
            RoundToFloor(fCurrentTotalBonus), CalculateBonusPercent(fCurrentTotalBonus, fMaxTotalMapBonus),
            RoundToFloor(fHealthBonus), CalculateBonusPercent(fHealthBonus, fMapHealthBonus),
            RoundToFloor(fDamageBonus), CalculateBonusPercent(fDamageBonus, fMapDamageBonus),
            RoundToFloor(fPillsBonus), CalculateBonusPercent(fPillsBonus, fMaxPillsBonus),
            RoundToFloor(fMedkitBonus), CalculateBonusPercent(fMedkitBonus, fMaxMedkitBonus),
            RoundToFloor(fAdrenalineBonus), CalculateBonusPercent(fAdrenalineBonus, fMaxAdrenalineBonus)); 
    }
    else if (StrEqual(sArg1, "lite") || StrEqual(sCmdType, "sm_bonus_lite")) 
    {
        PrintToChat(client, "%s\x01R\x04#%i\x01 Bonus: \x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, InSecondHalfOfRound() + 1, RoundToFloor(fCurrentTotalBonus), CalculateBonusPercent(fCurrentTotalBonus, fMaxTotalMapBonus));
    }
    else if (StrEqual(sCmdType, "sm_health"))
    {
        PrintToChat(client, "%s\x01Health Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, RoundToFloor(fHealthBonus), RoundToFloor(fMapHealthBonus), CalculateBonusPercent(fHealthBonus, fMapHealthBonus));
    }
    else if (StrEqual(sCmdType, "sm_damage"))
    {
        PrintToChat(client, "%s\x01Damage Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, RoundToFloor(fDamageBonus), RoundToFloor(fMapDamageBonus), CalculateBonusPercent(fDamageBonus, fMapDamageBonus));
    }
    else if (StrEqual(sCmdType, "sm_pills"))
    {
        PrintToChat(client, "%s\x01Pills Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, RoundToFloor(fPillsBonus), RoundToFloor(fMaxPillsBonus), CalculateBonusPercent(fPillsBonus, fMaxPillsBonus));
    }
    else if (StrEqual(sCmdType, "sm_medkits")) 
    {
        PrintToChat(client, "%s\x01Medkit Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, RoundToFloor(fMedkitBonus), RoundToFloor(fMaxMedkitBonus), CalculateBonusPercent(fMedkitBonus, fMaxMedkitBonus));
    }
    else if (StrEqual(sCmdType, "sm_adrenaline")) 
    {
        PrintToChat(client, "%s\x01Adrenaline Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, RoundToFloor(fAdrenalineBonus), RoundToFloor(fMaxAdrenalineBonus), CalculateBonusPercent(fAdrenalineBonus, fMaxAdrenalineBonus));
    }
    else 
    {
        if (InSecondHalfOfRound())
        {
            new Float:fOldMaxTotalBonus = fMapBonus + float(iPillWorth * iTeamSize) + float(iMedkitWorth * iTeamSize) + float(iAdrenalineWorth * iTeamSize);
            PrintToChat(client, "%s\x01R\x04#1\x01 Bonus: \x05%d\x01 <\x03%.1f%%\x01>", PLUGIN_TAG, RoundToFloor(fSurvivorBonus[0]), CalculateBonusPercent(fSurvivorBonus[0], fOldMaxTotalBonus));
        }
        PrintToChat(client, "%s\x01R\x04#%i\x01 Bonus: \x05%d\x01 <\x03%.1f%%\x01> [HB: \x03%.0f%%\x01 | DB: \x03%.0f%%\x01 | 药: \x03%.0f%%\x01 | 包: \x03%.0f%%\x01 | 针: \x03%.0f%%\x01]",
            PLUGIN_TAG, InSecondHalfOfRound() + 1,
            RoundToFloor(fCurrentTotalBonus), CalculateBonusPercent(fCurrentTotalBonus, fMaxTotalMapBonus),
            CalculateBonusPercent(fHealthBonus, fMapHealthBonus),
            CalculateBonusPercent(fDamageBonus, fMapDamageBonus),
            CalculateBonusPercent(fPillsBonus, fMaxPillsBonus),
            CalculateBonusPercent(fMedkitBonus, fMaxMedkitBonus),
            CalculateBonusPercent(fAdrenalineBonus, fMaxAdrenalineBonus)); 
    }
    return Plugin_Handled;
}

Action:CmdMapInfo(client, args)
{
    new Float:fMaxPillsBonus = float(iPillWorth * iTeamSize);
    new Float:fMaxMedkitBonus = float(iMedkitWorth * iTeamSize);
    new Float:fMaxAdrenalineBonus = float(iAdrenalineWorth * iTeamSize);
    new Float:fTotalMaxBonusItems = fMaxPillsBonus + fMaxMedkitBonus + fMaxAdrenalineBonus;
    new Float:fTotalOverallMaxBonus = fMapHealthBonus + fMapDamageBonus + fTotalMaxBonusItems;


    PrintToChat(client, "\x01[\x04Hybrid Bonus\x01 :: \x03%iv%i\x01] Map Info", iTeamSize, iTeamSize);
    PrintToChat(client, "\x01Distance: \x05%d\x01", iMapDistance);
    PrintToChat(client, "\x01Total Max Bonus: \x05%d\x01 <\x03100.0%%\x01>", RoundToFloor(fTotalOverallMaxBonus));
    PrintToChat(client, "\x01Max Health Bonus: \x05%d\x01 <\x03%.1f%%\x01>", RoundToFloor(fMapHealthBonus), CalculateBonusPercent(fMapHealthBonus, fTotalOverallMaxBonus));
    PrintToChat(client, "\x01Max Damage Bonus: \x05%d\x01 <\x03%.1f%%\x01>", RoundToFloor(fMapDamageBonus), CalculateBonusPercent(fMapDamageBonus, fTotalOverallMaxBonus));
    PrintToChat(client, "\x01Pills Bonus (per item): \x05%d\x01 (Team Max: \x05%d\x01) <\x03%.1f%%\x01>", iPillWorth, RoundToFloor(fMaxPillsBonus), CalculateBonusPercent(fMaxPillsBonus, fTotalOverallMaxBonus));
    PrintToChat(client, "\x01Medkit Bonus (per item): \x05%d\x01 (Team Max: \x05%d\x01) <\x03%.1f%%\x01>", iMedkitWorth, RoundToFloor(fMaxMedkitBonus), CalculateBonusPercent(fMaxMedkitBonus, fTotalOverallMaxBonus));
    PrintToChat(client, "\x01Adrenaline Bonus (per item): \x05%d\x01 (Team Max: \x05%d\x01) <\x03%.1f%%\x01>", iAdrenalineWorth, RoundToFloor(fMaxAdrenalineBonus), CalculateBonusPercent(fMaxAdrenalineBonus, fTotalOverallMaxBonus));
    PrintToChat(client, "\x01Tiebreaker (based on SI damage, item value for reference: \x05%d\x01)", iPillWorth); 
    return Plugin_Handled;
}
Action:OnTakeDamagePre(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if (!IsSurvivor(victim) || IsPlayerIncap(victim) || !IsPlayerAlive(victim)) 
    {
        return Plugin_Continue;
    }
    g_iPreDamagePermanentHealth[victim] = GetSurvivorPermanentHealth(victim);
    return Plugin_Continue;
}

Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
    if (!IsSurvivor(victim) || IsPlayerIncap(victim) || !IsPlayerAlive(victim))
    {
        if (IsSurvivor(victim) && (!IsPlayerAlive(victim) || IsPlayerIncap(victim))) {
             g_iPreDamagePermanentHealth[victim] = GetSurvivorPermanentHealth(victim); 
        }
        return Plugin_Continue;
    }

    iTempHealth[victim] = GetSurvivorTemporaryHealth(victim);

    if (!IsAnyInfected(attacker)) iSiDamage[InSecondHalfOfRound()] += (damage <= 100.0 ? RoundFloat(damage) : 100);


    int preDamagePermHealth = g_iPreDamagePermanentHealth[victim];
    int currentPermHealthAfterDamage = GetSurvivorPermanentHealth(victim);
    int actualPermHealthLostThisHit = 0; 

    if (preDamagePermHealth > currentPermHealthAfterDamage)
    {
        actualPermHealthLostThisHit = preDamagePermHealth - currentPermHealthAfterDamage;
    }

    if (actualPermHealthLostThisHit > 0)
    {
        float lostHBPoints = float(actualPermHealthLostThisHit) * fPermHpWorth;
        g_fAccumulatedPermHPLossBonus[InSecondHalfOfRound()] += lostHBPoints;

        #if SM2_DEBUG 
        PrintToChatAll("\x01[HB损失] %N: 永久血量 %d -> %d (损失: %d)。本次HB损失: %.2f。累计HB损失: %.2f",
            victim, preDamagePermHealth, currentPermHealthAfterDamage, actualPermHealthLostThisHit,
            lostHBPoints, g_fAccumulatedPermHPLossBonus[InSecondHalfOfRound()]);
        #endif
    }
    g_iPreDamagePermanentHealth[victim] = currentPermHealthAfterDamage;
    return Plugin_Continue;
}

void OnPlayerLedgeGrab(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    iLostTempHealth[InSecondHalfOfRound()] += L4D2Direct_GetPreIncapHealthBuffer(client);
}

void OnPlayerDeath(Event hEvent, const char[] sEventName, bool bDontBroadcast)
{
    int victim = GetClientOfUserId(hEvent.GetInt("userid"));
    if (IsSurvivor(victim) && !bRoundOver)
    {
        int incaps = GetEntProp(victim, Prop_Send, "m_currentReviveCount");
        int basePenaltyValue = RoundToFloor((fMapDamageBonus / iTeamSize) * 0.05 / (fTempHpWorth > 0.0 ? fTempHpWorth : 1.0) ); 
        if (basePenaltyValue < 0) basePenaltyValue = 0;

        int penalty = 0;
        if (incaps == 2) { 
            penalty = basePenaltyValue + 30;
        } else if (incaps == 1) { 
            penalty = (basePenaltyValue + 30) * 2; 
        } else if (incaps == 0) { 
            penalty = (basePenaltyValue + 30) * 3; 
        }

        iLostTempHealth[InSecondHalfOfRound()] += penalty;

        #if SM2_DEBUG
            PrintToChatAll("\x04[\x01Valid Death\x04] \x03%N \x01had \x03%i \x01incaps. Base Penalty Value: %d. Total Penalty: \x03%i", victim, incaps, basePenaltyValue, penalty);
        #endif
    }
}

void OnPlayerIncapped(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (IsSurvivor(client))
    {
        iLostTempHealth[InSecondHalfOfRound()] += RoundToFloor((fMapDamageBonus / iTeamSize) * 0.05 / (fTempHpWorth > 0.0 ? fTempHpWorth : 1.0)); 
    }
}

void OnPlayerRevived(Handle:event, const String:name[], bool:dontBroadcast)
{
    bool bLedge = GetEventBool(event, "ledge_hang");
    if (!bLedge) {
        return;
    }

    int client = GetClientOfUserId(GetEventInt(event, "subject"));
    if (!IsSurvivor(client)) {
        return;
    }

    RequestFrame(Revival, client);
}

void Revival(int client)
{
    iLostTempHealth[InSecondHalfOfRound()] -= GetSurvivorTemporaryHealth(client);
}

Action:OnPlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    new damage = GetEventInt(event, "dmg_health");
    new damagetype = GetEventInt(event, "type");

    new Float:fFakeDamage = float(damage); 

    if (!IsSurvivor(victim) || !IsSurvivor(attacker) || IsPlayerIncap(victim) || damagetype != DMG_PLASMA || fFakeDamage < GetSurvivorPermanentHealth(victim)) return Plugin_Continue;

    iTempHealth[victim] = GetSurvivorTemporaryHealth(victim);
    if (fFakeDamage > iTempHealth[victim]) fFakeDamage = float(iTempHealth[victim]);

    iLostTempHealth[InSecondHalfOfRound()] += RoundFloat(fFakeDamage);
    iTempHealth[victim] = GetSurvivorTemporaryHealth(victim) - RoundFloat(fFakeDamage);
    if (iTempHealth[victim] < 0) iTempHealth[victim] = 0; 


    return Plugin_Continue;
}

void OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype)
{
    if (!IsSurvivor(victim)) return;

    int tempHealthBeforeHit = iTempHealth[victim];
    int tempHealthAfterHit = IsPlayerAlive(victim) ? GetSurvivorTemporaryHealth(victim) : 0;

#if SM2_DEBUG
    PrintToChatAll("\x01[DB计算] %N: 临时血量 %d -> %d。伤害参数: %.1f", victim, tempHealthBeforeHit, tempHealthAfterHit, damage);
#endif

    if (!IsPlayerAlive(victim) || (IsPlayerIncap(victim) && !IsPlayerLedged(victim)))
    {
        iLostTempHealth[InSecondHalfOfRound()] += tempHealthBeforeHit;
        #if SM2_DEBUG
        PrintToChatAll("\x01[DB计算] %N 死亡或倒地。增加 %d 到 iLostTempHealth。总计: %d", victim, tempHealthBeforeHit, iLostTempHealth[InSecondHalfOfRound()]);
        #endif
    }
    else if (!IsPlayerLedged(victim))
    {
        if (tempHealthBeforeHit > tempHealthAfterHit)
        {
            iLostTempHealth[InSecondHalfOfRound()] += (tempHealthBeforeHit - tempHealthAfterHit);
            #if SM2_DEBUG
            PrintToChatAll("\x01[DB计算] %N 损失 %d 临时血量。已添加到 iLostTempHealth。总计: %d", victim, (tempHealthBeforeHit - tempHealthAfterHit), iLostTempHealth[InSecondHalfOfRound()]);
            #endif
        }
    }
    iTempHealth[victim] = tempHealthAfterHit;
}

public L4D2_ADM_OnTemporaryHealthSubtracted(client, oldHealth, newHealth)
{
    new healthLost = oldHealth - newHealth;
    iTempHealth[client] = newHealth;
    iLostTempHealth[InSecondHalfOfRound()] += healthLost;
    iSiDamage[InSecondHalfOfRound()] += healthLost;
}

public Action:L4D2_OnEndVersusModeRound(bool:countSurvivors)
{
#if SM2_DEBUG
    PrintToChatAll("CDirector::OnEndVersusModeRound() called. InSecondHalfOfRound(): %d, countSurvivors: %d", InSecondHalfOfRound(), countSurvivors);
#endif
    if (bRoundOver)
        return Plugin_Continue;

    new team = InSecondHalfOfRound();
    new iSurvivalMultiplier = countSurvivors ? GetAliveSurvivorCount(false) : 0;
    fSurvivorBonus[team] = GetSurvivorHealthBonus() + GetSurvivorDamageBonus() + GetSurvivorPillBonus() + GetSurvivorMedkitBonus() + GetSurvivorAdrenalineBonus();
    fSurvivorBonus[team] = float(RoundToFloor(fSurvivorBonus[team] / float(iTeamSize)) * iTeamSize);
    if (iSurvivalMultiplier > 0 && RoundToFloor(fSurvivorBonus[team] / iSurvivalMultiplier) >= iTeamSize)
    {
        SetConVarInt(hCvarValveSurvivalBonus, RoundToFloor(fSurvivorBonus[team] / iSurvivalMultiplier));
        fSurvivorBonus[team] = float(GetConVarInt(hCvarValveSurvivalBonus) * iSurvivalMultiplier);
        Format(sSurvivorState[team], 32, "%s%i\x01/\x05%i\x01", (iSurvivalMultiplier == iTeamSize ? "\x05" : "\x04"), iSurvivalMultiplier, iTeamSize);
    #if SM2_DEBUG
        PrintToChatAll("\x01Survival bonus cvar updated. Value: \x05%i\x01 [multiplier: \x05%i\x01]", GetConVarInt(hCvarValveSurvivalBonus), iSurvivalMultiplier);
    #endif
    }
    else
    {
        fSurvivorBonus[team] = 0.0;
        SetConVarInt(hCvarValveSurvivalBonus, 0);
        Format(sSurvivorState[team], 32, "\x04%s\x01", (iSurvivalMultiplier == 0 ? "wiped out" : "bonus depleted"));
        bTiebreakerEligibility[team] = (iSurvivalMultiplier == iTeamSize);
    }

    if (team > 0 && bTiebreakerEligibility[0] && bTiebreakerEligibility[1])
    {
        GameRules_SetProp("m_iChapterDamage", iSiDamage[0], _, 0, true);
        GameRules_SetProp("m_iChapterDamage", iSiDamage[1], _, 1, true);

        if (iSiDamage[0] != iSiDamage[1])
        {
            SetConVarInt(hCvarValveTieBreaker, iPillWorth); 
        }
    }

    CreateTimer(3.0, PrintRoundEndStats, _, TIMER_FLAG_NO_MAPCHANGE);

    bRoundOver = true;
    return Plugin_Continue;
}

Action:PrintRoundEndStats(Handle:timer)
{
    new Float:fCurrentMaxTotalBonusOverall = fMapHealthBonus + fMapDamageBonus + float(iPillWorth * iTeamSize) + float(iMedkitWorth * iTeamSize) + float(iAdrenalineWorth * iTeamSize);
    for (new i = 0; i <= InSecondHalfOfRound(); i++)
    {
        PrintToChatAll("%s\x01Round \x04%i\x01 Bonus: \x05%d\x01/\x05%d\x01 <\x03%.1f%%\x01> [%s]", PLUGIN_TAG, (i + 1), RoundToFloor(fSurvivorBonus[i]), RoundToFloor(fCurrentMaxTotalBonusOverall), CalculateBonusPercent(fSurvivorBonus[i], fCurrentMaxTotalBonusOverall), sSurvivorState[i]);
    }

    if (InSecondHalfOfRound() && bTiebreakerEligibility[0] && bTiebreakerEligibility[1])
    {
        PrintToChatAll("%s\x03TIEBREAKER\x01: Team \x04%#1\x01 - \x05%i\x01, Team \x04%#2\x01 - \x05%i\x01", PLUGIN_TAG, iSiDamage[0], iSiDamage[1]);
        if (iSiDamage[0] == iSiDamage[1])
        {
            PrintToChatAll("%s\x05Teams have performed absolutely equal! Impossible to decide a clear round winner", PLUGIN_TAG);
        }
    }

    return Plugin_Stop;
}

Float:GetSurvivorHealthBonus()
{
    new Float:fPotentialMaxTeamHB = 0.0; 
    new survivalMultiplier = 0; 
    new survivorCount = 0;    

    for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
    {
        if (IsSurvivor(i))
        {
            survivorCount++;
            if (IsPlayerAlive(i) && !IsPlayerIncap(i) && !IsPlayerLedged(i))
            {
                survivalMultiplier++;
                fPotentialMaxTeamHB += (100.0 * fPermHpWorth);
            }
        }
    }

    if (survivalMultiplier == 0) 
    {
        #if SM2_DEBUG
        PrintToChatAll("\x01[GetSurvivorHealthBonus] 没有符合条件的生还者 (survivalMultiplier 为 0)。返回 0.0 HB。");
        #endif
        return 0.0;
    }

    new Float:fCurrentCalculatedHB = fPotentialMaxTeamHB - g_fAccumulatedPermHPLossBonus[InSecondHalfOfRound()];

    #if SM2_DEBUG
    PrintToChatAll("\x01[GetSurvivorHealthBonus] 理论最大团队HB (基于 %d 个生还者): %.2f。累计永久HB损失: %.2f。计算得到HB: %.2f",
        survivalMultiplier, fPotentialMaxTeamHB, g_fAccumulatedPermHPLossBonus[InSecondHalfOfRound()], fCurrentCalculatedHB);
    #endif

    return (fCurrentCalculatedHB > 0.0) ? fCurrentCalculatedHB : 0.0; 
}

Float:GetSurvivorDamageBonus()
{
    new survivalMultiplier = GetAliveSurvivorCount(); 
    if (iTeamSize == 0 || survivalMultiplier == 0) return 0.0; 

    new Float:fDamageBonus = (fMapTempHealthBonus - float(iLostTempHealth[InSecondHalfOfRound()])) * fTempHpWorth;
    fDamageBonus = fDamageBonus / iTeamSize * survivalMultiplier; 

#if SM2_DEBUG
    PrintToChatAll("\x01Calculating temp hp bonus: Base Map Temp HP Bonus: %.1f, Lost Temp HP: %d, Temp HP Worth: %.3f. Initial Damage Bonus: \x05%.1f\x01 (eligible survivors: \x05%d\x01)", fMapTempHealthBonus, iLostTempHealth[InSecondHalfOfRound()], fTempHpWorth, (fMapTempHealthBonus - float(iLostTempHealth[InSecondHalfOfRound()])) * fTempHpWorth, survivalMultiplier);
#endif
    return (fDamageBonus > 0.0) ? fDamageBonus : 0.0;
}

Float:GetSurvivorPillBonus()
{
    new pillsBonus;
    new survivorCount;
    for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
    {
        if (IsSurvivor(i))
        {
            survivorCount++;
            if (IsPlayerAlive(i) && !IsPlayerIncap(i) && HasPills(i))
            {
                pillsBonus += iPillWorth;
            #if SM2_DEBUG
                PrintToChatAll("\x01Adding \x05%N's\x01 pills contribution, total bonus: \x05%d\x01 pts", i, pillsBonus);
            #endif
            }
        }
    }
    return Float:float(pillsBonus);
}

Float:GetSurvivorMedkitBonus()
{
    new medkitBonus; 
    new survivorCount; 
    for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++) 
    {
        if (IsSurvivor(i)) 
        {
            survivorCount++; 
            if (IsPlayerAlive(i) && !IsPlayerIncap(i) && HasMedkit(i)) 
            {
                medkitBonus += iMedkitWorth; 
            #if SM2_DEBUG
                PrintToChatAll("\x01Adding \x05%N's\x01 medkit contribution, total bonus: \x05%d\x01 pts", i, medkitBonus); 
            #endif
            }
        }
    }
    return Float:float(medkitBonus); 
}

Float:GetSurvivorAdrenalineBonus()
{
    new adrenalineBonus; 
    new survivorCount; 
    for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++) 
    {
        if (IsSurvivor(i)) 
        {
            survivorCount++; 
            if (IsPlayerAlive(i) && !IsPlayerIncap(i) && HasAdrenaline(i)) 
            {
                adrenalineBonus += iAdrenalineWorth; 
            #if SM2_DEBUG
                PrintToChatAll("\x01Adding \x05%N's\x01 adrenaline contribution, total bonus: \x05%d\x01 pts", i, adrenalineBonus); 
            #endif
            }
        }
    }
    return Float:float(adrenalineBonus); 
}


Float:CalculateBonusPercent(Float:score, Float:maxbonus = -1.0)
{
    new Float:effectiveMaxBonus = maxbonus;
    if (maxbonus == -1.0) 
    {
        effectiveMaxBonus = fMapHealthBonus + fMapDamageBonus + float(iPillWorth * iTeamSize) + float(iMedkitWorth * iTeamSize) + float(iAdrenalineWorth * iTeamSize);
    }

    if (effectiveMaxBonus == 0.0) return 0.0; 
    return (score / effectiveMaxBonus) * 100.0; 
}


/************/
/** Stocks **/
/************/

InSecondHalfOfRound()
{
    return GameRules_GetProp("m_bInSecondHalfOfRound");
}

bool:IsSurvivor(client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2;
}

bool:IsAnyInfected(entity)
{
    if (entity > 0 && entity <= MaxClients)
    {
        return IsClientInGame(entity) && GetClientTeam(entity) == 3;
    }
    else if (entity > MaxClients)
    {
        decl String:classname[64];
        GetEdictClassname(entity, classname, sizeof(classname));
        if (StrEqual(classname, "infected") || StrEqual(classname, "witch") || StrEqual(classname, "tank") || StrEqual(classname, "spitter") || StrEqual(classname, "jockey") || StrEqual(classname, "hunter") || StrEqual(classname, "charger") || StrEqual(classname, "smoker") || StrEqual(classname, "boomer"))
        {
            return true;
        }
    }
    return false;
}

bool:IsPlayerIncap(client)
{
    return bool:GetEntProp(client, Prop_Send, "m_isIncapacitated");
}

bool:IsPlayerLedged(client)
{
    return bool:(GetEntProp(client, Prop_Send, "m_isHangingFromLedge") | GetEntProp(client, Prop_Send, "m_isFallingFromLedge"));
}

GetAliveSurvivorCount(bool uprightOnly = true)
{
    new survivorCount, aliveCount, uprightCount;

    for (new i = 1; i <= MaxClients && survivorCount < iTeamSize; i++)
    {
        if (IsSurvivor(i))
        {
            survivorCount++;

            if (IsPlayerAlive(i))
                aliveCount++;

            if (IsPlayerAlive(i) && !IsPlayerIncap(i) && !IsPlayerLedged(i)) 
                uprightCount++;
        }
    }

    return uprightOnly ? uprightCount : aliveCount;
}

GetSurvivorTemporaryHealth(client)
{
    if (!IsSurvivor(client) || !IsPlayerAlive(client)) return 0;
    new Float:healthBuffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
    new Float:healthBufferTime = GetEntPropFloat(client, Prop_Send, "m_healthBufferTime");
    new Float:decayRate = GetConVarFloat(FindConVar("pain_pills_decay_rate"));
    new Float:elapsedTime = GetGameTime() - healthBufferTime;

    new temphp = RoundToCeil(healthBuffer - (elapsedTime * decayRate));
    return (temphp > 0 ? temphp : 0);
}

GetSurvivorPermanentHealth(client)
{
    if (!IsSurvivor(client)) return 0;
    if (GetEntProp(client, Prop_Send, "m_currentReviveCount") > 0 && IsPlayerIncap(client)) return 0;

    new health = GetEntProp(client, Prop_Send, "m_iHealth");
    return (health > 0 ? health : 0);
}

bool:HasPills(client)
{
    new item = GetPlayerWeaponSlot(client, 4); 
    if (IsValidEdict(item))
    {
        decl String:buffer[64];
        GetEdictClassname(item, buffer, sizeof(buffer));
        return StrEqual(buffer, "weapon_pain_pills");
    }
    return false;
}

bool:HasMedkit(client)
{
    new item = GetPlayerWeaponSlot(client, 3); 
    if (IsValidEdict(item)) 
    {
        decl String:buffer[64];
        GetEdictClassname(item, buffer, sizeof(buffer)); 
        return StrEqual(buffer, "weapon_first_aid_kit"); 
    }
    return false; 
}

bool:HasAdrenaline(client)
{
    new item = GetPlayerWeaponSlot(client, 4); 
    if (IsValidEdict(item)) 
    {
        decl String:buffer[64];
        GetEdictClassname(item, buffer, sizeof(buffer)); 
        return StrEqual(buffer, "weapon_adrenaline"); 
    }
    return false; 
}