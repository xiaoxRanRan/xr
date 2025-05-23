#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <adminmenu>
#include <readyup>

#define PLUGIN_VERSION "1.9.1"
#define BAN_FILE "data/quickleave_active_bans.txt"

// --- 结构体 ---
enum struct BannedPlayer
{
    char sName[MAX_NAME_LENGTH];
    char sSteamID[64]; // SteamID64
    int iBanExpireTime;
}

// --- 全局变量 ---
ConVar g_cvEnable;
ConVar g_cvBanTime;
ConVar g_cvThresholdTime;
ConVar g_cvImmunityFlag;
ConVar g_cvReadyupOnly;
ConVar g_cvPlayerThreshold; // 触发封禁所需的最大玩家数
ConVar g_cvDebugMode;

ArrayList g_hQuickBannedPlayers;
char g_szBanFilePath[PLATFORM_MAX_PATH];

bool g_bIsMapChanging = false;
TopMenu g_hTopMenu = null;
float g_fPlayerConnectTime[MAXPLAYERS + 1]; // 玩家连接服务器的时间
bool g_bPlayerDisconnecting[MAXPLAYERS + 1]; // 标记玩家是否正在断开连接

public Plugin myinfo =
{
    name = "L4D2 快速离开封禁",
    author = "染一",
    description = "封禁快速离开的玩家",
    version = PLUGIN_VERSION,
    url = "https://www.sourcemod.net/"
};

public void OnPluginStart()
{
    g_cvEnable = CreateConVar("sm_quickleave_enable", "1", "启用/禁用快速离开封禁插件。(0=禁用, 1=启用)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvBanTime = CreateConVar("sm_quickleave_bantime", "5", "对快速离开者设定的封禁时长 (分钟)。", FCVAR_NOTIFY, true, 1.0);
    g_cvThresholdTime = CreateConVar("sm_quickleave_threshold", "60", "加入后多少秒内离开会触发封禁。", FCVAR_NOTIFY, true, 10.0);
    g_cvImmunityFlag = CreateConVar("sm_quickleave_immunity_flag", "b", "免于快速离开封禁所需的管理员标记。留空则无豁免。", FCVAR_NOTIFY);
    g_cvReadyupOnly = CreateConVar("sm_quickleave_readyup_only", "1", "是否仅在readyup准备阶段触发封禁。(0=全时段, 1=仅准备阶段)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvPlayerThreshold = CreateConVar("sm_quickleave_player_threshold", "8", "仅当服务器人数小于此值时触发封禁。设为0则无限制。", FCVAR_NOTIFY, true, 0.0, true, 32.0);
    g_cvDebugMode = CreateConVar("sm_quickleave_debug", "0", "是否启用调试模式，输出更多日志。(0=关闭, 1=启用)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig(true, "l4d2_quick_leave_ban");

    BuildPath(Path_SM, g_szBanFilePath, sizeof(g_szBanFilePath), BAN_FILE);
    g_hQuickBannedPlayers = new ArrayList(sizeof(BannedPlayer));

    LoadBansFromFile();
    CleanupExpiredBans(true);

    RegServerCmd("changelevel", Command_MapChangeCommand);
    RegServerCmd("map", Command_MapChangeCommand);
    RegAdminCmd("sm_qlm", Command_QuickLeaveMenu, ADMFLAG_UNBAN, "打开菜单以解封被快速离开插件封禁的玩家。");
    RegAdminCmd("sm_ql_sync", Command_SyncFileBans, ADMFLAG_ROOT, "同步封禁文件:若文件中条目被删除,则解封对应玩家。");

    // 添加事件钩子，保留回合开始和玩家断开连接事件
    HookEvent("round_start", Event_RoundStart);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

    if (LibraryExists("adminmenu")) OnAdminMenuReady(null);
    
    // 初始化玩家数组
    for (int i = 1; i <= MaxClients; i++) {
        g_fPlayerConnectTime[i] = 0.0;
        g_bPlayerDisconnecting[i] = false;
    }
}

public void OnLibraryAdded(const char[] name) { if (StrEqual(name, "adminmenu")) OnAdminMenuReady(null); }

public void OnAdminMenuReady(Handle topMenu) 
{
    if (topMenu == null && g_hTopMenu != null) return;
    if (topMenu != null && g_hTopMenu == topMenu) return;

    if (topMenu == null) {
        TopMenu adminTopMenuHandle = GetAdminTopMenu();
        if (adminTopMenuHandle != null) {
             g_hTopMenu = adminTopMenuHandle;
        }
    } else {
        g_hTopMenu = TopMenu.FromHandle(topMenu);
    }

    if (g_hTopMenu != null) {
        TopMenuObject cat = g_hTopMenu.FindCategory("ql_category_l4d2_file_v191");
        if (cat == INVALID_TOPMENUOBJECT) {
            cat = g_hTopMenu.AddCategory("ql_category_l4d2_file_v191", 
                                       Handler_TopCategory,
                                       "快速离开封禁",
                                       ADMFLAG_GENERIC);
        }
        if (cat != INVALID_TOPMENUOBJECT) {
            g_hTopMenu.AddItem("sm_qlm", AdminMenu_QuickLeaveMenu, cat, "管理快速离开封禁", ADMFLAG_UNBAN);
            g_hTopMenu.AddItem("sm_ql_sync", AdminMenu_SyncFileBans, cat, "同步封禁文件", ADMFLAG_ROOT);
        } else {
            PrintToServer("[快速离开封禁] 警告:无法创建或找到菜单分类 'ql_category_l4d2_file_v191'。");
        }
    } else {
        PrintToServer("[快速离开封禁] 警告:无法获取顶层菜单句柄,管理员菜单集成失败。");
    }
}

public int Handler_TopCategory(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
    {
        FormatEx(buffer, maxlength, "快速离开封禁管理");
    }
    return 0;
}

public void AdminMenu_QuickLeaveMenu(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        FormatEx(buffer, maxlength, "管理快速离开封禁");
    }
    else if (action == TopMenuAction_SelectOption)
    {
        Command_QuickLeaveMenu(param, 0);
    }
}

public void AdminMenu_SyncFileBans(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        FormatEx(buffer, maxlength, "同步封禁文件");
    }
    else if (action == TopMenuAction_SelectOption)
    {
        Command_SyncFileBans(param, 0);
    }
}

public void OnPluginEnd() { if (g_hQuickBannedPlayers != null) delete g_hQuickBannedPlayers; }
public Action Command_MapChangeCommand(int args) { g_bIsMapChanging = true; PrintToServer("[快速离开封禁] 地图切换已启动,暂时停止封禁。"); return Plugin_Continue; }

// 处理玩家断开连接前的事件
public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;
    
    // 标记玩家正在断开连接
    g_bPlayerDisconnecting[client] = true;
    
    if (g_cvDebugMode.BoolValue) {
        char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
        PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 正在断开连接, 连接时间: %.2f 秒", 
            client, steamID, GetGameTime() - g_fPlayerConnectTime[client]);
    }
    
    // 这里调用检查函数来处理玩家离开
    ProcessPlayerDisconnect(client);
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // 在回合开始时重置所有玩家的连接时间
    for (int i = 1; i <= MaxClients; i++)
    {
        g_fPlayerConnectTime[i] = 0.0;
        g_bPlayerDisconnecting[i] = false;
    }
    
    if (g_cvDebugMode.BoolValue) {
        PrintToServer("[快速离开封禁] [调试] 回合开始，重置所有玩家数据");
    }
}

public void OnMapStart() {
    g_bIsMapChanging = false;
    PrintToServer("[快速离开封禁] 新地图已开始,封禁逻辑已激活。");
    for (int i = 1; i <= MaxClients; i++) {
        g_fPlayerConnectTime[i] = 0.0;
        g_bPlayerDisconnecting[i] = false;
    }
    
    if (g_cvDebugMode.BoolValue) {
        PrintToServer("[快速离开封禁] [调试] 地图开始，重置所有玩家数据");
    }
}

public void OnClientPutInServer(int client) {
    if (!g_cvEnable.BoolValue || IsFakeClient(client)) return;
    
    // 玩家加入服务器时记录连接时间
    g_fPlayerConnectTime[client] = GetGameTime();
    g_bPlayerDisconnecting[client] = false;
    
    // 增加readyup检查，仅在准备阶段才记录连接时间
    if (g_cvReadyupOnly.BoolValue && !IsInReady()) {
        if (g_cvDebugMode.BoolValue) {
            PrintToServer("[快速离开封禁] [调试] 玩家 %N 加入服务器，但不在ready阶段，重置连接时间", client);
        }
        g_fPlayerConnectTime[client] = 0.0;
        return;
    }
    
    if (g_cvDebugMode.BoolValue) {
        char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
        PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 加入服务器，记录连接时间: %.2f", 
            client, steamID, g_fPlayerConnectTime[client]);
    }
}

// 处理离开事件
void ProcessPlayerDisconnect(int client) {
    if (!g_cvEnable.BoolValue || IsFakeClient(client) || g_fPlayerConnectTime[client] == 0.0) {
        g_fPlayerConnectTime[client] = 0.0;
        g_bPlayerDisconnecting[client] = false;
        return;
    }
    
    // 增加readyup检查，仅在准备阶段触发封禁
    if (g_cvReadyupOnly.BoolValue && !IsInReady()) {
        PrintToServer("[快速离开封禁] 玩家 %N 不在准备阶段离开,不执行封禁。", client);
        
        if (g_cvDebugMode.BoolValue) {
            char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
            PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 不在准备阶段离开，已豁免封禁", client, steamID);
        }
        
        g_fPlayerConnectTime[client] = 0.0;
        g_bPlayerDisconnecting[client] = false;
        return;
    }
    
    // 检查服务器人数，只在人数少于阈值时触发封禁
    int playerCount = GetPlayerCount();
    int threshold = g_cvPlayerThreshold.IntValue;
    
    if (threshold > 0 && playerCount >= threshold) {
        PrintToServer("[快速离开封禁] 玩家 %N 离开时服务器人数为 %d，大于或等于阈值 %d，不执行封禁。", 
            client, playerCount, threshold);
        
        if (g_cvDebugMode.BoolValue) {
            char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
            PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 离开时服务器人数(%d)>=阈值(%d)，不执行封禁", 
                client, steamID, playerCount, threshold);
        }
        
        g_fPlayerConnectTime[client] = 0.0;
        g_bPlayerDisconnecting[client] = false;
        return;
    }
    
    if (g_bIsMapChanging) {
        PrintToServer("[快速离开封禁] 玩家 %N 在地图切换期间断开连接,不执行封禁。", client);
        
        if (g_cvDebugMode.BoolValue) {
            char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
            PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 在地图切换期间离开，已豁免封禁", client, steamID);
        }
        
        g_fPlayerConnectTime[client] = 0.0;
        g_bPlayerDisconnecting[client] = false;
        return;
    }

    float timeSpent = GetGameTime() - g_fPlayerConnectTime[client];
    float timeThreshold = g_cvThresholdTime.FloatValue;

    char sImmunityFlag[8]; g_cvImmunityFlag.GetString(sImmunityFlag, sizeof(sImmunityFlag));
    if (sImmunityFlag[0] != '\0') {
        AdminId admin = GetUserAdmin(client);
        if (admin != INVALID_ADMIN_ID && GetAdminFlag(admin, view_as<AdminFlag>(ReadFlagString(sImmunityFlag)))) {
            PrintToServer("[快速离开封禁] 玩家 %N 拥有豁免权,不执行封禁。", client);
            
            if (g_cvDebugMode.BoolValue) {
                char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
                PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 拥有管理员豁免权，已豁免封禁", client, steamID);
            }
            
            g_fPlayerConnectTime[client] = 0.0;
            g_bPlayerDisconnecting[client] = false;
            return;
        }
    }

    if (timeSpent < timeThreshold && timeSpent >= 0.0) {
        char steamID64[64], playerName[MAX_NAME_LENGTH];
        GetClientName(client, playerName, sizeof(playerName));
        if (!GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64), true) ||
            strcmp(steamID64, "STEAM_ID_PENDING", false) == 0 || strcmp(steamID64, "BOT", false) == 0) {
            PrintToServer("[快速离开封禁] 无法获取玩家 %N 的有效SteamID64,无法封禁。", client);
            
            if (g_cvDebugMode.BoolValue) {
                PrintToServer("[快速离开封禁] [调试] 玩家 %N 的SteamID无效，无法执行封禁", client);
            }
            
            g_fPlayerConnectTime[client] = 0.0;
            g_bPlayerDisconnecting[client] = false;
            return;
        }

        int banMinutes = g_cvBanTime.IntValue;
        char banReasonPlayer[128], banReasonAdmin[128];
        FormatEx(banReasonPlayer, sizeof(banReasonPlayer), "[自动处罚] 您因在准备阶段 %.0f 秒内迅速离开服务器而被临时封禁 %d 分钟。", timeThreshold, banMinutes);
        FormatEx(banReasonAdmin, sizeof(banReasonAdmin), "[QuickLeaveBan] Quick Leave during ReadyUp (<%.0fs)", timeThreshold);

        if (g_cvDebugMode.BoolValue) {
            PrintToServer("[快速离开封禁] [调试] 执行封禁 - 玩家 %N (%s), 停留时间: %.2f 秒, 封禁时长: %d 分钟", 
                client, steamID64, timeSpent, banMinutes);
        }

        BanClient(client, banMinutes, BANFLAG_AUTHID, steamID64, banReasonAdmin, banReasonPlayer, 0);
        PrintToServer("[快速离开封禁] 玩家 %s (%s) 因在准备阶段 %.2f 秒内离开服务器而被封禁 %d 分钟。服务器人数: %d/%d", 
            playerName, steamID64, timeSpent, banMinutes, playerCount, threshold);
        LogAction(0, client, "\"%L\" (SteamID %s) 被插件自动封禁 %d 分钟 (原因: 准备阶段迅速离开服务器,停留 %.2f 秒,服务器人数 %d/%d)。", 
            client, steamID64, banMinutes, timeSpent, playerCount, threshold);

        BannedPlayer bp;
        strcopy(bp.sName, sizeof(bp.sName), playerName);
        strcopy(bp.sSteamID, sizeof(bp.sSteamID), steamID64);
        bp.iBanExpireTime = GetTime() + (banMinutes * 60);

        bool found = false;
        for(int i=0; i<g_hQuickBannedPlayers.Length; i++) {
            BannedPlayer temp_bp;
            g_hQuickBannedPlayers.GetArray(i, temp_bp);
            if(StrEqual(temp_bp.sSteamID, bp.sSteamID)) {
                g_hQuickBannedPlayers.SetArray(i, bp);
                found = true;
                break;
            }
        }
        if(!found) g_hQuickBannedPlayers.PushArray(bp);
        SaveBansToFile();
    } else {
        if (g_cvDebugMode.BoolValue) {
            char steamID[64]; GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID));
            PrintToServer("[快速离开封禁] [调试] 玩家 %N (%s) 停留时间 %.2f 秒超过阈值 %.2f 秒，不执行封禁", 
                client, steamID, timeSpent, timeThreshold);
        }
    }
    
    g_fPlayerConnectTime[client] = 0.0;
    g_bPlayerDisconnecting[client] = false;
}

// 获取当前服务器真实玩家数量（不包括机器人）
int GetPlayerCount()
{
    int count = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            count++;
        }
    }
    return count;
}

// ReadyUp相关的钩子函数
public void OnReadyUpInitiate()
{
    // 准备阶段开始时，在控制台上通知
    PrintToServer("[快速离开封禁] 准备阶段已开始,快速离开封禁已激活。");
    
    // 在准备阶段开始时重新记录所有玩家的连接时间
    if (g_cvEnable.BoolValue && g_cvReadyupOnly.BoolValue)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                g_fPlayerConnectTime[i] = GetGameTime();
                
                if (g_cvDebugMode.BoolValue) {
                    char steamID[64]; GetClientAuthId(i, AuthId_Steam2, steamID, sizeof(steamID));
                    PrintToServer("[快速离开封禁] [调试] 准备阶段 - 玩家 %N (%s) 连接时间已记录: %.2f", 
                        i, steamID, g_fPlayerConnectTime[i]);
                }
            }
        }
    }
}

public void OnRoundIsLive()
{
    // 回合正式开始，重置所有玩家的连接时间
    PrintToServer("[快速离开封禁] 回合已开始,快速离开封禁已停止。");
    
    if (g_cvReadyupOnly.BoolValue)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            g_fPlayerConnectTime[i] = 0.0;
        }
        
        if (g_cvDebugMode.BoolValue) {
            PrintToServer("[快速离开封禁] [调试] 回合正式开始，重置所有玩家的连接时间");
        }
    }
}

// 在玩家断开连接时完全清理
public void OnClientDisconnect(int client) {
    // 通过Event_PlayerDisconnect和ProcessPlayerDisconnect已经处理了逻辑
    // 这里只需要保证变量被重置
    g_fPlayerConnectTime[client] = 0.0;
    g_bPlayerDisconnecting[client] = false;
}

// 以下是原有功能未修改部分
public Action Command_QuickLeaveMenu(int adminId, int args) {
    if (adminId == 0) { ReplyToCommand(adminId, "[快速离开封禁] 此命令只能在游戏内由管理员执行。"); return Plugin_Handled; }
    CleanupExpiredBans(true);
    Menu menu = new Menu(MenuHandler_QuickLeaveUnban);
    menu.SetTitle("快速离开封禁 - 解封菜单:\n ");
    int currentTime = GetTime(), validEntries = 0;
    for (int i = 0; i < g_hQuickBannedPlayers.Length; i++) {
        BannedPlayer bp;
        g_hQuickBannedPlayers.GetArray(i, bp);
        if (bp.iBanExpireTime > currentTime) {
            int remSecsTotal = bp.iBanExpireTime - currentTime;
            char displayString[256];
            FormatEx(displayString, sizeof(displayString), "%s (%s)\n剩余: %d分 %02d秒", bp.sName, bp.sSteamID, remSecsTotal / 60, remSecsTotal % 60);
            menu.AddItem(bp.sSteamID, displayString);
            validEntries++;
        }
    }
    if (validEntries == 0) { menu.SetTitle("快速离开封禁 - 解封菜单:\n \n当前没有由本插件造成的有效封禁。"); menu.AddItem("no_bans", "没有有效封禁", ITEMDRAW_DISABLED); }
    menu.ExitButton = true; menu.Display(adminId, MENU_TIME_FOREVER);
    return Plugin_Handled;
}

public int MenuHandler_QuickLeaveUnban(Menu menu, MenuAction action, int adminId, int itemNum) {
    if (action == MenuAction_Select) {
        if (adminId == 0) return 0;
        char steamIDToUnban[64]; menu.GetItem(itemNum, steamIDToUnban, sizeof(steamIDToUnban));
        if (StrEqual(steamIDToUnban, "no_bans")) return 0;
        ServerCommand("sm_unban \"%s\"", steamIDToUnban);
        PrintToChat(adminId, "[快速离开封禁] 已尝试解封 SteamID: %s。", steamIDToUnban);
        LogAdminAction(adminId, -1, "\"%L\" 通过菜单解封了快速离开封禁的 SteamID \"%s\".", adminId, steamIDToUnban);
        for (int i = 0; i < g_hQuickBannedPlayers.Length; i++) {
            BannedPlayer bp;
            g_hQuickBannedPlayers.GetArray(i, bp);
            if (StrEqual(bp.sSteamID, steamIDToUnban)) {
                g_hQuickBannedPlayers.Erase(i);
                break;
            }
        }
        SaveBansToFile();
        Command_QuickLeaveMenu(adminId, 0);
    } else if (action == MenuAction_End) { delete menu; }
    return 0;
}

public Action Command_SyncFileBans(int adminId, int args) {
    if (adminId == 0 && !IsClientInGame(adminId)) { PrintToServer("[快速离开封禁] 控制台执行文件同步..."); }
    else if (!IsClientInGame(adminId) || !IsPlayerAdmin(adminId, view_as<AdminFlag>(ADMFLAG_ROOT))) {
        ReplyToCommand(adminId, "[快速离开封禁] 您没有权限执行此命令。");
        return Plugin_Handled;
    }
    ReplyToCommand(adminId, "[快速离开封禁] 开始同步封禁文件...");

    ArrayList bansFromFile = new ArrayList(sizeof(BannedPlayer));
    File file = OpenFile(g_szBanFilePath, "rt");
    if (file == null) {
        PrintToServer("[快速离开封禁] 无法打开封禁文件 '%s' 进行读取 (同步)。", g_szBanFilePath);
        ReplyToCommand(adminId, "[快速离开封禁] 错误:无法打开封禁文件进行读取。");
        delete bansFromFile;
        return Plugin_Handled;
    }

    char line[256], parts[3][128];
    while (file.ReadLine(line, sizeof(line))) {
        TrimString(line);
        if (strlen(line) == 0) continue;
        if (ExplodeString(line, "\t", parts, 3, sizeof(parts[])) == 3) {
            BannedPlayer bp;
            strcopy(bp.sSteamID, sizeof(bp.sSteamID), parts[0]);
            bp.iBanExpireTime = StringToInt(parts[1]);
            strcopy(bp.sName, sizeof(bp.sName), parts[2]);
            if (bp.iBanExpireTime > GetTime()) bansFromFile.PushArray(bp);
        }
    }
    delete file;

    int unbannedCount = 0;
    for (int i = g_hQuickBannedPlayers.Length - 1; i >= 0; i--) {
        BannedPlayer bpInMemory;
        g_hQuickBannedPlayers.GetArray(i, bpInMemory);
        bool foundInFile = false;
        for (int j = 0; j < bansFromFile.Length; j++) {
            BannedPlayer bpFromFileList;
            bansFromFile.GetArray(j, bpFromFileList);
            if (StrEqual(bpInMemory.sSteamID, bpFromFileList.sSteamID)) {
                foundInFile = true;
                if (bpFromFileList.iBanExpireTime > bpInMemory.iBanExpireTime) {
                    bpInMemory.iBanExpireTime = bpFromFileList.iBanExpireTime;
                    g_hQuickBannedPlayers.SetArray(i, bpInMemory);
                }
                break;
            }
        }
        if (!foundInFile && bpInMemory.iBanExpireTime > GetTime()) {
            ServerCommand("sm_unban \"%s\"", bpInMemory.sSteamID);
            PrintToServer("[快速离开封禁] [同步] 因文件记录被移除,已解封 SteamID: %s (%s)", bpInMemory.sSteamID, bpInMemory.sName);
            LogAction(adminId, -1, "[同步操作] 因文件记录移除,解封了 \"%s\" (SteamID %s)", bpInMemory.sName, bpInMemory.sSteamID);
            g_hQuickBannedPlayers.Erase(i);
            unbannedCount++;
        }
    }

    g_hQuickBannedPlayers.Clear();
    for (int i = 0; i < bansFromFile.Length; i++) {
        BannedPlayer bpToPush;
        bansFromFile.GetArray(i, bpToPush);
        g_hQuickBannedPlayers.PushArray(bpToPush);
    }
    SaveBansToFile();
    delete bansFromFile;
    ReplyToCommand(adminId, "[快速离开封禁] 文件同步完成。共解封了 %d 名因文件记录移除的玩家。", unbannedCount);
    PrintToServer("[快速离开封禁] 文件同步完成。");
    return Plugin_Handled;
}

void LoadBansFromFile() {
    g_hQuickBannedPlayers.Clear();
    File file = OpenFile(g_szBanFilePath, "rt");
    if (file == null) return;

    char line[256], parts[3][128];
    while (file.ReadLine(line, sizeof(line))) {
        TrimString(line);
        if (strlen(line) == 0) continue;
        if (ExplodeString(line, "\t", parts, 3, sizeof(parts[])) == 3) {
            BannedPlayer bp;
            strcopy(bp.sSteamID, sizeof(bp.sSteamID), parts[0]);
            bp.iBanExpireTime = StringToInt(parts[1]);
            strcopy(bp.sName, sizeof(bp.sName), parts[2]);
            if (bp.iBanExpireTime > GetTime()) g_hQuickBannedPlayers.PushArray(bp);
        } else { PrintToServer("[快速离开封禁] 警告: 封禁文件 '%s' 中发现格式错误的行: %s", g_szBanFilePath, line); }
    }
    delete file;
}

void SaveBansToFile() {
    File file = OpenFile(g_szBanFilePath, "wt");
    if (file == null) {
        PrintToServer("[快速离开封禁] 错误: 无法打开封禁文件 '%s' 进行写入!", g_szBanFilePath);
        LogError("无法写入快速离开封禁文件: %s", g_szBanFilePath);
        return;
    }

    int currentTime = GetTime(), savedCount = 0;
    for (int i = 0; i < g_hQuickBannedPlayers.Length; i++) {
        BannedPlayer bp;
        g_hQuickBannedPlayers.GetArray(i, bp);
        if (bp.iBanExpireTime > currentTime) {
            file.WriteLine("%s\t%d\t%s", bp.sSteamID, bp.iBanExpireTime, bp.sName);
            savedCount++;
        }
    }
    delete file;
}

void CleanupExpiredBans(bool alsoSaveToFile) {
    bool changed = false;
    int currentTime = GetTime();
    for (int i = g_hQuickBannedPlayers.Length - 1; i >= 0; i--) {
        BannedPlayer bp;
        g_hQuickBannedPlayers.GetArray(i, bp);
        if (bp.iBanExpireTime <= currentTime) {
            g_hQuickBannedPlayers.Erase(i);
            changed = true;
        }
    }
    if (changed && alsoSaveToFile) SaveBansToFile();
}

stock void LogAdminAction(int adminId, int targetId, const char[] format, any ...) {
    char buffer[256]; VFormat(buffer, sizeof(buffer), format, 4);
    if (adminId != 0 && IsClientInGame(adminId)) LogMessage("[%s 管理员] %s", PLUGIN_VERSION, buffer);
    else LogMessage("[%s 控制台] %s", PLUGIN_VERSION, buffer);
}

bool IsPlayerAdmin(int client, AdminFlag flag) {
    if (client <= 0 || client > MaxClients || !IsClientInGame(client)) return false;
    AdminId id = GetUserAdmin(client);
    if (id == INVALID_ADMIN_ID) return false;
    return GetAdminFlag(id, flag);
}