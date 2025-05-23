#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <chat-processor> // 聊天处理器头文件，确保它在你的 include 文件夹中

// 备用定义，以防 chat-processor.inc 未定义这些常量
// 理想情况下，这些应该由 chat-processor.inc 提供
#if !defined MAX_NAME_LENGTH
    #define MAX_NAME_LENGTH         128 // 名称的最大字节长度
#endif
#if !defined MAX_MESSAGE_LENGTH
    #define MAX_MESSAGE_LENGTH      256 // 聊天消息的最大字节长度
#endif

#define PLUGIN_VERSION "1.1.1-zh" // 版本号更新
#define MAX_TAG_LENGTH 32         // 标签最大长度（字节）

public Plugin myinfo = {
    name = "L4D2 自定义聊天标签", // 插件名称
    author = "Gemini Pro (基于 HexTags 概念)", // 作者
    description = "允许 L4D2 玩家设置带颜色的自定义聊天标签。", // 插件描述
    version = PLUGIN_VERSION, // 插件版本
    url = "N/A" // 相关链接
};

// --- 全局变量 ---
ConVar g_cv_bPluginEnabled;      // 控制插件是否启用的控制台变量
ConVar g_cv_iMaxTagLength;       // 控制标签最大长度的控制台变量
ConVar g_cv_sTagFormat;          // 控制聊天中标签和名称格式的控制台变量
// 新增的颜色控制台变量
ConVar g_cv_sTagColor;           // 标签文本本身的颜色
ConVar g_cv_sNameColor;          // 玩家名称的颜色
ConVar g_cv_sChatTextColor;      // 玩家聊天消息的颜色

Handle g_hCookiePlayerTag;                    // 存储玩家标签的 Cookie 句柄
char g_sPlayerTags[MAXPLAYERS + 1][MAX_TAG_LENGTH]; // 存储每个玩家标签的数组

// --- 插件核心函数 ---

public void OnPluginStart() {
    // 创建版本号控制台变量
    CreateConVar("sm_l4d2_customtags_version_zh", PLUGIN_VERSION, "L4D2 自定义聊天标签插件版本。", FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_REPLICATED);

    // 创建功能开关控制台变量
    g_cv_bPluginEnabled = CreateConVar("sm_l4d2_customtags_enabled", "1", "启用/禁用自定义聊天标签插件。0 = 禁用, 1 = 启用。", FCVAR_NONE, true, 0.0, true, 1.0);
    // 创建标签最大长度控制台变量
    g_cv_iMaxTagLength = CreateConVar("sm_l4d2_customtags_maxlen", "15", "自定义标签的最大长度 (不包括颜色代码，按英文字符计)。", FCVAR_NONE, true, 3.0, true, float(MAX_TAG_LENGTH - 1));
    // 创建聊天格式控制台变量
    g_cv_sTagFormat = CreateConVar("sm_l4d2_customtags_format", "[{tag}] {name}", "聊天格式。{tag} 是玩家的标签, {name} 是玩家的名称。", FCVAR_NONE);

    // 创建新的颜色控制台变量
    g_cv_sTagColor = CreateConVar("sm_l4d2_customtags_tag_color", "{green}", "聊天标签文本的默认颜色。使用 SourceMod 颜色代码 (例如: {green}, {teamcolor}, {default})。");
    g_cv_sNameColor = CreateConVar("sm_l4d2_customtags_name_color", "{teamcolor}", "玩家名称的默认颜色。使用 SourceMod 颜色代码。");
    g_cv_sChatTextColor = CreateConVar("sm_l4d2_customtags_chat_color", "{default}", "玩家聊天消息文本的默认颜色。使用 SourceMod 颜色代码。");

    // 注册玩家命令
    RegConsoleCmd("sm_settag", Cmd_SetTag, "设置您的自定义聊天标签。用法: sm_settag <你的标签内容>");
    RegConsoleCmd("sm_tag", Cmd_SetTag, "sm_settag 的别名。用法: sm_tag <你的标签内容>"); // 别名命令
    RegConsoleCmd("sm_removetag", Cmd_RemoveTag, "移除您的自定义聊天标签。");

    // 注册客户端 Cookie 用于保存标签
    g_hCookiePlayerTag = RegClientCookie("l4d2_custom_tag_zh", "玩家的自定义聊天标签", CookieAccess_Private); // Cookie 名称稍作区分
    // 自动加载或生成配置文件
    AutoExecConfig(true, "l4d2_customtags_zh"); // 配置文件名也稍作区分

    // 为已在游戏中的玩家加载 Cookie 数据
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && AreClientCookiesCached(i)) {
            OnClientCookiesCached(i);
        }
    }
}

// 当玩家进入服务器时调用
public void OnClientPutInServer(int client) {
    g_sPlayerTags[client][0] = '\0'; // 初始化玩家标签为空
    if (AreClientCookiesCached(client)) {
        LoadPlayerTagFromCookie(client); // 如果 Cookie 已缓存，则加载
    }
}

// 当玩家离开服务器时调用
public void OnClientDisconnect(int client) {
    g_sPlayerTags[client][0] = '\0'; // 清除玩家标签信息
}

// 当客户端的 Cookie 被缓存后调用
public void OnClientCookiesCached(int client) {
    LoadPlayerTagFromCookie(client); // 加载玩家标签
}

// 从 Cookie 加载玩家标签的辅助函数
void LoadPlayerTagFromCookie(int client) {
    if (!IsClientConnected(client) || !AreClientCookiesCached(client)) {
        return; // 客户端未连接或 Cookie 未缓存则返回
    }
    char cookieValue[MAX_TAG_LENGTH];
    GetClientCookie(client, g_hCookiePlayerTag, cookieValue, sizeof(cookieValue));
    if (cookieValue[0] != '\0') {
        strcopy(g_sPlayerTags[client], sizeof(g_sPlayerTags[]), cookieValue); // 从 Cookie 复制标签
    } else {
        g_sPlayerTags[client][0] = '\0'; // Cookie 为空则标签也为空
    }
}

// "sm_settag" 命令的处理函数
public Action Cmd_SetTag(int client, int args) {
    if (!g_cv_bPluginEnabled.BoolValue) {
        ReplyToUser(client, "自定义标签功能当前已被服务器管理员禁用。");
        return Plugin_Handled;
    }
    if (args < 1) {
        ReplyToUser(client, "用法: sm_settag <你的标签内容>");
        return Plugin_Handled;
    }
    char sNewTagArg[MAX_TAG_LENGTH * 2]; // 允许用户输入包含颜色代码的更长字符串
    GetCmdArgString(sNewTagArg, sizeof(sNewTagArg)); // 获取命令参数
    TrimString(sNewTagArg); // 去除首尾空格

    // 去除颜色代码后检查长度，但存储时保留颜色代码
    char sTagNoColor[MAX_TAG_LENGTH];
    RemoveColorCodes(sNewTagArg, sTagNoColor, sizeof(sTagNoColor));

    int maxLen = g_cv_iMaxTagLength.IntValue;
    if (strlen(sTagNoColor) > maxLen) {
        ReplyToUser(client, "您的标签 (文本部分) 过长。最大长度为 %d 个英文字符。", maxLen);
        return Plugin_Handled;
    }
    // 如果去除颜色后为空，但原始输入不为空（意味着只有颜色代码），则允许
    // 但如果去除颜色后为空，且原始输入也为空，则提示
    if (strlen(sTagNoColor) == 0 && strlen(sNewTagArg) == 0) {
         ReplyToUser(client, "标签不能为空。如需移除标签，请使用 sm_removetag。");
        return Plugin_Handled;
    }


    strcopy(g_sPlayerTags[client], MAX_TAG_LENGTH, sNewTagArg); // 存储包含颜色代码的标签
    SetClientCookie(client, g_hCookiePlayerTag, g_sPlayerTags[client]); // 保存到 Cookie
    // 回复用户时，使用配置的标签颜色进行预览
    char sTagColorPreview[32];
    g_cv_sTagColor.GetString(sTagColorPreview, sizeof(sTagColorPreview));
    ReplyToUser(client, "您的聊天标签已设置为: %s%s{default}", sTagColorPreview, g_sPlayerTags[client]);
    return Plugin_Handled;
}

// "sm_removetag" 命令的处理函数
public Action Cmd_RemoveTag(int client, int args) {
    if (!g_cv_bPluginEnabled.BoolValue) {
        ReplyToUser(client, "自定义标签功能当前已被服务器管理员禁用。");
        return Plugin_Handled;
    }
    g_sPlayerTags[client][0] = '\0'; // 清空玩家标签
    SetClientCookie(client, g_hCookiePlayerTag, ""); // 清空 Cookie 中的标签
    ReplyToUser(client, "您的自定义聊天标签已被移除。");
    return Plugin_Handled;
}

// Chat-Processor 的 Hook 函数，用于处理聊天消息
public Action CP_OnChatMessage(int &author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool &processcolors, bool &removecolors) {
    if (!g_cv_bPluginEnabled.BoolValue || author == 0) { // 如果插件禁用或发送者无效
        return Plugin_Continue; // 继续正常处理
    }

    // --- 首先处理聊天消息本身的颜色 ---
    char sChatColor[32];
    g_cv_sChatTextColor.GetString(sChatColor, sizeof(sChatColor)); // 获取配置的聊天文本颜色

    // 如果配置了非默认颜色，则应用
    if (!StrEqual(sChatColor, "{default}", false) && sChatColor[0] != '\0') {
        char sTempMessage[MAX_MESSAGE_LENGTH]; // 使用 MAX_MESSAGE_LENGTH
        Format(sTempMessage, sizeof(sTempMessage), "%s%s{default}", sChatColor, message); // 添加颜色代码
        strcopy(message, MAX_MESSAGE_LENGTH, sTempMessage); // 更新消息内容
    }

    // --- 接着处理名称和标签 ---
    if (g_sPlayerTags[author][0] == '\0') { // 如果玩家没有自定义标签
        char sNameColor[32];
        g_cv_sNameColor.GetString(sNameColor, sizeof(sNameColor)); // 获取配置的名称颜色
        // 如果配置了非默认颜色，则为名称应用颜色
        if (!StrEqual(sNameColor, "{default}", false) && sNameColor[0] != '\0') {
            char sTempName[MAX_NAME_LENGTH]; // 使用 MAX_NAME_LENGTH
            Format(sTempName, sizeof(sTempName), "%s%s{default}", sNameColor, name); // 添加颜色代码
            strcopy(name, MAX_NAME_LENGTH, sTempName); // 更新名称显示
        }
    } else { // 如果玩家有自定义标签
        char sCurrentFormat[128]; // 这个大小通常足够容纳格式字符串本身
        g_cv_sTagFormat.GetString(sCurrentFormat, sizeof(sCurrentFormat)); // 获取当前的聊天格式

        char sTagColor[32];
        g_cv_sTagColor.GetString(sTagColor, sizeof(sTagColor)); // 获取配置的标签颜色

        char sNameColorConfig[32];
        g_cv_sNameColor.GetString(sNameColorConfig, sizeof(sNameColorConfig)); // 获取配置的名称颜色

        // 1. 准备带颜色的标签部分
        // 标签(g_sPlayerTags[author])最大MAX_TAG_LENGTH，颜色代码和格式本身占一些空间
        char sFormattedTag[MAX_TAG_LENGTH + 64]; 
        if (!StrEqual(sTagColor, "{default}", false) && sTagColor[0] != '\0') {
            Format(sFormattedTag, sizeof(sFormattedTag), "%s%s{default}", sTagColor, g_sPlayerTags[author]);
        } else {
            strcopy(sFormattedTag, sizeof(sFormattedTag), g_sPlayerTags[author]);
        }

        // 2. 准备带颜色的名称部分
        // 原始名称(name参数)最大MAX_NAME_LENGTH，颜色代码占一些空间
        char sFormattedName[MAX_NAME_LENGTH + 32]; 
        if (!StrEqual(sNameColorConfig, "{default}", false) && sNameColorConfig[0] != '\0') {
            Format(sFormattedName, sizeof(sFormattedName), "%s%s{default}", sNameColorConfig, name); // 'name' 是原始玩家名称
        } else {
            strcopy(sFormattedName, sizeof(sFormattedName), name); // 'name' 是原始玩家名称
        }

        // 3. 将处理过的标签和名称替换到格式字符串中
        // sCurrentFormat 的大小是128，替换后的总长度不应超过 MAX_NAME_LENGTH (因为最终结果要写入 name 参数)
        // 确保 sCurrentFormat 在替换后不会超出 MAX_NAME_LENGTH
        ReplaceString(sCurrentFormat, sizeof(sCurrentFormat), "{tag}", sFormattedTag, false);
        ReplaceString(sCurrentFormat, sizeof(sCurrentFormat), "{name}", sFormattedName, false);
        
        // 检查最终长度是否会溢出 name 参数 (MAX_NAME_LENGTH)
        if (strlen(sCurrentFormat) >= MAX_NAME_LENGTH) {
            // 如果可能溢出，进行截断或其他处理，这里简单截断
            sCurrentFormat[MAX_NAME_LENGTH - 1] = '\0';
        }
        strcopy(name, MAX_NAME_LENGTH, sCurrentFormat); // 'name' 变量是聊天处理器用于显示发送者名称的
    }

    processcolors = true; // 关键: 告诉聊天处理器解析颜色标签
    removecolors = false; // 我们是在添加颜色，不是移除

    return Plugin_Changed; // 我们修改了 'name' 和/或 'message'
}

// 辅助函数：向用户发送消息 (聊天或控制台)
void ReplyToUser(int client, const char[] format, any ...) {
    char buffer[256]; // 这个大小通常足够用于聊天回复
    VFormat(buffer, sizeof(buffer), format, 3); // 格式化消息
    if (client == 0) { // 如果 client 为 0，则为服务器控制台
        PrintToServer("[自定义标签] %s", buffer);
    } else {
        PrintToChat(client, " \x04[自定义标签]\x01 %s", buffer); // \x04 是绿色, \x01 是默认色
    }
}

// 辅助函数：移除字符串中的颜色代码（用于长度检查的简化版）
// 输入: input - 原始字符串
// 输出: output - 处理后的字符串
//      maxlen - output缓冲区的最大长度
void RemoveColorCodes(const char[] input, char[] output, int maxlen) {
    int i = 0, j = 0;
    while (input[i] != '\0' && j < maxlen - 1) {
        if (input[i] == '{') { // 遇到 '{'
            int k = i + 1;
            // 寻找对应的 '}'
            while (input[k] != '\0' && input[k] != '}') {
                k++;
            }
            if (input[k] == '}') { // 如果找到了 '}'
                i = k + 1; // 跳过整个颜色代码 {xxxx}
                continue;  // 继续下一次循环
            }
            // 如果没有找到匹配的 '}'，则将其视为普通字符
        }
        output[j++] = input[i++]; // 复制非颜色代码字符
    }
    output[j] = '\0'; // 添加字符串结束符
}