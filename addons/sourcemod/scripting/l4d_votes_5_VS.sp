#pragma semicolon 1
#pragma newdecls required	 //強制1.7以後的新語法
#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <multicolors>
#include <readyup>

#define SCORE_DELAY_EMPTY_SERVER 3.0
#define ZOMBIECLASS_SMOKER		 1
#define ZOMBIECLASS_BOOMER		 2
#define ZOMBIECLASS_HUNTER		 3
#define ZOMBIECLASS_SPITTER		 4
#define ZOMBIECLASS_JOCKEY		 5
#define ZOMBIECLASS_CHARGER		 6
#define ZOMBIECLASS_TANK		 8
#define MaxHealth				 100
#define VOTE_NO					 "no"
#define VOTE_YES				 "yes"
#define MENU_TIME				 20
#define L4D_TEAM_SPECTATE		 1
#define MAX_CAMPAIGN_LIMIT		 64
#define READY_RESTART_MAP_DELAY	 2

int	   Votey	 = 0;
int	   Voten	 = 0;
bool   game_l4d2 = false;
int	   kickplayer_userid;
char   kickplayer_name[MAX_NAME_LENGTH];
char   kickplayer_SteamId[MAX_NAME_LENGTH];
char   votesmaps[MAX_NAME_LENGTH];
char   votesmapsname[MAX_NAME_LENGTH];
ConVar g_Cvar_Limits;
ConVar VotensHpED;
ConVar VotensAlltalkED;
ConVar VotensRestartmapED;
ConVar VotensMapED;
ConVar VotensMap2ED;
ConVar VotensED;
ConVar VotensKickED;
ConVar VotensForceSpectateED;
ConVar VotensForceStartGameED;
ConVar g_hCvarPlayerLimit;
ConVar g_hKickImmueAccess;
int	   g_iCvarPlayerLimit;
Handle g_hVoteMenu = null;
float  lastDisconnectTime;
bool   ClientVoteMenu[MAXPLAYERS + 1];
int	   g_iCount;
char   g_sMapinfo[MAX_CAMPAIGN_LIMIT][MAX_NAME_LENGTH];
char   g_sMapname[MAX_CAMPAIGN_LIMIT][MAX_NAME_LENGTH];
float  g_fLimit;
bool   g_bEnable, VotensHpE_D, VotensAlltalkE_D, VotensRestartmapE_D,
	VotensMapE_D, VotensMap2E_D, g_bVotensKickED, g_bVotensForceSpectateED, g_bVotenForceDelLobby, VotensForceStartGameE_D;
char   g_sKickImmueAccesslvl[16];
int	   fsgclient;
ConVar VotenForceDelLobby;
ConVar hforcespectate_penalty;
int	   iforcespectate_penalty;
ConVar hvotedelay_time;
int	   ivotedelay_time;
// 添加ConVar
ConVar VotensHunterPitchLockED;
bool VotensHunterPitchLockE_D;

// 添加Hunter插件检查变量
bool g_bHunterPluginLoaded = false;
// Native函数声明
native bool IsHunterPitchLockEnabled();
native void SetHunterPitchLockEnabled(bool enabled);
enum voteType
{
	None,
	hp,
	alltalk,
	alltalk2,
	restartmap,
	kick,
	map,
	map2,
	forcespectate,
	forcedellobby,
	forcestartgame,
	hunterpitchlock,  // 新增

} voteType g_voteType = None;

int		   forcespectateid;
char	   forcespectateplayername[MAX_NAME_LENGTH];
static int g_iSpectatePenaltyCounter[MAXPLAYERS + 1];
static int g_votedelay;
int		   MapRestartDelay;
Handle	   MapCountdownTimer;
bool	   isMapRestartPending = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();

	if (test == Engine_Left4Dead) game_l4d2 = false;
	else if (test == Engine_Left4Dead2) game_l4d2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public Plugin myinfo =
{
	name		= "L4D2 Vote Menu but Versus",
	author		= "HarryPotter apples1949",
	description = "Votes Commands",
	version		= "6.1",
	url			= "https://github.com/apples1949/l4dplugins"
};

public void OnPluginStart()
{
	RegConsoleCmd("voteshp", Command_VoteHp);
	RegConsoleCmd("votesalltalk", Command_VoteAlltalk);
	RegConsoleCmd("votesalltalk2", Command_VoteAlltalk2);
	RegConsoleCmd("votesrestartmap", Command_VoteRestartmap);
	RegConsoleCmd("votesmapsmenu", Command_VotemapsMenu);
	RegConsoleCmd("votesmaps2menu", Command_Votemaps2Menu);
	RegConsoleCmd("voteskick", Command_VotesKick);
	RegConsoleCmd("sm_votes", Command_Votes, "open vote meun");
	RegConsoleCmd("sm_callvote", Command_Votes, "open vote meun");
	RegConsoleCmd("sm_callvotes", Command_Votes, "open vote meun");
	RegConsoleCmd("votesforcespectate", Command_Votesforcespectate);
	RegConsoleCmd("votesforcedellobby", Command_Votesforcedellobby);
	RegConsoleCmd("votesforcestartgame", Command_Votesforcestartgame);
	// 添加命令
    RegConsoleCmd("voteshunterpitchlock", Command_VoteHunterPitchLock);
	// 添加更多选项菜单命令
    RegConsoleCmd("sm_votes_more", Command_VotesMore, "open more vote options");
	
	RegAdminCmd("sm_restartmap", CommandRestartMap, ADMFLAG_CHANGEMAP, "sm_restartmap - changelevels to the current map");
	RegAdminCmd("sm_rs", CommandRestartMap, ADMFLAG_CHANGEMAP, "sm_restartmap - changelevels to the current map");

	g_Cvar_Limits		   = CreateConVar("sm_votes_s", "0.51", "超过这个百分比才能投票通过", 0, true, 0.05, true, 1.0);
	VotensHpED			   = CreateConVar("l4d_VotenshpED", "1", "如果为1，则开启回血投票选项", FCVAR_NOTIFY);
	VotensAlltalkED		   = CreateConVar("l4d_VotensalltalkED", "1", "如果为1，则开启调整全体语音投票选项", FCVAR_NOTIFY);
	VotensRestartmapED	   = CreateConVar("l4d_VotensrestartmapED", "1", "如果为1，则开启重置当前地图选项", FCVAR_NOTIFY);
	VotensMapED			   = CreateConVar("l4d_VotensmapED", "1", "如果为1，则开启投票更换官图选项", FCVAR_NOTIFY);
	VotensMap2ED		   = CreateConVar("l4d_Votensmap2ED", "0", "如果为1，则开启投票更换三方图选项", FCVAR_NOTIFY);
	VotensED			   = CreateConVar("l4d_Votens", "1", "如果为0，则关闭此插件，反之开启", FCVAR_NOTIFY);
	VotensKickED		   = CreateConVar("l4d_VotesKickED", "1", "如果为1，则开启投票踢出玩家选项", FCVAR_NOTIFY);
	VotensForceSpectateED  = CreateConVar("l4d_VotesForceSpectateED", "1", "如果为1，则开启投票强制玩家旁观选项", FCVAR_NOTIFY);
	VotenForceDelLobby	   = CreateConVar("l4d_VotesForceDelLobby", "1", "如果为1,则开启投票删除大厅选项", FCVAR_NOTIFY);
	VotensForceStartGameED = CreateConVar("l4d_VotesForceStartGame", "1", "如果为1，则开启投票强制开启readyup", FCVAR_NOTIFY);
	g_hCvarPlayerLimit	   = CreateConVar("sm_vote_player_limit", "2", "当有多少玩家才能启动插件", FCVAR_NOTIFY);
	g_hKickImmueAccess	   = CreateConVar("l4d_VotesKick_immue_access_flag", "z", "有这些标识的玩家不会被投票踢出以及强制旁观(无内容=所有人, -1:没有人)", FCVAR_NOTIFY);
	hforcespectate_penalty = CreateConVar("l4d_forcespectate_penalty", "10", "强制旁观多久才能重新加入队伍", FCVAR_NOTIFY);
	hvotedelay_time		   = CreateConVar("l4d_votedelay_time", "30", "多长时间才能发起新投票", FCVAR_NOTIFY);
    // 添加Hunter投票ConVar
    VotensHunterPitchLockED = CreateConVar("l4d_VotesHunterPitchLockED", "1", "如果为1,则开启Hunter俯仰角锁定投票选项", FCVAR_NOTIFY);
	HookEvent("round_start", event_Round_Start);

	GetCvars();
	g_Cvar_Limits.AddChangeHook(ConVarChanged_Cvars);
	VotensHpED.AddChangeHook(ConVarChanged_Cvars);
	VotensAlltalkED.AddChangeHook(ConVarChanged_Cvars);
	VotensRestartmapED.AddChangeHook(ConVarChanged_Cvars);
	VotensMapED.AddChangeHook(ConVarChanged_Cvars);
	VotensMap2ED.AddChangeHook(ConVarChanged_Cvars);
	VotensED.AddChangeHook(ConVarChanged_Cvars);
	VotensKickED.AddChangeHook(ConVarChanged_Cvars);
	VotensForceSpectateED.AddChangeHook(ConVarChanged_Cvars);
	VotenForceDelLobby.AddChangeHook(ConVarChanged_Cvars);
	VotensForceStartGameED.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarPlayerLimit.AddChangeHook(ConVarChanged_Cvars);
	g_hKickImmueAccess.AddChangeHook(ConVarChanged_Cvars);
	hforcespectate_penalty.AddChangeHook(ConVarChanged_Cvars);
	hvotedelay_time.AddChangeHook(ConVarChanged_Cvars);
	VotensHunterPitchLockED.AddChangeHook(ConVarChanged_Cvars);

	AutoExecConfig(true, "l4d_votes_5_VS");
}
public void OnNativeNotFound(const char[] name)
{
    if (StrEqual(name, "IsHunterPitchLockEnabled") || StrEqual(name, "SetHunterPitchLockEnabled"))
    {
        g_bHunterPluginLoaded = false;
    }
}
public void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_fLimit				 = g_Cvar_Limits.FloatValue;
	g_iCvarPlayerLimit		 = g_hCvarPlayerLimit.IntValue;
	VotensHpE_D				 = VotensHpED.BoolValue;
	VotensAlltalkE_D		 = VotensAlltalkED.BoolValue;
	VotensRestartmapE_D		 = VotensRestartmapED.BoolValue;
	VotensMapE_D			 = VotensMapED.BoolValue;
	VotensMap2E_D			 = VotensMap2ED.BoolValue;
	g_bVotensKickED			 = VotensKickED.BoolValue;
	g_bVotensForceSpectateED = VotensForceSpectateED.BoolValue;
	g_bVotenForceDelLobby	 = VotenForceDelLobby.BoolValue;
	VotensForceStartGameE_D	 = VotensForceStartGameED.BoolValue;
	g_bEnable				 = VotensED.BoolValue;
	g_hKickImmueAccess.GetString(g_sKickImmueAccesslvl, sizeof(g_sKickImmueAccesslvl));
	iforcespectate_penalty = hforcespectate_penalty.IntValue;
	ivotedelay_time		   = hvotedelay_time.IntValue;
	VotensHunterPitchLockE_D = VotensHunterPitchLockED.BoolValue;
}

bool g_enb;

public void OnRoundIsLive()
{
	g_enb = false;
}

public void OnReadyUpInitiate()
{
	g_enb = true;
}
public void OnAllPluginsLoaded()
{
    g_bHunterPluginLoaded = LibraryExists("hunter_pitch_lock");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "hunter_pitch_lock"))
        g_bHunterPluginLoaded = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "hunter_pitch_lock"))
        g_bHunterPluginLoaded = false;
}
public Action CommandRestartMap(int client, int args)
{
	if (!isMapRestartPending)
	{
		CPrintToChatAll("[{olive}VOTE{default}]地图将在{green}%d{default}秒后重置", READY_RESTART_MAP_DELAY + 1);
		RestartMapDelayed();
	}
	return Plugin_Handled;
}

void RestartMapDelayed()
{
	if (MapCountdownTimer == INVALID_HANDLE)
	{
		PrintHintTextToAll("请准备!\n地图将在 %d 秒后重置", READY_RESTART_MAP_DELAY + 1);
		isMapRestartPending = true;
		MapRestartDelay		= READY_RESTART_MAP_DELAY;
		MapCountdownTimer	= CreateTimer(1.0, timerRestartMap, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action timerRestartMap(Handle timer)
{
	if (MapRestartDelay == 0)
	{
		MapCountdownTimer = INVALID_HANDLE;
		RestartMapNow();
		return Plugin_Stop;
	}
	else
	{
		PrintHintTextToAll("请准备!\n地图将在 %d 秒后重置", MapRestartDelay);
		EmitSoundToAll("buttons/blip1.wav", _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		MapRestartDelay--;
	}
	return Plugin_Continue;
}

void RestartMapNow()
{
	isMapRestartPending = false;
	char currentMap[256];
	GetCurrentMap(currentMap, 256);
	ServerCommand("changelevel %s", currentMap);
}

public void event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
		ClientVoteMenu[i] = false;
}
//开局提示.
public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		CreateTimer(5.0, g_hTimerAnnounce, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	g_iSpectatePenaltyCounter[client] = iforcespectate_penalty;
}

public Action g_hTimerAnnounce(Handle timer, any client)
{
	if ((client = GetClientOfUserId(client)) && IsClientInGame(client))
	{
		CPrintToChat(client, "[{olive}VOTE{default}]{green}游戏自带投票已禁用! 你可以使用指令!votes进行以下投票:开关全体语音 重置地图 开始新图 强制踢出玩家或强制玩家旁观");	//聊天窗提示.
		CPrintToChat(client, "[{olive}VOTE{default}]{green}对了,如果有新手不会F1开始游戏,你也可以投票强制开始游戏哦!");
	}
	return Plugin_Continue;
}

public void OnMapStart()
{
	isMapRestartPending = false;
	MapCountdownTimer	= INVALID_HANDLE;

	ParseCampaigns();

	g_votedelay = 15;
	CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_iSpectatePenaltyCounter[i] = iforcespectate_penalty;
	}
	PrecacheSound("ui/menu_enter05.wav");
	PrecacheSound("ui/beep_synthtone01.wav");
	PrecacheSound("ui/beep_error01.wav");
	PrecacheSound("buttons/blip1.wav");

	VoteMenuClose();
}

public Action Command_Votes(int client, int args)
{
	if (client == 0)
	{
		PrintToServer("[VOTE] sm_votes cannot be used by server.");
		return Plugin_Handled;
	}
	if (GetClientTeam(client) == 1)
	{
		ReplyToCommand(client, "[VOTE] 旁观无法发起投票.");
		return Plugin_Handled;
	}

	ClientVoteMenu[client] = true;
	if (g_bEnable == true)
	{
		closereadyuphud(client);
		Handle menu = CreatePanel();
		SetPanelTitle(menu, "菜单");
		if (VotensHpE_D == false)
		{
			DrawPanelItem(menu, "全体回血(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "全体回血");
		}
		if (VotensAlltalkE_D == false)
		{
			DrawPanelItem(menu, "调整全体语音(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "调整全体语音");
		}
		if (VotensHunterPitchLockE_D == false || !g_bHunterPluginLoaded)
        {
            DrawPanelItem(menu, "Hunter简易天花板(禁用中)");
        }
        else
        {
            bool currentState = IsHunterPitchLockEnabled();
            char menuText[64];
            Format(menuText, sizeof(menuText), "%s Hunter简易天花板", currentState ? "关闭" : "开启");
            DrawPanelItem(menu, menuText);
        }
		if (VotensRestartmapE_D == false)
		{
			DrawPanelItem(menu, "重置当前地图(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "重置当前地图");
		}
		if (VotensMapE_D == false)
		{
			DrawPanelItem(menu, "投票更换官图(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "投票更换官图");
		}
		if (g_bVotensKickED == false)
		{
			DrawPanelItem(menu, "踢出玩家(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "踢出玩家");
		}
		if (g_bVotensForceSpectateED == false)
		{
			DrawPanelItem(menu, "强制玩家旁观(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "强制玩家旁观");
		}
		if (!VotensForceStartGameE_D || !g_enb)
		{
			DrawPanelItem(menu, "强制开始游戏(禁用中)");
		}
		else
		{
			DrawPanelItem(menu, "强制开始游戏");
		}
		DrawPanelItem(menu, "更多选项");

		DrawPanelText(menu, " \n");
		DrawPanelItem(menu, "退出");
		SendPanelToClient(menu, client, Votes_Menu, MENU_TIME);
		return Plugin_Handled;
	}
	else
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票菜单插件已关闭!");
	}

	return Plugin_Stop;
}
public Action Command_VotesMore(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    
    ClientVoteMenu[client] = true;
    if (g_bEnable == true)
    {
        closereadyuphud(client);
        Handle menu = CreatePanel();
        SetPanelTitle(menu, "更多投票选项");
        
        // 1. 投票更换三方图
        if (VotensMap2E_D == false)
        {
            DrawPanelItem(menu, "投票更换三方图(禁用中)");
        }
        else
        {
            DrawPanelItem(menu, "投票更换三方图");
        }
        
        // 2. 强制删除游戏大厅
        if (g_bVotenForceDelLobby == false)
        {
            DrawPanelItem(menu, "强制删除游戏大厅(禁用中)");
        }
        else
        {
            DrawPanelItem(menu, "强制删除游戏大厅");
        }
        
        DrawPanelText(menu, " \n");
        DrawPanelItem(menu, "返回主菜单");
        DrawPanelItem(menu, "退出");
        
        SendPanelToClient(menu, client, VotesMore_Menu, MENU_TIME);
        return Plugin_Handled;
    }
    else
    {
        CPrintToChat(client, "[{olive}VOTE{default}]投票菜单插件已关闭!");
    }
    return Plugin_Handled;
}
public int Votes_Menu(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 1:
			{
				if (VotensHpE_D == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]全体回血已禁用");
				}
				else if (VotensHpE_D == true)
				{
					FakeClientCommand(client, "voteshp");
				}
			}
			case 2:
			{
				if (VotensAlltalkE_D == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]调整全体语音已禁用");
				}
				else if (FindConVar("sv_alltalk").IntValue == 0)
				{
					FakeClientCommand(client, "votesalltalk");
				}
				else
				{
					FakeClientCommand(client, "votesalltalk2");
				}
			}
			case 3: // Hunter简易天花板锁定
            {
                if (VotensHunterPitchLockE_D == false || !g_bHunterPluginLoaded)
                {
                    FakeClientCommand(client, "sm_votes");
                    CPrintToChat(client, "[{olive}VOTE{default}]Hunter简易天花板投票已禁用或插件未加载");
                }
                else
                {
                    FakeClientCommand(client, "voteshunterpitchlock");
                }
            }
			case 4:
			{
				if (VotensRestartmapE_D == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]重置当前地图已禁用");
				}
				else if (VotensRestartmapE_D == true)
				{
					FakeClientCommand(client, "votesrestartmap");
				}
			}
			case 5:
			{
				if (VotensMapE_D == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]投票更换官图已禁用,请使用游戏自带投票");
				}
				else if (VotensMapE_D == true)
				{
					FakeClientCommand(client, "votesmapsmenu");
				}
			}
			case 6:
			{
				if (g_bVotensKickED == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]踢出玩家已禁用");
				}
				else if (g_bVotensKickED == true)
				{
					FakeClientCommand(client, "voteskick");
				}
			}
			case 7:
			{
				if (g_bVotensForceSpectateED == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]强制玩家旁观已禁用");
				}
				else if (g_bVotensForceSpectateED == true)
				{
					FakeClientCommand(client, "votesforcespectate");
				}
			}
			case 8:
			{
				if (VotensForceStartGameE_D == false)
				{
					FakeClientCommand(client, "sm_votes");
					CPrintToChat(client, "[{olive}VOTE{default}]强制开始已禁用");
				}
				else if (VotensForceStartGameE_D == true)
				{
					FakeClientCommand(client, "votesforcestartgame");
				}
			}
			case 9: // 更多选项
            {
                FakeClientCommand(client, "sm_votes_more"); // 创建第二页菜单
            }
			case 10:
			{
				ClientVoteMenu[client] = false;
				openreadyuphud(client);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		ClientVoteMenu[client] = false;
		openreadyuphud(client);
	}
	else if (action == MenuAction_End)
	{
		openreadyuphud(client);
		delete menu;
	}
	return 0;
}
public int VotesMore_Menu(Menu menu, MenuAction action, int client, int itemNum)
{
    if (action == MenuAction_Select)
    {
        switch (itemNum)
        {
            case 1: // 投票更换三方图
            {
                if (VotensMap2E_D == false)
                {
                    FakeClientCommand(client, "sm_votes_more");
                    CPrintToChat(client, "[{olive}VOTE{default}]投票更换三方图已禁用");
                }
                else if (VotensMap2E_D == true)
                {
                    FakeClientCommand(client, "votesmaps2menu");
                }
            }
            case 2: // 强制删除游戏大厅
            {
                if (g_bVotenForceDelLobby == false)
                {
                    FakeClientCommand(client, "sm_votes_more");
                    CPrintToChat(client, "[{olive}VOTE{default}]强制删除游戏大厅已禁用");
                }
                else
                {
                    FakeClientCommand(client, "votesforcedellobby");
                }
            }
            case 3: // 返回主菜单
            {
                FakeClientCommand(client, "sm_votes");
            }
            case 4: // 退出
            {
                ClientVoteMenu[client] = false;
                openreadyuphud(client);
            }
        }
    }
    else if (action == MenuAction_Cancel)
    {
        ClientVoteMenu[client] = false;
        openreadyuphud(client);
    }
    else if (action == MenuAction_End)
    {
        openreadyuphud(client);
        delete menu;
    }
    return 0;
}
public Action Command_VoteHp(int client, int args)
{
	if (g_bEnable == true
		&& VotensHpE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		if (CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起了一个投票: {blue}全体回血{default}, 只有游戏中的玩家才能参与投票", client);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					closereadyuphud(i);
					ClientVoteMenu[i] = true;
				}
			}

			g_voteType = view_as<voteType>(hp);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) 发起了一个投票: 全体回血!", client, SteamId);	//記錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "是否全体回血?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "同意");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "不同意");

			SetMenuExitButton(g_hVoteMenu, false);
			DisplayVoteMenuToNotSpec(g_hVoteMenu, 20);

			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					EmitSoundToClient(i, "ui/beep_synthtone01.wav");
				}
			}
		}
		else
		{
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensHpE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票被禁止");
	}
	return Plugin_Handled;
}

public Action Command_Votesforcestartgame(int client, int args)
{
	if (g_bEnable == true && VotensForceStartGameE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		if (!g_enb)
		{
			PrintToChatAll("[{olive}VOTE{default}]游戏已开始!");
			return Plugin_Handled;
		}
		if (CanStartVotes(client))
		{
			fsgclient = client;
			CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起了一个投票: {blue}强制开始游戏{default}, 只有游戏中的玩家才能参与投票", client);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					closereadyuphud(i);
					ClientVoteMenu[i] = true;
				}
			}

			g_voteType = view_as<voteType>(forcestartgame);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) 发起了一个投票: 强制开始游戏!", client, SteamId);	//記錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "是否强制开始游戏?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "同意");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "不同意");

			SetMenuExitButton(g_hVoteMenu, false);
			DisplayVoteMenuToNotSpec(g_hVoteMenu, 20);

			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					EmitSoundToClient(i, "ui/beep_synthtone01.wav");
				}
			}
		}
		else
		{
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensHpE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票被禁止");
	}
	return Plugin_Handled;
}

public Action Command_Votesforcedellobby(int client, int args)
{
	if (g_bEnable == true
		&& g_bVotenForceDelLobby == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		if (CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}VOTE{default}]{olive}%N{default}发起了一个投票: {blue}删除匹配大厅 {default}删除大厅用来解决卡大厅问题或者关闭匹配.请慎重投票!", client);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					closereadyuphud(client);
					ClientVoteMenu[i] = true;
				}
			}

			g_voteType = view_as<voteType>(forcedellobby);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) 发起了一个投票: 删除匹配大厅!", client, SteamId);	//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "是否删除匹配大厅?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "否");

			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);

			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensAlltalkE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票被禁止");
	}
	return Plugin_Handled;
}

public Action Command_VoteAlltalk(int client, int args)
{
	if (g_bEnable == true
		&& VotensAlltalkE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		if (CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}VOTE{default}]{olive}%N{default}发起了一个投票: {blue}开启全体语音", client);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					closereadyuphud(i);
					ClientVoteMenu[i] = true;
				}
			}

			g_voteType = view_as<voteType>(alltalk);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) 发起了一个投票: 开启全体语音!", client, SteamId);	//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "是否开启全体语音?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "否");

			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);

			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensAlltalkE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票被禁止");
	}
	return Plugin_Handled;
}

public Action Command_VoteAlltalk2(int client, int args)
{
	if (g_bEnable == true
		&& VotensAlltalkE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}

		if (CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起投票: {blue}关闭全体语音", client);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					closereadyuphud(i);
					ClientVoteMenu[i] = true;
				}
			}

			g_voteType = view_as<voteType>(alltalk2);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) 发起了一个投票: 关闭全体语音!", client, SteamId);	//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "是否关闭全体语音?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "否");

			SetMenuExitButton(g_hVoteMenu, false);
			VoteMenuToAll(g_hVoteMenu, 20);

			EmitSoundToAll("ui/beep_synthtone01.wav");
		}
		else
		{
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensAlltalkE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票被禁止");
	}
	return Plugin_Handled;
}

public Action Command_VoteRestartmap(int client, int args)
{
	if (g_bEnable == true
		&& VotensRestartmapE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		if (CanStartVotes(client))
		{
			CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起了一个投票: {blue}重置当前地图 {default}, 只有游戏中的玩家才能参与投票", client);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					closereadyuphud(i);
					ClientVoteMenu[i] = true;
				}
			}

			g_voteType = view_as<voteType>(restartmap);
			char SteamId[35];
			GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
			LogMessage("%N(%s) 发起了一个投票: 重置当前地图!", client, SteamId);	//紀錄在log文件
			g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
			SetMenuTitle(g_hVoteMenu, "是否重置当前地图?");
			AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
			AddMenuItem(g_hVoteMenu, VOTE_NO, "否");

			SetMenuExitButton(g_hVoteMenu, false);
			DisplayVoteMenuToNotSpec(g_hVoteMenu, 20);

			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
				{
					EmitSoundToClient(i, "ui/beep_synthtone01.wav");
				}
			}
		}
		else
		{
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensRestartmapE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]投票被禁止");
	}
	return Plugin_Handled;
}

public Action Command_VotesKick(int client, int args)
{
	if (client == 0) return Plugin_Handled;
	if (g_bEnable == true && g_bVotensKickED == true)
	{
		CreateVoteKickMenu(client);
	}
	else if (g_bEnable == false || g_bVotensKickED == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]已禁止踢出玩家");
	}
	return Plugin_Handled;
}

void CreateVoteKickMenu(int client)
{
	int	   team = GetClientTeam(client);
	Handle menu = CreateMenu(Menu_VotesKick);
	char   name[MAX_NAME_LENGTH];
	char   playerid[32];
	SetMenuTitle(menu, "请选择你要踢出的玩家");
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && (GetClientTeam(i) == team || GetClientTeam(i) == 1))
		{
			Format(playerid, sizeof(playerid), "%i", GetClientUserId(i));
			if (GetClientName(i, name, sizeof(name)))
			{
				AddMenuItem(menu, playerid, name);
			}
		}
	}
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME);
}

public int Menu_VotesKick(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32], name[32];
		GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
		int player = StringToInt(info);
		player	   = GetClientOfUserId(player);
		if (player && IsClientInGame(player))
		{
			if (player == param1)
			{
				CPrintToChatAll("[{olive}VOTE{default}]你确定要踢你自己吗?请重新选择");
				CreateVoteKickMenu(param1);
				return 0;
			}

			if (HasAccess(player, g_sKickImmueAccesslvl))
			{
				CPrintToChat(param1, "[{olive}VOTE{default}]该玩家无法被踢出，请重新选择你想踢出的玩家!");
				CPrintToChat(player, "[{olive}VOTE{default}]{olive}%N{default}尝试投票将你踢出, 但你拥有权限无法踢出", param1);
				CreateVoteKickMenu(param1);
			}
			else
			{
				kickplayer_userid = GetClientUserId(player);
				kickplayer_name	  = name;
				GetClientAuthId(player, AuthId_Steam2, kickplayer_SteamId, sizeof(kickplayer_SteamId));
				DisplayVoteKickMenu(param1);
			}
		}
		else
		{
			CPrintToChatAll("[{olive}VOTE{default}]该玩家已不在游戏中, 请重新选择!");
			CreateVoteKickMenu(param1);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			FakeClientCommand(param1, "votes");
		}
		else
			ClientVoteMenu[param1] = false;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DisplayVoteKickMenu(int client)
{
	if (!TestVoteDelay(client))
	{
		return;
	}

	if (CanStartVotes(client))
	{
		char SteamId[35];
		GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
		LogMessage("%N(%s) 发起投票: 踢出 %s(%s)", client, SteamId, kickplayer_name, kickplayer_SteamId);	 //紀錄在log文件
		int iTeam = GetClientTeam(client);
		CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起投票: {blue}踢出 %s {default}, 只有投票发起者的阵营才能参与投票", client, kickplayer_name);
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == iTeam)
			{
				closereadyuphud(i);
				ClientVoteMenu[i] = true;
			}

		g_voteType	= view_as<voteType>(kick);

		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
		SetMenuTitle(g_hVoteMenu, "是否踢出 %s ?", kickplayer_name);
		AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
		AddMenuItem(g_hVoteMenu, VOTE_NO, "否");
		SetMenuExitButton(g_hVoteMenu, false);
		DisplayVoteMenuToTeam(g_hVoteMenu, 20, iTeam);

		for (int i = 1; i <= MaxClients; i++)
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == iTeam)
				EmitSoundToClient(i, "ui/beep_synthtone01.wav");
	}
	else
	{
		return;
	}
}

public Action Command_VotemapsMenu(int client, int args)
{
	if (g_bEnable == true && VotensMapE_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		Handle menu = CreateMenu(MapMenuHandler);

		SetMenuTitle(menu, "请选择你要更换地图");
		if (game_l4d2)
		{
			AddMenuItem(menu, "c1m1_hotel", "死亡中心 C1");
			AddMenuItem(menu, "c2m1_highway", "黑色嘉年华 C2");
			AddMenuItem(menu, "c3m1_plankcountry", "沼泽激战 C3");
			AddMenuItem(menu, "c4m1_milltown_a", "暴风骤雨 C4");
			AddMenuItem(menu, "c5m1_waterfront", "教区 C5");
			AddMenuItem(menu, "c6m1_riverbank", "短暂时刻 C6");
			AddMenuItem(menu, "c7m1_docks", "牺牲 C7");
			AddMenuItem(menu, "c8m1_apartment", "毫不留情 C8");
			AddMenuItem(menu, "c9m1_alleys", "坠机险途 C9");
			AddMenuItem(menu, "c10m1_caves", "死亡丧钟 C10");
			AddMenuItem(menu, "c11m1_greenhouse", "寂静时分 C11");
			AddMenuItem(menu, "c12m1_hilltop", "血腥收获 C12");
			AddMenuItem(menu, "c13m1_alpinecreek", "刺骨寒溪 C13");
			AddMenuItem(menu, "c14m1_junkyard", "背水一战 C14");
		}
		else
		{
			AddMenuItem(menu, "l4d_vs_hospital01_apartment", "毫不留情 No Mercy");
			AddMenuItem(menu, "l4d_garage01_alleys", "坠机险途 Crash Course");
			AddMenuItem(menu, "l4d_vs_smalltown01_caves", "死亡丧钟 Death Toll");
			AddMenuItem(menu, "l4d_vs_airport01_greenhouse", "寂静时分 Dead Air");
			AddMenuItem(menu, "l4d_vs_farm01_hilltop", "血腥收获 Bloody Harvest");
			AddMenuItem(menu, "l4d_river01_docks", "牺牲 The Sacrifice");
		}
		SetMenuExitBackButton(menu, true);
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME);

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensMapE_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]官图投票已禁止,请使用自带投票");
	}
	return Plugin_Handled;
}

public Action Command_Votemaps2Menu(int client, int args)
{
	if (g_bEnable == true && VotensMap2E_D == true)
	{
		if (!TestVoteDelay(client))
		{
			return Plugin_Handled;
		}
		Handle menu = CreateMenu(MapMenuHandler);

		SetMenuTitle(menu, "▲ 选择三方图 <%d map%s>", g_iCount, ((g_iCount > 1) ? "s" : ""));
		for (int i = 0; i < g_iCount; i++)
		{
			AddMenuItem(menu, g_sMapinfo[i], g_sMapname[i]);
		}

		SetMenuExitBackButton(menu, true);
		SetMenuExitButton(menu, true);
		DisplayMenu(menu, client, MENU_TIME);

		return Plugin_Handled;
	}
	else if (g_bEnable == false || VotensMap2E_D == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]三方图投票已禁止,请使用自带投票");
	}
	return Plugin_Handled;
}

public int MapMenuHandler(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char info[32], name[64];
		GetMenuItem(menu, itemNum, info, sizeof(info), _, name, sizeof(name));
		votesmaps	  = info;
		votesmapsname = name;
		DisplayVoteMapsMenu(client);
	}
	else if (action == MenuAction_Cancel)
	{
		if (itemNum == MenuCancel_ExitBack)
		{
			FakeClientCommand(client, "votes");
		}
		else
			ClientVoteMenu[client] = false;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DisplayVoteMapsMenu(int client)
{
	if (!TestVoteDelay(client))
	{
		return;
	}
	if (CanStartVotes(client))
	{
		char SteamId[35];
		GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
		LogMessage("%N(%s) 发起投票: 更换地图 %s", client, SteamId, votesmapsname);	   //紀錄在log文件
		CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起投票: {blue}更换地图%s{default}, 只有游戏中的玩家才能参与投票", client, votesmapsname);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
			{
				closereadyuphud(i);
				ClientVoteMenu[i] = true;
			}
		}

		g_voteType	= view_as<voteType>(map);

		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
		SetMenuTitle(g_hVoteMenu, "是否更换地图: %s", votesmapsname);
		AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
		AddMenuItem(g_hVoteMenu, VOTE_NO, "否");
		SetMenuExitButton(g_hVoteMenu, false);
		DisplayVoteMenuToNotSpec(g_hVoteMenu, 20);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
			{
				{
					EmitSoundToClient(i, "ui/beep_synthtone01.wav");
				}
			}
		}
	}
	else
	{
		return;
	}
}

public Action Command_Votesforcespectate(int client, int args)
{
	if (client == 0) return Plugin_Handled;
	if (g_bEnable == true && g_bVotensForceSpectateED == true)
	{
		CreateVoteforcespectateMenu(client);
	}
	else if (g_bEnable == false || g_bVotensForceSpectateED == false)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]强制玩家旁观已被禁止");
	}
	return Plugin_Handled;
}

void CreateVoteforcespectateMenu(int client)
{
	Handle menu = CreateMenu(Menu_Votesforcespectate);
	int	   team = GetClientTeam(client);
	char   name[MAX_NAME_LENGTH];
	char   playerid[32];
	SetMenuTitle(menu, "请选择你要强制旁观的玩家");
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
		{
			Format(playerid, sizeof(playerid), "%d", i);
			if (GetClientName(i, name, sizeof(name)))
			{
				AddMenuItem(menu, playerid, name);
			}
		}
	}
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME);
}

public int Menu_Votesforcespectate(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32], name[32];
		GetMenuItem(menu, param2, info, sizeof(info), _, name, sizeof(name));
		forcespectateid			= StringToInt(info);
		forcespectateid			= GetClientUserId(forcespectateid);
		forcespectateplayername = name;

		DisplayVoteforcespectateMenu(param1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			FakeClientCommand(param1, "votes");
		}
		else
			ClientVoteMenu[param1] = false;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DisplayVoteforcespectateMenu(int client)
{
	if (!TestVoteDelay(client))
	{
		return;
	}

	if (CanStartVotes(client))
	{
		char SteamId[35];
		GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
		LogMessage("%N(%s) 发起投票: 强制玩家 %s 旁观", client, SteamId, forcespectateplayername);	  //紀錄在log文件

		int iTeam = GetClientTeam(client);
		CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起投票: {blue}强制玩家%s旁观{default}, 只有投票发起者的阵营才能参与投票", client, forcespectateplayername);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && GetClientTeam(i) == iTeam)
			{
				ClientVoteMenu[i] = true;
				closereadyuphud(i);
			}
		}
		g_voteType	= view_as<voteType>(forcespectate);

		g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
		SetMenuTitle(g_hVoteMenu, "是否强制%s旁观?", forcespectateplayername);
		AddMenuItem(g_hVoteMenu, VOTE_YES, "是");
		AddMenuItem(g_hVoteMenu, VOTE_NO, "否");
		SetMenuExitButton(g_hVoteMenu, false);
		DisplayVoteMenuToTeam(g_hVoteMenu, 20, iTeam);

		for (int i = 1; i <= MaxClients; i++)
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == iTeam)
				EmitSoundToClient(i, "ui/beep_synthtone01.wav");
	}
	else
	{
		return;
	}
}
public Action Command_VoteHunterPitchLock(int client, int args)
{
    if (g_bEnable == true && VotensHunterPitchLockE_D == true && g_bHunterPluginLoaded)
    {
        if (!TestVoteDelay(client))
        {
            return Plugin_Handled;
        }
        if (CanStartVotes(client))
        {
            bool currentState = IsHunterPitchLockEnabled();
            char voteText[64];
            Format(voteText, sizeof(voteText), "%s Hunter简易天花板", currentState ? "关闭" : "开启");
            
            CPrintToChatAll("[{olive}VOTE{default}]{olive} %N {default}发起了一个投票: {blue}%s{default}, 只有游戏中的玩家才能参与投票", client, voteText);
            
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
                {
                    closereadyuphud(i);
                    ClientVoteMenu[i] = true;
                }
            }

            g_voteType = view_as<voteType>(hunterpitchlock);
            char SteamId[35];
            GetClientAuthId(client, AuthId_Steam2, SteamId, sizeof(SteamId));
            LogMessage("%N(%s) 发起了一个投票: %s!", client, SteamId, voteText);
            
            g_hVoteMenu = CreateMenu(Handler_VoteCallback, MENU_ACTIONS_ALL);
            SetMenuTitle(g_hVoteMenu, "是否%s?", voteText);
            AddMenuItem(g_hVoteMenu, VOTE_YES, "同意");
            AddMenuItem(g_hVoteMenu, VOTE_NO, "不同意");

            SetMenuExitButton(g_hVoteMenu, false);
            DisplayVoteMenuToNotSpec(g_hVoteMenu, 20);

            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1)
                {
                    EmitSoundToClient(i, "ui/beep_synthtone01.wav");
                }
            }
        }
        else
        {
            return Plugin_Handled;
        }
        return Plugin_Handled;
    }
    else
    {
        CPrintToChat(client, "[{olive}VOTE{default}]Hunter简易天花板投票被禁止或插件未加载");
    }
    return Plugin_Handled;
}

stock bool DisplayVoteMenuToTeam(Handle hMenu, int iTime, int iTeam)
{
	int iTotal	   = 0;
	int[] iPlayers = new int[MaxClients];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != iTeam)
		{
			continue;
		}

		iPlayers[iTotal++] = i;
	}

	return VoteMenu(hMenu, iPlayers, iTotal, iTime, 0);
}

stock bool DisplayVoteMenuToNotSpec(Handle hMenu, int iTime)
{
	int iTotal	   = 0;
	int[] iPlayers = new int[MaxClients];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == 1)
		{
			continue;
		}

		iPlayers[iTotal++] = i;
	}

	return VoteMenu(hMenu, iPlayers, iTotal, iTime, 0);
}

public int Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
	//==========================
	if (action == MenuAction_Select)
	{
		switch (param2)
		{
			case 0:
			{
				Votey += 1;
				CPrintToChatAll("[{olive}VOTE{default}] %N {blue}同意了该投票{default}.", param1);
			}
			case 1:
			{
				Voten += 1;
				CPrintToChatAll("[{olive}VOTE{default}] %N {blue}拒绝了该投票{default}.", param1);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (param1 > 0 && param1 <= MaxClients && IsClientConnected(param1) && IsClientInGame(param1) && !IsFakeClient(param1))
		{
			Voten += 1;
			CPrintToChatAll("[{olive}VOTE{default}] %N {blue}放弃了该投票{default}.", param1);
		}
	}
	//==========================
	char  item[64], display[64];
	float percent;
	int	  votes, totalVotes;

	GetMenuVoteInfo(param2, votes, totalVotes);
	GetMenuItem(menu, param1, item, sizeof(item), _, display, sizeof(display));

	if (strcmp(item, VOTE_NO) == 0 && param1 == 1)
	{
		votes = totalVotes - votes;
	}
	percent = GetVotePercent(votes, totalVotes);

	CheckVotes();
	if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		CPrintToChatAll("[{olive}VOTE{default}]没有投票");
		g_votedelay = ivotedelay_time;
		EmitSoundToAll("ui/beep_error01.wav");
		CreateTimer(2.0, VoteEndDelay);
		CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (action == MenuAction_VoteEnd)
	{
		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent, g_fLimit) < 0 && param1 == 0) || (strcmp(item, VOTE_NO) == 0 && param1 == 1))
		{
			g_votedelay = ivotedelay_time;
			CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			EmitSoundToAll("ui/beep_error01.wav");
			CPrintToChatAll("[{olive}VOTE{default}]{lightgreen}投票未通过 {default}至少需要{green}%d%%{default}的玩家同意。(同意： {green}%d%%{default}, 投票人数： {green}%i {default})", RoundToNearest(100.0 * g_fLimit), RoundToNearest(100.0 * percent), totalVotes);
			CreateTimer(2.0, VoteEndDelay);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					openreadyuphud(i);
				}
			}
		}
		else
		{
			g_votedelay = ivotedelay_time;
			CreateTimer(1.0, Timer_VoteDelay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
			EmitSoundToAll("ui/menu_enter05.wav");
			CPrintToChatAll("[{olive}VOTE{default}]{lightgreen}投票通过 {default}(同意：{green}%d%%{default}, 投票人数：{green}%i{default})", RoundToNearest(100.0 * percent), totalVotes);
			CreateTimer(2.0, VoteEndDelay);
			CreateTimer(3.0, COLD_DOWN, _);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					openreadyuphud(i);
				}
			}
		}
	}
	else if (action == MenuAction_End)
	{
		VoteMenuClose();
		// delete menu;
	}

	return 0;
}

public Action Timer_forcespectate(Handle timer, any client)
{
	static bool bClientJoinedTeam = false;	  // did the client try to join the infected?

	if (!IsClientInGame(client) || IsFakeClient(client)) return Plugin_Stop;	// if client disconnected or is fake client

	if (g_iSpectatePenaltyCounter[client] != 0)
	{
		if ((GetClientTeam(client) == 3 || GetClientTeam(client) == 2))
		{
			ChangeClientTeam(client, 1);
			CPrintToChat(client, "[{olive}VOTE{default}] 你已被投票强制旁观! 等待 {green}%d {default}秒后重新回到游戏.", g_iSpectatePenaltyCounter[client]);
			bClientJoinedTeam = true;	 // client tried to join the infected again when not allowed
		}
		else if (GetClientTeam(client) == 1 && IsClientIdle(client))
		{
			L4D_TakeOverBot(client);
			ChangeClientTeam(client, 1);
			CPrintToChat(client, "[{olive}VOTE{default}] 你已被投票强制旁观! 等待 {green}%d {default}秒后重新回到游戏.", g_iSpectatePenaltyCounter[client]);
			bClientJoinedTeam = true;	 // client tried to join the infected again when not allowed
		}
		g_iSpectatePenaltyCounter[client]--;
		return Plugin_Continue;
	}
	else if (g_iSpectatePenaltyCounter[client] == 0)
	{
		if (GetClientTeam(client) == 3 || GetClientTeam(client) == 2)
		{
			ChangeClientTeam(client, 1);
			bClientJoinedTeam = true;
		}
		if (GetClientTeam(client) == 1 && bClientJoinedTeam)
		{
			CPrintToChat(client, "[{olive}VOTE{default}]你现在可以按M回到队伍了");	  // only print this hint text to the spectator if he tried to join the infected team, and got swapped before
		}
		bClientJoinedTeam				  = false;
		g_iSpectatePenaltyCounter[client] = iforcespectate_penalty;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

//====================================================
public void AnyHp()
{
	// CPrintToChatAll("[{olive}TS{default}] All players{blue}");
	int flags = GetCommandFlags("give");
	SetCommandFlags("give", flags & ~FCVAR_CHEAT);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			FakeClientCommand(i, "give health");
			SetEntityHealth(i, MaxHealth);
		}
	}
	SetCommandFlags("give", flags | FCVAR_CHEAT);
}

public void CheatCommandEx(int client)
{
	int bits = GetUserFlagBits(client);
	// int flags = GetCommandFlags("sm_fs");
	SetUserFlagBits(client, ADMFLAG_ROOT);
	// SetCommandFlags("sm_fs", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "sm_fs");
	SetUserFlagBits(client, bits);
	// SetCommandFlags("sm_fm", flags);
}	 // https://github.com/umlka/l4d2/blob/main/l4d2_points_system/l4d2_points_system.sp#L3153

//================================
void CheckVotes()
{
	PrintHintTextToAll("同意的玩家: %i\n不同意的玩家: %i", Votey, Voten);
}

public Action VoteEndDelay(Handle timer)
{
	Votey = 0;
	Voten = 0;
	for (int i = 1; i <= MaxClients; i++)
		ClientVoteMenu[i] = false;

	return Plugin_Continue;
}

public Action Changelevel_Map(Handle timer)
{
	ServerCommand("changelevel %s", votesmaps);

	return Plugin_Continue;
}
//===============================
void VoteMenuClose()
{
	Votey = 0;
	Voten = 0;
	CloseHandle(g_hVoteMenu);
	g_hVoteMenu = INVALID_HANDLE;
}
float GetVotePercent(int votes, int totalVotes)
{
	return (float(votes) / float(totalVotes));
}
bool TestVoteDelay(int client)
{
	int delay = CheckVoteDelay();

	if (delay > 0)
	{
		if (delay > 60)
		{
			CPrintToChat(client, "[{olive}VOTE{default}]你必须等待{red}%i{default}秒后再发起投票!", delay % 60);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					openreadyuphud(i);
				}
			}
		}
		else
		{
			CPrintToChat(client, "[{olive}VOTE{default}]你必须等待{red}%i{default}秒后再发起投票!", delay);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
				{
					openreadyuphud(i);
				}
			}
		}
		return false;
	}

	delay = GetVoteDelay();
	if (delay > 0)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]你必须等待{red}%i{default}秒后再发起投票!", delay);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
			{
				openreadyuphud(i);
			}
		}
		return false;
	}
	return true;
}

bool CanStartVotes(int client)
{
	if (g_hVoteMenu != INVALID_HANDLE || IsVoteInProgress())
	{
		CPrintToChat(client, "[{olive}VOTE{default}]已经有了一个投票正在进行中");
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
			{
				openreadyuphud(i);
			}
		}
		return false;
	}
	int iNumPlayers;
	// list of players
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || !IsClientConnected(i))
		{
			continue;
		}
		iNumPlayers++;
	}
	if (iNumPlayers < g_iCvarPlayerLimit)
	{
		CPrintToChat(client, "[{olive}VOTE{default}]无法发起投票。需要{red}%d{default}个玩家", g_iCvarPlayerLimit);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i))
			{
				openreadyuphud(i);
			}
		}
		return false;
	}
	return true;
}
//=======================================
public void OnClientDisconnect(int client)
{
	if (IsClientInGame(client) && IsFakeClient(client)) return;

	float currenttime = GetGameTime();

	if (lastDisconnectTime == currenttime) return;

	CreateTimer(SCORE_DELAY_EMPTY_SERVER, IsNobodyConnected, currenttime);
	lastDisconnectTime = currenttime;
}

public Action IsNobodyConnected(Handle timer, any timerDisconnectTime)
{
	if (timerDisconnectTime != lastDisconnectTime) return Plugin_Stop;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && !IsFakeClient(i))
			return Plugin_Stop;
	}

	return Plugin_Stop;
}

public Action COLD_DOWN(Handle timer, any client)
{
	switch (g_voteType)
	{
		case (view_as<voteType>(hp)):
		{
			AnyHp();
			LogMessage("全体回血通过");
		}
		case (view_as<voteType>(alltalk)):
		{
			ServerCommand("sv_alltalk 1");
			LogMessage("开启全体语音通过");
		}
		case (view_as<voteType>(alltalk2)):
		{
			ServerCommand("sv_alltalk 0");
			LogMessage("关闭全体语音通过");
		}
		case (view_as<voteType>(restartmap)):
		{
			ServerCommand("sm_restartmap");
			LogMessage("重置地图通过");
		}
		case (view_as<voteType>(map)):
		{
			CreateTimer(5.0, Changelevel_Map);
			CPrintToChatAll("[{olive}VOTE{default}]{green}5{default}秒后将切换地图为{blue}%s", votesmapsname);
			LogMessage("更换地图 %s %s 通过", votesmaps, votesmapsname);
		}
		case (view_as<voteType>(kick)):
		{
			CPrintToChatAll("[{olive}VOTE{default}]%s 已被投票踢出!", kickplayer_name);
			LogMessage("投票踢出玩家%s通过", kickplayer_name);

			int player = GetClientOfUserId(kickplayer_userid);
			if (player && IsClientInGame(player)) KickClient(player, "你已被投票踢出");
			ServerCommand("sm_addban 5 \"%s\" \"你已被投票踢出\" ", kickplayer_SteamId);
		}
		case (view_as<voteType>(forcespectate)):
		{
			forcespectateid = GetClientOfUserId(forcespectateid);
			if (HasAccess(forcespectateid, g_sKickImmueAccesslvl))
			{
				CPrintToChatAll("[{olive}VOTE{default}]玩家%s因拥有权限而无法强制旁观!", forcespectateplayername);
				LogMessage("玩家%s因拥有权限而无法强制旁观", forcespectateplayername);
				return Plugin_Handled;
			}
			if (forcespectateid && IsClientInGame(forcespectateid))
			{
				CPrintToChatAll("[{olive}VOTE{default}]玩家{blue}%s{default}已被强制旁观!", forcespectateplayername);
				ChangeClientTeam(forcespectateid, 1);
				LogMessage("玩家%s已经被强制旁观", forcespectateplayername);
				CreateTimer(1.0, Timer_forcespectate, forcespectateid, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);	   // Start unpause countdown
			}
			else
			{
				CPrintToChatAll("[{olive}VOTE{default}]无法找到玩家%s", forcespectateplayername);
			}
		}
		case (view_as<voteType>(forcedellobby)):
		{
			L4D_LobbyUnreserve();
			LogMessage("删除匹配大厅通过");
		}
		case (view_as<voteType>(forcestartgame)):
		{
			if (!g_enb)
			{
				CPrintToChatAll("[{olive}VOTE{default}]注意是给投票发起玩家临时提升权限来强制开始游戏!但他不一定是管理员哦.");
				CheatCommandEx(fsgclient);
				LogMessage("强制开始游戏通过");
			}
			else {
				CPrintToChatAll("[{olive}VOTE{default}]对局已开始!无需强制启动游戏!");
			}
		}
		case (view_as<voteType>(hunterpitchlock)):
		{
			if (g_bHunterPluginLoaded)
			{
				bool currentState = IsHunterPitchLockEnabled();
				SetHunterPitchLockEnabled(!currentState);
				CPrintToChatAll("[{olive}VOTE{yellow}]Hunter简易天花板已%s", !currentState ? "开启" : "关闭");
				LogMessage("Hunter简易天花板投票通过: %s", !currentState ? "开启" : "关闭");
			}
			else
			{
				CPrintToChatAll("[{olive}VOTE{default}]Hunter插件未加载，无法执行操作");
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_VoteDelay(Handle timer, any client)
{
	g_votedelay--;
	if (g_votedelay <= 0)
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

int GetVoteDelay()
{
	return g_votedelay;
}

void ParseCampaigns()
{
	Handle g_kvCampaigns = CreateKeyValues("VoteCustomCampaigns");

	char   sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "data/VoteCustomCampaigns.txt");

	if (!FileToKeyValues(g_kvCampaigns, sPath))
	{
		SetFailState("<VCC> File not found: %s", sPath);
		CloseHandle(g_kvCampaigns);
		return;
	}

	if (!KvGotoFirstSubKey(g_kvCampaigns))
	{
		SetFailState("<VCC> File can't read: you dumb noob!");
		CloseHandle(g_kvCampaigns);
		return;
	}

	for (int i = 0; i < MAX_CAMPAIGN_LIMIT; i++)
	{
		KvGetString(g_kvCampaigns, "mapinfo", g_sMapinfo[i], sizeof(g_sMapinfo));
		KvGetString(g_kvCampaigns, "mapname", g_sMapname[i], sizeof(g_sMapname));

		if (!KvGotoNextKey(g_kvCampaigns))
		{
			g_iCount = ++i;
			break;
		}
	}
}

bool HasAccess(int client, char[] g_sAcclvl)
{
	// no permissions set
	if (strlen(g_sAcclvl) == 0)
		return true;

	else if (StrEqual(g_sAcclvl, "-1"))
		return false;

	// check permissions
	int iFlag = GetUserFlagBits(client);
	if (iFlag & ReadFlagString(g_sAcclvl) || iFlag & ADMFLAG_ROOT)
	{
		return true;
	}

	return false;
}

bool IsClientIdle(int client)
{
	if (GetClientTeam(client) != 1)
		return false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
		{
			if (HasEntProp(i, Prop_Send, "m_humanSpectatorUserID"))
			{
				if (GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID")) == client)
					return true;
			}
		}
	}
	return false;
}

void openreadyuphud(int client)
{
	if (g_enb) FakeClientCommand(client, "sm_show");
}

void closereadyuphud(int client)
{
	if (g_enb) FakeClientCommand(client, "sm_hide");
}