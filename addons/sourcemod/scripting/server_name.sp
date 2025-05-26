#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

ConVar
    cvarServerNameFormatCase1,
    cvarMpGameMode,
    cvarHostName,
    cvarMainName,
    cvarMod,
    cvarHostPort;

Handle
    HostName = INVALID_HANDLE;
char
    SavePath[256],
    g_sDefaultN[68];
static Handle
    g_hHostNameFormat;

public Plugin myinfo =
{
    name = "[L4D2]Server Name",
    author = "东,奈",
    description = "动态修改服务器名称",
    version = "1.4", // Incremented version
    url = "https://github.com/NanakaNeko/l4d2_plugins_coop"
};

public void OnPluginStart()
{
    HostName = CreateKeyValues("servername");
    BuildPath(Path_SM, SavePath, sizeof(SavePath), "data/servername.txt");
    if (FileExists(SavePath))
    {
        FileToKeyValues(HostName, SavePath);
    }

    cvarHostName	= FindConVar("hostname");
    cvarHostPort = FindConVar("hostport");
    cvarMainName = CreateConVar("sn_main_name", "XR对抗服");
    g_hHostNameFormat = CreateConVar("sn_hostname_format", "{hostname}{gamemode}");
    cvarServerNameFormatCase1 = CreateConVar("sn_hostname_format1", "{Full}{MOD}{Confogl}");
    cvarMod = FindConVar("l4d2_addons_eclipse");

    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("player_bot_replace", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("bot_player_replace", Event_PlayerTeam, EventHookMode_Post);

    Update();
}

public void OnPluginEnd()
{
    cvarMpGameMode = null;
    cvarMod = null;
}

public void OnAllPluginsLoaded()
{
    cvarMpGameMode = FindConVar("l4d_ready_cfg_name");
    cvarMod = FindConVar("l4d2_addons_eclipse");
}

public void OnConfigsExecuted()
{
    if(cvarMpGameMode != null){
        cvarMpGameMode.AddChangeHook(OnCvarChanged);
    }else if(FindConVar("l4d_ready_cfg_name")){
        cvarMpGameMode = FindConVar("l4d_ready_cfg_name");
        cvarMpGameMode.AddChangeHook(OnCvarChanged);
    }

    if(cvarMod != null){
        cvarMod.AddChangeHook(OnCvarChanged);
    }else if(FindConVar("l4d2_addons_eclipse")){
        cvarMod = FindConVar("l4d2_addons_eclipse");
        cvarMod.AddChangeHook(OnCvarChanged);
    }
    Update();
}

public void Event_PlayerTeam( Event hEvent, const char[] sName, bool bDontBroadcast )
{
    Update();
}

public void OnMapStart()
{
    HostName = CreateKeyValues("servername");
    BuildPath(Path_SM, SavePath, sizeof(SavePath), "data/servername.txt");
    if (FileExists(SavePath))
    {
        FileToKeyValues(HostName, SavePath);
    }
}

public void Update()
{
    if(cvarMpGameMode == null){
        ChangeServerName(); // Will call with default empty sGameModeSpecificText
    }else{
        UpdateServerName(); // Will call ChangeServerName with constructed game mode part
    }
}

public void OnCvarChanged(ConVar cvar, const char[] oldVal, const char[] newVal)
{
    Update();
}

public void UpdateServerName(){
    char sReadyUpCfgName[128];
    char sGameModePart[128]; // This buffer will hold the constructed game mode string part
    char buffer[128];

    GetConVarString(cvarServerNameFormatCase1, sGameModePart, sizeof(sGameModePart)); // e.g., "{Full}{MOD}{Confogl}"
    GetConVarString(cvarMpGameMode, sReadyUpCfgName, sizeof(sReadyUpCfgName));

    if(StrContains(sReadyUpCfgName, "applemod", false)!=-1){
        ReplaceString(sGameModePart, sizeof(sGameModePart), "{Confogl}","[进阶包抗]");
    }
    else if(StrContains(sReadyUpCfgName, "xr4v4charger", false)!=-1){
        ReplaceString(sGameModePart, sizeof(sGameModePart), "{Confogl}","[全牛4v4测试]");
    }
    else{
        GetConVarString(cvarMpGameMode, buffer, sizeof(buffer));
        if (strlen(buffer) > 0) {
            Format(buffer, sizeof(buffer),"[%s]", buffer);
            ReplaceString(sGameModePart, sizeof(sGameModePart), "{Confogl}", buffer);
        } else {
            ReplaceString(sGameModePart, sizeof(sGameModePart), "{Confogl}", "");
        }
    }

    if(IsTeamFull()){
        ReplaceString(sGameModePart, sizeof(sGameModePart), "{Full}", "");
    }else
    {
        ReplaceString(sGameModePart, sizeof(sGameModePart), "{Full}", "[缺人]");
    }

    if(cvarMod == null || (cvarMod != null && GetConVarInt(cvarMod) != 0)){
        ReplaceString(sGameModePart, sizeof(sGameModePart), "{MOD}", "");
    }else
    {
        ReplaceString(sGameModePart, sizeof(sGameModePart), "{MOD}", "[无MOD]");
    }
    // sGameModePart now contains something like "[缺人][无MOD][进阶包抗]"
    ChangeServerName(sGameModePart);
}

bool IsTeamFull(){
    int sum = 0;
    for(int i = 1; i <= MaxClients; i++){
        if(IsPlayer(i) && !IsFakeClient(i)){
            sum ++;
        }
    }

    if(sum == 0){
        return true;
    }
    return sum >= (GetConVarInt(FindConVar("survivor_limit")) + GetConVarInt(FindConVar("z_max_player_zombies")));
}

bool IsPlayer(int client)
{
    if(IsValidClient(client) && (GetClientTeam(client) == 2 || GetClientTeam(client) == 3)){
        return true;
    }
    else{
        return false;
    }
}

// Refactored ChangeServerName function
// sGameModeSpecificText is an INPUT: it's the part like "[缺人][MOD][模式]" or ""
void ChangeServerName(char[] sGameModeSpecificText = "")
{
    char sFinalHostname[128];    // Local buffer to build the complete server name
    char sBaseHostname[128];     // To store the base part (from file or cvarMainName)
    char sServerPort[128];
    bool bBaseHostnameFound = false;

    GetConVarString(cvarHostPort, sServerPort, sizeof(sServerPort));
    KvJumpToKey(HostName, sServerPort, false); // Attempt to jump to port-specific section

    // Try to get base hostname from file for the current port
    if (KvGetString(HostName, "hostname", sBaseHostname, sizeof(sBaseHostname)))
    {
        bBaseHostnameFound = true;
    }
    KvGoBack(HostName); // Go back to the root of HostName KeyValues, regardless of KvGetString outcome

    // If not found in file for this port, use the default sn_main_name
    if (!bBaseHostnameFound)
    {
        GetConVarString(cvarMainName, sBaseHostname, sizeof(sBaseHostname));
    }

    // sBaseHostname now contains the base name part.
    // Get the overall format string like "{hostname}{gamemode}"
    char sFormatPattern[128];
    GetConVarString(g_hHostNameFormat, sFormatPattern, sizeof(sFormatPattern));

    // Replace {hostname} placeholder with the determined sBaseHostname
    ReplaceString(sFormatPattern, sizeof(sFormatPattern), "{hostname}", sBaseHostname);

    // Replace {gamemode} placeholder with the provided sGameModeSpecificText (which might be empty)
    ReplaceString(sFormatPattern, sizeof(sFormatPattern), "{gamemode}", sGameModeSpecificText);

    // sFormatPattern now holds the fully constructed hostname. Copy it to sFinalHostname.
    // Although sFormatPattern could be used directly, copying to sFinalHostname is fine.
    strcopy(sFinalHostname, sizeof(sFinalHostname), sFormatPattern);

    // Set the game's hostname convar
    SetConVarString(cvarHostName, sFinalHostname);
    // Store it in g_sDefaultN as well
    Format(g_sDefaultN, sizeof(g_sDefaultN), "%s", sFinalHostname);
}

public bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client));
}